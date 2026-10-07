$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$depsPath = Join-Path $projectRoot 'build\deps'
New-Item -ItemType Directory -Force -Path $depsPath | Out-Null
$otpArchive = Join-Path $depsPath 'otp-27.3.4.zip'
$elixirArchive = Join-Path $depsPath 'elixir-1.18.4.zip'
if (!(Test-Path $otpArchive)) { Invoke-WebRequest 'https://github.com/erlang/otp/releases/download/OTP-27.3.4/otp_win64_27.3.4.zip' -OutFile $otpArchive }
# Pinned digest of the Windows asset fetched over HTTPS from the official OTP release.
# The release's SHA256.txt covers source/docs only.
$otpExpected = '0a564e77b3b22f0d03ce86b3a22f1ff6e2d844a43fa7a9f0630e073700d13430'
if (!$otpExpected -or (Get-FileHash $otpArchive -Algorithm SHA256).Hash -ne $otpExpected) { throw 'OTP checksum mismatch' }
Invoke-WebRequest 'https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-27.zip' -OutFile $elixirArchive
$elixirHashes = (Invoke-WebRequest 'https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-27.zip.sha256sum').Content
if ($elixirHashes -is [byte[]]) { $elixirHashes = [Text.Encoding]::UTF8.GetString($elixirHashes) }
$elixirExpected = ([regex]::Match($elixirHashes, '[a-fA-F0-9]{64}')).Value
if (!$elixirExpected -or (Get-FileHash $elixirArchive -Algorithm SHA256).Hash -ne $elixirExpected) { throw 'Elixir checksum mismatch' }
Expand-Archive -LiteralPath $otpArchive -DestinationPath "$depsPath\otp" -Force
Expand-Archive -LiteralPath $elixirArchive -DestinationPath "$depsPath\elixir" -Force
Write-Host "Installed locally: $depsPath\otp and $depsPath\elixir"
