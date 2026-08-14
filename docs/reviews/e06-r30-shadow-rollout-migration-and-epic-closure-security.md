# E06-R30 — Dedikált biztonsági / adatvédelmi / rollout review

- **Kör:** E06-R30 — Shadow rollout, migráció és Epic 6 lezárás (ZÁRÓ KÖR)
- **Branch / SHA:** `codex/e06-r30-shadow-rollout-migration-and-epic-closure` @ `caceaae4` (a `fae6e9ad` + `d54821ae` pre-flight commitok fölött — mindhárom SHA gépileg igazolva létezik)
- **Base (implementer induló HEAD):** `d54821ae`
- **Reviewer:** security-reviewer (READ-ONLY, AGENTS.md §15.1)
- **Kockázat:** high (migráció + adatvédelem + rollout) — a review a merge kötelező előfeltétele
- **Verdikt:** **PASS / APPROVED — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 0 MINOR, 4 NOTE**

## 1. Verdikt

A kör egy **bekötetlen** (production-hívó nélküli) shadow/rollout/migráció-tesztelő és Epic-lezáró kör. A három nem tárgyalható termékhatár — (a) nyers audio nem hagyja el az eszközt / nem kerül logba, (b) egyetlen flag sem `true` semmilyen környezetben, (c) a migráció nem törli/sérti a legacy adatot — **mind teljesül**, futtatott bizonyítékkal. A dokumentáció (completion report, 29 ADR, README, HANDOFF, SDD index) **őszinte**: explicit rögzíti, hogy a shadow mechanizmus „hívó nélkül, csak contract-teszt", és hogy a rollout shadow szinten marad. Nincs merge-blokkoló lelet.

**Megjegyzés (az orchestrátor felől, a párhuzamos content-review után):** a NOTE-1/NOTE-2 alább ugyanazt a `rollback_test.dart`/`full_migration_test.dart` tautológia-mintát írja le, amit a párhuzamos content-review F1-ként (MAJOR) sorolt be — a security-reviewer ezt a terméktulajdonság (a migrátor konstrukcióból nem tud legacy-t törölni) szempontjából NOTE-nak minősítette, mert a mögöttes TERMÉK biztonságos, csak a TESZT gyenge. A content-review szigorúbb besorolása arra épül, hogy a completion report a kapcsolódó DoD-tételt bizonyítottként (`[x]`) állítja a teszt gyengesége ellenére — ez egy dokumentum-hűségi, nem termék-biztonsági probléma. A két jelentés nem mond ellent egymásnak; a merge-döntés a content-review F1 MAJOR-ját tekinti irányadónak (docs/reviews/e06-r30-…-review.md), a security-review PASS-a változatlanul érvényes a saját hatáskörére.

## 2. Leletek (mind NOTE — egyik sem határsértés, egyik sem él ma production-úton)

**NOTE-1 — A migrációs teszt „mezőnkénti egyezés" assertionje önmagát hasonlítja (teszt-szigor).** `test/features/audio_analysis/data/full_migration_test.dart:32-34,62-69`. A teszt a migráció előtt `originalPayloads[id] = session.toJson()`-t tárol, utána `reencoded = session.toJson()`-t vet össze — de a `session` UGYANAZ az immutable in-memory objektum (`supplier: () async => sessions`), így a hasonlítás **tautológ**: a migrátor viselkedésétől függetlenül sosem bukhat, és nem bizonyítja független módon a lemez-szintű legacy-megőrzést. **Miért csak NOTE:** a valós tulajdonság (a migrátor sosem törli a legacy kulcsot) **konstrukcióból** áll — a `LegacyLibraryMigrator` (körön kívül, változatlan) csak egy OLVASÓ `supplier`-t (`legacy_library_migrator.dart:78,107`) és V2 repository-t tart, nincs handle-je a legacy tár írásához/törléséhez (docstring 20-23: „NEVER touches the legacy `ss.library.sessions` / `library_sessions` keys"). A teszt valódi értéke az idempotencia (2. futás `migrated:0`, `skipped:50`). **Javasolt irány:** ha MÉRNI kell a legacy-megőrzést, valós háttértárat snapshotolni migráció előtt/után.

**NOTE-2 — A rollback teszt nem kapcsol flaget ON→OFF→ON, és flag-független olvasást ellenőriz (teszt-szigor).** `test/features/audio_analysis/data/rollback_test.dart:11,29-44,47-62`. A teszt neve „OFF → migrate → OFF → ON preserves both legacy and V2 reads", de **soha nem kapcsol be** flaget: `_flagsOff()` egy `const FeatureFlags(...)`-t épít az alap-konstruktorral és azt ellenőrzi (konstans `true`), a `repository.getById('rollback')` pedig nem olvas flaget (a `FileAnalysisRepository` feltétel nélkül olvas lemezről). **Miért csak NOTE:** amit bizonyít, elég a §5 Döntés 4 határhoz — a V2 dokumentum migráció után sértetlen és olvasható (`getById` sikerül), és a migráció nem módosítja a flageket. **Javasolt irány:** valós ON→OFF→ON `AppConfig`-override szekvencia (brief R8), vagy a teszt-név összehangolása a mérttel. (Lásd fenti orchestrátori megjegyzés: a content-review ugyanezt MAJOR-nak minősítette a completion report `[x]` túlállítása miatt — a javító kör mindkét jelentés szerint ugyanazt a tesztet javítja.)

