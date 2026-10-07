param([string]$Server = "127.0.0.1:7777", [switch]$Online, [switch]$NoServer, [string]$Screenshot = "", [string]$ClientDirectory = "")
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$clientRoot = if ($ClientDirectory) { [IO.Path]::GetFullPath($ClientDirectory) } else { "$projectRoot\build\bin" }
$clientExe = Join-Path $clientRoot "blackshift.exe"
$releaseScript = "$projectRoot\build\server\bin\blackshift.bat"
$buildScript = "$projectRoot\scripts\build.ps1"
$sourceRoots = @("$projectRoot\client", "$projectRoot\server\lib", "$projectRoot\server\priv", "$projectRoot\assets", "$projectRoot\CMakeLists.txt")
$artifacts = @($clientExe, $releaseScript)
$latestSource = ($sourceRoots | ForEach-Object { if (Test-Path $_ -PathType Leaf) { Get-Item $_ } else { Get-ChildItem $_ -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/](target|_build)[\\/]' } } } | Measure-Object LastWriteTime -Maximum).Maximum
$oldestArtifact = if ($artifacts | Where-Object { !(Test-Path $_) }) { [datetime]::MinValue } else { ($artifacts | ForEach-Object { (Get-Item $_).LastWriteTime } | Measure-Object -Minimum).Minimum }
if ($oldestArtifact -lt $latestSource) {
    Write-Host "Building current client and server release..."
    & $buildScript -OutputDirectory $clientRoot
    if ($LASTEXITCODE -ne 0) { throw "Build failed; play was not started." }
}
if (!(Test-Path $clientExe) -or !(Test-Path $releaseScript)) { throw 'Build did not produce playable artifacts.' }
$serverProcess = $null
$savedEnvironment = @{}
foreach ($key in @('BS_PORT','BS_BIND','BS_DB_DIR','RELEASE_NODE')) { $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    if (!$NoServer) {
        if ($Server -ne '127.0.0.1:7777') { throw 'Use -NoServer when connecting to a remote server.' }
        $env:BS_PORT = '7777'
        $env:BS_BIND = '127.0.0.1'
        $env:BS_DB_DIR = "$projectRoot\server\data\mnesia"
        $env:RELEASE_NODE = 'blackshift@localhost'
        $probe = [Net.Sockets.TcpClient]::new()
        try { $probe.Connect('127.0.0.1',7777); throw 'Port 7777 is already in use. Use -NoServer.' }
        catch [Net.Sockets.SocketException] { } finally { $probe.Dispose() }
        $serverProcess = Start-Process -FilePath $env:COMSPEC -ArgumentList "/d /s /c `"`"$releaseScript`" start`"" -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot\build\server-stdout.log" -RedirectStandardError "$projectRoot\build\server-stderr.log"
        $ready = $false
        for ($i=0; $i -lt 80; $i++) {
            if ($serverProcess.HasExited) { throw 'Elixir server failed to start. See build/server-stderr.log.' }
            $probe = [Net.Sockets.TcpClient]::new()
            try { $probe.Connect('127.0.0.1',7777); $ready = $true } catch [Net.Sockets.SocketException] { } finally { $probe.Dispose() }
            if ($ready) { break }
            Start-Sleep -Milliseconds 100
        }
        if (!$ready) { throw 'Elixir server startup timed out.' }
    }
    $modeArgument = if ($Online) { '--online' } else { '--practice' }
    $clientArguments = @('--server', $Server, $modeArgument)
    if ($Screenshot) { $clientArguments += @('--screenshot', $Screenshot) }
    & $clientExe @clientArguments
    if ($LASTEXITCODE -ne 0) { throw "Client failed with exit code $LASTEXITCODE" }
} finally {
    if ($serverProcess -and !$serverProcess.HasExited) {
        & $releaseScript stop
        $serverProcess.WaitForExit(5000) | Out-Null
    }
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process') }
}

