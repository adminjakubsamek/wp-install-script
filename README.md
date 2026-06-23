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
│  ├─ pdfsam.l4j.ini
│  ├─ vlc.reg
│  └─ wincmd.ini            # jazyk (LanguageIni) přepíše bootstrap dle Windows
└─ desktop/                  # volitelné ikony na plochu
   ├─ PlochaAll/
   └─ PlochaUser/
```

> Pozn.: `INSTALL.bat`, `vpn.ps1`, `SetACL.exe`, `syspin.exe`, `elevate.exe` se sem
> **nepřenášejí** — nahradil je `bootstrap.ps1` + winget. Site-specific věci
> (Toshiba tiskárna, OpenVPN profil) řešíme zvlášť/ručně.

## 1) Založení repa

1. GitHub → **New repository** → název `wp-install-script` → **Private**.
2. Nahrát soubory dle struktury výše (web UI „Add file → Upload files", nebo `git push`).
3. Do `bootstrap.ps1` nahoře vyplnit `$Owner` a `$Repo`.

## 2) Spuštění na novém PC

Repo je veřejné → žádný token není potřeba, soubory se tahají přes
`raw.githubusercontent.com`. Čistý Win11 po prvním spuštění, otevřít
**PowerShell jako správce**, vložit:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

Skript: ověří admin práva → detekuje jazyk Windows → nainstaluje aplikace win?getem
v nejnovějších verzích → stáhne a aplikuje tweaky a konfigy do temp složky →
temp smaže → naplánuje restart.

## 3) Jazyk programů (dle jazyka Windows)

Skript přečte display language Windows (cs/en/de, fallback en) a podle toho:

| Aplikace | Jak se řeší jazyk |
|---|---|
| 7-Zip, VLC, Chrome, Adobe Reader | automaticky dle jazyka OS (multijazyčné) |
| Firefox | `policies.json` s `RequestedLocales` → langpack se dotáhne sám |
| doPDF | parametr instalátoru `-install_language=<cs/en/de>` |
| Total Commander | `LanguageIni` ve `wincmd.ini` (cz/eng/deu .lng) |
| Java (Temurin), OpenVPN | bez UI jazyka / nerelevantní |

## 4) Co ještě ověřit na prvním stroji (v skriptu označeno „OVERIT")

- **Total Commander** — winget ho instaluje jen do *user-scope* (jiná cesta než staré
  `C:\Program Files\totalcmd`); doladit cílovou cestu `wincmd.ini`.
- **doPDF** — ověřit, že winget předá `-install_language` instalátoru (jinak dořešit přes
  přímý download MSI/EXE).
- **Adobe Reader** — ověřit, že winget balíček je MUI a chytne jazyk OS.
- **Ikony na plochu** — v repu je lepší držet je jako ZIP a v `bootstrap.ps1` rozbalit
  (v kódu ponecháno jako TODO).
- **winget na čistém OOBE** — na Win11 Pro bývá hned; pokud chybí, aktualizovat
  „App Installer" ve Store.

## Bezpečnost

- Repo je veřejné, takže do něj **nesmí** přijít nic citlivého. Po auditu v souborech
  žádná hesla nejsou (NAS heslo, admin heslo i VPN PSK jsme odstranili).
- OpenVPN `.ovpn` profily a certifikáty se sem **nedávají** — nasazují se ručně.
- `bootstrap.ps1` se spouští přes `irm ... | iex` z veřejné URL — kdokoliv s odkazem
  ho vidí. To je u provisioning skriptu bez tajemství v pořádku; jen v něm nesmí
  nikdy skončit žádný credential.
