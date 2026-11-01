# Browser-launcher

Windows / macOS / Linux 用的 Chrome / Edge 多配置代理启动器：一个配置 = 一个浏览器 + 一个代理 + 一组网址，每个配置用独立的用户数据目录启动，互不干扰。同一配置的多个网址：第一个开新窗口，后面的开成这个窗口的标签页。

## 版本

- browser-launcher.ps1：命令行版（Windows PowerShell），菜单选编号启动
- browser-launcher-gui.ps1：图形界面版（Windows），每配置一个按钮
- browser-launcher-visual.ps1：可视化配置版（Windows，推荐），配置存在 profiles.json，界面里可新增、编辑、删除、导入、导出
- browser-launcher.py：跨平台版（Windows / macOS / Linux），界面用各系统自带的 tkinter，功能与可视化配置版相同

## 运行

Windows PowerShell 版：

    powershell -ExecutionPolicy Bypass -File .\browser-launcher-visual.ps1

跨平台版：

    python3 browser-launcher.py

macOS 请用官网或 Homebrew 装的 Python 3，系统自带的 /usr/bin/python3 没有 tkinter；Linux 缺 tkinter 时，Ubuntu/Debian 执行 sudo apt install python3-tk。

PowerShell 版是 UTF-8 带 BOM 编码，Windows PowerShell 5.1 可直接运行；用记事本改完另存时保持 UTF-8 编码。

## 配置

profiles.json 是示例配置，和 PowerShell 版格式通用，两个版本可以共用：

- baseDir：各配置的用户数据目录存放位置
- 每个配置：名字、浏览器（chrome / edge）、代理（留空 = 直连）、网址（第一个开新窗口，后面的开成标签页）

示例里的代理地址是占位符（你的服务器IP），用前改成自己的代理地址。带账号密码的 SOCKS5 代理，浏览器第一次启动时会弹窗让填账号密码。

## 默认打开的网站

可视化版和跨平台版默认每个配置先打开 https://ippure.com/（测 IP 纯净度），再开配置里的其他网址；不想要的话在界面里编辑删掉即可。
