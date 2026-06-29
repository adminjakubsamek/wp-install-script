#Requires -Version 5.1
<#
    Vsenory - Win11 provisioning bootstrap (v1, k otestovani na jednom stroji)
    --------------------------------------------------------------------------
    Spustit v ELEVOVANEM PowerShellu na ciste instalaci Win11 po prvnim spusteni.
    Nezavisi na NASce ani na jednotce Q: - vse se tahne z verejneho GitHub repa
    a z webu vyrobcu (nejnovejsi verze) pres winget.

    Priklad spusteni (jeden radek, elevovany PowerShell):
      irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex

    Log z kazdeho behu: na plochu admina (install_<datum>_<cas>.log)
    Nahled bez instalace: nahore prepni $PreviewOnly = $true (jen vypise plan a skonci).
#>

# ============================ KONFIGURACE ============================
$Owner       = 'adminjakubsamek'      # GitHub ucet
$Repo        = 'wp-install-script'    # nazev repa
$Ref         = 'main'                 # vetev nebo tag
$Restart     = $true                  # na konci restartovat
$PreviewOnly = $false                 # $true = jen vypsat co by se delalo, nic neinstalovat
# Log se uklada na plochu admina (viz 0b) - zadny zapis do C:\ProgramData
$InstallPrinter = $true               # tiskarna TOSHIBA-recepce se instaluje vzdy ($false = preskocit)
$RenameToSerial = $true               # prejmenovat pocitac dle serioveho cisla (projevi se po restartu)
$NamePrefix     = ''                  # volitelna predpona nazvu (napr. 'WP-'); prazdne = jen serial
$RemovePreinstalledOffice = $true     # PRVNI krok: odinstalovat OEM Office C2R + jazykove mutace + Store OneNote
$RemoveThirdPartyAV       = $true     # PRVNI krok: odinstalovat cizi antiviry (Defender a ESET nechat)
$UserDesktopShortcuts     = @('Google Chrome.lnk','Firefox.lnk','Outlook*.lnk','Word.lnk','Excel.lnk','TeamViewer.lnk')  # smazatelne kopie na plochu (Outlook* = i 'Outlook (classic)')
$ClearPublicDesktop       = $true     # smazat (ne-smazatelne) zastupce z verejne plochy
$SetWallpaper             = $true     # nastavit tapetu vsem uzivatelum
$SetLockScreen            = $true     # nastavit zamykaci obrazovku vsem uzivatelum
# Obrazky: skript zkusi stahnout z repa config/branding/{wallpaper.jpg,lockscreen.jpg};
# kdyz tam nejsou, pouzije vychozi Win11 img0.jpg.
$WallpaperFallback        = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
$LockScreenFallback       = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
$SetDefaultApps           = $true     # nasadit vychozi aplikace vsem (nove) uzivatelum z config/appassoc.xml
$AdminUser                = 'admin'   # ucet, kteremu se nastavi admin prava + heslo bez expirace (HESLO rucne)
# ====================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- 0) Kontrola admin prav ---
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Spust tento skript v ELEVOVANEM PowerShellu (Run as administrator)."
}

# --- 0a) Vypnout QuickEdit konzole (klik do okna jinak pozastavi beh az do stisku klavesy) ---
try {
    Add-Type -Name WPConsole -Namespace WP -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@ -ErrorAction SilentlyContinue
    $h = [WP.WPConsole]::GetStdHandle(-10)   # STD_INPUT_HANDLE
    $m = 0
    if ([WP.WPConsole]::GetConsoleMode($h, [ref]$m)) {
        $m = ($m -band (-bnot 0x40)) -band (-bnot 0x20)   # vypnout QuickEdit (0x40) a Insert (0x20)
        $m = $m -bor 0x80                                  # ENABLE_EXTENDED_FLAGS
        [WP.WPConsole]::SetConsoleMode($h, $m) | Out-Null
    }
} catch {}

