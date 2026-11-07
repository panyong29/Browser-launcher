#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
浏览器多配置代理启动器（跨平台版：Windows / macOS / Linux 图形界面）

一个配置 = 一个浏览器 + 一个代理 + 一组网址，
每个配置用独立的用户数据目录启动，互不干扰。

界面用各系统自带的 tkinter（macOS 上是 Cocoa 原生窗口，
Linux 上走 Tk），不用额外装 Qt 之类的库。

运行：
    python browser-launcher.py
    （Windows 上用 python / py，不要用 python3，那是应用商店占位程序）

配置存在 profiles.json（和脚本放同一目录），
和 Windows 的 PowerShell 版是同一套格式，两个版本可以共用这个文件。
第一次运行没有 profiles.json 时，会按默认配置自动生成一个。
每个配置可再填两个字段（留空 = 跟系统）：
    lang：启动语言，如 en-US、zh-CN，会同时传 --lang 和 --accept-lang
    timezone：启动时区，IANA 名字，如 America/New_York、Asia/Shanghai、UTC
注意：原版 Chrome / Edge 没有 --timezone 参数，时区默认跟系统。
Linux / macOS 下本脚本用 TZ 环境变量给子进程传时区，能生效；
Windows 下 TZ 对图形程序不起作用，填了时区也只会在日志里提醒、
不会假装已生效——Windows 上要改时区请改系统时区，或在浏览器里
用开发者工具 Sensors 按标签页覆盖。
浏览器选 fingerprint（改过的 fingerprint-chromium）时例外：
它自带 --timezone 补丁，启动时传 --fingerprint=<种子> --timezone=<时区>，
Windows 下也能生效；exe 路径填在“浏览器 exe 路径”那格，
留空时按常见 Chromium 安装位置自动找。
注意（2026-11-04 用户 Windows 实测）：fingerprint 150 版单加 --fingerprint
就会在百度页触发 Aw Snap / Crashpad_NotConnectedToHandler；手动测试结果
不稳定，二次测试结果完全不同，画布/元素尺寸等结论均未复现，
不要当成定论；“关闭伪装”格只是用来复测的工具。
用户 2026-11-04 报告能用的组合：--fingerprint=2023
--fingerprint-platform=windows --disable-spoofing=gpu
--proxy-server=socks5://127.0.0.1:10808，百度页能开（仅该次报告，
未在启动器里复测语言/时区叠加后的情况）。
因此 fingerprint 配置多了一个“关闭伪装”格，可填
clientrects、canvas、font、gpu、audio 等逗号分隔的值作复测，启动时传 --disable-spoofing=<值>；时区本身不是
祸首（带时区的全套 D 也能开），不要只盯时区。
--fingerprint 必须带一个 32 位整数种子，裸传 --fingerprint 是错的；
指纹开关（use_fingerprint）关了就不传 --fingerprint，只用语言/
时区/代理（2026-11-04 用户要求：只为设置语言和时区，不想开任何
伪装时就关开关）；开关开了才传 --fingerprint，种子留空时按配置名
自动生成一个固定种子，填错格式时也按配置名回落。

macOS 注意：请用官网或 Homebrew 装的 Python 3，
系统自带的 /usr/bin/python3 没有 tkinter，跑不起来。
Linux 注意：如果提示找不到 tkinter，Ubuntu/Debian 装 python3-tk：
    sudo apt install python3-tk
