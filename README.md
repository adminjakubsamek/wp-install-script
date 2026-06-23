# wp-install-script — nasazení nových PC (Všenory)

Veřejné repo, ze kterého `bootstrap.ps1` tahá tweaky, konfigurace a ikony.
Instalace programů jde přes **winget** (nejnovější verze přímo od výrobců).
Žádná závislost na NASce ani na jednotce Q:.

## Struktura repa

```
wp-install-script/
├─ bootstrap.ps1              # hlavní skript, spouští IT na čistém Win11
├─ tweaks/
│  ├─ win10.ps1              # runner (beze změny)
│  ├─ win10.psm1             # modul tweaků (beze změny)
│  └─ install.preset         # vyčištěný preset (z auditu)
├─ config/
│  ├─ pdfsam.reg
│  ├─ pdfsam.l4j.ini        # volitelné
│  ├─ vlc.reg               # volitelné
│  └─ office/
│     ├─ configuration.xml  # ODT: M365 Apps for business, jazyk=MatchOS
│     └─ setup.exe          # ODT (volitelné – fallback; jinak si ho stáhne winget)
└─ desktop/                  # volitelné ikony na plochu
   ├─ PlochaAll/
   └─ PlochaUser/
```

> Pozn.: `INSTALL.bat`, `vpn.ps1`, `SetACL.exe`, `syspin.exe`, `elevate.exe` se sem
> **nepřenášejí** — nahradil je `bootstrap.ps1` + winget. Site-specific věci
> (Toshiba tiskárna, OpenVPN profil) řešíme zvlášť/ručně.

## 1) Založení repa

1. GitHub → **New repository** → název `wp-install-script` → **Public**.
2. Nahrát soubory dle struktury výše (web UI „Add file → Upload files", nebo `git push`).
3. `$Owner`/`$Repo` jsou v `bootstrap.ps1` už vyplněné na `adminjakubsamek/wp-install-script`.

## 2) Spuštění na novém PC

Repo je veřejné → žádný token není potřeba, soubory se tahají přes
`raw.githubusercontent.com`. Čistý Win11 po prvním spuštění, otevřít
**PowerShell jako správce**, vložit:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

Skript: ověří admin práva → detekuje jazyk Windows → nainstaluje aplikace wingetem
v nejnovějších verzích → stáhne a aplikuje tweaky a konfigy do temp složky →
temp smaže → vypíše shrnutí → naplánuje restart.

**Log** každého běhu: `C:\ProgramData\wp-install\install_<datum>_<cas>.log`.
**Náhled bez instalace** (jen výpis plánu): nahoře v `bootstrap.ps1` přepni
`$PreviewOnly = $true` a spusť — nic se nenainstaluje.

### Instalované aplikace
Chrome, Firefox, 7-Zip, VLC, Adobe Reader, PDFsam, doPDF, **Oracle Java 8 (JRE)**,
OpenVPN Community, TeamViewer, **Microsoft 365 Apps for business**.
Total Commander se **neinstaluje**.

- **Firefox** se instaluje rovnou jako lokalizovaný build přímo od Mozilly (jazyk dle Windows).
- **Adobe Reader** = bezplatný Reader; nabídka upgradu na placený Acrobat je vypnutá
  (`bAcroSuppressUpsell`), takže se chová jako čistý Reader.
- **Java** = `Oracle.JavaRuntimeEnvironment` (klasická java.com, Java 8). Pozn.: komerční/úřední
  použití Oracle Javy vyžaduje licenci od Oracle.

#### Microsoft 365 Apps
Instaluje se přes Office Deployment Tool (ODT) podle `config/office/configuration.xml`:
produkt **for business**, jazyk **`MatchOS`** (dle Windows, fallback en-us), tichá
instalace, **bez aktivace** – licenci aktivuje uživatel přihlášením pod svým účtem.
ODT `setup.exe` si skript stáhne přes winget (nejnovější); jako fallback může ležet
v `config/office/setup.exe`.

## 3) Jazyk programů (dle jazyka Windows)

Skript přečte display language Windows (cs/en/de, fallback en) a podle toho:

| Aplikace | Jak se řeší jazyk |
|---|---|
| 7-Zip, VLC, Chrome, Adobe Reader | automaticky dle jazyka OS (multijazyčné) |
| Firefox | lokalizovaný build přímo od Mozilly podle jazyka Windows |
| doPDF | parametr instalátoru `-install_language=<cs/en/de>` |
| Java (Oracle 8), OpenVPN, TeamViewer | bez UI jazyka / nerelevantní |

## 4) Co ještě ověřit na prvním stroji (v skriptu označeno „OVERIT")

- **TeamViewer** — winget balíček občas hlásí „installer hash mismatch" (chyba na straně
  manifestu); když spadne, zkusit znovu později nebo přímý download z teamviewer.com.
  Pozn.: komerční/úřední použití TeamVieweru vyžaduje licenci. Host varianta =
  `TeamViewer.TeamViewer.Host` (bezobslužný přístup).
