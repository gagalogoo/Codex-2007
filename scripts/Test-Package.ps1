#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Test-JavaScriptSyntax {
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -eq $node) {
        Add-Failure 'node.exe was not found on PATH.'
        return
    }
    foreach ($file in @('src/injector.mjs', 'src/token-stats.mjs', 'src/skin-runtime.js')) {
        & $node.Source --check (Join-Path $root $file)
        if ($LASTEXITCODE -ne 0) { Add-Failure "JavaScript syntax failed: $file" }
    }
}

function Test-PowerShellSyntax {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File) {
        $tokens = $null
        $errors = $null
        # Windows PowerShell 5.1 may decode a UTF-8 file without BOM using the
        # legacy system code page. Read UTF-8 explicitly before parsing so CI
        # validates the same Chinese source text that Node and Git preserve.
        $source = [IO.File]::ReadAllText($file.FullName, [Text.UTF8Encoding]::new($false))
        [Management.Automation.Language.Parser]::ParseInput($source, $file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        foreach ($parseError in @($errors)) {
            Add-Failure "PowerShell syntax failed: $($file.FullName.Substring($root.Length + 1)): $($parseError.Message)"
        }
    }
}

function Test-Manifest {
    try { $manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-Failure "manifest.json is invalid: $($_.Exception.Message)"; return }
    if ([string]$manifest.version -notmatch '^\d+\.\d+\.\d+$') { Add-Failure 'manifest version must use semantic versioning.' }
    if ($manifest.id -ne 'codex-2007') { Add-Failure 'manifest id must be codex-2007.' }
    if ($manifest.name -ne 'Codex 2007') { Add-Failure 'manifest name must be Codex 2007.' }
    foreach ($property in $manifest.entrypoints.PSObject.Properties) {
        $path = Join-Path $root ([string]$property.Value)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "Missing entrypoint: $($property.Value)" }
    }
    foreach ($asset in @($manifest.thirdPartyAssets)) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $asset) -PathType Leaf)) { Add-Failure "Missing declared third-party asset: $asset" }
    }
}

function Test-VersionConsistency {
    $manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $version = [string]$manifest.version
    $common = Get-Content -LiteralPath (Join-Path $root 'windows/Common.ps1') -Raw -Encoding UTF8
    $installer = Get-Content -LiteralPath (Join-Path $root 'windows/Install-Codex-2007.ps1') -Raw -Encoding UTF8
    $installation = Get-Content -LiteralPath (Join-Path $root 'docs/INSTALLATION.md') -Raw -Encoding UTF8
    $changelog = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
    if (-not $common.Contains("`$script:QQVersion = '$version'")) {
        Add-Failure "windows/Common.ps1 version does not match manifest: $version"
    }
    if (-not $installer.Contains("Join-Path (Join-Path `$script:QQStateRoot 'packages') `$script:QQVersion")) {
        Add-Failure 'Installer package path must derive from the canonical runtime version.'
    }
    if (-not $installation.Contains("packages\$version")) {
        Add-Failure "Installation documentation does not contain package version $version."
    }
    if (-not $changelog.Contains("## [$version]")) {
        Add-Failure "CHANGELOG.md does not contain version $version."
    }
}

function Test-CanonicalProductNaming {
    $canonical = 'Codex 2007'
    $requiredFiles = @(
        'README.md', 'CHANGELOG.md', 'manifest.json',
        'src/skin-runtime.js', 'src/injector.mjs',
        'windows/Common.ps1', 'windows/Install-Codex-2007.ps1',
        'windows/Start-Codex-2007.ps1', 'windows/Restore-Codex.ps1'
    )
    foreach ($file in $requiredFiles) {
        $content = Get-Content -LiteralPath (Join-Path $root $file) -Raw -Encoding UTF8
        if (-not $content.Contains($canonical)) {
            Add-Failure "Canonical product name is missing from $file"
        }
    }
    foreach ($oldFile in @(
        'windows/Install-QQ2009-Programmer-Codex.ps1',
        'windows/Start-QQ2009-Programmer-Codex.ps1',
        'windows/Install-QQ2007-Programmer-Edition.ps1',
        'windows/Start-QQ2007-Programmer-Edition.ps1'
    )) {
        if (Test-Path -LiteralPath (Join-Path $root $oldFile)) {
            Add-Failure "Legacy-named entrypoint must not remain: $oldFile"
        }
    }
    foreach ($contract in @('codex-2007', 'Codex2007', 'CODEX_2007')) {
        $found = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
            $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]artifacts[\\/]' -and
            $_.Name -ne 'SHA256SUMS' -and $_.Extension -in @('.js', '.mjs', '.css', '.ps1', '.json')
        } | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).Contains($contract) }
        if (-not $found) { Add-Failure "Missing canonical runtime identifier: $contract" }
    }
}

