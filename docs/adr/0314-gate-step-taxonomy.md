# ADR 0314 — Kapu-lépés taxonómia: mit bukunk el, és mikor zaj

- **Státusz:** elfogadva (2026-08-18)
- **Kontextus-ADR-ek:** [`0052`](0052-green-gate.md) (zöld kapu), [`0053`](0053-ci-full-test-suite.md), [`0307`](0307-pipeline-throughput-program-v2.md) §1

## 1. Probléma — amit ma NEM tudunk

A `tools/round-metrics.py` mérve **31,3% holtidőt** és **142 körből 31
önjavítást igénylőt** mutat. A halt-rekordok (`.pipeline/halted-*.txt`)
`round=`, `halt=`, `summary=` mezőket vezetnek, tehát a **halt-kód** szintje
mérve van (H3: 136, H6: 129, H8: 36, H2: 16).

Ami nincs mérve: **melyik kapu-lépés** bukott. A `round-gate.sh` külön
processzben futtat `format` → `analyze` → `test <útvonalanként>` →
`architecture` → `secrets` → `l10n` lépéseket, de a kimenet elolvasása után
nem marad gépi nyom arról, hogy melyik lépés adott nem-nulla kilépési kódot és
mennyi ideig futott.

Ebből két dolog következik, mindkettő ma vak folt:

1. **Nem tudjuk, hova érdemes optimalizálni.** Ha a holtidő nagy része az
   `analyze` lépésre megy el, az más beavatkozás, mint ha a `test`-re.
2. **Nem tudjuk szétválasztani a valódi hibát a zajtól.** Egy változatlan fán
   előbb piros, majd zöld teszt **flaky** — iparági gyakorlat szerint külön
   sávba tartozik, mert különben a CI jelzése megbízhatatlanná válik
   ([test quarantine pattern](https://deflaky.com/blog/test-quarantine-pattern)).
   Ma egy ilyen eset ugyanúgy önjavító ciklust indít, mint egy valódi regresszió.

## 2. Döntés

A `tools/round-gate.sh` minden lépés után **append-only** eseménysort ír a
`.pipeline/gate-events.tsv` fájlba:

```
ts  round  step  test_path  exit_code  duration_s  head_sha  tree_dirty  rerun_of
```

- A rögzítés **nem befolyásolhatja a kapu kilépési kódját**: a rögzítő ág
  hibája `|| true`, a kapu viselkedése bitre azonos marad.
- `flaky` nem külön oszlop, hanem **levezetett** tulajdonság: ugyanaz a
  (`round`, `step`, `test_path`) pár azonos `head_sha` + azonos `tree_dirty`
  mellett előbb nem-nulla, majd nulla kilépési kóddal záruló eseménypár. A
  levezetés a `round-metrics.py --gates` dolga, nem a kapué — a kapu csak tényt
  ír, nem ítél.
- `tools/round-metrics.py --gates` aggregál: lépésenkénti bukás-szám, medián
  időtartam, és a levezetett flaky-párok listája.

## 3. Amit ez a döntés NEM tesz

- **Nem karanténoz.** Ez a kör mér, nem dönt: egy flaky-nak jelölt teszt
  továbbra is pirosra viszi a kaput. A karantén külön, mért döntés lesz — és
  csak akkor, ha az adat indokolja.
- **Nem gyengíti a mércét.** A kapu lépései, sorrendje, kilépési kódjai és a
  csonkítatlan kimenet elve változatlan (ADR 0052).
- Nem vezet be teszt-kiválasztást (test impact analysis): a kör `gate_tests`
  cellája ma is szűkít, a teljes suite a CI-ban fut (ADR 0053).

## 4. Következmények

- A `.pipeline/` védett útvonal, de futásidejű írásra való — a rögzítés a kapu
  futása közben történik, nem implementer-szerkesztésként.
- Az eseménysor append-only és soronként zárt: párhuzamos slotok mellett is
  írható, mert minden sor egy lépés.
- Új kockázat: a rögzítő ág hibája elrejtőzhet a `|| true` mögött. Ellenszer: a
  mérce-mátrix falszifikációs cellája éppen azt méri, hogy a kapu kilépési kódja
  a rögzítés hibája esetén is helyes marad.
