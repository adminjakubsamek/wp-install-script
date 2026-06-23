#Requires -Version 5.1
<#
    Vsenory - Win11 provisioning bootstrap (v1, k otestovani na jednom stroji)
    --------------------------------------------------------------------------
    Spustit v ELEVOVANEM PowerShellu na ciste instalaci Win11 po prvnim spusteni.
    Nezavisi na NASce ani na jednotce Q: - vse se tahne z verejneho GitHub repa
    a z webu vyrobcu (nejnovejsi verze) pres winget.

    Priklad spusteni (jeden radek, elevovany PowerShell):
      irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
#>

# ============================ KONFIGURACE ============================
$Owner = 'adminjakubsamek'   # GitHub ucet
$Repo  = 'wp-install-script'  # nazev repa
$Ref   = 'main'              # vetev nebo tag
$Restart = $true             # na konci restartovat
# ====================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- 0) Kontrola admin prav ---
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Spust tento skript v ELEVOVANEM PowerShellu (Run as administrator)."
}

# --- 1) Pracovni temp slozka (na konci se smaze) ---
$work = Join-Path $env:TEMP ("provision-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Write-Host "[*] Pracovni slozka: $work" -ForegroundColor Cyan

# --- 2) Pomocna funkce: stahni soubor z verejneho repa (raw.githubusercontent.com) ---
function Get-RepoFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OutFile)
    $uri = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/$Path"
    $dir = Split-Path $OutFile -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Invoke-WebRequest -Uri $uri -OutFile $OutFile -UseBasicParsing
    Write-Host "    [+] $Path" -ForegroundColor DarkGray
}

# --- 3) Detekce jazyka Windows (display language) -> cs/en/de ---
try   { $tag = (Get-WinUserLanguageList)[0].LanguageTag }   # napr. cs-CZ
catch { $tag = (Get-Culture).Name }
$lang = ($tag.Split('-')[0]).ToLower()
if ($lang -notin @('cs','en','de')) { $lang = 'en' }        # fallback
Write-Host "[*] Jazyk Windows: $tag -> '$lang'" -ForegroundColor Cyan

# --- 4) Overeni / naprava wingetu ---
function Resolve-Winget {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # zkus najit primo v balickove ceste (cerstvy OOBE stroj nemusi mit PATH)
    $p = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" -ErrorAction SilentlyContinue |
         Sort-Object FullName -Descending | Select-Object -First 1
    if ($p) { return $p.FullName }
    throw "winget neni k dispozici. Na ciste Win11 Pro byva predinstalovany; aktualizuj 'App Installer' v Microsoft Store a spust znovu."
}
$winget = Resolve-Winget
Write-Host "[*] winget: $winget" -ForegroundColor Cyan

# --- 5) Seznam aplikaci (winget ID) + jazykove/scope vyjimky ---
#     Apps bez poznamky se ridi jazykem Windows automaticky (7zip, VLC, Chrome, Reader).
$apps = @(
    @{ Id = 'Google.Chrome' }                                  # UI dle OS
    @{ Id = 'Mozilla.Firefox' }                                # jazyk resen policies.json (krok 7)
    @{ Id = '7zip.7zip' }                                      # multijazycny, dle OS
    @{ Id = 'VideoLAN.VLC' }                                   # multijazycny, dle OS  (+ vlc.reg)
    @{ Id = 'Adobe.Acrobat.Reader.64-bit' }                    # MUI dle OS  (OVERIT na 1. stroji)
    @{ Id = 'PDFsam.PDFsam' }                                  # (+ pdfsam.reg, pdfsam.l4j.ini)
    @{ Id = 'Softland.doPDF.11'; Custom = "-install_language=$lang" }   # OVERIT, ze winget arg prijme
    @{ Id = 'Ghisler.TotalCommander'; Scope = 'user' }         # winget umi jen user-scope (+ wincmd.ini)
    @{ Id = 'EclipseAdoptium.Temurin.21.JRE' }                 # Java 21 LTS runtime
    @{ Id = 'OpenVPNTechnologies.OpenVPN' }                    # OpenVPN Community klient (profily rucne)
)

$failed = @()
foreach ($a in $apps) {
    $args = @('install','--id', $a.Id, '-e', '--silent',
              '--accept-package-agreements','--accept-source-agreements',
              '--disable-interactivity')
    $scope = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
    $args += @('--scope', $scope)
    if ($a.ContainsKey('Custom')) { $args += @('--custom', $a.Custom) }

    Write-Host "[>] Instaluji $($a.Id) (scope=$scope)..." -ForegroundColor Yellow
    & $winget @args
    # winget: 0 = OK, -1978335189 = uz nainstalovano/no upgrade. Bereme jako OK.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "    $($a.Id) skoncil s kodem $LASTEXITCODE"
        $failed += $a.Id
    }
}

