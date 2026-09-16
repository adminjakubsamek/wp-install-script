#Requires -Version 5.1
<#
    Vsenory - Win11 provisioning bootstrap (v1, k otestovani na jednom stroji)
    --------------------------------------------------------------------------
    Spustit v ELEVOVANEM PowerShellu na ciste instalaci Win11 po prvnim spusteni.
    Nezavisi na NASce ani na jednotce Q: - vse se tahne z verejneho GitHub repa
    a z webu vyrobcu (nejnovejsi verze) pres winget.

    Priklad spusteni (jeden radek, elevovany PowerShell) - URL = $BaseUrl/bootstrap.ps1 (+ pripadne $Sas):
      irm "https://<ucet>.z13.web.core.windows.net/bootstrap.ps1" | iex
    (Docasne z GitHubu: irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex)

    Log z kazdeho behu: na plochu admina (install_<datum>_<cas>.log)
    Nahled bez instalace: nahore prepni $PreviewOnly = $true (jen vypise plan a skonci).
#>

# ============================ KONFIGURACE ============================
# Zdroj vsech souboru (bootstrap.ps1 + tweaks/ + config/ + *.exe + ToshibaDRV.zip). BEZ prihlasovani.
#   - Azure Storage static website:  https://<ucet>.z13.web.core.windows.net
#   - nebo blob kontejner:           https://<ucet>.blob.core.windows.net/<kontejner>
#   - GitHub raw (docasne/testovaci): https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main
$BaseUrl     = 'https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main'
$Sas         = ''   # volitelny read-only SAS vcetne '?', napr. '?sv=...&sig=...'; prazdne = anonymni/verejne
$DriverUrl   = 'https://github.com/adminjakubsamek/wp-install-script/releases/latest/download/ToshibaDRV.zip'  # ovladac tiskarny (GitHub release asset); pri migraci na Storage sem dej Storage URL
$Restart     = $true                  # na konci restartovat
$PreviewOnly = $false                 # $true = jen vypsat co by se delalo, nic neinstalovat
# Log se uklada na plochu admina (viz 0b) - zadny zapis do C:\ProgramData
$InstallPrinter = $true               # tiskarna TOSHIBA-recepce se instaluje vzdy ($false = preskocit)
$RenameToSerial = $true               # prejmenovat pocitac dle serioveho cisla (projevi se po restartu)
$NamePrefix     = ''                  # volitelna predpona nazvu (napr. 'WP-'); prazdne = jen serial
$RenameOnlyDefaultNames = $true       # prejmenovat JEN kdyz ma PC tovarni/vychozi nazev; vlastni nazvy nechat byt
$DefaultNamePatterns = @(             # co se povazuje za vychozi nazev (regex, case-insensitive)
    '^DESKTOP-[A-Z0-9]{7}$'           # standardni Windows (DESKTOP-ABC1234)
    '^LAPTOP-[A-Z0-9]{7}$'
    '^WIN-[A-Z0-9]{11}$'              # Windows Server / sysprep
    '^MININT-[A-Z0-9]+$'              # WinPE / MDT
    '^(USER|USER-PC|PC|COMPUTER|MYPC|HOME|OEM)$'
)
$RemoveENKeyboard = $true             # odebrat sekundarni en-US klavesnici (jen kdyz neni jazykem systemu)
$RemovePreinstalledOffice = $true     # PRVNI krok: odinstalovat OEM Office C2R + jazykove mutace + Store OneNote
$RemoveThirdPartyAV       = $true     # PRVNI krok: odinstalovat cizi antiviry (Defender a ESET nechat)
# Smazatelne kopie zastupcu na plochu. Alternativni nazvy se oddeluji svislitkem '|'
# (pouzije se prvni nalezeny) - ruzne verze pojmenovavaji zastupce ruzne. '|' v nazvu souboru byt nemuze.
$UserDesktopShortcuts     = @(
    'Google Chrome.lnk'
    'Firefox.lnk'
    'Outlook (classic).lnk|Outlook.lnk'                                 # klasicky Outlook ma prednost
    'Word.lnk'
    'Excel.lnk'
    'TeamViewer.lnk'
    'Adobe Acrobat.lnk|Acrobat Reader.lnk|Adobe Acrobat Reader*.lnk'    # nazev se lisi podle verze
    'PDFsam Basic.lnk|PDFsam*.lnk'
)
$ClearPublicDesktop       = $true     # smazat (ne-smazatelne) zastupce z verejne plochy
$SetWallpaper             = $true     # nastavit vychozi tapetu (MENITELNOU) aktualnimu i novym uzivatelum
$SetLockScreen            = $false    # $true nastavi zamykaci obrazovku, ale UZAMKNE ji (Win11 jinak neumi) -> vychozi vypnuto
# Obrazky: skript zkusi stahnout z repa config/branding/{wallpaper.jpg,lockscreen.jpg};
# kdyz tam nejsou, pouzije vychozi Win11 img0.jpg.
$WallpaperFallback        = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
$LockScreenFallback       = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
$SetDefaultApps           = $true     # vychozi aplikace pro NOVE uzivatele (Chrome/VLC/Adobe/Outlook/7-Zip) pres DISM; ProgID cte z registru
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
$script:sourceRepaired = $false; $script:wingetReRegistered = $false
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
    $uri = "$BaseUrl/$Path$Sas"
    $dir = Split-Path $OutFile -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Invoke-WebRequest -Uri $uri -OutFile $OutFile -UseBasicParsing
    Write-Host "    [+] $Path" -ForegroundColor DarkGray
}

