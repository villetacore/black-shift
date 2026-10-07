# Builds and tests the server release (build/server) and the Windows client (build/bin).
#   -QtPath           Qt 6 MSVC kit; defaults to the local build/deps/Qt install
#   -SkipClient       server and Rust core only
#   -SkipTests        no formatting checks or unit tests (used by the release workflow)
#   -TestClient       also run the native Qt integration test against the server release
#   -OutputDirectory  where the deployable client goes (default build/bin)
param([string]$QtPath = "", [switch]$SkipClient, [switch]$SkipTests, [switch]$TestClient, [string]$OutputDirectory = "")
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot
$deployRoot = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { "$projectRoot\build\bin" }
New-Item -ItemType Directory -Force -Path $deployRoot | Out-Null
$localBeam = "$projectRoot\build\deps\otp\bin"
$localElixir = "$projectRoot\build\deps\elixir\bin"
if (Test-Path "$localBeam\erl.exe") { $env:PATH = "$localBeam;$localElixir;" + $env:PATH }
if (!(Get-Command mix -ErrorAction SilentlyContinue)) { throw "Install Erlang/OTP 27+ and Elixir 1.18+, or run scripts/install-beam.ps1." }
Push-Location "$projectRoot\server"
$savedMixEnv = $env:MIX_ENV
try {
    if (!$SkipTests) {
        $env:MIX_ENV = 'test'
        mix format --check-formatted
        if ($LASTEXITCODE -ne 0) { throw "Elixir formatting failed" }
        mix test --warnings-as-errors
        if ($LASTEXITCODE -ne 0) { throw "Elixir tests failed" }
    }
    $env:MIX_ENV = 'prod'
    mix compile --warnings-as-errors
    if ($LASTEXITCODE -ne 0) { throw "Elixir compilation failed" }
    mix release --overwrite --path "$projectRoot\build\server"
    if ($LASTEXITCODE -ne 0) { throw "OTP release build failed" }
} finally { $env:MIX_ENV = $savedMixEnv; Pop-Location }
if (!$SkipTests) {
    cargo test --manifest-path "$projectRoot\client\core\Cargo.toml"
    if ($LASTEXITCODE -ne 0) { throw "Rust tests failed" }
}
if ($SkipClient) { exit 0 }
if (!$QtPath) { $QtPath = "$projectRoot\build\deps\Qt\6.8.3\msvc2022_64" }
if (!(Test-Path "$QtPath\lib\cmake\Qt6\Qt6Config.cmake")) { throw "Qt 6 missing. Pass -QtPath C:\Qt\6.x.x\msvc2022_64. See README.md." }
$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmakeCommand) { $cmakeExe = $cmakeCommand.Source } else {
    $vswhereExe = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $vswhereExe)) { throw "Install CMake or Visual Studio C++ tools." }
    $vsPath = & $vswhereExe -latest -property installationPath
    $cmakeExe = "$vsPath\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
$nativeTests = if ($TestClient) { "ON" } else { "OFF" }
& $cmakeExe -S $projectRoot -B "$projectRoot\build\client" -A x64 "-DCMAKE_PREFIX_PATH=$QtPath" "-DBLACKSHIFT_CLIENT_TESTS=$nativeTests"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
& $cmakeExe --build "$projectRoot\build\client" --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "Client build failed" }
Copy-Item -LiteralPath "$projectRoot\build\client\Release\blackshift.exe" -Destination "$deployRoot\blackshift.exe"
& "$QtPath\bin\windeployqt.exe" --release --no-translations --no-opengl-sw --no-system-d3d-compiler "$deployRoot\blackshift.exe"
if ($LASTEXITCODE -ne 0) { throw "Qt deployment failed" }
if ($TestClient) {
    $savedTestEnvironment = @{}
    foreach ($key in @('PATH','QT_QPA_PLATFORM','QT_QPA_FONTDIR','BLACKSHIFT_SERVER')) { $savedTestEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    try {
        $env:PATH = "$QtPath\bin;" + $env:PATH
        $env:QT_QPA_PLATFORM = "windows"
        $env:QT_QPA_FONTDIR = "$env:WINDIR\Fonts"
        $env:BLACKSHIFT_SERVER = "$projectRoot\build\server\bin\blackshift.bat"
        & "$projectRoot\build\client\Release\blackshift-client-test.exe" -o "$projectRoot/build/native-test.txt,txt"
        $nativeTestExit = $LASTEXITCODE
        Get-Content "$projectRoot\build\native-test.txt"
        if ($nativeTestExit -ne 0) { throw "Native Qt integration test failed" }
    } finally {
        foreach ($key in $savedTestEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedTestEnvironment[$key], 'Process') }
    }
}
Write-Host "Ready: $deployRoot"