**NOTE-3 — ADR 0239 kissé többet tulajdonít a tesztnek, mint amit az mér (doksi-őszinteség).** `docs/adr/0239-analysis-document-storage.md` E06-R30 bekezdés: „az 50-session migrációs teszt **további bizonyíték**: … a legacy forrás érintetlen." A tulajdonság igaz (konstrukcióból), de a teszt önmagában nem bizonyítja (NOTE-1). **Miért csak NOTE:** a párhuzamos 0220/0221/0216 bekezdések pontosak; nincs valótlan „bizonyított" állítás. **Javasolt irány:** a legacy-sértetlenséget a migrátor konstrukciójához / E06-R21-hez kötni.

**NOTE-4 — `analysisRolloutStage` getter kihagyja a `v2ShadowLab` lépcsőt — ma inert, előretekintő mag.** `lib/app/config/feature_flags.dart:202-204`: `audioAnalysisV2Enabled ? v2OptIn : v1Default` — kihagyja a `v2ShadowLab`-ot. Ha egy JÖVŐBELI kör ezt adatfolyam-kapuként köti be, egy puszta `audioAnalysisV2Enabled=true` build `v2OptIn`-t jelentene `v2ShadowLab` helyett (rollout-lépcső túl-reprezentálás). **Miért csak NOTE:** ma teljesen inert — mind a kilenc flag OFF (mindig `v1Default`), és **nulla fogyasztója** van a `lib/`-ben (grep igazolt, csak a flag-őr teszt olvassa). **Javasolt irány:** a bekötő kör ne kezelje az `== v2OptIn`-t opt-in kapuként explicit Lab-check nélkül.

## 3. Pozitív bizonyíték (végignézve, tisztának találva)

- **Nyers audio (§5, fókusz 1):** `ShadowDiffReport` (`shadow_diff_report.dart:5-31`) csak `int`/`double`/`Duration`/`bool` (count/BPM/hossz/futásidő/`v2Failed`) — nincs PCM/fájlnév/időbélyeg. Grep a 3 új lib-fájlon `print|log|toJson|toMap|toString|jsonEncode|stderr|stdout` → **0 találat** ⇒ a riportnak nincs egress-útja. A V2 hibaág (`shadow_analysis_runner.dart:62-63`) `on Object { v2Failed = true; }` — a kivétel üzenete sosem tárolódik. Secret scan: 2494 fájl, 0 finding; fixture-ök fake-ek (`fingerprint: 'shadow-fixture'`, `dspConfigHash: 'test'`).
- **Flag-őr (§5 Döntés 1, fókusz 2):** mind a kilenc analízis-flag literál `false` a `forEnvironment`-ben (`feature_flags.dart:84-92`, NEM `nonProd`) és az alap-ctorban; nincs `fromEnvironment`/dart-define (grep 0); `usesNetwork` (207) változatlan, egyik flaget sem tartalmazza. Próba: flip → PIROS minden környezetben.
- **Shadow-izoláció (§5 Döntés 2):** V1 a kapu ELŐTT fut (`shadow_analysis_runner.dart:45`), mindkét ágban változatlan; teszt bizonyítja a bitre azonos V1-et 9 fixture-ön + dobás/cancel izolációt + négycellás kapu-mátrixot.
- **Migráció:** olvasó-only supplier → nem tud legacy kulcsot törölni; idempotencia bizonyított; checkpoint a durable írás után mentődik (crash-biztos, `legacy_library_migrator.dart:175-178`).
- **Prompt-injection (§5.1, fókusz 5):** nincs dinamikus eval, nincs untrusted-string→fájlnév interpoláció a diffben.
- **H-GATEGUARD / új-ADR (§4, fókusz 7):** 0 hozzáadott `docs/adr/*.md` (mind 29 `M`); nincs `.github/**`, `tool/ci/**`, `round-gate.sh`; scope-audit OK.
- **Doksi-őszinteség (§5 Döntés 7 / OD-02, fókusz 6):** completion report `:112` „hívó nélkül, csak contract-teszt", `:114` „raw audio nincs a shadow reportban"; ADR 0220 „hívó nélkül tesztelt"; 0216 kalibráció `identity.v1`/EVAL-06 PENDING; README „all nine flags OFF, no production caller … fails closed"; 00-index Chapter 7 „rollout stays at shadow, release blockers remain". Nincs „minden kész" túlállítás.

## Nyers kimenetek és kilépési kódok

**round-gate.sh** (`GATE_EXIT: 0`):
```
format zöld · analyze zöld (No issues found) · test test/features/audio_analysis zöld ·
test test/app zöld · test test/features/analyze zöld · test test/features/library zöld ·
architecture zöld · secrets zöld (2494 file scan, 0 finding) · l10n zöld (en→hu, 1276 message)
MINDEN GATE ZÖLD.
```

**scope-audit.py** (`SCOPE_AUDIT_EXIT: 0`):
```
Legacy scope audit OK (d54821ae..caceaae47994, 46 changed path(s), 0 generated/ignored)
```

**Valódi-sértés próba** (flag `true`-ra állítva `forEnvironment`-ben, `PROBE_EXIT: 1` = PIROS, majd `git checkout` → `git status --porcelain` üres):
```
00:00 +0 -1: all nine Audio Analysis V2 flags stay off in every environment [E]
  Expected: every element(false)
    Actual: [true, false, false, false, false, false, false, false, false]
    Which: has value <true> which doesn't match false at index 0
```
