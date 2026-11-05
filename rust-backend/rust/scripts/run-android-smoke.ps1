param(
    [string]$Adb = "adb",
    [string]$Query = "test"
)

$ErrorActionPreference = "Stop"

$binary = Join-Path $PWD "target\aarch64-linux-android\release\jmcomic3-backend-smoke"
if (-not (Test-Path -LiteralPath $binary)) {
    & (Join-Path $PSScriptRoot "build-android-arm64.ps1") -Artifact Smoke
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$devices = & $Adb devices
if (($devices -join "`n") -notmatch "\sdevice\s") {
    throw "No authorized Android device is connected."
}

$remote = "/data/local/tmp/jmcomic3-backend-smoke"
& $Adb push $binary $remote | Out-Host
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $Adb shell chmod 755 $remote
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$safeQuery = $Query.Replace("'", "")
& $Adb shell "JM_SMOKE_QUERY='$safeQuery' $remote"
exit $LASTEXITCODE
