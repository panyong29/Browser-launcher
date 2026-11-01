# ============================================================
# 浏览器多配置代理启动器（可视化配置版，Chrome / Edge，Windows）
# 用法：powershell -ExecutionPolicy Bypass -File .\browser-launcher-visual.ps1
# 配置存在 profiles.json（和脚本放同一目录），界面里可新增、编辑、删除、
# 导入、导出；第一次运行没有 profiles.json 时会自动按默认配置生成一个。
# ============================================================

# ---------------- 默认配置（只在没有 profiles.json 时用一次） ----------------
$script:BaseDir = "D:\browser-launcher"
$script:Profiles = @(
    [PSCustomObject]@{ name = "VPS美国";   browser = "chrome"; proxy = "socks5://你的服务器IP:1080"; urls = @("https://ippure.com/", "https://www.google.com", "https://www.youtube.com") },
    [PSCustomObject]@{ name = "本地10808"; browser = "chrome"; proxy = "socks5://127.0.0.1:10808";      urls = @("https://ippure.com/", "https://x.com") },
    [PSCustomObject]@{ name = "Edge直连";   browser = "edge";   proxy = "";                              urls = @("https://ippure.com/", "https://www.bing.com") }
)
# ---------------- 默认配置结束 ----------------

$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:ConfigPath = Join-Path $script:ScriptDir "profiles.json"

# WinForms 需要 STA 线程；不是 STA 时自动重启一次（直接粘贴到控制台运行时跳过）
if ($PSCommandPath -and ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
    Start-Process powershell -ArgumentList '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"" -Wait
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-BrowserPath($browser) {
    $candidates = switch ($browser) {
        "chrome" { @(
            "C:\Program Files\Google\Chrome\Application\chrome.exe",
            "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
        ) }
        "edge" { @(
            "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
        ) }
        default { @() }
    }
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    $script:logBox.AppendText("$line`r`n")
}

function Export-Config($path) {
    $obj = [PSCustomObject]@{ baseDir = $script:BaseDir; profiles = $script:Profiles }
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Save-Config {
    Export-Config $script:ConfigPath
}

function Load-Config {
    if (-not (Test-Path $script:ConfigPath)) { return $false }
    try {
        $data = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.profiles -is [array] -and $data.profiles.Count -gt 0) {
            $script:Profiles = @($data.profiles)
            if ($data.baseDir) { $script:BaseDir = $data.baseDir }
            return $true
        }
    } catch { }
    return $false
}

function Refresh-List {
    $script:listView.Items.Clear()
    foreach ($p in $script:Profiles) {
        $item = New-Object System.Windows.Forms.ListViewItem($p.name)
        [void]$item.SubItems.Add($p.browser)
        [void]$item.SubItems.Add($(if ($p.proxy) { $p.proxy } else { "直连" }))
        [void]$item.SubItems.Add("$($p.urls.Count)")
        $item.Tag = $p
        [void]$script:listView.Items.Add($item)
    }
}

function Get-SelectedProfile {
    if ($script:listView.SelectedItems.Count -eq 0) { return $null }
    return $script:listView.SelectedItems[0].Tag
}

function Start-Profile($p) {
    $exe = Get-BrowserPath $p.browser
    if (-not $exe) { Write-Log "[!] 没找到 $($p.browser)，跳过 [$($p.name)]"; return }
    $dataDir = Join-Path $script:BaseDir ("{0}-{1}" -f $p.browser, $p.name)
    $baseArgs = @("--user-data-dir=$dataDir", "--no-first-run")
    if ($p.proxy) { $baseArgs += "--proxy-server=$($p.proxy)" }
    $proxyText = if ($p.proxy) { $p.proxy } else { "直连" }
    Write-Log "启动 [$($p.name)] $($p.browser)，代理：$proxyText"
    $first = $true
    foreach ($url in $p.urls) {
        if ($first) {
            Start-Process -FilePath $exe -ArgumentList ($baseArgs + "--new-window" + $url) | Out-Null
            Start-Sleep -Milliseconds 1500
            $first = $false
        } else {
            Start-Process -FilePath $exe -ArgumentList ($baseArgs + $url) | Out-Null
            Start-Sleep -Milliseconds 800
        }
    }
    Write-Log "完成 [$($p.name)]，1 个窗口、$($p.urls.Count) 个标签页"
}

function Show-ProfileDialog($p) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($p.name) { "编辑配置" } else { "新增配置" }
    $dlg.Size = New-Object System.Drawing.Size(480, 400)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("微软雅黑", 10)

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "名字："; $lblName.Location = New-Object System.Drawing.Point(20, 20); $lblName.AutoSize = $true
    $dlg.Controls.Add($lblName)
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(110, 18); $txtName.Size = New-Object System.Drawing.Size(340, 26)
    $txtName.Text = $p.name
    $dlg.Controls.Add($txtName)

    $lblBrowser = New-Object System.Windows.Forms.Label
    $lblBrowser.Text = "浏览器："; $lblBrowser.Location = New-Object System.Drawing.Point(20, 60); $lblBrowser.AutoSize = $true
    $dlg.Controls.Add($lblBrowser)
    $cmbBrowser = New-Object System.Windows.Forms.ComboBox
    $cmbBrowser.DropDownStyle = "DropDownList"
    $cmbBrowser.Location = New-Object System.Drawing.Point(110, 58); $cmbBrowser.Size = New-Object System.Drawing.Size(150, 26)
    [void]$cmbBrowser.Items.AddRange(@("chrome", "edge"))
    if ($p.browser -eq "edge") { $cmbBrowser.SelectedIndex = 1 } else { $cmbBrowser.SelectedIndex = 0 }
    $dlg.Controls.Add($cmbBrowser)

    $lblProxy = New-Object System.Windows.Forms.Label
    $lblProxy.Text = "代理："; $lblProxy.Location = New-Object System.Drawing.Point(20, 100); $lblProxy.AutoSize = $true
    $dlg.Controls.Add($lblProxy)
    $txtProxy = New-Object System.Windows.Forms.TextBox
    $txtProxy.Location = New-Object System.Drawing.Point(110, 98); $txtProxy.Size = New-Object System.Drawing.Size(340, 26)
    $txtProxy.Text = $p.proxy
    $dlg.Controls.Add($txtProxy)
    $lblProxyHint = New-Object System.Windows.Forms.Label
    $lblProxyHint.Text = "(留空 = 直连，例如 socks5://127.0.0.1:10808)"
    $lblProxyHint.Location = New-Object System.Drawing.Point(110, 128); $lblProxyHint.AutoSize = $true
    $dlg.Controls.Add($lblProxyHint)

    $lblUrls = New-Object System.Windows.Forms.Label
    $lblUrls.Text = "网址："; $lblUrls.Location = New-Object System.Drawing.Point(20, 155); $lblUrls.AutoSize = $true
    $dlg.Controls.Add($lblUrls)
    $txtUrls = New-Object System.Windows.Forms.TextBox
    $txtUrls.Multiline = $true; $txtUrls.ScrollBars = "Vertical"
    $txtUrls.Location = New-Object System.Drawing.Point(110, 153); $txtUrls.Size = New-Object System.Drawing.Size(340, 130)
    if ($p.urls) { $txtUrls.Text = ($p.urls -join "`r`n") }
    $dlg.Controls.Add($txtUrls)
    $lblUrlsHint = New-Object System.Windows.Forms.Label
    $lblUrlsHint.Text = "(每行一个网址，第一个开新窗口，后面的开成标签页)"
    $lblUrlsHint.Location = New-Object System.Drawing.Point(110, 288); $lblUrlsHint.AutoSize = $true
    $dlg.Controls.Add($lblUrlsHint)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "保存"; $btnOK.Size = New-Object System.Drawing.Size(80, 32)
    $btnOK.Location = New-Object System.Drawing.Point(270, 320)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOK)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"; $btnCancel.Size = New-Object System.Drawing.Size(80, 32)
    $btnCancel.Location = New-Object System.Drawing.Point(360, 320)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.AcceptButton = $btnOK
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }
    if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
        [void][System.Windows.Forms.MessageBox]::Show("名字不能为空。")
        return $false
    }
    $p.name = $txtName.Text.Trim()
    $p.browser = $cmbBrowser.SelectedItem
    $p.proxy = $txtProxy.Text.Trim()
    $p.urls = @($txtUrls.Lines | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
    return $true
}