function Test-RequiredFiles {
    $required = @(
        'README.md', 'SECURITY.md', 'LICENSE', 'LICENSE.txt', 'NOTICE.txt', 'THIRD_PARTY_NOTICES.md',
        'CHANGELOG.md', 'CONTRIBUTING.md', 'SUPPORT.md', 'docs/SOURCES.md',
        'scripts/build-animated-stages.py', 'scripts/Build-Release.ps1', 'scripts/Test-Release.ps1',
        'assets/codex2007-title-bg.png',
        'assets/codex2007-bot-typing-sprites.png', 'assets/codex2007-bot-stage.gif',
        'assets/qq-retro-stage.png', 'assets/qq-retro-wave-sprites.png', 'assets/qq-retro-stage.gif',
        'assets/qq2007-gary-show.png', 'assets/qq2007-gary-avatar.png', 'assets/qq2007-gary-avatar.gif',
        'assets/qq-level-star.png', 'assets/qq-level-moon.png',
        'assets/qq-level-sun.png', 'assets/qq-level-crown.png'
    )
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) { Add-Failure "Missing required file: $file" }
    }
}

function Test-AnimatedAssets {
    try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
    catch { Add-Failure "System.Drawing could not validate animated assets: $($_.Exception.Message)"; return }
    foreach ($file in @('assets/codex2007-bot-stage.gif', 'assets/qq-retro-stage.gif', 'assets/qq2007-gary-avatar.gif')) {
        $path = Join-Path $root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $image = $null
        try {
            $image = [Drawing.Image]::FromFile($path)
            $dimension = [Drawing.Imaging.FrameDimension]::new($image.FrameDimensionsList[0])
            $frameCount = $image.GetFrameCount($dimension)
            if ((Get-Item -LiteralPath $path).Length -gt 1.5MB) { Add-Failure "Animated asset exceeds 1.5 MB: $file" }
            if ($file -eq 'assets/codex2007-bot-stage.gif' -and $frameCount -lt 6) {
                Add-Failure "Animated asset has too few frames: $file ($frameCount)"
            }
            if ($file -eq 'assets/qq-retro-stage.gif' -and ($image.Width -ne 390 -or $image.Height -ne 520)) {
                Add-Failure "Codex bot-stage asset must be 390x520: $($image.Width)x$($image.Height)"
            }
        }
        catch { Add-Failure "Animated asset is invalid: $file ($($_.Exception.Message))" }
        finally { if ($null -ne $image) { $image.Dispose() } }
    }
    $friend = Join-Path $root 'assets/qq2007-gary-show.png'
    if (Test-Path -LiteralPath $friend -PathType Leaf) {
        $image = $null
        try {
            $image = [Drawing.Image]::FromFile($friend)
            if ($image.Width -ne 240 -or $image.Height -ne 320) {
                Add-Failure "Friend-stage asset must be 240x320: $($image.Width)x$($image.Height)"
            }
        }
        catch { Add-Failure "Friend-stage asset is invalid ($($_.Exception.Message))" }
        finally { if ($null -ne $image) { $image.Dispose() } }
    } else {
        Add-Failure 'Missing friend-stage asset: assets/qq2007-gary-show.png'
    }
}

function Test-QQCharacterProportionContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $contractSources = $css + $injector
    foreach ($contract in @(
        'friendStageAspectReady',
        'friendStagePixelReady',
        '.qq2007-friend-stage > .qq2007-motion-stage > img',
        'aspect-ratio: 240 / 320',
        'aspect-ratio: 3 / 4',
        'qq2007-idle-bob',
        'qq-retro-stage.gif',
        'qq2007-gary-show.png',
        'image-rendering: auto'
    )) {
        if (-not $contractSources.Contains($contract)) {
            Add-Failure "Missing QQ character-proportion contract: $contract"
        }
    }
}

