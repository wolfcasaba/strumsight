# E09-R01 — Review

Brief: `docs/rounds/e09-r01-community-baseline-and-feature-flags.md` (with
the pre-flight `## 0.0` revision + ADR 0395)
Diff: `git diff 7d578ce8...f89a84ff` (pre-flight commit → implementer HEAD)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A Community productionben explicit engedély nélkül nem indul | ✅ | `lib/app/config/feature_flags.dart` `forEnvironment` — mind az öt Community flag `const bool.fromEnvironment('STRUMSIGHT_COMMUNITY*')` `defaultValue` nélkül, tehát production-ben (és minden más környezetben) `false`, amíg egy explicit dart-define nincs átadva. `feature_flags_test.dart` "factory keeps all five flags OFF in production (A1)" — saját kézzel újrafuttatva izolált klónban: ZÖLD. |
| A2 | Mind az öt Community flag development/lab környezetben elérhető, production-ben alapból KI | ✅ | Mind az öt flag SAJÁT, FÜGGETLEN `bool.fromEnvironment` hívással olvas (nem `communityEnabled`-ből származtatva) — ADR 0395 Döntés 2–3. pont szerint. `test_each_subflag_defaults_off_independently` (backend, parametrizált 4 sub-flag) + a Flutter oldal "OFF in development"/"OFF in lab" cellái mind lefedik a §6.1 sor 2 hibás implementációt ("csak egy flag véd, a többi négy nem"). |
| A3 | A threat model lefedi az összes §6 nem-tárgyalható invariánst | ✅ | `docs/security/community-threat-model.md` — mind a nyolc kötelező kategória (identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse) jelen van, konkrét fenyegetésekkel, védelmekkel és feature-flag-gate hivatkozással minden szakaszban (dokumentum-audit, teljes szöveg átolvasva). |
| A4 | Nincs új hálózati kérés és nincs funkcionális regresszió | ✅ | `git diff 7d578ce8..f89a84ff` — 7 fájl, mind az `allowed_paths`-on. A §6.1 valódi-sértés próba során a Practice Generator és Recognition recovery csoportok teljes teszt-halmaza ZÖLD maradt (a meglévő 31 flag értékszemantikája érintetlen). Saját gate-újrafuttatás (lásd alább) ugyanezt igazolja. |
| A5 | A backend `Settings` readiness placeholder-je dokumentálja a SQLite-vs-PostgreSQL éles döntést | ✅ | `backend/app/config.py` `community_postgres_ready` property (ADR 0395 Döntés 5. pont) — `test_community_postgres_ready_is_false_for_sqlite_default`, `..._is_true_for_postgres_url`, + 4-elemű parametrize a PG-flavorokra. |

### §6.1 Mérce-mátrix — saját ellenőrzés

A négy hibás-implementáció sor mindegyikéhez van a fentiek szerint dedikált,
FÜGGETLEN teszt-eset; a `communityEnabled: true` szabotázs-próba
(§10.3-ban dokumentálva) reprodukálva — a leírt három piros cella
(A1 + a két A2-cella) a mai branch-en is pontosan így reprodukálódik
(kézzel megismételve a diff-et, futtatva, majd visszaállítva).

## Scope-audit

```
python3 tools/scope-audit.py --repo <izolált /tmp klón> \
  --brief docs/rounds/e09-r01-community-baseline-and-feature-flags.md \
  --base 7d578ce8
```
→ **`Legacy scope audit OK (7d578ce8..f89a84ff, 7 changed path(s), 0
generated/ignored)`**. A 7 fájl pontosan az `allowed_paths` listája
(`lib/app/config/feature_flags.dart`, `backend/app/config.py`,
`docs/security/community-threat-model.md`,
`docs/baseline/epic-09-community-start.md`,
`test/app/config/feature_flags_test.dart`,
`backend/tests/test_community_config.py`,
`docs/rounds/e09-r01-community-baseline-and-feature-flags.md`).
`lib/features/community/**`, `backend/app/community/**` és `docs/adr/**`
egyike sem érintett — a tilos zóna sértetlen.

