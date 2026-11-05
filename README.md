# Browser-launcher

Windows / macOS / Linux 用的 Chrome / Edge / fingerprint-chromium 多配置代理启动器：一个配置 = 一个浏览器 + 一个代理 + 一组网址，每个配置用独立的用户数据目录启动，互不干扰。同一配置的多个网址：第一个开新窗口，后面的开成这个窗口的标签页。每个配置还能单独设启动语言、启动时区、浏览器 exe 路径和指纹参数（见下）。

## 界面截图

<img src="images/screenshot.png" width="720" alt="浏览器多配置代理启动器界面">

## 版本

- browser-launcher.ps1：命令行版（Windows PowerShell），菜单选编号启动；配置写在脚本“配置区”，可填语言、时区、exe 路径、指纹开关及指纹参数
- browser-launcher-gui.ps1：图形界面版（Windows），每配置一个按钮；配置同样写在脚本“配置区”，可填语言、时区、exe 路径、指纹开关及指纹参数
- browser-launcher-visual.ps1：可视化配置版（Windows，推荐），配置存在 profiles.json，界面里可新增、编辑、删除、导入、导出，编辑框里有语言、时区、exe 路径、指纹开关及指纹参数
- browser-launcher.py：跨平台版（Windows / macOS / Linux），界面用各系统自带的 tkinter，功能与可视化配置版相同
- BrowserLauncher.CSharp：C# Windows 图形界面版，支持 profiles.json 读写、新增/编辑/删除配置、导入/导出、启动选中或全部配置；配置编辑页包含字段说明，指纹参数仅在选择 fingerprint 且打开指纹开关时展开；exe 可从 Releases 下载

### C# 版下载与运行

