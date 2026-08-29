# E12-R16 review — AI és ML összesített release gate

- **Kör:** `E12-R16` (Chapter 12, Kör 16)
- **Branch / PR:** `sonnet-impl/e12-r16-ai-release-gate-aggregation` · [#507](https://github.com/wolfcasaba/strumsight/pull/507)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5) — read-only, a munkapéldányon mérve
- **Implementer HEAD:** `4f38590e` (1 kör-commit a `787e0df2` pre-flight fölött)
- **Scope-audit:** `Legacy scope audit OK (787e0df2bf76..4f38590ee121, 5 changed path(s), 0 generated/ignored)`
- **ADR:** [`0477`](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md)

## 1. menet — verdikt: **CHANGES REQUESTED** (1 MAJOR, 1 MINOR)

A diff a brief §4 engedélyezett listáján belül marad, az ADR 0477 D1–D7
döntéseit végigviszi, és a 22 teszt-cella `skip:` ág nélkül, `systemTemp`
fixture-ökön, `Process.runSync('python3', …)`-szal méri az összesítőt (a
`benchmark_budget_test.dart` E12-R14 mintája). A `docs/release/ai-quality-gates.md`
minden sora MÉRT dokumentumra vagy a `model_manifest.json`-ban MÁR deklarált
`evaluation_report` útvonalra hivatkozik — kitalált riport-forma nincs.

Két lelet maradt.

---

### MAJOR-1 — a kapu teljes lefedettsége NÉMÁN törölhető: egy sor kivétele zöldre váltja a release-kaput

**Mérve** (`/home/ubuntu/ss-sonnet-impl-e12-r16`, `4f38590e`):

```
$ python3 tool/release/build_ai_report.py --profile development \
    --scope-file docs/release/ai-quality-gates.md ; echo exit=$?
build_ai_report: 3 release-blocking finding(s):
  - audio_analysis_core/chord_accuracy: required evidence document is missing or unreadable ...
  - audio_analysis_core/onset_f1_50ms: required evidence document is missing or unreadable ...
  - live_and_tuner/direction_accuracy: required evidence document is missing or unreadable ...
exit=1

$ grep -v "^| audio_analysis_core \|^| live_and_tuner " \
    docs/release/ai-quality-gates.md > /tmp/gutted.md
$ python3 tool/release/build_ai_report.py --profile production \
    --scope-file /tmp/gutted.md ; echo exit=$?
{ "capabilities": [ { "id": "computer_vision", "metrics": [], "status": "not_in_scope" } ],
  "findings": [], "profile": "production", "schemaVersion": 1 }
exit=0
```

**És egyetlen cella sem lesz ettől piros:**

```
$ grep -n "ai-quality-gates.md\|docs/release" test/tooling/ai_release_report_test.dart
(nincs találat)
```

A teszt-fájl KIZÁRÓLAG `systemTemp`-be írt fixture-mátrixokon méri az
összesítőt; a SZÁLLÍTOTT `docs/release/ai-quality-gates.md`-t egyetlen cella
sem olvassa.

**Miért MAJOR:** ez pontosan az a hamis zöld, aminek a kizárása a kör célja. Az
ADR 0477 D2 („a hiányzó KRITIKUS bizonyíték BLOKKOL") és a brief §5.1 azt az
utat zárja, amelyen a *bizonyíték* hiányzik — de nyitva hagyja azt, amelyen a
*követelmény* tűnik el. A `build_ai_report.py` `build_report()`-ja a
`gate_rows`-ból építi a `grouped` szótárat (`:335-343`), ezért egy `ga_scope: true`
capability, amelyhez a mátrix egyetlen sort sem nevez meg, **meg sem jelenik a
riportban**. A kapu megkerülésének olcsóbb módja lett a sor törlése, mint a
mérés elvégzése — és semmi nem méri.

A brief §6.1 mérce-mátrixának saját szabálya sérül: „A hiányzó riport üres
eredménnyel, `pass` döntéssel csúszik át → A1". Az A1 cellái csak a
fixture-mátrixon mérnek, ahol a sor definíció szerint jelen van.

**Javítás (az engedélyezett fájllistán belül, `test/tooling/ai_release_report_test.dart`
+ `docs/release/ai-quality-gates.md`):** kipinnelt lefedettség-cella, amely a
SZÁLLÍTOTT `docs/release/ai-quality-gates.md` gépi tábláját és a SZÁLLÍTOTT
`docs/testing/device-matrix.yaml`-t olvassa, és PIROS, ha az `audio_analysis_core`
vagy a `live_and_tuner` capabilityhez nincs sor a táblában (a két MÉRT,
AI-bizonyítékot hordozó GA-scope capability — §0.0 R2). Ugyanez a cella zárja
azt is, hogy egy sor `ga_scope: false` capabilityre írása („átsoroljuk
not_in_scope-ba") ugyanezt a megkerülést adja. A pinnelés indokát a
`ai-quality-gates.md` mondja ki: a sor törlése a kaput PIROSRA váltja, nem
zöldre.

---

### MINOR-1 — a `WARN_THRESHOLD` / `FAIL_THRESHOLD` import halott, így az A4 őr részben színház

`tool/release/build_ai_report.py:60-65` importálja a `DIRECTIONS`, a
`FAIL_THRESHOLD`, a `WARN_THRESHOLD` és a `classify` nevet, de a két küszöb-név
a fájlban **sehol nem szerepel újra** — a tényleges osztályozást a `classify()`
hívás végzi (`:299`).

Az A4 cella (`:417-434`) ezért azt bizonyítja, hogy a két név *megjelenik a
forrásban*, nem azt, hogy a küszöb onnan JÖN. A `classify` importja és
használata önmagában erős őr, de a két halott név egy jövőbeli olvasónak azt
sugallja, hogy a fájl maga is küszöböt kezel.

**Javítás:** tedd teherhordóvá az importot — a riport hordozza a provenanciát,
pl. `"thresholds": {"warn": WARN_THRESHOLD, "fail": FAIL_THRESHOLD}` a
top-level kimenetben (ez egyben azt is dokumentálja egy elmentett riportban,
MELYIK küszöb minősítette), és egy cella mérje, hogy a kiírt értékek egyeznek a
`compare_benchmarks.py`-ben állókkal. (Alternatíva: az importot szűkíteni
`classify`/`DIRECTIONS`-ra és az A4-et a `classify(` hívás meglétére kötni — de
az kevesebbet bizonyít.)

---

## Nyitva hagyott NOTE-ok (nem blokkolnak)

- **NOTE-1:** a `not_in_scope` capabilityk sorai sosem esnek át a
  `resolve_expected_model()` ellenőrzésen (az csak az `evaluate_capability`-ben
  fut), így egy elgépelt `vision:<model_id>` a `computer_vision` sorokban csak
  akkor derülne ki, amikor a capability GA-scope-ba kerül. Ma nem kapu-hiba, de
  egy jövőbeli GA-átsorolás meglepetése.
- **NOTE-2:** az `evidence_path` és a két default (`--matrix`,
  `--model-manifest`) a futtatási munkakönyvtárhoz relatív. A repó gyökeréből
  futtatva helyes; máshonnan a bizonyíték `missing`-nek látszik. A
  `compare_benchmarks.py` ugyanezt a konvenciót követi, ezért nem lelet.

## Amit a review MÉRT és rendben talált

- **A1/A2/A3/A5/A6/A7 + küszöb-cellahármas:** 22 cella, `skip:` ág nélkül; az
  A3 utolsó cellája (`:368`) UGYANAZT a bemenetet futtatja az `ai_tutor`
  fixture-mátrixbeli `ga_scope: true`-ra billentésével, és blokkolást vár — ez
  géppel bizonyítja, hogy nincs beégetett GA-lista (ADR 0477 D1).
- **A6 profil-invariancia** (`:554`): ugyanaz a hiányzó-bizonyíték bemenet
  mindhárom profilon UGYANAZT a nem-nulla kódot adja — a D6 „a profil nem lazít"
  állítása mérve van, nem csak leírva.
- **A4 küszöb-literál tilalom** (`:427-433`): a forrás nem tartalmazhat `0.05`,
  `0.10`, `5.0`, `10.0` literált — a versengő küszöb gépileg kizárva.
- **A modell-verzió két alakja** (`:131-153`, `:198-221`) a MÉRT manifesthez
  igazodik: `models[].filename` → `training_run.identifier`,
  `vision_models[].model_id` → `version`, plusz a mátrix által engedélyezett
  `none` literál — és a `none` kiskapuvá válását külön cella zárja (`:284`).
- **A mai fán a futás szándékosan `exit=1`** (§0.0 R5): a két GA-scope
  AI-capability bizonyítéka ma prózai Markdown, nem gépi dokumentum. Az
  implementer ezt NEM fedte el kitalált riporttal — a `docs/eval/**` és az
  `evaluation/**` érintetlen.

---

## 2. menet — a javító kör után

*(a javító kör lezárása után töltendő)*
