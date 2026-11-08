# Browser-launcher

Browser-launcher 可按配置启动 Chrome、Edge 或 fingerprint-chromium。每个配置由一个浏览器、一个代理和一组网址组成，并使用独立的浏览器数据目录，配置之间互不干扰。同一配置的第一个网址会打开新窗口，其余网址会在该窗口中打开为标签页。

启动语言、时区、浏览器路径和指纹参数都可以按配置设置。项目提供 Windows PowerShell、跨平台 Python 和 C# Windows 图形界面版本。

## 界面截图

<img src="images/screenshot.png" width="720" alt="浏览器多配置代理启动器界面">

## 版本一览

- **PowerShell 命令行版**（`browser-launcher.ps1`）：Windows PowerShell 菜单，按编号启动；配置直接写在脚本的“配置区”。
- **PowerShell 图形界面版**（`browser-launcher-gui.ps1`）：每个配置显示一个启动按钮；配置写在脚本的“配置区”。
- **PowerShell 可视化配置版**（`browser-launcher-visual.ps1`）：Windows 图形界面，支持新增、编辑、删除、导入和导出配置；配置保存在 `profiles.json`。
- **Python 跨平台版**（`browser-launcher.py`）：支持 Windows、macOS 和 Linux，使用系统自带的 tkinter 图形界面。
- **C# Windows 版**（`BrowserLauncher.CSharp`）：图形界面支持配置管理、导入导出和启动选中或全部配置；配置编辑页带字段说明，指纹参数可折叠。

C# 版点击主窗口关闭按钮后会隐藏到系统托盘继续运行。右键托盘图标可切换 Windows 系统时区、直接启动任意配置或退出启动器；双击托盘图标可重新打开主界面。切换系统时区前会提示确认，因为该设置会影响整台电脑上的应用。

Python 跨平台版、C# 版和 PowerShell 可视化配置版支持登录启动器及按配置自动启动浏览器。登录启动只打开启动器界面；每个配置可单独勾选是否在启动器打开时启动浏览器。Python 版支持 Windows、macOS 和 Linux；C# 版与 PowerShell 版支持 Windows。

## 下载 C# 版

