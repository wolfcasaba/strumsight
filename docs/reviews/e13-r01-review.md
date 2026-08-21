# E13-R01 — Review

Brief: `docs/rounds/e13-r01-ui-baseline-inventory.md`
Reviewed head: `5fc18cea1f0b`
Reviewer: Codex Sol (független a Terra implementertől) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az első review egy BLOCKER és négy MAJOR leletet talált. A Terra két
javítócommitja (`dc053d52`, `6a09dad7`) után mind az öt lelet lezárható.
A friss, távoli branch-SHA-ról készített izolált klónban a teljes kör-gate
7/7 zöld; a screenshot-capture újrafuttatása bájtszintű diff nélkül
reprodukálta a hét képet. Mind a hét PNG-t külön megnyitottam: olvasható
production tipográfia és Material ikonok látszanak, Ahem-blokk, négyzetes ikon
és debug banner nincs.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nulla `lib/**` módosítás | ✅ | `git diff --name-only origin/main...HEAD -- lib` → üres |
| A2 | Determinisztikus inventory | ✅ | `ui_inventory_test.dart`; az első review sort-rontása célzottan piros volt |
| A3 | Mind az 58 production screen szerepel | ✅ | `dart run tool/ui_inventory.dart` → 58 screen, 96 reusable widget/view, 16 overlay-forrás |
| A4 | Legacy ↔ cél route-map és kockázatok | ✅ | a 40 `AppRoutes` string és a 40 current-route sor rendezett halmazkülönbsége üres; a `:songId` + typed `extra` contract rögzítve |
| A5 | Token-adósság mérve | ✅ | exact `rg -o`: 28 color occurrence / 9 fájl, 174 `TextStyle`, 817 spacing occurrence |
| A6 | Prioritásos accessibility-leletek | ✅ | `accessibility-findings.md`; a korábbi két piros saroksáv bizonyítottan capture-debug-banner volt, nem production overflow |
| A7 | Screenshot nem design-jóváhagyás | ✅ | `docs/ui/README.md:3-5` |
| A8 | Hét production-state screenshot megnyitható és nem üres | ✅ | strukturális teszt zöld; hét kézi megnyitás; capture újrafuttatás után `git diff --exit-code` zöld |
| A9 | Kötelező round-gate zöld | ✅ | izolált klón: 7/7 lépés, terminális exit 0 |

## Scope-audit

Az implementer három saját commit-tartománya külön-külön:

- `6570b678..ce190827` → OK, 16/16 engedélyezett út;
- `0fe1b9d3..dc053d52` → OK, 13/13 engedélyezett út;
- `dc053d52..6a09dad7` → OK, 11/11 engedélyezett út.

A friss `origin/main...5fc18cea` teljes branch-diff 18 utat tartalmaz:
16 briefben engedélyezett implementer-utat, a generált/ignored review-jelentést
és az ADR 0376-ot. Az audit egyedül az ADR-t jelzi listán kívülinek, de az ADR
a kötelező orchestrátor pre-flight része, a `6570b678` implementer
launch-HEAD-ben már commitolva volt; ezért ez nem implementer-scope sértés.
Az upstream merge-ek által behozott útvonalakat egyik implementer-audit sem
tulajdonítja a körnek.

## Megállapítások

### F1 — BLOCKER — A kötelező screenshot-validátor 10 perc után timeoutolt

- **Javítás:** a corpus-dekódolás plain aszinkron `test`-ben fut explicit
  10 másodperces timeouttal, a fake-async widget-zónán kívül.
- **Ellenőrzés:** a célteszt és a teljes kör-gate terminális exit 0-val zárt.
- **Státusz:** FIXED (`dc053d52`)

### F2 — MAJOR — A route-map elvesztette a `songTrainerResult` path-paraméterét

- **Javítás:** az exact current route `/song-trainer/result/:songId`; a
  `songId` path-paraméter és a typed `SongTrainerResult` `extra` kettős
  contract dokumentált.
- **Ellenőrzés:** a 40 kód-string és 40 dokumentált current route
  halmazkülönbsége üres.
- **Státusz:** FIXED (`dc053d52`)

### F3 — MAJOR — A token-adósság számai nem voltak reprodukálhatók

- **Javítás:** az exact parancsok, mérési egységek és újramért 28/9,
  174, illetve 817 érték dokumentált.
- **Ellenőrzés:** a report készítésekor mind a négy parancs egyezett a táblával.
- **Státusz:** FIXED (`dc053d52`)

### F4 — MAJOR — A corpus nem a production tipográfiát renderelte

- **Javítás:** a capture a bundle Poppins/Montserrat/Material Icons és az aktív
  Flutter SDK Roboto Regular/Medium/Bold fontjait tölti; a wrapper a production
  theme-et használja.
- **Ellenőrzés:** a capture újrafuttatása 2 passed / 1 skipped, majd
  `git diff --exit-code` zöld; mind a hét PNG kézi review-ja tiszta.
- **Státusz:** FIXED (`6a09dad7`)

### F5 — MAJOR — Két piros saroksáv hibásan production overflowként szerepelt

- **Javítás:** a közvetlen capture wrapper kikapcsolja a debug bannert; a
  corpus újragenerálva, a leletlista az artifact eredetét rögzíti.
- **Ellenőrzés:** a Tuner és onboarding képen nincs piros sáv; a wrapper-test
  `debugShowCheckedModeBanner == false` értéket követel.
- **Státusz:** FIXED (`6a09dad7`)

### F6 — NOTE — A valódi-sértés őrök működnek

- **Bizonyíték:** az első review-ban az inventory rendezés eltávolítása
  `ui_inventory_test.dart`-ot pirosra vitte. A végső review-ban a
  `live-compact-portrait.png` ideiglenes eltávolítása a corpus-tesztet
  célzottan pirosra vitte (`mutation_exit=1`); restore után a klón tiszta.
- **Státusz:** FIXED (review-bizonyíték, nincs production patch)

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény |
|---|---|
| format | ✅ 1735 fájl, 0 változás |
| analyze | ✅ `No issues found` |
| `ui_inventory_test.dart` | ✅ 1/1 |
| `ui_baseline_screenshot_test.dart` | ✅ 2 passed / 1 skipped |
| architecture | ✅ 12 ismert allowlisted eltérés |
| secrets | ✅ 3120 fájl, 0 lelet |
| l10n | ✅ 1503 EN/HU message, aggregate friss |
| capture-reprodukció | ✅ 2 passed / 1 skipped, nulla git diff |
| CI teljes suite + property | merge előtt exact-SHA run szükséges |

## Merge-döntés

Correctness review: **APPROVED**. Nyitott BLOCKER/MAJOR nincs. Az ADR 0052
szerinti merge csak az exact-SHA Full Gate és Router CI sikere után engedett.
