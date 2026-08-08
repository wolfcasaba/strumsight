# Dataset manifest — vision guitar/neck detection

**Státusz:** véglegesített governance-manifest (E05-R30, 2026-08-08). Nincs a repóban consentelt
gitárkép-adat, és ez a kör nem is gyűjt — a manifest a jövőbeli dataset
kötelező kategória-szerkezetét és consent-szabályait rögzíti, hogy egy
későbbi aktiváló kör ([ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)
Döntés 2/4) ne a tiltott zónába csússzon, hanem ezen a vázon dolgozzon.

A dokumentum forrásai:

- SDD Ch6 §31.1 ([`docs/sdd/06-epic-05-computer-vision.md`](../../docs/sdd/06-epic-05-computer-vision.md)
  — dataset-kategóriák) és §31.2 (consent);
- [ADR 0187](../../docs/adr/0187-vision-automatic-guitar-geometry-detection.md)
  Döntés 3 — „consent kötelező, forrás szerint korlátozott";
- jelenleg mért korlát: ebben a környezetben **nincs consentelt gitáros
  képanyag** (E05-R17 brief §2).

## 1. Kötelező kategóriák (SDD §31.1)

Minden kategóriát külön sorként kell vezetni, és csak az a kategória
szerepelhet itt, amelyre **explicit, dokumentált hozzájárulás** van.
Az `Státusz` mező induláskor egységesen `PENDING_COLLECTION`, és csak
azután válthat `COLLECTED`/`ARCHIVED` értékre, ha a §2 consent-rekord
teljes.

| Kategória | Rövid cél | Státusz | Forrás | Jogalap | Tervezet méret | Megjegyzés |
|---|---|---|---|---|---|---|
| Synthetic geometry fixture | a harness szintetikus önellenőrzése (NEM valós adat) | `READY` | belső, `evaluate_geometry_baseline.py` kimenete | saját, nincs személyes adat | n/a | nem emberi felvétel, ezért nem kell consent — de NEM használható a production küszöb (§2) mérésére |
| Consentelt belső fejlesztői videó | nut/bridge anchor és neck polygon ground truth | `PENDING_COLLECTION` | belső, dokumentált contributor | aláírt contributor agreement | ≥ 3 gitár × ≥ 2 fényhelyzet × ≥ 1 személy | csak a contributor saját hangszerén, saját kezével |
| Különböző gitártípusok | acoustic dreadnought, classical, electric solid-body, elektro-akusztikus, bass | `PENDING_COLLECTION` | contributor vagy jogtiszta belső tulajdon | contributor agreement VAGY belső asset-nyilvántartás | ≥ 3 gitár, különböző scale-length és nyakszélesség | az ADR 0187 minimum-korlátja: ≥ 3 gitár |
| Bal- és jobbkezes játék | mindkét handedness külön split | `PENDING_COLLECTION` | contributor | contributor agreement | mindkét csoportból ≥ 1 személy | az ADR 0187 minimum-korlátja: mindkét kezesség |
| Eltérő bőrtónus és ruházat | a tracker ne legyen kontraszt-függő | `PENDING_COLLECTION` | contributor | contributor agreement | ≥ 4 személy, dokumentált kategória-eloszlás | a §31.1 „eltérő bőrtónusok és ruházat" sora; csak a kategória-eloszlásig, demográfiai címke NÉLKÜL |
| Eltérő fények | beltéri nappali / beltéri mesterséges / gyenge fény / kültéri borús | `PENDING_COLLECTION` | contributor | contributor agreement | ≥ 2 fényhelyzet | az ADR 0187 minimum-korlátja: ≥ 2 fényhelyzet |
| Front és rear camera | elülső és hátsó kamera | `PENDING_COLLECTION` | contributor | contributor agreement | ≥ 1 eszköz, mindkét kamera | a §31.1 sora |
| Ülő és álló testtartás | álló (széken ülve, illetve állva) | `PENDING_COLLECTION` | contributor | contributor agreement | mindkét testtartás, azonos gitár | a §31.1 sora |
| Akusztikus és elektromos gitár | hangszer-család diverzitás | `PENDING_COLLECTION` | contributor vagy belső asset | contributor agreement VAGY belső asset | mindkét család | a §31.1 sora |
| Különböző nyakszín és háttérkontraszt | a polygon-érzékelés háttér-függetlensége | `PENDING_COLLECTION` | contributor | contributor agreement | ≥ 3 kontraszt-szint | a §31.1 sora |
| Occlusion és blur edge-case | ujj-takarás, motion blur, gyenge fény | `PENDING_COLLECTION` | contributor, szándékosan produkált | contributor agreement | ≥ 1 személy, ≥ 3 edge-case | a §31.1 sora |
| Helyes és szándékosan változtatott technikai mozgások | a tracker ne csak „happy path" -on működjön | `PENDING_COLLECTION` | contributor | contributor agreement | ≥ 1 személy, ≥ 2 technikai szcenárió | a §31.1 sora |

