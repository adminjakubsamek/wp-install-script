# WELL PACK - automatický instalační skript Windows

## Spuštění

Na čisté instalaci Windows 11 (po prvním přihlášení) → **PowerShell jako správce** → vlož jeden řádek:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

- Skript vyžaduje **práva správce** (jinak se ukončí).
- Na konci se počítač **restartuje za 30 s** — zrušíš `shutdown /a`.
- **Náhled bez instalace**: nahoře ve skriptu přepni `$PreviewOnly = $true` → jen vypíše plán a skončí.
- Skript na začátku **vypne QuickEdit** konzole, aby kliknutí do okna nepozastavilo běh.

---

## Konfigurace (přepínače nahoře ve skriptu)

- `$Owner` / `$Repo` / `$Ref` — odkud se tahají soubory (GitHub).
- `$Restart` — restart na konci (výchozí `$true`).
- `$PreviewOnly` — jen vypsat plán, nic neinstalovat (`$false`).
- `$InstallPrinter` — instalovat tiskárnu TOSHIBA-recepce (`$true`).
- `$RenameToSerial` — přejmenovat PC dle sériového čísla (`$true`).
- `$RenameOnlyDefaultNames` — přejmenovat **jen počítače s továrním názvem** (`$true`); ručně pojmenovaná PC zůstanou beze změny.
- `$DefaultNamePatterns` — co se považuje za tovární název (`DESKTOP-XXXXXXX`, `LAPTOP-XXXXXXX`, `WIN-…`, `MININT-…`, `PC`, `USER-PC` apod.).
- `$RemoveENKeyboard` — odebrat sekundární en-US klávesnici (`$true`); na anglických Windows se neprovede.
- `$NamePrefix` — volitelná předpona názvu PC (např. `'WP-'`); prázdné = jen sériové číslo.
- `$RemovePreinstalledOffice` — nejdřív odinstalovat OEM Office balast (`$true`).
- `$RemoveThirdPartyAV` — nejdřív odinstalovat cizí antiviry (`$true`).
- `$UserDesktopShortcuts` — zástupci na plochu uživatele (názvy `.lnk`, lze i `*`).
- `$ClearPublicDesktop` — smazat zástupce z veřejné plochy (`$true`).
- `$SetWallpaper` — nastavit výchozí tapetu (**měnitelnou**) aktuálnímu i novým uživatelům (`$true`).
- `$SetLockScreen` — `$true` nastaví zamykací obrazovku, ale **uzamkne ji** (Win11 jinak neumí) → výchozí `$false`.
- `$WallpaperFallback` / `$LockScreenFallback` — výchozí obrázek, když není v repu.
- `$SetDefaultApps` — nastavit výchozí aplikace (Chrome, VLC, Adobe, Outlook, 7-Zip) **novým uživatelům** přes DISM.
- `$DriverUrl` — URL ovladače tiskárny (`ToshibaDRV.zip`); výchozí je GitHub Release asset, při migraci sem dej Storage URL.
- `$AdminUser` — účet, kterému se nastaví admin práva + heslo bez expirace (samotné heslo ručně).

---

## Průběh instalace (v pořadí)

1. **Kontrola práv správce** + vypnutí QuickEditu + start logu na plochu admina.
2. **Detekce jazyka Windows** → `cs` / `en` / `de` (fallback `cs`); řídí jazyk aplikací.
3. **Přejmenování počítače** podle sériového čísla z BIOSu — **jen má-li PC tovární název** (projeví se po restartu).
4. **Ověření wingetu** (najde i na čerstvém stroji bez PATH).
5. **Předinstalační úklid (jako PRVNÍ akce):**
   - odinstaluje **všechny předinstalované Office Click-to-Run** produkty a jazykové mutace (ODT *Remove All*);
   - odebere **Store OneNote / Office stuby** (i provisioned, aby se nevracely novým uživatelům);
   - **best-effort odebere cizí antiviry** (McAfee, Norton, Avast, AVG, Avira, Kaspersky, Bitdefender, Webroot, Malwarebytes, Panda, Sophos, TotalAV). **Defender a ESET zůstávají.**