function Test-MarkdownLinks {
    $markdownFiles = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]artifacts[\\/]'
    }
    foreach ($file in $markdownFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($content, '\]\((?<target>[^)]+)\)')) {
            $target = $match.Groups['target'].Value.Trim().Trim('<', '>')
            if ($target -match '^(https?://|mailto:|#)' -or $target -match '^app://') { continue }
            $relative = ($target -split '#', 2)[0]
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $resolved = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relative))
            if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $resolved)) {
                Add-Failure "Broken Markdown link in $($file.FullName.Substring($root.Length + 1)): $target"
            }
        }
    }
}

function Test-NoRuntimeArtifacts {
    $forbidden = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and (
            $_.Extension -eq '.log' -or
            $_.Name -like 'verify*.json' -or
            $_.Name -like 'watcher-ready*.json' -or
            $_.Name -eq 'state.json' -or
            $_.Name -like 'dom-*.json'
        )
    }
    foreach ($file in $forbidden) { Add-Failure "Runtime artifact must not be committed: $($file.FullName.Substring($root.Length + 1))" }
}

function Test-ApprovalOverlayProtection {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    foreach ($contract in @(
        'const hasNativeApprovalSurface = () =>',
        'if (hasNativeApprovalSurface()) return;',
        'if (hasNativeApprovalSurface()) {',
        'const nativeApprovalActive =',
        'nativeActionControlsReady',
        '&& !verified?.visualContract?.nativeApprovalActive'
    )) {
        if (-not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing approval-overlay protection contract: $contract"
        }
    }
}

function Test-NativeFloatingTrayScope {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    foreach ($contract in @(
        'bg-surface-elevated-secondary',
        'findNativeOverlayCard',
        'isViewportVisible',
        'isNativeTrayExpanded',
        "card.closest('.origin-top-right')",
        'new DOMMatrixReadOnly(transform)',
        'isNativeInformationTray',
        'nativeOverlayLeavesLayout'
    )) {
        if (-not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing native floating-tray scope contract: $contract"
        }
    }
}

function Test-SettingsHeightChain {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        'qq2007SettingsColumn',
        'qq2007SettingsNavigationHost',
        'settingsNavigationFillsPane',
        'settingsNavigationContentReady',
        'settingsVisibleRowCount',
        'settingsRowsSized'
    )) {
        if (-not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing settings height-chain contract: $contract"
        }
    }
    foreach ($selector in @(
        '[data-qq2007-settings-column="true"]',
        '[data-qq2007-settings-navigation-host="true"]'
    )) {
        if (-not $css.Contains($selector)) {
            Add-Failure "Missing settings height-chain selector: $selector"
        }
    }
}

function Test-SettingsSidebarHeightContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    if (-not $runtime.Contains("settingsContent?.closest('aside.app-shell-left-panel')")) {
        Add-Failure 'Settings sidebar must decorate the full-height app-shell aside.'
    }
    foreach ($contract in @('settingsSidebarFillsPane', "settingsSidebar?.matches('aside.app-shell-left-panel')")) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing settings sidebar height verification contract: $contract"
        }
    }
    foreach ($contract in @(
        'const findSettingsSearch =',
        'const isSettingsSurface = () => Boolean(findSettingsSearch())',
        'state.refreshSettingsTheme = () =>',
        'state.settingsPoller = window.setInterval'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing stable settings-surface detection contract: $contract"
        }
    }
    foreach ($contract in @('preserveExistingSettings', 'preservedSettingsSurface', 'typeof state.refreshSettingsTheme')) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing settings re-bootstrap protection contract: $contract"
        }
    }
}

function Test-ClassicMessageActionsContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        'makeClassicMessageActionIcon',
        'qq2007MessageAction',
        'qq2007MessageActions',
        'qq2007MessageNativeIcon'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing classic message-action runtime contract: $contract"
        }
    }
    foreach ($kind in @("kind: 'copy'", "kind: 'like'", "kind: 'dislike'", "kind: 'share'")) {
        if (-not $runtime.Contains($kind)) {
            Add-Failure "Missing classic message-action kind: $kind"
        }
    }
    foreach ($contract in @(
        'findMessageActionStrip',
        'matchingButtons.length === presentations.length',
        'delete staleStrip.dataset.qq2007MessageActions'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing scoped message-action strip contract: $contract"
        }
    }
    foreach ($selector in @('[data-qq2007-message-actions="true"]', 'button[data-qq2007-message-action]', '.qq2007-message-action-icon')) {
        if (-not $css.Contains($selector)) {
            Add-Failure "Missing classic message-action selector: $selector"
        }
    }
    foreach ($contract in @(
        'classicMessageActionsReady',
        'classicMessageActionCount',
        'classicMessageActionStripsScoped',
        'conversationTurnsContained',
        'visibleConversationTurnCount'
    )) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing classic message-action verification contract: $contract"
        }
    }
}

