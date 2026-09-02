# ADR 0484 — Privacy-safe telemetria-szerződés: a tiltás STRUKTURÁLIS, a consent INJEKTÁLT, az `unknown` NEM zöld

- **Státusz:** elfogadva
- **Dátum:** 2026-09-01
- **Kör:** `E12-R19` (Chapter 12, Kör 19)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0132`](0132-ai-tutor-privacy-and-consent.md) (AI Tutor privacy & consent — a
  consent-flow és a redakció külön körök felelőssége; a döntés „nem lazítható
  azért, hogy egy teszt zöld legyen"),
  [`0178`](0178-vision-privacy-by-default.md) (vision privacy by default — az
  „opt-in mentés a termékben" ELVETVE),
  [`0217`](0217-analysis-raw-audio-retention.md) (nyers audio élettartam),
  [`0418`](0418-leaderboards-and-opt-in-competition.md) (opt-in verseny-nézet —
  az alapállapot a NEM-küldés),
  [`0474`](0474-benchmark-record-and-performance-budget-comparison.md) (D5: a
  hiányzó mérés NEM zöld — ennek a körnek a `unknown`-szabálya UGYANEZ a
  hibaosztály, a release-dashboard sávjára alkalmazva),
  [`0479`](0479-privacy-data-inventory-and-consent-enforcement.md) (data
  inventory + consent enforcement — a `tool/check_data_inventory.dart`
  egress-felfedezése ennek a körnek a GÉPI hálózat-tilalmi őre),
  [`0481`](0481-program-threat-model-and-release-security-scan.md)
  (bizonyíték-kötés: minden ellenintézkedés géppel olvasható guardot nevez meg)

## Kontextus — a pre-flight MÉRT tényei (2026-09-01, `main @ 877e356b`)

1. **`lib/core/telemetry/` nem létezik.** A fán a rokon réteg a
   `lib/core/logging/{app_logger,debug_app_logger,log_redactor,logger_provider}.dart`
   és a `lib/core/network/redacted_log_interceptor.dart`.
2. **Telemetria-consent kapcsoló MA NINCS.** `grep -rn
   "analyticsConsent\|telemetryConsent" lib/ --include=*.dart` → nulla találat.
   A `docs/privacy/data-inventory.yaml` öt valódi route-ja (`account_api`,
   `diagnostics_upload`, `tutor_stream`, `community_media`, `share_export`)
   közül egyik sem telemetria.
3. **A `flutter_test` alatt nincs `dart:mirrors`**, tehát a „ebbe a típusba nem
   fér bele szabad szöveg" állítás futásidejű reflexióval nem mérhető. A fán
   MÉRT precedens a forrás-szken (`test/tooling/legacy_identifier_guard_test.dart`,
   `repository_policy_test.dart`, `screen_reachability_test.dart` — mind
   `Directory.current`-ből olvas valódi forrást).
4. **Nincs `yaml` csomag.** A `pubspec.yaml` `dev_dependencies` blokkja pontosan
   `flutter_test` + `flutter_lints ^6.0.0`. A fán MÉRT precedens a kézi,
   `RegExp`-alapú sor-parszer: `tool/check_data_inventory.dart`, valódi fán
   futtatva a `test/tooling/data_inventory_test.dart`-ból.
5. **A `tool/check_data_inventory.dart` a `lib/**` fán egress-útvonalat fedez
   fel** a `DioFactory.create<Név>Client`, `Dio`-típusú tag + kérés-ige,
   `ApiClient`-típusú tag + kérés-ige, `HttpClient(`, `package:http` és
   `SharePlus` mintákra; a `test/tooling/data_inventory_test.dart` A2 cellája
   ezt a VALÓDI fán keresztellenőrzi a `docs/privacy/data-inventory.yaml`-lel.
6. **A hiányzó mérés kezelése már el van döntve** a teljesítmény-sávra:
   [ADR 0474](0474-benchmark-record-and-performance-budget-comparison.md) D5 /
   E12-R14 §5.2 — `tool/compare_benchmarks.py`. Ez a kör ugyanezt a szabályt
   viszi át a release-dashboard sávjára, **nem** ír mellé másikat.
7. **A releváns hibaosztály mérve:** [L549](../LESSONS.md#l549) — a metaadat
   MEGLÉTÉT mérni nem ugyanaz, mint a JELENTÉSÉT érvényesíteni; 33 zöld cella
   közül egy sem mérte a lényeget.

## Döntés

### D1 — A tiltás STRUKTURÁLIS, a redakció csak a MÁSODIK védelmi vonal

A `TelemetryEvent` típusban nincs olyan mező, amibe nyers prompt, hang, kép vagy
szabad felhasználói szöveg beleférne: az esemény neve és kategóriája **zárt
szótárból** (enum) származik, a mért mennyiségek pedig számosak/enumok. Általános
`Map<String, dynamic>` payload-mező TILOS — „a rugalmasság kedvéért" indoklással
is.

A redakció (D2) ezután fut, de nem ő az első védelmi vonal: egy szűrő
kikapcsolható vagy hiányos lehet, egy nem létező mező nem.

**Mérve (bizonyíték-kötés, ADR 0481 mintájára):** `telemetry_redaction_test.dart`
forrás-szken cellája `lib/core/telemetry/telemetry_event.dart` felett.

### D2 — Egyetlen redakciós igazságforrás: a `LogRedactor`

A `telemetry_redactor.dart` a `lib/core/logging/log_redactor.dart` MÉRT felületét
hívja (`fields`, `value`, `text`, `isSensitiveKey`, `sensitiveKeyFragments`,
`maxStringLength = 200`, `maxNumberListLength = 16`, `maxDepth = 4`). Saját
minta-lista, saját kulcs-szótár vagy a konstansok újradeklarálása TILOS: két
lista elkerülhetetlenül szétcsúszik, és a szétcsúszás iránya mindig a
megengedőbb.

A `lib/core/logging/**` ebben a körben **olvasható/importálható, de nem
módosítható** — a meglévő logging-viselkedés nem változhat.

### D3 — Az `unknown` NEM sikeres állapot, és a hiányzó metrika nem hagyható ki

A `docs/operations/slo.yaml` verdikt-szótára `[success, degraded, breach,
unknown]`; `success_verdicts = [success]`, és az `unknown` a **blokkoló**
halmazban van. Minden SLO `required: true` és `on_missing: unknown`. A
release-dashboard hiányzó metrikát `unknown`-ként JELÖL — kihagyni az
összesítésből tilos.

Ez az [ADR 0474](0474-benchmark-record-and-performance-budget-comparison.md) D5
szabályának átvitele, nem új szabály: a „hiányzó mérés = nem zöld" invariáns
egyetlen forrásból származik, csak most a release-kapun is érvényesül.

**Mérve:** az A5 cella parszolja a `slo.yaml`-t és állítja
`unknown ∉ success_verdicts`, `unknown ∈ blocking_verdicts`, minden SLO-nál
`required: true` + `on_missing: unknown`, és az `id`-k egyediségét.

### D4 — Opt-out mellett a sink NO-OP, és a consent INJEKTÁLT

Az alapértelmezett sink hozzájárulás nélkül **nem tárol, nem pufferel és nem
küld**. „Gyűjtsük, és majd ha hozzájárul, elküldjük" TILOS — az a hozzájárulás
előtti gyűjtés, és a `false → true` váltás utáni utólagos flush ugyanaz a
sértés más időzítéssel.

A hozzájárulást a sink **kívülről kapja** (konstruktor-paraméter vagy injektált
olvasó). Provider, `SharedPreferences`, settings-repository vagy bármely
`lib/features/**` hivatkozás TILOS: a fán MA nincs telemetria-consent kapcsoló
(Kontextus 2.), tehát bármely ilyen hivatkozás egy MÁSODIK igazságforrást
teremtene, a bekötés pedig egy KÉSŐBBI kör dolga.

### D5 — A telemetria-réteg szerkezetileg hálózat-képtelen

A `lib/core/telemetry/**` egyetlen fájlja sem hivatkozhat `Dio`-ra,
`ApiClient`-re, `HttpClient(`-re, `package:http`-ra vagy `SharePlus`-ra — sem
típusként, sem hívásként, sem importként. Nem „még nem hívjuk meg": a mező
puszta megléte elég ahhoz, hogy a réteg egress-útvonallá váljon.

**Kettős őr:** (a) a kör saját A7 forrás-szken cellája; (b) a fán MÁR MŰKÖDŐ
`tool/check_data_inventory.dart` egress-felfedezés + a
`test/tooling/data_inventory_test.dart` A2 valódi-fa keresztellenőrzése, ami a
teljes CI-suite-ban fut. A (b) az erősebb, mert nem ennek a körnek a
jóindulatától függ.

## Következmények

- A kör **nem** köt be gyűjtést: az esemény-kibocsátás (`lib/features/**`), a
  telemetria data-inventory route-ja (`docs/privacy/**`) és a backend-oldali
  végpont (`backend/app/telemetry/`) mind KÉSŐBBI körök, feature-flag mögött
  (a rollout-körök 31–33 user-döntése).
- A `docs/operations/slo.yaml` a `docs/operations/release-dashboard.md`
  küszöb-igazságforrása; a dashboard-dokumentum nem ismételheti meg a
  küszöböket (különben D3 két helyen él).
- Az `unknown` blokkoló volta a release-kapun **szigorítás**: egy hiányzó
  mérés eddig láthatatlan volt, ezután nem zöld. Ez szándékos.
- A D1 forrás-szken cellái a `lib/core/telemetry/**` fájljainak SZÖVEGÉRE
  támaszkodnak, tehát egy későbbi átnevezés/refaktor a cellát is érinti — ez a
  reflexió hiányának ára (Kontextus 3.), és tudatosan vállalt.

## Elutasított alternatívák

- **Általános `Map<String, dynamic> payload` mező „a rugalmasság kedvéért".**
  Elvetve: minden strukturális védelmet kinyit (D1), és a redakcióra hárítja azt,
  amit a típusnak kellene garantálnia.
- **Második, telemetria-specifikus redakciós minta-lista.** Elvetve: két lista
  szétcsúszik, és a `log_redactor.dart` a MÉRT, már használatban lévő forrás (D2).
- **Pufferelés hozzájárulásig, utólagos küldéssel.** Elvetve: ez hozzájárulás
  előtti gyűjtés (D4), és pontosan az a minta, amit az
  [ADR 0178](0178-vision-privacy-by-default.md) a vision-sávon már elvetett.
- **A hiányzó metrika kihagyása az összesítésből.** Elvetve: a hiányzó mérést
  zöldnek mutatja — az [ADR 0474](0474-benchmark-record-and-performance-budget-comparison.md)
  D5-ben már mért hibaosztály (D3).
- **Saját consent-tároló a telemetria-rétegben.** Elvetve: második
  igazságforrás, és a fán ma nincs mit tükröznie (D4).
- **`yaml` csomag felvétele a teszt-parszerhez.** Elvetve: a `pubspec.*` nincs a
  kör scope-jában, és a fán MÁR van kézi sor-parszer precedens
  (`tool/check_data_inventory.dart`, Kontextus 4.).
