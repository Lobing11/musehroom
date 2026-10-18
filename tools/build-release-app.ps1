# Build a release-signed HarmonyOS App Pack (.app) with the AGC release certificate.
#
# Why this script exists
# ----------------------
# hvigor refuses a plaintext keystore password in build-profile.json5:
#   hvigor ERROR: 00303116 Configuration Error
#   Error Message: The length of the storePassword or keyPassword field in the signature
#   configuration is less than 32
# It only accepts the AES-encrypted form DevEco Studio writes, which cannot be produced by hand.
# So: let hvigor emit the *unsigned* app pack, then sign the .app container ourselves with
# hap-sign-tool.jar. Note that inside a .app pack the module HAPs are unsigned by design - the
# signature lives on the .app container (verified against DevEco's own debug-signed pack).
#
# Usage (execution policy may block unsigned scripts):
#   powershell -ExecutionPolicy Bypass -File tools\build-release-app.ps1
#
# Inputs  <release dir>\   (default: %USERPROFILE%\.ohos\musehroom-release,
#                           override with the MUSEHROOM_RELEASE_DIR environment variable)
#           musehroom-release.cer                     (AGC release certificate chain)
#           musehroom-release.p12                     (keystore, alias musehroom-release-key)
#           musehroom-release-profileRelease.p7b      (AGC release profile)
#           keystore-password.txt                     (keystore == key password)
# Outputs <repo>\build\release\Musehroom-<version>-release-signed.app   (fresh build)
#         <release dir>\Musehroom-<version>-release-signed.app          (copy for upload)
#
# The script fails loudly if the resulting pack is not a release/distribution one, because
# uploading a debug-signed pack to AppGallery Connect is rejected at review time.

param(
  [string]$ReleaseDir = $(if ($env:MUSEHROOM_RELEASE_DIR) { $env:MUSEHROOM_RELEASE_DIR } else { Join-Path $env:USERPROFILE '.ohos\musehroom-release' })
)

# 'Continue', not 'Stop': PowerShell 5.1 turns a native tool's stderr (hvigor warns about
# obfuscation / skips sign) into a terminating error record. Every step below is checked
# explicitly instead.
$ErrorActionPreference = 'Continue'

$repo     = Split-Path -Parent $PSScriptRoot
# DevEco Studio install root; override with DEVECO_HOME when it lives elsewhere.
$deveco   = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'D:\DevEco Studio' }
$java     = Join-Path $deveco 'jbr\bin\java.exe'
$signTool = Join-Path $deveco 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$hvigor   = Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat'
$sdk      = Join-Path $deveco 'sdk'
$keyAlias = 'musehroom-release-key'

$cert   = Join-Path $ReleaseDir 'musehroom-release.cer'
$p12    = Join-Path $ReleaseDir 'musehroom-release.p12'
$prof   = Join-Path $ReleaseDir 'musehroom-release-profileRelease.p7b'
$pwFile = Join-Path $ReleaseDir 'keystore-password.txt'

foreach ($f in @($cert, $p12, $prof, $pwFile, $java, $signTool, $hvigor)) {
  if (-not (Test-Path $f)) { throw "missing required file: $f" }
}

$pw = (Get-Content $pwFile -Raw).Trim()
if ($pw.Length -lt 8) { throw "keystore password looks wrong (length $($pw.Length)) - check $pwFile" }

$version = '1.0.0'
$appJson = Join-Path $repo 'AppScope\app.json5'
if (Test-Path $appJson) {
  $m = [regex]::Match((Get-Content $appJson -Raw), '"versionName"\s*:\s*"([^"]+)"')
  if ($m.Success) { $version = $m.Groups[1].Value }
}

$env:DEVECO_SDK_HOME = $sdk
$cleanLog = Join-Path $repo 'build-release-clean.log'
$buildLog = Join-Path $repo 'build-release.log'
$unsigned = Join-Path $repo 'build\outputs\default\Musehroom-default-unsigned.app'
$outDir   = Join-Path $repo 'build\release'
$signed   = Join-Path $outDir "Musehroom-$version-release-signed.app"

'== 1/4 build the app pack (hvigor, debug signing config stays untouched) =='
Push-Location $repo
try {
  & $hvigor clean --no-daemon *> $cleanLog
  & $hvigor --mode project -p product=default -p buildMode=release assembleApp --no-daemon *> $buildLog
} finally {
  Pop-Location
}
$lines = ((Get-Content $buildLog -Raw) -replace "\x1b\[[0-9;]*m", '') -split "`r?`n"
$verdict = $lines | Select-String -Pattern 'BUILD (SUCCESSFUL|FAILED)' | Select-Object -Last 1
if ($verdict) { '  ' + $verdict.Line.Trim() }
if (-not ($verdict -and $verdict.Line -match 'BUILD SUCCESSFUL')) { throw "hvigor build failed - see $buildLog" }
if (-not (Test-Path $unsigned)) { throw "unsigned app pack not found: $unsigned" }

'== 2/4 sign the app pack with the AGC release certificate =='
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
& $java -jar $signTool sign-app -mode localSign -keyAlias $keyAlias -keyPwd $pw `
  -appCertFile $cert -profileFile $prof -inFile $unsigned -inForm zip `
  -signAlg SHA256withECDSA -keystoreFile $p12 -keystorePwd $pw -outFile $signed 2>&1 |
  Select-String -Pattern 'sign-app success|Sign Hap success|ERROR' | ForEach-Object { '  ' + $_.Line.Trim() }
if (-not (Test-Path $signed)) { throw 'signing produced no output file' }

'== 3/4 verify signature and profile =='
$chain = Join-Path $ReleaseDir 'verify-chain.cer'
$prof2 = Join-Path $ReleaseDir 'verify-profile.p7b'
$json  = Join-Path $ReleaseDir 'verify-profile.json'
& $java -jar $signTool verify-app -inFile $signed -outCertChain $chain -outProfile $prof2 2>&1 |
  Select-String -Pattern 'Verify success|failed' | ForEach-Object { '  ' + $_.Line.Trim() }
& $java -jar $signTool verify-profile -inFile $prof2 -outFile $json 2>&1 | Select-Object -Last 1
$p = Get-Content $json -Raw | ConvertFrom-Json
$kind = if ($p.content.'bundle-info'.'distribution-certificate') { 'distribution' } else { 'development' }
"  profile: type=$($p.content.type) cert=$kind bundle=$($p.content.'bundle-info'.'bundle-name') verified=$($p.verifiedPassed)"
if ($p.content.type -ne 'release' -or $kind -ne 'distribution') {
  throw "NOT a release-signed pack (type=$($p.content.type) cert=$kind) - do not upload"
}

'== 4/4 copy next to the signing material =='
$final = Join-Path $ReleaseDir "Musehroom-$version-release-signed.app"
Copy-Item $signed $final -Force
"  $final  ($((Get-Item $final).Length) B)"