## Gate — saját, izolált újrafuttatás

Izolált `/tmp` klón, `f89a84ff` HEAD-en, `tools/round-gate.sh
test/app/config/feature_flags_test.dart`:

```
format: zöld · analyze: zöld (0 issue) · test: zöld (12/12) ·
architecture: zöld (12 allowlisted deviation) · secrets: zöld (0 finding) ·
l10n: zöld (1663 message) · backend ruff format: zöld · backend ruff check:
zöld · backend pytest: zöld (187/187)
MINDEN GATE ZÖLD.
```

Az implementer §10.2 táblázatával megegyező eredmény — a `done` jelzés
kilépéskori `dirty_files=1` tranziens volt (a re-checkolt `f89a84ff`-en a
munkafa tiszta, a scope-audit és a saját gate-futtatás is ezt igazolja).

## Megállapítások

### M1 — MINOR — a baseline-doksi három mért fájlszáma eltér a tényleges számtól

- **Fájl:** `docs/baseline/epic-09-community-start.md:44,48`
- **Megfigyelés:** a §1.1 táblázat `lib/features/auth/` teszt-fájlszámot
  `7`-nek írja, a tényleges (`find test/features/auth -name '*.dart' |
  wc -l`) `4`; a `lib/features/learn/` sort `24`/`34`-nek írja, a
  tényleges `25`/`32`. A dokumentum saját módszertana explicit kimondja:
  "A mért számok `find … | wc -l` alapján vannak… A kód és a táblázat
  eltérése esetén a kód a mérvadó" — tehát az eltérés nem BLOCKER (a kód
  a forrás, és egyetlen acceptance-cella sem a baseline-táblázat
  konkrét számára épül), de a dokumentum kimondott CÉLJA ("hogy a
  későbbi körök ne találgassanak") pontosan azt a fajta pontos
  mérést ígéri, amit ez a három sor nem teljesít.
- **Ajánlás:** a Kör 2 pre-flightja frissítse a három sort a tényleges
  `find`-kimenetre, mielőtt a baseline-ra támaszkodna; nem blokkolja
  ezt a mergét (dokumentum-only, nincs gate-hatás, A1–A5 egyike sem
  érinti).

### N1 — NOTE — a négy alkapcsoló AND-szemantikája még csak dokumentált, nem kódolt

- **Fájl:** `lib/app/config/feature_flags.dart` (a négy sub-flag doc-commentje)
  + ADR 0395 Döntés 6. pont
- **Megfigyelés:** `communityWritesEnabled`/`communityMediaEnabled`/stb. a
  mai kódban FÜGGETLENÜL olvasódik `communityEnabled`-től (ez helyes és
  szándékos — lásd A2 fent), de a hívó oldali AND-kapcsolást
  (`communityEnabled && communityWritesEnabled`) még semmilyen kód nem
  valósítja meg, mert hívó még nincs. Ez nem hiba ebben a körben (a
  brief §1 kifejezetten "alkalmazáskód-változtatás nélkül" kört ír elő)
  — csak jegyzet a Kör 5+ implementer számára, hogy a kapcsolást a
  hívó oldalon kell megvalósítania, a flag-eket önmagukban nem.

## Végszó

A kör pontosan azt szállította, amit a brief + ADR 0395 előírt:
alkalmazáskód-változtatás nélkül, öt önálló, production-fail-closed
feature flag mindkét oldalon, egy nyolc kategóriát lefedő threat model,
egy mért baseline (egy MINOR pontossági hibával) és egy backend
readiness placeholder. Gate zöld (saját újrafuttatással megerősítve),
scope tiszta, §6.1 szabotázs-próba reprodukálva. **Merge-re javasolt.**