- **Microsoft 365** — na prvním stroji ověřit, že ODT `setup.exe` se přes winget najde
  (hledá se v `C:\Program Files\WinGet\Packages\...OfficeDeploymentTool`). Když ne,
  nahraj jednorázově `config/office/setup.exe` (viz níže) — skript ho použije jako fallback.
- **doPDF** — ověřit, že winget předá `-install_language` instalátoru (jinak dořešit přes
  přímý download MSI/EXE).
- **Adobe Reader** — ověřit, že winget balíček je MUI a chytne jazyk OS.
- **Ikony na plochu** — v repu je lepší držet je jako ZIP a v `bootstrap.ps1` rozbalit
  (v kódu ponecháno jako TODO).
- **winget na čistém OOBE** — na Win11 Pro bývá hned; pokud chybí, aktualizovat
  „App Installer" ve Store.

## Tiskárna TOSHIBA-recepce (volitelné, jen na pobočce)

Tiskárna (IP 192.168.0.240) se instaluje **vždy** (`$InstallPrinter = $true`).
Když ji na nějakém stroji nechceš, přepni nahoře v `bootstrap.ps1` na:

```powershell
$InstallPrinter = $false
```

Soubory:
- **`tisk-recepce.ps1`** a **`SetACL.exe`** → v **kořeni repa** (malé, stahují se přes raw).
- **`ToshibaDRV.zip`** → ovladač je velký, do stromu repa se nevejde (limit 100 MB).
  Nahraj ho jako **přílohu GitHub Release** (Releases → *Create a new release* →
  tag např. `drivers` → *Attach binaries* → vyber `ToshibaDRV.zip` → *Publish release*).
  Skript ho tahá z `releases/latest/download/ToshibaDRV.zip`, takže vždy z nejnovějšího release.

`ToshibaDRV.zip` vyrob tak, že zazipuješ **obsah** složky `ToshibaDRV`
(aby po rozbalení do `C:\Program Files\ToshibaDRV` vznikla cesta
`C:\Program Files\ToshibaDRV\Driver\64bit\eSf6u.inf`).

> Pozn.: ovladač je jeden vícejazyčný balík (TOSHIBA e-STUDIO Universal Printer Driver 2),
> jazyk dialogů se řídí jazykem Windows. Automatický download z webu Toshiby nejde –
> stránka blokuje roboty a má víc verzí; proto pevná verze v Release.

## Office Deployment Tool – fallback setup.exe (volitelné)

Pokud by `setup.exe` nešel získat přes winget, přidej ho jednorázově do repa:

1. Stáhni ODT z Microsoftu (Download Center, ID 49117) – soubor `officedeploymenttool_*.exe`.
2. Spusť ho a rozbal (nebo `officedeploymenttool_*.exe /quiet /extract:C:\ODT`).
3. Z rozbalené složky vezmi `setup.exe` a nahraj ho do `config/office/setup.exe`.

`configuration.xml` je už v repu, ten se needituje.

## Bezpečnost

- Repo je veřejné, takže do něj **nesmí** přijít nic citlivého. Po auditu v souborech
  žádná hesla nejsou (NAS heslo, admin heslo i VPN PSK jsme odstranili).
- OpenVPN `.ovpn` profily a certifikáty se sem **nedávají** — nasazují se ručně.
- `bootstrap.ps1` se spouští přes `irm ... | iex` z veřejné URL — kdokoliv s odkazem
  ho vidí. To je u provisioning skriptu bez tajemství v pořádku; jen v něm nesmí
  nikdy skončit žádný credential.