从 [GitHub Releases](https://github.com/panyong29/Browser-launcher/releases) 下载 `BrowserLauncher.CSharp.exe`。该版本面向 Windows x64，目标为 .NET Framework 4.8；Windows 11 自带相应运行环境，无需安装 .NET 8。浏览器本身仍需预先安装。首次运行会在 exe 同目录生成 `profiles.json`；若要与其他版本共用配置，建议先备份该文件。

源码构建需要 .NET 8 SDK 和 .NET Framework 4.8 targeting pack：

```powershell
dotnet build .\BrowserLauncher.CSharp\BrowserLauncher.CSharp.csproj -c Release
```

推送 `csharp-v*` 标签会自动构建 Windows x64 exe 并创建 GitHub Release。

## 运行

### Windows PowerShell 版

推荐先运行可视化配置版：

```powershell
powershell -ExecutionPolicy Bypass -File .\browser-launcher-visual.ps1
```

也可以运行命令行版或固定按钮版：

```powershell
powershell -ExecutionPolicy Bypass -File .\browser-launcher.ps1
powershell -ExecutionPolicy Bypass -File .\browser-launcher-gui.ps1
```

PowerShell 脚本使用 UTF-8 with BOM 编码，可直接在 Windows PowerShell 5.1 运行。编辑并保存时请保留 UTF-8 编码。

### Windows Python 版

安装 Python 3 后，在项目目录运行：

```powershell
python .\browser-launcher.py
```

也可以使用 `py .\browser-launcher.py`。Windows 上不要用 `python3`：`WindowsApps` 中的 `python3` 可能只是 Microsoft Store 占位程序。

### macOS / Linux Python 版

```bash
python3 browser-launcher.py
```

macOS 请安装官网或 Homebrew 提供的 Python 3；系统自带的 `/usr/bin/python3` 通常没有 tkinter。Ubuntu / Debian 缺少 tkinter 时安装：

```bash
sudo apt install python3-tk
```

## 配置文件

可视化版、Python 版和 C# 版都使用 `profiles.json`，格式相同，可共用配置。PowerShell 脚本版也可按相同字段填写配置。

- **`baseDir`**：浏览器独立用户数据目录的存放位置。
- **基本配置**：配置名称、浏览器类型（`chrome` / `edge` / `fingerprint`）、代理地址和网址列表。代理留空表示直连。
- **`lang`**：启动语言，如 `en-US`、`zh-CN`；留空跟随系统。
- **`timezone`**：启动时区，使用 IANA 名称，如 `America/New_York`、`Asia/Shanghai`；留空跟随系统。
- **`browser_path`**：浏览器 exe 路径。填写且文件存在时优先使用；留空则自动查找。此项适用于所有浏览器，不属于指纹参数。
- **`use_fingerprint`**：fingerprint 浏览器的指纹开关。
- **`auto_start`**：是否在启动器打开时自动启动此浏览器配置；默认 `false`。旧配置没有此字段时按未勾选处理。
- **`fingerprint_seed`**：指纹种子，32 位整数；留空时按配置名生成固定值。
- **`fingerprint_platform`**：指纹操作系统，可填 `windows`、`linux` 或 `macos`。
- **`disable_spoofing`**：要关闭的指纹伪装类别，逗号分隔，如 `font,audio,canvas,clientrects,gpu`；留空表示全部开启。

示例配置中的代理 IP 是占位符，使用前请替换成自己的代理地址。带账号密码的 SOCKS5 代理，浏览器首次联网时会提示输入账号密码。

### 登录启动和配置自动启动

在 Python、C# 或 PowerShell 可视化配置版主界面勾选“登录时启动启动器”，即可在当前用户登录系统时打开启动器界面。启动器不会因此启动所有浏览器；在单个配置的编辑窗口勾选“跟随启动器启动此浏览器配置”，该配置才会在启动器每次打开时自动启动。新配置默认不勾选，旧配置也按不勾选处理。

登录启动仅为当前用户设置：Windows 使用用户登录启动项，macOS 使用 LaunchAgent，Linux 使用 XDG autostart。跨平台登录启动由 Python 版提供；C# 与 PowerShell 可视化版只支持 Windows。

## 启动语言、时区和指纹

本节说明适用于 Python 跨平台版和 PowerShell 版。

### 启动语言和时区

- **启动语言**：填写 `lang` 后会传入 `--lang` 和 `--accept-lang`，各系统均生效。
- **普通 Chrome / Edge 的时区**：浏览器没有 `--timezone` 参数。Linux / macOS 版通过 `TZ` 环境变量设置子进程时区；Windows 上仍使用系统时区，配置里的 `timezone` 不会修改系统。C# 版可在托盘右键菜单切换 Windows 系统时区，这会影响整台电脑上的应用。
- **fingerprint 浏览器的时区**：带补丁的 Chromium 支持 `--timezone=<时区>`，Windows 上也能设置。请将“浏览器 exe 路径”指向 fingerprint 浏览器自己的 exe（通常位于安装目录的 `Application\chrome.exe`）；留空时会尝试自动查找。

### 指纹开关和参数

指纹开关仅在浏览器选择 `fingerprint` 时显示。关闭时不传 `--fingerprint`，仍可使用语言、时区和代理；开启后才显示种子、操作系统和关闭伪装选项。浏览器 exe 路径始终可见，不受指纹开关影响。

- **种子**：`--fingerprint` 必须带 32 位整数，不能只传 `--fingerprint`。种子留空时，跨平台版和 PowerShell 版使用配置名的 CRC32 生成固定值，同名配置得到相同结果。
- **操作系统**：`fingerprint_platform` 可填 `windows`、`linux` 或 `macos`；留空时不强制指定。
- **关闭伪装**：`disable_spoofing` 仅在启用指纹种子时有意义，可选项为 `font`、`audio`、`canvas`、`clientrects` 和 `gpu`，多个值用逗号分隔。
- **旧配置**：如果没有 `use_fingerprint` 字段，`fingerprint` 默认开启指纹，`chrome` / `edge` 默认关闭。

### PowerShell 版首次运行检查

选择 `fingerprint` 后，指纹开关应出现；关闭开关时指纹参数折叠，打开后展开。浏览器 exe 路径始终可见。种子留空时可对照日志：配置名 `HK_chromium` 的种子应为 `-1744200419`。

### 检查设置是否生效

- **检查时区**：在 fingerprint 浏览器中按 F12 打开 Console，运行 `Intl.DateTimeFormat().resolvedOptions().timeZone`；结果应与配置值一致。
- **检查 GPU 伪装**：在 Console 中读取 `UNMASKED_VENDOR_WEBGL` / `UNMASKED_RENDERER_WEBGL`，并与任务管理器“性能 → GPU”中的显卡名称比较。换一个种子后，输出不变通常表示使用真实显卡信息；输出随种子变化则表示仍在伪装。

<details>
<summary>GPU 伪装故障排查记录</summary>

Windows 上 fingerprint 150 曾多次出现 `Aw Snap` / `Crashpad_NotConnectedToHandler`，但重复测试结果不一致；时区、种子、画布和元素尺寸等原因都未能复现，目前没有可靠结论。

曾有一次用户报告以下参数组合可以正常打开百度页，之后确认起作用的是 `--disable-spoofing=gpu`：

```text
--fingerprint=2023 --fingerprint-platform=windows --disable-spoofing=gpu
```

GPU 伪装可能向浏览器提供显卡无法兑现的参数，导致页面调用 WebGL 时渲染进程崩溃。关闭 GPU 伪装后浏览器会报告真实显卡参数。复测请使用全新数据目录、彻底退出浏览器，并确认同一组参数连续两次结果一致。

</details>

## 默认打开的网站

可视化版、Python 版和 C# 版的默认配置会先打开 [ippure.com](https://ippure.com/) 检查 IP，再打开配置中的其他网址。可在配置中删除或替换该网址。
