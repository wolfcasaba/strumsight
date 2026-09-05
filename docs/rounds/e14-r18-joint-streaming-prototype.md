# E14-R18 — Streaming joint onset + direction prototípus

- **Státusz:** READY — mért alap: `main @ 368cd179` (a pre-flight 2026-09-05-i
  ÚJRAMÉRÉSE; az eredeti, 2026-08-20-i megírás alapja a `6371aa3` volt, az
  azóta bekövetkezett sodródást a §0.0/R11 méri ki tételesen)
- **Típus:** Chapter 14, Kör 18 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R18`
- **Branch:** `<motor>/e14-r18-joint-streaming-prototype`
- **Előfeltétel:** `E14-R08` (grouped harness) és `E14-R17` (referencia-audit,
  hogy tudjuk, mi vehető át és mi nem) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0370` — **a Claude írja meg (go/no-go), a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `ml/honest_eval.py`
> fejlécét (három-utas split, LOGO CV, cluster-bootstrap, kalibráció) — a
> prototípus mérése ezt a szigort örökli. Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió (orchestrátor, 2026-09-05, `main @ 368cd179`)

A brief 2026-08-20-án készült, `main @ 6371aa3` olvasata alapján; azóta a két
előfeltétel-kör (`E14-R08`, `E14-R17`) landolt. Az alábbi pontokat a pre-flight
MÉRÉSE javította. A revízió az orchestrátor saját hatásköre (ADR 0087 §2) — a
lista-tágítás nem: az **`allowed_paths` és a `gate_tests` VÁLTOZATLAN**.

**R1 — Az ADR-szám `0370` → `0517`.** A foglaló
(`tools/round-slots.py reserve-adr --round E14-R18`) a `0517`-et adta; a fán a
legmagasabb szám `0512`. Az **ADR 0517 meg van írva és commitolva** — az
implementer NEM nyúl a `docs/adr/`-hoz. A §5 döntései az ADR 0517 D1–D8-ra
hivatkoznak.

**R2 — S12 (brief-lint, strict): a §7 gate-parancs nem tükrözte a `gate_tests`
listát.** A `gate_tests` a konkrét fájlt sorolja, a §7 csak a könyvtárat adta
át. A §7 javítva: a gate a `gate_tests` útvonalát kapja argumentumként. Indok: a
metaadatot a scope-audit és a CI-terv olvassa, a kaput viszont a PARANCSSOR
futtatja — a kettő szétcsúszása néma.

**R3 — A tanító-környezet MEGVAN; a `blocked` ezen a címen HAMIS jelzés
volna.** Mérve: `/home/ubuntu/tf-venv/bin/python -c "import tensorflow"` →
**TF 2.21.0**. A rendszer `python3`-ban **nincs** TensorFlow
(`ModuleNotFoundError`; numpy `1.26.4`, a venv-é `2.5.1`). Ezért:

- a prototípus Python-oldala KIZÁRÓLAG a `/home/ubuntu/tf-venv/bin/python`
  interpreterrel futtatható, és a README + a report ezt a teljes útvonalat
  írja ki;
- a §7 `python3 -m pytest ml -q` a RENDSZER-interpreterrel fut, és zöld kell
  maradjon — ma **115 passed / 21,23 s** a mért kiindulás. A kör új Python
  moduljai nem `test_*.py` nevűek, tehát a pytest nem gyűjti be őket; ha
  bármelyik új modul import-időben TensorFlow-t igényelne a gyűjtés során, az
  ezt a mércét pirosra vinné.

**R4 — Az `ml/data/klangio` korpusz HORDOZ irány-igazságot.** Mérve a 82
`.strums` fájlon: **7228 `D` / 4539 `U`**, összesen 11 767 esemény (= a
baseline manifest `eventCount`-ja), és **76 felvétel tartalmaz `U`-t**. Egy
joint down/up fej tehát ezen a korpuszon mérhető; a
`ml/klangio.py::parse_strums` ismeretlen irány-betűre `ValueError`-t dob.

