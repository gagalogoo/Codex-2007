# Codex 2007

Windows Codex 桌面端的 QQ 2007 复古皮肤。不改官方安装包，下载后运行一条安装命令就能用；不想用了再运行恢复脚本，官方外观会回来。

<p align="center">
  <img src="assets/qq-retro-stage.png" alt="Codex 小蓝 QQ 秀" width="240">
  &nbsp;&nbsp;
  <img src="assets/qq2007-gary-show.png" alt="好友形象" width="180">
</p>

> 这是非官方视觉项目，和腾讯、QQ、OpenAI 都没有隶属或授权关系。代码使用 MIT 许可证；QQ 相关名称和图标属于各自权利人。

## 你需要准备什么

- Windows 10 或 Windows 11
- 已经安装官方 **Windows Codex** 桌面应用
- 已安装 [Node.js 22+](https://nodejs.org/)，在终端里输入 `node -v` 能看到版本号

## 安装（大约 3 分钟）

### 方式 A：下载 ZIP（不用 Git，推荐）

1. 打开仓库页面：[https://github.com/gagalogoo/Codex-2007](https://github.com/gagalogoo/Codex-2007)
2. 点击绿色按钮 **Code** → **Download ZIP**
3. 解压到任意目录，例如 `D:\Codex-2007`
4. 进入解压后的文件夹（能看到 `windows` 和 `README.md` 这一层）
5. 在文件夹空白处按住 **Shift** 再右键，选择 **在此处打开 PowerShell 窗口**
6. 可以直接双击 `windows\Install-Codex-2007.cmd`；也可粘贴下面这一行回车：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-Codex-2007.ps1
```

装完后，从桌面或开始菜单打开 **Codex 2007**。

> 直接点官方 Codex 图标不会套皮肤。皮肤版请用 **Codex 2007** 快捷方式。

### 方式 B：用 Git

```powershell
git clone https://github.com/gagalogoo/Codex-2007.git
cd Codex-2007
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-Codex-2007.ps1
```

只安装、先不启动：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-Codex-2007.ps1 -NoLaunch
```

## 日常使用

| 你想做的事 | 怎么做 |
| --- | --- |
| 用皮肤版 Codex | 打开桌面 / 开始菜单里的 **Codex 2007** |
| 用官方原版外观 | 打开官方 Codex 图标 |
| 卸掉皮肤、关掉调试端口 | 运行下面的恢复命令 |

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Restore-Codex.ps1
```

更新皮肤时，重新下载/拉取最新代码，再运行一次安装脚本即可。安装脚本不会删除你的 Codex 对话。

## 换自己的 QQ 秀 / 头像

1. 替换这些图片（保持文件名不变）：
   - `assets/qq2007-gary-show.png` 右侧好友形象，建议 `240×320`
   - `assets/qq2007-gary-avatar.png` 左侧头像
   - `assets/qq2007-gary-avatar.gif` 左侧头像动图
   - `assets/qq-retro-stage.png` / `assets/qq-retro-stage.gif` 小蓝 QQ 秀，建议 `390×520`
2. 再运行一次 `windows\Install-Codex-2007.ps1`
3. 用 **Codex 2007** 快捷方式重新打开

## 常见问题

- 报「表达式或语句中包含意外的标记」：请重新下载仓库最新 ZIP（已修复 PowerShell 5.1 中文编码），或直接双击 `windows\Install-Codex-2007.cmd`。
- 提示找不到 `node`：先安装 Node.js 22+，重新打开 PowerShell 再装。
- 装完还是官方外观：请用 **Codex 2007** 快捷方式启动，不要用官方图标。
- 安装失败 / 设置页异常：看 [故障排查](docs/TROUBLESHOOTING.md)。
- 更完整的安装说明：看 [安装文档](docs/INSTALLATION.md)。
- 使用方式、QQ 等级和状态栏：看 [使用说明](docs/USAGE.md)。

`-ExecutionPolicy Bypass` 只对这一次 PowerShell 进程有效，不会改系统执行策略。

## 这套皮肤会做什么 / 不会做什么

**会做**

- 给 Codex 套上 QQ2007 三栏外观：任务列表、对话、好友形象
- 对话三点平时隐藏，鼠标移上去后和置顶、归档一起出现，菜单仍是原版（含 worktree）
- 小蓝 QQ 秀包边，并和形象一样轻微晃动

**不会做**

- 不修改 `WindowsApps`、`app.asar`、官方签名
- 不读取或上传对话正文
- 不替换发送、模型、个人资料等原版关键按钮

当前已在 Codex `26.903.9818.0` 上验证。

## 文档

- [安装](docs/INSTALLATION.md) · [使用](docs/USAGE.md) · [故障排查](docs/TROUBLESHOOTING.md)
- [架构](docs/ARCHITECTURE.md) · [兼容性](docs/COMPATIBILITY.md) · [隐私](docs/PRIVACY.md)
- [更新记录](CHANGELOG.md) · [许可](LICENSE.txt) · [第三方说明](THIRD_PARTY_NOTICES.md)

视觉方向参考过公开的 QQ2007 概念图；本仓库是独立实现的主题层。完整来源见 [docs/SOURCES.md](docs/SOURCES.md)。