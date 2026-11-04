# ============================================================
# 浏览器多配置代理启动器（可视化配置版，Chrome / Edge / fingerprint，Windows）
# 用法：powershell -ExecutionPolicy Bypass -File .\browser-launcher-visual.ps1
# 配置存在 profiles.json（和脚本放同一目录，与跨平台版 browser-launcher.py 格式通用），界面里可新增、编辑、删除、
# 导入、导出；第一次运行没有 profiles.json 时会自动按默认配置生成一个。
# ============================================================

# ---------------- 默认配置（只在没有 profiles.json 时用一次） ----------------
$script:BaseDir = "D:\browser-launcher"
$script:Profiles = @(
    [PSCustomObject]@{ name = "VPS美国";   browser = "chrome"; proxy = "socks5://你的服务器IP:1080"; browser_path = ""; use_fingerprint = $false; fingerprint_seed = ""; fingerprint_platform = ""; disable_spoofing = ""; lang = ""; timezone = ""; urls = @("https://ippure.com/", "https://www.google.com", "https://www.youtube.com") },
    [PSCustomObject]@{ name = "本地10808"; browser = "chrome"; proxy = "socks5://127.0.0.1:10808";      browser_path = ""; use_fingerprint = $false; fingerprint_seed = ""; fingerprint_platform = ""; disable_spoofing = ""; lang = ""; timezone = ""; urls = @("https://ippure.com/", "https://x.com") },
    [PSCustomObject]@{ name = "Edge直连";   browser = "edge";   proxy = "";                              browser_path = ""; use_fingerprint = $false; fingerprint_seed = ""; fingerprint_platform = ""; disable_spoofing = ""; lang = ""; timezone = ""; urls = @("https://ippure.com/", "https://www.bing.com") }
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

function Get-BrowserPath($browser, $browserPath) {
    if ($browserPath -and (Test-Path $browserPath)) { return $browserPath }
    $local = $env:LOCALAPPDATA
    $candidates = switch ($browser) {
        "chrome" { @(
            "C:\Program Files\Google\Chrome\Application\chrome.exe",
            "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
        ) }
        "edge" { @(
            "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
        ) }
        "fingerprint" { @(
            (Join-Path $local "Chromium\Application\chrome.exe"),
            "C:\Program Files\Chromium\Application\chrome.exe",
            "C:\Program Files (x86)\Chromium\Application\chrome.exe"
        ) }
        default { @() }
    }
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Get-Crc32($text) {
    # 与 Python zlib.crc32 相同的 IEEE CRC32，种子留空时按配置名回落用。
    # 校验：Get-Crc32 "HK_chromium" 应为 -1744200419。
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $crc = [uint32]4294967295
    foreach ($b in $bytes) {
        $crc = [uint32]($crc -bxor $b)
        for ($i = 0; $i -lt 8; $i++) {
            if (($crc -band 1) -eq 1) { $crc = [uint32](($crc -shr 1) -bxor 0xEDB88320) } else { $crc = [uint32]($crc -shr 1) }
        }
    }
    $crc = [uint32]($crc -bxor 4294967295)
    if ($crc -gt 2147483647) { return [int64]$crc - 4294967296 } else { return [int64]$crc }
}

function Get-UseFingerprint($p) {
    # 旧配置没有 use_fingerprint 字段时：浏览器是 fingerprint 默认开，其他默认关（与 py 版一致）。
    if ($p.PSObject.Properties.Name -contains "use_fingerprint") { return [bool]$p.use_fingerprint }
    return ($p.browser -eq "fingerprint")
}

function Get-FingerprintSeed($p) {
    $raw = "$($p.fingerprint_seed)".Trim()
    $val = 0
    if ($raw -ne "" -and [int]::TryParse($raw, [ref]$val) -and $val -ge -2147483648 -and $val -le 2147483647) { return $val }
    return (Get-Crc32 $p.name)
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
        [void]$item.SubItems.Add($(if ($p.lang) { $p.lang } else { "" }))
        [void]$item.SubItems.Add($(if ($p.timezone) { $p.timezone } else { "" }))
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
    $exe = Get-BrowserPath $p.browser $p.browser_path
    if (-not $exe) { Write-Log "[!] 没找到 $($p.browser)，跳过 [$($p.name)]（请在编辑里填浏览器 exe 路径）"; return }
    $dataDir = Join-Path $script:BaseDir ("{0}-{1}" -f $p.browser, $p.name)
    $baseArgs = @("--user-data-dir=$dataDir", "--no-first-run")
    $useFp = ($p.browser -eq "fingerprint") -and (Get-UseFingerprint $p)
    if ($useFp) {
        $baseArgs += "--fingerprint=$(Get-FingerprintSeed $p)"
        if ($p.disable_spoofing) { $baseArgs += "--disable-spoofing=$($p.disable_spoofing)" }
        if ($p.fingerprint_platform) { $baseArgs += "--fingerprint-platform=$($p.fingerprint_platform)" }
    }
    if ($p.proxy) { $baseArgs += "--proxy-server=$($p.proxy)" }
    if ($p.lang) { $baseArgs += "--lang=$($p.lang)"; $baseArgs += "--accept-lang=$($p.lang)" }
    if ($p.timezone) {
        if ($p.browser -eq "fingerprint") {
            # fingerprint-chromium 自带 --timezone 补丁，Windows 下也能生效；开关关了也传时区。
            $baseArgs += "--timezone=$($p.timezone)"
        } else {
            Write-Log "[!] [$($p.name)] Windows 下原版浏览器不认时区，填的时区 $($p.timezone) 未生效"
        }
    }
    $proxyText = if ($p.proxy) { $p.proxy } else { "直连" }
    $logParts = @("启动 [$($p.name)] $($p.browser)，代理：$proxyText")
    if ($p.browser -eq "fingerprint") {
        if ($useFp) {
            $logParts += "指纹种子：$(Get-FingerprintSeed $p)"
            if ($p.disable_spoofing) { $logParts += "关闭伪装：$($p.disable_spoofing)" }
        } else {
            $logParts += "指纹：关（只用语言/时区）"
        }
    }
    if ($p.lang) { $logParts += "语言：$($p.lang)" }
    if ($p.timezone -and $p.browser -eq "fingerprint") { $logParts += "时区：$($p.timezone)" }
    Write-Log ($logParts -join "，")
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
    $dlg.Size = New-Object System.Drawing.Size(480, 760)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("微软雅黑", 10)

    function Add-Field($label, $y, $control) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $label; $l.Location = New-Object System.Drawing.Point(20, $y); $l.AutoSize = $true
        $dlg.Controls.Add($l)
        $control.Location = New-Object System.Drawing.Point(110, ($y - 2))
        $control.Size = New-Object System.Drawing.Size(340, 26)
        $dlg.Controls.Add($control)
        return $l
    }
    function Add-Hint($hint, $y) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $hint; $l.Location = New-Object System.Drawing.Point(110, $y); $l.AutoSize = $true
        $dlg.Controls.Add($l)
        return $l
    }

    $txtName = New-Object System.Windows.Forms.TextBox; $txtName.Text = $p.name
    Add-Field "名字：" 20 $txtName | Out-Null

    $cmbBrowser = New-Object System.Windows.Forms.ComboBox
    $cmbBrowser.DropDownStyle = "DropDownList"
    $cmbBrowser.Size = New-Object System.Drawing.Size(150, 26)
    [void]$cmbBrowser.Items.AddRange(@("chrome", "edge", "fingerprint"))
    $cmbBrowser.SelectedItem = if ($p.browser -in @("chrome", "edge", "fingerprint")) { $p.browser } else { "chrome" }
    Add-Field "浏览器：" 60 $cmbBrowser | Out-Null

    $txtProxy = New-Object System.Windows.Forms.TextBox; $txtProxy.Text = $p.proxy
    Add-Field "代理：" 100 $txtProxy | Out-Null
    Add-Hint "(留空 = 直连，例如 socks5://127.0.0.1:10808)" 128 | Out-Null

    $txtLang = New-Object System.Windows.Forms.TextBox; $txtLang.Text = $p.lang
    Add-Field "启动语言：" 155 $txtLang | Out-Null
    Add-Hint "(留空 = 跟系统，例如 en-US、zh-CN)" 183 | Out-Null

    $txtTimezone = New-Object System.Windows.Forms.TextBox; $txtTimezone.Text = $p.timezone
    Add-Field "启动时区：" 210 $txtTimezone | Out-Null
    Add-Hint "(留空 = 跟系统，例如 America/New_York；Windows 下原版浏览器不认时区)" 238 | Out-Null

    # 浏览器 exe 路径是通用字段，不是只属于指纹：任何浏览器填了且文件存在就优先用它，永远显示。
    $txtBrowserPath = New-Object System.Windows.Forms.TextBox; $txtBrowserPath.Text = $p.browser_path
    Add-Field "浏览器 exe 路径：" 265 $txtBrowserPath | Out-Null
    Add-Hint "(留空自动找；fingerprint 安装位置不固定，填它自己的 exe 最稳)" 293 | Out-Null

    $lblUrls = New-Object System.Windows.Forms.Label
    $lblUrls.Text = "网址："; $lblUrls.Location = New-Object System.Drawing.Point(20, 320); $lblUrls.AutoSize = $true
    $dlg.Controls.Add($lblUrls)
    $txtUrls = New-Object System.Windows.Forms.TextBox
    $txtUrls.Multiline = $true; $txtUrls.ScrollBars = "Vertical"
    $txtUrls.Location = New-Object System.Drawing.Point(110, 318); $txtUrls.Size = New-Object System.Drawing.Size(340, 110)
    if ($p.urls) { $txtUrls.Text = ($p.urls -join "`r`n") }
    $dlg.Controls.Add($txtUrls)
    Add-Hint "(每行一个网址，第一个开新窗口，后面的开成标签页)" 432 | Out-Null

    # 指纹开关：只有浏览器选了 fingerprint 时才显示；开了才展开下面参数。
    $lblFpSwitch = New-Object System.Windows.Forms.Label
    $lblFpSwitch.Text = "指纹开关："; $lblFpSwitch.Location = New-Object System.Drawing.Point(20, 460); $lblFpSwitch.AutoSize = $true
    $dlg.Controls.Add($lblFpSwitch)
    $chkUseFp = New-Object System.Windows.Forms.CheckBox
    $chkUseFp.Text = "使用指纹（fingerprint-chromium）"
    $chkUseFp.Location = New-Object System.Drawing.Point(110, 458); $chkUseFp.AutoSize = $true
    $chkUseFp.Checked = (Get-UseFingerprint $p)
    $dlg.Controls.Add($chkUseFp)
    $lblFpHint = Add-Hint "(关 = 不传指纹，只用语言/时区；开 = 展开下面参数)" 488

    $txtSeed = New-Object System.Windows.Forms.TextBox; $txtSeed.Text = $p.fingerprint_seed
    $lblSeed = Add-Field "指纹种子：" 515 $txtSeed
    $lblSeedHint = Add-Hint "(32 位整数；留空按配置名自动生成固定种子)" 543

    $txtDisable = New-Object System.Windows.Forms.TextBox; $txtDisable.Text = $p.disable_spoofing
    $lblDisable = Add-Field "关闭伪装：" 570 $txtDisable
    $lblDisableHint = Add-Hint "(逗号分隔，如 font,audio,canvas,clientrects,gpu；留空 = 全开)" 598

    $txtPlatform = New-Object System.Windows.Forms.TextBox; $txtPlatform.Text = $p.fingerprint_platform
    $lblPlatform = Add-Field "操作系统：" 625 $txtPlatform
    $lblPlatformHint = Add-Hint "(如 windows、linux、macos；留空 = 种子随机生成)" 653

    $fpDetail = @($lblSeed, $txtSeed, $lblSeedHint, $lblDisable, $txtDisable, $lblDisableHint, $lblPlatform, $txtPlatform, $lblPlatformHint)
    $refreshFp = {
        $isFp = ($cmbBrowser.SelectedItem -eq "fingerprint")
        $lblFpSwitch.Visible = $isFp; $chkUseFp.Visible = $isFp; $lblFpHint.Visible = $isFp
        $show = $isFp -and $chkUseFp.Checked
        foreach ($c in $fpDetail) { $c.Visible = $show }
    }
    $cmbBrowser.Add_SelectedIndexChanged($refreshFp.GetNewClosure())
    $chkUseFp.Add_CheckedChanged($refreshFp.GetNewClosure())
    & $refreshFp

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "保存"; $btnOK.Size = New-Object System.Drawing.Size(80, 32)
    $btnOK.Location = New-Object System.Drawing.Point(270, 685)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOK)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"; $btnCancel.Size = New-Object System.Drawing.Size(80, 32)
    $btnCancel.Location = New-Object System.Drawing.Point(360, 685)
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
    $p.lang = $txtLang.Text.Trim()
    $p.timezone = $txtTimezone.Text.Trim()
    $p.browser_path = $txtBrowserPath.Text.Trim()
    $p.use_fingerprint = [bool]$chkUseFp.Checked
    $p.fingerprint_seed = $txtSeed.Text.Trim()
    $p.disable_spoofing = $txtDisable.Text.Trim()
    $p.fingerprint_platform = $txtPlatform.Text.Trim()
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
[void]$script:listView.Columns.Add("名字", 100)
[void]$script:listView.Columns.Add("浏览器", 80)
[void]$script:listView.Columns.Add("代理", 180)
[void]$script:listView.Columns.Add("语言", 60)
[void]$script:listView.Columns.Add("时区", 110)
[void]$script:listView.Columns.Add("网址数", 60)
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
    $new = [PSCustomObject]@{ name = ""; browser = "chrome"; proxy = ""; browser_path = ""; use_fingerprint = $false; fingerprint_seed = ""; fingerprint_platform = ""; disable_spoofing = ""; lang = ""; timezone = ""; urls = @() }
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
