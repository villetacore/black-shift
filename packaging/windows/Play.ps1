# Black Shift launcher shipped in the Windows release archive.
#   .\Play.ps1                              local server + practice match against bots
#   .\Play.ps1 -Online                      local server + online queue (second player joins this PC)
#   .\Play.ps1 -NoServer -Server host:7777  join a remote server
param([string]$Server = "127.0.0.1:7777", [switch]$Online, [switch]$NoServer, [string]$Name = "Operator",
      [ValidateSet("ranger", "warden")][string]$Role = "ranger")
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$clientExe = Join-Path $root 'client\blackshift.exe'
$serverScript = Join-Path $root 'server\bin\blackshift.bat'

function Test-Port([int]$port) {
    $probe = [Net.Sockets.TcpClient]::new()
    try { $probe.Connect('127.0.0.1', $port); return $true }
    catch [Net.Sockets.SocketException] { return $false }
    finally { $probe.Dispose() }
}

$serverProcess = $null
try {
    if (!$NoServer) {
        if ($Server -ne '127.0.0.1:7777') { throw 'Use -NoServer to connect to a remote server.' }
        if (Test-Port 7777) { throw 'Port 7777 is already in use. Start with -NoServer to use that server.' }
        $env:BS_PORT = '7777'
        $env:BS_BIND = '127.0.0.1'
        $env:BS_DB_DIR = Join-Path $root 'data\mnesia'
        $env:RELEASE_NODE = 'blackshift@localhost'
        $serverProcess = Start-Process -FilePath $env:COMSPEC -ArgumentList "/d /s /c `"`"$serverScript`" start`"" `
            -WorkingDirectory $root -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $root 'server.log') -RedirectStandardError (Join-Path $root 'server-error.log')
        $ready = $false
        for ($i = 0; $i -lt 100 -and !$ready; $i++) {
            if ($serverProcess.HasExited) { throw 'The server failed to start. See server-error.log.' }
            $ready = Test-Port 7777
            if (!$ready) { Start-Sleep -Milliseconds 100 }
        }
        if (!$ready) { throw 'The server did not start in time.' }
    }
    $mode = if ($Online) { '--online' } else { '--practice' }
    & $clientExe --server $Server --name $Name --role $Role $mode
} finally {
    if ($serverProcess -and !$serverProcess.HasExited) {
        & $serverScript stop
        $serverProcess.WaitForExit(5000) | Out-Null
    }
}
