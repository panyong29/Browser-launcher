#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
浏览器多配置代理启动器（跨平台版：Windows / macOS / Linux 图形界面）

一个配置 = 一个浏览器 + 一个代理 + 一组网址，
每个配置用独立的用户数据目录启动，互不干扰。

界面用各系统自带的 tkinter（macOS 上是 Cocoa 原生窗口，
Linux 上走 Tk），不用额外装 Qt 之类的库。

运行：
    python3 browser-launcher.py

配置存在 profiles.json（和脚本放同一目录），
和 Windows 的 PowerShell 版是同一套格式，两个版本可以共用这个文件。
第一次运行没有 profiles.json 时，会按默认配置自动生成一个。

macOS 注意：请用官网或 Homebrew 装的 Python 3，
系统自带的 /usr/bin/python3 没有 tkinter，跑不起来。
Linux 注意：如果提示找不到 tkinter，Ubuntu/Debian 装 python3-tk：
    sudo apt install python3-tk
"""

import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time

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
     "urls": ["https://ippure.com/", "https://www.google.com", "https://www.youtube.com"]},
    {"name": "本地10808", "browser": "chrome", "proxy": "socks5://127.0.0.1:10808",
     "urls": ["https://ippure.com/", "https://x.com"]},
    {"name": "Edge直连", "browser": "edge", "proxy": "",
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


def find_browser(browser):
    """按当前系统找 Chrome / Edge 的可执行文件，找不到返回 None。"""
    system = platform.system()
    if system == "Windows":
        pf = os.environ.get("ProgramFiles", r"C:\Program Files")
        pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
        if browser == "chrome":
            candidates = [
                os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
                os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"),
            ]
        else:
            candidates = [
                os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
                os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
            ]
        for path in candidates:
            if os.path.exists(path):
                return path
        return shutil.which("chrome" if browser == "chrome" else "msedge")
    if system == "Darwin":
        if browser == "chrome":
            path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        else:
            path = "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
        return path if os.path.exists(path) else None
    # Linux
    if browser == "chrome":
        for cmd in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
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
        "browser": raw.get("browser", "chrome") if raw.get("browser") in ("chrome", "edge") else "chrome",
        "proxy": str(raw.get("proxy", "")),
        "urls": [str(u) for u in raw.get("urls", []) if str(u).strip()],
    }


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
            p["name"], p["browser"], p["proxy"] if p["proxy"] else "直连", len(p["urls"])))


def get_selected():
    selected = tree.selection()
    if not selected:
        return None
    return profiles[int(selected[0])]


def launch_profile(p):
    exe = find_browser(p["browser"])
    if not exe:
        write_log("[!] 没找到 %s，跳过 [%s]" % (p["browser"], p["name"]))
        return
    data_dir = os.path.join(base_dir, "%s-%s" % (p["browser"], sanitize(p["name"])))
    args = [exe, "--user-data-dir=" + data_dir, "--no-first-run"]
    if p["proxy"]:
        args.append("--proxy-server=" + p["proxy"])
    write_log("启动 [%s] %s，代理：%s" % (p["name"], p["browser"], p["proxy"] if p["proxy"] else "直连"))
    kwargs = {}
    if os.name == "posix":
        kwargs["start_new_session"] = True
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
    browser_box = ttk.Combobox(dlg, values=["chrome", "edge"], state="readonly", width=46)
    browser_box.set(p["browser"])
    browser_box.grid(row=1, column=1, padx=10, pady=8)

    tk.Label(dlg, text="代理：").grid(row=2, column=0, sticky="e", padx=10, pady=8)
    proxy_entry = tk.Entry(dlg, width=48)
    proxy_entry.insert(0, p["proxy"])
    proxy_entry.grid(row=2, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(留空 = 直连，例如 socks5://127.0.0.1:10808)").grid(
        row=3, column=1, sticky="w", padx=10)

    tk.Label(dlg, text="网址：").grid(row=4, column=0, sticky="ne", padx=10, pady=8)
    urls_text = tk.Text(dlg, width=48, height=8)
    urls_text.insert("1.0", "\n".join(p["urls"]))
    urls_text.grid(row=4, column=1, padx=10, pady=8)
    tk.Label(dlg, text="(每行一个网址，第一个开新窗口，后面的开成标签页)").grid(
        row=5, column=1, sticky="w", padx=10)

    result = {"ok": False}

    def on_save():
        if not name_entry.get().strip():
            messagebox.showwarning("提示", "名字不能为空。", parent=dlg)
            return
        p["name"] = name_entry.get().strip()
        p["browser"] = browser_box.get()
        p["proxy"] = proxy_entry.get().strip()
        p["urls"] = [line.strip() for line in urls_text.get("1.0", "end").splitlines()
                     if line.strip()]
        result["ok"] = True
        dlg.destroy()

    btn_frame = tk.Frame(dlg)
    btn_frame.grid(row=6, column=1, sticky="e", padx=10, pady=12)
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
    root.geometry("720x620")
    root.minsize(680, 580)

    tk.Label(root, text="配置从 profiles.json 读取（和脚本放同一目录）。双击一行可直接启动。"
             ).pack(anchor="w", padx=15, pady=(12, 6))

    tree = ttk.Treeview(root, columns=("name", "browser", "proxy", "count"), show="headings")
    tree.heading("name", text="名字")
    tree.heading("browser", text="浏览器")
    tree.heading("proxy", text="代理")
    tree.heading("count", text="网址数")
    tree.column("name", width=130)
    tree.column("browser", width=90)
    tree.column("proxy", width=330)
    tree.column("count", width=70)
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
        new_profile = {"name": "", "browser": "chrome", "proxy": "", "urls": []}
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

    root.mainloop()


if __name__ == "__main__":
    main()
