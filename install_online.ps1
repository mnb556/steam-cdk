# Steam CDK Activate — One Click
# COM Hook DLL injection + Flask CDK server

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

Write-Host "[2/6] Setting env..."
[Environment]::SetEnvironmentVariable("STEAMWORKS_FORCE_AUTH","1","User")

Write-Host "[3/6] Downloading files..."
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path "$workDir\server\templates" -Force | Out-Null
Invoke-WebRequest "$repo/server/app.py" -OutFile "$workDir\server\app.py" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/index.html" -OutFile "$workDir\server\templates\index.html" -UseBasicParsing
Invoke-WebRequest "$repo/server/templates/login.html" -OutFile "$workDir\server\templates\login.html" -UseBasicParsing
# COM Hook DLL (has CreateInterface + vtable hooks)
Invoke-WebRequest "$repo/dll/steam_license_probe.dll" -OutFile "$workDir\steam_license_probe.dll" -UseBasicParsing
Invoke-WebRequest "$repo/dll/steam_license_config.json" -OutFile "$workDir\steam_license_config.json" -UseBasicParsing
# App cache files from game owner
Invoke-WebRequest "$repo/dll/appinfo.vdf" -OutFile "$workDir\appinfo.vdf" -UseBasicParsing
Invoke-WebRequest "$repo/dll/packageinfo.vdf" -OutFile "$workDir\packageinfo.vdf" -UseBasicParsing

Write-Host "[4/6] Python + Flask..."
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile "$env:TEMP\py.exe" -UseBasicParsing
    Start-Process "$env:TEMP\py.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}
python -m pip install flask pyopenssl -q 2>$null

# Start Flask CDK server
Start-Process python -ArgumentList "$workDir\server\app.py" -WorkingDirectory "$workDir\server" -WindowStyle Hidden
Start-Sleep 2

Write-Host "[5/6] Deploying cache + starting Steam..."
$steamPath = ""
foreach($k in @(@{P='HKCU:\Software\Valve\Steam';N='SteamPath'},@{P='HKCU:\Software\Valve\Steam';N='SteamExe'},@{P='HKLM:\Software\WOW6432Node\Valve\Steam';N='InstallPath'})){
    try{$v=(Get-ItemProperty -Path $k.P -Name $k.N -ErrorAction Stop).($k.N);$v=$v -replace '/','\';if($v.ToLower().EndsWith('steam.exe')){$steamPath=Split-Path $v}else{$steamPath=$v};break}catch{}
}
if($steamPath) {
    # Copy app cache
    Copy-Item "$workDir\appinfo.vdf" "$steamPath\appcache\appinfo.vdf" -Force
    Copy-Item "$workDir\packageinfo.vdf" "$steamPath\appcache\packageinfo.vdf" -Force
    # Copy COM Hook DLL to Steam dir
    Copy-Item "$workDir\steam_license_probe.dll" "$steamPath\steam_license_probe.dll" -Force
    Copy-Item "$workDir\steam_license_config.json" "$steamPath\steam_license_config.json" -Force
    try{Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue}catch{}
}
Start-Process (Join-Path $steamPath "Steam.exe")
Start-Sleep 12

Write-Host "[6/6] Injecting COM Hook DLL..."
# Python script to inject DLL into Steam process
@'
import ctypes
k32 = ctypes.windll.kernel32
snap = k32.CreateToolhelp32Snapshot(0x2, 0)
class PE(ctypes.Structure):
    _fields_ = [("dwSize",ctypes.c_uint32),("cntUsage",ctypes.c_uint32),("pid",ctypes.c_uint32),
                ("th32DefaultHeapID",ctypes.c_void_p),("th32ModuleID",ctypes.c_uint32),
                ("cntThreads",ctypes.c_uint32),("th32ParentProcessID",ctypes.c_uint32),
                ("pcPriClassBase",ctypes.c_long),("dwFlags",ctypes.c_uint32),("szExeFile",ctypes.c_char*260)]
pe = PE(); pe.dwSize = ctypes.sizeof(PE); pid = 0
if k32.Process32First(snap, ctypes.byref(pe)):
    while k32.Process32Next(snap, ctypes.byref(pe)):
        if b"steam.exe" in pe.szExeFile.lower() and b"webhelper" not in pe.szExeFile.lower():
            pid = pe.pid; break
k32.CloseHandle(snap)
if pid:
    dll = "steam_license_probe.dll"
    dll_bytes = dll.encode("utf-16-le")
    hp = k32.OpenProcess(0x2|0x8|0x20|0x10|0x400, False, pid)
    if hp:
        remote = k32.VirtualAllocEx(hp, None, len(dll_bytes)+2, 0x3000, 0x4)
        written = ctypes.c_size_t(0)
        k32.WriteProcessMemory(hp, remote, dll_bytes, len(dll_bytes), ctypes.byref(written))
        loadlib = k32.GetProcAddress(k32.GetModuleHandleW("kernel32.dll"), b"LoadLibraryW")
        thread = k32.CreateRemoteThread(hp, None, 0, loadlib, remote, 0, None)
        k32.WaitForSingleObject(thread, 5000)
        k32.CloseHandle(thread); k32.CloseHandle(hp)
        print("COM Hook injected OK")
'@ | Set-Content "$env:TEMP\inject_hook.py"
python "$env:TEMP\inject_hook.py" 2>$null

Write-Host "[OK] Done." -ForegroundColor Green
Write-Host "Admin: http://127.0.0.1:5000?token=changeme"
