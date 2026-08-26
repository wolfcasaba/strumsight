# ADR 0426 — A golden-raszterizációt a MERGE-KAPU architektúráján mérjük

- **Státusz:** Elfogadva (ADR 0112 önjavító kör, E13-R20 / H5, 2026-08-26)
- **Kör:** önjavító kör (nem terméki kör) — a megállt kör: `E13-R20`
- **Szerző:** Claude (Opus 5), önjavító session
- **Kontext-ADR-ek:** [0052](0052-ci-green-gate.md) (a zöld kapu — ez az ADR
  NEM lazítja), [0112](0112-self-healing-pipeline.md) §2–§3 (az önjavító kör
  hatásköre és az egyetlen megmaradt emberi határ),
  [0053](0053-ci-full-test-suite.md) (a teljes suite a CI-ban fut, nem ezen a
  boxon)
- **Kapcsolódó leckék:** [L486](../LESSONS.md#l486) (a golden a
  RASZTERIZÁLÁST rögzíti), [L493](../LESSONS.md#l493) (ez a kör)

## Kontextus — a MÉRT rés

A goldeneket ez a box veszi fel: **aarch64** (Oracle ARM). A zöld kaput adó
CI (`build-apk.yml`, `full-gate.yml`) `ubuntu-latest` = **x86_64**. A
`matchesGoldenFile` alapértelmezett komparátora (`LocalFileComparator`) **nulla
toleranciájú**.

Következmény: minden olyan raszterizációs eltérés, ami a két ISA között
megmarad, a lokális gate-ben **mindig zöld** és a CI-ban **mindig piros**. Ez
nem elméleti — két egymást követő kör fizetett érte:

| Kör | Bukó cellák | Mért diff | Ár |
|---|---|---|---|
| E13-R17 | 4 | 5,60–11,71% | 2 vak javító kör ([run 32887590628](https://github.com/wolfcasaba/strumsight/actions/runs/32887590628)) |
| E13-R20 | 3 | **0,00%** (1 / 8 / 1 px) | 3 piros CI, majd **H5 halt** ([run 32918668534](https://github.com/wolfcasaba/strumsight/actions/runs/32918668534)) |

Az E13-R17 gyökéroka (L486) a `ColorScheme.fromSeed` HCT-lebegőpontos
szín-származtatása volt, és a javítás (konstans színforrás) **mérhetően
működött** — az E13-R20 `learning_path_compact` cellája 5976 px-ről 8 px-re
esett, a párja teljesen zöldre váltott. A maradék viszont **nem** színforrás:
két körrajz antialiasing-peremén 1–8 pixel. Ezt termékkódból nem lehet
megbízhatóan „kikerülni" (a `CircleAvatar` Material-widget, a
`ChordDiagram` `drawCircle` sugara pedig a rács geometriájából jön), és
újrafelvétellel sem: **minden ARM-on készült felvétel ARM-pixelt rögzít.**

Az L486 a saját lezárásában a korlátot ELVINEK mondta ki:

> „Őrteszt: nincs — a hordozhatóság ELVBŐL nem mérhető ezen a boxon (a
> felvétel és a verifikáció architektúrája különbözik); az egyetlen valódi őr
> az exact-SHA CI-futás."

Ez az ADR ezt az elvi korlátot szünteti meg.

## A mérés, amire a döntés épül

A box aarch64, de `qemu-user` amd64 binfmt kezelővel x86_64 konténert futtat,
benne a CI-vel AZONOS `flutter 3.44.2` linux-x64 SDK-val. Négy mérés:

| # | Mérés | Eredmény |
|---|---|---|
| 1 | a `main` MINDEN goldenje (7 teszt-fájl) az x86-konténerben | **27 zöld, 0 piros** |
| 2 | az E13-R20 branch (`c591d3e1`) goldenjei az x86-konténerben | **pontosan a CI 3 bukása**, `1 / 8 / 1 px`, mind `0,00%` |
| 3 | ugyanezek **x86-on újrafelvéve**, majd x86-on ellenőrizve | **6 zöld**; a felvétel PONTOSAN 3 PNG-t írt át |
| 4 | ugyanezek az **x86-felvételű** PNG-k **natív ARM**-on | **3 piros**, `1 / 8 / 1 px` |

Az 1. mérés hitelesíti az eszközt (a konténer a CI raszterizációjának hű mása),
a 2. a másik irányban (a CI pirosát is reprodukálja). A **4. mérés a döntő**: a
rés **szimmetrikus** — ARM-felvétel x86-on piros, x86-felvétel ARM-on piros,
ugyanazon a három cellán. Nulla toleranciával a két architektúra EGYSZERRE nem
elégíthető ki, tehát a felvételnek a KAPU architektúráján kell történnie.

## A döntés

**1. A golden-készlet mérési helye a merge-kapu architektúrája (x86_64).**

A `tools/golden-x86.sh` a golden-teszteket a CI-vel **azonos Flutter-verzióval**
(a `.github/workflows/` `flutter-version:` pinjéből olvasva), `linux/amd64`
konténerben, qemu-user emuláció alatt futtatja ezen a boxon:

```bash
tools/golden-x86.sh check    [teszt-útvonal ...]   # ellenőriz
tools/golden-x86.sh record   [teszt-útvonal ...]   # x86-on VESZ FEL goldent
```

**2. A goldeneket `record` móddal vesszük fel, nem `flutter test
--update-goldens`-szel.** A felvétel és a verifikáció architektúrája így
egybeesik — ez szünteti meg a hibaosztályt, nem a mérce lazítása.

**3. Golden-teszt-útvonal nem kerül a lokális `tools/round-gate.sh`
`gate_tests` listájára.** Az ARM-futás ezekre a cellákra a **rossz gépet**
méri: ma hamis zöldet ad, x86-felvétel után hamis pirosat adna. Helyette a
kör-brief §7-je a `tools/golden-x86.sh check` futtatását írja elő, a
verifikáció pedig — változatlanul — a CI teljes suite-ja.

## Amit ez a döntés NEM tesz — a mérce határa (ADR 0112 §3)

- **A komparátor változatlan.** Ugyanaz a nulla toleranciájú
  `LocalFileComparator`; nincs pixelküszöb, nincs `%`-os tolerancia.
- **A golden-készlet változatlan.** Egyetlen cella sincs törölve vagy
  `skip`-elve; a `test/ui/goldens/` bank teljes.
- **A CI változatlan.** Sem a `.github/workflows/`, sem a
  `.github/actions/flutter-gates` nem módosul — az ADR 0112 §3 tiltása
  kivétel nélkül érvényes (lásd az ADR 0112 2026-08-19-i Módosítás blokkját).
- **A `tools/round-gate.sh` változatlan.**
- A `gate_tests`-ből kikerülő golden-útvonal **nem** csökkenti a mérést: a
  golden-cellákat ezután **kétszer** méri valami (lokálisan az x86-konténer,
  a kapuban a CI), miközben eddig a lokális mérése bizonyítottan hamis volt.

## Következmények

- **A teljes lokális `flutter test` (ARM) piros lehet golden-cellákra.** Ez
  elfogadott és az ADR 0053 óta amúgy is a helyzet: a teljes suite a CI-ban
  fut, ezen a boxon a célzott sáv. A `tools/golden-x86.sh check` a lokális
  golden-mérés egyetlen érvényes alakja.
- **Első futás lassú** (x86 Flutter SDK letöltése emulált konténerben);
  utána a kép és a pub-cache docker-volume újrahasznosul.
- **Előfeltétel:** `docker run --privileged --rm tonistiigi/binfmt --install amd64`
  (egyszer, a boxon). A script hiányzó emulátornál környezeti hibával (20) áll
  meg, nem ad hamis zöldet.

## Gépi őr

`tools/tests/test_golden_x86_parity.py` — a három néma szétcsúszás ellen:
az eszköz létezik és futtatható; a workflow-k Flutter-pinje egyetlen érték, és
az eszköz ebből építi a képet (a Dockerfile nem rögzíthet saját verziót); a
felderítés lefedi az ÖSSZES `matchesGoldenFile`-t hívó teszt-fájlt. A
`router-ci.yml` `tools/**` trigger-útvonala miatt ez CI-ban is fut.