"""

import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import time
import zlib

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError:
    print("找不到 tkinter：macOS 请用官网或 Homebrew 的 Python 3；"
          "Linux（Ubuntu/Debian）请执行 sudo apt install python3-tk")
    sys.exit(1)

# ---------------- 默认配置（只在没有 profiles.json 时用一次） ----------------
if platform.system() == "Windows":
    DEFAULT_BASE_DIR = r"D:\browser-launcher"
else:
    DEFAULT_BASE_DIR = os.path.join(os.path.expanduser("~"), "browser-launcher")

DEFAULT_PROFILES = [
    {"name": "VPS美国", "browser": "chrome", "proxy": "socks5://你的服务器IP:1080",
     "browser_path": "", "use_fingerprint": False, "auto_start": False, "fingerprint_seed": "", "fingerprint_platform": "", "disable_spoofing": "", "lang": "", "timezone": "",
     "urls": ["https://ippure.com/", "https://www.google.com", "https://www.youtube.com"]},
    {"name": "本地10808", "browser": "chrome", "proxy": "socks5://127.0.0.1:10808",
     "browser_path": "", "use_fingerprint": False, "auto_start": False, "fingerprint_seed": "", "fingerprint_platform": "", "disable_spoofing": "", "lang": "", "timezone": "",
     "urls": ["https://ippure.com/", "https://x.com"]},
    {"name": "Edge直连", "browser": "edge", "proxy": "",
     "browser_path": "", "use_fingerprint": False, "auto_start": False, "fingerprint_seed": "", "fingerprint_platform": "", "disable_spoofing": "", "lang": "", "timezone": "",
     "urls": ["https://ippure.com/", "https://www.bing.com"]},
]
# ---------------- 默认配置结束 ----------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "profiles.json")

base_dir = DEFAULT_BASE_DIR
profiles = [dict(p, urls=list(p["urls"])) for p in DEFAULT_PROFILES]


def sanitize(name):
    """配置名用作目录名时，去掉各系统都不允许的字符。"""
    return re.sub(r'[\\/:*?"<>|]', "_", name)


def find_browser(browser, browser_path=""):
    """按当前系统找浏览器可执行文件，找不到返回 None。
    browser_path 填了且文件存在时优先用它（fingerprint-chromium 的
    安装位置不固定，靠这格最稳）。"""
    if browser_path and os.path.exists(browser_path):
        return browser_path
    system = platform.system()
    if system == "Windows":
        pf = os.environ.get("ProgramFiles", r"C:\Program Files")
        pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
        local = os.environ.get("LOCALAPPDATA", "")
        if browser == "chrome":
            candidates = [
                os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
                os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"),
            ]
        elif browser == "fingerprint":
            candidates = [
                os.path.join(local, "Chromium", "Application", "chrome.exe"),
                os.path.join(pf, "Chromium", "Application", "chrome.exe"),
                os.path.join(pf86, "Chromium", "Application", "chrome.exe"),
            ]
        else:
            candidates = [
                os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
                os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
            ]
        for path in candidates:
            if path and os.path.exists(path):
                return path
        return shutil.which("chrome" if browser in ("chrome", "fingerprint") else "msedge")
    if system == "Darwin":
        if browser == "chrome":
            path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        elif browser == "fingerprint":
            path = "/Applications/Chromium.app/Contents/MacOS/Chromium"
        else:
            path = "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
        return path if os.path.exists(path) else None
    # Linux
    if browser == "chrome":
        for cmd in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
            path = shutil.which(cmd)
            if path:
                return path
    elif browser == "fingerprint":
        for cmd in ("chromium", "chromium-browser", "ungoogled-chromium"):
            path = shutil.which(cmd)
            if path:
                return path
    else:
        for cmd in ("microsoft-edge", "microsoft-edge-stable"):
            path = shutil.which(cmd)
            if path:
                return path
    return None


def normalize_profile(raw):
    """读进来的配置缺字段时补齐，保证后面不报错。"""
    return {
        "name": str(raw.get("name", "")),
        "browser": raw.get("browser", "chrome") if raw.get("browser") in ("chrome", "edge", "fingerprint") else "chrome",
        "browser_path": str(raw.get("browser_path", "") or "").strip(),
        "use_fingerprint": raw["use_fingerprint"] if isinstance(raw.get("use_fingerprint"), bool) else (raw.get("browser") == "fingerprint"),
        "fingerprint_seed": str(raw.get("fingerprint_seed", "") or "").strip(),
        "disable_spoofing": str(raw.get("disable_spoofing", "") or "").strip(),
        "fingerprint_platform": str(raw.get("fingerprint_platform", "") or "").strip(),
        "proxy": str(raw.get("proxy", "")),
        "lang": str(raw.get("lang", "") or "").strip(),
        "timezone": str(raw.get("timezone", "") or "").strip(),
        "auto_start": bool(raw.get("auto_start", False)),
        "urls": [str(u) for u in raw.get("urls", []) if str(u).strip()],
    }


def _autostart_command():
    """Return the command used to start this GUI app at user login."""
    executable = sys.executable
    if os.name == "nt" and os.path.basename(executable).lower() == "python.exe":
        pythonw = os.path.join(os.path.dirname(executable), "pythonw.exe")
        if os.path.isfile(pythonw):
            executable = pythonw
    return [executable, os.path.abspath(__file__)]


def _autostart_paths():
    if sys.platform == "darwin":
        path = os.path.expanduser("~/Library/LaunchAgents/com.browserlauncher.app.plist")
    elif os.name == "nt":
        return None
    else:
        path = os.path.expanduser("~/.config/autostart/browser-launcher.desktop")
    return path


def is_launcher_autostart_enabled():
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                                r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
                value, _ = winreg.QueryValueEx(key, "BrowserLauncherPython")
            expected = '"%s" "%s"' % tuple(_autostart_command())
            return value.lower() == expected.lower()
        except (OSError, ImportError):
            return False
    path = _autostart_paths()
    if not os.path.isfile(path):
        return False
    if sys.platform == "darwin":
        try:
            with open(path, "rb") as f:
                data = plistlib.load(f)
            return data.get("ProgramArguments") == _autostart_command()
        except Exception:
            return False
    try:
        with open(path, "r", encoding="utf-8") as f:
            return os.path.abspath(__file__) in f.read()
    except OSError:
        return False


def set_launcher_autostart(enabled):
    """Register/unregister this launcher for the current user's next login."""
    command = _autostart_command()
    if os.name == "nt":
        import winreg
        key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
        with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, key_path, 0,
                                winreg.KEY_SET_VALUE) as key:
            if enabled:
                winreg.SetValueEx(key, "BrowserLauncherPython", 0, winreg.REG_SZ,
                                  '"%s" "%s"' % tuple(command))
            else:
                try:
                    winreg.DeleteValue(key, "BrowserLauncherPython")
                except FileNotFoundError:
                    pass
        return

    path = _autostart_paths()
    if sys.platform == "darwin":
        domain = "gui/%d" % os.getuid()
        if enabled:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            data = {
                "Label": "com.browserlauncher.app",
                "ProgramArguments": command,
                "WorkingDirectory": SCRIPT_DIR,
                "RunAtLoad": True,
            }
            with open(path, "wb") as f:
                plistlib.dump(data, f)
            subprocess.run(["launchctl", "bootout", domain, path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            result = subprocess.run(["launchctl", "bootstrap", domain, path],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if result.returncode:
                raise OSError(result.stderr.strip() or "launchctl bootstrap 失败")
        else:
            subprocess.run(["launchctl", "bootout", domain, path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        return

    os.makedirs(os.path.dirname(path), exist_ok=True)
    if enabled:
        def desktop_quote(arg):
            return '"%s"' % (arg.replace("\\", "\\\\").replace('"', '\\"')
                             .replace("`", "\\`").replace("$", "\\$").replace("%", "%%"))
        content = "\n".join([
            "[Desktop Entry]", "Type=Application", "Name=Browser Launcher",
            "Exec=" + " ".join(desktop_quote(arg) for arg in command),
            "Terminal=false", "X-GNOME-Autostart-enabled=true", "",
        ])
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    else:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def load_config():
    """返回 True 表示读到了现成的 profiles.json，False 表示用了默认配置。"""
    global base_dir, profiles
    if not os.path.exists(CONFIG_PATH):
        return False
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("profiles"), list) and data["profiles"]:
            profiles = [normalize_profile(p) for p in data["profiles"]]
            if data.get("baseDir"):
                base_dir = str(data["baseDir"])
            return True
    except Exception:
        pass
    return False


def save_config():
    data = {"baseDir": base_dir, "profiles": profiles}
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


# ---------------- 界面 ----------------
log_text = None
tree = None
base_dir_var = None


def write_log(msg):
    line = time.strftime("%H:%M:%S") + "  " + msg + "\n"
    log_text.configure(state="normal")
    log_text.insert("end", line)
    log_text.see("end")
    log_text.configure(state="disabled")


def refresh_list():
    for item in tree.get_children():
        tree.delete(item)
    for i, p in enumerate(profiles):
        tree.insert("", "end", iid=str(i), values=(
            p["name"], p["browser"], p["proxy"] if p["proxy"] else "直连",
            p.get("lang", "") or "跟系统", p.get("timezone", "") or "跟系统",
            len(p["urls"])))


def get_selected():
    selected = tree.selection()
    if not selected:
        return None
    return profiles[int(selected[0])]


def fingerprint_seed_for(p):
    """fingerprint-chromium 的 --fingerprint 必须带 32 位整数种子。
    填了就用填的；留空或填错格式时，按配置名用 CRC32 生成一个
    固定种子，同一配置每次都一样。开关关了时启动不调用它。"""
    raw = p.get("fingerprint_seed", "").strip()
    if raw:
        try:
            value = int(raw)
            if -2147483648 <= value <= 2147483647:
                return value
        except ValueError:
            pass
    crc = zlib.crc32(p["name"].encode("utf-8")) & 0xFFFFFFFF
    if crc > 2147483647:
        crc -= 4294967296
    return crc


def launch_profile(p):
    exe = find_browser(p["browser"], p.get("browser_path", ""))
    if not exe:
        write_log("[!] 没找到 %s，跳过 [%s]（请在编辑里填浏览器 exe 路径）" % (p["browser"], p["name"]))
        return
    data_dir = os.path.join(base_dir, "%s-%s" % (p["browser"], sanitize(p["name"])))
    args = [exe, "--user-data-dir=" + data_dir, "--no-first-run"]
    use_fp = p["browser"] == "fingerprint" and bool(p.get("use_fingerprint", False))
    if use_fp:
        args.append("--fingerprint=" + str(fingerprint_seed_for(p)))
        disable_spoofing = p.get("disable_spoofing", "").strip()
        if disable_spoofing:
            args.append("--disable-spoofing=" + disable_spoofing)
        fingerprint_platform = p.get("fingerprint_platform", "").strip()
        if fingerprint_platform:
            args.append("--fingerprint-platform=" + fingerprint_platform)
    if p["proxy"]:
        args.append("--proxy-server=" + p["proxy"])
    lang = p.get("lang", "").strip()
    if lang:
        args.append("--lang=" + lang)
        args.append("--accept-lang=" + lang)
    timezone = p.get("timezone", "").strip()
    kwargs = {}
    if os.name == "posix":
        kwargs["start_new_session"] = True
    if timezone:
        if p["browser"] == "fingerprint":
            # fingerprint-chromium 自带 --timezone 补丁，各系统都传这个。
            args.append("--timezone=" + timezone)
        elif os.name == "posix":
            env = dict(os.environ)
            env["TZ"] = timezone
            kwargs["env"] = env
        else:
            # Windows 下原版 Chrome / Edge 不认 --timezone，TZ 也不起作用，
            # 不加假参数，只在日志里明说，避免用户以为已生效。
            write_log("[!] [%s] Windows 下时区仍跟系统，填的时区 %s 未生效" % (p["name"], timezone))
    log_parts = ["启动 [%s] %s，代理：%s" % (p["name"], p["browser"], p["proxy"] if p["proxy"] else "直连")]
    if p["browser"] == "fingerprint":
        if use_fp:
            log_parts.append("指纹种子：%s" % fingerprint_seed_for(p))
            disable_spoofing = p.get("disable_spoofing", "").strip()
            if disable_spoofing:
                log_parts.append("关闭伪装：%s" % disable_spoofing)
        else:
            log_parts.append("指纹：关（只用语言/时区）")
    if lang:
        log_parts.append("语言：%s" % lang)
    if timezone and (p["browser"] == "fingerprint" or os.name == "posix"):
        log_parts.append("时区：%s" % timezone)
    write_log("，".join(log_parts))
    for i, url in enumerate(p["urls"]):
        uargs = args + (["--new-window", url] if i == 0 else [url])
        try:
            subprocess.Popen(uargs,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)
        except Exception as e:
            write_log("[!] 启动失败 [%s]：%s" % (p["name"], e))
            return
        time.sleep(1.5 if i == 0 else 0.8)
    write_log("完成 [%s]，1 个窗口、%d 个标签页" % (p["name"], len(p["urls"])))


def profile_dialog(parent, p):
    """新增/编辑配置的弹窗。点保存返回 True（p 已就地改好），点取消返回 False。"""
    dlg = tk.Toplevel(parent)
    dlg.title("编辑配置" if p["name"] else "新增配置")
    dlg.resizable(False, False)
    dlg.transient(parent)
    dlg.grab_set()

    tk.Label(dlg, text="名字：").grid(row=0, column=0, sticky="e", padx=10, pady=8)
    name_entry = tk.Entry(dlg, width=48)
    name_entry.insert(0, p["name"])
    name_entry.grid(row=0, column=1, padx=10, pady=8)

    tk.Label(dlg, text="浏览器：").grid(row=1, column=0, sticky="e", padx=10, pady=8)
    browser_box = ttk.Combobox(dlg, values=["chrome", "edge", "fingerprint"], state="readonly", width=46)
    browser_box.set(p["browser"] if p["browser"] in ("chrome", "edge", "fingerprint") else "chrome")
    browser_box.grid(row=1, column=1, padx=10, pady=8)

    tk.Label(dlg, text="代理：").grid(row=2, column=0, sticky="e", padx=10, pady=8)
    proxy_entry = tk.Entry(dlg, width=48)
    proxy_entry.insert(0, p["proxy"])
    proxy_entry.grid(row=2, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(留空 = 直连，例如 socks5://127.0.0.1:10808)").grid(
        row=3, column=1, sticky="w", padx=10)

    tk.Label(dlg, text="启动语言：").grid(row=4, column=0, sticky="e", padx=10, pady=8)
    lang_entry = tk.Entry(dlg, width=48)
    lang_entry.insert(0, p.get("lang", ""))
    lang_entry.grid(row=4, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(留空 = 跟系统，例如 en-US、zh-CN)").grid(
        row=5, column=1, sticky="w", padx=10)

    tk.Label(dlg, text="启动时区：").grid(row=6, column=0, sticky="e", padx=10, pady=8)
    timezone_entry = tk.Entry(dlg, width=48)
    timezone_entry.insert(0, p.get("timezone", ""))
    timezone_entry.grid(row=6, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(留空 = 跟系统，例如 America/New_York、Asia/Shanghai；Windows 下原版浏览器不认时区，仍跟系统；fingerprint 崩了先看关闭伪装那格)").grid(
        row=7, column=1, sticky="w", padx=10)

    tk.Label(dlg, text="网址：").grid(row=8, column=0, sticky="ne", padx=10, pady=8)
    urls_text = tk.Text(dlg, width=48, height=8)
    urls_text.insert("1.0", "\n".join(p["urls"]))
    urls_text.grid(row=8, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(每行一个网址，第一个开新窗口，后面的开成标签页)").grid(
        row=9, column=1, sticky="w", padx=10)

    follow_start_var = tk.BooleanVar(value=bool(p.get("auto_start", False)))
    tk.Label(dlg, text="启动选项：").grid(row=10, column=0, sticky="e", padx=10, pady=8)
    tk.Checkbutton(dlg, text="跟随启动器启动此浏览器配置", variable=follow_start_var).grid(
        row=10, column=1, sticky="w", padx=10, pady=8)

    # 指纹开关：只有浏览器选了 fingerprint 时才显示；开了才展开下面参数。
    use_fp_var = tk.BooleanVar(value=bool(p.get("use_fingerprint", False)))
    fp_switch_label = tk.Label(dlg, text="指纹开关：")
    fp_switch_label.grid(row=12, column=0, sticky="e", padx=10, pady=8)
    fp_switch = tk.Checkbutton(dlg, text="使用指纹（fingerprint-chromium）", variable=use_fp_var)
    fp_switch.grid(row=12, column=1, sticky="w", padx=10, pady=8)
    fp_switch_hint = tk.Label(dlg, text="(关 = 不传指纹，只用语言/时区；开 = 展开下面参数)")
    fp_switch_hint.grid(row=13, column=1, sticky="w", padx=10)

    fp_detail_widgets = []
    def _fp_row(label_text, entry, hint_text, row):
        lab = tk.Label(dlg, text=label_text)
        lab.grid(row=row, column=0, sticky="e", padx=10, pady=8)
        entry.grid(row=row, column=1, padx=10, pady=8)
        hint = tk.Label(dlg, text=hint_text)
        hint.grid(row=row + 1, column=1, sticky="w", padx=10)
        fp_detail_widgets.extend([lab, entry, hint])

    # 浏览器 exe 路径是通用字段，不是只属于指纹：find_browser 对 chrome /
    # edge / fingerprint 都是“填了且文件存在就优先用它”，所以它永远显示，
    # 不跟指纹开关一起收起（开关关了只用语言/时区时，仍要靠它找 fingerprint exe）。
    browser_path_entry = tk.Entry(dlg, width=48)
    browser_path_entry.insert(0, p.get("browser_path", ""))
    tk.Label(dlg, text="浏览器 exe 路径：").grid(row=14, column=0, sticky="e", padx=10, pady=8)
    browser_path_entry.grid(row=14, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(留空自动找；fingerprint-chromium 安装位置不固定，填它自己的 exe 最稳；例如 C:\\Chromium\\Application\\chrome.exe)").grid(
        row=15, column=1, sticky="w", padx=10)

    fingerprint_seed_entry = tk.Entry(dlg, width=48)
    fingerprint_seed_entry.insert(0, p.get("fingerprint_seed", ""))
    _fp_row("指纹种子：", fingerprint_seed_entry,
            "(仅 fingerprint 用，32 位整数；留空按配置名自动生成固定种子)", 16)

    disable_spoofing_entry = tk.Entry(dlg, width=48)
    disable_spoofing_entry.insert(0, p.get("disable_spoofing", ""))
    _fp_row("关闭伪装：", disable_spoofing_entry,
            "(仅 fingerprint 用，逗号分隔，如 font,audio,canvas,clientrects,gpu；留空 = 全开)", 18)

    fingerprint_platform_entry = tk.Entry(dlg, width=48)
    fingerprint_platform_entry.insert(0, p.get("fingerprint_platform", ""))
    _fp_row("操作系统：", fingerprint_platform_entry,
            "(仅 fingerprint 用，如 windows、linux、macos；留空 = 种子随机生成)", 20)

    def refresh_fp():
        is_fp = browser_box.get() == "fingerprint"
        for w in (fp_switch_label, fp_switch, fp_switch_hint):
            if is_fp:
                w.grid()
            else:
                w.grid_remove()
        show_detail = is_fp and use_fp_var.get()
        for w in fp_detail_widgets:
            if show_detail:
                w.grid()
            else:
                w.grid_remove()

    browser_box.bind("<<ComboboxSelected>>", lambda e: refresh_fp())
    fp_switch.configure(command=refresh_fp)
    refresh_fp()

    result = {"ok": False}

    def on_save():
        if not name_entry.get().strip():
            messagebox.showwarning("提示", "名字不能为空。", parent=dlg)
            return
        p["name"] = name_entry.get().strip()
        p["browser"] = browser_box.get()
        p["use_fingerprint"] = bool(use_fp_var.get())
        p["browser_path"] = browser_path_entry.get().strip()
        p["fingerprint_seed"] = fingerprint_seed_entry.get().strip()
        p["fingerprint_platform"] = fingerprint_platform_entry.get().strip()
        p["disable_spoofing"] = disable_spoofing_entry.get().strip()
        p["proxy"] = proxy_entry.get().strip()
        p["lang"] = lang_entry.get().strip()
        p["timezone"] = timezone_entry.get().strip()
        p["auto_start"] = bool(follow_start_var.get())
        p["urls"] = [line.strip() for line in urls_text.get("1.0", "end").splitlines()
                     if line.strip()]
        result["ok"] = True
        dlg.destroy()

    btn_frame = tk.Frame(dlg)
    btn_frame.grid(row=22, column=1, sticky="e", padx=10, pady=12)
    tk.Button(btn_frame, text="保存", width=10, command=on_save).pack(side="left", padx=4)
    tk.Button(btn_frame, text="取消", width=10, command=dlg.destroy).pack(side="left", padx=4)

    name_entry.focus_set()
    dlg.wait_window()
    return result["ok"]


def main():
    global log_text, tree, base_dir_var, base_dir

    loaded = load_config()
    if not loaded:
        save_config()

    root = tk.Tk()
    root.title("浏览器多配置代理启动器")
    root.geometry("860x620")
    root.minsize(820, 580)

    tk.Label(root, text="配置从 profiles.json 读取（和脚本放同一目录）。双击一行可直接启动。"
             ).pack(anchor="w", padx=15, pady=(12, 6))

    tree = ttk.Treeview(root, columns=("name", "browser", "proxy", "lang", "timezone", "count"), show="headings")
    tree.heading("name", text="名字")
    tree.heading("browser", text="浏览器")
    tree.heading("proxy", text="代理")
    tree.heading("lang", text="启动语言")
    tree.heading("timezone", text="启动时区")
    tree.heading("count", text="网址数")
    tree.column("name", width=120)
    tree.column("browser", width=80)
    tree.column("proxy", width=260)
    tree.column("lang", width=80)
    tree.column("timezone", width=130)
    tree.column("count", width=60)
    tree.pack(fill="both", expand=True, padx=15)
    tree.bind("<Double-1>", lambda e: launch_profile(get_selected()) if get_selected() else None)

    def need_selection():
        p = get_selected()
        if not p:
            messagebox.showwarning("提示", "请先选中一个配置。", parent=root)
        return p

    def on_launch_selected():
        p = need_selection()
        if p:
            launch_profile(p)

    def on_launch_all():
        for p in list(profiles):
            launch_profile(p)

    def on_add():
        new_profile = {"name": "", "browser": "chrome", "proxy": "", "browser_path": "", "use_fingerprint": False, "fingerprint_seed": "", "fingerprint_platform": "", "disable_spoofing": "", "lang": "", "timezone": "", "auto_start": False, "urls": []}
        if profile_dialog(root, new_profile):
            profiles.append(new_profile)
            save_config()
            refresh_list()
            write_log("新增配置 [%s]" % new_profile["name"])

    def on_edit():
        p = need_selection()
        if p and profile_dialog(root, p):
            save_config()
            refresh_list()
            write_log("已修改配置 [%s]" % p["name"])

    def on_delete():
        p = need_selection()
        if not p:
            return
        if len(profiles) <= 1:
            messagebox.showwarning("提示", "至少保留一个配置。", parent=root)
            return
        if messagebox.askyesno("确认", "确定删除 [%s] 吗？" % p["name"], parent=root):
            profiles.remove(p)
            save_config()
            refresh_list()
            write_log("已删除配置 [%s]" % p["name"])

    btn_row = tk.Frame(root)
    btn_row.pack(fill="x", padx=15, pady=(10, 4))
    for text, cmd in (("启动选中", on_launch_selected), ("全部启动", on_launch_all),
                      ("新增", on_add), ("编辑", on_edit), ("删除", on_delete)):
        tk.Button(btn_row, text=text, width=12, command=cmd).pack(side="left", padx=3)

    autostart_row = tk.Frame(root)
    autostart_row.pack(fill="x", padx=15, pady=3)
    autostart_var = tk.BooleanVar(value=is_launcher_autostart_enabled())

    def on_toggle_autostart():
        try:
            set_launcher_autostart(autostart_var.get())
            write_log("已启用登录时启动启动器" if autostart_var.get() else "已关闭登录时启动启动器")
        except Exception as e:
            autostart_var.set(is_launcher_autostart_enabled())
            messagebox.showerror("设置失败", str(e), parent=root)

    tk.Checkbutton(autostart_row, text="登录时启动启动器（勾选的浏览器配置也会随启动器启动）",
                   variable=autostart_var, command=on_toggle_autostart).pack(side="left")

    dir_row = tk.Frame(root)
    dir_row.pack(fill="x", padx=15, pady=4)
    tk.Label(dir_row, text="数据目录：").pack(side="left")
    base_dir_var = tk.StringVar(value=base_dir)
    dir_entry = tk.Entry(dir_row, textvariable=base_dir_var, width=52)
    dir_entry.pack(side="left", padx=4)

    def apply_base_dir():
        global base_dir
        new_dir = base_dir_var.get().strip()
        if new_dir and new_dir != base_dir:
            base_dir = new_dir
            save_config()
            write_log("数据目录改为 %s" % base_dir)

    dir_entry.bind("<FocusOut>", lambda e: apply_base_dir())

    def on_browse_dir():
        picked = filedialog.askdirectory(initialdir=base_dir, parent=root)
        if picked:
            base_dir_var.set(picked)
            apply_base_dir()

    tk.Button(dir_row, text="浏览…", command=on_browse_dir).pack(side="left", padx=4)

    io_row = tk.Frame(root)
    io_row.pack(fill="x", padx=15, pady=4)

    def on_import():
        path = filedialog.askopenfilename(
            parent=root, title="导入配置",
            filetypes=[("JSON 文件", "*.json"), ("所有文件", "*.*")])
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and isinstance(data.get("profiles"), list):
                imported = [normalize_profile(p) for p in data["profiles"]]
                imported_base = data.get("baseDir")
            elif isinstance(data, list):
                imported = [normalize_profile(p) for p in data]
                imported_base = None
            else:
                raise ValueError("文件里没有可用的配置")
            if not imported:
                raise ValueError("文件里没有可用的配置")
            if not messagebox.askyesno(
                    "确认导入", "导入 %d 个配置，并替换当前列表，确定吗？" % len(imported),
                    parent=root):
                return
            profiles.clear()
            profiles.extend(imported)
            if imported_base:
                base_dir_var.set(str(imported_base))
                apply_base_dir()
            save_config()
            refresh_list()
            write_log("已导入 %d 个配置" % len(imported))
        except Exception as e:
            messagebox.showerror("导入失败", str(e), parent=root)

    def on_export():
        path = filedialog.asksaveasfilename(
            parent=root, title="导出配置", initialfile="profiles.json",
            initialdir=SCRIPT_DIR, defaultextension=".json",
            filetypes=[("JSON 文件", "*.json")])
        if not path:
            return
        data = {"baseDir": base_dir, "profiles": profiles}
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        write_log("已导出到 %s" % path)

    tk.Button(io_row, text="导入配置", width=12, command=on_import).pack(side="left", padx=3)
    tk.Button(io_row, text="导出配置", width=12, command=on_export).pack(side="left", padx=3)
    tk.Label(io_row, text="配置文件：profiles.json（与脚本同目录）").pack(side="left", padx=10)

    log_text = tk.Text(root, height=7, state="disabled")
    log_text.pack(fill="both", expand=True, padx=15, pady=(8, 12))

    refresh_list()
    if loaded:
        write_log("已读取配置：%s，共 %d 个" % (CONFIG_PATH, len(profiles)))
    else:
        write_log("没有找到 profiles.json，已按默认配置生成一个")
    write_log("当前系统：%s，配置文件与 Windows 版通用" % platform.system())

    def start_marked_profiles():
        marked = [p for p in profiles if p.get("auto_start", False)]
        if marked:
            write_log("启动已勾选的浏览器配置：%d 个" % len(marked))
            for p in marked:
                launch_profile(p)

    root.after(300, start_marked_profiles)
    root.mainloop()


if __name__ == "__main__":
    main()
