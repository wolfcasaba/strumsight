# E16-R05 — A teljes app működésének mérése és kiadható build

- **Státusz:** IN PROGRESS (előre megírva 2026-09-02 a `main @ 11d0d2bb` fán; **pre-flight mérve 2026-09-04, `main @ d0575edd`** — a §0.0.1 hét mért revíziót ír)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 5 — a sáv ZÁRÓ köre
- **Kör-azonosító:** `E16-R05`
- **Branch:** `<motor>/e16-r05-full-app-verification-and-release`
- **Előfeltétel:** `E16-R04` merge-elve (és a Chapter 15 lezárva)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — záró/mérési kör.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "end to end verification release evidence apk full app"` → az `E15-R13` záró mintája és **[ADR 0053](../adr/0053-ci-full-test-suite.md)** (a teljes suite + property gate + APK a CI-ban fut). A kör ezt a mércét alkalmazza a TELJES appra.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd a `dart run tool/check_screen_reachability.dart --format table` és a migrációs mérést; olvasd be a `docs/release/capability-rollout.md` (E16-R03) besorolásait. A §6 cellái EZEKRE a MÉRT halmazokra épülnek, nem az itt írt számokra.

## 0.0 Mit állít ez a kör, és mit nem

Azt állítja: minden ELÉRHETŐ képernyő valós adatot kap vagy explicit üres állapotot mutat; a „BE" besorolású capabilityk a core úton működnek; és mindez egy telepíthető buildben látszik. Azt NEM állítja, hogy minden capability GA-kész (azt a Chapter 12 Kör 28 dönti el), és nem méri a felismerés pontosságát (az a Chapter 14 sáv tárgya).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/e2e/full_app_walkthrough_test.dart",
  "tool/check_placeholder_wiring.dart",
  "test/tooling/placeholder_wiring_test.dart",
  "test/support/e2e_harness.dart",
  "docs/release/full-app-verification.md",
  "docs/rounds/e16-r05-full-app-verification-and-release.md",
]
gate_tests = [
  "test/e2e/full_app_walkthrough_test.dart",
  "test/tooling/placeholder_wiring_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/tooling/screen_reachability_test.dart",
  "test/e2e/first_practice_offline_test.dart",
  "test/e2e/returning_user_restart_test.dart",
  "test/accessibility/release_flow_semantics_test.dart",
  "test/accessibility/release_flow_text_scale_test.dart",
]
native_gate = true
```

## 0.0.1 Módosítás (pre-flight, 2026-09-04, `main @ d0575edd`) — hét mért revízió

Az előre megírt brief a `main @ 11d0d2bb` fán készült. A pre-flight minden
hivatkozott halmazt, mezőt és sorszámot kimért; ahol a törzs mást mond, **ez a
szakasz az erősebb**. Egy cellát sem töröltünk és egyet sem lazítottunk — a
revízió kettőt SZIGORÍT (R3, R4) és egyet a mérhetőség feltételeként pótol (R2).

**Visszakeresés (ADR 0312, kötelező).** Szűkítve:
`--corpus lessons,halts,adr --top 5 "end to end walkthrough teljes app bejárás
placeholder mérés záró kör"` → **[L606](../LESSONS.md#l606)** (E16-R02 H3: *„a
kész felület bekötése előtt a FORRÁST kell mérni: az üres katalógus és a zöld
kapu megkülönböztethetetlen"*) és **[L558](../LESSONS.md#l558)** (a
`flutter_test` 800×600-as viewportja akár ÜRES fát is mérhet). Mindkettő
ugyanazt a hibaosztályt írja le, amit ez a kör MÉR: a **vákuum-cella** — egy
zöld mérce, ami valójában nulla dolgot néz. Ezért kapott az A1 egy kimondott,
nem üres kivétel-listát (R3) és a mérő egy fájlhalmaz-küszöböt (A7), a §6.1
valódi-sértés próbája pedig KÖTELEZŐ marad.

### R1 — a kör ADR-t NEM foglal, és a `docs/adr/**` tiltott marad

A pipeline-prompt sablonszövege szerint az „`Előre kiosztott ADR: nincs`" azt
jelenti, hogy a pre-flight ír egyet. Ez a kör **mérlegelve nem ír**: nem hoz
architekturális döntést, a mérce-szerződését az §5.3–5.5 és a szállított
`docs/release/full-app-verification.md` hordozza.

| Mért parancs | Eredmény |
|---|---|
| `awk -F'\t' '$4=="nincs" && $5=="done"' docs/execution/pipeline-queue.tsv \| wc -l` | **165** merge-elt kör ADR nélkül |
| ugyanez, `$1` kiírva | köztük az **`E15-R13`** (`ui-closure-and-release-evidence`) — pontosan az a záró-kör precedens, amit a fejléc visszakeresése is idéz |
| `grep -n "^E16-R05" docs/execution/pipeline-queue.tsv` | a sor ADR-oszlopa `nincs` |

`tools/round-slots.py reserve-adr` tehát **szándékosan nem futott**; a §3 tiltó
listája (`docs/adr/**`) változatlan.

