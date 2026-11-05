param(
    [string]$RustToolchain = "stable-x86_64-pc-windows-gnu"
)

$ErrorActionPreference = "Stop"

$ndkHome = $env:ANDROID_NDK_HOME
if ([string]::IsNullOrWhiteSpace($ndkHome) -and -not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    $ndkHome = Join-Path $env:ANDROID_HOME "ndk\25.2.9519653"
}
if ([string]::IsNullOrWhiteSpace($ndkHome) -or -not (Test-Path -LiteralPath $ndkHome)) {
    throw "Set ANDROID_NDK_HOME to the Android NDK directory."
}

$ndkBin = Join-Path $ndkHome "toolchains\llvm\prebuilt\windows-x86_64\bin"
$clang = Join-Path $ndkBin "clang.exe"
$llvmAr = Join-Path $ndkBin "llvm-ar.exe"
if (-not (Test-Path -LiteralPath $clang) -or -not (Test-Path -LiteralPath $llvmAr)) {
    throw "The selected Android NDK does not contain the Windows LLVM tools."
}

$sysroot = (& rustc "+$RustToolchain" --print sysroot).Trim()
$linker = Join-Path $sysroot "lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained\ld.exe"
if (-not (Test-Path -LiteralPath $linker)) {
    throw "The Rust GNU linker was not found under the selected toolchain."
}

$env:PATH = "$ndkBin;$env:PATH"
$env:CC_x86_64_pc_windows_gnu = $clang
$env:AR_x86_64_pc_windows_gnu = $llvmAr
$env:RUSTFLAGS = "-C linker=$linker"

& cargo "+$RustToolchain" check --all-targets
exit $LASTEXITCODE
