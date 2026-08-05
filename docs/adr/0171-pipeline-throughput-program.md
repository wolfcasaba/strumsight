# ADR 0171 — A kör-pipeline áteresztő-képességének programja

**Státusz:** elfogadva (2026-08-05, user-döntés: „hogyan tudom a fejlesztést
felgyorsítani … dolgozd ki és építsük be biztonságosan tesztekkel", majd
„figyelj arra is, hogy a kódminőség emiatt ne romoljon").

Kiegészíti az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu),
[ADR 0053](0053-ci-full-test-suite.md) (teljes suite a CI-ban),
[ADR 0086](0086-ci-dispatch-only-build-gate.md) (kör-scope-olt APK-dispatch),
[ADR 0087](0087-autonomous-round-pipeline.md) (autonóm lánc) és
[ADR 0112](0112-self-healing-pipeline.md) (önjavítás) döntéseit. Egyiket sem
írja felül: a **mérce változatlan**, csak a mérce körüli várakozás csökken.

## Kontextus — mit mértünk, mielőtt bármit módosítottunk

Az „mi lassítja a fejlesztést" kérdésre eddig becslés volt a válasz. A
`tools/round-metrics.py` a `.pipeline/chain.log` eseményeiből számol; 41 mért,
befejezett körre (2026-07-30 … 2026-08-05):

| Mérőszám | Érték |
|---|---|
| medián kör-idő (session indulásától merge-ig) | **79 perc** |
| medián holtidő két kör között | 3 perc |
| összes holtidő | 1545 perc = a lánc élettartamának **22,8%-a** |
| önjavítást igénylő kör | **9 / 41** |
| `build-apk.yml` futásideje körönként, legalább kétszer | ~11 perc |

Két dolog látszik: (a) a lánc negyede *várakozás*, nem munka; (b) a kör-időn
belül a legdrágább ismételhető elem a javító/önjavító kör, nem a CI.

A 2026-08-05 14:08–14:30 közötti eset ezt kicsiben mutatta: a merge után négy
firing kimaradt (piszkos munkafa egy párhuzamos brief-batch miatt), majd egy
ötödik a saját docs-push CI-jára várt — 22 perc holtidő nulla munkával.

## Döntés

Hat lever, mindegyik **gépi őrrel**, alapértelmezésben a mai viselkedéssel
(egy kivétel: az azonnali lánc-folytatás BE van kapcsolva).

### §1 Párhuzamos kör-slotok (`PIPELINE_SLOTS`, alap: 1)

`tools/round-slots.py` dönti el, indulhat-e egy kör a futók mellett:

* **fájl-diszjunktság** a briefek `allowed_paths` halmazaiból (a záró rituálék
  közös fájljai — HANDOFF, RTM, LESSONS, sor-fájl — nem számítanak ütközésnek,
  őket a `tools/round-merge-lock.sh` sorosítja);
* **előfeltétel-teljesülés**: az epicen belüli sorrend ÉS a briefben nevesített
  körök. A FUTÓ előfeltétel nem teljesített előfeltétel — a benne születő API
  még nem létezik.

**Mért következmény, amit nem szépítünk:** a jelenlegi sor függőségi értelemben
soros. Az Epic 4 körei mind érintik a `lib/features/ai_tutor/public.dart`-ot, az
Epic 5 pedig az Epic 4 zárására vár, ezért ma `PIPELINE_SLOTS=2` mellett is
legfeljebb egy kör indulna. A mechanizmus akkor fizet, ha két **valóban
független** munkafolyam van (pl. egy termék-epic + egy governance/infra kör,
vagy backend + Flutter). Ezért a slot alapértéke 1, és a kapcsolót akkor
érdemes átállítani, amikor a `plan` kimenete ténylegesen két kört admittál.

OOM-védelem: `effective_slots()` a szabad memóriából számol
(`PIPELINE_MIN_FREE_GB_PER_SLOT`, alap 6 GB), a `tools/round-gate.sh` pedig
globális zárat vesz, így két Flutter-gate soha nem fut egyszerre (L05).

### §2 Azonnali lánc-folytatás (`PIPELINE_SELF_CHAIN`, alap: 1)

Merge után a driver leválasztott gyereket indít, amely megvárja a slot-zár
elengedését, és azonnal viszi a következő kört — nem vár az 5 perces cron-ra.
Ezzel együtt a `main`-en FUTÓ workflow már nem blokkol (az ADR 0086 óta a
`build-apk` nem is indul main-push-ra; a saját docs-pushunk CI-ja nem kapu),
**cserébe új, keményebb kapu**: piros main fölé a lánc nem indul (ezt korábban
semmi nem ellenőrizte).

### §3 CI-terv: APK csak ott, ahol számít (`tools/round-ci-plan.py`)

A `full-gate.yml` UGYANAZT a mérce-láncot futtatja, mint a `build-apk.yml`
(`.github/actions/flutter-gates` composite: format, analyze, architecture,
secret, l10n, asset, **teljes** `flutter test`, randomizált property; plusz
song-schema/provenance gate és coverage job) — csak az Android-buildet hagyja
el. A választás nem ítélet, hanem terv:

* `build-apk.yml`, ha `native_gate = true`, VAGY a diff érint
  `android/ ios/ macos/ linux/ windows/ web/ assets/ pubspec.* .github/actions/**`
  útvonalat, VAGY a diff ismeretlen (**fail-closed**);
* `full-gate.yml` minden más esetben.

A user valódi gitáros APK-tesztje továbbra is a **végső** elfogadási feltétel;
epic-zárás előtt az APK-ág kötelező.

### §4 Brief-lint: a javító körök okát a kör ELEJÉN fogjuk meg

`tools/brief-lint.py` két szinten mér. A `base` szintet minden nyitott brief
teljesíti (mérve a bevezetéskor), ezért **CI-kapu** a Router CI-ban; a `strict`
szint (falszifikációs cella, küszöb-mátrix, STOP-protokoll, kör-jelzés) a kör
pre-flightjának teendőlistája, amit a driver a promptba fűz (`{{BRIEF_LINT}}`).

A bevezetéskor azonnal talált két valódi driftet: az `E05-R06`/`E05-R24` briefek
`test/core/camera` gate-útvonalát (amit a sor korábbi körei hoznak létre — ezt a
lint a *sorrendből* igazolja, nem a lemezről) és az `E04-R14` üres
`gate_tests` mezőjét.

### §5 Kör-granularitás — mérésre, nem érzésre

A kör fix overheadje (pre-flight, review, CI, záró rituálék) 40–50 perc, ezért
egy 20 perces implementációjú kör aránytalanul drága. A `tools/round-metrics.py`
adja a döntés alapját. **Queue-séma NEM változik**: az összevonás a
brief-előkészítés dolga (egy brief, egy kör, két SDD-kör tartalmával), mert a
sor-fájl ötoszlopos alakjára több gépi őr épül.

### §6 Vas

A box: 4 mag, 23 GB RAM (mérve ~11 GB szabad), 77 GB szabad lemez. A gate
memória-korlátos, ezért a §1 párhuzam RAM-fedezethez kötött. Ha a §1 valaha
tartósan 2+ slottal fut, a legolcsóbb lineáris gyorsítás a több RAM/mag — nem
motorváltás.

## Miért nem gyengül ettől a mérce

A user külön kikötése: „a kódminőség emiatt ne romoljon". Ezért minden lever
mellé gépi őr került (`tools/tests/test_pipeline_throughput.py`, 43 teszt):

| Kockázat | Őr |
|---|---|
| a `full-gate.yml`-ből később kikopik egy mérési lépés | teszt hasonlítja a két sáv lépéseit (`GateChainParityTest`) |
| új natív könyvtár némán az olcsó sávba csúszik | teszt: a repó minden natív könyvtárára illeszkednie kell az APK-szabálynak |
| a CI-terv „bizonytalanra" olcsó ágat választ | fail-closed teszt (üres/ismeretlen diff → APK) |
| a gate-zár ürügyén kimarad egy gate-lépés | teszt sorolja a `round-gate.sh` kötelező lépéseit |
| párhuzamos körök ADR-számot ütköztetnek | atomi (`O_EXCL`) foglaló + teszt |
| párhuzamos körök egymás fájljaiba írnak | diszjunkt-vizsgálat + előfeltétel-szabály + merge-zár |
| a brief-lint „megszokásból zöld" | a `base` szint állítása külön teszt is, nemcsak CI-lépés |
| a slot-kapcsoló véletlen bekapcsolása OOM-ot hoz | RAM-fedezet-számítás + gate-zár + teszt |

A §4 ráadásul **javítja** a minőséget: a briefek falszifikációs cellái
pontosan azt a hibaosztályt célozzák, ami eddig javító körré vált.

## Következmények

* Az orchestrátor-prompt új kötelezettségei: brief-lint teendők a pre-flightban,
  ADR-szám a foglalótól, CI-terv futtatása dispatch előtt, merge-zár párhuzamos
  körnél.
* Az `ls docs/adr | tail` alak sorszám-választásra tiltott.
* Visszakapcsolás: `PIPELINE_SELF_CHAIN=0` visszaadja a cron-ütemű láncot,
  `ROUND_GATE_LOCK=none` a zár nélküli gate-et, `PIPELINE_SLOTS=1` a mai
  egyszálú működést. A `full-gate.yml` elhagyásához elég a
  `tools/round-ci-plan.py --force-apk`.

## Várt hatás (becslés, mért alapon)

A §2 a mért 22,8%-os holtidő nagy részét viszi el, a §3 körönként ~5–10 percet
(natív-mentes köröknél, két dispatch-csel számolva), a §4 a 9/41 önjavítási
arányt célozza. A §1 hatása ma nulla, és szándékosan az marad, amíg a sor
függőségi értelemben soros — ezt a `plan` kimenete mutatja meg, nem érzés.
