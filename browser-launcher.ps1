# ============================================================
# 浏览器多配置代理启动器（Chrome / Edge / fingerprint，Windows PowerShell）
# 用法：powershell -ExecutionPolicy Bypass -File .\browser-launcher.ps1
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

function Start-Profile($p) {
    $exe = Get-BrowserPath $p.Browser $p.BrowserPath
    if (-not $exe) { Write-Host "  [!] 没找到 $($p.Browser)，跳过 [$($p.Name)]" -ForegroundColor Yellow; return }
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
    Write-Host "  启动 [$($p.Name)] $($p.Browser)，代理：$proxyText"
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
}

Write-Host ""
Write-Host "=== 浏览器多配置代理启动器 ==="
for ($i = 0; $i -lt $Profiles.Count; $i++) {
    $p = $Profiles[$i]
    $proxyText = if ($p.Proxy) { $p.Proxy } else { "直连" }
    Write-Host ("  {0}. [{1}] {2}  代理：{3}  网址：{4} 个" -f ($i + 1), $p.Browser, $p.Name, $proxyText, $p.Urls.Count)
}
Write-Host "  0. 全部启动"
Write-Host ""
$sel = Read-Host "输入编号（回车默认 0 全部启动）"
if ([string]::IsNullOrWhiteSpace($sel)) { $sel = "0" }

if ($sel -eq "0") {
    foreach ($p in $Profiles) { Start-Profile $p }
} elseif (($sel -as [int]) -ge 1 -and ($sel -as [int]) -le $Profiles.Count) {
    Start-Profile $Profiles[[int]$sel - 1]
} else {
    Write-Host "编号不对，退出。" -ForegroundColor Red
}
Write-Host ""
Write-Host "完成。带账号密码的代理，浏览器第一次联网会弹窗，填一次就行。"
