if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$scriptDir = Split-Path -Parent $PSCommandPath

$steamPath = ""
foreach($k in @(@{P='HKCU:\Software\Valve\Steam';N='SteamPath'},@{P='HKCU:\Software\Valve\Steam';N='SteamExe'},@{P='HKLM:\Software\WOW6432Node\Valve\Steam';N='InstallPath'})){
    try{$v=(Get-ItemProperty -Path $k.P -Name $k.N -ErrorAction Stop).($k.N);$v=$v -replace '/','\';if($v.ToLower().EndsWith('steam.exe')){$steamPath=Split-Path $v}else{$steamPath=$v};break}catch{}
}
if(!$steamPath){throw "Steam not found"}

Write-Host "[1/3] Stopping Steam..."
Get-Process | Where-Object { $_.ProcessName -ieq "steam" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2

Write-Host "[2/3] Copying appcache + license..."
Copy-Item "$scriptDir\dll\appinfo.vdf" "$steamPath\appcache\appinfo.vdf" -Force
Copy-Item "$scriptDir\dll\packageinfo.vdf" "$steamPath\appcache\packageinfo.vdf" -Force
python "$scriptDir\dll\steam_license_writer.py"

Write-Host "[3/3] Starting Steam..."
Start-Process "$steamPath\Steam.exe"
Write-Host "[OK] Done!"