6. **Instalace aplikací přes winget** (nejnovější verze) — viz seznam níže.
7. **Aktualizace aplikací z Microsoft Store** (na pozadí; přes MDM `UpdateScanMethod`).
8. **Firefox** — lokalizovaný build přímo od Mozilly (dle jazyka Windows), tichá instalace.
9. **Microsoft 365 Apps for business** — přes ODT, **jeden jazyk** dle Windows, **bez aktivace**. Čeká-li systém na restart, instalace se automaticky **odloží za restart** (naplánovaná úloha).
10. **Win11 tweaky** — vyčištěný preset Disassembler0 (`tweaks/`).
11. **Konfigurace aplikací** — pdfsam, vlc, vypnutí Adobe upsellu.
12. **Tiskárna TOSHIBA-recepce** (volitelné; ovladač z GitHub Release).
13. **Vlastní příkazy** — BitLocker, RDP, NCD, odblokování feature updates, časové pásmo + sync,
    **napájení = nejvyšší výkon** (uspávání ze sítě = Nikdy), **System Restore limit 5 %**, **popisek disku C: = OS**,
    **Defender SmartScreen + blokování PUA**, **účet admin** (admin práva + heslo bez expirace; heslo ručně),
    **indexace celého disku C:** (Enhanced) + běžící Windows Search.
14. **Personalizace** — hlavní panel, Start, plocha (i pro nové uživatele).
15. **Zástupci na plochu uživatele** (smazatelné) + úklid veřejné plochy.
16. **Tapeta** — výchozí, ale **měnitelná** (HKCU + Default hive); zamykací obrazovka volitelně (uzamkne ji).
16b. **Výchozí aplikace** — ProgID se čtou z registru a nasadí se **novým uživatelům přes DISM**. Chrome=http/https/.htm/.html, Adobe=.pdf, Outlook=mailto, VLC=.avi/.mp3/.mp4, 7-Zip=archivy. Aktuální účet si je nastaví ručně (viz níže).
17. **Poznámka na plochu admina** (úkoly + co se nepovedlo + cesta k logu).
18. **Úklid dočasných souborů**, výpis shrnutí, **restart**.

---

## Instalované aplikace

Přes **winget** (vždy nejnovější verze):

- **Google Chrome** — jazyk dle OS.
- **7-Zip** — multijazyčný.
- **VLC** — multijazyčný (+ `vlc.reg`).
- **Adobe Acrobat Reader (64-bit)** — MUI dle OS, upsell na placený Acrobat vypnut.
- **PDFsam Basic** (+ `pdfsam.reg`, `pdfsam.l4j.ini`).
- **doPDF 11** — jazyk přes `--custom -install_language=<cs|en|de>`.
- **Oracle Java 8 (JRE)** — pro komerční/úřední použití formálně vyžaduje licenci Oracle.
- **OpenVPN Community** — profily se přidávají ručně.
- **TeamViewer** (plný klient) — spouští se s Windows (služba); statické heslo nastav ručně.
- **Microsoft Teams** (nový klient work/school).
- **Azure VPN Client** (jen Windows 11+).

Mimo winget:

- **Firefox** — přímý lokalizovaný build od Mozilly.
- **Microsoft 365 Apps for business** — ODT, profil O365BusinessRetail, kanál Current, 64-bit.

Plus **aktualizace aplikací z Microsoft Store**.

---

## Jazyk aplikací (řídí se jazykem Windows)

Jazyk se **odvozuje přímo z jazyka Windows** (display language). Pro rumunský systém (`ro-RO`)
se nainstaluje vše v rumunštině, pro český (`cs-CZ`) v češtině atd. Žádný napevno nastavený fallback na češtinu.

