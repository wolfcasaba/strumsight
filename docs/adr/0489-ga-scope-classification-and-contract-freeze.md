# ADR 0489 — GA-scope: zárt besorolási készlet, a fán FELOLDHATÓ bizonyíték-hivatkozás, és a nevesített feltételhez kötött contract freeze

- **Státusz:** Elfogadva
- **Dátum:** 2026-09-02
- **Kör:** E12-R28 (Chapter 12 — Release Roadmap, Sprint Planning & Final Integration)
- **Kontextus-ADR-ek:**
  [0306](0306-plan-preview-presentation-activation-boundary.md) (plan-preview
  aktiválási határ — egy preview-funkció a core útra nem hathat; ez az ADR ezt a
  mintát általánosítja a teljes GA-scope-ra),
  [0446](0446-feature-flag-registry-and-emergency-kill-switch.md) (a MÉRT 40-es
  flag-katalógus és a kill switch — a besorolás alanyai innen jönnek),
  [0486](0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
  (béta-terjesztés és redaktált diagnosztika),
  [0488](0488-release-candidate-assembly-and-approval-gate.md) (RC-összeállítás,
  fail-closed eszköz + `python3` mint egyetlen külső bináris a gate-tesztben),
  [0052](0052-ci-apk-automerge-session-per-round.md) (a zöld kapu),
  [0112](0112-self-healing-pipeline.md) (a merge UTÁNI orchesztrátor-lépés)

## Kontextus

A Chapter 12 eddigi körei leszállították a kiadási előfeltételek darabjait: a
blocker-listát (`E12-R01`), a flag-katalógust (`E12-R05`, ADR 0446), a
béta-terjesztést (`E12-R22`, ADR 0486), az RC-összeállítást (`E12-R25`, ADR 0488) és a
Closed Beta indítási **konfigurációját** (`E12-R27`). Ami MA nincs: egyetlen
dokumentum, amely capabilityenként kimondja, hogy az adott képesség a GA-ban
**benne van-e**, és ezt a kimondást gép ellenőrzi.

A kör pre-flightja a fán ÚJRAMÉRTE a besorolás előfeltételeit (`main @ 4bdedfbc`):

1. **A Closed Beta NEM indult el.** `docs/beta/closed-beta-launch.md:3` —
   „Status: NOT launched"; a dokumentum §5 „Human launch field" mezője
   kipipálatlan és kitöltetlen, és az `E12-R27` HANDOFF-bejegyzése ezt kimondja
   („**A béta NEM indult el.**"). A béta indítása az `E12-R27` szerint **emberi
   kapu**, amelyet az automatizálás szándékosan nem hajt végre. **Tehát a fán ma
   nulla béta-mérési adat van** — a `docs/beta/` tartalma eljárás (triage-kategóriák,
   napi sablon, beleegyezés, cohort-profil), nem terepi mérés.
2. **A besorolás alanyainak halmaza MÉRHETŐ:** a `docs/beta/cohort-profiles.yaml`
   mindkét cohortja **16** flag-kulcsot rendel hozzá (`python3 -c "import yaml; …"`
   → `internal 16`, `closed_beta 16`), és mind a 16 kulcs a MÉRT 40-es
   `lib/core/feature_flags/feature_flag_registry.dart` katalógusban van (7 `high`,
   18 `medium`, 15 `low` kockázat).
3. **Nyitott P0 van.** `docs/release/blockers.md` — `R-SIGN-01` **P0**, owner-köre
   (`E12-R07`) `pending`; mellette öt **P1** (`R-VER-01`, `R-PRIV-01`, `R-SEC-01`,
   `R-STAGE-01`, `R-STORE-01`), mind nyitva.
4. **A core út gépi leírása létezik:** az `E12-R11` (`done`, ADR 0452) e2e-cellái —
   `test/e2e/first_practice_offline_test.dart`, `returning_user_restart_test.dart`,
   `upgrade_migration_test.dart`, `resource_coexistence_test.dart`.
5. **A profil-fájl parszolásának precedense kötött:** `tool/release/verify_beta_profile.py`
   ugyanezt a YAML-t PyYAML-lel olvassa (kemény függőség, CI-ben zölden futtatva);
   a fán mérve `PyYAML 6.0.1`.

Ebből következik, hogy a GA-scope MA **megalkotható és gépileg ellenőrizhető**, de
**nem béta-adatból** — és hogy a legnagyobb kockázat nem a hiányzó adat, hanem az,
hogy a hiányzó adat helyére **kitalált** adat kerül.

## Döntések

### D1 — A besorolás alanyainak halmaza a cohort-profil flag-kulcsainak halmaza, és ZÁRT

A GA-scope pontosan azokra a capabilityekre vonatkozik, amelyeket a
`docs/beta/cohort-profiles.yaml` nevesít (ma **16** kulcs). Minden kulcs **pontosan
egy** besorolást kap. Hiányzó besorolás, kettős besorolás, vagy a profilban nem
létező kulcs besorolása egyaránt **nem-nulla kilépés**.

**NEM elfogadható gyengítés:** „a fel nem sorolt capability alapértelmezésben
`postponed`". Egy hallgatólagos default pontosan azt a vákuumot hozza vissza,
amit az L566 fail-OPEN hibaosztálya leír: ami nincs kimondva, az nem hiányzik,
hanem „rendben van".

### D2 — A besorolási készlet zárt: `ga` | `preview` | `disabled` | `postponed`

Négy érték, más nem fogadható el. Jelentésük:

| Érték | Jelentés |
|---|---|
| `ga` | a GA-ban benne van, a core úton támaszkodni lehet rá |
| `preview` | szállítjuk, de a core út NEM támaszkodhat rá (D5) |
| `disabled` | a GA-ban ki van kapcsolva — a flag MINDEN cohortban `false` (D4) |
| `postponed` | GA után, nevesített feloldó feltétellel |

**NEM elfogadható gyengítés:** szabad szöveges vagy összetett besorolás
(`ga (részben)`, `preview/ga`) — a gépi cella pontos egyezésre mér.

### D3 — Minden besorolás bizonyíték-hivatkozása a fán FELOLDHATÓ útvonal

Minden besoroláshoz kötelező egy `evidence` hivatkozás, amely egy **létező**
repó-relatív útvonalra mutat; a `verify_ga_scope.py` a fájl **létezését**
ellenőrzi, és nem-nulla kóddal áll meg, ha nem oldható fel.

Ez a kör anti-fabrikációs őre. Béta-adat ma nincs (Kontextus 1.), tehát **nem
lehet** béta-mérésre hivatkozni: nincs olyan fájl, amire a hivatkozás feloldódna.
A hivatkozható bizonyíték a fán mérhető anyag — a flag-katalógus, a
cohort-profil, a blocker-lista, a felismerési release-guard, az e2e-cellák, a
korábbi körök mérési riportjai.

**NEM elfogadható gyengítés:** „stabilnak tűnik", „a béta alapján jónak látszik",
vagy bármilyen forrás nélküli indoklás (brief §5.2). **NEM elfogadható
gyengítés** az sem, hogy a hivatkozás egy MOST létrehozott, tartalmatlan
placeholder-fájlra mutasson.

### D4 — `disabled` ⇒ a flag MINDEN cohortban `false`; az irány a profiltól a scope felé mér

Ha egy capability besorolása `disabled`, akkor a `cohort-profiles.yaml` MINDEN
cohortjában `false` kell legyen. Eltérés → nem-nulla kilépés, a cohort és a kulcs
megnevezésével.

Az ellenőrzés iránya kötött: a **profil** a flag tényleges állapotának forrása, a
scope-dokumentum az állítás. Egy állítás, amit a profil cáfol, a scope hibája.

**NEM elfogadható gyengítés:** a `disabled` besorolás „szándék"-ként olvasása,
amit a profil később követ.

### D5 — Preview capability NEM lehet a core út kötelező eleme (ADR 0306 általánosítása)

A `ga-scope.md` nevesíti a core út lépéseit, minden lépéshez a D3 szerint
feloldható bizonyítékkal (az `E12-R11` e2e-cellái, Kontextus 4.), és megjelöli,
mely capabilityre támaszkodik a lépés. Minden core-úthoz szükségesnek jelölt
capability besorolása **`ga`** kell legyen. `preview`/`disabled`/`postponed`
besorolású capability a core úton → nem-nulla kilépés.

**NEM elfogadható gyengítés:** „preview, de a Today-képernyő nélküle üres" — az
funkcionálisan GA (brief §5.1).

### D6 — A contract freeze minden sora NEVESÍTETT feloldó feltételt hordoz

A `contract-freeze.md` minden befagyasztott contractjához tartozik egy feloldási
feltétel, amely **ellenőrizhető eseményt** ír le. Üres, hiányzó vagy tartalmatlan
feltétel → nem-nulla kilépés.

**NEM elfogadható gyengítés:** „szükség esetén módosítható", „a csapat döntése
alapján", „későbbi körben újratárgyalható" (brief §5.3) — ezek nem események. A
gépi cella ezt a három megfogalmazást (és a velük azonos alakúakat)
**tiltólistával** is fogja, nem csak a nem-üresség mérésével: a nem-üresség
önmagában fail-OPEN mérce.

### D7 — Nyitott P0/P1 blocker mellett a GA-scope állapota kimondottan NEM KÉSZ

A `verify_ga_scope.py` beolvassa a `docs/release/blockers.md` súlyossági
oszlopát. Ha van nyitott **P0** vagy **P1** sor, a `ga-scope.md` fejlécének
explicit **nem-kész** állapotot kell hordoznia; a „GA-kész" állítás ilyenkor
nem-nulla kilépés.

Mérve MA: `R-SIGN-01` P0 + öt P1 nyitva (Kontextus 3.) — a kör tehát **NEM-KÉSZ**
állapotú GA-scope-ot szállít, és ez a dokumentum helyes állapota, nem hiányossága.

**NEM elfogadható gyengítés:** a nem-kész állapot lábjegyzetbe rejtése, vagy a
blocker-lista „lezártnak" olvasása az owner-kör `pending` státusza mellett.

### D8 — A béta MÉG NEM FUTOTT LE: a hiánya MÉRT tény, nem pótolható becsléssel

A `docs/release/beta-findings.md` ebben a körben **nem** terepi triage-összefoglaló
— a fán nincs mihez. A fájl azt rögzíti, hogy a Closed Beta a mérés pillanatában
nem indult el (a D3 szerint feloldható hivatkozással a
`docs/beta/closed-beta-launch.md`-ra), felsorolja, MELY bizonyítékforrásokra épül
helyette a besorolás, és kimondja, hogy melyik besorolás **melyik béta-mérés**
hatására kerül újramérésre.

Amely capability GA/preview besorolása kizárólag béta-adatból következne, az
**`postponed`**, feloldó feltételként a béta lefutásával — nem `ga`, nem
`preview`, és nem becslés.

**NEM elfogadható gyengítés:** kitalált top-issue lista, kitalált funnel-számok,
kitalált tesztelői létszám, vagy bármely olyan állítás, amely csak akkor lenne
igaz, ha a béta lefutott volna. A D3 útvonal-feloldása ezt gépileg is fogja: egy
nem létező béta-riportra mutató hivatkozás nem-nulla kilépés.

### D9 — Fail-closed parszer, `python3`-only gate, és minden cella PIROS a saját javítása előtt

1. A `verify_ga_scope.py` a `ga-scope.md`/`contract-freeze.md` táblázatait
   **fail-closed** olvassa: ami nem illeszkedik a várt alakra, az **hiba** a sor
   számával, nem néma átugrás (L566). A cohort-profil PyYAML-lel olvasandó — a
   testvér `verify_beta_profile.py` precedense, ugyanaz a fájl, ugyanaz a parszer
   (Kontextus 5.).
2. Az eszköz a Python standard library + `yaml`; más külső csomag nincs. A
   gate-teszt egyetlen külső binárisa a `python3` (ADR 0488 D6 / ADR 0447 D5).
3. Minden acceptance-cella a saját javítása ELŐTTI eszközzel **PIROS** (L563). A
   kör §10-e dokumentálja a valódi-sértés próbát (brief §6.1: egy `disabled`
   capability flagje a cohort-profilban `true`-ra állítva → az **A2** cella
   pirosra vált → visszaállítás).

## Következmények

- **Pozitív:** a GA-scope kimondása gépi mércét kap; a „vélemény-alapú scope"
  kockázata (brief §9) nem retorikával, hanem útvonal-feloldással van zárva (D3);
  a rejtett GA (D5) és az örök freeze-kivétel (D6) is cella, nem szándék.
- **Negatív / vállalt ár:** a besorolás MA a fán mérhető bizonyítékra épül, nem
  terepi tapasztalatra — tehát kevesebbet tud, mint egy béta utáni scope. A D8 ezt
  kimondja és nevesített újramérési feltételhez köti, a D7 pedig nem engedi
  „GA-késznek" olvasni.
- **Nyitott:** a capability-halmaz a cohort-profil 16 kulcsához van kötve (D1),
  miközben a flag-katalógus 40 bejegyzést tartalmaz. A fennmaradó 24 flag ma nincs
  cohorthoz rendelve, tehát GA-besorolást sem kap — ha egy jövőbeli kör bővíti a
  cohort-profilt, a GA-scope-ot vele EGYÜTT kell bővíteni; a D1 zárt halmaza ezt
  a bővítést nem-nulla kilépéssel kényszeríti ki, nem csendes hiánnyal.

## A visszavonás feltétele

Felülvizsgálandó, ha a Closed Beta ténylegesen lefut és terepi triage-adatot
termel: ekkor a D8 szerinti újramérés esedékes, és a D3 bizonyíték-hivatkozásai
kiegészülhetnek a béta-riportokra mutató, akkor MÁR feloldható útvonalakkal. A D1
zárt halmaza akkor is kötelező marad.