function Test-MainTitleFrameContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        'const syncMainTitleFrame =',
        'const mainRect = main.getBoundingClientRect()',
        '--qq2007-main-title-frame-left',
        'window.innerWidth - mainRect.right',
        'height: 46px !important',
        'min-height: 46px !important'
    )) {
        if (-not $runtime.Contains($contract) -and -not $css.Contains($contract)) {
            Add-Failure "Missing main-title frame contract: $contract"
        }
    }
    foreach ($contract in @(
        'mainTitleClearOfLeftRail',
        'mainTitleAlignedWithConversationFrame',
        'mainTitleRounded',
        'mainTitleBottomAlignedWithConversation',
        'conversationViewportTop',
        'mainTitleFrameLeft',
        'conversationFrameLeft'
    )) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing main-title alignment verification: $contract"
        }
    }
}

function Test-HomeSurfaceStateContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    foreach ($contract in @(
        'const findHomePrompt =',
        'const findHomeAnchor =',
        'const homeSurfaceActive = Boolean(prompt || suggestions)',
        '--qq2007-home-welcome-top',
        'suggestionsRect.top - anchorRect.top - welcomeHeight - 6',
        'for (const card of suggestions?.querySelectorAll'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing home-surface state contract: $contract"
        }
    }
    foreach ($contract in @(
        'const homeSurfaceDetected = Boolean(homeSuggestions || homePrompt)',
        'const homePromptHidden =',
        'homeWelcomeAlignedWithSuggestions',
        'homeWelcomeSuggestionGap',
        '(homeSurfaceDetected || retroComposerControlsReady)',
        '(homeSurfaceDetected || mainTitleBottomAlignedWithConversation)',
        '&& homePromptHidden',
        '(!homeSuggestions || ('
    )) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing home-surface verification contract: $contract"
        }
    }
}

function Test-HomeCardAssetContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    if ($runtime.Contains('config.assets.toolPr')) {
        Add-Failure 'Home review card references undefined asset key: config.assets.toolPr'
    }
    foreach ($contract in @(
        'config.assets.toolPullRequests',
        'presentation.asset || config.assets.toolNew',
        'homeCardIconsReady',
        'homeCardIconCount',
        'homeReviewAssetReady',
        "startsWith('data:image/png;base64,')"
    )) {
        if (-not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing home-card asset contract: $contract"
        }
    }
}

function Test-NativeWindowControlsContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    if ($runtime.Contains('config.assets.windowControls') -or $injector.Contains("windowControls: 'codex2007-window-controls.png'")) {
        Add-Failure 'Decorative window-control imagery must not overlap native Electron controls.'
    }
    foreach ($contract in @(
        '--spacing-token-safe-header-right',
        ') || 137',
        'duplicateWindowControlGlyphsAbsent',
        'nativeWindowControlsSafeInset',
        'nativeWindowControlsReady'
    )) {
        if (-not $runtime.Contains($contract) -and -not $css.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing native window-controls contract: $contract"
        }
    }
    foreach ($forbidden in @('makeRetroCaptionUnderlay', 'qq2007-retro-caption-underlay')) {
        if ($runtime.Contains($forbidden) -or $css.Contains($forbidden)) {
            Add-Failure "Renderer-only caption decoration would duplicate native controls: $forbidden"
        }
    }
}

function Test-RetroComposerControlsContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        'qq2007NativeAttachTrigger',
        'qq2007NativeAccessTrigger',
        'qq2007NativeContextIndicator',
        'qq2007ContextValue',
        'qq2007-model-icon',
        'qq2007-model-caret',
        '--qq2007-composer-attach-bg',
        '--qq2007-shield-bg',
        'nativeContextIndicatorReady',
        'retroComposerControlsReady',
        'contextIndicatorRight',
        'modelButtonLeft'
    )) {
        if (-not $runtime.Contains($contract) -and -not $css.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing retro composer-controls contract: $contract"
        }
    }
}