### R2 — BLOKKOLÓ: az A3 a mai harness-szel MÉRHETETLEN, mert az öt BE-flagből ötöt kikapcsolva bootol

Az A3 a **„BE" besorolású** capabilityk core útjait kéri. A besorolás forrása a
`docs/release/capability-rollout.md` (E16-R03) — a BE halmaz nyolc eleme:
`diagnosticsEnabled`, `labModeAvailable`, `practiceEngineV2Enabled`,
`migratedLearnEnabled`, `practiceDetailedHistoryEnabled`,
`songTrainerV2Enabled`, `practiceGeneratorEnabled`, `adaptiveShellEnabled`.

| Mért parancs | Eredmény |
|---|---|
| `awk '/factory FeatureFlags.forEnvironment/,/^  );$/' lib/app/config/feature_flags.dart` | a `nonProd` ág PONTOSAN ezt a nyolc mezőt állítja `true`-ra (`feature_flags.dart:77–139`), minden más `false` (a Community öt flagje `bool.fromEnvironment` → dart-define nélkül `false`) |
| `grep -n "flags: const FeatureFlags" -A6 test/support/e2e_harness.dart` | a harness privát `_e2eConfig()`-ja **négy** mezőt ad meg: `accountEnabled:false, diagnosticsEnabled:false, labModeAvailable:false, practiceEngineV2Enabled:true` → a BE nyolcból **öt KI** (`adaptiveShell`, `practiceGenerator`, `songTrainerV2`, `migratedLearn`, `practiceDetailedHistory`) |
| `grep -n "bootE2eApp(" test/support/e2e_harness.dart` | a `bootE2eApp` szignatúrájában **nincs** flag-paraméter, a `_e2eConfig()` privát → a §3 bejárása a mai felületen nem konfigurálható |
| `sed -n '178,190p' lib/app/routing/app_router.dart` | a router `practiceEnabled` = `practiceEngineV2Enabled`, `songTrainerEnabled` = `songTrainerV2Enabled` (tehát a reachability-mérő flag-nevei a BE-halmazra képeznek) |
| `dart run tool/check_screen_reachability.dart --format table` | a §3-ban nevesített gerinc MINDEN állomása `adaptiveShellEnabled`-gated: `TodayHubScreen` (`app_router.dart:520`), `PracticeAreaHubScreen` (`:541`), `UnifiedLibraryScreen` (`:604`), `ProfileHubScreen` (`:600`) |

A mai harness-szel tehát a brief SAJÁT bejárási útvonala (indítás → Today →
gyakorlás → eredmény → Library → Progress → Profile) egyetlen állomásig sem jut
el — az A2/A3 nem lazítható cellák, hanem **futtathatatlanok**.

