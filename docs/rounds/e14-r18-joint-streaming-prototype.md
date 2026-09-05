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

## 11. Review — a Claude tölti ki
