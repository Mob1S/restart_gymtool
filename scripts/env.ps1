# 环境变量重定向脚本 —— 每个 shell 会话开头 dot-source 它：
#   . C:\ccproject\restart_gymtool\scripts\env.ps1
#
# 为什么需要它：这台机器上（理论上）沙箱外的家目录不可写，因此把
# USERPROFILE / HOME / APPDATA / LOCALAPPDATA 全部指到工作区内，让 Flutter /
# Dart / Gradle / Android SDK 的缓存落在工程目录里而不是用户家目录。
#
# 注意 USERPROFILE 一个不够 —— 旧项目（React Native 版）文档记着踩过五个位置，
# Windows 上 APPDATA / LOCALAPPDATA 必须单独设。

$root = "C:\ccproject\restart_gymtool\.tooling"

New-Item -ItemType Directory -Force `
    $root, "$root\home", "$root\appdata", "$root\localappdata", `
    "$root\pub-cache", "$root\gradle", "$root\android-sdk" | Out-Null

$env:USERPROFILE      = "$root\home"
$env:HOME             = "$root\home"
$env:APPDATA          = "$root\appdata"
$env:LOCALAPPDATA     = "$root\localappdata"
$env:PUB_CACHE        = "$root\pub-cache"
$env:GRADLE_USER_HOME = "$root\gradle"
$env:ANDROID_SDK_ROOT = "$root\android-sdk"
$env:ANDROID_HOME     = "$root\android-sdk"

# ---- 以下为计划 Step 1 之外的追加，理由见 dev-environment-notes.md ----
# 计划 Step 1 只重定向了缓存位置；但后续每个 Task 都要 dot-source 本脚本，
# 而 Step 3/Step 4 装的 JDK 与 Android SDK 若不在这里导回 PATH / JAVA_HOME，
# 每个新 shell 都会「找不到 flutter / java / adb」。因此在这里按存在与否追加。

$jdkHome = "$root\jdk"
if (Test-Path $jdkHome) {
    $jdkDir = Get-ChildItem $jdkHome -Directory -ErrorAction SilentlyContinue |
              Where-Object { Test-Path "$($_.FullName)\bin\java.exe" } |
              Select-Object -First 1
    if ($jdkDir) { $env:JAVA_HOME = $jdkDir.FullName }
}

$flutterBin = "$root\flutter\bin"
if (-not (Test-Path $flutterBin)) { $flutterBin = "$root\flutter_windows_3.47.6-stable\flutter\bin" }

$prepend = @(
    $flutterBin,
    "$root\android-sdk\platform-tools",
    "$root\android-sdk\cmdline-tools\latest\bin"
)
if ($env:JAVA_HOME) { $prepend += "$env:JAVA_HOME\bin" }

foreach ($p in $prepend) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
}