# --- 0b) Log (transcript) na plochu admina (ne do C:) ---
$adminDesktop = [Environment]::GetFolderPath('DesktopDirectory')
if (-not $adminDesktop) { $adminDesktop = Join-Path $env:USERPROFILE 'Desktop' }
if (-not (Test-Path $adminDesktop)) { New-Item -ItemType Directory -Path $adminDesktop -Force | Out-Null }
$script:Issues = @()   # sem se sbira, co se behem skriptu nepovedlo (pro poznamku adminovi)
$logFile = Join-Path $adminDesktop ("install_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
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

# --- 3b) Prejmenovani pocitace dle serioveho cisla (BIOS) ---
if ($RenameToSerial) {
    try {
        $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
        if ($serial) { $serial = $serial.Trim() }
        $bad   = @('to be filled by o.e.m.','default string','system serial number','none','o.e.m.','0','na','')
        $clean = if ($serial) { ($serial -replace '[^A-Za-z0-9-]','') } else { '' }
        if ((-not $clean) -or ($serial.ToLower() -in $bad)) {
            Write-Warning "[!] Seriove cislo nepouzitelne ('$serial') - nazev pocitace nechavam."
        } else {
            $newName = ($NamePrefix + $clean)
            if ($newName.Length -gt 15) { $newName = $newName.Substring(0,15) }   # NetBIOS limit 15 znaku
            $newName = $newName.TrimEnd('-')
            if ($newName -and ($newName -ne $env:COMPUTERNAME)) {
                Write-Host "[*] Prejmenovani pocitace: $env:COMPUTERNAME -> $newName (projevi se po restartu)" -ForegroundColor Cyan
                if (-not $PreviewOnly) { Rename-Computer -NewName $newName -Force -ErrorAction Stop }
            } else {
                Write-Host "[*] Nazev pocitace '$env:COMPUTERNAME' - beze zmeny." -ForegroundColor DarkGray
            }
        }
    } catch { Write-Warning "[!] Prejmenovani pocitace: $($_.Exception.Message)" }
}

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
    @{ Id = 'Microsoft.Teams'; Scope = 'none' }                # novy Teams (work/school); MSIX -> bez --scope
    @{ Id = 'Microsoft.AzureVPNClient'; Scope = 'none' }       # Azure VPN Client (Win11+); samostatny winget instalator
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
    Write-Host "`nStore: vynuti aktualizaci aplikaci z Microsoft Store"
    Write-Host "Firefox: lokalizovany build primo od Mozilly (lang dle Windows)"
    Write-Host "Microsoft 365 Apps for business: ODT, jazyk=MatchOS, aktivace rucne"
    Write-Host "`nTweaky: tweaks/win10.ps1 + win10.psm1 + install.preset"
    Write-Host "Konfigy: config/pdfsam.reg, config/vlc.reg, config/pdfsam.l4j.ini, Adobe upsell off"
    Write-Host "Tiskarna TOSHIBA-recepce: $InstallPrinter"
    Write-Host "Prejmenovat dle serioveho cisla: $RenameToSerial (predpona '$NamePrefix')"
    Write-Host "Personalizace: Start vlevo, lupa ikona, pripony on, ikony plochy, taskbar pripnuti (Chrome,FF,Pruzkumnik,Outlook,Teams,Vystrizky)"
    Write-Host "Poznamka na plochu admina: ESET, tiskarny, migrace, Chrome, OneDrive, heslo+sifrovani"
    Write-Host "Predinstalacni uklid: OEM Office=$RemovePreinstalledOffice, cizi AV=$RemoveThirdPartyAV"
    Write-Host "Plocha uzivatele (smazatelne): $($UserDesktopShortcuts -join ', '); vycistit verejnou=$ClearPublicDesktop"
    Write-Host "Tapeta=$SetWallpaper, zamykaci obrazovka=$SetLockScreen (vsem uzivatelum, PersonalizationCSP)"
    Write-Host "Vychozi aplikace pro vsechny (DISM): $SetDefaultApps (config/appassoc.xml)"
    Write-Host "Napajeni: nejvyssi vykon, uspavani ze site=Nikdy; System Restore 5%; popisek C: = OS"
    Write-Host "Ucet admin: admin prava + heslo bez expirace (heslo rucne); Defender SmartScreen/PUA on; indexace Enhanced"
    Write-Host "Vlastni prikazy: BitLocker off, RDP UDP/dialog off, NCD auto-tiskarny off, feature-update fix, casove pasmo CET + sync"
    Write-Host "Restart na konci: $Restart"
    Write-Host "=====================================================`n" -ForegroundColor Magenta
    try { Stop-Transcript | Out-Null } catch {}
    return
}

# --- 5a) Predinstalacni uklid: OEM Office balast + cizi antiviry (bezi jako PRVNI) ---
Write-Host "[*] Predinstalacni uklid (OEM Office / OneNote / cizi AV)..." -ForegroundColor Cyan
function Get-Prop { param($obj,$name) if ($obj.PSObject.Properties[$name]) { $obj.PSObject.Properties[$name].Value } else { $null } }

