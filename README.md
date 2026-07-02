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
- `$NamePrefix` — volitelná předpona názvu PC (např. `'WP-'`); prázdné = jen sériové číslo.
- `$RemovePreinstalledOffice` — nejdřív odinstalovat OEM Office balast (`$true`).
- `$RemoveThirdPartyAV` — nejdřív odinstalovat cizí antiviry (`$true`).
- `$UserDesktopShortcuts` — zástupci na plochu uživatele (názvy `.lnk`, lze i `*`).
- `$ClearPublicDesktop` — smazat zástupce z veřejné plochy (`$true`).
- `$SetWallpaper` / `$SetLockScreen` — nastavit tapetu / zamykací obrazovku všem (`$true`).
- `$WallpaperFallback` / `$LockScreenFallback` — výchozí obrázek, když není v repu.
- `$SetDefaultApps` — nastavit výchozí aplikace (Chrome, VLC, Adobe, Outlook) novým uživatelům (DISM) i aktuálnímu (SetUserFTA).
- `$AdminUser` — účet, kterému se nastaví admin práva + heslo bez expirace (samotné heslo ručně).

---

## Průběh instalace (v pořadí)

1. **Kontrola práv správce** + vypnutí QuickEditu + start logu na plochu admina.
2. **Detekce jazyka Windows** → `cs` / `en` / `de` (fallback `cs`); řídí jazyk aplikací.
3. **Přejmenování počítače** podle sériového čísla z BIOSu (projeví se po restartu).
4. **Ověření wingetu** (najde i na čerstvém stroji bez PATH).
5. **Předinstalační úklid (jako PRVNÍ akce):**
   - odinstaluje **všechny předinstalované Office Click-to-Run** produkty a jazykové mutace (ODT *Remove All*);
   - odebere **Store OneNote / Office stuby** (i provisioned, aby se nevracely novým uživatelům);
   - **best-effort odebere cizí antiviry** (McAfee, Norton, Avast, AVG, Avira, Kaspersky, Bitdefender, Webroot, Malwarebytes, Panda, Sophos, TotalAV). **Defender a ESET zůstávají.**
6. **Instalace aplikací přes winget** (nejnovější verze) — viz seznam níže.
7. **Aktualizace aplikací z Microsoft Store** (na pozadí; přes MDM `UpdateScanMethod`).
8. **Firefox** — lokalizovaný build přímo od Mozilly (dle jazyka Windows), tichá instalace.
9. **Microsoft 365 Apps for business** — přes ODT, **jeden jazyk** dle Windows, **bez aktivace**.
10. **Win11 tweaky** — vyčištěný preset Disassembler0 (`tweaks/`).
11. **Konfigurace aplikací** — pdfsam, vlc, vypnutí Adobe upsellu.
12. **Tiskárna TOSHIBA-recepce** (volitelné; ovladač z GitHub Release).
13. **Vlastní příkazy** — BitLocker, RDP, NCD, odblokování feature updates, časové pásmo + sync,
    **napájení = nejvyšší výkon** (uspávání ze sítě = Nikdy), **System Restore limit 5 %**, **popisek disku C: = OS**,
    **Defender SmartScreen + blokování PUA**, **účet admin** (admin práva + heslo bez expirace; heslo ručně),
    **indexace celého disku C:** (Enhanced) + běžící Windows Search.