function Test-RetroScrollbarContract {
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        '--qq2007-scrollbar-skin: xp-luna',
        'scrollbar-color: auto !important',
        'scrollbar-width: auto !important',
        '::-webkit-scrollbar-button:vertical:start:increment',
        '::-webkit-scrollbar-button:vertical:end:decrement',
        '::-webkit-scrollbar-thumb',
        '::-webkit-scrollbar-button:vertical:decrement',
        '::-webkit-scrollbar-button:vertical:increment',
        '::-webkit-scrollbar-button:horizontal:decrement',
        '::-webkit-scrollbar-button:horizontal:increment',
        'height: 17px',
        'width: 17px',
        'retroScrollbarReady',
        'retroScrollbarCssReady',
        'retroScrollbarTargetsReady',
        'retroScrollbarTargetCount',
        '--qq2007-scrollbar-skin: native-jump',
        'conversationJumpReady',
        'scrollbar-gutter: stable both-edges'
    )) {
        if (-not $css.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing retro scrollbar contract: $contract"
        }
    }
    if ($css -match '(?s)main\.main-surface \.thread-scroll-container[^}]*scrollbar-width:\s*thin') {
        Add-Failure 'Conversation must use the official Electron jump gutter, not scrollbar-width: thin.'
    }
    if ($css -match 'main\.main-surface \.thread-scroll-container::-webkit-scrollbar') {
        Add-Failure 'Do not style conversation ::-webkit-scrollbar; that disables Electron overlay jump scrolling.'
    }
    if ($css -match '(?m)html\.codex-2007 \*::-webkit-scrollbar') {
        Add-Failure 'Luna ::-webkit-scrollbar must exclude .thread-scroll-container so overlay jump scrolling survives.'
    }
    if ($css -notmatch '\*:not\(\.thread-scroll-container, \.thread-scroll-container \*\)::-webkit-scrollbar') {
        Add-Failure 'Luna scrollbar selectors must exclude the conversation scroller.'
    }
}

function Test-NativeNewTaskBackdropContract {
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    foreach ($contract in @(
        'qq2007NativeNavPaintHost',
        'data-qq2007-native-nav-paint-host="new-task"',
        '> [data-qq2007-nav="new-task"]:hover',
        'nativeNewTaskBackdropCleared'
    )) {
        if (-not $runtime.Contains($contract) -and -not $injector.Contains($contract) -and -not $css.Contains($contract)) {
            Add-Failure "Missing native New task backdrop contract: $contract"
        }
    }
}