# 1) Vsechny preinstalovane Office Click-to-Run produkty + jazykove mutace -> ODT Remove All
if ($RemovePreinstalledOffice) {
    try {
        & $winget install --id Microsoft.OfficeDeploymentTool -e --silent --accept-package-agreements --accept-source-agreements 2>$null
        $odtSetup = Join-Path $env:ProgramFiles 'OfficeDeploymentTool\setup.exe'
        if (Test-Path $odtSetup) {
            $rmXml = @"
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
"@
            Set-Content -Path "$work\office-remove.xml" -Value $rmXml -Encoding UTF8
            Write-Host "    [>] Odinstalace vsech Office C2R produktu (ODT Remove All)..." -ForegroundColor DarkGray
            Start-Process -FilePath $odtSetup -ArgumentList "/configure `"$work\office-remove.xml`"" -Wait -NoNewWindow
            Write-Host "    [i] OEM Office C2R odebran." -ForegroundColor DarkGray
        }
    } catch { $m = "OEM Office: ODT Remove All selhal ($($_.Exception.Message))"; Write-Warning "    $m"; $script:Issues += $m }

    # Store/UWP Office stuby + OneNote (vsem uzivatelum + provisioned, aby se nevracely)
    foreach ($pat in 'Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote','Microsoft.OneNote') {
        try { Get-AppxPackage -AllUsers -Name $pat -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue } catch {}
        try {
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $pat } |
                ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
        } catch {}
    }
}

# 2) Cizi antiviry (best-effort; Windows Defender a ESET ZAMERNE nechavame)
if ($RemoveThirdPartyAV) {
    try {
        $avRegex = 'McAfee|Norton|Avast|AVG|Avira|Kaspersky|Bitdefender|Webroot|Malwarebytes|Panda|Sophos|TotalAV'
        $uninstKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $found = Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object {
            $dn = Get-Prop $_ 'DisplayName'; $dn -and ($dn -match $avRegex)
        }
        if (-not $found) {
            Write-Host "    [i] Zadny cizi antivirus nenalezen." -ForegroundColor DarkGray
        } else {
            foreach ($p in $found) {
                $dn = Get-Prop $p 'DisplayName'
                $q  = Get-Prop $p 'QuietUninstallString'
                $u  = Get-Prop $p 'UninstallString'
                Write-Host "    [>] Odinstalace AV: $dn" -ForegroundColor DarkGray
                try {
                    if ($q) {
                        Start-Process cmd.exe -ArgumentList "/c `"$q`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    } elseif ($u -and ($u -match 'msiexec')) {
                        $code = [regex]::Match($u,'{[0-9A-Fa-f\-]+}').Value
                        if ($code) { Start-Process msiexec.exe -ArgumentList "/x $code /qn /norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue }
                    } else {
                        $m = "AV nelze ticho odinstalovat: $dn (nutny vendor nastroj - McAfee MCPR / Norton Remove Tool apod.)"
                        Write-Warning "      $m"; $script:Issues += $m
                    }
                } catch { $m = "AV odinstalace selhala: $dn ($($_.Exception.Message))"; Write-Warning "      $m"; $script:Issues += $m }
            }
        }
    } catch { Write-Warning "    Odebrani AV: $($_.Exception.Message)" }
}

