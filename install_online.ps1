# Steam CDK Activate - One-Click Install
# Usage: irm https://raw.githubusercontent.com/mnb556/steam-cdk/master/install_online.ps1 | iex

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/mnb556/steam-cdk/master/install_online.ps1 | iex`""
    exit
}

$repo = "https://raw.githubusercontent.com/mnb556/steam-cdk/master"
$workDir = "$env:LOCALAPPDATA\SteamCDK"

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Steam CDK Activate System v1.0" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan

Write-Host "[1/4] Downloading server files..."
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path "$workDir\server\templates" -Force | Out-Null
New-Item -ItemType Directory -Path "$workDir\dll" -Force | Out-Null

Invoke-WebRequest "$repo/server/app.py" -OutFile "$workDir\server\app.py" -UseBasicParsing
Invoke-WebRequest "$repo/server/requirements.txt" -OutFile "$workDir\server\requirements.txt" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/index.html" -OutFile "$workDir\server\templates\index.html" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/login.html" -OutFile "$workDir\server\templates\login.html" -UseBasicParsing
Invoke-WebRequest "$repo/dll/appinfo.vdf" -OutFile "$workDir\dll\appinfo.vdf" -UseBasicParsing
Invoke-WebRequest "$repo/dll/packageinfo.vdf" -OutFile "$workDir\dll\packageinfo.vdf" -UseBasicParsing
Invoke-WebRequest "$repo/dll/steam_license_writer.py" -OutFile "$workDir\dll\steam_license_writer.py" -UseBasicParsing
Invoke-WebRequest "$repo/dll/steam_license_config.json" -OutFile "$workDir\dll\steam_license_config.json" -UseBasicParsing

Write-Host "[2/4] Python + Flask..."
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing Python 3.11..."
    $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $pyExe = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest $pyUrl -OutFile $pyExe -UseBasicParsing
    Start-Process $pyExe -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item $pyExe
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}
python -m pip install flask -q 2>$null

Write-Host "[3/4] Setting up Steam cache..."
$steamPath = ""
foreach($k in @(@{P='HKCU:\Software\Valve\Steam';N='SteamPath'},@{P='HKCU:\Software\Valve\Steam';N='SteamExe'},@{P='HKLM:\Software\WOW6432Node\Valve\Steam';N='InstallPath'})){
    try{$v=(Get-ItemProperty -Path $k.P -Name $k.N -ErrorAction Stop).($k.N);$v=$v -replace '/','\';if($v.ToLower().EndsWith('steam.exe')){$steamPath=Split-Path $v}else{$steamPath=$v};break}catch{}
}
if($steamPath) {
    Get-Process | Where-Object { $_.ProcessName -ieq "steam" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    Copy-Item "$workDir\dll\appinfo.vdf" "$steamPath\appcache\appinfo.vdf" -Force
    Copy-Item "$workDir\dll\packageinfo.vdf" "$steamPath\appcache\packageinfo.vdf" -Force
    python "$workDir\dll\steam_license_writer.py"
    Write-Host "  [OK] Steam cache installed" -ForegroundColor Green
}

Write-Host "[4/4] Starting CDK server..."
Start-Process python -ArgumentList "$workDir\server\app.py" -WindowStyle Hidden
Start-Sleep 3
start http://127.0.0.1:5000?token=changeme

Write-Host ""
Write-Host "[OK] Done!" -ForegroundColor Green
Write-Host "Admin panel: http://127.0.0.1:5000?token=changeme" -ForegroundColor Cyan
Write-Host "Generate CDK codes, then activate in Steam" -ForegroundColor Cyan