function Test-ResolvedNodeProvidesWebSocket {
    $start = Get-Content -LiteralPath (Join-Path $root 'windows/Start-Codex-2007.ps1') -Raw -Encoding UTF8
    $restore = Get-Content -LiteralPath (Join-Path $root 'windows/Restore-Codex.ps1') -Raw -Encoding UTF8
    $common = Get-Content -LiteralPath (Join-Path $root 'windows/Common.ps1') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8

    if ($common -notmatch 'function Resolve-QQNode\b') {
        Add-Failure 'windows/Common.ps1 must define Resolve-QQNode so Codex-prepended Node 20 is not used blindly.'
    }
    if ($start -notmatch 'Resolve-QQNode') {
        Add-Failure 'windows/Start-Codex-2007.ps1 must resolve Node via Resolve-QQNode.'
    }
    if ($restore -notmatch 'Resolve-QQNode') {
        Add-Failure 'windows/Restore-Codex.ps1 must resolve Node via Resolve-QQNode.'
    }
    if ($start -match '\(Get-Command node\.exe -ErrorAction Stop\)\.Source' -or $restore -match '\(Get-Command node\.exe -ErrorAction Stop\)\.Source') {
        Add-Failure 'Start/Restore must not take the first PATH node.exe; Codex prepends Node 20 without WebSocket.'
    }
    if ($injector -notmatch 'globalThis\.WebSocket') {
        Add-Failure 'src/injector.mjs must read WebSocket from globalThis so Node 20 fails with a clear error instead of ReferenceError.'
    }
    if ($common -notmatch 'function Resolve-QQNode\b') { return }

    $commonPath = Join-Path $root 'windows/Common.ps1'
    $probe = Join-Path $env:TEMP ('codex2007-websocket-probe-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    $escapedCommon = $commonPath.Replace("'", "''")
    $probeLines = @(
        'Set-StrictMode -Version 2.0',
        '$ErrorActionPreference = ''Stop''',
        ". '$escapedCommon'",
        '$node = Resolve-QQNode',
        '$nodeArgs = @()',
        'if ($null -ne $node.ExtraArgs) { $nodeArgs += @($node.ExtraArgs) }',
        '$nodeArgs += ''-p''',
        '$nodeArgs += ''typeof WebSocket''',
        '$kind = (& $node.Path @nodeArgs | Out-String).Trim()',
        'if ($kind -ne ''function'') { throw "Resolved Node lacks WebSocket: $($node.Path) $($node.Version) => $kind" }'
    )
    [IO.File]::WriteAllText($probe, (($probeLines -join [Environment]::NewLine) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    try {
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $powershell -NoProfile -ExecutionPolicy Bypass -File $probe
        if ($LASTEXITCODE -ne 0) {
            Add-Failure 'Resolve-QQNode selected a Node.js binary that still does not provide WebSocket.'
        }
    }
    finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}


function Test-LockedSidebarSplitContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8

    foreach ($contract in @(
        '--qq2007-left-width: 280px;',
        '--qq2007-right-width: 232px;',
        'max-width: var(--qq2007-left-width) !important;',
        'aside.app-shell-left-panel [class*="panel-resizer"]',
        'aside.app-shell-left-panel [role="separator"]',
        'main.main-surface [role="separator"]',
        'main.main-surface [class*="cursor-row-resize"]',
        'main.main-surface [class*="cursor-col-resize"]',
        'pointer-events: none !important;',
        'display: none !important;'
    )) {
        if (-not $css.Contains($contract)) {
            Add-Failure "Missing locked-sidebar CSS contract: $contract"
        }
    }
    if ($css.Contains('19vw') -or $css.Contains('16vw')) {
        Add-Failure 'Sidebar widths must be fixed CSS pixels, not viewport units.'
    }
    foreach ($contract in @(
        'const lockSidebarSplit =',
        "'var(--qq2007-left-width)'",
        "removeProperty('--codex-sidebar-preferred-width')",
        'lockSidebarSplit()'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing locked-sidebar runtime contract: $contract"
        }
    }
    foreach ($contract in @('sidebarSplitLocked', 'preferredSidebarWidthSynced')) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing locked-sidebar verification contract: $contract"
        }
    }
}

function Test-RightPanelPinnedStagesContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8

    foreach ($contract in @(
        '.qq2007-friends-pane',
        'flex: 1 1 auto',
        'object-fit: contain'
    )) {
        if (-not $css.Contains($contract)) {
            Add-Failure "Missing pinned-stage CSS contract: $contract"
        }
    }
    if ($css -notmatch '(?s)#qq2007-right-panel\s*\{[^}]*height:\s*100%') {
        Add-Failure 'Right panel must fill the row height with height: 100%.'
    }
    if ($css -match '(?s)\.qq2007-bot-stage\s*>\s*\.qq2007-motion-stage\s*>\s*img\s*\{[^}]*object-fit:\s*cover') {
        Add-Failure 'Codex Xiaolan stage must use object-fit: contain, not cover.'
    }
    foreach ($contract in @(
        "create('div', 'qq2007-friends-pane')",
        '智能伙伴 (1/1)',
        '离线好友 (0/0)',
        "create('div', 'qq2007-friend-row')",
        'qq2007-friend-row-avatar',
        'friendsPane.append',
        'panel.append(header, botCard, friendsPane, friendStage, friendSearch)'
    )) {
        if (-not $runtime.Contains($contract)) {
            Add-Failure "Missing pinned-stage runtime contract: $contract"
        }
    }
    foreach ($contract in @('friendSearchPinnedToBottom', 'friendStageAboveSearch', 'partnerFriendRowReady', 'stageFramesReady')) {
        if (-not $injector.Contains($contract)) {
            Add-Failure "Missing pinned-stage verification contract: $contract"
        }
    }
    if ($css -notmatch '(?s)\.qq2007-friend-stage\s*\{[^}]*border:\s*1px solid') {
        Add-Failure 'Friend stage must use a 1px solid border on all sides.'
    }
    if ($css -notmatch '(?s)\.qq2007-bot-identity\s*\{[^}]*min-height:\s*26px') {
        Add-Failure 'Bot identity must not use a fixed 22px height.'
    }
}

