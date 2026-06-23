## Spuštění

Na čistém Win11 po prvním spuštění → **PowerShell jako správce** → vlož:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

Na konci se PC restartuje za 30 s (zrušíš `shutdown /a`).

## Co skript dělá (v pořadí)

1. **Ověří práva správce** a začne psát log do `C:\ProgramData\wp-install\`.
2. **Zjistí jazyk Windows** (cs/en/de, fallback cs) — podle něj se řídí jazyk aplikací.
3. **Nainstaluje aplikace přes winget** (vždy nejnovější verze) — viz seznam níže.
4. **Firefox** stáhne rovnou v lokalizované verzi přímo od Mozilly (dle jazyka Windows).
5. **Microsoft 365 Apps for business** — stáhne ODT přes winget, nainstaluje Office
   v **jednom jazyce** dle Windows, **bez aktivace** (aktivuje uživatel přihlášením).
6. **Aplikuje Win11 tweaky** (vyčištěný preset Disassembler0 z `tweaks/`).
7. **Aplikuje konfigurace** z `config/` (pdfsam, vlc) a vypne u Adobe Readeru
   nabízení placeného Acrobatu.
8. **Nainstaluje tiskárnu TOSHIBA-recepce** (ovladač z GitHub Release; lze vypnout).
9. **Vlastní příkazy**: vypne BitLocker na C: + službu BDESVC, vypne UDP pro RDP a
   potlačí varovný dialog přesměrování.
10. **Uklidí** dočasné soubory, vypíše shrnutí (OK / neúspěšné) a restartuje.

## Instalované aplikace

Chrome, Firefox, 7-Zip, VLC, Adobe Reader, PDFsam, doPDF, **Oracle Java 8 (JRE)**,
OpenVPN Community, TeamViewer, **Microsoft 365 Apps for business**.
Total Commander se **neinstaluje**.

## Jazyk aplikací (dle jazyka Windows)

| Aplikace | Jak |
|---|---|
| 7-Zip, VLC, Chrome, Adobe Reader | automaticky dle jazyka OS |
| Firefox | lokalizovaný build přímo od Mozilly |
| doPDF | parametr instalátoru `-install_language` |
| Microsoft 365 | ODT config s jedním jazykem (cs-cz / en-us / de-de) |
| Java, OpenVPN, TeamViewer | bez UI jazyka / nerelevantní |

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

**GitHub Release** (tag např. `drivers`) s přílohou **`ToshibaDRV.zip`** — ovladač
tiskárny (velký soubor, do stromu repa se nevejde). Skript ho bere z
`releases/latest/download/ToshibaDRV.zip`.

## Tiskárna

Instaluje se **vždy** (`$InstallPrinter = $true` nahoře v `bootstrap.ps1`). Kde ji
nechceš, přepni na `$false`. ZIP musí mít v kořeni cestu `Driver\64bit\eSf6u.inf`
(skript si INF i název ovladače najde sám).

## Log a náhled

- Log každého běhu: `C:\ProgramData\wp-install\install_<datum>_<čas>.log`.
- Náhled bez instalace: nahoře `$PreviewOnly = $true` → jen vypíše plán a skončí.

## Poznámky

- **Aktivace Office** a **VPN profily** se řeší ručně (skript instaluje jen programy).
- **Oracle Java** — pro úřední/komerční použití formálně vyžaduje licenci od Oracle.
- **TeamViewer** — winget balíček občas hlásí „hash mismatch"; pak stačí spustit znovu.
- **BitLocker** — vypnutí je záměrné (interní výjimka); ostatní se řeší jinde.
