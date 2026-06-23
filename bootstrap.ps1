#Requires -Version 5.1
<#
    Vsenory - Win11 provisioning bootstrap (v1, k otestovani na jednom stroji)
    --------------------------------------------------------------------------
    Spustit v ELEVOVANEM PowerShellu na ciste instalaci Win11 po prvnim spusteni.
    Nezavisi na NASce ani na jednotce Q: - vse se tahne z verejneho GitHub repa
    a z webu vyrobcu (nejnovejsi verze) pres winget.

    Priklad spusteni (jeden radek, elevovany PowerShell):
      irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex

    Log z kazdeho behu: C:\ProgramData\wp-install\install_<datum>_<cas>.log
    Nahled bez instalace: nahore prepni $PreviewOnly = $true (jen vypise plan a skonci).
#>

# ============================ KONFIGURACE ============================
$Owner       = 'adminjakubsamek'      # GitHub ucet
$Repo        = 'wp-install-script'    # nazev repa
$Ref         = 'main'                 # vetev nebo tag
$Restart     = $true                  # na konci restartovat
$PreviewOnly = $false                 # $true = jen vypsat co by se delalo, nic neinstalovat
$LogDir      = 'C:\ProgramData\wp-install'   # kam se uklada log
$InstallPrinter = $true               # tiskarna TOSHIBA-recepce se instaluje vzdy ($false = preskocit)
# ====================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- 0) Kontrola admin prav ---
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Spust tento skript v ELEVOVANEM PowerShellu (Run as administrator)."
}

# --- 0b) Log (transcript) ---
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir ("install_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}
Write-Host "[*] Log: $logFile" -ForegroundColor Cyan

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
if ($lang -notin @('cs','en','de')) { $lang = 'cs' }        # fallback = cestina
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
    @{ Id = '7zip.7zip' }                                      # multijazycny, dle OS
    @{ Id = 'VideoLAN.VLC' }                                   # multijazycny, dle OS  (+ vlc.reg)
    @{ Id = 'Adobe.Acrobat.Reader.64-bit' }                    # MUI dle OS  (OVERIT na 1. stroji)
    @{ Id = 'PDFsam.PDFsam' }                                  # (+ pdfsam.reg, pdfsam.l4j.ini)
    @{ Id = 'Softland.doPDF.11'; Custom = "-install_language=$lang" }   # OVERIT, ze winget arg prijme
    @{ Id = 'Oracle.JavaRuntimeEnvironment' }                  # Oracle Java 8 (klasicka java.com); komercne licence!
    @{ Id = 'OpenVPNTechnologies.OpenVPN' }                    # OpenVPN Community klient (profily rucne)
    @{ Id = 'TeamViewer.TeamViewer' }                          # plny klient; obcas 'hash mismatch' (OVERIT)
)

# --- 5b) Nahled bez instalace ---
if ($PreviewOnly) {
    Write-Host "`n===== NAHLED (PreviewOnly) - nic se neinstaluje =====" -ForegroundColor Magenta
    Write-Host "Jazyk: $tag -> '$lang'"
    Write-Host "`nAplikace (winget):"
    foreach ($a in $apps) {
        $sc = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
        $cu = if ($a.ContainsKey('Custom')) { "  custom: $($a.Custom)" } else { '' }
        Write-Host ("  - {0}  (scope={1}){2}" -f $a.Id, $sc, $cu)
    }
    Write-Host "`nFirefox: lokalizovany build primo od Mozilly (lang dle Windows)"
    Write-Host "Microsoft 365 Apps for business: ODT, jazyk=MatchOS, aktivace rucne"
    Write-Host "`nTweaky: tweaks/win10.ps1 + win10.psm1 + install.preset"
    Write-Host "Konfigy: config/pdfsam.reg, config/vlc.reg, config/pdfsam.l4j.ini, Adobe upsell off"
    Write-Host "Tiskarna TOSHIBA-recepce: $InstallPrinter"
    Write-Host "Restart na konci: $Restart"
    Write-Host "=====================================================`n" -ForegroundColor Magenta
    try { Stop-Transcript | Out-Null } catch {}
    return
}