**Javítás:** az `allowed_paths` megkapja a `test/support/e2e_harness.dart`-ot,
**KIZÁRÓLAG** egy opcionális, elnevezett `flags` paraméter hozzáadására, aminek
az alapértéke a MAI `_e2eConfig()` flag-készlete (§5.5). Ez a négy meglévő hívót
(`test/e2e/first_practice_offline_test.dart`,
`test/e2e/returning_user_restart_test.dart`,
`test/accessibility/release_flow_semantics_test.dart`,
`test/accessibility/release_flow_text_scale_test.dart` —
`grep -rln "bootE2eApp\|restartE2eApp" test/`) **változatlanul** hagyja, és mind
a négy bekerül a `gate_tests`-be, mert a briefen KÍVÜL élnek, mégis a kör által
írt fájlt pinnelik ([L593](../LESSONS.md#l593) / brief-lint **S11**+**S14**
hibaosztály). Precedens ugyanerre az indoklás-alakra: az `E16-R04` §0.0.1/R5
(`.gitignore` felvétele — „a §3 ígéretét enélkül nem lehetett H3 nélkül
teljesíteni").

### R3 — az A1 „aminek van valós forrása" feltétele gépileg ELDÖNTHETETLEN → zárt szabályra cserélve

A törzs §3-a azt írja, a mérő azt tiltja, hogy konstans `0`/`{}`/`null` menjen
„olyan képernyő-paraméternek, **aminek van valós forrása**". Azt, hogy egy
paraméternek „van-e valós forrása", statikusan semmi nem dönti el — így a mérő
kimenete az implementer ítélete lenne, nem mérés. A feltétel helyére az §5.3
**zárt, felsorolt szabályhalmaza** kerül (P1/P2/P3) + egy **kimondott,
indoklásos kivétel-lista**; a listán kívül minden találat lelet.

Mért kiindulás (a mai fán a mérő 18 fájlt lát: 4 routing + 14 kompozíciós
provider):

| Mért parancs | Eredmény |
|---|---|
| `grep -nE ":\s*(0\|0\.0\|''\|\"\"\|\[\]\|\{\}\|null\|const \[\]\|const \{\}\|const <)" lib/app/routing/app_router.dart lib/app/routing/adaptive_shell_routes.dart` | **0 találat** — a router képernyő-konstruálásai ma placeholder-mentesek (P1: 0) |
| `grep -rnE "Provider[A-Za-z]*(<[^>]*>)?\((ref\|_)\)\s*=>\s*(0\|0\.0\|''\|\"\"\|\[\]\|\{\}\|null\|const\s*[<\[{])" <a 18 fájl>` | **0 találat** (P2: 0) |
| `grep -nE "^(const\|final)\s+…\s*=\s*(0\|…\|false)\s*;" <a 18 fájl>` | **1 találat**: `lib/features/progress_v2/application/progress_providers.dart:34` — `const bool progressV2IsOffline = false;` (P3) |
| `grep -rn "TODO(E08-R30)" lib/ \| wc -l` · `grep -rni "placeholder" lib/app/routing/` | **0** · **0** — a §2 „12 placeholder + 8 `TODO(E08-R30)`" állítása TÖRTÉNETI: az `E16-R01`/`R02` lezárta |

A `progressV2IsOffline` a SAJÁT doc-commentje szerint szándékos
(„*Progress V2 is 100% local (§5.7) … A measured constant, not a placeholder
standing in for a missing sync-status source*"). Mivel a `lib/**` tiltott zóna,
ez **nem** a forrás megjelölésével, hanem a mérő kivétel-listájának EGY,
indoklással ellátott bejegyzésével oldódik fel — és épp ezért lesz a
kivétel-mechanizmus maga is **nem vákuum** (van valódi bejegyzése, amit az
**A7** cella pinnel).

### R4 — az A4 mércéje a briefen KÍVÜL él → a kör-belső őr a `placeholder_wiring_test.dart`-ba kerül

A törzs A4-e bizonyítékként a `test/tooling/screen_reachability_test.dart`-ot
nevezi meg, az viszont **nincs** az `allowed_paths`-on (csak a `gate_tests`-en)
— a kör tehát olyan mércét ígért, amit nem írhat meg (brief-lint **S14**). A
`gate_tests`-beli szerepe VÁLTOZATLAN (regressziós őr), de az A4 gépi cellája az
§5.4 szerint a `test/tooling/placeholder_wiring_test.dart`-ba kerül.

### R5 — az A4 halmaza MÉRVE 73, és a bejárható részhalmazt a BE-flagkészlet szabja meg

`dart run tool/check_screen_reachability.dart --format table` →
**„Measured screens: 96. Reachable: 73. Unreachable: 23. Flag-gated: 27."**
A §2 becslései helyett ezek a mért számok kötnek. A partíció szabálya az §5.4-ben.

### R6 — a §7 gate-parancs a bővült `gate_tests` listát tükrözi

A brief-lint **S12** („a §7 nem tükrözi a `gate_tests`-et") ellen: a §7 parancsa
a fenti nyolc útvonalat sorolja, ugyanabban a sorrendben.

### R7 — `native_gate = true` marad, de az APK-t a CI adja

Az A6 telepíthető APK-artefaktumot kér, ezért a `native_gate` `true`, és a
`tools/round-ci-plan.py` a `build-apk.yml`-t fogja tervezni. A lokális gate
Android-buildet **nem** futtat (ADR 0053, nincs helyi Android SDK) — az A6
bizonyítéka kizárólag az orchesztrátor CI-dispatch linkje a §10-ben.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bejárás olyan képernyőt talál, ami placeholder-adatot mutat, a kimenet a `stopped` jelzés és a lista — a javítás a felelős feature körének a dolga, nem a záró köré.

## 1. Cél

Gépi bizonyíték arra, hogy a fejlesztett kód és a felület EGYÜTT működik: minden elérhető képernyő valós adatot vagy explicit üres állapotot mutat, és a core utak végigjárhatók.

## 2. Jelenlegi állapot — mért tények (a pre-flight írja felül)

*(A §0.0.1 pre-flight felülírta: minden szám alatta MÉRVE, `main @ d0575edd`.)*

- A sáv indulásakor a routerben **12** placeholder-konstrukció és **8** `TODO(E08-R30)` volt; ezeket az `E16-R01`/`R02` **lezárta** — ma `grep -rn "TODO(E08-R30)" lib/` → **0**, `grep -rni "placeholder" lib/app/routing/` → **0**.
- `test/e2e/` a Ch12 Kör 11 óta létezik (determinisztikus harness, fake óra és globális hálózat-tiltás): 4 teszt + `test/support/e2e_harness.dart` (358 sor). A harness flag-készlete ma FIX (§0.0.1/R2).
- A képernyő-elérhetőség mérője (`tool/check_screen_reachability.dart`, 489 sor) az `E15-R03` terméke; Dart-API-ja (`ScreenReachability(repo).render()` → `ScreenReachabilityResult.verdicts`) tesztből hívható, ahogy a `test/tooling/screen_reachability_test.dart` teszi. Mai mérése: **96 / 73 elérhető / 23 elérhetetlen / 27 flag-gated**.
- A capability-besorolások az `E16-R03` `docs/release/capability-rollout.md` táblájában élnek. A **BE** halmaz nyolc eleme MÉRVE azonos a `FeatureFlags.forEnvironment(<nem-production>)` `nonProd`-ágával (`lib/app/config/feature_flags.dart:77–139`).
- A kompozíciós provider-réteg mai fájlhalmaza **14** fájl (`lib/features/*/application/*providers*.dart` + `lib/features/*/providers/*providers*.dart`), a routing-réteg **4** (`lib/app/routing/*.dart`).

## 3. Scope

**Benne van:** `tool/check_placeholder_wiring.dart` — statikus mérő az **§5.3 zárt szerződése** szerint (H1 routing + H2 kompozíciós provider réteg; P1/P2/P3 lelet-szabályok; indoklásos kivétel-lista; fail-closed üres fájlhalmazra), gépileg olvasható kimenettel · `test/tooling/placeholder_wiring_test.dart` — a mérő cellái **és** az A4/A5 partíció-őre (§5.4) · `test/e2e/full_app_walkthrough_test.dart` — a „BE" besorolású capabilityk core útjainak végigjárása a determinisztikus harnessen (indítás → Today → gyakorlás → eredmény → Library → Progress → Profile), minden lépésnél állítva, hogy a képernyő NEM placeholder-adatot mutat · `test/support/e2e_harness.dart` — kizárólag az §5.5 szerinti opcionális `flags` paraméter · `docs/release/full-app-verification.md` — a mért eredmény, a nyitott és kimaradó tételek gazdával és körrel.

**NINCS benne (tilos):**

- `lib/**` módosítás (a záró kör MÉR, nem javít).
- Új capability bekapcsolása.
- A felismerés pontosságának mérése (Chapter 14).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_placeholder_wiring.dart` | ÚJ — a placeholder-mérő (§5.3) |
| `test/tooling/placeholder_wiring_test.dart` | a mérő cellái **és** az A4/A5 dokumentum-őre (§0.0.1/R4, §5.4) |
| `test/e2e/full_app_walkthrough_test.dart` | a teljes bejárás |
| `test/support/e2e_harness.dart` | **KIZÁRÓLAG** az opcionális `flags` paraméter hozzáadása, mai alapértékkel (§0.0.1/R2, §5.5) |
| `docs/release/full-app-verification.md` | ÚJ — a mért eredmény |

**Tilos zóna:** `lib/**` · `backend/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A „működik" állítás MÉRÉSBŐL jön

**NEM elfogadható gyengítés:** „a képernyő megjelenik" mint bizonyíték — a cella az ADATOT is állítja.

### 5.2 A talált placeholder LELET, nem javítandó munka

**NEM elfogadható gyengítés:** gyors javítás a `lib/`-ben, ami elrejtené, mit mért a záró kör.

### 5.3 A placeholder-mérő ZÁRT szerződése (§0.0.1/R3 — ez váltja ki a „van valós forrása" feltételt)

**Mért fájlhalmaz** (a mérőben kimondva, nem paraméterezhető a hívóból):

- **H1 — routing réteg:** `lib/app/routing/*.dart` (ma **4** fájl).
- **H2 — kompozíciós provider réteg:** `lib/features/*/application/*providers*.dart`
  és `lib/features/*/providers/*providers*.dart` (ma **14** fájl).

**Placeholder-literál** (zárt lista): `0` · `0.0` · `''` · `""` · `[]` · `{}` ·
`null` · `const []` · `const {}` · `const <T>[]` · `const <K, V>{}`.

**A három lelet-szabály:**

| Kód | Hol | Mi a lelet |
|---|---|---|
| **P1** | H1 | egy képernyő-osztály (a `tool/ui_inventory.dart` mért 96-os listájából) konstruktor-hívásában bármely **elnevezett argumentum** értéke placeholder-literál |
| **P2** | H2 | egy **top-level provider-deklaráció** (`Provider`, `NotifierProvider`, `FutureProvider`, `StreamProvider` és `.family`/`.autoDispose` változataik) értékkifejezése **kizárólag** placeholder-literál |
| **P3** | H2 | egy **top-level `const`/`final` deklaráció** értéke placeholder-literál |

**Ami szándékosan NEM lelet:** metóduson/függvényen BELÜLI lokális változó,
mező-alapérték és `if`/`switch`-ág. Mért indok: `grep -nE "=\s*(0|null|…)\s*;"`
a 18 fájlon 7 ilyen sort ad (pl. `auth_providers.dart:32 int value = 0;`,
`practice_session_providers.dart:140 var counter = 0;`) — ezek algoritmus-belső
állapotok, nem képernyő-bekötés; felvételük a mérőt zajjá tenné.

**Kivétel-lista.** A mérőben egy kimondott, `(fájl, deklaráció-név, indok)`
hármasokból álló konstans lista él. Egy találat CSAK akkor nem lelet, ha
szerepel rajta **nem üres** `indok`-kal; az indok nélküli bejegyzés maga is
lelet. A mai fán a listának **pontosan egy** eleme van:
`lib/features/progress_v2/application/progress_providers.dart` ·
`progressV2IsOffline` · indok: a forrás saját doc-commentje („*Progress V2 is
100% local (§5.7) … A measured constant, not a placeholder standing in for a
missing sync-status source*"). **NEM elfogadható gyengítés:** új bejegyzés
felvétele azért, hogy egy MA nem létező lelet elférjen — a kivétel-lista a
`lib/**` tiltott zónája miatt létezik (§3), nem a mérce puhítására.

**Gépi kimenet és kilépési kód:** `--format table|json`; `0` = nulla lelet,
nem-nulla = lelet VAGY üres mért fájlhalmaz. Az üres halmaz **fail-closed**: ha
a glob 0 fájlt fed, az nem zöld, hanem hiba (a brief-lint `S13` és az
[L606](../LESSONS.md#l606) hibaosztálya).

### 5.4 Az A4 lefedettségi partíciója — mérve, nem kézzel másolva

A `test/tooling/placeholder_wiring_test.dart` cellája a MÉRT elérhető halmazt
(`ScreenReachability(Directory.current).render()`, `verdict.reachable == true`)
veti össze két listával:

1. **Bejárt halmaz** — a `full_app_walkthrough_test.dart` által exportált, a
   bejárás során ténylegesen megjelenített képernyők útvonal-listája. **NEM
   elfogadható gyengítés:** kézzel karbantartott konstans lista — a bejárt
   halmaznak a bejárás FUTÁSÁBÓL kell származnia (a felépült képernyő-típus
   megfigyeléséből), különben a cella egy szándéknyilatkozatot mér.
2. **Kimaradó halmaz** — a `docs/release/full-app-verification.md` gépileg
   parse-olt táblája, soronként `| Screen | Indok | Gazda | Kör |`, a
   `docs/ui/retirement-plan.md` §6 mintájára (amit a
   `screen_reachability_test.dart` már ugyanígy olvas be).

**A cella három állítása:** (a) a két halmaz **diszjunkt**; (b) az uniójuk a
mért elérhető halmaz **fölé megy** (egyetlen elérhető képernyő sem hiányzik);
(c) a kimaradó tábla egyetlen sorában sincs üres `Indok`, `Gazda` vagy `Kör`
cella, és a `Kör` cellája `E\d\d-R\d\d` alakú vagy kimondott
`nincs — <indok>` — ez az **A5** gépi őre is.

### 5.5 A harness `flags` paramétere — additív, alapértéke a mai viselkedés

`bootE2eApp` (és a rá épülő `restartE2eApp`) új, opcionális, elnevezett
paramétert kap; ennek **alapértéke bitre a mai `_e2eConfig()` flag-készlete**,
így a négy meglévő hívó viselkedése változatlan. A bejárás a paraméternek a
**szállított** `FeatureFlags.forEnvironment(AppEnvironment.development,
accountEnabled: false)` értéket adja át — **NEM elfogadható gyengítés:**
kézzel összeválogatott flag-készlet, ami a BE besorolástól eltérhet. A
determinisztikus profil többi eleme (`FakeNetworkGuard`, `HarnessClock`,
`fakeAudioOverrides`, token-store) VÁLTOZATLAN; a harnessben új fake nem
születik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A router és a kompozíciós rétegek placeholder-mentesek: a mérő az §5.3 P1/P2/P3 szabályaival **0** leletet ad, kilépési kód `0` | `placeholder_wiring_test.dart` |
| A2 | A teljes bejárás minden lépése valós adatot vagy EXPLICIT üres állapotot mutat — a cella az ADATOT állítja, nem a képernyő jelenlétét | `full_app_walkthrough_test.dart` |
| A3 | A „BE" besorolású capabilityk core útjai végigjárhatók hálózat nélkül, a **szállított** `forEnvironment(development)` flag-készlettel (§5.5) és sértetlen `FakeNetworkGuard`-dal | `full_app_walkthrough_test.dart` |
| A4 | Minden **mért** elérhető képernyő (ma 73) szerepel a bejárásban vagy nevesített indokkal kimarad — a partíció diszjunkt és teljes (§5.4) | `placeholder_wiring_test.dart` (§0.0.1/R4) + a dokumentum |
| A5 | A dokumentum minden nyitott/kimaradó tétele gazdát ÉS kört nevez, üres cella nélkül | `placeholder_wiring_test.dart` (§5.4/c) |
| A6 | ZÖLD teljes CI-futás a kör-branchen, telepíthető APK-artefaktummal | orchesztrátor-dispatch linkje a §10-ben |
| A7 | A mérő kivétel-listája **nem vákuum**: pontosan a §5.3-ban mért egyetlen bejegyzést tartalmazza, nem üres indokkal; indok nélküli bejegyzés PIROS | `placeholder_wiring_test.dart` |
| A8 | A mérő mért fájlhalmaza nem üres és nem szűkült: H1 ≥ 4, H2 ≥ 14 fájl; üres halmaznál a mérő nem-nulla kóddal áll meg | `placeholder_wiring_test.dart` |
| A9 | A négy meglévő harness-hívó viselkedése változatlan (a `flags` alapértéke a mai készlet, §5.5) | a `gate_tests` négy örökölt útvonala zölden |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A bejárás csak rendereli a képernyőket, az adatot nem állítja | A2 |
| Egy elérhető képernyő kimarad a bejárásból indok nélkül | A4 |
| A placeholder-mérő csak a routert nézi, a kompozíciós rétegeket nem | A1 + **A8** (H2 ≥ 14 fájl) |
| A dokumentum „hamarosan" bejegyzést tartalmaz gazda nélkül | A5 |
| A mérő globja elgépelt/üres halmazt fed, ezért trivi-zöld | **A8** (fail-closed üres halmazra) |
| A lelet a kivétel-listára kerül indok nélkül, hogy zöld legyen | **A7** |
| A bejárt halmaz kézzel karbantartott konstans lista, nem a futásból jön | A4 (§5.4/1) |
| A bejárás hand-picked flag-készlettel fut, ami eltér a BE besorolástól | A3 (§5.5) |
| A harness `flags` paramétere alapértéken megváltoztatja a mai viselkedést | **A9** (a négy örökölt teszt) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva).** Két lépés, mindkettő
a mai fán reprodukálható, a MÉRT kiindulással (§0.0.1/R3: P1 = 0, P2 = 0):

1. Írd át ideiglenesen a
   `lib/features/progress_v2/application/progress_providers.dart`
   `progressPracticeHistoryProvider` testét
   `const <PracticeHistoryEntry>[]`-re (P2-lelet), futtasd a §7 gate-et →
   az **A1** cellának PIROSNAK kell lennie, és a Progress-állomás adat-állítása
   miatt az **A2**-nek is.
2. Vedd fel ugyanezt a kivétel-listára ÜRES indokkal → az **A7** cellának
   PIROSNAK kell lennie (a kivétel nem menekülőút).

Mindkét lépés után **állítsd vissza** a fát (`git checkout --` a `lib/`-re), és
a §10-ben idézd a PIROS futások kimenetét szó szerint.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/e2e/full_app_walkthrough_test.dart test/tooling/placeholder_wiring_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart test/e2e/first_practice_offline_test.dart test/e2e/returning_user_restart_test.dart test/accessibility/release_flow_semantics_test.dart test/accessibility/release_flow_text_scale_test.dart
```

*(A nyolc útvonal PONTOSAN a `gate_tests` listája, ugyanabban a sorrendben —
§0.0.1/R6. Az utolsó négy a `test/support/e2e_harness.dart` briefen KÍVÜL élő
hívói: az **A9** mércéje.)*

A placeholder-mérő közvetlen futtatása (a kimenet a §10-be):

```bash
dart run tool/check_placeholder_wiring.dart --format table
```

A teljes suite + property gate + APK a CI-ban fut (ADR 0053); a dispatch és a kiadás-link az orchesztrátoré.

## 8. Implementációs sorrend

1. `tool/check_placeholder_wiring.dart` az §5.3 szerint + a mérő cellái (A1, A7, A8).
2. `test/support/e2e_harness.dart` — az §5.5 additív `flags` paramétere; a négy örökölt hívó FÁJLJÁHOZ nem nyúlsz (A9).
3. `test/e2e/full_app_walkthrough_test.dart` a MÉRT elérhető halmazra és a `forEnvironment(development)` BE-készletre (A2, A3), a bejárt halmaz exportálásával (§5.4/1).
4. A partíció-őr cellái a `placeholder_wiring_test.dart`-ban (A4, A5).
5. A leletek gyűjtése (**NEM javítása** — §5.2; ha a bejárás placeholder-adatot mutató képernyőt talál, a kimenet `stopped` jelzés + lista).
6. `docs/release/full-app-verification.md` — a mért eredmény és a kimaradó tábla.
7. A §6.1 valódi-sértés próba KÉT lépése a §10-be; a CI-dispatch és az APK-link az orchesztrátortól.

## 9. Kockázatok

- **Kozmetikai zárás.** „Megjelenik" ≠ „működik" (A2).
- **Részleges bejárás.** Kimaradó képernyő elrejt egy bekötési hiányt (A4).
- **Javítás-csábítás.** A talált placeholder a felelős feature körébe tartozik (§5.2).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`), effort `medium`. **Ág:**
`sonnet-impl/e16-r05-full-app-verification-and-release`.

### 10.1 Mit épült

| Fájl | Mit csinál |
|---|---|
| `tool/check_placeholder_wiring.dart` (ÚJ) | §5.3 zárt szerződés szerinti statikus mérő: H1 (`lib/app/routing/*.dart`, 4 fájl) + H2 (`lib/features/*/{application,providers}/*providers*.dart`, 14 fájl) ellen fut a P1 (screen-konstruktor elnevezett argumentuma), P2 (top-level provider bare arrow-testtel) és P3 (top-level const/final, bool-bővített) szabály. `_CodeScanner` (string/komment-átugró, zárójel-mélység alapú kinyerő) minden szabályhoz a TELJES érték-kifejezést vágja ki és pontos (`^...$`) egyezést vizsgál a zárt literál-halmazzal — soha nem részstring-regex. Kivétel-lista: egyetlen `(fájl, deklaráció-név, indok)` hármas, indok nélküli bejegyzés saját maga is lelet (`vacuousExceptions`). `--format table\|json`, fail-closed exit kód üres fájlhalmazra. |
| `test/support/e2e_harness.dart` (MÓDOSÍTVA, KIZÁRÓLAG additív) | `bootE2eApp`/`restartE2eApp` opcionális `flags` paramétert kapott, alapértéke bitre a mai `_e2eConfig()` (mostantól `e2eDefaultFlags` néven exportálva). A 4 örökölt hívó (`first_practice_offline_test.dart`, `returning_user_restart_test.dart`, mindkét accessibility fájl) egyetlen sort sem módosított, és zölden fut (A9). |
| `test/e2e/full_app_walkthrough_test.dart` (ÚJ) | `runCoreWalkthrough(WidgetTester)` — a szállított `FeatureFlags.forEnvironment(AppEnvironment.development, accountEnabled: false)` BE-készlettel bejárja: indítás → Today → gyakorlás (Practice Area Hub → Setup → Session) → eredmény → **app-újraindítás** (L5 miatt szükséges) → Library → Progress → Profile → Settings. Minden állomáson valós adatot vagy explicit állapotot állít (l. 10.2), és a ténylegesen felépült képernyő-osztályok halmazát adja vissza (megfigyelésből, nem kézi listából). Exportált, hogy a placeholder-mérő tesztje ÚJRA le tudja futtatni. |
| `test/tooling/placeholder_wiring_test.dart` (ÚJ) | A1 (0 lelet a valós fán), A7 (pontosan 1, nem üres indokú kivétel), A8 (H1≥4, H2≥14, fail-closed üres fixture-halmazra) + 4 fixture-teszt (P1/P2/P3 mindegyike tényleg jelez, egy lokális változó NEM jelez) + A4/A5 (a mért 73 elérhető képernyő ∩ bejárt(9) ∪ kimaradó(64) partíció, a `full-app-verification.md` táblájából parse-olva, egy automatizált „egy sor Gazdáját üresre törlöm” piros-próbával). |
| `docs/release/full-app-verification.md` (ÚJ) | A mérő mért kimenete, öt MÉRT, NEM javított lelet (L1–L5, l. 10.3), a 9 bejárt + 64 kimaradó képernyő teljes, gépileg parse-olható táblája (Screen\|Indok\|Gazda\|Kör). |

### 10.2 A placeholder-mérő mért kimenete (mai fa)

```
$ dart run tool/check_placeholder_wiring.dart --format table
H1 (routing) files: 4. H2 (composition provider) files: 14. Findings: 0.
Suppressed by exception: 1. Vacuous exceptions: 0. Exit code: 0.
```

Az egyetlen kivétel: `progressV2IsOffline` (P3), indokolt.

### 10.3 A bejárás öt mért, NEM javított lelete (teljes szöveg: `docs/release/full-app-verification.md` §2)

1. **L1** — `PracticeAreaHubScreen`'s recommended CTA (`practice_area_hub_screen.dart:55`) nem ad át `?id=`-t → `PracticeSetupScreen` a saját `_RouteError` ágát rendereli (valós, explicit hibaállapot, §5.1 nem sérül, de a shell egyetlen hirdetett belépési pontja egy pontozott gyakorlásba méréssel zsákutca).
2. **L2** — `OnboardingScreen._completeFinish` mindig `/live`-ra fejez be, függetlenül `adaptiveShellEnabled`-től (a `legacyRedirects` `/practice/live`-ra tereli, sosem `/today`-ra).
3. **L3** — `libraryV2SourcesProvider` az `analysisRepositoryProvider`/`songRepositoryProvider`/`setlistRepositoryProvider`-t olvassa, amiket csak a production bootstrap köt be — `bootE2eApp` nem —, ezért `UnifiedLibraryScreen` a saját, valós `libraryV2LoadFailed` hibaállapotát mutatja.
4. **L4** — `ProfileHubScreen`/`TodayHubScreen` „sessions” mércéje a V1 „Learn” naplót (`practiceLogProvider`) olvassa, amit a Practice Engine V2 quick-start flow sosem ír.
5. **L5** — `practiceHistoryV2ListProvider` sima `FutureProvider` (nincs `.family`, `grep -rn "invalidate(practiceHistoryV2ListProvider\|refresh(practiceHistoryV2ListProvider" lib/` → 0 találat) — az ELSŐ olvasása (a Today Hub napi-cél gyűrűjén keresztül, MÉG a gyakorlás előtt) örökre gyorsítótárazza az akkori (üres) állapotot a konténer élettartamára. A bejárás emiatt egy valós app-újraindítást végez az eredmény-állomás után — enélkül a Progress-mérce (a §6.1 mutációs célpontja) sosem tudna valós adatot mutatni ebben a konténerben, még helyes forráskód mellett sem.

Egyik lelet sem P1/P2/P3 placeholder-literál — mindegyik a bejárás (A2/A3) saját, dinamikus mérése. A STOP-protokollt (§0/§5.2) ez a kör úgy alkalmazta, hogy a leleteket **rögzítette és dokumentálta** (gazdával, „nincs — <indok>” körrel), a `lib/**`-et nem módosította — a javítás a felelős feature körök öröksége.

### 10.4 Valódi-sértés próba (§6.1, KÖTELEZŐ) — szó szerinti PIROS kimenet

**1. lépés** — `lib/features/progress_v2/application/progress_providers.dart`
`progressPracticeHistoryProvider` teste ideiglenesen:
```dart
final progressPracticeHistoryProvider = Provider<List<PracticeHistoryEntry>>(
  (ref) => const <PracticeHistoryEntry>[],
);
```
majd `git checkout --` a fájlra a mérés után. A mérő CLI önmagában:
```
$ dart run tool/check_placeholder_wiring.dart --format table
H1 (routing) files: 4. H2 (composition provider) files: 14. Findings: 1.
Suppressed by exception: 1. Vacuous exceptions: 0. Exit code: 1.
| P2 | progress_providers.dart:23 | progressPracticeHistoryProvider |
  top-level provider "progressPracticeHistoryProvider" resolves to the
  bare placeholder literal "const <PracticeHistoryEntry>[]" |
```

**A1 cella** (`flutter test test/tooling/placeholder_wiring_test.dart`) PIROS:
```
A1 — the router and composition layers are placeholder-free on the real tree
zero unsuppressed findings, exit code 0 [E]
  Expected: empty
    Actual: [Instance of 'PlaceholderFinding']
  unexpected placeholder-wiring findings: [top-level provider
  "progressPracticeHistoryProvider" resolves to the bare placeholder
  literal "const <PracticeHistoryEntry>[]"]
```

**A2 cella** (`flutter test test/e2e/full_app_walkthrough_test.dart`) PIROS:
```
E16-R05 A2/A3 — the BE-flagged core walkthrough asserts real data or an
explicit state at every stop ... [E]
Expected: an object with length of <1>
  Actual: []
   Which: has length of <0>
the just-completed session must reach the Progress V2 composition layer
through progressPracticeHistoryProvider
```

**2. lépés** — ugyanezt (`progressPracticeHistoryProvider`) felvéve
`tool/check_placeholder_wiring.dart`'s `placeholderExceptions`
listájára ÜRES indokkal (a lib/ mutáció változatlanul fennáll), majd
ismét visszaállítva mindkét fájlt a mérés után:

**A7 cella** PIROS:
```
A7 — the exception list is exactly one real, non-vacuous entry
exactly one exception, non-empty reason, nothing vacuous [E]
  Expected: an object with length of <1>
    Actual: [Instance of 'PlaceholderException', Instance of 'PlaceholderException']
     Which: has length of <2>
```

A mérő CLI önmagában (`vacuousExceptions` mezője is jelzi a hiányzó
indokot):
```
Vacuous exceptions: 1.
| lib/features/progress_v2/application/progress_providers.dart | progressPracticeHistoryProvider |
```

Mindkét lépés után `git checkout --` (lib/) és a `tool/check_placeholder_wiring.dart`
kézi visszaállítása futott; a `git status --porcelain` a próba után tiszta volt.

### 10.5 A záró gate — teljes, csonkítatlan kimenet

```
$ tools/round-gate.sh test/e2e/full_app_walkthrough_test.dart test/tooling/placeholder_wiring_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart test/e2e/first_practice_offline_test.dart test/e2e/returning_user_restart_test.dart test/accessibility/release_flow_semantics_test.dart test/accessibility/release_flow_text_scale_test.dart

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/e2e/full_app_walkthrough_test.dart               zöld
    test test/tooling/placeholder_wiring_test.dart             zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/e2e/first_practice_offline_test.dart             zöld
    test test/e2e/returning_user_restart_test.dart             zöld
    test test/accessibility/release_flow_semantics_test.dart   zöld
    test test/accessibility/release_flow_text_scale_test.dart  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A 8 útvonal PONTOSAN a `gate_tests` lista, ugyanabban a sorrendben. Az
utolsó négy (`first_practice_offline_test.dart`,
`returning_user_restart_test.dart`, mindkét accessibility fájl) a
`test/support/e2e_harness.dart` briefen KÍVÜL élő hívói — zöld futásuk az
A9 bizonyítéka.

### 10.6 Nyitott tételek / a review figyelmébe

- **L1–L5** (`docs/release/full-app-verification.md` §2/§4) — öt valós,
  MÉRT bekötési hiányosság, egyik sem javítva ebben a körben (`lib/**`
  tiltott zóna). Mindegyiknek nincs hozzárendelt javító kör — a review
  eldöntheti, kell-e ezekhez ÚJ kört nyitni (a döntés a Claude/orchesztrátor
  hatásköre, nem ezé a záró köré).
- **A6** (telepíthető APK) — ennek a körnek nincs helyi Android SDK-ja (ADR
  0053); a CI-dispatch és az APK-link az orchesztrátor dolga.
- A `docs/release/full-app-verification.md` §3.2 kimaradó táblájának 64
  sora kategóriánként (KI/PREVIEW capability, legacy/duplikált regisztráció,
  Quick Tools, Songs tab, Gamification, Song Trainer stb.) sorolja fel az
  okot — a review érdemes ellenőrizze, hogy egyik sor sem vákuum-indoklás
  (üres vagy „hamarosan” jellegű).

## 11. Review — a Claude tölti ki
