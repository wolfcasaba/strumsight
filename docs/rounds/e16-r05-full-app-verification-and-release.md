# E16-R05 — A teljes app működésének mérése és kiadható build

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
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
  "docs/release/full-app-verification.md",
  "docs/rounds/e16-r05-full-app-verification-and-release.md",
]
gate_tests = [
  "test/e2e/full_app_walkthrough_test.dart",
  "test/tooling/placeholder_wiring_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/tooling/screen_reachability_test.dart",
]
native_gate = true
```

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

- A sáv indulásakor a routerben **12** placeholder-konstrukció és **8** `TODO(E08-R30)` volt; ezeket az `E16-R01`/`R02` zárja.
- `test/e2e/` a Ch12 Kör 11 óta létezik (determinisztikus harness, fake óra és globális hálózat-tiltás).
- A képernyő-elérhetőség mérője (`tool/check_screen_reachability.dart`) az `E15-R03` terméke.
- A capability-besorolások az `E16-R03` `docs/release/capability-rollout.md` táblájában élnek.

## 3. Scope

**Benne van:** `tool/check_placeholder_wiring.dart` — statikus mérő: a `lib/app/routing/**` és a kompozíciós rétegek NEM adhatnak át konstans `0`/`{}`/`null` értéket olyan képernyő-paraméternek, aminek van valós forrása; a kimenet gépileg olvasható · `test/tooling/placeholder_wiring_test.dart` · `test/e2e/full_app_walkthrough_test.dart` — a „BE" besorolású capabilityk core útjainak végigjárása a determinisztikus harnessen (indítás → Today → gyakorlás → eredmény → Library → Progress → Profile), minden lépésnél állítva, hogy a képernyő NEM placeholder-adatot mutat · `docs/release/full-app-verification.md` — a mért eredmény, a nyitott tételek gazdával és körrel.

**NINCS benne (tilos):**

- `lib/**` módosítás (a záró kör MÉR, nem javít).
- Új capability bekapcsolása.
- A felismerés pontosságának mérése (Chapter 14).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_placeholder_wiring.dart` | ÚJ — a placeholder-mérő |
| `test/tooling/placeholder_wiring_test.dart` | a mérő cellái |
| `test/e2e/full_app_walkthrough_test.dart` | a teljes bejárás |
| `docs/release/full-app-verification.md` | ÚJ — a mért eredmény |

**Tilos zóna:** `lib/**` · `backend/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A „működik" állítás MÉRÉSBŐL jön

**NEM elfogadható gyengítés:** „a képernyő megjelenik" mint bizonyíték — a cella az ADATOT is állítja.

### 5.2 A talált placeholder LELET, nem javítandó munka

**NEM elfogadható gyengítés:** gyors javítás a `lib/`-ben, ami elrejtené, mit mért a záró kör.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A router és a kompozíciós rétegek placeholder-mentesek (a mérő 0 leletet ad) | `placeholder_wiring_test.dart` |
| A2 | A teljes bejárás minden lépése valós adatot vagy EXPLICIT üres állapotot mutat | `full_app_walkthrough_test.dart` |
| A3 | A „BE" besorolású capabilityk core útjai végigjárhatók hálózat nélkül | `full_app_walkthrough_test.dart` |
| A4 | Minden elérhető képernyő szerepel a bejárásban vagy nevesített indokkal kimarad | `screen_reachability_test.dart` + a dokumentum |
| A5 | A dokumentum minden nyitott tétele gazdát és kört nevez | `docs/release/full-app-verification.md` |
| A6 | ZÖLD teljes CI-futás a kör-branchen, telepíthető APK-artefaktummal | orchesztrátor-dispatch linkje a §10-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A bejárás csak rendereli a képernyőket, az adatot nem állítja | A2 |
| Egy elérhető képernyő kimarad a bejárásból indok nélkül | A4 |
| A placeholder-mérő csak a routert nézi, a kompozíciós rétegeket nem | A1 |
| A dokumentum „hamarosan" bejegyzést tartalmaz gazda nélkül | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vezess be ideiglenesen egy konstans `0`-t az egyik kompozíciós providerben, futtasd a §7 gate-et → az **A1** és **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/e2e/full_app_walkthrough_test.dart test/tooling/placeholder_wiring_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart
```

A placeholder-mérő közvetlen futtatása (a kimenet a §10-be):

```bash
dart run tool/check_placeholder_wiring.dart --format table
```

A teljes suite + property gate + APK a CI-ban fut (ADR 0053); a dispatch és a kiadás-link az orchesztrátoré.

## 8. Implementációs sorrend

1. `tool/check_placeholder_wiring.dart` + a teszt-párja.
2. `test/e2e/full_app_walkthrough_test.dart` a MÉRT elérhető halmazra és a „BE" capabilitykre.
3. A leletek gyűjtése (NEM javítása).
4. `docs/release/full-app-verification.md`.
5. A valódi-sértés próba a §10-be; a CI-dispatch és az APK-link az orchesztrátortól.

## 9. Kockázatok

- **Kozmetikai zárás.** „Megjelenik" ≠ „működik" (A2).
- **Részleges bejárás.** Kimaradó képernyő elrejt egy bekötési hiányt (A4).
- **Javítás-csábítás.** A talált placeholder a felelős feature körébe tartozik (§5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
