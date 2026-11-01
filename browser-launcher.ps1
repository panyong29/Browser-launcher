# ============================================================
# 浏览器多配置代理启动器（Chrome / Edge，Windows PowerShell）
# 用法：powershell -ExecutionPolicy Bypass -File .\browser-launcher.ps1
# 配置只改「配置区」，每行一个配置：名字、浏览器、代理、要打开的网址
# ============================================================

# ---------------- 配置区 ----------------
$BaseDir = "D:\browser-launcher"   # 每个配置的独立数据目录放这里，互不干扰

$Profiles = @(
    # 名字随便起；Proxy 为空 = 直连；第一个网址开新窗口，后面的开成标签页
    @{ Name = "VPS美国";   Browser = "chrome"; Proxy = "socks5://你的服务器IP:1080"; Urls = @("https://www.google.com", "https://www.youtube.com") },
    @{ Name = "本地10808"; Browser = "chrome"; Proxy = "socks5://127.0.0.1:10808";      Urls = @("https://x.com") },
    @{ Name = "Edge直连";   Browser = "edge";   Proxy = "";                              Urls = @("https://www.bing.com") }
)
# ---------------- 配置区结束 ----------------

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

function Start-Profile($p) {
    $exe = Get-BrowserPath $p.Browser
    if (-not $exe) { Write-Host "  [!] 没找到 $($p.Browser)，跳过 [$($p.Name)]" -ForegroundColor Yellow; return }
    $dataDir = Join-Path $BaseDir ("{0}-{1}" -f $p.Browser, $p.Name)
    $baseArgs = @("--user-data-dir=$dataDir", "--no-first-run")
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