# --- 5c) Instalace aplikaci ---
$ok = @(); $failed = @()
foreach ($a in $apps) {
    $wgArgs = @('install','--id', $a.Id, '-e', '--silent',
                '--accept-package-agreements','--accept-source-agreements',
                '--disable-interactivity')
    $scope = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
    if ($scope -ne 'none') { $wgArgs += @('--scope', $scope) }
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

# --- 5e) Aktualizace aplikaci z Microsoft Store (na pozadi, pokud je treba) ---
try {
    Write-Host "[*] Spoustim aktualizaci aplikaci z Microsoft Store..." -ForegroundColor Cyan
    Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop |
        Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop | Out-Null
    Write-Host "    [i] Store aktualizace spustena (probiha na pozadi)." -ForegroundColor DarkGray
} catch { Write-Warning "    Store aktualizace: $($_.Exception.Message)" }

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

# --- 6) Microsoft 365 Apps for business (ODT z webu pres winget, jazyk = MatchOS) ---
$odtDir = Join-Path $env:ProgramFiles 'OfficeDeploymentTool'
try {
    Write-Host "[*] Microsoft 365 Apps for business (ODT)..." -ForegroundColor Cyan
    # configuration.xml se generuje s JEDNIM jazykem dle Windows (MatchOS by nabral vic jazyku)
    $offLangMap = @{ cs = 'cs-cz'; en = 'en-us'; de = 'de-de' }
    $offLang = $offLangMap[$lang]
    $offXml = @"
<Configuration ID="vsenory-m365-business">
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365BusinessRetail">
      <Language ID="$offLang" />
    </Product>
  </Add>
  <Property Name="AUTOACTIVATE" Value="0" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Updates Enabled="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <RemoveMSI />
</Configuration>
"@
    Set-Content -Path "$work\office.xml" -Value $offXml -Encoding UTF8
    Write-Host "    [i] Office jazyk: $offLang (jediny)" -ForegroundColor DarkGray

    # winget stahne nejnovejsi ODT a rozbali setup.exe do %ProgramFiles%\OfficeDeploymentTool
    & $winget install --id Microsoft.OfficeDeploymentTool -e --silent `
        --accept-package-agreements --accept-source-agreements 2>$null
    $setup = Join-Path $odtDir 'setup.exe'
    if (-not (Test-Path $setup)) {
        $setup = Get-ChildItem $env:ProgramFiles -Recurse -Filter 'setup.exe' -ErrorAction SilentlyContinue |
                 Where-Object { $_.DirectoryName -match 'OfficeDeploymentTool' } |
                 Select-Object -First 1 -ExpandProperty FullName
    }
    if ($setup -and (Test-Path $setup)) {
        Write-Host "    ODT: $setup" -ForegroundColor DarkGray
        Start-Process -FilePath $setup -ArgumentList "/configure `"$work\office.xml`"" -Wait -NoNewWindow
        Write-Host "    [i] M365 Apps nainstalovany. Aktivace = rucne pri prihlaseni uzivatele." -ForegroundColor DarkGray
        $ok += 'Microsoft365Apps'
    } else {
        Write-Warning "    ODT setup.exe nenalezen - M365 preskoceno."
        $failed += 'Microsoft365Apps (ODT nenalezen)'
    }
} catch { Write-Warning "    M365 Apps: $($_.Exception.Message)"; $failed += 'Microsoft365Apps' }
finally {
    # uklid ODT (stejne jako ostatni docasne instalacky)
    if (Test-Path $odtDir) { Remove-Item $odtDir -Recurse -Force -ErrorAction SilentlyContinue }
}

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
        # overit, ze tiskarna opravdu vznikla, az pak nastavit prava a hlasit OK
        if (Get-Printer -Name 'TOSHIBA-recepce' -ErrorAction SilentlyContinue) {
            Get-RepoFile -Path 'SetACL.exe' -OutFile "$work\SetACL.exe"
            & "$work\SetACL.exe" -on "TOSHIBA-recepce" -ot prn -actn ace -ace "n:Everyone;p:man_docs" -ace "n:Everyone;p:print"
            Write-Host "    [i] Tiskarna TOSHIBA-recepce nainstalovana." -ForegroundColor DarkGray
            $ok += 'TOSHIBA-recepce'
        } else {
            Write-Warning "    Tiskarna se nevytvorila (ovladac/INF?) - viz vystup tisk-recepce.ps1 vyse."
            $failed += 'TOSHIBA-recepce (ovladac/INF)'
        }
    } catch {
        Write-Warning "    Tiskarna preskocena: $($_.Exception.Message)"
        $failed += "Tiskarna ($($_.Exception.Message))"
    }
}

# --- 8c) Vlastni prikazy (uprav/doplnuj dle potreby) ---
Write-Host "[*] Vlastni prikazy..." -ForegroundColor Cyan

# BitLocker: vypnout sifrovani C: a sluzbu BDESVC (dle interni vyjimky)
try {
    & manage-bde.exe -off C: *>$null   # na nesifrovanem disku hlasi chybu - swallneme
    Set-Service -Name 'BDESVC' -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name 'BDESVC' -Force -ErrorAction SilentlyContinue
    Write-Host "    [i] BitLocker C: vypinan, sluzba BDESVC disabled." -ForegroundColor DarkGray
} catch { Write-Warning "    BitLocker: $($_.Exception.Message)" }