# ---------------- 界面 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "浏览器多配置代理启动器"
$form.Size = New-Object System.Drawing.Size(660, 580)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("微软雅黑", 10)

$lblTop = New-Object System.Windows.Forms.Label
$lblTop.Text = "配置从 profiles.json 读取（和脚本放同一目录）。双击一行可直接启动。"
$lblTop.AutoSize = $true
$lblTop.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($lblTop)

$script:listView = New-Object System.Windows.Forms.ListView
$script:listView.View = "Details"
$script:listView.FullRowSelect = $true
$script:listView.MultiSelect = $false
$script:listView.GridLines = $true
$script:listView.Location = New-Object System.Drawing.Point(20, 40)
$script:listView.Size = New-Object System.Drawing.Size(600, 230)
[void]$script:listView.Columns.Add("名字", 130)
[void]$script:listView.Columns.Add("浏览器", 90)
[void]$script:listView.Columns.Add("代理", 280)
[void]$script:listView.Columns.Add("网址数", 70)
$script:listView.Add_DoubleClick({
    $sel = Get-SelectedProfile
    if ($sel) { Start-Profile $sel }
})
$form.Controls.Add($script:listView)

function Add-RowButton($text, $x, $handler) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size(108, 36)
    $b.Location = New-Object System.Drawing.Point($x, 285)
    $b.Add_Click($handler)
    $form.Controls.Add($b)
}

