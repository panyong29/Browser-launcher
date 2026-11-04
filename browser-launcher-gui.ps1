# ============================================================
# 浏览器多配置代理启动器（图形界面版，Chrome / Edge / fingerprint，Windows）
# 用法：powershell -ExecutionPolicy Bypass -File .\browser-launcher-gui.ps1
# 配置只改「配置区」，每行一个配置：名字、浏览器、代理、网址，另可填语言、时区、exe 路径、指纹开关及指纹参数（与跨平台版格式对应）
# ============================================================

# ---------------- 配置区 ----------------
$BaseDir = "D:\browser-launcher"   # 每个配置的独立数据目录放这里，互不干扰

$Profiles = @(
    # 名字随便起；Proxy 为空 = 直连；第一个网址开新窗口，后面的开成标签页
    @{ Name = "VPS美国";   Browser = "chrome"; Proxy = "socks5://你的服务器IP:1080"; Urls = @("https://www.google.com", "https://www.youtube.com"); BrowserPath = ""; UseFingerprint = $false; FingerprintSeed = ""; FingerprintPlatform = ""; DisableSpoofing = ""; Lang = ""; Timezone = "" },
    @{ Name = "本地10808"; Browser = "chrome"; Proxy = "socks5://127.0.0.1:10808";      Urls = @("https://x.com"); BrowserPath = ""; UseFingerprint = $false; FingerprintSeed = ""; FingerprintPlatform = ""; DisableSpoofing = ""; Lang = ""; Timezone = "" },
    @{ Name = "Edge直连";   Browser = "edge";   Proxy = "";                              Urls = @("https://www.bing.com"); BrowserPath = ""; UseFingerprint = $false; FingerprintSeed = ""; FingerprintPlatform = ""; DisableSpoofing = ""; Lang = ""; Timezone = "" }
)
# ---------------- 配置区结束 ----------------

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

function Get-FingerprintSeed($p) {
    $raw = "$($p.FingerprintSeed)".Trim()
    $val = 0
    if ($raw -ne "" -and [int]::TryParse($raw, [ref]$val) -and $val -ge -2147483648 -and $val -le 2147483647) { return $val }
    return (Get-Crc32 $p.Name)
}

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    $script:logBox.AppendText("$line`r`n")
}

function Start-Profile($p) {
    $exe = Get-BrowserPath $p.Browser $p.BrowserPath
    if (-not $exe) { Write-Log "[!] 没找到 $($p.Browser)，跳过 [$($p.Name)]"; return }
    $dataDir = Join-Path $BaseDir ("{0}-{1}" -f $p.Browser, $p.Name)
    $baseArgs = @("--user-data-dir=$dataDir", "--no-first-run")
    $useFp = ($p.Browser -eq "fingerprint") -and [bool]$p.UseFingerprint
    if ($useFp) {
        $baseArgs += "--fingerprint=$(Get-FingerprintSeed $p)"
        if ($p.DisableSpoofing) { $baseArgs += "--disable-spoofing=$($p.DisableSpoofing)" }
        if ($p.FingerprintPlatform) { $baseArgs += "--fingerprint-platform=$($p.FingerprintPlatform)" }
    }
    if ($p.Lang) { $baseArgs += "--lang=$($p.Lang)"; $baseArgs += "--accept-lang=$($p.Lang)" }
    if ($p.Timezone -and $p.Browser -eq "fingerprint") { $baseArgs += "--timezone=$($p.Timezone)" }
    if ($p.Proxy) { $baseArgs += "--proxy-server=$($p.Proxy)" }
    $proxyText = if ($p.Proxy) { $p.Proxy } else { "直连" }
    Write-Log "启动 [$($p.Name)] $($p.Browser)，代理：$proxyText"
    $first = $true
    foreach ($url in $p.Urls) {
        if ($first) {
            Start-Process -FilePath $exe -ArgumentList ($baseArgs + "--new-window" + $url) | Out-Null
            Start-Sleep -Milliseconds 1500
            $first = $false
        } else {
            Start-Process -FilePath $exe -ArgumentList ($baseArgs + $url) | Out-Null
            Start-Sleep -Milliseconds 800
        }
    }
    Write-Log "完成 [$($p.Name)]，1 个窗口、$($p.Urls.Count) 个标签页"
}

# ---------------- 界面 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "浏览器多配置代理启动器"
$form.Size = New-Object System.Drawing.Size(600, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("微软雅黑", 10)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "点一个按钮启动对应配置；每个配置用独立数据目录，互不干扰。"
$lbl.AutoSize = $true
$lbl.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($lbl)

$y = 50
foreach ($p in $Profiles) {
    $proxyText = if ($p.Proxy) { $p.Proxy } else { "直连" }
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "启动 [$($p.Browser)] $($p.Name)  |  代理：$proxyText  |  $($p.Urls.Count) 个网址"
    $btn.Size = New-Object System.Drawing.Size(540, 44)
    $btn.Location = New-Object System.Drawing.Point(20, $y)
    $btn.Tag = $p
    $btn.Add_Click({ Start-Profile $this.Tag })
    $form.Controls.Add($btn)
    $y += 54
}

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "全部启动"
$btnAll.Size = New-Object System.Drawing.Size(540, 44)
$btnAll.Location = New-Object System.Drawing.Point(20, $y)
$btnAll.Add_Click({ foreach ($p in $Profiles) { Start-Profile $p } })
$form.Controls.Add($btnAll)
$y += 54

$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text = "带账号密码的代理，浏览器第一次联网会弹窗，填一次就行。"
$lblNote.AutoSize = $true
$lblNote.Location = New-Object System.Drawing.Point(20, $y + 5)
$form.Controls.Add($lblNote)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = "Vertical"
$script:logBox.Font = New-Object System.Drawing.Font("微软雅黑", 9)
$script:logBox.Location = New-Object System.Drawing.Point(20, $y + 30)
$script:logBox.Size = New-Object System.Drawing.Size(540, 110)
$form.Controls.Add($script:logBox)

[void]$form.ShowDialog()