### 1.1 Minimum eval-korpusz (ADR 0187 Döntés 2 utolsó sora)

A fenti kategóriák kombinációjából összeálló eval-korpusz **nem** minősül
elfogadhatónak, amíg egyszerre nem teljesül:

- ≥ **200 frame** (a harness anchor error és failure rate méréséhez);
- ≥ **3 különböző gitár**;
- ≥ **2 fényhelyzet**;
- **mindkét kezesség**.

Ennek hiányában a harness kimenete az ADR 0187 szabályai szerint
`NO_DATA`/`insufficient_corpus` státuszú, és a `production-candidate`
minősítés nem javasolható.

## 2. Consent-rekord kötelező mezői (SDD §31.2)

Minden `COLLECTED` státuszú kategóriához az alábbi kötelező consent-rekord
tartozik (a manifest itt csak a struktúrát rögzíti, a tényleges rekordok a
későbbi aktiváló körben jönnek létre):

| Mező | Tartalom | Példa |
|---|---|---|
| `contributor_id` | anonimizált, stabil azonosító (nem természetes személy-név) | `c-0007` |
| `signed_at` | aláírás UTC timestamp | `2026-XX-XXTHH:MM:SSZ` |
| `purpose` | rövid, egyértelmű cél | „guitar neck geometry detector eval, on-device only" |
| `retention_days` | meddig tárolható | pl. `365` |
| `access_scope` | ki fér hozzá (személy/szerep) | pl. „ci-rig, vision eng" |
| `deletion_procedure` | hogyan törölhető | pl. „egy contributor = egy törlési kulcs, 24 órán belül" |
| `publication_opt_in` | `true`/`false` | `false` (kutatási anyag nem kerül publikálásra) |
| `model_training_opt_in` | `true`/`false` | `false` (csak kiértékelés; training külön, későbbi kör) |
| `annotator_privacy_guideline` | mutató a kötelező annotátor-kezelési/-terjesztési szabályzatra (SDD §31.2 7. elem) | pl. „annotator-handling-v1: nyers frame-eket csak a kijelölt annotátor nézheti, nem másolható, nem továbbítható, a session végén törölve" |

A consent-rekordot az adatgyűjtés **megkezdése előtt** rögzíteni kell;
utólagos módosítás csak a contributor aláírásával lehetséges.

## 3. Tiltott források listája (kötelező, a §6 acceptance #2 cellája)

A kör-brief §6.1 (mérce-mátrix) második sora szerint a manifest
**TILOS** listájának hiánya a `--self-test` PIROSRA váltását okozza.
A tiltott források:

1. **Web-scrapelt vagy más módon ismeretlen jogállású gitárkép.**
   Sérti az SDD §31.2 consent-szabályt és a jelenlegi ADR 0187
   Döntés 3-at. Bármely, harmadik fél által közzétett, engedély nélküli
   kép (weboldal, közösségi média, GitHub repo, stock-photo oldal,
   licenc nélküli oktatóvideó-thumbnail) kizárt — függetlenül attól,
   hogy a kép „jól néz ki" demoanyagnak.
2. **Harmadik féltől licenc nélkül átvett bármilyen vision dataset.**
   Ide tartozik minden olyan „public benchmark" vagy „GuitarSet"-szerű
   anyag, amelyhez nincs a StrumSight repojában (vagy a contributor
   saját, aláírt megállapodásában) dokumentált, a célra szóló
   felhasználási engedély.
3. **A contributor által korábban, más célra gyűjtött felvétel,
   kiterjesztett célra utólag felhasználva.** A consentet kifejezetten
   erre a kutatásra kell újra kérni; a korábbi hozzájárulás nem
   terjeszthető ki.
4. **Saját eszközzel készített, de nem dokumentált felvétel.** Az
   előfeltétel a dokumentált consent, nem a saját tulajdon — ha nincs
   aláírt contributor agreement, a felvétel akkor sem használható.
5. **Bármilyen, a contributor személyét azonosító vagy visszafejthető
   metaadatot tartalmazó kép.** Arc, tetoválás, egyedi szoba-
   részlet, monitor-szöveg, vagy bármi, ami a contributor személyét
   a képből rekonstruálhatóvá teszi — kivéve, ha a contributor az
   azonosíthatóságot külön, kifejezetten engedélyezte. A preferált
   alapértelmezett a **maszkolt, blurring-elt** kép, az arc- és
   tetoválás-régióra.