**R5 — A legacy lánc irány- és latencia-száma ezen a korpuszon NEM létezik →
a 2. acceptance-pont átfogalmazva (ADR 0517 D6).** Mérve a merge-elt
`evaluation/recognition/baseline_manifest.json`-ban:
`metricBlocks.direction.status = "not-measured"` és
`metricBlocks.latency.status = "not-measured"` (utóbbi indoklása szó szerint:
„offline batch run … not a real-time on-device run"). Ami mérve VAN, az a
legacy **onset** oldal, korpusz-hash-sel horgonyozva
(`corpusSha256 = 4880face…5827`, 82 felvétel):

| Legacy onset (manifestből) | Érték | n |
|---|---:|---:|
| `tolerance25000us.f1` | 0,4042664942830592 | 19 748 |
| `tolerance50000us.f1` | **0,6739121651650438** | 16 411 |
| `tolerance100000us.f1` | 0,8520059795563816 | 14 207 |

Az „EGY tábla, azonos korpusz-hash" követelmény tehát így teljesül: az
evaluate script kiszámolja a korpusz hash-ét, és **egyeznie kell** a manifest
`corpusSha256` értékével — eltéréskor hiba, report nélkül. Legacy end-to-end
irány-számot MÉRTKÉNT közölni **tilos**; ha a report ad ilyen sort, az explicit
felső korlát, kiírt származtatással és `bound: "upper"` jelöléssel (ADR 0517
D6). A `direction: not-measured` indoklása a *Dart-oldali annotációs útra*
igaz — a report mondja ki, hogy a Python-oldali `.strums` irány-igazság ezt
mint korpusz-állítást cáfolja (R4).

**R6 — Az 5. acceptance-pont hármas cellája GÉPI ŐRT kap a `gate_tests`-ben.**
A Chapter 14 §7.2 mért Alpha küszöbei: **onset F1 @50 ms = 0,82**,
**end-to-end direction macro-F1 = 0,80**. A hármas cella (alatta / pontosan
rajta / fölötte) a Dart-oldali őrben, a fixture-ből épített változatokon fut. A
határértékek **LITERÁLOK**, nem aritmetika eredményei: mérve `python3`-mal
`repr(0.80) == '0.8'`, `0.80 >= 0.80 → True`, `0.79 >= 0.80 → False`,
`0.81 >= 0.80 → True` — az L637 csapdája (kerek tizedessel felírt „a küszöbön"
cella számolva pirosra megy) így nem áll fenn.

**R7 — A futási artefaktumok a repó fáján KÍVÜLre mennek (ADR 0517 D5).** Súly,
checkpoint, feature-cache és köztes kimenet kötelezően egy `--workdir` /
`--cache` argumentummal megadott, a repón kívüli útvonalra kerül (ADR 0369 D1
precedense). Ennek scope-oka is van: az `allowed_paths` egyetlen `.npz`-t vagy
bináris kimenetet sem enged, tehát bármi ilyen a repó fájában scope-sértés
volna.

**R8 — Számítási költség: a mérés dokumentáltan szűkített konfiguráción fut.**
Mérve a meglévő, ennél KISEBB (ablakos) modell tanítási logján
(`ml/train_live_3c.log`): ~44–84 s/epoch, 36 epoch ≈ **36 perc** ezen a boxon.
Egy keret-szintű joint fej ennél drágább. Ezért a prototípus konfigurációja
(modellméret, epoch-szám, batch, fold-szám) úgy választandó, hogy a teljes
dokumentált futás **≤ 20 perc** legyen, és a README + a report a konfigurációt
ÉS a mért wall-clockot kiírja. A headline szám EGY dokumentált grouped
spliten mérendő, nem a `honest_eval.py` teljes multi-seed sweepjén.

**Az implementer futtatási mintája (L104, a Bash-hívás 600 s-es plafonja
miatt):** ha egy futás 480 s-nél tovább tart, NEM egyetlen előtérben futó
hívásként indítod, hanem leválasztva, majd rövid hívásokkal nézed a logot:

```bash
setsid /home/ubuntu/tf-venv/bin/python ml/joint_prototype/train_prototype.py \
  --workdir /tmp/e14r18-work > /tmp/e14r18-train.log 2>&1 < /dev/null &
tail -5 /tmp/e14r18-train.log   # rövid, ismételt hívásokkal
```

**R9 — A Dart-oldali validátor ebben a körben a TESZTBEN él (ADR 0517 D8).**
Az `allowed_paths` egyetlen Dart fájlt enged, és az maga a teszt; `lib/` és
`tool/` tilos zóna, a §5.5 pedig szállítható artefaktumot sem enged. Ez
kimondott, határolt eltérés az L631 mintájától („a cella a SZÁLLÍTOTT belépési
pontot mérje") — ebben a körben nincs szállított belépési pont. A validáció
kézzel írt, séma-könyvtár függés nélkül (ADR 0354 D8 precedense). A
productizálás köre mozgatja `tool/` alá.

**R10 — Új fájl az `evaluation/recognition/**` alatt nem visz pirosra briefen
kívüli tesztet.** Mérve: nulla találat könyvtár-bejáró mintára (`Directory('evaluation…')`)
a `test/` és `tool/` fában; a `test/tooling/recognition_baseline_manifest_test.dart`
kizárólag a saját két fájlját olvassa. S11/S14 nem áll fenn.

**R11 — S15 (brief-lint, strict): a `main @ 6371aa3` mért alap ELMOZDULT —
mi maradt igaz, mi nem.** Mérve `git log 6371aa3..368cd179`: a lintelt fájl,
a `test/tooling/recognition_baseline_manifest_test.dart` **azóta jött létre**
(`2bbd36bd3`, `[E14-R02] … (#565)`, 676 sor hozzáadás, nulla törlés).

- **NEM igaz többé** a §2 utolsó pontja („`evaluation/recognition/` — az
  `E14-R02` hozza létre; az IO-séma ide kerül"): az `E14-R02` **merge-elve
  van**, a könyvtár él, és már hordoz szerződést (`baseline_manifest.json` +
  `baseline_manifest_schema.json` + `annotation_schema.json` +
  `recognition_release_gate.json` + `fixtures/`). Az IO-séma tehát egy MEGLÉVŐ
  könyvtárba kerül, a bevett alakot követve, nem üres helyre.
- **NEM igaz többé** az sem, hogy a legacy összehasonlítás szabadon
  definiálható: az `E14-R02` merge-elt manifestje MÁR eldöntötte, mit mértek és
  mit nem (R5) — a kör ehhez horgonyoz, nem ír fölé új mércét.
- **Igaz maradt** a §2 első két pontja: a mai lánc két lépcső
  (`superflux_onset_detector.dart` → `strum_direction_classifier.dart`,
  209 + 207 sor), és az `ml/` alatt nincs joint fej (`ml/joint_prototype/`
  nem létezik).
- **A kör EGYETLEN döntési helye** az ADR 0517 — a go/no-go szabálya és a
  mérési szerződés. Sem a Chapter 14 §7.2 küszöbeit, sem az E14-R02 manifest
  értékeit ez a kör nem írja át; egy merge-elt szerződés módosítása H1 volna.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "ml/joint_prototype/README.md",
  "ml/joint_prototype/train_prototype.py",
  "ml/joint_prototype/evaluate_prototype.py",
  "evaluation/recognition/joint_io_schema.json",
  "evaluation/recognition/fixtures/joint_io_sample.json",
  "test/tooling/joint_io_schema_test.dart",
  "docs/eval/joint-strum-prototype.md",
  "docs/rounds/e14-r18-joint-streaming-prototype.md",
]
gate_tests = [
  "test/tooling/joint_io_schema_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`. Hiányzó
tanító-környezet → `blocked`.

## 1. Cél

Offline prototípus arról, hogy egy **joint** fej (külön down- és up-onset
regresszió + no-event confidence) jobb-e a mai kétlépcsős (onset → irány)
útnál, ahol az onset-hiba továbbterjed. A prototípus **nem kerül a termékbe**
ebben a körben; a kimenete mért összehasonlítás és verziózott IO-séma.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.4/§5.1:** a kétlépcsős lánc hibaterjedése MÉRT; a joint
  modell természetesen támogatja az abstentiont.
- **`ml/honest_eval.py`:** a repó saját mérési szigora (három-utas split, LOGO,
  bootstrap CI) — a prototípus ugyanezt használja, nem lazábbat.

**A pre-flight visszakeresése (ADR 0312, 2026-09-05 — `knowledge-rag`,
szűkítve `lessons,halts,adr`-re, majd teljes korpuszon):**

- **`lessons/L630`** (E14-R08 review MAJOR-1): a metrika mellé SZÁLLÍTOTT
  definíció-szöveg ellentmondhat a számításnak, és 22 zöld cella átengedi — a
  szám mérve volt, a MONDAT nem. → 7. acceptance-pont + ADR 0517 D7.
- **`lessons/L631`** (E14-R08 review MAJOR-2): egy acceptance-cella, amely a
  SZÁLLÍTOTT belépési pontot megkerülve kézzel épít riportot, nem a futtatási
  úton mér. → §0.0/R9 kimondja, miért nincs ebben a körben szállított belépési
  pont, és ki mozgatja `tool/` alá.
- **`lessons/L637`** (E14-R10 pre-flight): egy kerek tizedessel felírt „a
  küszöbön" cella a HELYES implementáción piros, ha aritmetikából áll elő. →
  §0.0/R6: a határértékek literálok, `python3`-mal ellenőrizve.
- **`lessons/L636`** (E14-R10 / H3): az előre megírt brief mért alapja
  elmozdul alatta. → az egész §0.0 revízió, kiemelten R5 (a legacy sor).
- **`lessons/L104` + `lessons/L131`**: a lassú boxon a hosszú futás egyetlen
  hívásként deadlockol / a wrapper időkorlátjába fut; a scope-tiszta,
  commit-előtti munka viszont nem vész el. → §0.0/R8 futtatási mintája.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/dsp/superflux_onset_detector.dart` →
  `strum_direction_classifier.dart` — a mai lánc KÉT lépcső.
- `ml/` — a jelenlegi CRNN tanító- és export-eszközei megvannak
  (`klangio.py`, `export_live_weights.py`), joint fej nincs.
- `evaluation/recognition/` — az `E14-R02` hozza létre; az IO-séma ide kerül.

## 3. Scope

**Benne:** offline prototípus (16 kHz log-mel frontend), down/up onset
regresszió + no-event fej, causal vagy kontrollált lookahead, összehasonlítás a
legacy lánccal, verziózott IO-séma + Dart-oldali séma-őr, report.

**Nincs benne:** mobil bekötés, `lib/**` módosítás, súly-export a termékbe,
DSP-konstans, production flag.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/joint_prototype/README.md` | környezet és futtatás |
| `ml/joint_prototype/train_prototype.py` | prototípus tanítás |
| `ml/joint_prototype/evaluate_prototype.py` | mérés a grouped splittel |
| `evaluation/recognition/joint_io_schema.json` | verziózott IO-szerződés |
| `evaluation/recognition/fixtures/joint_io_sample.json` | CI-fixture |
| `test/tooling/joint_io_schema_test.dart` | séma-őr |
| `docs/eval/joint-strum-prototype.md` | report + go/no-go javaslat |
| `docs/rounds/e14-r18-joint-streaming-prototype.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/**`, `assets/**`, `ml/` a
`joint_prototype/` alkönyvtáron kívül, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0517 — §0.0/R1)

### 5.1 Csak causal vagy kontrollált lookahead

Mobil jelöltként kizárólag olyan architektúra értékelhető, amelynek a
lookahead-je számszerűen korlátozott és a reportban szerepel. **NEM
elfogadható**: „offline jobb, majd a mobilon lesz valami".

### 5.2 Nincs player-leakage

A train/eval split játékos szerint csoportosított; a leakage-detektor
(E14-R08) futása a report kötelező része.

### 5.3 Az IO-séma verziózott

A modell be- és kimenete sémában rögzített, `schemaVersion`-nel; ismeretlen
verzió típusos hiba a Dart-oldali őrben is.

### 5.4 A go/no-go az Alpha kapuhoz kötött

A javaslat csak akkor „go", ha a mért érték eléri a Chapter 14 §7.2 Strum
Alpha kapuját a grouped spliten. **NEM elfogadható**: „majdnem elérte".

### 5.5 A prototípus nem szállítható artefaktum

Súly nem kerül `assets/`-be ebben a körben.

## 6. Acceptance criteria

1. A prototípus futtatható egyetlen paranccsal, és a splitet a manifestből
   veszi (nem beégetve).
2. A report EGY táblában közli a prototípus end-to-end down/up F1-ét és
   algoritmikus latenciáját a legacy lánc **mért** soraival, és az azonos
   korpusz gépi bizonyítékával: az evaluate script kiszámolja az
   `ml/data/klangio` hash-ét, és az **egyezik** a
   `evaluation/recognition/baseline_manifest.json` `corpusSha256` értékével
   (`4880face…5827`) — eltéréskor hiba, report NÉLKÜL. A legacy onset F1 a
   manifestből átvett érték a forrás-mezőivel; legacy end-to-end irány-szám
   MÉRTKÉNT nem közölhető (a manifest szerint `direction: not-measured`), csak
   explicit, `bound: "upper"` jelölésű felső korlátként, kiírt származtatással
   (§0.0/R5, ADR 0517 D6).
3. A lookahead értéke számszerűen szerepel a reportban és a sémában.
4. A Dart-oldali séma-őr ismeretlen `schemaVersion`-re típusos hibát ad
   (fixture-rel mérve).
5. A go/no-go a Chapter 14 §7.2 Alpha küszöbhöz méri magát (**onset F1 @50 ms
   = 0,82**, **end-to-end direction macro-F1 = 0,80**): a hármas cella a küszöb
   **alatt** → no-go, pontosan **rajta** → go (a határ inkluzív), a küszöb
   **fölött** → go. A hármas cellát a `gate_tests` Dart-őre futtatja, a
   fixture-ből épített változatokon, **literál** határértékekkel (§0.0/R6).
6. Player-leakage esetén a futás hibával áll meg, nem ad reportot.
7. Minden szállított metrika-rekord hordozza a definícióját ÉS a
   `higherIsBetter` irányát, és a Dart-őr a **számot és a definíció-szöveget
   EGYÜTT** méri: az a bemenet, amelyik a definíció szerinti olvasattól eltérő
   értéket ad, egyszerre állítja a tényleges számot és azt, hogy a definíció
   ezt (és ne az ellenkezőjét) mondja (ADR 0517 D7, L630).
8. A futás semmit nem ír a repó fája alá: súly, checkpoint és feature-cache
   kötelezően a `--workdir` / `--cache` argumentummal megadott, repón kívüli
   útvonalra kerül (ADR 0517 D5, §0.0/R7).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A split beégetve | 1. pont |
| A legacy összehasonlítás külön korpuszon | 2. pont hash-cellája |
| A legacy end-to-end irány-szám mértként közölve | 2. pont `bound: "upper"` cellája |
| A lookahead nincs jelentve | 3. pont |
| Ismeretlen séma-verzió → default | 4. pont (Dart-őr, `gate_tests`) |
| A küszöb exkluzív („majdnem elérte" → go) | 5. pont „pontosan rajta" cellája (Dart-őr) |
| A leakage csak figyelmeztetés | 6. pont |
| A definíció-szöveg ellentmond a számításnak | 7. pont együtt-mérő cellája (Dart-őr) |
| Checkpoint/cache a repó fájában | 8. pont + a gépi scope-audit |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/joint_io_schema_test.dart
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). A parancs a `gate_tests` listát tükrözi (§0.0/R2). A Python
oldal külön, önálló parancsként — a RENDSZER-interpreterrel, és zöldnek kell
maradnia (mért kiindulás: 115 passed, §0.0/R3):

```bash
python3 -m pytest ml -q
```

A prototípus saját futtatása ettől külön, a venv-interpreterrel megy
(§0.0/R3, R8):

```bash
/home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py --help
```

`&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a séma-verzió ellenőrzésének ideiglenes kivételével a
4. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. IO-séma + fixture + Dart-őr (RED-del kezdve).
2. Prototípus tanítás/mérés script.
3. Összehasonlító report a legacy lánccal.
4. Go/no-go javaslat (a döntés ADR-je a Claude-é).

## 9. Kockázatok

- **Tanító-környezet hiánya:** ez a kockázat a pre-flight mérése szerint NEM
  áll fenn — TF 2.21.0 telepítve van a `/home/ubuntu/tf-venv/bin/python`
  interpreterben (§0.0/R3). `blocked` jelzés a „nincs tanító-környezet" címen
  tehát HAMIS volna; csak egy ténylegesen mért, más előfeltétel-hiány
  indokolhat `blocked`-ot, a mérés kiírásával.
- **Számítási költség:** valós korlát a lassú boxon — a válasz a §0.0/R8
  szerint dokumentáltan szűkített konfiguráció és leválasztott futtatás, NEM a
  mérés elhagyása vagy becslés.
- **Túlillesztés a fixture-re:** a mérés grouped spliten megy, különben
  értelmetlen.
- **Scope-csúszás a termék felé:** az 5.5 és a tilos zóna védi.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`), 2026-09-05.

### 10.1 Mit épített

- `evaluation/recognition/joint_io_schema.json` — verziózott IO-séma (D1
  lookahead frame+ms, D2 split/leakage invariánsok, D4 inkluzív
  go/no-go-hármas, D6 legacy `bound:"upper"` sor, D7 metrika+definíció
  együtt-utazás).
- `evaluation/recognition/fixtures/joint_io_sample.json` — CI-fixture.
- `test/tooling/joint_io_schema_test.dart` — kézzel írt draft-07-részhalmaz
  validátor A TESZTBEN (D8, mert ehhez a körhöz nincs szállított Dart
  belépési pont), plusz a séma nem-fejezhető kereszt-mező szemantikák
  (lookahead-konzisztencia, literál küszöb-hármas, higherIsBetter-tábla,
  bound-jelölés). **23/23 teszt zöld** (`tools/round-gate.sh
  test/tooling/joint_io_schema_test.dart` — format/analyze/test/
  architecture/secrets/l10n mind ZÖLD, első futásra).
- `ml/joint_prototype/train_prototype.py` — a joint fej tanítása: 3-osztályú
  (down/up/no-event) CRNN, ugyanaz a conv+GRU törzs mint
  `ml/train.py::build_model` (importálva, nem újraírva), `PRE_FRAMES=3` +
  `LOOKAHEAD_FRAMES=4` (7 keret, 70 ms) ablak, audio nullázva
  onset+lookahead után (`joint_window`, az `experiment_deadline.py` mintája).
  Split: leave-one-guitarist-out (`ml/klangio.py::guitarist_of`/
  `logo_folds`), EGY reprezentatív fold (a sorba rendezett gitáros-id-k
  közül az első — determinisztikus, nem szelektált), 3-osztályú
  trainability-őr (`assert_fold_trainable_3class` — az örökölt
  `assert_folds_trainable` a legacy 2-osztályú `{0,1}` halmazra van
  kőbe vésve, 3 osztályra MINDIG bukna) + explicit
  `assert_no_guitarist_leakage`. Minden futási artefaktum (súly,
  provenance JSON) a `--workdir`-be megy, a repóba SEMMI.
- `ml/joint_prototype/evaluate_prototype.py` — a mérés: korpusz-hash
  ellenőrzés a `baseline_manifest.json` ellen (eltérésnél hiba, NINCS
  report — ténylegesen kipróbálva, ld. 10.3), a split FÜGGETLEN
  újraszámolása és leakage-ellenőrzése (nem bízik a train provenance-ban),
  teljes idővonal-pásztázás minden TESZT felvételen 10 ms-onként
  (`detect_events`, csúcskeresés `1-P(no-event)`-en, ugyanaz a
  csúcskeresési fegyelem mint `ml/features.py::spectral_flux_onsets`),
  50 ms-os toleranciájú mohó legközelebbi-párosítás, onset F1 + irány
  macro-F1 (a `recognition_metrics.dart::directionF1` definíciójával
  megegyező szemantika), és a sémának megfelelő JSON-dokumentum
  nyomtatása/mentése.
- `ml/joint_prototype/README.md` — környezet, architektúra, split, futtatás,
  mért konfiguráció+wall-clock, az ismert korlát (lásd 10.4) leírása.
- `docs/eval/joint-strum-prototype.md` — a teljes összehasonlító report,
  a valós mért JSON-dokumentummal, a két fail-closed kapu VALÓS
  kimenetével, és a korlátok/ajánlás szakasszal.

### 10.2 Mért számok (egy dokumentált, determinisztikus futás)

- **Interpreter:** `/home/ubuntu/tf-venv/bin/python` (TF 2.21.0) — a
  rendszer `python3`-ban nincs TensorFlow (mérve, `ModuleNotFoundError`).
- **Korpusz-hash:** `4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827`
  — EGYEZIK a `baseline_manifest.json` `corpusSha256`-jával (mérve, a
  `_corpusChecksum` Dart-algoritmus Python-reprodukciójával, byte-azonos).
- **Lookahead:** 4 keret = 40 ms (+ 3 keret = 30 ms kauzális kontextus, 7
  keret / 70 ms össz-ablak) — a sémában ÉS a reportban ugyanaz a szám.
- **Split:** leave-one-guitarist-out, held-out gitáros `'1'` (55 tanító / 27
  teszt felvétel), a `logo_folds` sorba rendezett első foldja.
- **Konfiguráció:** epochs 12 konfigurált / 6 lefutott (EarlyStopping,
  patience 4), batch 32, seed 42, 363 891 paraméter.
- **Wall-clock:** tanítás 137,9 s + kiértékelés (teljes idővonal-pásztázás,
  27 felvétel) 125,7 s = **~4,4 perc összesen** (a 20 perces keret alatt).
- **Prototípus onset F1 @50ms = 0,3824146481022315** (n=16 962; TP 4010, FP
  12 893, FN 59; precision 0,237, recall 0,986).
- **Prototípus end-to-end irány macro-F1 = 0,22403434521366614** (n=20 972;
  down F1 0,299, up F1 0,149).
- **Prototípus algoritmikus latencia = 40 ms** (csak a lookahead; nem valós
  idejű eszközmérés).
- **Legacy onset F1 @50ms = 0,6739121651650438** (n=16 411) — átvéve a
  `baseline_manifest.json`-ból, forrás-mezőkkel.
- **Legacy end-to-end irány = NEM mérhető ezen a korpuszon** — a report
  `bound:"upper"` jelöléssel közli a legacy onset F1-et mint felső korlátot
  (`0,6739121651650438`), kiírt származtatással (`TP_direction ⊆
  TP_onset` ⇒ az irány-F1 sosem lehet nagyobb az onset F1-nél); ez a szám
  NEM ad alapot „a prototípus jobb" következtetésre.

### 10.3 Falszifikáció (§7.1, kötelező)

**A séma-verzió-ellenőrzés ideiglenes kikapcsolása → PIROS, majd
visszaállítás → ZÖLD, a tényleges parancs+kimenet:**

Kikapcsolás (`test/tooling/joint_io_schema_test.dart`, a `const` kulcsszó
kezelésének ideiglenes letiltása: `if (resolved.containsKey('const'))` →
`if (false && resolved.containsKey('const'))`), majd:

```
$ /home/ubuntu/flutter/bin/flutter test test/tooling/joint_io_schema_test.dart
...
00:00 +1 -1: A2 … schemaVersion "2.0" is rejected [E]
  Expected: false
    Actual: <true>
...
00:00 +18 -2: A7 … matchesBaselineManifest: false fails schema validation … [E]
  Expected: false
    Actual: <true>
...
00:00 +18 -3: A7 … leakageCheckPassed: false fails schema validation … [E]
  Expected: false
    Actual: <true>
...
00:00 +20 -3: Some tests failed.
```

Pontosan a három `const`-ra támaszkodó teszt (schemaVersion,
matchesBaselineManifest, leakageCheckPassed) vált PIROSSÁ, a többi 20
(beleértve a küszöb-hármas és a higherIsBetter szemantikai teszteket, amik
NEM a `const` ágon mennek át) zöld maradt — pontosan azt méri, amit kellett.
Visszaállítás után (`if (resolved.containsKey('const'))`):

```
$ /home/ubuntu/flutter/bin/flutter test test/tooling/joint_io_schema_test.dart
...
00:00 +23: All tests passed!
```

**A player-leakage és a korpusz-hash fail-closed kapu VALÓS kipróbálása**
(a §6 AC6 és a D6 mércéje — nem csak kódolvasással állítva):

```
$ /home/ubuntu/tf-venv/bin/python -c "
import sys; sys.path.insert(0, 'ml/joint_prototype')
import evaluate_prototype as ep
ep.assert_no_leakage(['1001','1002'], ['4001','2001'], '4')
"
GuitaristLeakageError: guitarist/recording leakage detected: ...
test_guitarists=['2', '4'] (expected only '4') — aborting before any
document is written (ADR 0517 D2)
```

```
$ /home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \
    --workdir /tmp/e14r18-work \
    --baseline-manifest /tmp/fake_baseline_manifest.json \
    --output /tmp/e14r18-work/leakage_probe_output.json
error: corpus hash mismatch: ... refusing to compare against a different
corpus (ADR 0517 D6); no document written
exit=1
$ ls /tmp/e14r18-work/leakage_probe_output.json
ls: cannot access '...': No such file or directory
```

Mindkét kapu hibával áll meg, és egyik sem ír fájlt — a valós `main()`
végponton át kipróbálva, nem csak a belső függvényen.

### 10.4 Ahol el kellett térni a brief szövegétől (mérve, nem becsülve)

- **A teljes idővonal-pásztázásos kiértékelés kívül esik a tanítási
  eloszláson** — a modell bányászott negatívokon (flux-csúcs + könnyű
  belső) tanult, nem "minden 10 ms-os kereten". Ez MÉRT tény (precision
  0,237 / recall 0,986 a pásztázáson) és a `docs/eval/
  joint-strum-prototype.md` §8 kimondja: ez a tanítási recept korlátja, nem
  a mérés hibája. A brief nem írt elő konkrét kiértékelési protokollt a
  "streaming-stílusú pásztázásra" — ez az implementer döntése volt, és a
  §8-ban dokumentálva van, miért nem próbáltam meg utólag hangolni a
  küszöböt egy jobb számért (az a p-hacking lenne, amit a repó kultúrája
  kifejezetten tilt).
- **A párosítás mohó, nem Kuhn-algoritmus** — a
  `recognition_metrics.dart::_matchEvents` maximális-számosságú
  párosítójának dokumentált egyszerűsítése; a §8 kimondja.
- **Az `assert_folds_trainable` (ml/klangio.py) nem újrafelhasználható
  változatlanul** — 2-osztályú `{0,1}`-re van kőbe vésve, egy 3-osztályú
  (down/up/no-event) foldon MINDIG bukna. Írtam egy `assert_
  fold_trainable_3class` függvényt `train_prototype.py`-ban (ADR/brief nem
  mondta ki explicit módon, hogy ez a függvény nem újrafelhasználható —
  mérve a tényleges kóddal).
- **`ml/data/klangio` a munkapéldányból hiányzott** — a korpusz (423 MB,
  gitignore-olt) a `/home/ubuntu/music-theory` főkönyvtárban élt, nem a
  `/home/ubuntu/ss-sonnet-impl-e14-r18` munkapéldányban. Egy szimbolikus
  linket hoztam létre (`ml/data/klangio -> /home/ubuntu/music-theory/ml/
  data/klangio`) — a `.gitignore` `ml/data/` mintája fedi, `git status`
  tisztán marad, nincs commitolt hivatkozás. Ez az implementer saját
  hatásköre volt (nem production fájl, nem az allowed_paths listán, nem
  git-nyomon-követett), és a §10-ben mondom ki, miért volt szükséges.

### 10.5 Go/no-go javaslat

**NO-GO** a Chapter 14 §7.2 Strum Alpha kapuhoz mérve — mindkét metrika
messze a küszöb alatt (onset F1 0,3824 < 0,82; irány macro-F1 0,2240 <
0,80), nem "majdnem elérte" eset. A joint-fej architekturális ötlete (a
kétlépcsős hibaterjedés elkerülése, ADR 0312) ezzel a méréssel NEM cáfolt —
amit ez az EGY dokumentált futás cáfol, az *ez a konkrét tanítási recept*
(bányászott negatívokon tanítva, folytonos idővonalon mérve). Egy
esetleges következő kör konkrét, mérhető javaslata: tanítás folytonos-
idővonal negatívokon (nem csak bányászott csúcsokon), vagy időbeli
hiszterézis/magasabb döntési küszöb hozzáadása a pásztázáshoz — nem
egyszerűen ugyanennek a konfigurációnak az újrafuttatása más
hiperparaméterekkel.

### 10.6 A Dart-oldali validátor helye (D8, kimondva)

Ebben a körben NINCS szállított Dart belépési pont: az `allowed_paths`
egyetlen Dart fájlt enged (`test/tooling/joint_io_schema_test.dart`), a
`lib/` és a `tool/` tilos zóna, és az 5.5 szakasz szerint a prototípus nem
szállítható artefaktum. Ezért a kézzel írt draft-07-részhalmaz validátor
(és a hozzá tartozó szemantikai kereszt-ellenőrzések) TELJES EGÉSZÉBEN a
tesztfájlban élnek — ez tudatos, határolt eltérés az L631 mintájától ("a
cella a szállított belépési pontot mérje"), ADR 0517 D8 szerint. A
productizálás köre mozgatja a validátort `tool/` alá, és a teszt onnan
importálja majd.

## 11. Review — a Claude tölti ki
