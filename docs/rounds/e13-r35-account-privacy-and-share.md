# E13-R35 — Account, Settings, Privacy, Offline AI és Share UI

- **Státusz:** READY (pre-flight elvégezve 2026-08-27, `main @ 9ca4a0dc` — lásd §0.0.B;
  előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 35
- **Kör-azonosító:** `E13-R35`
- **Branch:** `<motor>/e13-r35-account-privacy-and-share`
- **Előfeltétel:** `E13-R34` merge-elve (közösségi kihívások)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs írnivaló — a
  [`0292`](../adr/0292-model-activation-requires-verified-integrity.md) **MÁR
  MEGÍRVA ÉS MERGE-ELVE** (`5b32bd8e`, 2026-08-15). **A kör ADR-t NEM ír, a
  `docs/adr/` TILOS zóna, a 0292 módosítása H1** (§0.0.B/B2).

> ✅ **Pre-flight ELVÉGEZVE (2026-08-27, orchestrátor Claude Opus 5).** A brief
> fejléce a TÉNYLEGES beállítás-szinkron réteg mérését írta elő: a
> `settings_sync.dart` a „csak szerver-megerősítés után szinkronizált" szabályt
> **MÁR betartja** (`_sendPatch` `Success()` ága), a `settings_sync_test.dart`
> pedig — a kör listáján KÍVÜL — kipinneli, hogy a bukott írás **soha nem
> ismételhető automatikusan**. Ezért az A4 „újrapróbál" cellája
> **FELHASZNÁLÓ-INDÍTOTTA** újrapróbálás, nem automatikus replay (B3). A
> `brief-lint` `S13` lelete a B1-ben oldódik fel, a golden-útvonal a B8-ban
> kerül ki a lokális kapuból (ADR 0426).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/auth/",
  "lib/features/settings/",
  "lib/features/offline_ai/",
  "lib/features/share/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/settings/lab_mode_toggle_test.dart",
  "test/features/settings/settings_account_test.dart",
  "test/features/settings/vision_privacy_screen_test.dart",
  "test/features/share/share_preview_test.dart",
  "test/features/share/strum_card_test.dart",
  "test/features/share/strum_reel_test.dart",
  "test/features/share/wrapped_test.dart",
  "test/features/settings/auth_states_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/model_integrity_test.dart",
  "test/features/settings/share_redaction_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/share/reel_meter_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "docs/rounds/e13-r35-account-privacy-and-share.md",
]
gate_tests = [
  "test/features/settings/auth_states_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/model_integrity_test.dart",
  "test/features/settings/share_redaction_test.dart",
  "test/features/settings/settings_sync_test.dart",
  "test/features/settings/settings_account_test.dart",
  "test/features/settings/vision_privacy_screen_test.dart",
  "test/features/settings/lab_mode_toggle_test.dart",
  "test/features/share/share_preview_test.dart",
  "test/features/share/strum_card_test.dart",
  "test/features/share/strum_reel_test.dart",
  "test/features/share/wrapped_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/share/reel_meter_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
  "test/features/today/hub_navigation_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a kör közvetlenül érinti az `auth`, `privacy` és `share` felületeket: bejelentkezés, adatvédelmi beállítás és kifelé megosztás.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/offline_ai/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `auth` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `offline_ai` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `settings` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `share` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/settings/lab_mode_toggle_test.dart`
  - `test/features/settings/settings_account_test.dart`
  - `test/features/settings/vision_privacy_screen_test.dart`
  - `test/features/share/share_preview_test.dart`
  - `test/features/share/strum_card_test.dart`
  - `test/features/share/strum_reel_test.dart`
  - `test/features/share/wrapped_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 19 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/auth/`, `lib/features/offline_ai/`, `lib/features/settings/`, `lib/features/share/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/navigation/adaptive_scaffold_test.dart`
- `test/app/navigation/legacy_route_redirect_test.dart`
- `test/app/offline_network_guard_test.dart`
- `test/app/routing/app_router_test.dart`
- `test/features/share/reel_meter_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

**Kiegészítés (az E13-R17 merge UTÁN újramérve):** a `4235f636` körrel új őr került a fába, ami szintén pinneli a kör képernyőit — `test/features/today/hub_navigation_test.dart` —, ezért az is felkerült mindkét listára és a §7 parancsba.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0.B — PRE-FLIGHT MÉRÉS, 2026-08-27 (`main @ 9ca4a0dc`, orchestrátor Claude Opus 5)

A §0.0 (batch, 2026-08-25) állításait a kör indítása előtt újramértem a fán.
Ami alább áll, az **erősebb** a §0.0-nál: ütközésnél a B-cella dönt.

**Visszakeresett előzmény (ADR 0312, szűkített korpusz):** [L06](../LESSONS.md)
(az elnyelt hiba néma no-op — a szinkron-szabály forrása),
[L517](../LESSONS.md#l517) (a `textScaler 2.0` keret két körben mért ki valódi,
addig láthatatlan túlcsordulást), [L465](../LESSONS.md#l465) (a képernyő-leltár
egzakt száma minden új `_screen.dart`-nál elmozdul),
[L397](../LESSONS.md#l397) (ugyanez CI-only leletként),
[L486](../LESSONS.md#l486) + [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
(a golden a RASZTERIZÁLÁST rögzíti; ARM-felvétel az x86 kapun mindig piros),
[ADR 0292](../adr/0292-model-activation-requires-verified-integrity.md) (a kör
normája — MÁR MERGE-ELVE).

### B1 — `lib/features/offline_ai/` a fán NEM létezik: EZT A KÖNYVTÁRAT EZ A KÖR HOZZA LÉTRE (`S13` feloldva)

Mérve: `ls lib/features/offline_ai` → *No such file or directory*; a
`lib/features/` valódi gyerekei között nincs `offline_ai`. A `brief-lint` `S13`
lelete pontosan ezt jelzi. **Feloldás:** az előtag a listán MARAD, mert a
modellkezelő felület ÚJ feature-fa, amit ez a kör hoz létre — nem tévedés és nem
tágítás. A másik három előtag (`lib/features/auth/`, `lib/features/settings/`,
`lib/features/share/`) a fán LÉTEZIK, mérve.

**A jogosultság az ÚJ fára szűk:** az `offline_ai` fa alá kizárólag a §3
modellkezelő rétege kerül. Más feature fájának érintése (a másik háromon kívül)
listán kívüli, tehát `stopped`.

### B2 — a kör ADR-t NEM ír: a 0292 MÁR MERGE-ELVE

Mérve: `docs/adr/0292-model-activation-requires-verified-integrity.md` létezik a
fán, a `5b32bd8e` („docs(ch13): E13-R30..R36 briefek + ADR 0288-0292") commitban,
2026-08-15-i dátummal, **elfogadva** státusszal. A brief fejlécének „a Claude
írja meg a kör indításakor" mondata tehát tárgytalan.

Következmény: a `docs/adr/` VÉGIG tilos zóna; a 0292 szövegének módosítása egy
merge-elt döntés átírása lenne, azaz **H1**. A §5 normái ebből az ADR-ből és a
[0279](../adr/0279-consequence-first-confirmations.md)-ből jönnek.

### B3 — §1.1/1. szabály (elérhetetlen cél-státusz): az A4 „újrapróbál" cellája FELHASZNÁLÓ-INDÍTOTTA, nem automatikus

Ez a kör legfontosabb mérése. Két tény a fán:

1. **A §5.2 szabálya MÁR TELJESÜL a szinkron-rétegben.** A
   `lib/features/settings/providers/settings_sync.dart` `_sendPatch` metódusa a
   `_syncedSignature`-t **kizárólag** a `case Success()` ágon írja
   (296–299. sor), a `Failure` ág csak naplóz és lejárt sessiont érvénytelenít.
   A kör tehát NEM a szinkron-protokollt javítja — az helyes —, hanem
   **láthatóvá teszi** az állapotát a felületen.
2. **Az automatikus újrapróbálás KIPINNELVE TILOS**, méghozzá a kör listáján
   KÍVÜL élő `test/features/settings/settings_sync_test.dart`-ban:
   - `'a transient 5xx is still attempted only once'` → `settings.updates.length == 1`,
     indoklás: *„settings updates must never be replayed automatically"* (588. sor);
   - `'a PERMANENT rejection (401/422) is NOT retried — no infinite loop'` →
     *„a permanent 4xx must be attempted exactly once, not retried"* (531. sor).

**Következmény — kötelező olvasat:** az A4 „a felület jelez és újrapróbál"
cellája **kizárólag felhasználó-indította** újrapróbálás (explicit „Újra"
akció), amely a MEGLÉVŐ, egyszeri push-úton megy végig. **Bármilyen időzítő,
backoff vagy automatikus replay bevezetése a `SettingsSync`-be a fenti két,
NEM szerkeszthető cellát pirosra váltja** — az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A `settings_sync_test.dart` ezért felkerült
a `gate_tests`-re (őrként, NEM az `allowed_paths`-ra).

**Amit a kör hozzáadhat:** a `SettingsSync` ma **semmilyen megfigyelhető
állapotot nem publikál** (minden mező privát, a provider `Provider<SettingsSync>`).
A felület állapotához additív, csak-olvasható állapot-közzététel (pl.
`synced | pending | failed`) megengedett a `lib/features/settings/providers/`
alatt — de a push/pull sorrend, a debounce, a revízió-őrök és a
„csak `Success` után szinkronizált" szabály **változatlanul marad**.

### B4 — a hat érintett képernyőnek NULLA design-system importja van: EZ a kör tényleges munkája

Mérve (`grep -c design_system`):

| Fájl | design-system referencia | l10n referencia | sor |
|---|---|---|---|
| `lib/features/auth/screens/login_screen.dart` | **0** | 11 | 163 |
| `lib/features/settings/screens/settings_screen.dart` | **0** | 42 | 459 |
| `lib/features/settings/screens/vision_privacy_screen.dart` | **0** | 23 | 181 |
| `lib/features/share/screens/share_preview_screen.dart` | **0** | 5 | 142 |
| `lib/features/share/screens/strum_reel_screen.dart` | **0** | 6 | 359 |
| `lib/features/share/screens/wrapped_preview_screen.dart` | **0** | 3 | 98 |

Az import **kizárólag** a `lib/core/design_system/public.dart` barrelen át
mehet. A `foundations/**` közvetlen importja **11 sértést** adott az E13-R16/F8-ban,
és a mércéje a `test/core/architecture_dependency_test.dart` — ami a `gate_tests`-en
van, tehát a kör SAJÁT kapujában bukik, nem a ~17 perces CI-ban.

Kész, felhasználható komponensek a barrelben (mérve a `public.dart`-ban):
`SsModelStatusCard`, `SsProvenanceBadge`, `SsStatusBadge`, `SsSwitchRow`,
`SsChoice`, `SsTextField`, `SsValidationSummary`, `SsConfirmationSheet`,
`SsFailureState`, `SsSection`, `SsContentCard`, `SsCard`, `SsEmptyState`.

### B5 — §1.1/2. szabály (erőforrás-tulajdonlás): a NAVIGÁCIÓT a router birtokolja, ami TILOS ZÓNA → az új képernyők `Navigator.push`-sal élnek

Mérve: `lib/app/routing/app_router.dart` és `app_route.dart` **nincs** az
`allowed_paths`-on, tehát új útvonal regisztrálása **H3** volna. A fán MÉRT,
merge-elt precedens viszont pontosan ezt kerüli meg:

- `lib/features/songs/screens/song_list_screen.dart:39`,
  `lib/features/library/screens/session_detail_screen.dart:126`,
  `lib/features/analyze/screens/analyze_screen.dart:299` →
  `Navigator.push(MaterialPageRoute(builder: (_) => SharePreviewScreen(...)))`;
- `lib/features/share/screens/share_preview_screen.dart:118` → ugyanígy a
  `StrumReelScreen`-re.

**Következmény:** az adatvédelmi központ és az offline-AI modellkezelő
belépőpontja a `settings_screen.dart`-ból `Navigator.push` +
`MaterialPageRoute`, útvonal-regisztráció NÉLKÜL. Útvonal-literál
(`.push('/...')`) **TILOS** — a `test/tooling/route_literal_guard_test.dart`
(`gate_tests`) minden `lib/**` fájlra méri; ha a kör GoRouter-navigációt
használ, az `AppRoutes` konstansain át tegye (`settings_screen.dart:297`:
`context.push(AppRoutes.login)` a MÉRT minta).

### B6 — az A5 valódi munka: a `VisionPrivacyScreen`-re MA NULLA navigáció mutat

Mérve: `grep -rn "VisionPrivacyScreen" lib/` → kizárólag a saját fájlja. A
képernyő ma **elérhetetlen** a futó appból (csak teszt éri el). Az A5 cellája
tehát nem „már megvan, csak migrálni kell": a `consent_center_test.dart`-nak a
`SettingsScreen`-ről INDULÓ, felső szintű elérési utat kell állítania (koppintás
a beállítások gyökeréről), nem a képernyő puszta létezését.

### B7 — `ui_inventory` bázisvonal = 94, és a kör ELMOZDÍTJA

Mérve: `test/ui/ui_inventory_test.dart:22` → `expect(first.screenPaths, hasLength(94))`.
A kör legalább két új `_screen.dart`-ot hoz (adatvédelmi központ, modellkezelő),
tehát a szám elmozdul. **A jogosultság PONTOSAN a szám emelése a tényleges
képernyőszámra**, a §0.0/R4 szerint, plusz — a merge-elt precedenst követve — a
kör indoklásának egy kommentsora és opcionálisan egy `contains(...)` cella az új
képernyőkre. A leltárteszt MINDEN más állítása (rendezettség, `test/` kizárás,
immutábilitás, a meglévő `contains` cellák) érintetlen marad. A
`tool/ui_inventory.dart` szabályának lazítása vagy képernyő-átnevezés a szám
elkerülésére **TILOS** — az a mérce meghamisítása.

### B8 — a golden-útvonal NEM kerül a lokális `gate_tests`-be; a felvétel x86-on megy (ADR 0426, L486, L516, L517)

A brief eredeti `gate_tests` tömbje és §7 sora tartalmazta a golden-útvonalat, a
§7 pedig `flutter test --update-goldens`-t írt elő — **mindkettő HIBÁS ezen a
boxon**. A box `aarch64`, a merge-kaput adó CI `ubuntu-latest` = `x86_64`, a
`LocalFileComparator` pedig nulla toleranciájú: minden ARM-on rögzített pixel a
kapun MINDIG piros (ADR 0426 §2–§3 mérése; az E13-R17 két vak javító kört, az
E13-R20 egy **H5 haltot** fizetett érte). Ezen felül a golden-lépés lokális
pirosa a szekvenciális `round-gate.sh`-t megállítaná az `architecture` /
`secrets` / `l10n` lépések ELŐTT, elrejtve a kör három utolsó mércéjét.

**Mindkettő JAVÍTVA:** a golden-útvonal kikerült a `gate_tests`-ből és a §7
gate-sorából; a rögzítés és az ellenőrzés `tools/golden-x86.sh record|check`
(§7). A golden-teszt fájlja és a PNG-k továbbra is a kör diffjében vannak
(`test/ui/goldens/` az `allowed_paths`-on).

**A mérce NEM lazul:** a golden-cellákat KETTŐ méri — lokálisan a kötelező
`tools/golden-x86.sh check`, a kapuban az exact-SHA `full-gate.yml` teljes
suite-ja —, mindkettő x86_64-en, változatlan komparátorral, a TELJES
golden-készlettel. A `textScaler 2.0` keret KÖTELEZŐ, és a felvétel közben
talált, akár a kör ELŐTTI elrendezési hibát **javítani** kell, nem bázisvonalként
rögzíteni ([L517](../LESSONS.md#l517)).

### B9 — a §0.0/R2 hét tesztje MIND létezik és a `gate_tests`-re is felkerült

Mérve: mind a hét fájl a fán van. Mivel a migráció ezeket pirosra váltaná, a kör
ráállíthatja őket az ÚJ widgetekre — de **a lefedett viselkedés gyengítése,
cella törlése vagy `skip`-je TILOS** (§0.0/R2 változatlan). Ezek most a
`gate_tests`-en is szerepelnek, hogy a lelet a kör SAJÁT kapujában jöjjön elő,
ne a ~17 perces CI-ban.

### B10 — az A6 alá NINCS meglévő domain: a modellkezelőnek VALÓDI ellenőrzést kell számolnia

Mérve: a fán nincs offline-AI modell-domain (`lib/features/offline_ai/` nem
létezik). Ami VAN és felhasználható:

- `lib/core/ml/vision_model_manifest.dart` — valódi sha256-számítás és
  -összevetés a manifest bejegyzés ellen (`_sha256Hex`, 263–267. sor: eltérésnél
  a bejegyzés **elutasított**), plusz `VisionModelStatus { active, deferred }`;
- a design-system `SsModelStatusCard` / `SsProvenanceBadge` / `SsStatusBadge`.

A `lib/core/ml/**` a listán KÍVÜL van: olvasható és importálható, **nem
szerkeszthető**. Az `offline_ai` domainje mögött **tényleges**
ellenőrzőösszeg-összevetésnek kell állnia (a projekt szabálya: a mag-funkciót
mockolni tilos, a mock csak teszt-infrastruktúra) — a hármas cella (küszöb
alatt / rajta / fölött, §6.1) csak így mérhető.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-48 és UI-62–UI-65 rendszerfelületeinek egységes, **biztonságos**
implementációja (SDD Ch13 Kör 35).

## 2. Jelenlegi állapot — mért tények

- A fiók **opcionális**: a felismerés végig on-device, az app kijelentkezve is
  teljes (CLAUDE.md).
- A projekt **mérte**, hogy a felhő-írást elnyelő `try/catch` néma no-opot ad,
  és hogy a szinkronizált jelölés csak szerver-megerősítés után helyes.
- Az offline AI-modell letölthető bináris — az aktiválás bizalmi döntés.

## 3. Scope

**Benne van:** a bejelentkezés/regisztráció **opcionális** fiókkal és biztonságos
hibamegjelenítéssel · a beállítások kategória / lista-részlet szerkezete és
keresése · az Adatvédelmi és hozzájárulási központ (leltár, export, törlés,
szabályzat-állapotok) · az offline AI modellkezelő letöltés / ellenőrzés /
aktiválás / visszaállítás / tárhely állapotokkal · a megosztás-előnézet
redakcióval, formátummal és közönséggel · tárolási/hálózati hiba,
újraindítás-igény, kevés tárhely, ellenőrzőösszeg-hiba, export/törlés feladat és
offline sor.

**NINCS benne (tilos):** a hitelesítési vagy a szinkron-protokoll módosítása ·
az ellenőrzés nélküli modell-aktiválás engedélyezése · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/auth/` | bejelentkezés/regisztráció |
| `lib/features/settings/` | beállítások + adatvédelem |
| `lib/features/offline_ai/` | modellkezelő — **ÚJ fa, ezt a kör hozza létre** (§0.0.B/B1) |
| `lib/features/share/` | megosztás-előnézet |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a rendszer-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (7 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/settings/*_test.dart` (5) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r35-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a négy érintett KIVÉTELÉVEL ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0292)

### 5.1 A modell ELLENŐRZÉS NÉLKÜL nem aktiválható

Letöltött bináris aláírás/ellenőrzőösszeg igazolása nélkül nem lép működésbe.
Hibás ellenőrzés esetén a felület **nem kínál** „aktiváld mégis" utat.

**NEM elfogadható gyengítés:** figyelmeztetés melletti aktiválás „a
felhasználó döntsön". Egy hamisított modell mindent lát, amit a mikrofon.

### 5.2 A beállítás CSAK szerver-megerősítés után jelölhető szinkronizáltnak

A projekt mért tanulsága. Sikertelen írás után a felület jelzi a
függőben lévő állapotot és a felhasználó **explicit akcióval** újrapróbálhatja
— nem tesz úgy, mintha mentve lenne. **Automatikus replay/backoff bevezetése
TILOS** (§0.0.B/B3: a `settings_sync_test.dart` két, NEM szerkeszthető cellája
pinneli, hogy egy bukott írás pontosan egyszer megy ki).

**NEM elfogadható gyengítés:** `try { push() } catch (_) {}` és optimista
„Mentve" felirat. Ez néma szerkesztés-vesztés.

### 5.3 Az adatvédelem NEM rejtett

A leltár, az export és a törlés a beállítások felső szintjéről elérhető, nem
három menü mélyen.

### 5.4 A fiók nélküli kilépés ELÉRHETŐ

A bejelentkezési képernyőről mindig van út „fiók nélkül tovább" irányba.

### 5.5 A megosztás alapból MINIMÁLIS adatot visz

A redakció az alapállapot; a felhasználó **bővíti**, nem szűkíti. A felület
tételesen mutatja, mi kerül ki.

### 5.6 A destruktív adatművelet EXPLICIT és auditálható

Export és törlés feladatként jelenik meg, állapottal és eredménnyel — az
ADR 0279 következmény-központú megerősítésével.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A bejelentkezésből elérhető a „fiók nélkül tovább" út | `auth_states_test.dart` |
| A2 | A hitelesítési hiba nem szivárogtat technikai részletet | ugyanott |
| A3 | A beállítás csak szerver-megerősítés után jelölt szinkronizáltnak | `settings_persistence_failure_test.dart` |
| A4 | Sikertelen mentés után a felület **függő** állapotot jelez, és a felhasználó **explicit akcióval** újrapróbálhatja (automatikus replay TILOS — §0.0.B/B3) | ugyanott + a NEM szerkeszthető `settings_sync_test.dart` őrcellái |
| A5 | Az adatvédelmi központ a felső szintről elérhető | `consent_center_test.dart` |
| A6 | Ellenőrzőösszeg-hiba esetén a modell NEM aktiválható | `model_integrity_test.dart` |
| A7 | A megosztás alapból minimális adatot visz, tételesen felsorolva | `share_redaction_test.dart` |
| A8 | Az export/törlés explicit, állapottal és eredménnyel | `consent_center_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r35_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Aktiváld mégis" gomb hibás ellenőrzőösszegnél | **A6** |
| `try/catch` + optimista „Mentve" | **A3** + A4 |
| Az adatvédelem három menü mélyen | A5 |
| A bejelentkezés kötelező | **A1** |
| A megosztás alapból mindent visz | **A7** |
| Nyers hibaüzenet a bejelentkezésnél | A2 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A modell-aktiválás három kötelező cellája** (a küszöb: az integritás
igazolása):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | hiányzó vagy hibás ellenőrzőösszeg | **nem aktiválható** — nincs megkerülő út |
| rajta (a küszöbön) | **érvényes ellenőrzőösszeg, ismert forrás** | aktiválható |
| a küszöb fölött | érvényes ellenőrzőösszeg + korábbi működő verzió | aktiválható, **visszaállítási** úttal |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedélyezd az
aktiválást hibás ellenőrzőösszeg mellett → az **A6** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/settings/auth_states_test.dart test/features/settings/settings_persistence_failure_test.dart test/features/settings/consent_center_test.dart test/features/settings/model_integrity_test.dart test/features/settings/share_redaction_test.dart test/features/settings/settings_sync_test.dart test/features/settings/settings_account_test.dart test/features/settings/vision_privacy_screen_test.dart test/features/settings/lab_mode_toggle_test.dart test/features/share/share_preview_test.dart test/features/share/strum_card_test.dart test/features/share/strum_reel_test.dart test/features/share/wrapped_test.dart test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/features/share/reel_meter_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart test/features/today/hub_navigation_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/ui/goldens/e13_r34_screens_golden_test.dart`
(merge-elt, valódi kapu, nem `skip`-elt rögzítő).

**Előállítás és ellenőrzés — KIZÁRÓLAG x86-on** (§0.0.B/B8,
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)); a
`flutter test --update-goldens` ezen az `aarch64` boxon TILOS, mert az ott
rögzített pixel az x86-os merge-kapun MINDIG piros:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r35_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r35_screens_golden_test.dart
```

A `check` kilépési kódja: `0` = egyezik, `10` = valódi golden-eltérés (javítandó,
NEM újrarögzítendő bázisvonal), `20` = környezeti hiba (jelentsd, ne kerüld meg).

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör hitelesítést, adatvédelmet és modell-
> aktiválást érint, ezért a review-ban a `security-reviewer` ügynök futtatása
> kötelező.

## 8. Implementációs sorrend

1. A bejelentkezés/regisztráció, „fiók nélkül tovább" úttal és redaktált hibával.
2. A beállítások szerkezete + a szinkron-állapot **megerősítés után**.
3. A sikertelen mentés jelzése és újrapróbálása.
4. Az adatvédelmi központ (leltár, export, törlés) felső szintű belépéssel.
5. Az offline AI modellkezelő + a három integritás-cella.
6. A megosztás-előnézet minimális alapadattal, tételes felsorolással.
7. A valódi-sértés próba, §10-be dokumentálva.
8. A golden-felvétel `tools/golden-x86.sh record`-dal, majd `check` (§7, §0.0.B/B8).
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az elnyelt szinkron-hiba.** A projekt már mérte: a felület „Mentve"-t
  mutat, az adat elveszik (A3/A4).
- **A megkerülhető modell-ellenőrzés.** A „felhasználó döntsön" érv itt a
  mikrofon teljes tartalmát teszi kockára (A6).
- **A bővítő megosztás.** Ha az alapállapot a teljes adat, a redakció
  elfelejthető — az alapérték a védelem (A7).

## 10. Implementation handoff — az implementer tölti ki

**Ez a kör két résztben futott** (abszolút időkorlát miatt): az első rész
(`8e261b53`, `e2014c4f`, `f3541338`) építette fel a képernyőket és a
tesztgyűjteményt; ez a folytatás rögzítette a goldeneket, futtatta a
valódi-sértés próbát, és — a golden-felvétel közben talált — egy pluszban
mért, valódi textScaler-2.0 túlcsordulást javított.

### Képernyőnkénti összefoglaló

| Fájl | Mit épít |
|---|---|
| `lib/features/auth/screens/login_screen.dart` | bejelentkezés/regisztráció, „fiók nélkül tovább" úttal, redaktált hitelesítési hibaüzenettel |
| `lib/features/settings/screens/settings_screen.dart` | kategória/lista-részlet szerkezet + a szinkron-állapot sáv (`SettingsSyncStatus.synced\|pending\|failed`) + felhasználó-indított Retry |
| `lib/features/settings/screens/privacy_center_screen.dart` | **ÚJ képernyő** — adatvédelmi/hozzájárulási központ (leltár, export, törlés, szabályzat-állapotok), a beállítások felső szintjéről elérhető |
| `lib/features/settings/screens/vision_privacy_screen.dart` | a kamerás funkció adatvédelmi állapotai |
| `lib/features/offline_ai/screens/model_manager_screen.dart` | **ÚJ képernyő, ÚJ feature-fa** — offline AI modellkezelő: letöltés/ellenőrzés/aktiválás/visszaállítás/tárhely állapotokkal |
| `lib/features/share/screens/share_preview_screen.dart` | megosztás-előnézet, tételes redakció-összegzővel, formátum- és közönség-választással |

### Acceptance cellák → mérő teszt (fájl + teszt-név)

| # | Bizonyíték |
|---|---|
| A1 | `test/features/settings/auth_states_test.dart` — a „fiók nélkül tovább" út létezik és navigál |
| A2 | ugyanott — a hitelesítési hiba redaktált, technikai részlet nem szivárog |
| A3 | `test/features/settings/settings_persistence_failure_test.dart` — `'A3 — while a save is in flight the screen shows "Saving…", not "saved"'` + az A3/A4 közös cella |
| A4 | ugyanott — `'A3/A4 — a failed save shows a pending state, not "saved", and a Retry action sends exactly one more attempt through the existing push path'`: 1 push → hiba → `settingsSyncRetry` gomb → pontosan 1 ÚJ push (összesen 2, nem több) — **plusz** a NEM szerkeszthető `settings_sync_test.dart` két őrcellája (588. és 531. sor), amelyek azt pinnelik, hogy sem az átmeneti 5xx, sem a végleges 4xx nem ismétlődik automatikusan |
| A5 | `test/features/settings/consent_center_test.dart` — a `PrivacyCenterScreen` a beállítások felső szintjéről (nem 3 menü mélyen) elérhető |
| A6 | `test/features/settings/model_integrity_test.dart` — a három §6.1 cella (`OfflineModelController` egység-szinten + `ModelManagerScreen` widget-szinten) — **lásd a valódi-sértés próbát alább** |
| A7 | `test/features/settings/share_redaction_test.dart` — alapból a cím NEM kerül ki, csak explicit bekapcsolás után (`shareIncludeTitleToggle`), soha nem fordítva |
| A8 | `test/features/settings/consent_center_test.dart` — export/törlés feladatként, állapottal és eredménnyel |
| A9 | `test/ui/goldens/e13_r35_screens_golden_test.dart` + `test/ui/goldens/goldens/e13_r35_*.png` (10 kép: 5 képernyő × {compact, compact_scale2}) |

### A valódi-sértés próba (A6, KÖTELEZŐ, §6.1) — MÉRT kimenet

Helyszín: `lib/features/offline_ai/providers/offline_model_controller.dart`,
`activate()` metódus. Ideiglenesen `if (false && !verification.verified)`-re
cserélve a `if (!verification.verified)` gate-et (a kikapcsolt ág soha nem fut
le), majd lefuttatva:

```
flutter test test/features/settings/model_integrity_test.dart
```

**MÉRT: 10-ből 3 cella PIROSRA váltott** (baseline 10/10 zöld):

- `OfflineModelController — … below threshold: a bad checksum blocks
  activation, active stays null` → `Expected: blockedIntegrity, Actual: active`
- `OfflineModelController — … a bad candidate NEVER overwrites a good,
  already-active version` → `Expected: blockedIntegrity, Actual:
  activeWithRollback`
- `ModelManagerScreen — … below threshold: NO activation control is rendered
  at all` → a „Not activated — checksum could not be verified" szöveg el sem
  jelent meg (a hibás modell simán aktiválódott)

A gate visszaállítva (`git diff` üres volt a visszaállítás után), a teszt
újrafuttatva: **10/10 zöld**.

### A golden-felvétel közben talált, ÉS EBBEN A KÖRBEN JAVÍTOTT hiba (L517)

Az első felvételi kísérlet (a folytatás előtti kör commitolatlan állapotában)
két, egymást követő valódi túlcsordulást fogott ki `compact_scale2`
(textScaler 2.0) keretben, mindkettőt a `share_preview` képernyőn:

1. **`SharePreviewScreen` külső `Column`-ja** — a rögzített `Expanded` kártya-
   terület + a redakció-összegző + a gombok együtt magasabbak voltak, mint a
   rendelkezésre álló magasság 2.0 szövegskálázásnál. Javítás: a törzs
   `SingleChildScrollView`-vá vált, a kártyaterület `LayoutBuilder`-ből mért
   arányra (`maxHeight * 0.55`) és a `StrumCard` natív 9:16 arányára
   (`AspectRatio`) korlátozva — így soha nem szorítja ki magát a maradék
   terület alapján, hanem a törzs görget, ha kell.
2. **`StrumCard` (a megosztott grafika) belső `Column`/`Row`-jai** — miután az
   1. javítás valódi helyet adott a kártyának, kiderült, hogy maga a kártya
   (rögzített 360×640 pixel, exportált grafika) is öröklte az ambiens
   `textScaler`-t, és 2.0-nál túlcsordult a saját dobozán belül. **Ez egy a
   körön KÍVÜLI, korábban rejtett, éles hiba**: bármely felhasználó, akinek a
   rendszerén nagy betűméret van beállítva, a megosztott képen csonkolt/
   túlcsorduló kártyát kapott volna. Javítás: a `StrumCard.build()`
   `MediaQuery(data: …copyWith(textScaler: TextScaler.noScaling), …)`-be lett
   csomagolva — a kártya egy rögzített pixelméretű, exportált grafika, nem
   olvasási felület, ezért az akadálymentesítési szövegskálázás soha nem
   érintheti.

Mindkettő a §0.0.B/B8 normája szerint JAVÍTVA lett, nem bázisvonalként
rögzítve. Az érintett widget-tesztek (`test/features/share/share_preview_test.dart`,
`test/features/settings/share_redaction_test.dart`) egy `tester.ensureVisible(...)`
hívást kaptak a „Share as text" tap elé, mert a törzs görgethetővé vált — ez
NEM gyengítés, a mért állítások (log-tartalom, widget-jelenlét) változatlanok.

### `ui_inventory` — 94 → 96, miért pontosan ennyi

Két ÚJ `_screen.dart` került a fába ebben a körben:
`lib/features/offline_ai/screens/model_manager_screen.dart` és
`lib/features/settings/screens/privacy_center_screen.dart` (mérve:
`git log --diff-filter=A -- '*_screen.dart'` a kör commitjain). A
`test/ui/ui_inventory_test.dart` `hasLength(94)` → `hasLength(96)`-ra emelve,
más állítás érintetlen.

### Golden-felvétel módja

`tools/golden-x86.sh record test/ui/goldens/e13_r35_screens_golden_test.dart`,
majd `tools/golden-x86.sh check` ugyanarra az útvonalra — mindkettő x86_64
docker/qemu-emulációval, a CI-val azonos Flutter-verzióval (ADR 0426). Mindkét
parancs `0` kilépési kóddal futott le (felvétel: 10/10 teszt zöld; ellenőrzés:
10/10 teszt zöld, nulla eltérés). 5 képernyő × 2 keret (412×915 compact és
ugyanaz textScaler 2.0) = 10 PNG, mind commitolva.

### Amit ez a kör NEM csinált, és miért

- **Nem módosította a hitelesítési vagy szinkron-protokollt** — a §5.2 szabály
  már teljesült a `_sendPatch`-ben (B3); a kör csak megfigyelhető státuszt
  (`SettingsSyncStatus`) tett hozzá és egy felhasználó-indított Retry akciót.
- **Nem vezetett be automatikus replay/backoff-ot** — a `settings_sync_test.dart`
  két, listán kívüli cellája ezt tiltja (B3); a Retry mindig explicit
  felhasználói tap.
- **Nem nyúlt a `lib/core/ml/vision_model_manifest.dart`-hoz** — az A6 mögötti
  valódi sha256-ellenőrzés innen származik (B10), a fájl csak importálva lett.
- **Nem vett fel golden-t minden állapotra** (pl. hiba-, letöltés-közbeni
  állapotok) — a §7 kifejezetten csak a §3 szerinti alap-nézetet írja elő a
  két kerettel, ez teljesült.

## 10.1 Javító kör 1 (2026-08-27, `sonnet-impl`) — a review 7 MAJOR-jának javítása

A review (`docs/reviews/e13-r35-review.md`) 6 MAJOR-t (F1–F6) és 3 MINOR-t
(s1, s4, m1) talált, mindegyiket futtatott próbateszttel reprodukálva. Alább
leletenként: mi változott, MELYIK cella fogja meg, és mi a mért kimenet.

### F1 — az A6 UI-oldali őrcellája most a MŰKÖDÉSRE mér, nem widget-típusra

`test/features/settings/model_integrity_test.dart` „below threshold: NO
activation control…" cellája eddig kizárólag `FilledButton`/`OutlinedButton`
hiányát nézte — egy `SsButtonVariant.tertiary` (→ `TextButton`) bypass simán
átment volna rajta. A cella most a `modelManagerBlockedIntegrity` kulcsú
terület ALÁ scope-olva keres BÁRMILYEN `ButtonStyleButton`-t (ez lefedi
Filled/Outlined/Text/Elevated — azaz minden `SsButton`-variánst), `InkWell`-t
és `GestureDetector`-t.

**A §6.1/§10 kötelező valódi-sértés próba (UI-tengely), TÉNYLEGESEN
lefuttatva:** `model_manager_screen.dart` blockedIntegrity ágába ideiglenesen
egy `SsButton(variant: tertiary, label: 'Activate anyway')` került, majd
`flutter test test/features/settings/model_integrity_test.dart`:

```
00:01 +9 -1: … below threshold: NO activation control is rendered at all — not disabled, absent [E]
  Expected: no matching candidates
  Actual: _DescendantWidgetFinder:<Found 1 widget with widget matching predicate
  descending from widget with key [<'modelManagerBlockedIntegrity'>]: [ TextButton(...) ]>
```

A cella PIROSRA váltott, ahogy a §6.1 előírja. A gate visszaállítva
(`git diff` üres a bypass-gomb törlése után), a teszt újrafuttatva: **12/12
zöld** (a 9 eredeti cella + az F1 megerősítő cella + a két F5-cella).

### F2 — a szinkron-státusz a TÉNYLEGES gépezetből származik, nem él-publikálásból

`lib/features/settings/providers/settings_sync.dart`: az eddigi szórt
`_publishStatus(SettingsSyncStatus.xxx)` hívásokat egyetlen `_computeStatus()`
váltotta fel — `pending`, ha van repülő VAGY függő push; különben `failed`,
ha az aktuális aláírás még eltér a szervertől megerősítettől ÉS az utolsó
kísérlet bukott (`_lastPushFailed`); egyébként `synced`. A publikálás
(`_republishStatus`) továbbra is `Future.microtask`-ban fut (reentrancy),
de MOST a mikrotaszk BELSEJÉBEN hívja `_computeStatus()`-t, a tényleges,
akkor-aktuális mezőkből — nem a hívás pillanatában befagyasztott értékből.
Ez zárja az S2-t (egy korábbi push `Success`-e már nem írhatja felül egy
később még repülő push státuszát, mert `_pushInFlight` a ciklus végéig
igaz marad) ÉS az M2-t (`_onLocalChange` korai visszatérési ága most is
hív `_republishStatus()`-t, tehát egy debounce-ablakon belüli visszaállítás
korrekt `synced`-reold fel, nem ragad `pending`-en).

**Cella:** `test/features/settings/settings_sync_test.dart` (nem
szerkeszthető, mind a 20 cella zöld maradt — a push/pull mechanika
változatlan) + az ÚJ F6-cella (lásd alább), ami VALÓS in-flight méréssel
bizonyítja az S2/M2 javítást.

### F3 — a Privacy Center felirata most a TÉNYLEGES hatókört mondja

`privacy_center_screen.dart` export/delete-all feliratai és az `en`/`hu`
`base` ARB-ok: „Export my data"/„Delete all my data" → „Export my Vision
data"/„Delete all my Vision data" (a `VisionPrivacyScreen` testvér-mintáját
követve). A törlés-megerősítés szövege explicit kimondja, hogy a könyvtár,
dalok és gyakorlási előzmény NEM érintett.

**Cella:** `test/features/settings/consent_center_test.dart` ÚJ cellája —
„F3 — 'delete all my Vision data' leaves non-Vision storage untouched" —
egy nem-vision kulcsba (`StorageKeys.songs`) ír egy értéket a törlés előtt,
majd bizonyítja, hogy a törlés UTÁN is megvan. Ez a cella pirosra váltana,
ha valaki a törlést a teljes `StorageKeys.all`-ra bővítené anélkül, hogy a
kör `allowed_paths`-a ezt engedné.

### F4 — a „fiók nélkül tovább" a `go()`-belépésű úton is elhagyja a képernyőt

`login_screen.dart`: a `Navigator.of(context).maybePop()` most `await`-elt,
és ha `false`-t ad vissza (nincs mit popolni — a `profile_hub_screen.dart`
`context.go(AppRoutes.login)`-ja pontosan ezt idézi elő), a képernyő
`context.go(AppRoutes.profileHome)`-ra esik vissza. Útvonal-literál nem
került a kódba (`route_literal_guard` zöld).

**Cella:** `test/features/settings/auth_states_test.dart` ÚJ cellája —
„on the go()-entry path… via a real router" — egy VALÓDI, minimális
`GoRouter`-t épít (profileHome → login, pontosan a mért produkciós minta),
és bizonyítja, hogy a „Continue without an account" tap után a
`LoginScreen` eltűnik és a location NEM `/login`. A plain-`Navigator`
harness-szel élő két meglévő cella (push-úton) változatlanul zöld.

### F5 — a beszerzési hiba (`fetchFailed`) különvált a valódi ellenőrzőösszeg-eltéréstől

`offline_model.dart`: új `OfflineModelPhase.fetchFailed` érték. A
`checkAndActivate` `Failure()` ága most ide megy (NEM `blockedIntegrity`-be)
— a `blockedIntegrity` mostantól KIZÁRÓLAG az `activate()` valódi
checksum-összevetéséből érhető el. `model_manager_screen.dart`-ban a
`fetchFailed` a normál (Check gombos) ágba esik, saját, nem-riasztó
szöveggel (`modelManagerStatusFetchFailed`); a `blockedIntegrity` gomb
nélküli, riasztó ága VÁLTOZATLAN.

**Cella:** `model_integrity_test.dart` két ÚJ cellája — unit-szinten
(`fetchFailed` fázis, `isNot(blockedIntegrity)`) és widget-szinten (a
riasztó szöveg és a `modelManagerBlockedIntegrity` terület ABSZENS, a
`modelManagerCheck` gomb `onPressed` NEM null).

### F6 — az A3 in-flight cellája MOST valódi in-flight állapotot mér

`settings_persistence_failure_test.dart`: a `FakeSettingsRepository`
(`test/support/`, a kör `allowed_paths`-án KÍVÜL) `update()`-je mindig
szinkron zár le — sosem volt in-flight ablak, amit mérni lehetett volna. A
fájlban (engedélyezett) most egy helyi `_DelayedUpdateRepository` blokkol
egy `Completer`-en, amíg a teszt fel nem oldja. A cella: szerkesztés →
`tester.pumpAndSettle()` (ami elsüti a nulla debounce-Timert és elindítja a
pusht, de NEM várja meg a blokkolt `update()`-et, mert a Scheduler nem lát
további ütemezett frame-et) → `settings.updateStarted.isCompleted` igaz ÉS
„Saving…" látszik ÉS „All changes saved" NEM látszik → `releaseUpdate`
feloldása → „All changes saved" megjelenik. Ez a cella az F2 javítás
VALÓDI bizonyítéka (korábban ez a cella épp az ellenkezőjét állította, és
ez engedte át az S2-t).

**Megjegyzés (mért, nem javítás):** az első implementációs kísérlet a
`Completer.future`-t `tester.pump()` nélkül `await`-elte — mivel az
`AutomatedTestWidgetsFlutterBinding`-ben a nulla-időtartamú `Timer` csak
pumpolásra süt el, ez valódi holtpontot okozott (mért: 1166948 pid, 0.3%
CPU, 9+ perc mozdulatlanság). A végleges változat a bizonyítottan működő
`pumpAndSettle()`-mintát követi (ugyanaz, mint a fájl első cellájában).

### s1 — a redakció-lista most tételesen felsorolja a löketszámot és a hosszt is

`share_preview_screen.dart` `_RedactionSummary`-je két új tétellel bővült
(`shareRedactionStrokeCounts`, `shareRedactionDuration`) — a `StrumCard`
mindig kiviszi a le/fel löketszámot és a session hosszát (`_stats()`), ezt
a lista eddig nem nevezte meg. **Mellékhatás:** a két új sor lejjebb tolta a
cím-opt-in kapcsolót és a „Share card"/„Share as text" gombokat a kis
teszt-viewportban — a `share_redaction_test.dart` és a `share_preview_test.dart`
(mindkettő a kör §0.0/R2 listáján) érintett tap-jai elé egy-egy
`tester.ensureVisible(...)` került, ugyanúgy, ahogy a meglévő A9-görgetési
javítás már tette a „Share as text" gombnál. A mért állítások (mit naplóz a
fake share service, milyen szöveg jelenik meg) VÁLTOZATLANOK.

**Cella:** `share_redaction_test.dart` „the always-shared core is itemized
on screen" — két új `expect` a fenti szövegekre.

### s4 — TUDATOSAN KIHAGYVA ebben a körben

A `wrapped_preview_screen.dart` / `strum_reel_screen.dart` heti perc/
sorozat/pontosság adata valóban opt-in és tételes lista nélkül megy ki, DE
a javítás — egy teljes redakció-összegző UI + opt-in kapcsoló mindkét
képernyőn, a `ShareContent.wrappedCaption`/a reel megosztási útjának
feltételes meződivatlanítása, plusz az ehhez tartozó widget-tesztek — egy
önálló funkció méretű munka, nem egy sornyi felirat-igazítás. A brief §2
MINOR szakasza kifejezetten megengedi a kihagyást, ha a javítás
„aránytalanul hizlalná a diffet" — ez itt a hat MAJOR + s1 + m1 melletti
HETEDIK jelentős funkcionális változtatás lenne. Következő SDD-körre
javasolt, nem ennek a javító körnek a hatókörébe.

### m1 — a Privacy Center export-dialógusa most kimondja, hogy pillanatkép, nem fájl

`privacy_center_screen.dart`: az export-dialógus tartalma egy új
`privacyCenterExportSnapshotNote` sorral bővült a JSON felett — „This is a
viewable snapshot, not a saved file…" — mert a dialógus valójában sosem ír
fájlt, csak megjeleníti a JSON-t.

**Cella:** `consent_center_test.dart` A8 export-cellájának új `expect`-je a
fenti szövegre.

### A gate + a golden újrafelvétele — mért kimenet

A §7 teljes gate (29 lépés — format, analyze, 23 célteszt, architecture,
secrets, l10n) **MIND ZÖLD** (`tools/round-gate.sh` teljes futása, csonkítás
nélkül). Az `analyze` lépés útközben egy `use_build_context_synchronously`
lintet jelzett az F4 új metódusán (`context.mounted` helyett `mounted`-re
javítva — `State.context`-hez a State saját `mounted`-je a helyes őr); a
javítás után az `analyze` is zöld.

A privacy_center és a share_preview képernyő ELRENDEZÉSE/szövege
megváltozott (F3 felirat, s1 két új tétel), ezért a goldenek újrafelvétele
KÖTELEZŐ volt (§0.0.B/B8): `tools/golden-x86.sh record` →
`test/ui/goldens/e13_r35_screens_golden_test.dart`, **10/10 zöld**; utána
`tools/golden-x86.sh check` ugyanarra, **10/10 zöld, nulla eltérés**. 3 PNG
változott ténylegesen: `e13_r35_privacy_center_compact.png`,
`e13_r35_share_preview_compact.png`, `e13_r35_share_preview_compact_scale2.png`
(a `privacy_center_compact_scale2` és a `login`/`settings`/`model_manager`
mind a 4 kerete pixel-azonos maradt — ezeket a kör nem érintette).

## 11. Review — a Claude tölti ki