6. **Gyermeket ábrázoló kép.** A jelenlegi contributor agreement
   kizáró klauzulája; a kutatás kizárólag felnőtt, saját jogú
   contributorokra terjed ki.
7. **Felhőalapú (hosztolt) detekciós API-ból származó kimenet.** Sérti
   az ADR 0178 §Döntés 1-et („a kamerakép feldolgozása kizárólag a
   készüléken történik"); a detektor-eval offline, lokális modellel
   történik.

## 4. Adatkezelési határ

A manifest **NEM** rögzíti a tényleges felvételeket — a felvételek
maguk a tilos zóna részei (a jelenlegi kör nem gyűjt adatot, lásd a
brief §3). A manifest kizárólag:

- a kategória-vázat;
- a consent-rekord mezőszerkezetét;
- a tiltott források listáját;
- a minimum-korlátokat.

rögzíti, hogy a későbbi aktiváló kör a struktúrát örökölhesse.

## 5. Referenciák

- [ADR 0187](../../docs/adr/0187-vision-automatic-guitar-geometry-detection.md)
  — kategória-korlát, consent-kötelezettség, tiltott források;
- [ADR 0181](../../docs/adr/0181-vision-manual-calibration-fallback.md)
  — a manual kalibráció a production út, az adatgyűjtés célja kizárólag
  a detektor minősítése, nem a manual út pótlása;
- [ADR 0179](../../docs/adr/0179-vision-capability-aware-feedback.md)
  — a `notObservable` a helyes kimenet, ha a mérés nem megbízható;
- [ADR 0178](../../docs/adr/0178-vision-privacy-by-default.md) — a
  feldolgozás kizárólag on-device;
- SDD Ch6 §31 ([`docs/sdd/06-epic-05-computer-vision.md`](../../docs/sdd/06-epic-05-computer-vision.md))
  — a kategória-lista és a consent-mezők forrása.

## 6. Evaluation-harness szerződés (E05-R30)

Az [`evaluate_vision_metrics.py`](evaluate_vision_metrics.py) kizárólag
privacy-safe fixture-összefoglalókat olvas JSONL formátumban. Nem olvas,
nem ír és nem logol raw frame-et, képet, videót vagy biometrikus landmark
idősort. Egy rekord szerződése:

```json
{
  "fixture_id": "quality-low-light-001",
  "metric": "quality",
  "expected": true,
  "observed": true,
  "negative_cue_expected": false,
  "negative_cue_emitted": false
}
```

Az engedélyezett `metric` értékek: `hand_tracking`, `quality`, `geometry` és
`metric_policy`. Az `expected`/`observed` a fixture ground-truth és a
kiértékelt lokális eredmény boolean összefoglalója. A két `negative_cue_*`
mező vagy együtt szerepel, vagy egyik sem; a *hamis negatív cue* olyan sor,
ahol a cue ki lett adva, de a ground-truth szerint nem volt indokolt.

### 6.1 False-feedback küszöb és besorolás

Az E05-R30 production-safety küszöb **1%** (`0.01`), a határ inkluzív. A
valós eszközös benchmark célértéke ettől függetlenül továbbra is **0**
(`docs/manual-testing/vision-performance-benchmark.md` §2.8): a 1% nem
teljesítménycél, hanem a legszigorúbb nemnulla kiadási korlát, amelyen a
kötelező 0%/1%/2% matrica értelmezhető. Száz, függetlenül review-zott
fixture-ben ez legfeljebb egy hamis cue.

| Mért arány | Kimenet |
|---:|---|
| 0.00 | `production-supported` |
| 0.01 | `production-supported` (inkluzív határ) |
| 0.02 | `experimental` |

Az `experimental` besorolás a megengedett fail-closed kimenet. A küszöböt
utólag, egy mért érték kedvéért felemelni tilos. Üres bemenet vagy olyan
korpusz, amely nem tartalmaz cue-lehetőséget, `NO_DATA`/`experimental`;
semmilyen szintetikus self-test nem promotál valós termékképességet.

### 6.2 Futtatás és evidence-határ

```bash
python3 ml/vision/evaluate_vision_metrics.py --self-test
python3 ml/vision/evaluate_vision_metrics.py --input /path/to/fixture-summaries.jsonl
```

A `--self-test` a `NO_DATA`, 0%, 1% és 2% cellákat bizonyítja. Production
besoroláshoz ezen felül a §1.1 minimum-korpusz, a §2 consent-rekord, a SDD
§32.3 kézi review-ja és a device matrix valós mérési evidence-e is kell.
Mivel E05-R30-ban nincs consentelt korpusz, a manifest minden nemszintetikus
kategóriája változatlanul `PENDING_COLLECTION`, és egyik capability sem válik
ettől a harness-től élessé.
