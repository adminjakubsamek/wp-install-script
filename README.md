# WELL PACK - automatický instalační skript Windows

## Spuštění

Na čisté instalaci Windows 11 (po prvním přihlášení) → **PowerShell jako správce** → vlož jeden řádek:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

- Skript vyžaduje **práva správce** (jinak se ukončí).
- Na konci se počítač **restartuje za 30 s** — zrušíš `shutdown /a`.
- **Náhled bez instalace**: nahoře ve skriptu přepni `$PreviewOnly = $true` → jen vypíše plán a skončí.

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
- `$UserDesktopShortcuts` — zástupci na plochu uživatele (názvy `.lnk`).
- `$ClearPublicDesktop` — smazat zástupce z veřejné plochy (`$true`).

---

## Průběh instalace (v pořadí)

1. **Kontrola práv správce** + start logu na plochu admina.
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
13. **Vlastní příkazy** — BitLocker, RDP, NCD, odblokování feature updates, časové pásmo + sync.
14. **Personalizace** — hlavní panel, Start, plocha (i pro nové uživatele).
15. **Zástupci na plochu uživatele** (smazatelné) + úklid veřejné plochy.
16. **Poznámka na plochu admina** (úkoly + co se nepovedlo + cesta k logu).
17. **Úklid dočasných souborů**, výpis shrnutí, **restart**.

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

## Jazyk aplikací (dle jazyka Windows)

| Aplikace | Jak se řídí jazyk |
|---|---|
| 7-Zip, VLC, Chrome, Adobe Reader | automaticky dle jazyka OS |
| Firefox | lokalizovaný build od Mozilly (`cs` / `en-US` / `de`) |
| doPDF | parametr instalátoru `-install_language` |
| Microsoft 365 | jeden jazyk v ODT configu (`cs-cz` / `en-us` / `de-de`) |
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

---

## Soubory, které skript vytváří nebo mění

- **Log běhu**: `…\Desktop\install_<datum>_<čas>.log` (na ploše admina; **žádný zápis do `C:\ProgramData`**).
- **Poznámka pro admina**: `…\Desktop\ADMIN - po instalaci.txt`.
- **Připnutí na hlavní panel**: `C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml`.
- **Zástupci na ploše uživatele**: kopie `.lnk` do `C:\Users\Default\Desktop`.
- **Veřejná plocha**: smazání `C:\Users\Public\Desktop\*.lnk` (když `$ClearPublicDesktop=$true`).
- **PDFsam**: `pdfsam.l4j.ini` → `C:\Program Files\PDFsam Basic`.
- **Tiskový ovladač**: rozbalen do `C:\Program Files\ToshibaDRV`.
- **Dočasná složka** `%TEMP%\provision-xxxxxxxx` — na konci smazána.

---

## Hlavní panel / Start / plocha

- **Start vlevo**, **lupa jako ikona**, **sloučené ikony oken**, **viditelné přípony**.
- **Na ploše**: Tento počítač, Složka uživatele, Koš.
- **Připnutí na panel v pořadí**: Firefox → Chrome → Průzkumník → Outlook → Teams → Výstřižky (**Edge odepnut**).
- Připnutí na panel **platí pro nově přihlášené uživatele** (zakládá se z Default profilu); na účtu, pod kterým běží instalace, se panel nemění.
- „Sloučené ikony oken" = `TaskbarGlomLevel=0`; pro opačné chování (nikdy neslučovat) dej `2`.

---

## Předinstalační úklid (detail)

- **Office balast** — ODT s `<Remove All="TRUE"/>` smaže všechny Click-to-Run produkty a jazykové mutace najednou; pak se (krok 9) nainstaluje čistá jednojazyčná verze.
- **Cizí antiviry** — best-effort přes tichý odinstalátor / `msiexec /x`. Tvrdošíjné (McAfee, Norton) můžou vyžadovat vendor nástroj (MCPR, Norton Remove & Reinstall). **ESET se nemaže.**

---

## Struktura repa

```
wp-install-script/
├─ bootstrap.ps1          # hlavní skript
├─ README.md
├─ tisk-recepce.ps1       # instalace tiskárny (volá ho bootstrap)
├─ SetACL.exe             # práva tiskárny
├─ tweaks/
│  ├─ win10.ps1           # runner
│  ├─ win10.psm1          # modul tweaků
│  └─ install.preset      # vyčištěný preset
└─ config/
   ├─ pdfsam.reg
   ├─ pdfsam.l4j.ini
   └─ vlc.reg
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
- **Microsoft 365** – aktivace přihlášením uživatele.
- **VPN profily** (OpenVPN / Azure VPN) – import ručně.

---

## Poznámky a upozornění

- **BitLocker** — vypnutí je záměrné (interní výjimka). Pokud je C: opravdu zašifrované, zákaz služby BDESVC může pozastavit dešifrování v půlce — řeší se ručně.
- **Oracle Java** — pro komerční/úřední použití formálně vyžaduje licenci Oracle.
- **TeamViewer** — winget balíček občas hlásí „hash mismatch"; pak stačí spustit znovu.
- **Odinstalace cizích AV** — best-effort; McAfee/Norton můžou potřebovat vendor nástroj.
- **Připnutí na panel a zástupci na ploše** — platí pro nově přihlášené uživatele (Default profil).
- **Pořadí ikon v oznamovací oblasti (u hodin)** — Windows 11 to skriptem spolehlivě nenastaví (položky vznikají per-aplikace až při prvním spuštění pod uživatelem a pořadí není nikde stabilně vystaveno); řeší se ručním přetažením.
- **Log na ploše** — každý běh vytvoří nový soubor s časovým razítkem; staré klidně smaž.