# --- 6) Stazeni a aplikace tweaku (Disassembler0 - vycisteny preset) ---
Write-Host "[*] Stahuji a aplikuji Win11 tweaky..." -ForegroundColor Cyan
Get-RepoFile -Path 'tweaks/win10.ps1'       -OutFile "$work\win10.ps1"
Get-RepoFile -Path 'tweaks/win10.psm1'      -OutFile "$work\win10.psm1"
Get-RepoFile -Path 'tweaks/install.preset'  -OutFile "$work\install.preset"
& $winget *> $null 2>&1   # no-op, jen aby PATH/context byl ohraty
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\win10.ps1" `
    -include "$work\win10.psm1" -preset "$work\install.preset"

# --- 7) Stazeni a aplikace vlastnich konfiguraci ---
Write-Host "[*] Stahuji a aplikuji konfigurace..." -ForegroundColor Cyan

# 7a) Registry tweaky aplikaci
foreach ($reg in 'pdfsam.reg','vlc.reg') {
    try {
        Get-RepoFile -Path "config/$reg" -OutFile "$work\$reg"
        Start-Process regedit.exe -ArgumentList "/S `"$work\$reg`"" -Wait
    } catch { Write-Warning "    $reg se nepodarilo aplikovat: $($_.Exception.Message)" }
}

# 7b) pdfsam.l4j.ini  (OVERIT cilovou cestu winget instalace)
try {
    Get-RepoFile -Path 'config/pdfsam.l4j.ini' -OutFile "$work\pdfsam.l4j.ini"
    $pdfsamDir = 'C:\Program Files\PDFsam Basic'
    if (Test-Path $pdfsamDir) { Copy-Item "$work\pdfsam.l4j.ini" $pdfsamDir -Force }
    else { Write-Warning "    PDFsam adresar nenalezen ($pdfsamDir) - over cestu winget instalace." }
} catch { Write-Warning "    pdfsam.l4j.ini: $($_.Exception.Message)" }

# 7c) Total Commander - wincmd.ini + jazyk (OVERIT cestu; winget instaluje user-scope!)
try {
    Get-RepoFile -Path 'config/wincmd.ini' -OutFile "$work\wincmd.ini"
    $lngMap  = @{ cs = 'wcmd_cz.lng'; en = 'wcmd_eng.lng'; de = 'wcmd_deu.lng' }
    $ini = Get-Content "$work\wincmd.ini" -Raw
    $ini = [regex]::Replace($ini, '(?im)^\s*languageini\s*=.*$', "languageini=$($lngMap[$lang])")
    Set-Content "$work\wincmd.ini" -Value $ini -Encoding Default
    # POZN: presnou cilovou cestu wincmd.ini doladime, az uvidime kam winget TC nainstaloval.
    Write-Host "    [i] wincmd.ini pripraven s jazykem '$lang' - cilova cesta k overeni." -ForegroundColor DarkYellow
} catch { Write-Warning "    wincmd.ini: $($_.Exception.Message)" }

# 7d) Firefox - jazyk pres policies.json (Firefox si langpack dotahne sam)
try {
    $ffDir = 'C:\Program Files\Mozilla Firefox\distribution'
    if (Test-Path 'C:\Program Files\Mozilla Firefox') {
        New-Item -ItemType Directory -Path $ffDir -Force | Out-Null
        $policy = @{ policies = @{ RequestedLocales = @($lang) } } | ConvertTo-Json -Depth 5
        Set-Content -Path "$ffDir\policies.json" -Value $policy -Encoding UTF8
        Write-Host "    [i] Firefox RequestedLocales=$lang" -ForegroundColor DarkGray
    }
} catch { Write-Warning "    Firefox policies.json: $($_.Exception.Message)" }

# 7e) Ikony na plochu (volitelne - jen pokud v repu existuji)
foreach ($set in @(@{P='desktop/PlochaAll';  D="$env:PUBLIC\Desktop"},
                    @{P='desktop/PlochaUser'; D="$env:USERPROFILE\Desktop"})) {
    # Pozn: pro vice souboru je lepsi v repu drzet ZIP a tady ho rozbalit; tady ponechano jako TODO.
}

# --- 8) Uklid temp + restart ---
Write-Host "[*] Uklizim pracovni slozku..." -ForegroundColor Cyan
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

if ($failed.Count) { Write-Warning "Neuspesne balicky: $($failed -join ', ')" }
Write-Host "[OK] Hotovo." -ForegroundColor Green

if ($Restart) {
    shutdown.exe /r /t 30 /c "Instalace dokoncena, restartuji za 30 s"
}