在 [Releases](https://github.com/panyong29/Browser-launcher/releases) 下载最新的 `BrowserLauncher.CSharp.exe`。该版本面向 Windows x64，基于 .NET Framework 4.8，使用 Windows 11 自带的 .NET Framework，无需单独安装 .NET 8；首次运行时会在 exe 同目录生成 `profiles.json`。把它与其他版本共用时，建议先备份配置文件。启动的浏览器仍需预先安装。

源码构建需要 .NET 8 SDK 和 .NET Framework 4.8 targeting pack：

```powershell
dotnet build .\BrowserLauncher.CSharp\BrowserLauncher.CSharp.csproj -c Release
```

推送 `csharp-v*` 格式的标签（例如 `csharp-v1.0.0`）会自动构建 Windows x64 exe 并创建 GitHub Release。

## 运行

Windows PowerShell 版：

    powershell -ExecutionPolicy Bypass -File .\browser-launcher-visual.ps1

跨平台版（Windows 上用 python / py，不要用 python3，WindowsApps 下的 python3 只是应用商店占位程序）：

    python browser-launcher.py

macOS / Linux 跨平台版：

    python3 browser-launcher.py

macOS 请用官网或 Homebrew 装的 Python 3，系统自带的 /usr/bin/python3 没有 tkinter；Linux 缺 tkinter 时，Ubuntu/Debian 执行 sudo apt install python3-tk。

PowerShell 版是 UTF-8 带 BOM 编码，Windows PowerShell 5.1 可直接运行；用记事本改完另存时保持 UTF-8 编码。

## 配置

profiles.json 是示例配置，和 PowerShell 版格式通用，两个版本可以共用：

- baseDir：各配置的用户数据目录存放位置
- 每个配置：名字、浏览器（chrome / edge / fingerprint）、代理（留空 = 直连）、网址（第一个开新窗口，后面的开成标签页）
- 每个配置还可填：启动语言（lang，留空 = 跟系统，如 en-US、zh-CN）、启动时区（timezone，留空 = 跟系统，IANA 名字如 America/New_York、Asia/Shanghai）、浏览器 exe 路径（browser_path，通用字段，填了且文件存在就优先用它，留空自动找，不属于指纹选项）、指纹开关（use_fingerprint，仅 fingerprint 用，见下）、指纹种子（fingerprint_seed，仅 fingerprint 用，见下）、操作系统（fingerprint_platform，仅 fingerprint 用，如 windows、linux、macos，留空 = 不强制）、关闭伪装（disable_spoofing，仅 fingerprint 用，逗号分隔，如 font,audio,canvas,clientrects,gpu，留空 = 全开）

## 启动语言、启动时区和指纹（跨平台版与 PowerShell 版通用）

### 启动语言和时区

- **启动语言（`lang`）**：填写后会传入 `--lang` 和 `--accept-lang`，各系统均生效；留空则跟随系统。
- **启动时区（`timezone`）**：留空则跟随系统。原版 Chrome / Edge 没有 `--timezone` 参数：Linux / macOS 版通过 `TZ` 环境变量设置子进程时区；Windows 上原版浏览器仍使用系统时区，启动器会在日志中提示该设置未生效。
- **fingerprint 浏览器**：它是带指纹补丁的 Chromium，支持 `--timezone=<时区>`，Windows 上也能设置时区。请选择 `fingerprint`，并在“浏览器 exe 路径”中指定它自己的 exe（通常位于安装目录的 `Application\chrome.exe`）；路径留空时会尝试自动查找。

### 指纹开关和参数

指纹开关只在浏览器选择 `fingerprint` 时显示。关闭开关时不传 `--fingerprint`，只应用语言、时区和代理；开启后才显示指纹种子、操作系统和关闭伪装选项。浏览器 exe 路径是通用设置，不受指纹开关影响。

- **指纹种子（`fingerprint_seed`）**：必须是 32 位整数，不能裸传 `--fingerprint`。留空时会按配置名生成固定种子；跨平台版与 PowerShell 版使用相同的 CRC32 算法。同一配置名会得到相同种子。
- **操作系统（`fingerprint_platform`）**：仅 fingerprint 使用，可填 `windows`、`linux` 或 `macos`；留空时不强制指定。
- **关闭伪装（`disable_spoofing`）**：仅在传入指纹种子时有意义。可用值为 `font,audio,canvas,clientrects,gpu`，多个值用逗号分隔；留空表示全部开启。
- **旧配置兼容**：没有 `use_fingerprint` 字段时，`fingerprint` 默认开启指纹，`chrome` / `edge` 默认关闭。

### PowerShell 版首次运行检查

首次在 Windows 上运行可视化版时，请确认：选择 `fingerprint` 后指纹开关出现；开关关闭时指纹参数折叠，打开时展开；浏览器 exe 路径始终可见。

种子留空时，PowerShell 版和跨平台版的启动日志应一致。校验值：配置名 `HK_chromium` 对应种子 `-1744200419`。

### 指纹排查记录

Windows 上 fingerprint 150 曾多次出现 `Aw Snap` / `Crashpad_NotConnectedToHandler`，但重复测试结果不一致；时区、种子、画布和元素尺寸等原因都没有复现，目前没有可靠结论。曾有一次用户报告以下参数组合可以正常打开百度页，之后确认起作用的是 `--disable-spoofing=gpu`：

```text
--fingerprint=2023 --fingerprint-platform=windows --disable-spoofing=gpu
```

GPU 伪装可能向浏览器提供显卡无法兑现的参数，导致页面调用 WebGL 时渲染进程崩溃；关闭 GPU 伪装后浏览器会报告真实显卡参数。复测时请使用全新数据目录、彻底退出浏览器，并确认同一组参数连续两次结果一致。

**检查 GPU 伪装**：按 F12 打开 Console，读取 `UNMASKED_VENDOR_WEBGL` / `UNMASKED_RENDERER_WEBGL`，并与任务管理器“性能 → GPU”中的显卡名称比较。也可以换一个指纹种子：输出不变通常表示使用真实显卡信息，输出随种子变化则表示仍在伪装。

**检查时区**：在 fingerprint 浏览器的 Console 中运行 `Intl.DateTimeFormat().resolvedOptions().timeZone`，结果应与配置的时区一致。

示例里的代理地址是占位符（你的服务器IP），用前改成自己的代理地址。带账号密码的 SOCKS5 代理，浏览器第一次启动时会弹窗让填账号密码。

## 默认打开的网站

可视化版和跨平台版默认每个配置先打开 https://ippure.com/ （测 IP 纯净度），再开配置里的其他网址；不想要的话在界面里编辑删掉即可。
