#requires -Version 5.1

param(
    [ValidateRange(1024, 65515)][int]$PreferredPort = 9349
)

$forward = @('-PreferredPort', [string]$PreferredPort)
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $legacy = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $legacy -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forward
    exit $LASTEXITCODE
}

. (Join-Path $PSScriptRoot 'Common.ps1')

$packageRoot = Get-QQPackageRoot
$injector = Join-Path $packageRoot 'src\injector.mjs'
$node = Resolve-QQNode
$readyFile = Join-Path $script:QQRuntimeRoot 'watcher-ready.json'
$verifyFile = Join-Path $script:QQRuntimeRoot 'verify.json'
$domInspectFile = Join-Path $script:QQRuntimeRoot 'dom-before-theme.json'
$watcher = $null
$codex = $null
$launchedThemeCodex = $false

try {
    if (-not (Test-Path -LiteralPath $injector -PathType Leaf)) { throw '主题注入器文件不存在。' }
    New-Item -ItemType Directory -Force -Path $script:QQRuntimeRoot | Out-Null

    $oldState = Read-QQState
    if ($null -ne $oldState) {
        Stop-QQWatcherSafely -State $oldState -ExpectedInjector ([string]$oldState.injectorPath) | Out-Null
    }

    $codex = Get-QQCodexInstall
    $profile = Ensure-QQProfileAlias
    Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $verifyFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $domInspectFile -Force -ErrorAction SilentlyContinue

    $existing = Find-QQLiveThemeEndpoint -Codex $codex
    if ($null -ne $existing) {
        $port = [int]$existing.Port
        $endpoint = $existing
        $launchPid = [int]$existing.ProcessId
        $launchedThemeCodex = $false
        Write-Host "检测到当前 Codex 已打开调试端口 $port，直接套用主题，不关闭窗口。" -ForegroundColor Green
    } else {
        $running = @(Get-QQCodexProcesses -Codex $codex)
        if ($running.Count -gt 0) { Stop-QQCodexProcesses -Codex $codex -Processes $running }

        $port = Get-QQFreePort -PreferredPort $PreferredPort
        # Codex 26.9+ 使用 --user-data-dir junction 会导致 CDP HTTP 挂起。
        # 这里与本机已验证可用的启动方式保持一致：只打开回环调试端口。
        $launchPid = Start-QQCodexPackage -Codex $codex -Arguments @(
            '--remote-debugging-address=127.0.0.1',
            "--remote-debugging-port=$port"
        )
        $launchedThemeCodex = $true
        $endpoint = Wait-QQVerifiedEndpoint -Port $port -Codex $codex -TimeoutSeconds 60
    }

    $domDeadline = (Get-Date).AddSeconds(60)
    $nativeDomReady = $false
    do {
        Invoke-QQNode -Node $node -Arguments @($injector, "inspect", "--port", [string]$port, "--output", $domInspectFile) | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $domInspectFile -PathType Leaf)) {
            $domInspection = Get-Content -LiteralPath $domInspectFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $nativeDomReady = (
                [int]$domInspection.selectors.root -ge 1 -and
                [int]$domInspection.selectors.leftPanel -ge 1 -and
                [int]$domInspection.selectors.mainSurface -ge 1 -and
                [int]$domInspection.selectors.composer -ge 1
            )
        }
        if (-not $nativeDomReady) { Start-Sleep -Milliseconds 300 }
    } while (-not $nativeDomReady -and (Get-Date) -lt $domDeadline)
    if (-not $nativeDomReady) {
        throw 'Codex 原生 DOM 未在 60 秒内完整挂载；已保留 dom-before-theme.json 供排查。'
    }

    $assetRoot = Join-Path $script:QQStateRoot 'assets'
    $watcher = Start-QQWatcher -NodePath $node.Path -InjectorPath $injector -Port $port -ReadyFile $readyFile -AssetRoot $assetRoot -NodeArguments $node.ExtraArgs
    $deadline = (Get-Date).AddSeconds(60)
    do {
        if ($watcher.HasExited) { throw '主题监视进程提前退出，请查看运行日志。' }
        if (Test-Path -LiteralPath $readyFile -PathType Leaf) { break }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    if (-not (Test-Path -LiteralPath $readyFile -PathType Leaf)) { throw '主题监视进程未在 60 秒内就绪。' }
    $ready = Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $ready.pass -or -not $ready.applied.pass) { throw '主题监视进程未确认皮肤已应用。' }

    Invoke-QQNode -Node $node -Arguments @($injector, "verify", "--port", [string]$port, "--output", $verifyFile) | Out-Null
    if (-not (Test-Path -LiteralPath $verifyFile -PathType Leaf)) { throw '主题布局验收文件未生成。' }
    $verification = Get-Content -LiteralPath $verifyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $chromeVisible = [bool]$verification.classApplied -and [bool]$verification.nativeAppIntact -and [bool]$verification.nodes.titlebar.visible -and [bool]$verification.nodes.composerChrome.visible
    if (-not $chromeVisible) {
        throw '主题未能同时满足布局完整与原生功能保留。'
    }
    if ($LASTEXITCODE -ne 0 -and -not [bool]$verification.pass) {
        Write-Host '主题已套上。部分细节验收未通过，已继续启动，避免退回原版 Codex。' -ForegroundColor Yellow
    }

    Write-QQState -State ([ordered]@{
        schemaVersion = 1
        product = $script:QQProductName
        version = $script:QQVersion
        port = $port
        watcherPid = $watcher.Id
        watcherStartedAt = $watcher.StartTime.ToUniversalTime().ToString('o')
        injectorPath = [IO.Path]::GetFullPath($injector)
        nodePath = [IO.Path]::GetFullPath($node.Path)
        profileAlias = $profile.Alias
        profileTarget = $profile.Target
        codexExecutable = $codex.Executable
        codexPackageFullName = $codex.PackageFullName
        codexAppUserModelId = $codex.AppUserModelId
        codexLaunchPid = $launchPid
        targetId = $endpoint.TargetId
        verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
    })

    Write-Host "Codex 2007 已启动并通过验证。" -ForegroundColor Green
    Write-Host "QQ等级由本机累计 Token 统计自动计算；主题接口仅监听 127.0.0.1:$port。"
    exit 0
}
catch {
    if ($null -ne $watcher -and -not $watcher.HasExited) {
        Stop-Process -Id $watcher.Id -ErrorAction SilentlyContinue
    }
    if ($launchedThemeCodex -and $null -ne $codex) {
        $stillRunning = @(Get-QQCodexProcesses -Codex $codex)
        if ($stillRunning.Count -eq 0) {
            try { Start-QQCodexPackage -Codex $codex | Out-Null } catch {}
        } else {
            Write-Host '主题启动未完全通过验收，已保留当前 Codex 窗口，不再退回原版。' -ForegroundColor Yellow
        }
    }
    Write-Error $_.Exception.Message
    exit 1
}