# --- 5c) Instalace aplikaci ---
$ok = @(); $failed = @()
foreach ($a in $apps) {
    $wgArgs = @('install','--id', $a.Id, '-e', '--silent',
                '--accept-package-agreements','--accept-source-agreements',
                '--disable-interactivity')
    $scope = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
    $wgArgs += @('--scope', $scope)
    if ($a.ContainsKey('Custom')) { $wgArgs += @('--custom', $a.Custom) }

    Write-Host "[>] Instaluji $($a.Id) (scope=$scope)..." -ForegroundColor Yellow
    & $winget @wgArgs
    # winget: 0 = OK, -1978335189 = uz nainstalovano/no upgrade. Bereme jako OK.
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        $ok += $a.Id
    } else {
        Write-Warning "    $($a.Id) skoncil s kodem $LASTEXITCODE"
        $failed += "$($a.Id) (kod $LASTEXITCODE)"
    }
}

# --- 5d) Firefox - lokalizovany build primo od Mozilly (dle jazyka Windows) ---
try {
    $ffLangMap = @{ cs = 'cs'; en = 'en-US'; de = 'de' }
    $ffLang = $ffLangMap[$lang]
    $ffUri  = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=$ffLang"
    $ffExe  = Join-Path $work 'firefox-setup.exe'
    Write-Host "[>] Firefox ($ffLang) primo od Mozilly..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ffUri -OutFile $ffExe -UseBasicParsing
    Start-Process -FilePath $ffExe -ArgumentList '-ms' -Wait
    $ok += "Firefox ($ffLang)"
} catch {
    Write-Warning "    Firefox: $($_.Exception.Message)"
    $failed += "Firefox ($($_.Exception.Message))"
}

# --- 6) Microsoft 365 Apps for business (ODT, jazyk = MatchOS, aktivace rucne) ---
try {
    Write-Host "[*] Microsoft 365 Apps for business (ODT)..." -ForegroundColor Cyan
    Get-RepoFile -Path 'config/office/configuration.xml' -OutFile "$work\office.xml"

    # ODT setup.exe: nejdriv winget (nejnovejsi), jinak fallback na config/office/setup.exe v repu
    $setup = $null
    & $winget install --id Microsoft.OfficeDeploymentTool -e --silent `
        --accept-package-agreements --accept-source-agreements --scope machine 2>$null
    $pkgDir = Join-Path $env:ProgramFiles 'WinGet\Packages'
    if (Test-Path $pkgDir) {
        $setup = Get-ChildItem $pkgDir -Recurse -Filter 'setup.exe' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match 'OfficeDeploymentTool' } |
                 Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $setup) {
        try { Get-RepoFile -Path 'config/office/setup.exe' -OutFile "$work\odt-setup.exe"; $setup = "$work\odt-setup.exe" } catch {}
    }
    if ($setup) {
        Write-Host "    ODT: $setup" -ForegroundColor DarkGray
        Start-Process -FilePath $setup -ArgumentList "/configure `"$work\office.xml`"" -Wait -NoNewWindow
        Write-Host "    [i] M365 Apps nainstalovany. Aktivace = rucne pri prihlaseni uzivatele." -ForegroundColor DarkGray
        $ok += 'Microsoft365Apps'
    } else {
        Write-Warning "    ODT setup.exe nenalezen (winget ani config/office/setup.exe) - M365 preskoceno."
        $failed += 'Microsoft365Apps (ODT setup.exe nenalezen)'
    }
} catch { Write-Warning "    M365 Apps: $($_.Exception.Message)"; $failed += 'Microsoft365Apps' }