# RDP: vypnout UDP (zasekavajici se obraz) + potlacit varovny dialog presmerovani
try {
    $tsc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'
    if (-not (Test-Path $tsc)) { New-Item -Path $tsc -Force | Out-Null }
    Set-ItemProperty -Path $tsc -Name 'fClientDisableUDP'               -Value 1 -Type DWord
    Set-ItemProperty -Path $tsc -Name 'RedirectionWarningDialogVersion' -Value 1 -Type DWord
    Write-Host "    [i] RDP: UDP vypnuto, varovny dialog potlacen." -ForegroundColor DarkGray
} catch { Write-Warning "    RDP tweaky: $($_.Exception.Message)" }

# Vypnout automaticke pridavani sitovych zarizeni/tiskaren (NCD AutoSetup)
try {
    $ncd = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private'
    if (-not (Test-Path $ncd)) { New-Item -Path $ncd -Force | Out-Null }
    Set-ItemProperty -Path $ncd -Name 'AutoSetup' -Value 0 -Type DWord
    Write-Host "    [i] Automaticke pridavani sitovych tiskaren vypnuto." -ForegroundColor DarkGray
} catch { Write-Warning "    NcdAutoSetup: $($_.Exception.Message)" }

# Odblokovat Windows feature updates (novy build):
# preset pres DisableTelemetry zastavi a zakaze sluzbu DiagTrack -> Windows pak nema
# data z "Compatibility Appraiseru" a novy build nenabidne. Tady surgicky vratime
# minimum nutne pro updaty (telemetrie = Required, DiagTrack on, appraiser spusten).
try {
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
                   'HKLM:\SOFTWARE\Microsoft\Windows\DataCollection') {
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name 'AllowTelemetry' -Value 1 -Type DWord   # 1 = Required
    }
    Set-Service  -Name 'DiagTrack' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
    $apprTask = '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    Enable-ScheduledTask -TaskName $apprTask -ErrorAction SilentlyContinue | Out-Null
    Start-ScheduledTask  -TaskName $apprTask -ErrorAction SilentlyContinue
    Write-Host "    [i] Feature updates odblokovany (telemetrie=Required, DiagTrack on, appraiser)." -ForegroundColor DarkGray
} catch { Write-Warning "    Feature-update fix: $($_.Exception.Message)" }

