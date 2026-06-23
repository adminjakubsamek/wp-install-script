# WELL PACK - automatický instalační skript Windows

## Spuštění

Na čistém Win11 po prvním spuštění → **PowerShell jako správce** → vlož:

```powershell
irm "https://raw.githubusercontent.com/adminjakubsamek/wp-install-script/main/bootstrap.ps1" | iex
```

Na konci se PC restartuje za 30 s (zrušíš `shutdown /a`).

## Co skript dělá (v pořadí)

1. **Ověří práva správce** a začne psát log **na plochu admina** (žádný zápis do `C:\ProgramData`).
2. **Zjistí jazyk Windows** (cs/en/de, fallback cs) — podle něj se řídí jazyk aplikací.
3. **Pojmenuje počítač podle sériového čísla** (z BIOSu; projeví se po restartu). Lze vypnout a doplnit předponu.
4. **Předinstalační úklid (jako první):** odinstaluje všechny předinstalované Office Click-to-Run
   produkty a jazykové mutace (přes ODT Remove All) i Store OneNote, a best-effort odebere cizí
   antiviry (McAfee, Norton, Avast…). **Defender a ESET zůstávají.**
5. **Nainstaluje aplikace přes winget** (vždy nejnovější verze) — viz seznam níže;
   mimo jiné ověří/doinstaluje **Microsoft Teams** (nový klient).
6. **Vynutí aktualizaci aplikací z Microsoft Store** (na pozadí, pokud je třeba).
7. **Firefox** stáhne rovnou v lokalizované verzi přímo od Mozilly (dle jazyka Windows).
8. **Microsoft 365 Apps for business** — stáhne ODT přes winget, nainstaluje Office
   v **jednom jazyce** dle Windows, **bez aktivace** (aktivuje uživatel přihlášením).
9. **Aplikuje Win11 tweaky** (vyčištěný preset Disassembler0 z `tweaks/`).
10. **Aplikuje konfigurace** z `config/` (pdfsam, vlc) a vypne u Adobe Readeru nabízení placeného Acrobatu.
11. **Nainstaluje tiskárnu TOSHIBA-recepce** (ovladač z GitHub Release; lze vypnout).
12. **Vlastní příkazy**: vypne BitLocker na C: + službu BDESVC, vypne UDP pro RDP,
   potlačí varovný dialog přesměrování, vypne automatické přidávání síťových tiskáren
   a **odblokuje Windows feature updates** (telemetrie = Required, DiagTrack zapnut, spuštěn appraiser).
   Nastaví **časové pásmo** (CET + automaticky dle polohy) a **vynutí synchronizaci času**.
13. **Přizpůsobí hlavní panel, Start a plochu**: Start vlevo, hledání jen jako ikona (lupa),
   sloučené ikony oken, viditelné přípony souborů, na ploše Tento počítač / Složka uživatele / Koš,
   a připne na panel v pořadí Firefox, Chrome, Průzkumník, Outlook, Teams, Výstřižky (Edge odepnut).
14. **Vyhodí smazatelné zástupce na plochu uživatele** (kopie do Default profilu, takže je nový
   uživatel může smazat) a volitelně vyčistí nesmazatelné zástupce z veřejné plochy.
15. **Vytvoří na ploše admina poznámku** `ADMIN - po instalaci.txt`: ruční úkoly
   (ESET, **statické heslo TeamViewer**, tiskárny, migrace dat, Chrome záložky/hesla,
   OneDrive, heslo + ESET šifrování) **plus výpis toho, co se ve skriptu nepovedlo** a cestu k logu.
16. **Uklidí** dočasné soubory, vypíše shrnutí (OK / neúspěšné) a restartuje.

## Instalované aplikace

Chrome, Firefox, 7-Zip, VLC, Adobe Reader, PDFsam, doPDF, **Oracle Java 8 (JRE)**,
OpenVPN Community, **Azure VPN Client**, TeamViewer, **Microsoft Teams**, **Microsoft 365 Apps for business**.
Plus aktualizace aplikací z Microsoft Store.

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

- Log každého běhu: **na ploše admina** `install_<datum>_<čas>.log`.
- Náhled bez instalace: nahoře `$PreviewOnly = $true` → jen vypíše plán a skončí.

## Poznámky

- **Aktivace Office** a **VPN profily** se řeší ručně (skript instaluje jen programy).
- **Oracle Java** — pro úřední/komerční použití formálně vyžaduje licenci od Oracle.
- **Název počítače** — `$RenameToSerial` nahoře ve skriptu (default zapnuto); `$NamePrefix`
  přidá předponu (např. `WP-`). Nepoužitelná sériová čísla (prázdné, „Default string"…) se
  přeskočí. Limit názvu je 15 znaků (delší se ořízne).
- **TeamViewer** (dříve) — winget balíček občas hlásí „hash mismatch"; pak stačí spustit znovu.
  Spouštění s Windows je automatické (plná verze běží jako služba). **Statické heslo** ale
  nejde nasadit jedním reg klíčem na všechny PC — TeamViewer ho šifruje pro každý stroj jinak;
  řeší se buď Easy Access (přiřazení k TV účtu) nebo nastavením hesla per-stroj přes TV.
- **Hlavní panel / Start / plocha** — připnutí aplikací platí pro nově přihlášené uživatele
  (zakládá se z Default profilu); na účtu, pod kterým běží instalace, se taskbar nemění.
  „Sloučené ikony oken" = `TaskbarGlomLevel=0`; pro opačné chování (nikdy neslučovat) dej `2`.
- **Předinstalační úklid** — `$RemovePreinstalledOffice` a `$RemoveThirdPartyAV` nahoře ve skriptu.
  Odinstalace cizích AV je best-effort; tvrdošíjné (McAfee/Norton) můžou potřebovat vendor nástroj
  (MCPR / Norton Remove & Reinstall). ESET se záměrně **nemaže**.
- **Zástupci na ploše** — seznam v `$UserDesktopShortcuts` (názvy `.lnk`, hledají se ve Start menu);
  kopírují se do Default profilu, takže je každý nový uživatel vlastní a může smazat.
  `$ClearPublicDesktop=$true` navíc smaže nesmazatelné zástupce z veřejné plochy.
- **BitLocker** — vypnutí je záměrné (interní výjimka); ostatní se řeší jinde.
- **Feature updates** — aby stroje dostávaly nové buildy Win11, skript po presetu
  vrací telemetrii na *Required* a zapíná službu DiagTrack. Pokud chceš telemetrii
  úplně vypnutou, tuhle část v sekci „Vlastní příkazy" odstraň a nové buildy řeš ručně.