| Aplikace | Jak se řídí jazyk |
|---|---|
| 7-Zip, VLC, Chrome, Adobe Reader | automaticky dle jazyka OS |
| Firefox | lokalizovaný build od Mozilly (`$ffLang` = dvoupísmenný kód OS, `en`→`en-US`) |
| doPDF | `-install_language` = kód OS, u nepodporovaného jazyka fallback `en` |
| Microsoft 365 | jeden jazyk v ODT (`$offLang` = plný kód OS, např. `ro-ro`, `cs-cz`) |
| Java, OpenVPN, TeamViewer, Azure VPN | bez jazykového UI / nerelevantní |

---

## Změny v registru

### Pro celý počítač (HKLM)

- **Adobe Reader – vypnutí upsellu** (`bAcroSuppressUpsell=1`, `bToggleFTE=1`):
  - `HKLM\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown`
  - `HKLM\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown`
- **RDP** (`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client`):
  - `fClientDisableUDP = 1` — vypne UDP (řeší zasekávající se obraz).
  - `RedirectionWarningDialogVersion = 1` — potlačí varovný dialog přesměrování.
- **Auto-přidávání síťových tiskáren – vypnuto** (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private`):
  - `AutoSetup = 0`.
- **Telemetrie (kvůli feature updatům)** — `AllowTelemetry = 1` (Required) v:
  - `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection`
  - `HKLM\SOFTWARE\Microsoft\Windows\DataCollection`
- **Služby polohy** (pro automatické časové pásmo):
  - `HKLM\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration` → `Status = 1`
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location` → `Value = Allow`
- **Automatické časové pásmo** (`HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate`):
  - `Start = 3` (zapnuto, on-demand).
- **Tapeta (měnitelná)** — `HKCU\Control Panel\Desktop\Wallpaper` (+ `WallpaperStyle=10`) a totéž v Default hive pro nové uživatele. **Žádný PersonalizationCSP** (ten by tapetu zamkl). Skript navíc odstraní případný starý CSP zámek tapety, takže opětovné spuštění odemkne i dřív postižené stroje.
- **Zamykací obrazovka (volitelně, `$SetLockScreen=$true`)** — `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP`:
  - `DesktopImagePath` / `DesktopImageUrl` + `DesktopImageStatus = 1`.
  - `LockScreenImagePath` / `LockScreenImageUrl` + `LockScreenImageStatus = 1`.
- **Obrázek pozadí na přihlašovací obrazovce** (`HKLM\SOFTWARE\Policies\Microsoft\Windows\System`):
  - `DisableLogonBackgroundImage = 0` (zobrazovat).
- **Defender SmartScreen / PUA** (Řízení aplikací a prohlížečů):
  - `Set-MpPreference -PUAProtection Enabled` + policy `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\PUAProtection = 1`
    (policy klíč funguje i při zapnuté **Tamper Protection**, kterou `Set-MpPreference` jinak blokuje).
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer` → `SmartScreenEnabled = Warn`.
  - `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` → `EnableSmartScreen = 1`, `ShellSmartScreenLevel = Warn`.
- **Indexace celého disku (Enhanced)** (`HKLM\SOFTWARE\Microsoft\Windows Search`):
  - `EnableFindMyFiles = 1` (indexovat celý PC; vyžaduje restart služby Windows Search).

### Pro uživatele (HKCU + Default profil `C:\Users\Default\NTUSER.DAT`)

Zapisuje se do aktuálního účtu **i** do Default profilu, takže nastavení dostanou i nově založení uživatelé.

- `…\Explorer\Advanced`:
  - `TaskbarAl = 0` — Start/hlavní panel zarovnán doleva.
  - `TaskbarGlomLevel = 0` a `MMTaskbarGlomLevel = 0` — vždy slučovat ikony oken (i na 2. monitoru).
  - `HideFileExt = 0` — zobrazit přípony souborů.
- `…\Search` → `SearchboxTaskbarMode = 0` — **Hledat = Skrýt**.
  - `…\Advanced` → `ShowTaskViewButton = 0` (Zobrazení úkolů vyp.), `TaskbarDa = 0` (Widgety vyp.).
  - `HKLM\SOFTWARE\Policies\Microsoft\Dsh` → `AllowNewsAndInterests = 0` (Widgety vyp. strojově).
  - `HKLM\…\PolicyManager\default\Connectivity\DisableCrossDeviceResume = 1` (Pokračovat vyp. strojově).
- `…\Explorer\HideDesktopIcons\NewStartPanel` (ikony na ploše, `0` = zobrazit):
  - `{20D04FE0-3AEA-1069-A2D8-08002B30309D}` — Tento počítač.
  - `{59031a47-3f72-44a7-89c5-5595fe6b30ee}` — Složka uživatele.
  - `{645FF040-5081-101B-9F08-00AA002F954E}` — Koš.

> Pozn.: Win11 tweaky (preset Disassembler0) navíc samy zapisují další hodnoty do registru — viz `tweaks/install.preset`.

---

## Služby a systémové změny

- **BDESVC** (BitLocker) → zastavena + `Disabled`; `manage-bde -off C:` spustí dešifrování (interní výjimka).
- **DiagTrack** (Connected User Experiences and Telemetry) → `Automatic` + nastartována (nutné pro feature updaty).
- **W32Time** → `Automatic` + nastartována; `w32tm /resync /force` (zdroj `time.windows.com`).
- **tzautoupdate** → zapnuto (Start=3); časové pásmo nastaveno na **Central European Standard Time**.
- **Naplánovaná úloha** „Microsoft Compatibility Appraiser" → povolena a spuštěna (data pro kontrolu kompatibility upgradu).
- **Název počítače** → změněn na sériové číslo z BIOSu (max 15 znaků; nepoužitelná čísla se přeskočí).
- **Napájení** → aktivní plán **High performance** + power mode **Best performance** (na síti i baterii); **uspávání při napájení ze sítě = Nikdy**.
- **System Restore** → limit stínové kopie **5 % disku C:** (`vssadmin resize shadowstorage`).
- **Popisek disku C:** → nastaven na **OS**.
- **Účet `admin`** → přidán do Administrators, **heslo bez expirace**, účet povolen. Samotné **heslo se nastavuje ručně** (je v poznámce). Když účet neexistuje, zapíše se do poznámky.
- **Windows Search (WSearch)** → Automatic + restart; **Enhanced indexace** (celý disk C:).

---

## Soubory, které skript vytváří nebo mění

- **Log běhu**: `…\Desktop\install_<datum>_<čas>.log` (na ploše admina; **žádný zápis do `C:\ProgramData`**).
- **Poznámka pro admina**: `…\Desktop\ADMIN - po instalaci.txt`.
- **Připnutí na hlavní panel**: `C:\ProgramData\WPBranding\TaskbarLayout.xml` (+ policy `LayoutXMLPath`); fallback i do Default profilu.
- **Zástupci na ploše uživatele**: kopie `.lnk` do `C:\Users\Default\Desktop`.
- **Veřejná plocha**: smazání `C:\Users\Public\Desktop\*.lnk` (když `$ClearPublicDesktop=$true`).
- **Tapeta/zamykací obrazovka**: obrázky uloženy do `C:\ProgramData\WPBranding`.
- **PDFsam**: `pdfsam.l4j.ini` → `C:\Program Files\PDFsam Basic`.
- **Tiskový ovladač**: rozbalen do `C:\Program Files\ToshibaDRV`.
- **Dočasná složka** `%TEMP%\provision-xxxxxxxx` — na konci smazána.

---

## Hlavní panel / Start / plocha

- **Start vlevo**, **Hledat skryto**, **Zobrazení úkolů / Widgety / Pokračovat vypnuto**, **sloučené ikony oken**, **viditelné přípony**.
- **Na ploše**: Tento počítač, Složka uživatele, Koš.
- **Připnutí na panel v pořadí**: Chrome → Firefox → Průzkumník → Outlook → Teams → Výstřižky (**Edge odepnut**).
- Připnutí na panel se nasazuje **policy metodou** (`HKLM\…\Explorer\LayoutXMLPath` → `C:\ProgramData\WPBranding\TaskbarLayout.xml`), protože na Win11 24H2/25H2 už metoda přes Default profil nefunguje. Projeví se **po restartu** (na buildu 26200.5722+ i u stávajících uživatelů).
- „Sloučené ikony oken" = `TaskbarGlomLevel=0`; pro opačné chování (nikdy neslučovat) dej `2`.

---

## Tapeta a zamykací obrazovka

- **Tapeta** se nastaví jako výchozí, ale **zůstane měnitelná** (přes `HKCU` + Default hive, ne PersonalizationCSP). Uživatel si ji může v Nastavení normálně změnit. Skript zároveň odstraní starý CSP zámek tapety (`DesktopImagePath/Url/Status`), takže odemkne i stroje, kde byla dřív zamčená.
- **Zamykací obrazovku** lze na Win11 strojově nastavit jen jejím **uzamčením** (PersonalizationCSP/policy → „některá nastavení spravuje vaše organizace"). Proto je ve výchozím stavu **vypnutá** (`$SetLockScreen=$false`); zapni ji jen když chceš firemní zamčenou zamykací obrazovku.
- Obrázky skript hledá v repu: `config/branding/wallpaper.jpg` a `config/branding/lockscreen.jpg`.
- Když v repu nejsou, použije **výchozí Win11 `img0.jpg`** (modrá „Bloom"). Obrázky se vždy zkopírují do `C:\ProgramData\WPBranding` a CSP ukazuje na tu kopii (stabilní cesta).
- Na přihlašovací obrazovce se zobrazuje obrázek zamykací obrazovky.

---

## Výchozí aplikace a asociace souborů (vč. 7-Zip)

Skript nastavuje tyto výchozí aplikace: **Chrome** pro http/https/.htm/.html, **Adobe** pro .pdf,
**Outlook** pro mailto, **VLC** pro .avi/.mp3/.mp4, **7-Zip** pro archivy (.7z/.zip/.rar/.tar/.gz/.bz2/.xz/.cab/.iso/.wim — jen ty, které 7-Zip reálně zaregistruje). **ProgID se čtou přímo z registru** (z `Capabilities`
nainstalovaných aplikací), takže nezávisí na verzi ani jazyku a **není potřeba nic exportovat**.

Nasazení probíhá dvěma cestami, protože Windows 11 chrání výchozí aplikace per-uživatel hashem:

- **Noví uživatelé** — vygeneruje se `appassoc.xml` a naimportuje přes `dism /online /import-defaultappassociations`.
  (Má-li repo `config/appassoc.xml`, použije se místo vygenerovaného — tvůj vlastní export má přednost.)
- **Aktuální uživatel** (účet, pod kterým skript běží) — na **workgroup** strojích **nejde nastavit skriptem**.
  Windows 11 chrání per-user asociace hashem, který od února 2024 hlídá i kernel driver **UCPD.sys** a odmítá
  zápis přes registr/reg.exe/PowerShell (ACCESS_DENIED). DISM platí jen pro nové uživatele a policy
  `DefaultAssociationsConfiguration` funguje jen na **doménových** strojích. Aktuální účet si tedy výchozí
  aplikace nastaví **ručně** (Nastavení → Aplikace → Výchozí aplikace). Volitelně lze použít nástroj
  **SetUserFTA** (UCPD-kompatibilní verze na https://setuserfta.com), ale skript ho nevyžaduje.

> Proč to dřív nefungovalo: DISM import platí **jen pro nové uživatele**, ne pro účet, pod kterým instaluješ.
> Když skript spouští přímo koncový uživatel (např. `catalin.barbu`), výchozí aplikace pro jeho účet nastav ručně.

---

## Předinstalační úklid (detail)

- **Office balast** — ODT s `<Remove All="TRUE"/>` smaže všechny Click-to-Run produkty a jazykové mutace najednou; pak se (krok 9) nainstaluje čistá jednojazyčná verze. **Pozor:** po tomto odebrání systém čeká na restart, takže se instalace M365 automaticky odloží za restart (viz `WP-Office-Install`).
- **Cizí antiviry** — best-effort přes tichý odinstalátor / `msiexec /x`. Tvrdošíjné (McAfee, Norton) můžou vyžadovat vendor nástroj (MCPR, Norton Remove & Reinstall). **ESET se nemaže.**

---

## Zdroj souborů / hosting (`$BaseUrl`)

Skript nestahuje z pevně zadaného GitHubu — vše jde přes proměnnou **`$BaseUrl`** (+ volitelný **`$Sas`**)
nahoře v `bootstrap.ps1`. Díky tomu je zdroj vyměnitelný bez zásahu do logiky.

| Hosting | `$BaseUrl` | Přihlášení |
|---|---|---|
| GitHub raw (testovací) | `https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main` | ne (veřejné) |
| Azure Storage **static website** (`$web`) | `https://<ucet>.z13.web.core.windows.net` | ne (veřejné by design) |
| Azure Blob s anonymním čtením | `https://<ucet>.blob.core.windows.net/<kontejner>` | ne (nutno zapnout public access) |
| Azure Blob privátní + SAS | `https://<ucet>.blob.core.windows.net/<kontejner>` + `$Sas='?sv=...&sig=...'` | ne (token v URL, expiruje) |

**Spuštění** = `irm "$BaseUrl/bootstrap.ps1$Sas" | iex` (jeden řádek, elevovaný PowerShell).

### Migrace GitHub → Azure DevOps
1. **Repo:** DevOps → *Repos → Import a repository* → vlož veřejnou GitHub URL (bez auth).
2. **`ToshibaDRV.zip`** (byl GitHub Release asset) se **nemigruje** — nahraj ho ručně do Storage (do `$web`).
3. **Storage:** vytvoř účet → zapni *Static website* → soubory publikuje pipeline `azure-pipelines.yml`
   (DevOps repo = privátní zdroj, Storage `$web` = veřejné doručování bez přihlašování).
4. V `bootstrap.ps1` přepni `$BaseUrl` na endpoint static website.

> **Proč ne přímo z DevOps:** REST API DevOps na stažení souboru vyžaduje PAT token — anonymní „raw" jako
> `raw.githubusercontent.com` DevOps nenabízí. Proto se pro doručování používá Storage.

---

## Struktura repa

```
wp-install-script/
├─ bootstrap.ps1          # hlavní skript
├─ README.md
├─ azure-pipelines.yml    # publikace do Azure Storage (DevOps -> $web)
├─ tisk-recepce.ps1       # instalace tiskárny (volá ho bootstrap)
├─ SetACL.exe             # práva tiskárny
├─ tweaks/
│  ├─ win10.ps1           # runner
│  ├─ win10.psm1          # modul tweaků
│  └─ install.preset      # vyčištěný preset
└─ config/
   ├─ pdfsam.reg
   ├─ pdfsam.l4j.ini
   ├─ vlc.reg
   ├─ appassoc.xml        # volitelné - vlastní export; jinak si skript vygeneruje sám
   └─ branding/           # volitelné
      ├─ wallpaper.jpg
      └─ lockscreen.jpg
```

- **GitHub Release** (tag např. `drivers`) s přílohou **`ToshibaDRV.zip`** — ovladač tiskárny (velký soubor mimo strom repa). Skript bere z `releases/latest/download/ToshibaDRV.zip`.
- ZIP musí mít v kořeni cestu `Driver\64bit\eSf6u.inf` (INF i název ovladače si skript najde sám).

---

## Log a náhled

- Log každého běhu: **na ploše admina** `install_<datum>_<čas>.log`.
- Poznámka `ADMIN - po instalaci.txt` obsahuje ruční úkoly **a výpis toho, co se ve skriptu nepovedlo**.
- Náhled bez instalace: `$PreviewOnly = $true`.

---

## Ruční kroky po instalaci (jsou i v poznámce na ploše)

- **ESET** – doinstalovat.
- **TeamViewer** – nastavit statické heslo (nelze nasadit jedním reg klíčem napříč PC).
- **Tiskárny**, **migrace dat**, **Chrome** (kontrola záložek a hesel).
- **OneDrive** – přihlášení.
- **Heslo počítače** + **ESET šifrování**.
- **Kontrola povolení Defenderu**.
- **Nastavit heslo k účtu admin (Windows)**.
- **Ověřit indexaci Outlooku** po nastavení e-mailového účtu (indexace mailboxu běží až po vytvoření profilu).
- **Microsoft 365** – aktivace přihlášením uživatele.
- **VPN profily** (OpenVPN / Azure VPN) – import ručně.

---

## Poznámky a upozornění

- **Heslo účtu admin** — skript nastaví jen admin práva a vypnutí expirace; **samotné heslo nastav ručně** (je v poznámce na ploše).
- **Indexace Outlooku** — celý disk se indexuje (Enhanced); samotné indexování pošty běží až po nastavení Outlook profilu uživatelem.
- **Přejmenování jen továrních názvů** — počítač se přejmenuje na sériové číslo **pouze** má-li ještě tovární název (`DESKTOP-…`, `LAPTOP-…`, `WIN-…`, `MININT-…`). Pojmenoval-li ho admin ručně, název zůstane. Vypíná se `$RenameOnlyDefaultNames = $false`.
- **Sekundární en-US klávesnice** — z presetu byl odebrán `AddENKeyboard`; skript navíc en-US aktivně **odebere** (`$RemoveENKeyboard`), ale nikdy na Windows, jejichž jazykem je angličtina.
- **winget „Přístup odepřen"** — cesta `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_…\winget.exe` je chráněná ACL a povýšenému účtu ji často **nedovolí spustit**. Skript proto kandidáty (PATH → alias `%LOCALAPPDATA%\Microsoft\WindowsApps` → cesta balíčku) **otestuje spuštěním** `--version` a vezme první, který skutečně běží. Když neběží žádný, pokusí se balíček *App Installer* pro daný účet **přeregistrovat** (`Add-AppxPackage -Register`) a zkusí to znovu.
- **Poškozený zdroj wingetu (`0x8A15000F`)** — index zdrojů bývá prázdný nebo rozbitý, typicky po přeregistraci *App Installeru*; winget pak u **každé** aplikace hlásí „chybí data zdroje". Skript to řeší sám: jednou za běh spustí `winget source reset --force` + `source update` a instalaci zopakuje. Po přeregistraci balíčku se index obnoví rovnou, ne až u první aplikace.
- **Argumenty wingetu se předávají jako pole** (`Invoke-Winget -WgArgs @(...)`). Předat je volně nejde — PowerShell by `-e` (`--exact`) považoval za svůj vlastní parametr a hlásil by nejednoznačnost s `-ErrorAction`/`-ErrorVariable`.
- **Selhání wingetu neshodí skript** — všechna volání jdou přes `Invoke-Winget`, které dočasně přepne `$ErrorActionPreference` na `Continue` a vrátí návratový kód. Dřív nativní chyba wingetu při globálním `Stop` ukončila **celý běh** (skript skončil hned u první aplikace).
- **M365 a čekající restart (chyba 1603)** — Click-to-Run instalace **vždy selže s 1603**, pokud systém čeká na restart. To nastane skoro pokaždé, protože skript předtím odebere OEM Office (*Remove All*) a přejmenuje počítač. Proto skript stav `PendingReboot` **detekuje předem**, marnou instalaci nezkouší a místo toho registruje naplánovanou úlohu **`WP-Office-Install`** (SYSTEM, při startu). Ta po restartu počká, až doběhne Windows Update, nainstaluje M365, doplní zástupce Wordu/Excelu/Outlooku na plochy a **sama se smaže**. Průběh: `C:\ProgramData\WPBranding\Office\post-restart.log`.
- **ODT logování** — `office.xml` má `<Logging>` do `C:\ProgramData\WPBranding\OfficeLogs`, takže případné selhání jde dohledat.
- **Ovladač tiskárny** — `ToshibaDRV.zip` se stahuje z `$DriverUrl` (výchozí = GitHub Release asset, `releases/latest/download/ToshibaDRV.zip`; sleduje přesměrování). Při migraci na Storage přepiš `$DriverUrl`. Nedostupný ovladač = tiskárna se přeskočí s hláškou, nespadne.
- **„Pokračovat"** se vypíná per-uživatel (`Advanced\IsEnabled = 0`), ne přes `PolicyManager\default` — ten je chráněný a zápis do něj hlásí „Přístup byl odepřen".
- **Zdroj `winget` napevno** — instalace používají `--source winget`, takže se **obchází zdroj `msstore`**.
  Na čerstvě nainstalovaném Windows (bez aktualizací) má App Installer starý certifikát pro `msstore`
  (`0x8a15005e: server certificate did not match`) a bez určení zdroje by winget odmítl instalovat. Tímto je to ošetřené.
- **Retry jen na 1618** — opakuje se pouze při „another installation in progress"; ostatní chyby končí hned
  (dřív retry zbytečně čekal 3×30 s i u trvalých chyb).
- **Chyba 1618 „another installation in progress"** — Windows dovolí jen jednu MSI instalaci naráz.
  Když během běhu instaluje něco na pozadí (Windows Update, aktualizace Store aplikací), MSI aplikace
  by jinak spadly. Instalační smyčka proto při neúspěchu **3× zopakuje pokus s pauzou 30 s**.
- **Doporučení na čerstvém stroji** — ideálně nechat proběhnout prvotní Windows Update (nebo aspoň aktualizaci App Installeru), jinak mohou instalace narážet na běžící aktualizace (1618) nebo starý `msstore` certifikát. Skript je idempotentní, takže **druhý běh po restartu** bezpečně doinstaluje, co poprvé selhalo kvůli běžícím aktualizacím.
- **Opakované spuštění (idempotence)** — skript lze pustit znovu bez reinstalace:
  aplikace přes winget se jen aktualizují (nebo přeskočí, když jsou aktuální), **M365 se neodstraňuje**
  (jen zaktualizuje), Firefox se přeskočí, pokud je nainstalovaný, a tiskárna se přeskočí, pokud existuje.
  Registry/služby/personalizace se přepisují (je to neškodné).
- **BitLocker** — vypnutí je záměrné (interní výjimka). Na nešifrovaném disku `manage-bde -off` hlásí chybu (potlačeno); je-li C: opravdu zašifrované, zákaz služby BDESVC může pozastavit dešifrování v půlce.
- **Oracle Java** — pro komerční/úřední použití formálně vyžaduje licenci Oracle.
- **TeamViewer** — winget balíček občas hlásí „hash mismatch"; pak stačí spustit znovu.
- **Odinstalace cizích AV** — best-effort; McAfee/Norton můžou potřebovat vendor nástroj.
- **Zástupci na ploše** — Chrome, Firefox, Outlook (classic), Word, Excel, TeamViewer; kopírují se do Default profilu (noví uživatelé) **i na plochu admina** (aby je bylo vidět hned). Smazatelné.
- **Připnutí na panel** — policy přes `LayoutXMLPath` (funguje na 24H2/25H2); projeví se po restartu, na 26200.5722+ i u stávajících uživatelů.
- **Tapeta** se nastaví jako výchozí, ale **měnitelná** (HKCU + Default hive, ne PersonalizationCSP). **Zamykací obrazovka** je ve výchozím vypnutá, protože ji Win11 umí nastavit jen uzamčením.
- **Pořadí ikon v oznamovací oblasti (u hodin)** — Windows 11 to skriptem spolehlivě nenastaví; řeší se ručním přetažením.
- **Konzole** — QuickEdit je na začátku vypnut, aby kliknutí do okna nepozastavilo běh.
- **Log na ploše** — každý běh vytvoří nový soubor s časovým razítkem; staré klidně smaž.