# Casove pasmo dle polohy + vynuceni synchronizace casu.
# Vsechny stroje jsou v CR -> nastavime rovnou CET (spolehlive) a zaroven zapneme
# automatiku dle polohy, aby se to samo opravilo, kdyby stroj jel jinam.
try {
    Set-TimeZone -Id 'Central European Standard Time' -ErrorAction SilentlyContinue
    # povolit sluzby polohy (nutne pro "nastavit pasmo automaticky")
    & reg add "HKLM\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" /v Status /t REG_DWORD /d 1 /f *>$null
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v Value /t REG_SZ /d Allow /f *>$null
    # "Nastavit casove pasmo automaticky" = sluzba tzautoupdate (Start=3 -> zapnuto)
    & reg add "HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate" /v Start /t REG_DWORD /d 3 /f *>$null
    # vynutit synchronizaci casu
    Set-Service  -Name w32time -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name w32time -ErrorAction SilentlyContinue
    & w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:manual /update *>$null
    & w32tm /resync /force *>$null
    Write-Host "    [i] Casove pasmo (CET + auto dle polohy) a synchronizace casu nastaveny." -ForegroundColor DarkGray
} catch { $m = "Cas/pasmo: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# Napajeci plan = nejvyssi vykon (sit i baterie) + power mode Best performance
try {
    & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c *>$null          # High performance plan
    & powercfg /overlaysetactive ded574b5-45a0-4f42-8737-46345c09c238 *>$null   # power mode = Best performance
    & powercfg /change standby-timeout-ac 0 *>$null                             # uspavani pri napajeni ze site = Nikdy
    Write-Host "    [i] Napajeni: nejvyssi vykon; uspavani ze site = Nikdy." -ForegroundColor DarkGray
} catch { $m = "Napajeni: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# System Restore - limit stinove kopie na 5 % disku C:
try {
    & vssadmin resize shadowstorage /for=C: /on=C: /maxsize=5% *>$null
    if ($LASTEXITCODE -ne 0) { & vssadmin add shadowstorage /for=C: /on=C: /maxsize=5% *>$null }
    Write-Host "    [i] System Restore: limit 5 % disku C:." -ForegroundColor DarkGray
} catch { $m = "System Restore limit: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# Popisek disku C: -> OS
try {
    Set-Volume -DriveLetter C -NewFileSystemLabel 'OS' -ErrorAction Stop
    Write-Host "    [i] Popisek disku C: = 'OS'." -ForegroundColor DarkGray
} catch {
    try { & label.exe C: OS } catch { $m = "Popisek disku C:: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }
}

# Defender - zapnout "Rizeni aplikaci a prohlizecu" (reputace + blokovani PUA) pro vsechny
try {
    Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v SmartScreenEnabled /t REG_SZ /d Warn /f *>$null
    & reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableSmartScreen /t REG_DWORD /d 1 /f *>$null
    & reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v ShellSmartScreenLevel /t REG_SZ /d Warn /f *>$null
    Write-Host "    [i] Defender: SmartScreen + blokovani PUA zapnuto." -ForegroundColor DarkGray
} catch { $m = "Defender SmartScreen/PUA: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# Ucet "admin": admin prava + heslo BEZ expirace (samotne HESLO se nastavuje rucne - viz poznamka)
try {
    if (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue) {
        Set-LocalUser  -Name $AdminUser -PasswordNeverExpires $true -ErrorAction SilentlyContinue
        Enable-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue
        $adminGrp = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue   # Administrators (locale-safe)
        if ($adminGrp) { try { Add-LocalGroupMember -Group $adminGrp -Member $AdminUser -ErrorAction Stop } catch {} }
        Write-Host "    [i] Ucet '$AdminUser': admin prava, heslo bez expirace (heslo nastav rucne)." -ForegroundColor DarkGray
    } else {
        $m = "Ucet '$AdminUser' neexistuje - vytvor rucne vcetne hesla"
        Write-Host "    [i] $m" -ForegroundColor DarkGray; $script:Issues += $m
    }
} catch { $m = "Ucet '$AdminUser': $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# Indexace: Enhanced mode (cely disk C:) + bezici sluzba Windows Search
try {
    & reg add "HKLM\SOFTWARE\Microsoft\Windows Search" /v EnableFindMyFiles /t REG_DWORD /d 1 /f *>$null
    Set-Service  -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue
    Restart-Service -Name WSearch -Force -ErrorAction SilentlyContinue
    Write-Host "    [i] Indexace: Enhanced (cely PC), sluzba Windows Search bezi." -ForegroundColor DarkGray
} catch { $m = "Indexace: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# --- 8d) Personalizace: hlavni panel, Start, plocha (aktualni + novi uzivatele) ---
# HKCU se tyka jen aktualniho uctu; aby nastaveni dostali i nove zalozeni uzivatele,
# zapisujeme zaroven do Default hive (C:\Users\Default\NTUSER.DAT).
Write-Host "[*] Personalizace (taskbar / Start / plocha)..." -ForegroundColor Cyan
try {
    $loaded = $false
    & reg load "HKU\WPDEF" "C:\Users\Default\NTUSER.DAT" *>$null
    if ($LASTEXITCODE -eq 0) { $loaded = $true }

    $targets = @('HKCU')
    if ($loaded) { $targets += 'HKU\WPDEF' }
    foreach ($r in $targets) {
        $adv = "$r\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        & reg add $adv /v TaskbarAl          /t REG_DWORD /d 0 /f *>$null   # Start/taskbar zarovnat doleva
        & reg add $adv /v TaskbarGlomLevel   /t REG_DWORD /d 0 /f *>$null   # vzdy slucovat (vypnout "roztahovani" oken)
        & reg add $adv /v MMTaskbarGlomLevel /t REG_DWORD /d 0 /f *>$null   # totez na sekundarnich monitorech
        & reg add $adv /v HideFileExt        /t REG_DWORD /d 0 /f *>$null   # zobrazit pripony souboru
        & reg add "$r\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 1 /f *>$null  # hledani = jen ikona (lupa)
        $nsp = "$r\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        & reg add $nsp /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f *>$null   # Tento pocitac
        & reg add $nsp /v "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" /t REG_DWORD /d 0 /f *>$null   # Slozka uzivatele
        & reg add $nsp /v "{645FF040-5081-101B-9F08-00AA002F954E}" /t REG_DWORD /d 0 /f *>$null   # Kos
    }
    if ($loaded) {
        [gc]::Collect(); Start-Sleep -Milliseconds 700
        & reg unload "HKU\WPDEF" *>$null
        if ($LASTEXITCODE -ne 0) { [gc]::Collect(); Start-Sleep -Seconds 1; & reg unload "HKU\WPDEF" *>$null }
    }
    Write-Host "    [i] Start vlevo, lupa jako ikona, pripony viditelne, ikony na plose (Tento PC/Slozka/Kos)." -ForegroundColor DarkGray
} catch { Write-Warning "    Personalizace registru: $($_.Exception.Message)" }

# Pripnuti na hlavni panel v presnem poradi (Edge pryc) pres LayoutModification.xml.
# Plati pro NOVE prihlasene uzivatele (zaklada se z Default profilu).
try {
    function Find-Lnk { param([string[]]$Names)
        $root = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        foreach ($n in $Names) {
            $f = Get-ChildItem -Path $root -Recurse -Filter $n -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
        return $null
    }
    $ff = Find-Lnk @('Firefox.lnk','Mozilla Firefox.lnk')
    $gc = Find-Lnk @('Google Chrome.lnk','Chrome.lnk')
    $ol = Find-Lnk @('Outlook.lnk','Outlook (classic).lnk','Microsoft Outlook.lnk')

    $pins = ''
    if ($gc) { $pins += "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$gc`" />`r`n" }
    if ($ff) { $pins += "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$ff`" />`r`n" }
    $pins += "        <taskbar:DesktopApp DesktopApplicationID=`"Microsoft.Windows.Explorer`" />`r`n"
    if ($ol) { $pins += "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$ol`" />`r`n" }
    $pins += "        <taskbar:UWA AppUserModelID=`"MSTeams_8wekyb3d8bbwe!MSTeams`" />`r`n"
    $pins += "        <taskbar:UWA AppUserModelID=`"Microsoft.ScreenSketch_8wekyb3d8bbwe!App`" />`r`n"

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$pins      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
    $shellDir = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell'
    if (-not (Test-Path $shellDir)) { New-Item -ItemType Directory -Path $shellDir -Force | Out-Null }
    Set-Content -Path (Join-Path $shellDir 'LayoutModification.xml') -Value $xml -Encoding UTF8
    Write-Host "    [i] Taskbar pripnuti (Chrome, Firefox, Pruzkumnik, Outlook, Teams, Vystrizky) pro nove uzivatele." -ForegroundColor DarkGray
} catch { Write-Warning "    Taskbar pripnuti: $($_.Exception.Message)" }

# --- 8e) Poznamka na plochu admina (co dodelat po instalaci) ---
try {
    $todo = @(
        'ADMIN – dodělat po instalaci'
        '============================'
        ''
        '• ESET – doinstalovat'
        '• TeamViewer – nastavit statické heslo'
        '• Tiskárny'
        '• Migrace dat'
        '• Google Chrome – záložky a hesla (kontrola)'
        '• OneDrive – přihlášení'
        '• Heslo počítače + ESET šifrování'
        '• Kontrola povolení Defenderu'
        '• Nastavit heslo k účtu admin (Windows)'
        '• Ověřit indexaci Outlooku po nastavení e-mailového účtu'
    )
    # co se behem skriptu nepovedlo (neuspesne instalace + problemy z uklidu apod.)
    $problems = @()
    if ($failed)        { $problems += $failed }
    if ($script:Issues) { $problems += $script:Issues }
    $todo += ''
    $todo += 'Co se NEPOVEDLO automaticky (zkontrolovat):'
    $todo += '-------------------------------------------'
    if ($problems) { foreach ($x in $problems) { $todo += "• $x" } }
    else           { $todo += '• (nic – vše proběhlo OK)' }
    $todo += ''
    $todo += "Detailní log: $logFile"
    $noteText = $todo -join "`r`n"
    $notePath = Join-Path $adminDesktop 'ADMIN - po instalaci.txt'
    Set-Content -Path $notePath -Value $noteText -Encoding UTF8
    Write-Host "    [i] Poznamka na plochu: $notePath" -ForegroundColor DarkGray
} catch { Write-Warning "    Poznamka na plochu: $($_.Exception.Message)" }

# --- 8f) Zastupci na plochu uzivatele (smazatelne) + uklid verejne plochy ---
# Verejna plocha (C:\Users\Public\Desktop) je pro ne-adminy NESMAZATELNA. Proto davame
# zastupce do Default\Desktop -> kazdy novy uzivatel dostane VLASTNI kopii, kterou smaze.
try {
    $defDesk = 'C:\Users\Default\Desktop'
    if (-not (Test-Path $defDesk)) { New-Item -ItemType Directory -Path $defDesk -Force | Out-Null }
    $startRoot = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    foreach ($name in $UserDesktopShortcuts) {
        $lnk = Get-ChildItem -Path $startRoot -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) {
            Copy-Item $lnk.FullName -Destination $defDesk      -Force -ErrorAction SilentlyContinue   # novi uzivatele
            Copy-Item $lnk.FullName -Destination $adminDesktop -Force -ErrorAction SilentlyContinue   # aby je videl i admin
            Write-Host "    [+] plocha: $($lnk.Name)" -ForegroundColor DarkGray
        } else {
            Write-Host "    [-] zastupce nenalezen: $name" -ForegroundColor DarkGray
        }
    }
    if ($ClearPublicDesktop) {
        Get-ChildItem 'C:\Users\Public\Desktop\*.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "    [i] Verejna plocha vycistena (nesmazatelni zastupci pryc)." -ForegroundColor DarkGray
    }
} catch { Write-Warning "    Zastupci na plochu: $($_.Exception.Message)" }

# --- 8g) Tapeta + zamykaci obrazovka pro vsechny uzivatele (PersonalizationCSP) ---
Write-Host "[*] Tapeta a zamykaci obrazovka..." -ForegroundColor Cyan
try {
    $brandDir = 'C:\ProgramData\WPBranding'
    if (-not (Test-Path $brandDir)) { New-Item -ItemType Directory -Path $brandDir -Force | Out-Null }

    # obrazky drzime v $brandDir (i vychozi Win11), aby CSP mel stabilni cestu mimo C:\Windows
    $wall = "$brandDir\wallpaper.jpg"
    try { Get-RepoFile -Path 'config/branding/wallpaper.jpg'  -OutFile $wall } catch { Copy-Item $WallpaperFallback  $wall -Force -ErrorAction SilentlyContinue }
    $lock = "$brandDir\lockscreen.jpg"
    try { Get-RepoFile -Path 'config/branding/lockscreen.jpg' -OutFile $lock } catch { Copy-Item $LockScreenFallback $lock -Force -ErrorAction SilentlyContinue }

    $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    if (-not (Test-Path $csp)) { New-Item -Path $csp -Force | Out-Null }

    if ($SetWallpaper -and (Test-Path $wall)) {
        Set-ItemProperty -Path $csp -Name 'DesktopImagePath'   -Value $wall -Type String
        Set-ItemProperty -Path $csp -Name 'DesktopImageUrl'    -Value $wall -Type String
        Set-ItemProperty -Path $csp -Name 'DesktopImageStatus' -Value 1 -Type DWord
        Write-Host "    [i] Tapeta: $wall" -ForegroundColor DarkGray
    }
    if ($SetLockScreen -and (Test-Path $lock)) {
        Set-ItemProperty -Path $csp -Name 'LockScreenImagePath'   -Value $lock -Type String
        Set-ItemProperty -Path $csp -Name 'LockScreenImageUrl'    -Value $lock -Type String
        Set-ItemProperty -Path $csp -Name 'LockScreenImageStatus' -Value 1 -Type DWord
        Write-Host "    [i] Zamykaci obrazovka: $lock" -ForegroundColor DarkGray
    }
    # ukazovat obrazek zamykaci obrazovky i na prihlasovaci obrazovce (0 = ukazovat)
    $sysPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    if (-not (Test-Path $sysPol)) { New-Item -Path $sysPol -Force | Out-Null }
    Set-ItemProperty -Path $sysPol -Name 'DisableLogonBackgroundImage' -Value 0 -Type DWord
} catch { $m = "Tapeta/zamykaci obrazovka: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# --- 8h) Vychozi aplikace pro vsechny (nove) uzivatele - DISM import ---
if ($SetDefaultApps) {
    try {
        Get-RepoFile -Path 'config/appassoc.xml' -OutFile "$work\appassoc.xml"
        & dism.exe /Online /Import-DefaultAppAssociations:"$work\appassoc.xml" *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [i] Vychozi aplikace nasazeny (plati pro nove uzivatele)." -ForegroundColor DarkGray
        } else {
            $m = "Vychozi aplikace: DISM import skoncil s kodem $LASTEXITCODE"
            Write-Warning "    $m"; $script:Issues += $m
        }
    } catch {
        $m = "Vychozi aplikace: chybi config/appassoc.xml v repu nebo import selhal ($($_.Exception.Message))"
        Write-Warning "    $m"; $script:Issues += $m
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