Add-RowButton "启动选中" 20 {
    $sel = Get-SelectedProfile
    if (-not $sel) { [void][System.Windows.Forms.MessageBox]::Show("请先选中一个配置。"); return }
    Start-Profile $sel
}
Add-RowButton "全部启动" 138 {
    foreach ($p in $script:Profiles) { Start-Profile $p }
}
Add-RowButton "新增" 256 {
    $new = [PSCustomObject]@{ name = ""; browser = "chrome"; proxy = ""; urls = @() }
    if (Show-ProfileDialog $new) {
        $script:Profiles += $new
        Save-Config; Refresh-List
        Write-Log "新增配置 [$($new.name)]"
    }
}
Add-RowButton "编辑" 374 {
    $sel = Get-SelectedProfile
    if (-not $sel) { [void][System.Windows.Forms.MessageBox]::Show("请先选中一个配置。"); return }
    if (Show-ProfileDialog $sel) {
        Save-Config; Refresh-List
        Write-Log "已修改配置 [$($sel.name)]"
    }
}
Add-RowButton "删除" 492 {
    $sel = Get-SelectedProfile
    if (-not $sel) { [void][System.Windows.Forms.MessageBox]::Show("请先选中一个配置。"); return }
    if ($script:Profiles.Count -le 1) { [void][System.Windows.Forms.MessageBox]::Show("至少保留一个配置。"); return }
    if ([System.Windows.Forms.MessageBox]::Show("确定删除 [$($sel.name)] 吗？", "确认", "YesNo") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $newList = @()
    foreach ($x in $script:Profiles) { if ($x -ne $sel) { $newList += $x } }
    $script:Profiles = $newList
    Save-Config; Refresh-List
    Write-Log "已删除配置 [$($sel.name)]"
}

$lblDir = New-Object System.Windows.Forms.Label
$lblDir.Text = "数据目录："; $lblDir.AutoSize = $true
$lblDir.Location = New-Object System.Drawing.Point(20, 343)
$form.Controls.Add($lblDir)
$script:txtBaseDir = New-Object System.Windows.Forms.TextBox
$script:txtBaseDir.Location = New-Object System.Drawing.Point(105, 340)
$script:txtBaseDir.Size = New-Object System.Drawing.Size(400, 24)
$script:txtBaseDir.Add_Leave({
    $t = $script:txtBaseDir.Text.Trim()
    if ($t -ne "" -and $t -ne $script:BaseDir) {
        $script:BaseDir = $t
        Save-Config
        Write-Log "数据目录改为 $($script:BaseDir)"
    }
})
$form.Controls.Add($script:txtBaseDir)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "浏览…"; $btnBrowse.Size = New-Object System.Drawing.Size(85, 28)
$btnBrowse.Location = New-Object System.Drawing.Point(515, 338)
$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $script:BaseDir
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:BaseDir = $fbd.SelectedPath
        $script:txtBaseDir.Text = $script:BaseDir
        Save-Config
        Write-Log "数据目录改为 $($script:BaseDir)"
    }
})
$form.Controls.Add($btnBrowse)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = "导入配置"; $btnImport.Size = New-Object System.Drawing.Size(120, 36)
$btnImport.Location = New-Object System.Drawing.Point(20, 385)
$btnImport.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $data = Get-Content -Path $ofd.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        $imported = $null
        if ($data.profiles -is [array]) { $imported = @($data.profiles) }
        elseif ($data -is [array]) { $imported = @($data) }
        if (-not $imported -or $imported.Count -eq 0) { throw "文件里没有可用的配置" }
        if ([System.Windows.Forms.MessageBox]::Show("导入 $($imported.Count) 个配置，并替换当前列表，确定吗？", "确认导入", "YesNo") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:Profiles = $imported
        if ($data.baseDir) {
            $script:BaseDir = $data.baseDir
            $script:txtBaseDir.Text = $script:BaseDir
        }
        Save-Config; Refresh-List
        Write-Log "已导入 $($imported.Count) 个配置"
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("导入失败：$($_.Exception.Message)")
    }
})
$form.Controls.Add($btnImport)
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "导出配置"; $btnExport.Size = New-Object System.Drawing.Size(120, 36)
$btnExport.Location = New-Object System.Drawing.Point(150, 385)
$btnExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "JSON 文件 (*.json)|*.json"
    $sfd.FileName = "profiles.json"
    $sfd.InitialDirectory = $script:ScriptDir
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    Export-Config $sfd.FileName
    Write-Log "已导出到 $($sfd.FileName)"
})
$form.Controls.Add($btnExport)
$lblConfig = New-Object System.Windows.Forms.Label
$lblConfig.Text = "配置文件：profiles.json（与脚本同目录）"
$lblConfig.AutoSize = $true
$lblConfig.Location = New-Object System.Drawing.Point(285, 392)
$form.Controls.Add($lblConfig)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = "Vertical"
$script:logBox.Font = New-Object System.Drawing.Font("微软雅黑", 9)
$script:logBox.Location = New-Object System.Drawing.Point(20, 430)
$script:logBox.Size = New-Object System.Drawing.Size(600, 110)
$form.Controls.Add($script:logBox)

# ---------------- 启动时读取配置 ----------------
if (Load-Config) {
    Write-Log "已读取配置：$($script:ConfigPath)，共 $($script:Profiles.Count) 个"
} else {
    Save-Config
    Write-Log "没有找到 profiles.json，已按默认配置生成一个"
}
$script:txtBaseDir.Text = $script:BaseDir
Refresh-List

[void]$form.ShowDialog()
