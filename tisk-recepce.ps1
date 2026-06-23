# Instalace tiskarny TOSHIBA-recepce (robustni - sam najde INF i nazev ovladace)
$address = "192.168.0.240"
$name    = "TOSHIBA-recepce"
$root    = "C:\Program Files\ToshibaDRV"

# 1) Nainstaluj vsechny INF z balicku do driver store (nezavisle na presne ceste/nazvu)
$infs = Get-ChildItem -Path $root -Recurse -Filter *.inf -ErrorAction SilentlyContinue
if (-not $infs) { Write-Warning "Zadny .inf nenalezen v $root - zkontroluj obsah ToshibaDRV.zip"; return }
foreach ($inf in $infs) {
    Write-Host "pnputil /add-driver: $($inf.FullName)"
    pnputil.exe /add-driver "$($inf.FullName)" /install | Out-Null
}
Start-Sleep 3

# 2) Najdi nainstalovany TOSHIBA Universal ovladac (presny nazev z driver store)
$driver = (Get-PrinterDriver -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like '*Universal Printer 2*' -or $_.Name -like '*TOSHIBA*Universal*' } |
           Select-Object -First 1 -ExpandProperty Name)
if (-not $driver) {
    # fallback: zkus pridat ovladac podle puvodniho nazvu
    try { Add-PrinterDriver -Name "TOSHIBA Universal Printer 2" -ErrorAction Stop; $driver = "TOSHIBA Universal Printer 2" } catch {}
}
if (-not $driver) {
    Write-Warning "Ovladac TOSHIBA Universal Printer 2 se nepodarilo najit v driver store. Dostupne TOSHIBA ovladace:"
    Get-PrinterDriver | Where-Object { $_.Name -like '*TOSHIBA*' } | Select-Object -ExpandProperty Name
    return
}
Write-Host "Pouzivam ovladac: $driver"

# 3) Port (idempotentne) + tiskarna
if (-not (Get-PrinterPort -Name $address -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $address -PrinterHostAddress $address
}
Start-Sleep 2
if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
    Add-Printer -DriverName $driver -Name $name -PortName $address
}
Write-Host "Tiskarna '$name' pripravena."
