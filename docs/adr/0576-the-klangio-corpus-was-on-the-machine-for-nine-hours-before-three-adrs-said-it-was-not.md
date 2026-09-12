# ADR 0576 — A Klangio korpusz KILENC ÉS FÉL ÓRÁVAL azelőtt került a gépre, hogy három ADR kimondta volna, hogy nincs rajta — és a mérés, amit ezért elnapoltunk, azóta elérhető

- **Státusz:** elfogadva (egy **ténybeli hiba** javítása 5 fájlban / 10 helyen, és egy elnapolt mérés
  felszabadítása; szállított viselkedés nem változik)
- **Dátum:** 2026-09-13
- **Kör:** E18-R45
- **Kapcsolódó:** ADR 0569 (ahol az állítás keletkezett), ADR 0571, ADR 0572 (ahol
  továbbterjedt), ADR 0573 (a „harmadik korpusz" követelmény, amit ez részben feloldja),
  ADR 0555, `ml/klangio.py`, `ml/honest_eval.py`, `docs/LESSONS.md` L690

## Kontextus

Az ADR 0569 D-pontjai alatt ez állt, és három kör épített rá:

> „Az in-situ változat ebben a környezetben nem elérhető: a Klangio korpusz **nincs a
> gépen**, a Dart pipeline pedig audiót fogyaszt, nem gyorsítótárazott ablakot."

Ebből következett minden, ami utána jött: a Klangio-oldal **orákulum**-ablakon mérése, az
ADR 0571 D4 „az orákulum-műszer delta-kérdésekre korroborált" korlátja, az ADR 0572 „a
Klangio-számok orákulum-ablakosak (a korpusz nincs a gépen)" kikötése, és a HANDOFF
visszatérő tétele: *„a Klangio in-situ söprése, **ha a korpusz bekerül a gépre**"*.

## Döntés

### D1 — A korpusz a gépen van, és teljes

```
  ml/data/klangio/   82 db recording_<id>_phone.wav   44,1 kHz mono 16 bit, ~60 s
                     82 db recording_<id>.strums      TAB: idő, D/U, akkord
```

Gitignore-olt (`git ls-files | grep -c '\.wav$'` → **0**), tehát a harmadik-fél audió
szabály sértetlen. Ez a **telepítési feltétel**: telefon-mikrofon, ahogy a `ml/klangio.py`
maga írja („our deployment condition").

### D2 — És nem „most került oda": kilenc és fél órával megelőzte az állítást

Fájl-időpontok és commit-időpontok egymás mellett:

```
  12:38–12:42   ml/data/klangio/  — a 82 wav + 82 .strums a gépre kerül
  12:53         ml/klangio_live70.npz       ebből ÉPÜL
  15:53         ml/klangio_neg_live70.npz   ebből ÉPÜL
  22:12         ADR 0569 commit (7d72025c): „a Klangio korpusz NINCS A GÉPEN"
  22:44         ADR 0572 commit (6d1eefc1): ugyanez megismételve
```

A középső két sor nem egybeesés. A `honest_eval.build_live` a gyorsítótárat csak akkor írja
meg, ha előtte **beolvasta** a `ml/data/klangio/recording_<id>_phone.wav`-okat és a
`.strums`-okat:

```python
    if os.path.exists(path):            # cache hit -> korai visszatérés
        ...
    for rid in recording_ids(DATA):     # különben: a KORPUSZT olvassa
        pcm = _read_wav(f"{DATA}/recording_{rid}_phone.wav")
```

És ez nem következtetés, hanem **mérve**: az első felvétel ablakai a helyi audióból
újraépítve **bitre** megegyeznek a gyorsítótár soraival:

```
  recording 1001   cached (49, 15, 128)   rebuilt (49, 15, 128)
  max |cached − rebuilt| = 0,000e+00      bitre azonos sor: 49/49
```

Tehát a három ADR pontosan azon a gyorsítótáron mért, ami **ebből** a korpuszból
reprodukálható, **miközben kimondta, hogy a korpusz nem elérhető.** Az artefaktum létezése
önmagában cáfolta az állítást, és nem néztem meg.

És volt egy harmadik, még kínosabb cáfolat is a repóban, r164 óta: **két teszt, ami erre a
könyvtárra mutat, és aminek az ELSŐ dolga megnézni, ott van-e.**

```
  test/tools/klangio_real_ab_test.dart       const dataDir = 'ml/data/klangio';
                                            „Auto-skips when ml/data/klangio is absent"
  test/tools/onset_recall_probe_test.dart    ugyanazt a dataDir-t importálja
```

Vagyis a repó **kész elérhetőség-próbát** tartalmazott: bármelyik teszt futtatása
megválaszolta volna a kérdést. Nem egy nehezen hozzáférhető tényt néztem el, hanem egy
olyat, amire a repóban egy egysoros ellenőrzés várt.

### D3 — Ami ezzel felszabadul

A **Klangio in-situ söprés** — a telepítési feltétel mérése azon az úton, amit az app
futtat (SuperFlux onset-detektálás + a szállított CRNN a streamelt ablakon), nem annotált
onsetre épített orákulum-ablakon. Ez az a mérés, amit

- az ADR 0569 „Amit NEM állítunk" szakasza nevezett meg (*„ha bekerül, a mérés a
  `guitarset_threshold_sweep_test.dart` mintájára megírható"*),
- az ADR 0571 D4 korlátja követelt meg egy szállítási állítás **szintjéhez**,
- és az ADR 0572 egy szállítási döntés előfeltételének nevezett.

Mindhárom elnapolás **alaptalan** volt.

### D4 — És részben feloldja az ADR 0573 D6 „harmadik korpusz" követelményét is

Az ADR 0573 D6 azt mondta, hogy a szállított asset és egy jelölt között nincs dönthető
sejt, és a feloldás egy **harmadik korpusz**. Az ott felsorolt okok állnak, de az
elérhetőségi kép megváltozott: a telepítési korpuszon most **in situ** is mérhető mindkét
asset, ugyanazon az úton, ugyanazzal a műszerrel. A **fold**-torzítás ettől nem szűnik meg
(a szállított asset Klangio-számai továbbra is same-player — ADR 0573 D1), tehát a D6
táblája érvényes; de a „csak orákulumon tudjuk" korlát nem.

### D5 — Az állítás mind a 10 helyen javítva, 5 fájlban

```
  docs/adr/0569-…md       2 hely  (a Kontextus és az „Amit NEM állítunk")
  docs/adr/0571-…md       1 hely
  docs/adr/0572-…md       2 hely
  docs/rag/chunks/018-…   1 hely
  HANDOFF.md              4 hely
```

Helyben annotálva, nem átírva: a **számok** amiket ezek az ADR-ek mértek, érvényesek
maradnak (orákulum-ablakos számok, és annak is nevezték magukat). Ami megdőlt, az az **ok**,
amiért nem mértek in situ, és az ebből következő elnapolás.

## Következmények

- A Klangio in-situ söprés megírható, és a `test/support/live_sweep_harness.dart`
  (ebben a körben kiszervezve a GuitarSet söprésből) azt adja, hogy **egy** műszer hajtsa
  mindkét korpuszt — különben a kereszt-korpusz delta értelmetlen (L269, L682).
- A `ml/data/` és a `*.npz` gitignore-olt marad; **audió nem kerül a repóba**, csak mérés.
- Minden jövőbeli „X nem elérhető ebben a környezetben" állítás előtt a tétel:
  **nézd meg.** A `ls` költsége nulla, a három körön átívelő elnapolás költsége nem.

## Amit NEM állítunk

- **Nem állítjuk, hogy az orákulum-mérések hibásak.** Azok azt mérték, amit mondtak. Az
  ADR 0571 D4 delta-korroborációja is áll.
- ~~**Nem mértük meg még a Klangio in-situ számot.**~~ — **ugyanebben a körben megmértük:
  ADR 0577.** Ez az ADR a korpusz **jelenlétét** rögzíti és az elnapolást vonja vissza; a
  szám az ADR 0577-ben áll (irány-macro **0,9166** a szállított kapun, és a letisztult tier
  ott **−0,3355**).
- **Nem tudjuk**, miért írtam azt, hogy nincs a gépen. A valószínű ok az, hogy a korpusz
  hiányát egy korábbi körben **megállapítottam** (a `find`-alapú keresések a korábbi
  összefoglalók szerint tényleg nem találták), és utána **nem mértem újra** — de ez
  rekonstrukció, nem mérés, és nem is számít: a gyorsítótár dátuma akkor is ott volt.
- **A fold-torzítás nem szűnt meg** (D4). Egy in-situ Klangio szám a szállított assetre
  továbbra is same-player szám.
