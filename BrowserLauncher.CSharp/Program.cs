using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace BrowserLauncher.CSharp;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class AppConfig
{
    [JsonPropertyName("baseDir")] public string BaseDir { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "browser-launcher");
    [JsonPropertyName("profiles")] public List<BrowserProfile> Profiles { get; set; } = [];
}

internal sealed class BrowserProfile
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("browser")] public string Browser { get; set; } = "chrome";
    [JsonPropertyName("proxy")] public string Proxy { get; set; } = "";
    [JsonPropertyName("urls")] public List<string> Urls { get; set; } = [];
    [JsonPropertyName("browser_path")] public string BrowserPath { get; set; } = "";
    [JsonPropertyName("use_fingerprint")] public bool? UseFingerprint { get; set; }
    [JsonPropertyName("fingerprint_seed")] public string FingerprintSeed { get; set; } = "";
    [JsonPropertyName("fingerprint_platform")] public string FingerprintPlatform { get; set; } = "";
    [JsonPropertyName("disable_spoofing")] public string DisableSpoofing { get; set; } = "";
    [JsonPropertyName("lang")] public string Lang { get; set; } = "";
    [JsonPropertyName("timezone")] public string Timezone { get; set; } = "";
}

internal sealed class MainForm : Form
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    private readonly string configPath = Path.Combine(AppContext.BaseDirectory, "profiles.json");
    private AppConfig config = new();
    private readonly DataGridView grid = new();
    private readonly TextBox baseDir = new();
    private readonly TextBox log = new();

    public MainForm()
    {
        Text = "浏览器多配置代理启动器（C#）";
        Width = 980; Height = 680; MinimumSize = new Size(840, 580); StartPosition = FormStartPosition.CenterScreen;
        BuildUi(); LoadConfig(); RefreshGrid();
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
            if (File.Exists(configPath)) config = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(configPath), JsonOptions) ?? new AppConfig();
            else config.Profiles = Defaults();
            config.BaseDir ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "browser-launcher");
            config.Profiles ??= [];
            foreach (var p in config.Profiles)
            {
                p.Name ??= ""; p.Browser ??= "chrome"; p.Proxy ??= ""; p.Urls ??= []; p.BrowserPath ??= "";
                p.UseFingerprint ??= p.Browser == "fingerprint";
                p.FingerprintSeed ??= ""; p.FingerprintPlatform ??= ""; p.DisableSpoofing ??= ""; p.Lang ??= ""; p.Timezone ??= "";
            }
            if (config.Profiles.Count == 0) config.Profiles = Defaults();
        }
        catch (Exception ex) { MessageBox.Show(this, $"读取配置失败，将使用默认配置。\n{ex.Message}", "配置读取失败"); config = new AppConfig { Profiles = Defaults() }; }
        baseDir.Text = config.BaseDir;
        if (!File.Exists(configPath)) SaveConfig();
    }

    private static List<BrowserProfile> Defaults() =>
    [
        new() { Name="VPS美国", Browser="chrome", Proxy="socks5://你的服务器IP:1080", Urls=["https://ippure.com/", "https://www.google.com", "https://www.youtube.com"] },
        new() { Name="本地10808", Browser="chrome", Proxy="socks5://127.0.0.1:10808", Urls=["https://ippure.com/", "https://x.com"] },
        new() { Name="Edge直连", Browser="edge", Urls=["https://ippure.com/", "https://www.bing.com"] }
    ];

    private void SaveConfig()
    {
        try { File.WriteAllText(configPath, JsonSerializer.Serialize(config, JsonOptions)); }
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
        using var d = new Form { Text = editing ? "编辑配置" : "新增配置", Width = 610, Height = 700, StartPosition = FormStartPosition.CenterParent, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false };
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoScroll = true, Padding = new Padding(12) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 155)); panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); d.Controls.Add(panel);
        TextBox AddField(string label, string value, bool multiline = false, int height = 28)
        {
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize)); panel.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) }, 0, panel.RowCount);
            var box = new TextBox { Text = value, Dock = DockStyle.Fill, Multiline = multiline, Height = height, ScrollBars = multiline ? ScrollBars.Vertical : ScrollBars.None };
            panel.Controls.Add(box, 1, panel.RowCount); panel.RowCount++; return box;
        }
        var name = AddField("名字", p.Name);
        panel.Controls.Add(new Label { Text = "浏览器", AutoSize = true, Anchor = AnchorStyles.Right, Padding = new Padding(0, 7, 0, 0) }, 0, panel.RowCount);
        var browser = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; browser.Items.AddRange(["chrome", "edge", "fingerprint"]); browser.SelectedItem = p.Browser; if (browser.SelectedIndex < 0) browser.SelectedIndex = 0; panel.Controls.Add(browser, 1, panel.RowCount++);
        var proxy = AddField("代理（空=直连）", p.Proxy); var lang = AddField("启动语言", p.Lang); var tz = AddField("启动时区", p.Timezone);
        var path = AddField("浏览器 exe 路径", p.BrowserPath);
        panel.Controls.Add(new Label { Text = "指纹开关", AutoSize = true, Anchor = AnchorStyles.Right }, 0, panel.RowCount);
        var useFp = new CheckBox { Text = "使用 fingerprint 参数", Checked = p.UseFingerprint == true, AutoSize = true }; panel.Controls.Add(useFp, 1, panel.RowCount++);
        var seed = AddField("指纹种子", p.FingerprintSeed); var platform = AddField("指纹操作系统", p.FingerprintPlatform); var disabled = AddField("关闭伪装", p.DisableSpoofing);
        var urls = AddField("网址（每行一个）", string.Join(Environment.NewLine, p.Urls), true, 100);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 44, Padding = new Padding(8) };
        var ok = new Button { Text = "保存", DialogResult = DialogResult.OK, Width = 90 }; var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, Width = 90 };
        buttons.Controls.Add(ok); buttons.Controls.Add(cancel); d.Controls.Add(buttons); d.AcceptButton = ok; d.CancelButton = cancel;
        if (d.ShowDialog(this) != DialogResult.OK) return false;
        if (string.IsNullOrWhiteSpace(name.Text)) { MessageBox.Show(this, "名字不能为空。"); return false; }
        p.Name = name.Text.Trim(); p.Browser = browser.Text; p.Proxy = proxy.Text.Trim(); p.Lang = lang.Text.Trim(); p.Timezone = tz.Text.Trim(); p.BrowserPath = path.Text.Trim();
        p.UseFingerprint = useFp.Checked; p.FingerprintSeed = seed.Text.Trim(); p.FingerprintPlatform = platform.Text.Trim(); p.DisableSpoofing = disabled.Text.Trim();
        p.Urls = urls.Lines.Select(x => x.Trim()).Where(x => x.Length > 0).ToList(); return true;
    }

    private void ImportConfig()
    {
        using var d = new OpenFileDialog { Filter = "JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*" };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(d.FileName)); var root = doc.RootElement;
            var imported = root.ValueKind == JsonValueKind.Array ? JsonSerializer.Deserialize<List<BrowserProfile>>(root.GetRawText(), JsonOptions) : JsonSerializer.Deserialize<AppConfig>(root.GetRawText(), JsonOptions)?.Profiles;
            if (imported is null || imported.Count == 0) throw new InvalidDataException("配置中没有 profiles。");
            config.Profiles = imported; if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("baseDir", out var dir)) config.BaseDir = dir.GetString() ?? config.BaseDir;
            baseDir.Text = config.BaseDir; SaveConfig(); RefreshGrid(); WriteLog($"已导入 {imported.Count} 个配置。");
        }
        catch (Exception ex) { MessageBox.Show(this, $"导入失败：{ex.Message}", "错误"); }
    }

    private void ExportConfig()
    {
        using var d = new SaveFileDialog { Filter = "JSON 文件 (*.json)|*.json", FileName = "profiles.json", InitialDirectory = AppContext.BaseDirectory };
        if (d.ShowDialog(this) == DialogResult.OK) { File.WriteAllText(d.FileName, JsonSerializer.Serialize(config, JsonOptions)); WriteLog($"已导出到 {d.FileName}"); }
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
                var psi = new ProcessStartInfo(exe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe) ?? Environment.CurrentDirectory };
                psi.ArgumentList.Add("--user-data-dir=" + dataDir); psi.ArgumentList.Add("--no-first-run");
                if (useFp)
                {
                    psi.ArgumentList.Add("--fingerprint=" + seed);
                    if (!string.IsNullOrWhiteSpace(p.DisableSpoofing)) psi.ArgumentList.Add("--disable-spoofing=" + p.DisableSpoofing);
                    if (!string.IsNullOrWhiteSpace(p.FingerprintPlatform)) psi.ArgumentList.Add("--fingerprint-platform=" + p.FingerprintPlatform);
                }
                if (!string.IsNullOrWhiteSpace(p.Lang)) { psi.ArgumentList.Add("--lang=" + p.Lang); psi.ArgumentList.Add("--accept-lang=" + p.Lang); }
                if (!string.IsNullOrWhiteSpace(p.Timezone) && p.Browser == "fingerprint") psi.ArgumentList.Add("--timezone=" + p.Timezone);
                if (!string.IsNullOrWhiteSpace(p.Proxy)) psi.ArgumentList.Add("--proxy-server=" + p.Proxy);
                if (i == 0) psi.ArgumentList.Add("--new-window");
                if (p.Urls.Count > 0) psi.ArgumentList.Add(p.Urls[i]);
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
        return candidates.FirstOrDefault(File.Exists);
    }

    private void WriteLog(string message) { log.AppendText($"{DateTime.Now:HH:mm:ss}  {message}{Environment.NewLine}"); }
    private static string EmptyFallback(string value, string fallback) => string.IsNullOrWhiteSpace(value) ? fallback : value;
}