14. **Personalizace** — hlavní panel, Start, plocha (i pro nové uživatele).
15. **Zástupci na plochu uživatele** (smazatelné) + úklid veřejné plochy.
16. **Tapeta + zamykací obrazovka** — pro všechny uživatele (PersonalizationCSP).
16b. **Výchozí aplikace** — ProgID se čtou z registru; noví uživatelé přes DISM, aktuální uživatel přes `SetUserFTA.exe` (je-li v repu). Chrome=http/https/.htm/.html, Adobe=.pdf, Outlook=mailto, VLC=.avi/.mp3/.mp4.
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
- **Tapeta + zamykací obrazovka pro všechny** (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP`):
  - `DesktopImagePath` / `DesktopImageUrl` + `DesktopImageStatus = 1`.
  - `LockScreenImagePath` / `LockScreenImageUrl` + `LockScreenImageStatus = 1`.
- **Obrázek pozadí na přihlašovací obrazovce** (`HKLM\SOFTWARE\Policies\Microsoft\Windows\System`):
  - `DisableLogonBackgroundImage = 0` (zobrazovat).
- **Defender SmartScreen / PUA** (Řízení aplikací a prohlížečů):
  - `Set-MpPreference -PUAProtection Enabled` (blokovat potenciálně nežádoucí aplikace).
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
- `…\Search` → `SearchboxTaskbarMode = 1` — hledání jen jako ikona (lupa).
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

- **Start vlevo**, **lupa jako ikona**, **sloučené ikony oken**, **viditelné přípony**.
- **Na ploše**: Tento počítač, Složka uživatele, Koš.
- **Připnutí na panel v pořadí**: Chrome → Firefox → Průzkumník → Outlook → Teams → Výstřižky (**Edge odepnut**).
- Připnutí na panel se nasazuje **policy metodou** (`HKLM\…\Explorer\LayoutXMLPath` → `C:\ProgramData\WPBranding\TaskbarLayout.xml`), protože na Win11 24H2/25H2 už metoda přes Default profil nefunguje. Projeví se **po restartu** (na buildu 26200.5722+ i u stávajících uživatelů).
- „Sloučené ikony oken" = `TaskbarGlomLevel=0`; pro opačné chování (nikdy neslučovat) dej `2`.

---

## Tapeta a zamykací obrazovka

- Nastaví se **všem uživatelům** přes PersonalizationCSP a **zamknou** (uživatel je v Nastavení nezmění).
- Obrázky skript hledá v repu: `config/branding/wallpaper.jpg` a `config/branding/lockscreen.jpg`.
- Když v repu nejsou, použije **výchozí Win11 `img0.jpg`** (modrá „Bloom"). Obrázky se vždy zkopírují do `C:\ProgramData\WPBranding` a CSP ukazuje na tu kopii (stabilní cesta).
- Na přihlašovací obrazovce se zobrazuje obrázek zamykací obrazovky.

---

## Výchozí aplikace a asociace souborů (vč. 7-Zip)

Skript nastavuje tyto výchozí aplikace: **Chrome** pro http/https/.htm/.html, **Adobe** pro .pdf,
**Outlook** pro mailto, **VLC** pro .avi/.mp3/.mp4. **ProgID se čtou přímo z registru** (z `Capabilities`
nainstalovaných aplikací), takže nezávisí na verzi ani jazyku a **není potřeba nic exportovat**.

Nasazení probíhá dvěma cestami, protože Windows 11 chrání výchozí aplikace per-uživatel hashem:

- **Noví uživatelé** — vygeneruje se `appassoc.xml` a naimportuje přes `dism /online /import-defaultappassociations`.
  (Má-li repo `config/appassoc.xml`, použije se místo vygenerovaného — tvůj vlastní export má přednost.)
- **Aktuální uživatel** (účet, pod kterým skript běží = koncový uživatel) — nastaví se přes **`SetUserFTA.exe`**,
  který umí zapsat chráněný per-user hash. Aby to fungovalo, přidej do **kořene repa** `SetUserFTA.exe`
  (zdarma, https://kolbi.cz/SetUserFTA/). Bez něj se výchozí aplikace nastaví jen novým uživatelům.

> Proč to dřív nefungovalo: DISM import platí **jen pro nové uživatele**, ne pro účet, pod kterým instaluješ.
> Když skript spouští přímo koncový uživatel (např. `catalin.barbu`), musí se použít SetUserFTA.

---

## Předinstalační úklid (detail)

- **Office balast** — ODT s `<Remove All="TRUE"/>` smaže všechny Click-to-Run produkty a jazykové mutace najednou; pak se (krok 9) nainstaluje čistá jednojazyčná verze.
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
├─ SetUserFTA.exe         # výchozí aplikace pro aktuálního uživatele (volitelné, doporučené)
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
- **Chyba 1618 „another installation in progress"** — Windows dovolí jen jednu MSI instalaci naráz.
  Když během běhu instaluje něco na pozadí (Windows Update, aktualizace Store aplikací), MSI aplikace
  by jinak spadly. Instalační smyčka proto při neúspěchu **3× zopakuje pokus s pauzou 30 s**.
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
- **Tapeta a zamykací obrazovka** — přes PersonalizationCSP se nastaví a **zamknou** (uživatel je nezmění).
- **Pořadí ikon v oznamovací oblasti (u hodin)** — Windows 11 to skriptem spolehlivě nenastaví; řeší se ručním přetažením.
- **Konzole** — QuickEdit je na začátku vypnut, aby kliknutí do okna nepozastavilo běh.
- **Log na ploše** — každý běh vytvoří nový soubor s časovým razítkem; staré klidně smaž.
