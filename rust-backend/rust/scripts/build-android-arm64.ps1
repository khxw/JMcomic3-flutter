param(
    [string]$RustToolchain = "stable-x86_64-pc-windows-gnu",
    [ValidateSet("Lib", "Cli", "Smoke")]
    [string]$Artifact = "Lib"
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
$hostClang = Join-Path $ndkBin "clang.exe"
$llvmAr = Join-Path $ndkBin "llvm-ar.exe"
$targetClang = Join-Path $ndkBin "aarch64-linux-android24-clang.cmd"
$readelf = Join-Path $ndkBin "llvm-readelf.exe"
$nm = Join-Path $ndkBin "llvm-nm.exe"
foreach ($tool in @($hostClang, $llvmAr, $targetClang, $readelf, $nm)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Missing NDK tool: $tool"
    }
}

$sysroot = (& rustc "+$RustToolchain" --print sysroot).Trim()
$hostLinker = Join-Path $sysroot "lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained\ld.exe"
if (-not (Test-Path -LiteralPath $hostLinker)) {
    throw "The Rust GNU host linker was not found."
}

Remove-Item Env:RUSTFLAGS -ErrorAction SilentlyContinue
$env:PATH = "$ndkBin;$env:PATH"
$env:CC_x86_64_pc_windows_gnu = $hostClang
$env:AR_x86_64_pc_windows_gnu = $llvmAr
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = $hostLinker
$env:CC_aarch64_linux_android = $targetClang
$env:AR_aarch64_linux_android = $llvmAr
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $targetClang

if ($Artifact -eq "Cli") {
    & cargo "+$RustToolchain" build --target aarch64-linux-android --release --bin jmcomic3-backend-cli
} elseif ($Artifact -eq "Smoke") {
    & cargo "+$RustToolchain" build --target aarch64-linux-android --release --bin jmcomic3-backend-smoke
} else {
    & cargo "+$RustToolchain" build --target aarch64-linux-android --release --lib
}
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$artifactPath = switch ($Artifact) {
    "Cli" { Join-Path $PWD "target\aarch64-linux-android\release\jmcomic3-backend-cli" }
    "Smoke" { Join-Path $PWD "target\aarch64-linux-android\release\jmcomic3-backend-smoke" }
    default { Join-Path $PWD "target\aarch64-linux-android\release\libjmcomic3_rust_backend_v2.so" }
}
$header = & $readelf -h $artifactPath
if (($header -join "`n") -notmatch "AArch64") {
    throw "The output artifact is not AArch64."
}
if ($Artifact -eq "Lib") {
    $symbols = & $nm -D --defined-only $artifactPath
    foreach ($required in @(
            "Java_opensource_jenny_Jni_init",
            "Java_opensource_jenny_Jni_invoke",
            "init_ffi",
            "invoke_ffi",
            "free_str_ffi"
        )) {
        if (($symbols -join "`n") -notmatch [regex]::Escape($required)) {
            throw "Required exported symbol is missing: $required"
        }
    }
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash
Write-Host "Built: $artifactPath"
Write-Host "SHA256: $hash"