function Get-UrlQuiet {
    # stahne soubor z plne URL; pri 404/chybe NEhazi (zadny sum v logu), vraci $true/$false. Nasleduje presmerovani (napr. GitHub release).
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$OutFile)
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $hc = New-Object System.Net.Http.HttpClient
        $resp = $hc.GetAsync($Url).GetAwaiter().GetResult()
        $ok = $false
        if ($resp.IsSuccessStatusCode) {
            $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $dir = Split-Path $OutFile -Parent
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllBytes($OutFile, $bytes)
            $ok = $true
        }
        $hc.Dispose(); return $ok
    } catch { return $false }
}
function Get-RepoFileQuiet {
    # stahne soubor z repa ($BaseUrl); pri 404 NEhazi chybu, vraci $true/$false
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OutFile)
    return (Get-UrlQuiet -Url "$BaseUrl/$Path$Sas" -OutFile $OutFile)
}
function Get-PendingRebootKind {
    # 'hard' = C2R instalace Office skoro jiste skonci chybou 1603 -> nezkouset a odlozit za restart
    # 'soft' = slaby signal (prejmenovani souboru po instalacich) - instalaci zkusit, pri selhani odlozit
    # 'none' = nic neceka
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    try {
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return 'hard' }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return 'hard' }
        $cn  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
        $acn = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
        if ($cn -and $acn -and ($cn -ne $acn)) { return 'hard' }   # ceka prejmenovani pocitace
        # PendingFileRenameOperations nechava za sebou skoro kazdy instalator - samo o sobe to Office nezablokuje
        $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations
        if ($pfro -and $pfro.PendingFileRenameOperations) { return 'soft' }
        return 'none'
    } finally { $ErrorActionPreference = $eap }
}
function Register-OfficePostRestart {
    # dolozi instalaci M365 po restartu: naplanovana uloha jako SYSTEM pri startu, po uspechu se sama smaze
    param([Parameter(Mandatory)][string]$SetupExe, [Parameter(Mandatory)][string]$ConfigXml)
    try {
        $base = 'C:\ProgramData\WPBranding\Office'
        if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
        Copy-Item $SetupExe  "$base\setup.exe"  -Force
        Copy-Item $ConfigXml "$base\office.xml" -Force
        $runner = @'
$ErrorActionPreference = 'SilentlyContinue'
$base = 'C:\ProgramData\WPBranding\Office'
$log  = "$base\post-restart.log"
$key  = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
function W([string]$t) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $t" | Out-File $log -Append -Encoding UTF8 }
function Test-Office { $c = Get-ItemProperty $key; return ($c -and $c.ProductReleaseIds -match 'O365BusinessRetail') }
function Add-OfficeShortcuts {
    # po instalaci doplnit zastupce Wordu/Excelu/Outlooku na plochy (pri behu skriptu jeste neexistovaly)
    $src = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs'
    $desks = @('C:\Users\Default\Desktop')
    $desks += (Get-ChildItem 'C:\Users' -Directory | Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' } | ForEach-Object { Join-Path $_.FullName 'Desktop' })
    foreach ($pat in 'Outlook (classic).lnk','Outlook.lnk','Word.lnk','Excel.lnk') {
        $lnk = Get-ChildItem $src -Recurse -Filter $pat | Select-Object -First 1
        if (-not $lnk) { continue }
        if ($pat -eq 'Outlook.lnk' -and (Get-ChildItem $src -Recurse -Filter 'Outlook (classic).lnk')) { continue }
        foreach ($d in $desks) { if (Test-Path $d) { Copy-Item $lnk.FullName (Join-Path $d $lnk.Name) -Force } }
    }
    W 'Zastupci Office doplneni na plochy.'
}
W 'Start po restartu.'
if (Test-Office) { W 'Office uz je nainstalovan - ukol splnen.'; Add-OfficeShortcuts; Unregister-ScheduledTask -TaskName 'WP-Office-Install' -Confirm:$false; return }
Start-Sleep -Seconds 120
for ($i = 0; $i -lt 60; $i++) {   # pockat, az dobehne Windows Update / jine instalace (max ~30 min)
    if (-not (Get-Process TrustedInstaller,TiWorker,msiexec)) { break }
    Start-Sleep -Seconds 30
}
W 'Spoustim ODT...'
$arg = '/configure "' + $base + '\office.xml"'
$p = Start-Process "$base\setup.exe" -ArgumentList $arg -Wait -NoNewWindow -PassThru
W ('ODT navratovy kod: ' + $p.ExitCode)
for ($i = 0; $i -lt 18; $i++) {
    if (Test-Office) { W 'M365 nainstalovan - ukol splnen.'; Add-OfficeShortcuts; Unregister-ScheduledTask -TaskName 'WP-Office-Install' -Confirm:$false; return }
    Start-Sleep -Seconds 10
}
W 'Nepovedlo se - uloha zustava a zkusi to po dalsim restartu.'
'@
        [System.IO.File]::WriteAllText("$base\install-office.ps1", $runner, (New-Object System.Text.UTF8Encoding($false)))
        $act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$base\install-office.ps1`""
        $trg  = New-ScheduledTaskTrigger -AtStartup
        $prin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $set  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName 'WP-Office-Install' -Action $act -Trigger $trg -Principal $prin -Settings $set -Force -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

# --- 3) Detekce jazyka Windows (display language) - aplikace se instaluji v jazyce Windows ---
try   { $tag = (Get-WinUserLanguageList)[0].LanguageTag }   # napr. ro-RO, cs-CZ
catch { $tag = (Get-Culture).Name }
if (-not $tag) { $tag = 'en-US' }
$lang     = ($tag.Split('-')[0]).ToLower()   # dvoupismenne: ro, cs, en, de...
$offLang  = $tag.ToLower()                    # Office kod: ro-ro, cs-cz, en-us, de-de...
$ffLang   = if ($lang -eq 'en') { 'en-US' } else { $lang }                              # Mozilla locale
$dopdfLang = if ($lang -in @('cs','en','de','fr','it','es','nl','pl','pt','ru','tr','sk','hu')) { $lang } else { 'en' }
Write-Host "[*] Jazyk Windows: $tag (aplikace v tomto jazyce; Office=$offLang)" -ForegroundColor Cyan

# --- 3b) Prejmenovani pocitace dle serioveho cisla (BIOS) ---
if ($RenameToSerial) {
    try {
        # prejmenovavat jen tovarni nazvy - rucne pojmenovane PC nechat byt
        $isDefaultName = $false
        foreach ($rx in $DefaultNamePatterns) { if ($env:COMPUTERNAME -match $rx) { $isDefaultName = $true; break } }
        if ($RenameOnlyDefaultNames -and -not $isDefaultName) {
            Write-Host "[*] Nazev pocitace '$env:COMPUTERNAME' neni tovarni - prejmenovani preskoceno." -ForegroundColor DarkGray
            $script:skipRename = $true
        }
        $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
        if ($serial) { $serial = $serial.Trim() }
        $bad   = @('to be filled by o.e.m.','default string','system serial number','none','o.e.m.','0','na','')
        $clean = if ($serial) { ($serial -replace '[^A-Za-z0-9-]','') } else { '' }
        if ($script:skipRename) {
            # nic - nazev nastavil admin rucne
        } elseif ((-not $clean) -or ($serial.ToLower() -in $bad)) {
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
function Test-WingetPath {
    # kandidat je pouzitelny jen tehdy, kdyz opravdu BEZI (cesta ve WindowsApps casto konci "Zugriff verweigert")
    param([string]$Exe)
    if (-not $Exe) { return $false }
    if (-not (Test-Path $Exe)) { return $false }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    try {
        $global:LASTEXITCODE = 9999          # aby stary kod nezpusobil falesne pozitivni vysledek
        $out = & $Exe --version 2>&1
        return (($LASTEXITCODE -eq 0) -and ("$out" -match '\d+\.\d+'))   # musi vratit i cislo verze
    } catch { return $false } finally { $ErrorActionPreference = $eap }
}
function Get-WingetCandidates {
    $c = @()
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { $c += $cmd.Source }
    $c += "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"          # alias aktualniho uzivatele (funguje i po elevaci)
    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
           Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) { $c += (Join-Path $pkg.InstallLocation 'winget.exe') }
    $c += (Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
    return ($c | Where-Object { $_ } | Select-Object -Unique)
}
function Resolve-Winget {
    foreach ($cand in (Get-WingetCandidates)) { if (Test-WingetPath $cand) { return $cand } }

    # nic nebezi - typicky "App Installer" neni zaregistrovany pro tento ucet (cesta ve WindowsApps = Zugriff verweigert).
    Write-Host "[*] winget nelze spustit - zkousim preregistrovat balicek 'App Installer' pro tento ucet..." -ForegroundColor DarkYellow
    $script:wingetReRegistered = $true
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
    try {
        $all = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller | Sort-Object Version -Descending | Select-Object -First 1
        if ($all -and $all.InstallLocation) {
            $man = Join-Path $all.InstallLocation 'AppXManifest.xml'
            if (Test-Path $man) { Add-AppxPackage -DisableDevelopmentMode -Register $man }
        }
    } catch { } finally { $ErrorActionPreference = $eap }

    foreach ($cand in (Get-WingetCandidates)) { if (Test-WingetPath $cand) { return $cand } }
    throw "winget neni k dispozici (nebo ho tento ucet nesmi spustit). Otevri Microsoft Store, aktualizuj 'App Installer', pripadne spust skript pod uctem, ktery uz winget pouzil, a zkus znovu."
}
function Invoke-Winget {
    # volani wingetu, ktere NIKDY neshodi skript (nativni chyba na stderr by pri EAP='Stop' ukoncila cely beh).
    # POZOR: argumenty se predavaji jako POLE pres -WgArgs; jinak by PowerShell bral '-e' jako svuj vlastni parametr.
    param([string[]]$WgArgs)
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    # winget pise UTF-8; konzole ma ale narodni znakovou stranku (CP852/850), takze by se z bloku
    # prubehu staly patvary typu "ÔûêÔûê". Na dobu volani prepneme dekodovani na UTF-8.
    $encOld = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
        # pruh prubehu a procenta do logu nepatri - filtrujeme je, at je vypis citelny (jinak ~1700 radku navic)
        $blocks = @([char]0x2588, [char]0x2592, [char]0x2591, [char]0x25A0)
        & $script:winget @WgArgs 2>&1 | ForEach-Object {
            $line = "$_"
            $skip = $false
            foreach ($b in $blocks) { if ($line.IndexOf($b) -ge 0) { $skip = $true; break } }
            if (-not $skip -and ($line -match '^\s*[-\\/|]\s*$' -or $line -match '^\s*\d+%\s*$')) { $skip = $true }
            if (-not $skip -and $line.Trim()) { Write-Host $line }
        }
        return $LASTEXITCODE
    } catch {
        Write-Warning "    winget selhal: $($_.Exception.Message)"
        return -1
    } finally {
        $ErrorActionPreference = $eap
        try { [Console]::OutputEncoding = $encOld } catch { }
    }
}
function Repair-WingetSource {
    # 0x8A15000F = poskozeny/chybejici index zdroju (typicky po preregistraci App Installeru). Provede se jednou za beh.
    if ($script:sourceRepaired) { return $false }
    $script:sourceRepaired = $true
    Write-Host "    [~] Zdroj wingetu je poskozeny - provadim 'source reset' + 'source update'..." -ForegroundColor DarkYellow
    $null = Invoke-Winget -WgArgs @('source','reset','--force')
    $null = Invoke-Winget -WgArgs @('source','update')
    return $true
}
function Invoke-WingetInstall {
    # instalace s opakovanim: 1618 (jina instalace bezi) a 0x8A15000F (rozbity zdroj -> reset a znovu)
    param([string[]]$WgArgs)
    # kody podle oficialni tabulky winget (returnCodes.md)
    $okCodes     = @(0, -1978335189, -1978335135, -1978334963, -1978335153)  # OK / neni co aktualizovat / uz nainstalovano / verze neni novejsi
    $retryCodes  = @(-1978334974,   # 0x8A150102 jina instalace prave bezi (ekvivalent 1618)
                     -1978334975,   # 0x8A150101 aplikace bezi
                     -1978334973,   # 0x8A150103 soubor se prave pouziva
                     -1978335123)   # 0x8A15006D potrebna sluzba je zaneprazdnena
    $sourceCodes = @(-1978335217,   # 0x8A15000F chybi data zdroje
                     -1978335163,   # 0x8A150045 zdroj se nepodarilo otevrit
                     -1978335157,   # 0x8A15004B nepodarilo se otevrit zadny zdroj
                     -1978335169,   # 0x8A15003F data zdroje jsou poskozena
                     -1978335222,   # 0x8A15000A index je poskozeny
                     -1978335221)   # 0x8A15000B konfigurace zdroju je poskozena
    $code = $null
    for ($try = 1; $try -le 4; $try++) {
        $code = Invoke-Winget -WgArgs $WgArgs
        if ($okCodes -contains $code) { break }
        if ($try -lt 4 -and $sourceCodes -contains $code) {
            if (Repair-WingetSource) { continue }        # po oprave zkusit hned znovu
            break                                        # oprava uz probehla a nepomohla -> nema smysl dal
        }
        if ($try -lt 4 -and $retryCodes -contains $code) {
            Write-Host "    [~] Instalace je blokovana (bezi jina instalace / aplikace / soubor se pouziva) - cekam 30 s, pokus $try/3..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds 30
            continue
        }
        break   # jina chyba -> opakovani nema smysl
    }
    return $code
}
$winget = Resolve-Winget
$script:winget = $winget
Write-Host "[*] winget: $winget" -ForegroundColor Cyan
# po preregistraci balicku byva index zdroju prazdny/rozbity (0x8A15000F) - poresit rovnou, ne az u prvni aplikace
if ($script:wingetReRegistered) { $null = Repair-WingetSource }

# --- 5) Seznam aplikaci (winget ID) + jazykove/scope vyjimky ---
#     Apps bez poznamky se ridi jazykem Windows automaticky (7zip, VLC, Chrome, Reader).
$apps = @(
    @{ Id = 'Google.Chrome' }                                  # UI dle OS
    @{ Id = '7zip.7zip' }                                      # multijazycny, dle OS
    @{ Id = 'VideoLAN.VLC' }                                   # multijazycny, dle OS  (+ vlc.reg)
    @{ Id = 'Adobe.Acrobat.Reader.64-bit' }                    # MUI dle OS  (OVERIT na 1. stroji)
    @{ Id = 'PDFsam.PDFsam' }                                  # (+ pdfsam.reg, pdfsam.l4j.ini)
    @{ Id = 'Softland.doPDF.11'; Custom = "-install_language=$dopdfLang" }
    @{ Id = 'Oracle.JavaRuntimeEnvironment' }                  # Oracle Java 8 (klasicka java.com); komercne licence!
    @{ Id = 'OpenVPNTechnologies.OpenVPN' }                    # OpenVPN Community klient (profily rucne)
    @{ Id = 'TeamViewer.TeamViewer'; SkipIfRunning = 'TeamViewer' }   # upgrade za bezici vzdalene relace vzdy selze (kod 2)
    @{ Id = 'Microsoft.Teams'; Scope = 'none' }                # novy Teams (work/school); MSIX -> bez --scope
    @{ Id = 'Microsoft.AzureVPNClient'; Scope = 'none' }       # Azure VPN Client (Win11+); samostatny winget instalator
)

# --- 5b) Nahled bez instalace ---
if ($PreviewOnly) {
    Write-Host "`n===== NAHLED (PreviewOnly) - nic se neinstaluje =====" -ForegroundColor Magenta
    Write-Host "Jazyk Windows: $tag (aplikace v tomto jazyce; Office=$offLang)"
    Write-Host "`nAplikace (winget):"
    foreach ($a in $apps) {
        $sc = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
        $cu = if ($a.ContainsKey('Custom')) { "  custom: $($a.Custom)" } else { '' }
        Write-Host ("  - {0}  (scope={1}){2}" -f $a.Id, $sc, $cu)
    }
    Write-Host "`nStore: vynuti aktualizaci aplikaci z Microsoft Store"
    Write-Host "Firefox: lokalizovany build primo od Mozilly (lang dle Windows)"
    Write-Host "Microsoft 365 Apps for business: ODT, jazyk dle Windows ($offLang), aktivace rucne"
    Write-Host "`nTweaky: tweaks/win10.ps1 + win10.psm1 + install.preset"
    Write-Host "Konfigy: config/pdfsam.reg, config/vlc.reg, config/pdfsam.l4j.ini, Adobe upsell off"
    Write-Host "Tiskarna TOSHIBA-recepce: $InstallPrinter"
    Write-Host "Prejmenovat dle serioveho cisla: $RenameToSerial (predpona '$NamePrefix')"
    Write-Host "Personalizace: Start vlevo, lupa ikona, pripony on, ikony plochy, taskbar pripnuti (Chrome,FF,Pruzkumnik,Outlook,Teams,Vystrizky)"
    Write-Host "Poznamka na plochu admina: ESET, tiskarny, migrace, Chrome, OneDrive, heslo+sifrovani"
    Write-Host "Predinstalacni uklid: OEM Office=$RemovePreinstalledOffice, cizi AV=$RemoveThirdPartyAV"
    Write-Host "Plocha uzivatele (smazatelne): $($UserDesktopShortcuts -join ', '); vycistit verejnou=$ClearPublicDesktop"
    Write-Host "Tapeta=$SetWallpaper (menitelna), zamykaci obrazovka=$SetLockScreen (pokud ano, uzamkne ji)"
    Write-Host "Vychozi aplikace: $SetDefaultApps (Chrome/VLC/Adobe/Outlook/7-Zip; DISM = nove uzivatele)"
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

# 1) Office: nas M365 (O365BusinessRetail) ponechat a jen zaktualizovat; cizi/OEM Office odstranit
$script:officeHave = $false; $script:officeIsOurs = $false; $script:officeRemoved = $false
try {
    $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($c2r -and $c2r.PSObject.Properties['ProductReleaseIds']) {
        $script:officeHave = $true
        if ($c2r.ProductReleaseIds -match 'O365BusinessRetail') { $script:officeIsOurs = $true }
    }
} catch {}

if ($RemovePreinstalledOffice -and $script:officeHave -and -not $script:officeIsOurs) {
    try {
        $null = Invoke-WingetInstall -WgArgs @('install','--id','Microsoft.OfficeDeploymentTool','-e','--silent','--source','winget','--accept-package-agreements','--accept-source-agreements')
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
            Write-Host "    [>] Odinstalace cizich Office C2R produktu (ODT Remove All)..." -ForegroundColor DarkGray
            Start-Process -FilePath $odtSetup -ArgumentList "/configure `"$work\office-remove.xml`"" -Wait -NoNewWindow
            Write-Host "    [i] Cizi/OEM Office C2R odebran (vyzaduje restart pred novou instalaci)." -ForegroundColor DarkGray
            $script:officeHave = $false
            $script:officeRemoved = $true
        }
    } catch { $m = "OEM Office: ODT Remove All selhal ($($_.Exception.Message))"; Write-Warning "    $m"; $script:Issues += $m }
} elseif ($script:officeIsOurs) {
    Write-Host "    [i] M365 (O365BusinessRetail) uz je nainstalovan - neodstranuji (jen se zaktualizuje)." -ForegroundColor DarkGray
} else {
    Write-Host "    [i] Zadny cizi Office k odebrani." -ForegroundColor DarkGray
}

# Store/UWP Office stuby + OneNote (vsem uzivatelum + provisioned) - idempotentni, vzdy
if ($RemovePreinstalledOffice) {
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
    $wgArgs = @('install','--id', $a.Id, '-e', '--silent', '--source', 'winget',
                '--accept-package-agreements','--accept-source-agreements',
                '--disable-interactivity')
    $scope = if ($a.ContainsKey('Scope')) { $a.Scope } else { 'machine' }
    if ($scope -ne 'none') { $wgArgs += @('--scope', $scope) }
    if ($a.ContainsKey('Custom')) { $wgArgs += @('--custom', $a.Custom) }

    Write-Host "[>] $($a.Id) (scope=$scope)..." -ForegroundColor Yellow

    # nektere aplikace nejde aktualizovat, dokud bezi (TeamViewer za vzdalene relace vraci kod 2).
    # Kdyz uz nainstalovane JSOU a prave bezi, upgrade preskocime - nova instalace probehne normalne.
    if ($a.ContainsKey('SkipIfRunning') -and (Get-Process -Name $a.SkipIfRunning -ErrorAction SilentlyContinue)) {
        $m = "$($a.Id): aplikace prave bezi (vzdalena relace?) - aktualizace preskocena, udelej ji mimo relaci"
        Write-Host "    [i] $m" -ForegroundColor DarkYellow
        $ok += "$($a.Id) (bezi - preskoceno)"; $script:Issues += $m
        continue
    }

    # winget install sam upgraduje (kdyz je novejsi) nebo neudela nic (kdyz je aktualni) - NEreinstaluje.
    $code = Invoke-WingetInstall -WgArgs $wgArgs
    switch ($code) {
        0           { Write-Host "    [i] nainstalovano / zaktualizovano." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978335189 { Write-Host "    [i] uz je aktualni - preskoceno." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978335135 { Write-Host "    [i] uz nainstalovano - preskoceno." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978334963 { Write-Host "    [i] uz nainstalovano - preskoceno." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978335153 { Write-Host "    [i] uz je aktualni - preskoceno." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978335217 { $m = "$($a.Id): zdroj wingetu je poskozeny i po 'source reset' - spust rucne 'winget source reset --force' a skript znovu"
                      Write-Warning "    $m"; $failed += "$($a.Id) (zdroj)"; $script:Issues += $m }
        -1978335226 { $m = "$($a.Id): instalator skoncil chybou (ShellExecute failed) - aplikace nejspis bezi; zavri ji a nainstaluj rucne"
                      Write-Warning "    $m"; $failed += "$($a.Id) (instalator)"; $script:Issues += $m }
        -1978335215 { $m = "$($a.Id): kontrolni soucet instalatoru nesouhlasi s manifestem - zkus pozdeji (balicek se prave aktualizuje)"
                      Write-Warning "    $m"; $failed += "$($a.Id) (hash)"; $script:Issues += $m }
        -1978335216 { $m = "$($a.Id): zadny instalator nesedi na tento system (architektura/verze Windows)"
                      Write-Warning "    $m"; $failed += "$($a.Id) (nepodporovano)"; $script:Issues += $m }
        -1978334967 { Write-Host "    [i] nainstalovano, dokonci se po restartu." -ForegroundColor DarkGray; $ok += $a.Id }
        -1978334966 { $m = "$($a.Id): instalace vyzaduje restart - po restartu spust skript znovu"
                      Write-Warning "    $m"; $failed += "$($a.Id) (restart)"; $script:Issues += $m }
        default     { Write-Warning "    $($a.Id) skoncil s kodem $code (i po opakovani)"; $failed += "$($a.Id) (kod $code)" }
    }
}

# --- 5e) Aktualizace aplikaci z Microsoft Store (na pozadi, pokud je treba) ---
try {
    Write-Host "[*] Spoustim aktualizaci aplikaci z Microsoft Store..." -ForegroundColor Cyan
    Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop |
        Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop | Out-Null
    Write-Host "    [i] Store aktualizace spustena (probiha na pozadi)." -ForegroundColor DarkGray
} catch { Write-Warning "    Store aktualizace: $($_.Exception.Message)" }

# --- 5d) Firefox - lokalizovany build primo od Mozilly (jen kdyz jeste neni; sam se aktualizuje) ---
$ffInstalled = (Test-Path 'C:\Program Files\Mozilla Firefox\firefox.exe') -or (Test-Path 'C:\Program Files (x86)\Mozilla Firefox\firefox.exe')
if ($ffInstalled) {
    Write-Host "[>] Firefox uz je nainstalovan - preskoceno (aktualizuje se sam)." -ForegroundColor DarkGray
    $ok += 'Firefox (uz nainstalovan)'
} else {
    try {
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
}

# --- 6) Microsoft 365 Apps for business (ODT z webu pres winget, jazyk dle Windows = $offLang) ---
$odtDir = Join-Path $env:ProgramFiles 'OfficeDeploymentTool'
try {
    Write-Host "[*] Microsoft 365 Apps for business (ODT)..." -ForegroundColor Cyan
    if ($script:officeIsOurs) { Write-Host "    [i] M365 uz je nainstalovan -> jen kontrola aktualizaci (bez reinstalace)." -ForegroundColor DarkGray }
    # configuration.xml s JEDNIM jazykem dle Windows ($offLang z detekce, napr. ro-ro)
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
  <Logging Level="Standard" Path="C:\ProgramData\WPBranding\OfficeLogs" />
  <RemoveMSI />
</Configuration>
"@
    Set-Content -Path "$work\office.xml" -Value $offXml -Encoding UTF8
    Write-Host "    [i] Office jazyk: $offLang (jediny)" -ForegroundColor DarkGray

    # winget stahne nejnovejsi ODT a rozbali setup.exe do %ProgramFiles%\OfficeDeploymentTool
    $null = Invoke-WingetInstall -WgArgs @('install','--id','Microsoft.OfficeDeploymentTool','-e','--silent','--source','winget','--accept-package-agreements','--accept-source-agreements')
    $setup = Join-Path $odtDir 'setup.exe'
    if (-not (Test-Path $setup)) {
        $setup = Get-ChildItem $env:ProgramFiles -Recurse -Filter 'setup.exe' -ErrorAction SilentlyContinue |
                 Where-Object { $_.DirectoryName -match 'OfficeDeploymentTool' } |
                 Select-Object -First 1 -ExpandProperty FullName
    }
    if ($setup -and (Test-Path $setup)) {
        Write-Host "    ODT: $setup" -ForegroundColor DarkGray
        $officeOk = $false; $odtExit = $null

        # C2R instalace SELZE (1603), pokud system ceka na restart - typicky po odebrani OEM Office
        # nebo po prejmenovani pocitace. V tom pripade to nezkousime a rovnou odlozime za restart.
        $rebootKind = Get-PendingRebootKind
        $pending = ($rebootKind -eq 'hard') -or $script:officeRemoved
        if ($pending) {
            Write-Host "    [~] System ceka na restart (aktualizace / odebrany OEM Office / prejmenovani) - instalace by skoncila chybou 1603." -ForegroundColor DarkYellow
        } else {
            if ($rebootKind -eq 'soft') { Write-Host "    [i] Po instalacich zbyla prejmenovani souboru - zkousim Office presto nainstalovat." -ForegroundColor DarkGray }
            $proc = Start-Process -FilePath $setup -ArgumentList "/configure `"$work\office.xml`"" -Wait -NoNewWindow -PassThru
            $odtExit = $proc.ExitCode
            for ($i = 0; $i -lt 18; $i++) {   # pockej az ~3 min, nez se instalace projevi v registru
                $c = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
                if ($c -and $c.PSObject.Properties['ProductReleaseIds'] -and $c.ProductReleaseIds -match 'O365BusinessRetail') { $officeOk = $true; break }
                Start-Sleep -Seconds 10
            }
        }

        if ($officeOk) {
            Write-Host "    [i] M365 Apps nainstalovany (overeno v registru). Aktivace = rucne pri prihlaseni." -ForegroundColor DarkGray
            $ok += 'Microsoft365Apps'
        } else {
            # misto marneho opakovani ve stejnych podminkach naplanujeme instalaci PO RESTARTU (SYSTEM, pri startu)
            if (Register-OfficePostRestart -SetupExe $setup -ConfigXml "$work\office.xml") {
                $why = if ($pending) { 'ceka se na restart' } else { "ODT kod $odtExit" }
                $m = "M365 se nainstaluje automaticky PO RESTARTU ($why) - uloha 'WP-Office-Install', prubeh: C:\ProgramData\WPBranding\Office\post-restart.log"
                Write-Host "    [i] $m" -ForegroundColor DarkYellow
                $ok += 'Microsoft365Apps (po restartu)'
                $script:Issues += $m
            } else {
                $m = "M365 se nenainstaloval (ODT kod $odtExit) a nepodarilo se naplanovat instalaci po restartu - spust skript znovu po restartu"
                Write-Warning "    $m"; $failed += 'Microsoft365Apps'; $script:Issues += $m
            }
        }
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
  if (Get-Printer -Name 'TOSHIBA-recepce' -ErrorAction SilentlyContinue) {
    Write-Host "[*] Tiskarna TOSHIBA-recepce uz existuje - preskoceno." -ForegroundColor DarkGray
    $ok += 'TOSHIBA-recepce (uz existuje)'
  } else {
    Write-Host "[*] Instalace tiskarny TOSHIBA-recepce..." -ForegroundColor Cyan
    try {
        # ovladac (velky) z $DriverUrl (GitHub release asset; nasleduje presmerovani). Pri migraci zmen $DriverUrl na Storage.
        if (-not (Get-UrlQuiet -Url $DriverUrl -OutFile "$work\ToshibaDRV.zip")) {
            $m = "Tiskarna: ovladac se nepodarilo stahnout - zkontroluj `$DriverUrl ($DriverUrl)"
            Write-Host "    [i] $m" -ForegroundColor DarkGray; $script:Issues += $m
        } else {
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
        }
    } catch {
        Write-Warning "    Tiskarna preskocena: $($_.Exception.Message)"
        $failed += "Tiskarna ($($_.Exception.Message))"
    }
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
    # PUA i pres policy klic - Set-MpPreference blokuje Tamper Protection, policy klic ne
    & reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v PUAProtection /t REG_DWORD /d 1 /f *>$null
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
        if ($adminGrp) { Add-LocalGroupMember -Group $adminGrp -Member $AdminUser -ErrorAction SilentlyContinue }
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

    # Sekundarni en-US klavesnice pryc (preset ji drive pridaval). Pojistka: na anglickych Windows nemazat.
    if ($RemoveENKeyboard) {
        try {
            $langs = Get-WinUserLanguageList
            if (($langs.Count -gt 1) -and ($langs[0].LanguageTag -notlike 'en*')) {
                $keep = $langs | Where-Object { $_.LanguageTag -ne 'en-US' }
                if ($keep) { Set-WinUserLanguageList $keep -Force; Write-Host "    [i] Sekundarni en-US klavesnice odebrana." -ForegroundColor DarkGray }
            } else {
                Write-Host "    [i] en-US klavesnice: nic k odebrani (nebo je jazykem systemu)." -ForegroundColor DarkGray
            }
        } catch { Write-Warning "    en-US klavesnice: $($_.Exception.Message)" }
    }
} catch { $m = "Indexace: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }

# --- 8d) Personalizace: hlavni panel, Start, plocha (aktualni + novi uzivatele) ---
# HKCU se tyka jen aktualniho uctu; aby nastaveni dostali i nove zalozeni uzivatele,
# zapisujeme zaroven do Default hive (C:\Users\Default\NTUSER.DAT).
Write-Host "[*] Personalizace (taskbar / Start / plocha)..." -ForegroundColor Cyan
$eapPers = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'   # chyba jednoho reg.exe nesmi shodit cely blok
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
        & reg add "$r\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f *>$null  # Hledat = Skryt
        & reg add $adv /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f *>$null   # totez i ve starsim umisteni
        & reg add $adv /v ShowTaskViewButton   /t REG_DWORD /d 0 /f *>$null   # Zobrazeni ukolu = Vypnuto
        & reg add $adv /v TaskbarDa            /t REG_DWORD /d 0 /f *>$null   # Widgety = Vypnuto
        & reg add $adv /v IsEnabled            /t REG_DWORD /d 0 /f *>$null   # Pokracovat (Resume) = Vypnuto
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
    # Widgety vypnout i strojovou politikou (Dsh je zapisovatelne adminem; PolicyManager\default NE - je chraneny)
    & reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f *>$null
    Write-Host "    [i] Start vlevo, Hledat skryto, Task View/Widgety/Pokracovat vypnuto, pripony viditelne, ikony na plose." -ForegroundColor DarkGray
} catch { Write-Warning "    Personalizace registru: $($_.Exception.Message)" }
finally { $ErrorActionPreference = $eapPers }

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
    $ol = Find-Lnk @('Outlook (classic).lnk','Microsoft Outlook.lnk','Outlook.lnk')   # classic ma prednost pred 'novym' Outlookem

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
    $enc = New-Object System.Text.UTF8Encoding($false)   # bez BOM (Win11 je vybiravy)
    $shellDir = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell'
    if (-not (Test-Path $shellDir)) { New-Item -ItemType Directory -Path $shellDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $shellDir 'LayoutModification.xml'), $xml, $enc)   # starsi buildy / novi uzivatele
    # Win11 24H2/25H2: Default-profile XML uz na taskbar nefunguje -> policy pres LayoutXMLPath
    $tbDir = 'C:\ProgramData\WPBranding'
    if (-not (Test-Path $tbDir)) { New-Item -ItemType Directory -Path $tbDir -Force | Out-Null }
    $tbXml = Join-Path $tbDir 'TaskbarLayout.xml'
    [System.IO.File]::WriteAllText($tbXml, $xml, $enc)
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v LayoutXMLPath /t REG_SZ /d $tbXml /f *>$null
    Write-Host "    [i] Taskbar pripnuti (Chrome, Firefox, Pruzkumnik, Outlook, Teams, Vystrizky) - policy LayoutXMLPath, projevi se po restartu." -ForegroundColor DarkGray
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
        '• Pokud se Office instaloval až po restartu: ověřit Word/Excel/Outlook (log C:\ProgramData\WPBranding\Office\post-restart.log)'
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
    # hledame ve Start menu pro vsechny uzivatele i v tom uzivatelskem (nektere instalatory davaji zastupce jen tam)
    $startRoots = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs") | Where-Object { Test-Path $_ }

    # kam zastupce kopirovat: Default (novi uzivatele) + plocha aktualniho uctu + plochy uz existujicich uzivatelu
    $deskTargets = @($defDesk, $adminDesktop)
    $deskTargets += (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' } |
                     ForEach-Object { Join-Path $_.FullName 'Desktop' })
    $deskTargets = $deskTargets | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($entry in $UserDesktopShortcuts) {
        $patterns = $entry -split '\|'   # alternativni nazvy oddelene svislitkem
        $name = $patterns -join ' / '    # do hlasky, kdyby se nic nenaslo
        $lnk = $null
        foreach ($pat in $patterns) {
            $lnk = Get-ChildItem -Path $startRoots -Recurse -Filter $pat -ErrorAction SilentlyContinue |
                   Sort-Object @{ Expression = { if ($_.Name -like '*classic*') { 0 } else { 1 } } }, Name | Select-Object -First 1
            if ($lnk) { break }        # prvni nalezena alternativa vyhrava
        }
        if ($lnk) {
            if (-not (Test-Path $defDesk)) { New-Item -ItemType Directory -Path $defDesk -Force | Out-Null }
            Copy-Item $lnk.FullName -Destination $defDesk -Force -ErrorAction SilentlyContinue        # novi uzivatele
            foreach ($d in $deskTargets) { Copy-Item $lnk.FullName -Destination $d -Force -ErrorAction SilentlyContinue }
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

# --- 8g) Tapeta (menitelna) + zamykaci obrazovka ---
Write-Host "[*] Tapeta a zamykaci obrazovka..." -ForegroundColor Cyan
$eapWall = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
try {
    $brandDir = 'C:\ProgramData\WPBranding'
    if (-not (Test-Path $brandDir)) { New-Item -ItemType Directory -Path $brandDir -Force | Out-Null }

    # obrazky drzime v $brandDir (i vychozi Win11) pro stabilni cestu mimo C:\Windows
    $wall = "$brandDir\wallpaper.jpg"
    if (-not (Get-RepoFileQuiet -Path 'config/branding/wallpaper.jpg'  -OutFile $wall)) { Copy-Item $WallpaperFallback  $wall -Force }
    $lock = "$brandDir\lockscreen.jpg"
    if (-not (Get-RepoFileQuiet -Path 'config/branding/lockscreen.jpg' -OutFile $lock)) { Copy-Item $LockScreenFallback $lock -Force }

    $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    # TAPETU NIKDY nezamykame (PersonalizationCSP by ji uzamkl = "spravuje organizace") -> odstranit pripadny STARY zamek tapety,
    # takze opetovne spusteni odemkne i uz postizene stroje.
    if (Test-Path $csp) { foreach ($v in 'DesktopImagePath','DesktopImageUrl','DesktopImageStatus') { Remove-ItemProperty -Path $csp -Name $v -ErrorAction SilentlyContinue } }

    if ($SetWallpaper -and (Test-Path $wall)) {
        # nastavit jako VYCHOZI tapetu, ale MENITELNOU: HKCU (aktualni uzivatel) + Default hive (novi uzivatele)
        & reg add "HKCU\Control Panel\Desktop" /v Wallpaper      /t REG_SZ /d "$wall" /f *>$null
        & reg add "HKCU\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d 10      /f *>$null   # 10 = Vyplnit
        & reg add "HKCU\Control Panel\Desktop" /v TileWallpaper  /t REG_SZ /d 0       /f *>$null
        $loaded = $false
        & reg load "HKU\WPDEF" "C:\Users\Default\NTUSER.DAT" *>$null; if ($LASTEXITCODE -eq 0) { $loaded = $true }
        if ($loaded) {
            & reg add "HKU\WPDEF\Control Panel\Desktop" /v Wallpaper      /t REG_SZ /d "$wall" /f *>$null
            & reg add "HKU\WPDEF\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d 10      /f *>$null
            & reg add "HKU\WPDEF\Control Panel\Desktop" /v TileWallpaper  /t REG_SZ /d 0       /f *>$null
            [gc]::Collect(); Start-Sleep -Milliseconds 300
            & reg unload "HKU\WPDEF" *>$null
        }
        rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True   # aplikovat hned pro aktualniho uzivatele
        Write-Host "    [i] Tapeta nastavena (lze normalne zmenit): $wall" -ForegroundColor DarkGray
    }

    if ($SetLockScreen -and (Test-Path $lock)) {
        # POZOR: na Win11 lze zamykaci obrazovku strojove nastavit jen pres PersonalizationCSP/policy, coz ji UZAMKNE ("spravuje organizace").
        if (-not (Test-Path $csp)) { New-Item -Path $csp -Force | Out-Null }
        Set-ItemProperty -Path $csp -Name 'LockScreenImagePath'   -Value $lock -Type String
        Set-ItemProperty -Path $csp -Name 'LockScreenImageUrl'    -Value $lock -Type String
        Set-ItemProperty -Path $csp -Name 'LockScreenImageStatus' -Value 1 -Type DWord
        $sysPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        if (-not (Test-Path $sysPol)) { New-Item -Path $sysPol -Force | Out-Null }
        Set-ItemProperty -Path $sysPol -Name 'DisableLogonBackgroundImage' -Value 0 -Type DWord
        Write-Host "    [i] Zamykaci obrazovka nastavena (UZAMKNE ji - 'spravuje organizace'): $lock" -ForegroundColor DarkYellow
    } else {
        # zamykaci obrazovku nezamykat -> odstranit pripadny STARY CSP zamek zamykaci obrazovky
        if (Test-Path $csp) { foreach ($v in 'LockScreenImagePath','LockScreenImageUrl','LockScreenImageStatus') { Remove-ItemProperty -Path $csp -Name $v -ErrorAction SilentlyContinue } }
    }
} catch { $m = "Tapeta/zamykaci obrazovka: $($_.Exception.Message)"; Write-Warning "    $m"; $script:Issues += $m }
finally { $ErrorActionPreference = $eapWall }

# --- 8h) Vychozi aplikace (Chrome=web, VLC=avi/mp3/mp4, Adobe=pdf, Outlook=mailto, 7-Zip=archivy) ---
if ($SetDefaultApps) {
    function Get-CapProgId { param($CapRel,$Type,$Name)
        foreach ($root in 'HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node') {
            $k = Join-Path (Join-Path $root $CapRel) $Type
            if (Test-Path $k) {
                $it = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
                if ($it -and $it.PSObject.Properties[$Name]) { return $it.$Name }
            }
        }
        return $null
    }
    # ProgID bereme primo z registru (co appky zaregistrovaly) - nezavisle na verzi/jazyku
    $want = @()
    $cCap = 'Clients\StartMenuInternet\Google Chrome\Capabilities'
    foreach ($u in 'http','https') { $pg = Get-CapProgId $cCap 'URLAssociations'  $u; if ($pg) { $want += @{ Id=$u; ProgId=$pg; App='Google Chrome' } } }
    foreach ($e in '.htm','.html')  { $pg = Get-CapProgId $cCap 'FileAssociations' $e; if ($pg) { $want += @{ Id=$e; ProgId=$pg; App='Google Chrome' } } }
    $vCap = 'VideoLAN\VLC\Capabilities'
    foreach ($e in '.avi','.mp3','.mp4') { $pg = Get-CapProgId $vCap 'FileAssociations' $e; if ($pg) { $want += @{ Id=$e; ProgId=$pg; App='VLC media player' } } }
    $ol = Get-CapProgId 'Clients\Mail\Microsoft Outlook\Capabilities' 'URLAssociations' 'mailto'
    if ($ol) { $want += @{ Id='mailto'; ProgId=$ol; App='Outlook' } }
    $pdf = $null
    $pdfKey = 'HKLM:\SOFTWARE\Classes\.pdf\OpenWithProgids'
    if (Test-Path $pdfKey) { $pdf = (Get-Item $pdfKey).Property | Where-Object { $_ -like '*Acro*' -or $_ -like '*Adobe*' } | Select-Object -First 1 }
    if (-not $pdf) { $pdf = 'AcroExch.Document.DC' }
    $want += @{ Id='.pdf'; ProgId=$pdf; App='Adobe Acrobat Reader' }
    # 7-Zip: archivni pripony (jen ty, kde 7-Zip realne zaregistroval ProgID -> zadne rozbite asociace)
    function Get-ArchProgId { param($Ext,$Match)
        $k = "HKLM:\SOFTWARE\Classes\$Ext\OpenWithProgids"
        if (Test-Path $k) { $hit = (Get-Item $k).Property | Where-Object { $_ -like "$Match*" } | Select-Object -First 1; if ($hit) { return $hit } }
        return $null
    }
    foreach ($e in '.7z','.zip','.rar','.tar','.gz','.bz2','.xz','.cab','.iso','.wim') {
        $pg = Get-ArchProgId $e '7-Zip'
        if (-not $pg) { $cand = '7-Zip.' + $e.TrimStart('.'); if (Test-Path "HKLM:\SOFTWARE\Classes\$cand") { $pg = $cand } }
        if ($pg) { $want += @{ Id=$e; ProgId=$pg; App='7-Zip' } }
    }

    # 1) NOVI uzivatele: appassoc.xml + DISM (repo verze ma prednost, pokud existuje)
    $xmlPath = "$work\appassoc.xml"
    if (-not (Get-RepoFileQuiet -Path 'config/appassoc.xml' -OutFile $xmlPath)) {
        $sb = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n<DefaultAssociations>`r`n"
        foreach ($w in $want) { $sb += "  <Association Identifier=`"$($w.Id)`" ProgId=`"$($w.ProgId)`" ApplicationName=`"$($w.App)`" />`r`n" }
        $sb += "</DefaultAssociations>`r`n"
        [System.IO.File]::WriteAllText($xmlPath, $sb, (New-Object System.Text.UTF8Encoding($false)))
    }
    & dism.exe /Online /Import-DefaultAppAssociations:"$xmlPath" *>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "    [i] Vychozi aplikace pro NOVE uzivatele nasazeny (DISM)." -ForegroundColor DarkGray }
    else { $m = "Vychozi aplikace (DISM) kod $LASTEXITCODE"; Write-Warning "    $m"; $script:Issues += $m }

    # 2) AKTUALNI uzivatel: na workgroup Win11 nejde per-user defaults spolehlive nastavit skriptem
    #    (chrani je hash + kernel driver UCPD.sys; DISM plati jen pro NOVE uzivatele; policy DefaultAssociationsConfiguration jen pro domenove stroje).
    #    -> aktualni ucet si vychozi aplikace nastavi rucne (Nastaveni > Aplikace > Vychozi aplikace).
    Write-Host "    [i] Pozn.: vychozi aplikace plati pro NOVE uzivatele; aktualnimu uctu je nutne nastavit rucne (Win11 je chrani hashem)." -ForegroundColor DarkGray
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