# --- 7) Stazeni a aplikace tweaku (Disassembler0 - vycisteny preset) ---
Write-Host "[*] Stahuji a aplikuji Win11 tweaky..." -ForegroundColor Cyan
try {
    Get-RepoFile -Path 'tweaks/win10.ps1'       -OutFile "$work\win10.ps1"
    Get-RepoFile -Path 'tweaks/win10.psm1'      -OutFile "$work\win10.psm1"
    Get-RepoFile -Path 'tweaks/install.preset'  -OutFile "$work\install.preset"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\win10.ps1" `
        -include "$work\win10.psm1" -preset "$work\install.preset"
} catch {
    Write-Warning "    Tweaky preskoceny (chybi soubor v repu?): $($_.Exception.Message)"
    $failed += "Tweaky ($($_.Exception.Message))"
}

# --- 8) Stazeni a aplikace vlastnich konfiguraci ---
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

# 7c) Adobe Reader - vypnuti nabidky upgrade na placeny Acrobat (chova se jako cisty Reader)
try {
    $arPaths = @(
        'HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown',
        'HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown'
    )
    foreach ($rp in $arPaths) {
        if (-not (Test-Path $rp)) { New-Item -Path $rp -Force | Out-Null }
        New-ItemProperty -Path $rp -Name 'bAcroSuppressUpsell' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $rp -Name 'bToggleFTE'          -Value 1 -PropertyType DWord -Force | Out-Null
    }
    Write-Host "    [i] Adobe Reader: upsell na placeny Acrobat vypnut." -ForegroundColor DarkGray
} catch { Write-Warning "    Adobe upsell: $($_.Exception.Message)" }

# 7d) Ikony na plochu (volitelne - jen pokud v repu existuji)
#     Pozn: pro vice souboru je lepsi v repu drzet ZIP a tady ho rozbalit; ponechano jako TODO.

# --- 8b) Tiskarna TOSHIBA-recepce (volitelne, site-specific - jen na pobocce) ---
if ($InstallPrinter) {
    Write-Host "[*] Instalace tiskarny TOSHIBA-recepce..." -ForegroundColor Cyan
    try {
        # ovladac (velky) z GitHub Release assetu (releases/latest), zbytek z korene repa
        $relUrl = "https://github.com/$Owner/$Repo/releases/latest/download/ToshibaDRV.zip"
        Invoke-WebRequest -Uri $relUrl -OutFile "$work\ToshibaDRV.zip" -UseBasicParsing
        Expand-Archive -Path "$work\ToshibaDRV.zip" -DestinationPath 'C:\Program Files\ToshibaDRV' -Force
        Get-RepoFile -Path 'tisk-recepce.ps1' -OutFile "$work\tisk-recepce.ps1"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\tisk-recepce.ps1"
        Get-RepoFile -Path 'SetACL.exe' -OutFile "$work\SetACL.exe"
        & "$work\SetACL.exe" -on "TOSHIBA-recepce" -ot prn -actn ace -ace "n:Everyone;p:man_docs" -ace "n:Everyone;p:print"
        Write-Host "    [i] Tiskarna TOSHIBA-recepce nainstalovana." -ForegroundColor DarkGray
        $ok += 'TOSHIBA-recepce'
    } catch {
        Write-Warning "    Tiskarna preskocena: $($_.Exception.Message)"
        $failed += "Tiskarna ($($_.Exception.Message))"
    }
}

# --- 9) Uklid temp + shrnuti + restart ---
Write-Host "[*] Uklizim pracovni slozku..." -ForegroundColor Cyan
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n===== SHRNUTI =====" -ForegroundColor Green
Write-Host ("Nainstalovano OK ({0}): {1}" -f $ok.Count, ($ok -join ', '))
if ($failed.Count) {
    Write-Host ("Neuspesne ({0}): {1}" -f $failed.Count, ($failed -join ', ')) -ForegroundColor Red
} else {
    Write-Host "Neuspesne: zadne" -ForegroundColor Green
}
Write-Host "Log: $logFile"
Write-Host "===================`n" -ForegroundColor Green

try { Stop-Transcript | Out-Null } catch {}

if ($Restart) {
    shutdown.exe /r /t 30 /c "Instalace dokoncena, restartuji za 30 s"
}
