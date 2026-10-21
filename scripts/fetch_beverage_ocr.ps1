#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$calorieVendor = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../web/beverage/vendor'))
New-Item -ItemType Directory -Force -Path $calorieVendor, "$calorieVendor/core", "$calorieVendor/lang" | Out-Null
$calorieAssets = @(
    @{File='tesseract.min.js';Url='https://unpkg.com/tesseract.js@6.0.1/dist/tesseract.min.js'},
    @{File='worker.min.js';Url='https://unpkg.com/tesseract.js@6.0.1/dist/worker.min.js'},
    @{File='LICENSE-tesseract.js';Url='https://unpkg.com/tesseract.js@6.0.1/LICENSE.md'},
    @{File='LICENSE-core';Url='https://unpkg.com/tesseract.js-core@6.0.0/LICENSE'},
    @{File='LICENSE-tessdata';Url='https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/LICENSE'}
)
foreach ($calorieCoreName in @('tesseract-core', 'tesseract-core-simd', 'tesseract-core-lstm', 'tesseract-core-simd-lstm')) {
    foreach ($calorieExtension in @('.wasm.js','.wasm')) {
        $calorieAssets += @{File="core/$calorieCoreName$calorieExtension";Url="https://unpkg.com/tesseract.js-core@6.0.0/$calorieCoreName$calorieExtension"}
    }
}
foreach ($calorieLanguage in @('chi_sim','eng')) {
    $calorieAssets += @{File="lang/$calorieLanguage.traineddata";Url="https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/$calorieLanguage.traineddata"}
}
$calorieAssets | ForEach-Object -Parallel {
    $ErrorActionPreference = 'Stop'
    $calorieTarget = Join-Path $using:calorieVendor $_.File
    if ((Test-Path -LiteralPath $calorieTarget) -and (Get-Item -LiteralPath $calorieTarget).Length -gt 1024) { return }
    Write-Output "Downloading $($_.File)"
    $calorieTemporary = $calorieTarget + '.download'
    & curl.exe --silent --show-error --location --fail --connect-timeout 20 --max-time 120 --retry 3 --output $calorieTemporary $_.Url
    if ($LASTEXITCODE -ne 0) { throw "Asset download failed: $($_.Url)" }
    Move-Item -LiteralPath $calorieTemporary -Destination $calorieTarget -Force
    Write-Output "Ready $($_.File)"
} -ThrottleLimit 4
foreach ($calorieAsset in $calorieAssets) {
    $calorieFile = Join-Path $calorieVendor $calorieAsset.File
    if (-not (Test-Path -LiteralPath $calorieFile)) { throw "Missing OCR file: $calorieFile" }
}
Get-ChildItem -LiteralPath $calorieVendor -Recurse -File | Where-Object Name -NotLike '*.download' | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash
$calorieManifestFiles = @{}
Get-ChildItem -LiteralPath $calorieVendor -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' -and $_.Name -notlike '*.download' } | ForEach-Object {
    $calorieRelative = $_.FullName.Substring($calorieVendor.Length + 1).Replace('\','/')
    $calorieManifestFiles[$calorieRelative] = @{ bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
@{tesseract='6.0.1';core='6.0.0';tessdata='4.1.0';files=$calorieManifestFiles} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$calorieVendor/manifest.json" -Encoding utf8
