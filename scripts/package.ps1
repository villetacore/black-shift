# Assembles the Windows release archive from the outputs of build.ps1:
#   dist/BlackShift-<version>-windows-x64/{client, server, Play.cmd, Play.ps1, README.txt, LICENSE}
#   dist/BlackShift-<version>-windows-x64.zip
param([string]$Version = "", [string]$ClientDirectory = "", [string]$ServerDirectory = "")
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (!$Version) {
    $match = Select-String -Path "$projectRoot\CMakeLists.txt" -Pattern 'project\(BlackShift VERSION ([0-9.]+)'
    $Version = $match.Matches[0].Groups[1].Value
}
$Version = $Version.TrimStart('v')
$client = if ($ClientDirectory) { $ClientDirectory } else { "$projectRoot\build\bin" }
$server = if ($ServerDirectory) { $ServerDirectory } else { "$projectRoot\build\server" }
if (!(Test-Path "$client\blackshift.exe")) { throw "Client not found in $client. Run scripts/build.ps1 first." }
if (!(Test-Path "$server\bin\blackshift.bat")) { throw "Server release not found in $server. Run scripts/build.ps1 first." }

$name = "BlackShift-$Version-windows-x64"
$dist = "$projectRoot\dist"
$stage = "$dist\$name"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -Recurse $client "$stage\client"
Copy-Item -Recurse $server "$stage\server"
# App-local MSVC runtime, so the game runs without the Visual C++ Redistributable installed.
$runtime = 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll'
$erts = Get-ChildItem "$stage\server" -Directory -Filter 'erts-*' | Select-Object -First 1
foreach ($dll in $runtime) {
    $source = Join-Path "$env:SystemRoot\System32" $dll
    if (!(Test-Path $source)) { throw "MSVC runtime $dll not found; install the Visual C++ Redistributable." }
    Copy-Item $source "$stage\client"
    if ($erts) { Copy-Item $source "$($erts.FullName)\bin" }
}
# Never ship a local database or logs.
Get-ChildItem "$stage\client" -Recurse -Include *.db, *.log | Remove-Item -Force
foreach ($file in 'Play.cmd', 'Play.ps1') { Copy-Item "$projectRoot\packaging\windows\$file" $stage }
Copy-Item "$projectRoot\packaging\README.txt", "$projectRoot\LICENSE" $stage
$zip = "$dist\$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $stage -DestinationPath $zip
Write-Host "Packaged: $zip"
