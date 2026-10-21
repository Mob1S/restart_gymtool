$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')
$env:ANDROID_USER_HOME = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../.tooling/android-user-home'))
Remove-Item Env:ANDROID_PREFS_ROOT -ErrorAction SilentlyContinue
$env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'
# A daemon started by a sandbox account retains that account for subprocesses.
# Stop it before the authorized release build uses the normal signing identity.
& (Join-Path $PSScriptRoot '../android/gradlew.bat') -p (Join-Path $PSScriptRoot '../android') --stop
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# A fixed release define isolates this build from old machine-specific caches.
# Keep the existing main application's debug signing identity for updates.
& flutter build apk --release --no-pub --dart-define=BEVERAGE_RELEASE=2026-10-21
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '../build/app/outputs/flutter-apk/app-release.apk') -Algorithm SHA256
