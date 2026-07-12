param(
  [string]$TargetDir = "",
  [ValidateSet("version","hid","xinput1_4")][string]$Proxy = "version",
  [string]$BuildDir = "$PSScriptRoot\..\cpp_proxy\build-x64\Release",
  [switch]$AddDefenderExclusion,
  [string]$ProcessName = "steam.exe"
)
$ErrorActionPreference = "Stop"

function Find-SteamRoot {
  $keys = @(
    @{Path='HKCU:\Software\Valve\Steam'; Name='SteamPath'},
    @{Path='HKCU:\Software\Valve\Steam'; Name='SteamExe'},
    @{Path='HKLM:\Software\WOW6432Node\Valve\Steam'; Name='InstallPath'}
  )
  foreach($k in $keys){
    try {
      $v=(Get-ItemProperty -Path $k.Path -Name $k.Name -ErrorAction Stop).($k.Name)
      if($v){
        $v=$v -replace '/','\'
        if($v.ToLower().EndsWith('steam.exe')){ return Split-Path -Parent $v }
        return $v
      }
    } catch {}
  }
  throw "Steam path not found; pass -TargetDir"
}

if(!$TargetDir){ $TargetDir = Find-SteamRoot }
$TargetDir = [IO.Path]::GetFullPath($TargetDir)
$dll = Join-Path $BuildDir "$Proxy.dll"
if(!(Test-Path $dll)){ throw "Proxy DLL not found: $dll. Build cpp_proxy first." }
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
$dest = Join-Path $TargetDir "$Proxy.dll"
Copy-Item -LiteralPath $dll -Destination $dest -Force
Write-Host "[+] Deployed $dest"

if($AddDefenderExclusion){
  try {
    Add-MpPreference -ExclusionPath $TargetDir
    Write-Host "[+] Defender exclusion added for research directory: $TargetDir"
  } catch { Write-Warning "Could not add Defender exclusion: $_" }
}

Get-Process | Where-Object { $_.ProcessName -ieq ($ProcessName -replace '\.exe$','') } | ForEach-Object {
  Write-Host "[*] Stopping $($_.ProcessName) pid=$($_.Id)"
  Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 2
$exe = Join-Path $TargetDir $ProcessName
if(Test-Path $exe){ Start-Process -FilePath $exe -WorkingDirectory $TargetDir; Write-Host "[+] Restarted $exe" }
else { Write-Host "[*] Target exe not found at $exe; start it manually." }
Write-Host "[*] Log: $env:TEMP\steamworks_module_load_research.log"