function Test-ComposerAttachmentsContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    foreach ($contract in @(
        'ComposerLayoutAttachments',
        'data-qq2007-composer-attachments',
        'const syncComposerAttachments =',
        'composerAttachmentsClickable'
    )) {
        if (-not $runtime.Contains($contract) -and -not $css.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing composer-attachment contract: $contract"
        }
    }
    if ($css -notmatch 'margin-top:\s*36px !important') {
        Add-Failure 'Attachment strip must clear the 34px composer toolbar.'
    }
}

function Test-ThreadOverlayGutterContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    if ($css -match '(?s)html\.codex-2007\s*\{[^}]*zoom\s*:') {
        Add-Failure 'Do not zoom the whole page to compensate for display scaling.'
    }
    if ($css -match '(?s)main \[class\*="overflow-x-clip"\][^}]*overflow-x:\s*visible') {
        Add-Failure 'Message column must not force overflow-x: visible.'
    }
    if ($css -match '(?s)main \[class\*="overflow-x-clip"\][^}]*overflow-x:\s*hidden') {
        Add-Failure 'Message column overflow-x:hidden creates a nested Y scroller.'
    }
    if ($css -match '(?s)\[data-qq2007-native-overlay="true"\][^{]*#qq2007-right-panel\s*\{[^}]*display:\s*none') {
        Add-Failure 'Environment overlay must not hide the QQ right panel.'
    }
    if ($css.Contains('--qq2007-thread-overlay-gutter') -or $runtime.Contains('--qq2007-thread-overlay-gutter')) {
        Add-Failure 'Do not add a thread overlay gutter that squeezes the conversation left.'
    }
    foreach ($contract in @(
        'nativeOverlayLeavesLayout',
        'lockConversationScrollParent',
        'conversationScrollNotNested',
        '[data-thread-find-target="conversation"] > .relative.shrink-0'
    )) {
        if (-not $css.Contains($contract) -and -not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing thread overlay layout contract: $contract"
        }
    }
}

function Test-SidebarNavAlignmentContract {
    $css = Get-Content -LiteralPath (Join-Path $root 'src/skin.css') -Raw -Encoding UTF8
    $runtime = Get-Content -LiteralPath (Join-Path $root 'src/skin-runtime.js') -Raw -Encoding UTF8
    $injector = Get-Content -LiteralPath (Join-Path $root 'src/injector.mjs') -Raw -Encoding UTF8
    foreach ($contract in @(
        'padding-left: 36px !important;',
        'background-position: 16px center !important;',
        '.w-4.shrink-0.items-center.justify-center',
        'sidebarNavIconsAligned',
        'threadRowIconTextTight',
        '定时任务'
    )) {
        if (-not $css.Contains($contract) -and -not $runtime.Contains($contract) -and -not $injector.Contains($contract)) {
            Add-Failure "Missing sidebar alignment contract: $contract"
        }
    }
}

Test-JavaScriptSyntax
Test-PowerShellSyntax
Test-Manifest
Test-VersionConsistency
Test-CanonicalProductNaming
Test-RequiredFiles
Test-AnimatedAssets
Test-QQCharacterProportionContract
Test-MarkdownLinks
Test-NoRuntimeArtifacts
Test-ApprovalOverlayProtection
Test-NativeFloatingTrayScope
Test-SettingsHeightChain
Test-SettingsSidebarHeightContract
Test-ClassicMessageActionsContract
Test-MainTitleFrameContract
Test-HomeSurfaceStateContract
Test-HomeCardAssetContract
Test-NativeWindowControlsContract
Test-RetroComposerControlsContract
Test-RetroScrollbarContract
Test-NativeNewTaskBackdropContract
Test-ResolvedNodeProvidesWebSocket
Test-LockedSidebarSplitContract
Test-RightPanelPinnedStagesContract
Test-ComposerAttachmentsContract
Test-ThreadOverlayGutterContract
Test-SidebarNavAlignmentContract

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Package validation passed.' -ForegroundColor Green
exit 0
