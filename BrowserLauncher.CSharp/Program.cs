using System.Diagnostics;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace BrowserLauncher.CSharp;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
    }
}

internal sealed class AppConfig
{
    public string BaseDir { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "browser-launcher");
    public List<BrowserProfile> Profiles { get; set; } = new List<BrowserProfile>();
}

internal sealed class BrowserProfile
{
    public string Name { get; set; } = "";
    public string Browser { get; set; } = "chrome";
    public string Proxy { get; set; } = "";
    public List<string> Urls { get; set; } = new List<string>();
    public string BrowserPath { get; set; } = "";
    public bool? UseFingerprint { get; set; }
    public bool AutoStart { get; set; }
    public string FingerprintSeed { get; set; } = "";
    public string FingerprintPlatform { get; set; } = "";
    public string DisableSpoofing { get; set; } = "";
    public string Lang { get; set; } = "";
    public string Timezone { get; set; } = "";
}

internal sealed class MainForm : Form
{
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    private readonly string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "profiles.json");
    private AppConfig config = new();
    private readonly DataGridView grid = new();
    private readonly TextBox baseDir = new();
    private readonly TextBox log = new();
    private CheckBox autoStartLauncher = new();
    private bool changingAutostartToggle;
    private readonly NotifyIcon trayIcon = new();
    private readonly ContextMenuStrip trayMenu = new();
    private bool exitRequested;

    public MainForm()
    {
        Text = "浏览器多配置代理启动器（C#）";
        Width = 980; Height = 680; MinimumSize = new Size(840, 580); StartPosition = FormStartPosition.CenterScreen;
        BuildUi(); LoadConfig(); RefreshGrid();
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.Text = "Browser Launcher";
        trayIcon.ContextMenuStrip = trayMenu;
        trayIcon.Visible = true;
        trayIcon.MouseDoubleClick += (_, e) => { if (e.Button == MouseButtons.Left) RestoreFromTray(); };
        trayMenu.Opening += (_, _) => RefreshTrayMenu();
        FormClosing += (_, e) =>
        {
            if (!exitRequested && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
            }
        };
        FormClosed += (_, _) =>
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
            trayMenu.Dispose();
        };
        Shown += (_, _) => BeginInvoke(new Action(() =>
        {
            foreach (var profile in config.Profiles.Where(p => p.AutoStart)) Launch(profile);
        }));
    }

    private void RestoreFromTray()
    {
        Show();
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate();
    }

    private void RefreshTrayMenu()
    {
        trayMenu.Items.Clear();
        trayMenu.Items.Add("打开启动器", null, (_, _) => RestoreFromTray());
        var timezoneMenu = new ToolStripMenuItem("Windows 系统时区");
        timezoneMenu.DropDownItems.Add(new ToolStripMenuItem("当前：" + TimeZoneInfo.Local.DisplayName) { Enabled = false });
        timezoneMenu.DropDownItems.Add(new ToolStripSeparator());
        var commonZones = new (string Id, string Label)[]
        {
            ("China Standard Time", "中国标准时间（北京/上海）"),
            ("Tokyo Standard Time", "日本标准时间（东京）"),
            ("Singapore Standard Time", "新加坡标准时间"),
            ("UTC", "协调世界时（UTC）"),
            ("GMT Standard Time", "英国时间（伦敦）"),
            ("Eastern Standard Time", "美国东部时间"),
            ("Pacific Standard Time", "美国太平洋时间")
        };
        var zonesById = TimeZoneInfo.GetSystemTimeZones().ToDictionary(zone => zone.Id);
        foreach (var (id, label) in commonZones)
        {
            if (!zonesById.TryGetValue(id, out var zone)) continue;
            var zoneItem = new ToolStripMenuItem(label)
            {
                Checked = zone.Id == TimeZoneInfo.Local.Id,
                CheckOnClick = false
            };
            zoneItem.Click += (_, _) => PromptAndSetSystemTimeZone(zone);
            timezoneMenu.DropDownItems.Add(zoneItem);
        }
        timezoneMenu.DropDownItems.Add(new ToolStripSeparator());
        timezoneMenu.DropDownItems.Add("选择其他时区…", null, (_, _) => ChooseSystemTimeZone());
        trayMenu.Items.Add(timezoneMenu);
        trayMenu.Items.Add(new ToolStripSeparator());
        foreach (var profile in config.Profiles.ToArray())
        {
            var label = string.IsNullOrWhiteSpace(profile.Name) ? "未命名配置" : profile.Name;
            trayMenu.Items.Add(new ToolStripMenuItem(label, null, (_, _) => Launch(profile)));
        }
        trayMenu.Items.Add(new ToolStripSeparator());
        trayMenu.Items.Add("退出", null, (_, _) => ExitApplication());
    }

    private void ChooseSystemTimeZone()
    {
        var zones = TimeZoneInfo.GetSystemTimeZones().OrderBy(zone => zone.DisplayName).ToList();
        using var dialog = new Form
        {
            Text = "选择 Windows 系统时区",
            Width = 620,
            Height = 150,
            StartPosition = FormStartPosition.CenterScreen,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };
        var selector = new ComboBox { Left = 16, Top = 16, Width = 570, DropDownStyle = ComboBoxStyle.DropDownList };
        selector.DisplayMember = nameof(TimeZoneInfo.DisplayName);
        selector.DataSource = zones;
        selector.SelectedItem = zones.FirstOrDefault(zone => zone.Id == TimeZoneInfo.Local.Id);
        dialog.Controls.Add(selector);
        var apply = new Button { Text = "切换", Left = 410, Top = 58, Width = 80, DialogResult = DialogResult.None };
        apply.Click += (_, _) =>
        {
            if (selector.SelectedItem is TimeZoneInfo zone && PromptAndSetSystemTimeZone(zone))
            {
                dialog.DialogResult = DialogResult.OK;
                dialog.Close();
            }
        };
        var cancel = new Button { Text = "取消", Left = 506, Top = 58, Width = 80, DialogResult = DialogResult.Cancel };
        dialog.Controls.Add(apply);
        dialog.Controls.Add(cancel);
        dialog.AcceptButton = apply;
        dialog.CancelButton = cancel;
        dialog.ShowDialog();
    }

    private static bool PromptAndSetSystemTimeZone(TimeZoneInfo zone)
    {
        var choice = MessageBox.Show(
            $"将 Windows 系统时区切换为：\n{zone.DisplayName}\n\n这会影响整台电脑上的应用和网站时区检测。是否继续？",
            "切换系统时区", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (choice != DialogResult.Yes) return false;

        try
        {
            var tzutil = Path.Combine(Environment.SystemDirectory, "tzutil.exe");
            using var process = Process.Start(new ProcessStartInfo(tzutil, "/s " + QuoteArgument(zone.Id))
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true
            });
            if (process == null) throw new InvalidOperationException("无法启动 Windows 时区工具 tzutil.exe。");
            var error = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Windows 拒绝了时区更改。" : error.Trim());

            TimeZoneInfo.ClearCachedData();
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "切换系统时区失败。当前 Windows 账户可能没有更改时区的权限。\n\n" + ex.Message,
                "时区切换失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return false;
        }
    }

    private void ExitApplication()
    {
        exitRequested = true;
        trayIcon.Visible = false;
        Close();
    }

    private void BuildUi()
    {
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(12) };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 150));
        Controls.Add(root);
        root.Controls.Add(new Label { Text = "配置读取/保存到程序目录的 profiles.json；双击一行启动。配置格式与 Python、PowerShell 版本兼容。", AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(0, 0, 0, 8) }, 0, 0);
        grid.Dock = DockStyle.Fill; grid.ReadOnly = true; grid.AllowUserToAddRows = false; grid.AllowUserToDeleteRows = false;
        grid.MultiSelect = false; grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect; grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        grid.Columns.Add("name", "名字"); grid.Columns.Add("browser", "浏览器"); grid.Columns.Add("proxy", "代理"); grid.Columns.Add("lang", "语言"); grid.Columns.Add("timezone", "时区"); grid.Columns.Add("urls", "网址数");
        grid.CellDoubleClick += (_, _) => LaunchSelected(); root.Controls.Add(grid, 0, 1);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(0, 8, 0, 4) };
        AddButton(buttons, "启动选中", LaunchSelected); AddButton(buttons, "全部启动", () => { foreach (var p in config.Profiles.ToArray()) Launch(p); });
        AddButton(buttons, "新增", AddProfile); AddButton(buttons, "编辑", EditProfile); AddButton(buttons, "删除", DeleteProfile);
        AddButton(buttons, "导入配置", ImportConfig); AddButton(buttons, "导出配置", ExportConfig);
        autoStartLauncher = new CheckBox { Text = "登录时启动启动器", AutoSize = true, Checked = IsLauncherAutostartEnabled(), Margin = new Padding(8, 8, 3, 3) };
        autoStartLauncher.CheckedChanged += (_, _) => ToggleLauncherAutostart();
        buttons.Controls.Add(autoStartLauncher);
        root.Controls.Add(buttons, 0, 2);
        var dirPanel = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(0, 4, 0, 8), WrapContents = false };
        dirPanel.Controls.Add(new Label { Text = "数据目录：", AutoSize = true, Padding = new Padding(0, 7, 0, 0) });
        baseDir.Width = 620; baseDir.Text = config.BaseDir; baseDir.Leave += (_, _) => { config.BaseDir = baseDir.Text.Trim(); SaveConfig(); };
        dirPanel.Controls.Add(baseDir); AddButton(dirPanel, "浏览…", BrowseBaseDir); root.Controls.Add(dirPanel, 0, 3);
        log.Dock = DockStyle.Fill; log.Multiline = true; log.ReadOnly = true; log.ScrollBars = ScrollBars.Vertical; root.Controls.Add(log, 0, 4);
    }

    private static void AddButton(Control parent, string label, Action action)
    {
        var b = new Button { Text = label, AutoSize = true, MinimumSize = new Size(88, 32), Margin = new Padding(3) };
        b.Click += (_, _) => action(); parent.Controls.Add(b);
    }

    private void LoadConfig()
    {
        try
        {
            if (File.Exists(configPath)) config = ParseConfig(File.ReadAllText(configPath));
            else config.Profiles = Defaults();
            config.BaseDir ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "browser-launcher");
            config.Profiles = config.Profiles ?? new List<BrowserProfile>();
            foreach (var p in config.Profiles)
            {
                p.Name = p.Name ?? ""; p.Browser = p.Browser ?? "chrome"; p.Proxy = p.Proxy ?? ""; p.Urls = p.Urls ?? new List<string>(); p.BrowserPath = p.BrowserPath ?? "";
                p.UseFingerprint = p.UseFingerprint ?? (p.Browser == "fingerprint");
                p.FingerprintSeed = p.FingerprintSeed ?? ""; p.FingerprintPlatform = p.FingerprintPlatform ?? ""; p.DisableSpoofing = p.DisableSpoofing ?? ""; p.Lang = p.Lang ?? ""; p.Timezone = p.Timezone ?? "";
            }
            if (config.Profiles.Count == 0) config.Profiles = Defaults();
        }
        catch (Exception ex) { MessageBox.Show(this, $"读取配置失败，将使用默认配置。\n{ex.Message}", "配置读取失败"); config = new AppConfig { Profiles = Defaults() }; }
        baseDir.Text = config.BaseDir;
        if (!File.Exists(configPath)) SaveConfig();
    }

    private static List<BrowserProfile> Defaults() => new List<BrowserProfile>
    {
        new BrowserProfile { Name="VPS美国", Browser="chrome", Proxy="socks5://你的服务器IP:1080", Urls=new List<string> { "https://ippure.com/", "https://www.google.com", "https://www.youtube.com" } },
        new BrowserProfile { Name="本地10808", Browser="chrome", Proxy="socks5://127.0.0.1:10808", Urls=new List<string> { "https://ippure.com/", "https://x.com" } },
        new BrowserProfile { Name="Edge直连", Browser="edge", Urls=new List<string> { "https://ippure.com/", "https://www.bing.com" } }
    };

    private void SaveConfig()
    {
        try { File.WriteAllText(configPath, Json.Serialize(ToJsonConfig(config))); }
        catch (Exception ex) { MessageBox.Show(this, $"保存配置失败：{ex.Message}", "错误"); }
    }

    private void RefreshGrid()
    {
        grid.Rows.Clear();
        foreach (var p in config.Profiles) grid.Rows.Add(p.Name, p.Browser, string.IsNullOrWhiteSpace(p.Proxy) ? "直连" : p.Proxy, EmptyFallback(p.Lang, "跟系统"), EmptyFallback(p.Timezone, "跟系统"), p.Urls.Count);
    }

    private BrowserProfile? Selected() => grid.CurrentRow is { Index: >= 0 } row && row.Index < config.Profiles.Count ? config.Profiles[row.Index] : null;
    private void LaunchSelected() { if (Selected() is { } p) Launch(p); else MessageBox.Show(this, "请先选中一个配置。"); }
    private void AddProfile() { var p = new BrowserProfile(); if (EditDialog(p, false)) { config.Profiles.Add(p); SaveConfig(); RefreshGrid(); } }
    private void EditProfile() { if (Selected() is not { } p) { MessageBox.Show(this, "请先选中一个配置。"); return; } if (EditDialog(p, true)) { SaveConfig(); RefreshGrid(); } }
    private void DeleteProfile()
    {
        if (Selected() is not { } p) { MessageBox.Show(this, "请先选中一个配置。"); return; }
        if (config.Profiles.Count < 2) { MessageBox.Show(this, "至少保留一个配置。"); return; }
        if (MessageBox.Show(this, $"确定删除 [{p.Name}] 吗？", "确认", MessageBoxButtons.YesNo) == DialogResult.Yes) { config.Profiles.Remove(p); SaveConfig(); RefreshGrid(); }
    }

    private bool EditDialog(BrowserProfile p, bool editing)
    {
        using var d = new Form { Text = editing ? "编辑配置" : "新增配置", Width = 660, Height = 760, StartPosition = FormStartPosition.CenterParent, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false };
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoScroll = true, Padding = new Padding(12) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 155)); panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); d.Controls.Add(panel);
        var fingerprintToggleControls = new List<Control>();
        var fingerprintOptionControls = new List<Control>();
        Label AddHint(string text, bool fingerprintToggle = false, bool fingerprintOption = false)
        {
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var hint = new Label { Text = text, AutoSize = true, MaximumSize = new Size(420, 0), ForeColor = SystemColors.GrayText, Padding = new Padding(0, 0, 0, 5) };
            panel.Controls.Add(hint, 1, panel.RowCount++);
            if (fingerprintToggle) fingerprintToggleControls.Add(hint);
            if (fingerprintOption) fingerprintOptionControls.Add(hint);
            return hint;
        }
        TextBox AddField(string label, string value, string hint, bool multiline = false, int height = 28, bool fingerprintOption = false)
        {
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var labelControl = new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) };
            var box = new TextBox { Text = value, Dock = DockStyle.Fill, Multiline = multiline, AcceptsReturn = multiline, Height = height, ScrollBars = multiline ? ScrollBars.Vertical : ScrollBars.None };
            panel.Controls.Add(labelControl, 0, panel.RowCount); panel.Controls.Add(box, 1, panel.RowCount++);
            if (fingerprintOption) { fingerprintOptionControls.Add(labelControl); fingerprintOptionControls.Add(box); }
            if (!string.IsNullOrWhiteSpace(hint)) AddHint(hint, fingerprintOption: fingerprintOption);
            return box;
        }
        var name = AddField("名字", p.Name, "给配置起个容易识别的名字；每个配置使用独立的浏览器数据目录。");
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.Controls.Add(new Label { Text = "浏览器", AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) }, 0, panel.RowCount);
        var browser = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; browser.Items.AddRange(["chrome", "edge", "fingerprint"]); browser.SelectedItem = p.Browser; if (browser.SelectedIndex < 0) browser.SelectedIndex = 0; panel.Controls.Add(browser, 1, panel.RowCount++);
        AddHint("选择 Chrome、Edge，或带 fingerprint 补丁的 Chromium。");
        var proxy = AddField("代理（空=直连）", p.Proxy, "留空表示直连，例如 socks5://127.0.0.1:10808。");
        var lang = AddField("启动语言", p.Lang, "留空跟随系统；例如 en-US、zh-CN。设置后同时传给浏览器语言和 Accept-Language。");
        var tz = AddField("启动时区", p.Timezone, "留空跟随系统；填写 IANA 时区名，例如 America/New_York、Asia/Shanghai。原版 Chrome/Edge 在 Windows 上仍使用系统时区；fingerprint 支持自定义时区。");
        var path = AddField("浏览器 exe 路径", p.BrowserPath, "留空时自动查找；也可填写浏览器可执行文件的完整路径。此项对所有浏览器类型生效。");
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var fpLabel = new Label { Text = "指纹开关", AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) };
        var useFp = new CheckBox { Text = "使用 fingerprint 参数", Checked = p.UseFingerprint == true, AutoSize = true };
        panel.Controls.Add(fpLabel, 0, panel.RowCount); panel.Controls.Add(useFp, 1, panel.RowCount++);
        fingerprintToggleControls.Add(fpLabel); fingerprintToggleControls.Add(useFp);
        AddHint("仅 fingerprint 浏览器使用；关闭时不传指纹参数，只应用语言、时区和代理。", fingerprintToggle: true);
        var seed = AddField("指纹种子", p.FingerprintSeed, "32 位整数；留空时按配置名自动生成固定种子。", fingerprintOption: true);
        var platform = AddField("指纹操作系统", p.FingerprintPlatform, "可填 windows、linux 或 macos；留空由浏览器按种子决定。", fingerprintOption: true);
        var disabled = AddField("关闭伪装", p.DisableSpoofing, "用逗号分隔：font,audio,canvas,clientrects,gpu；留空表示全部开启。", fingerprintOption: true);
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.Controls.Add(new Label { Text = "启动选项", AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) }, 0, panel.RowCount);
        var autoStart = new CheckBox { Text = "跟随启动器启动此浏览器配置", Checked = p.AutoStart, AutoSize = true };
        panel.Controls.Add(autoStart, 1, panel.RowCount++);
        AddHint("启动器打开时自动启动此配置；未勾选的配置不会自动启动。");
        var urls = AddField("网址（每行一个）", string.Join(Environment.NewLine, p.Urls), "第一个网址打开新窗口，后续网址在同一配置中打开为标签页。", true, 100);
        void RefreshFingerprintFields()
        {
            var isFingerprint = browser.Text == "fingerprint";
            foreach (var control in fingerprintToggleControls) control.Visible = isFingerprint;
            foreach (var control in fingerprintOptionControls) control.Visible = isFingerprint && useFp.Checked;
        }
        browser.SelectedIndexChanged += (_, _) => RefreshFingerprintFields();
        useFp.CheckedChanged += (_, _) => RefreshFingerprintFields();
        RefreshFingerprintFields();
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 44, Padding = new Padding(8) };
        var ok = new Button { Text = "保存", Width = 90 }; var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, Width = 90 };
        ok.Click += (_, _) => { if (string.IsNullOrWhiteSpace(name.Text)) { MessageBox.Show(d, "名字不能为空。"); return; } d.DialogResult = DialogResult.OK; d.Close(); };
        buttons.Controls.Add(ok); buttons.Controls.Add(cancel); d.Controls.Add(buttons); d.AcceptButton = ok; d.CancelButton = cancel;
        if (d.ShowDialog(this) != DialogResult.OK) return false;
        p.Name = name.Text.Trim(); p.Browser = browser.Text; p.Proxy = proxy.Text.Trim(); p.Lang = lang.Text.Trim(); p.Timezone = tz.Text.Trim(); p.BrowserPath = path.Text.Trim();
        p.UseFingerprint = useFp.Checked; p.FingerprintSeed = seed.Text.Trim(); p.FingerprintPlatform = platform.Text.Trim(); p.DisableSpoofing = disabled.Text.Trim();
        p.AutoStart = autoStart.Checked;
        p.Urls = urls.Lines.Select(x => x.Trim()).Where(x => x.Length > 0).ToList(); return true;
    }

    private void ImportConfig()
    {
        using var d = new OpenFileDialog { Filter = "JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*" };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            var importedConfig = ParseConfig(File.ReadAllText(d.FileName));
            var imported = importedConfig.Profiles;
            if (imported is null || imported.Count == 0) throw new InvalidDataException("配置中没有 profiles。");
            config.Profiles = imported; config.BaseDir = importedConfig.BaseDir ?? config.BaseDir;
            baseDir.Text = config.BaseDir; SaveConfig(); RefreshGrid(); WriteLog($"已导入 {imported.Count} 个配置。");
        }
        catch (Exception ex) { MessageBox.Show(this, $"导入失败：{ex.Message}", "错误"); }
    }

    private void ExportConfig()
    {
        using var d = new SaveFileDialog { Filter = "JSON 文件 (*.json)|*.json", FileName = "profiles.json", InitialDirectory = AppDomain.CurrentDomain.BaseDirectory };
        if (d.ShowDialog(this) == DialogResult.OK) { File.WriteAllText(d.FileName, Json.Serialize(ToJsonConfig(config))); WriteLog($"已导出到 {d.FileName}"); }
    }

    private void BrowseBaseDir() { using var d = new FolderBrowserDialog { SelectedPath = baseDir.Text }; if (d.ShowDialog(this) == DialogResult.OK) { baseDir.Text = d.SelectedPath; config.BaseDir = d.SelectedPath; SaveConfig(); } }

    private void Launch(BrowserProfile p)
    {
        try
        {
            var exe = FindBrowser(p.Browser, p.BrowserPath);
            if (exe is null) { WriteLog($"[!] 找不到 {p.Browser}，跳过 [{p.Name}]；请填写浏览器 exe 路径。"); return; }
            Directory.CreateDirectory(config.BaseDir);
            var dataDir = Path.Combine(config.BaseDir, $"{p.Browser}-{Regex.Replace(p.Name, "[\\\\/:*?\"<>|]", "_")}");
            var useFp = p.Browser == "fingerprint" && p.UseFingerprint == true;
            var seed = GetSeed(p);
            for (var i = 0; i < p.Urls.Count; i++)
            {
                var args = new List<string> { "--user-data-dir=" + dataDir, "--no-first-run" };
                if (useFp)
                {
                    args.Add("--fingerprint=" + seed);
                    if (!string.IsNullOrWhiteSpace(p.DisableSpoofing)) args.Add("--disable-spoofing=" + p.DisableSpoofing);
                    if (!string.IsNullOrWhiteSpace(p.FingerprintPlatform)) args.Add("--fingerprint-platform=" + p.FingerprintPlatform);
                }
                if (!string.IsNullOrWhiteSpace(p.Lang)) { args.Add("--lang=" + p.Lang); args.Add("--accept-lang=" + p.Lang); }
                if (!string.IsNullOrWhiteSpace(p.Timezone) && p.Browser == "fingerprint") args.Add("--timezone=" + p.Timezone);
                if (!string.IsNullOrWhiteSpace(p.Proxy)) args.Add("--proxy-server=" + p.Proxy);
                if (i == 0) args.Add("--new-window");
                if (p.Urls.Count > 0) args.Add(p.Urls[i]);
                var psi = new ProcessStartInfo(exe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe) ?? Environment.CurrentDirectory, Arguments = string.Join(" ", args.Select(QuoteArgument)) };
                Process.Start(psi); Thread.Sleep(i == 0 ? 1500 : 800);
            }
            WriteLog($"启动 [{p.Name}] {p.Browser}，代理：{(string.IsNullOrWhiteSpace(p.Proxy) ? "直连" : p.Proxy)}" + (useFp ? $"，指纹种子：{seed}" : ""));
            if (!string.IsNullOrWhiteSpace(p.Timezone) && p.Browser != "fingerprint") WriteLog($"[!] 原版 Chrome/Edge 时区由系统控制；配置的时区 {p.Timezone} 未传给浏览器。");
            WriteLog($"完成 [{p.Name}]，{p.Urls.Count} 个网址。");
        }
        catch (Exception ex) { WriteLog($"[!] 启动失败 [{p.Name}]：{ex.Message}"); }
    }

    private static int GetSeed(BrowserProfile p)
    {
        if (int.TryParse(p.FingerprintSeed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var seed)) return seed;
        uint crc = 0xFFFFFFFF;
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(p.Name)) { crc ^= b; for (var i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1; }
        return unchecked((int)(crc ^ 0xFFFFFFFF));
    }

    private static string? FindBrowser(string browser, string custom)
    {
        if (!string.IsNullOrWhiteSpace(custom) && File.Exists(custom)) return custom;
        var pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles); var pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86); var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = browser switch
        {
            "chrome" => new[] { Path.Combine(pf, "Google/Chrome/Application/chrome.exe"), Path.Combine(pf86, "Google/Chrome/Application/chrome.exe") },
            "edge" => new[] { Path.Combine(pf86, "Microsoft/Edge/Application/msedge.exe"), Path.Combine(pf, "Microsoft/Edge/Application/msedge.exe") },
            _ => new[] { Path.Combine(local, "Chromium/Application/chrome.exe"), Path.Combine(pf, "Chromium/Application/chrome.exe"), Path.Combine(pf86, "Chromium/Application/chrome.exe") }
        };
        return candidates.FirstOrDefault(path => File.Exists(path));
    }

    private static string QuoteArgument(string value)
    {
        if (value.Length > 0 && value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0) return value;
        var result = new StringBuilder("\""); var slashes = 0;
        foreach (var ch in value)
        {
            if (ch == '\\') { slashes++; continue; }
            if (ch == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(ch); slashes = 0;
        }
        result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
    }

    private static object ToJsonConfig(AppConfig value) => new Dictionary<string, object>
    {
        { "baseDir", value.BaseDir },
        { "profiles", value.Profiles.Select(p => (object)new Dictionary<string, object>
            {
                { "name", p.Name }, { "browser", p.Browser }, { "proxy", p.Proxy }, { "urls", p.Urls },
                { "browser_path", p.BrowserPath }, { "use_fingerprint", p.UseFingerprint ?? false },
                { "auto_start", p.AutoStart },
                { "fingerprint_seed", p.FingerprintSeed }, { "fingerprint_platform", p.FingerprintPlatform },
                { "disable_spoofing", p.DisableSpoofing }, { "lang", p.Lang }, { "timezone", p.Timezone }
            }).ToArray() }
    };

    private static AppConfig ParseConfig(string json)
    {
        var root = Json.DeserializeObject(json);
        var result = new AppConfig();
        if (root is Dictionary<string, object> data)
        {
            if (data.TryGetValue("baseDir", out var baseValue) && baseValue is string dir && !string.IsNullOrWhiteSpace(dir)) result.BaseDir = dir;
            if (data.TryGetValue("profiles", out var profilesValue) && profilesValue is IEnumerable entries)
                foreach (var item in entries) if (item is Dictionary<string, object> profile) result.Profiles.Add(ParseProfile(profile));
        }
        else if (root is IEnumerable list && !(root is string))
            foreach (var item in list) if (item is Dictionary<string, object> profile) result.Profiles.Add(ParseProfile(profile));
        return result;
    }

    private static BrowserProfile ParseProfile(Dictionary<string, object> item)
    {
        object value; var profile = new BrowserProfile();
        profile.Name = ReadString(item, "name", ""); profile.Browser = ReadString(item, "browser", "chrome");
        profile.Proxy = ReadString(item, "proxy", ""); profile.BrowserPath = ReadString(item, "browser_path", "");
        profile.FingerprintSeed = ReadString(item, "fingerprint_seed", ""); profile.FingerprintPlatform = ReadString(item, "fingerprint_platform", "");
        profile.DisableSpoofing = ReadString(item, "disable_spoofing", ""); profile.Lang = ReadString(item, "lang", ""); profile.Timezone = ReadString(item, "timezone", "");
        profile.UseFingerprint = item.TryGetValue("use_fingerprint", out value) ? Convert.ToBoolean(value, CultureInfo.InvariantCulture) : profile.Browser == "fingerprint";
        profile.AutoStart = item.TryGetValue("auto_start", out value) && Convert.ToBoolean(value, CultureInfo.InvariantCulture);
        if (item.TryGetValue("urls", out value) && value is IEnumerable urls)
            foreach (var url in urls) if (url != null && !string.IsNullOrWhiteSpace(Convert.ToString(url, CultureInfo.InvariantCulture))) profile.Urls.Add(Convert.ToString(url, CultureInfo.InvariantCulture));
        return profile;
    }

    private static string ReadString(Dictionary<string, object> item, string key, string fallback) =>
        item.TryGetValue(key, out var value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) ?? fallback : fallback;

    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "BrowserLauncherCSharp";

    private static string CurrentExecutablePath() => Process.GetCurrentProcess().MainModule?.FileName ?? Application.ExecutablePath;

    private static bool IsLauncherAutostartEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
            var command = key?.GetValue(RunValueName) as string;
            return command != null && command.IndexOf(CurrentExecutablePath(), StringComparison.OrdinalIgnoreCase) >= 0;
        }
        catch { return false; }
    }

    private void ToggleLauncherAutostart()
    {
        if (changingAutostartToggle) return;
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (autoStartLauncher.Checked) key.SetValue(RunValueName, "\"" + CurrentExecutablePath() + "\"", RegistryValueKind.String);
            else if (key.GetValue(RunValueName) != null) key.DeleteValue(RunValueName, false);
            WriteLog(autoStartLauncher.Checked ? "已启用登录时启动启动器。" : "已关闭登录时启动启动器。");
        }
        catch (Exception ex)
        {
            changingAutostartToggle = true;
            autoStartLauncher.Checked = IsLauncherAutostartEnabled();
            changingAutostartToggle = false;
            MessageBox.Show(this, "设置登录启动失败：" + ex.Message, "错误");
        }
    }

    private void WriteLog(string message) { log.AppendText($"{DateTime.Now:HH:mm:ss}  {message}{Environment.NewLine}"); }
    private static string EmptyFallback(string value, string fallback) => string.IsNullOrWhiteSpace(value) ? fallback : value;
}
