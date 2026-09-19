# ADR 0568 — A fixtúra-nyilvántartás őre Windowson nem tudott bukni, két paritás-arany nem volt bejegyezve, és a settled arany a ROSSZ TÉRBEN volt

- **Státusz:** elfogadva (őr-javítás + bejegyzés + az első fogyasztó; **szállított viselkedés
  nem változik**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0473 (a fixtúra-manifeszt és a proveniencia-szabályok), ADR 0555 D3
  (a bekötetlen settled asset és „a paritás-fixtúra megvan"), ADR 0567 (a settled asset
  in-situ mérése — ugyanebből a körből), AGENTS.md §9, `docs/LESSONS.md` L671, L683

## Kontextus

A bekötő kör előkészítéseként felmértem, melyik AGENTS.md §9 láb van már meg a settled
asset alatt (fixtúra + property + paritás + valódi-audió). Az ADR 0555 D3 azt írja: „a
paritás-fixtúra `test/fixtures/crnn_live_3c_settled_parity.json`-ban van". Megvan — 1,26 MB,
commitolva, és **semmi nem olvassa**.

Innen három, egymásba kapcsolódó hiba jött elő.

## Döntés

### D1 — A fixtúra-őr Windowson a fa MINDEN fájlját kihagyta

A `tool/check_fixture_manifest.dart` bejárója így szűr:

```dart
final prefix = '$root/';
final absolute = entity.absolute.path.replaceAll('\\', '/');
if (!absolute.startsWith(prefix)) continue;
```

Az **absolute** normalizálva van forward slashre, a **prefix** nem. Windowson a `root`
backslash-eket hord, tehát a `startsWith` **soha** nem egyezett, a bejárás **semmit** nem
adott vissza, és a „lemezen van, manifesztben nincs" irány **nem tudott jelezni**. A
„valódi manifeszt tiszta" állítás ezen a gépen ezért **üres** volt; Linuxon (CI) viszont
működik, tehát ott valódi.

Javítva a `root` származtatásánál (forward slash + lezáró szeparátor levágása), és
**ellenőrizve mindkét irányban**: egy bedobott `_tmp_walker_probe.json` most
`fixture file has no manifest entry`-t ad, a fa pedig `Fixture manifest OK (54 fixture(s))`-t.

**Amit ez a kódról mond:** a hibát nem kódolvasás találta meg, hanem a repó **önteszt**je —
az az eset, ami azt állítja, hogy *az őr tud bukni* (`a fixture file on disk with no
manifest entry is flagged`). Ez az eset Windowson **piros** volt, és ez volt az egyetlen
jelzés. Pontosan az [[L671]] szabálya: *egy kontroll, ami nem tud elbukni, nem mond semmit*
— és a repó már rendelkezett azzal az öntesztel, ami ezt kimutatta.

### D2 — Két paritás-arany git-ben volt, manifesztben nem

```
  test/fixtures/crnn_live_3c_settled_parity.json   1 256 394 B   commitolva E18-R32
  test/fixtures/strum_metric_channel_parity.json     221 569 B   commitolva E18-R35
```

Mindkettő **követett és commitolt**, tehát a CI látja őket, és a manifeszt 52 bejegyzése
mellett a fán 54 adatfájl volt. A `flutter test --coverage` a CI-ban **útvonal nélkül**
fut, tehát a `fixture_manifest_test.dart` is, és Linuxon a „valódi fa tiszta" eset ezekre
**elbukik**. Ebből következik — nem mérésből, hanem logikából, mert gh-t nem hívok —, hogy a
**teljes CI-kapu ezen a teszten az E18-R32 óta piros**. Ezt az orchestrátornak érdemes
ellenőriznie.

Miért nem fogta a helyi kapu: a `tools/round-gate.sh` **megnevezett** teszt-utakat futtat, és
tizenegy kör egyike sem nevezte meg ezt. A D1 hibával együtt ez azt jelenti, hogy a hiány
**sem** helyben, **sem** a kör-kapuban nem volt látható.

A `strum_metric_channel_parity.json`-t **én** hagytam ott az E18-R35-ben. Bejegyezve, a
licenc-/proveniencia-szöveggel az ADR 0473 szerint, és kimondva benne az is, amit a fájl
**nem** tud: 120 esete valódi held-out GuitarSet onset-fázis, 60 szintetikus él-eset, de a
fájl **nem jelöli**, melyik melyik, és tíz szintetikus eset ugyanazt a minta-nevet hordja,
mint a mértek — a szétválasztás csak a generátorból állítható vissza. Ez így már olvasható
tény, nem rejtett tulajdonság.

### D3 — A settled paritás-arany a ROSSZ TÉRBEN volt, tehát fogyaszthatatlan

A `CrnnStrumNet.forward` **maga standardizál** a saját assetjéből parse-olt mean/std-del:

```dart
x.set(i, j, 0, (window[i][j] - mean[j]) / std[j]);
```

Tehát **nyers** log-melt vár. A két arany tere mérve:

```
  fixtúra                            mean     std     tér
  crnn_live_3c_parity.json          −4,906   6,884   NYERS        (helyes)
  crnn_live_3c_settled_parity.json  +0,126   0,960   normalizált  (hibás)
```

A `ml/train_live_3c_settled.py` `Xn[i]`-t írt `X[i]` helyett, tehát a Dart oldal
**másodszor** is standardizálta volna a sorokat. A fixtúra önmagában **konzisztens** volt (a
Keras-referencia a normalizált sorokra pontosan egyezik: max|Δ| = **0,000000**) — csak
éppen a Dart belépési pontjával nem.

Javítás: a sorok **helyben visszaskálázva** nyers térbe az asset saját mean/std-jével, az
`expected` változatlanul. A kör mérve biztonságos: a
normalizál → visszaskáláz → normalizál út hibája **2,4e-07** az ablakon és **1,8e-07** a
softmaxon, négy nagyságrenddel az 1e-3 tolerancia alatt (a `std` mindenhol 5,01–7,56, tehát
nincs felerősítés). Az értékek **teljes float32 pontossággal** kerültek ki, nem 5 tizedesre
kerekítve, mert így a JSON-ban álló szám **pontosan** az, amit mindkét oldal fogyaszt (az
r143 szabálya szigorúbban teljesítve, mint kerekítéssel). A **generátor is javítva**, hogy a
következő futás ne hozza vissza.

### D4 — És ezzel az ADR 0567 mérése hitelesítve van

Ez nem mellékes: az ADR 0567 a settled assetet a **szállított Dart pipeline-on** mérte, és
+0,186 irány-macro-F1-et jelentett. Ha a Dart port nem reprodukálja a tanított modellt, az
a mérés **egy ismeretlen modellről** szólt volna. A most megírt paritás-teszt szerint a
legnagyobb eltérés a 32 esetre **1,78e-07** — vagyis a Dart forward *ugyanazt* a modellt
számolja, amit a Keras tanított, és az ADR 0567 száma **áll**.

Sorrend szerint ez visszafelé történt: előbb mértem a modellt, utána ellenőriztem a portját.
Helyesen fordítva lett volna; a kör ezt kimondja, nem elhallgatja.

### D5 — A §9 paritás- ÉS property-lába ezzel lezárva a settled asset alatt

`test/features/live/ml/crnn_live_3c_settled_parity_test.dart`, öt eset:

1. **séma-őr** — a `cases` nem üres és 15×128×3 alakú (egy átnevezett kulcs különben
   minden alábbi állítást **nulla** soron futtatna);
2. **paritás** ≤1e-3 (mért legrosszabb: 1,78e-07), a legrosszabb eltérés **kiírva**, hogy a
   toleranciában maradó elcsúszás is látható legyen;
3. a bányászott **no-strum** esetek az elutasító osztályra esnek (≥0,6);
4. **property**: 40 magolt véletlen ablakon a softmax **eloszlás** (véges, [0,1], összeg
   1-hez 1e-9-en belül) — a fixtúra 32 pontot pinel, egy máshol eloszlást nem adó háló
   azokat átmehetné;
5. **„mért, de nincs bekötve" őr**: a `noStrumThreshold` még **0,85**, **és** a két asset
   bájtjai különböznek — a második nélkül a teszt akkor is átmenne, ha valaki a settled
   súlyokat a szállított útra másolja, ami épp az a változás, amit észre kell vennie.

A `fixture_manifest_test.dart` darabszáma 52 → **54**, a teszt nevében a szokásos
történet-sorral.

## Következmények

- A fixtúra-korpusz őre **működik ezen a gépen is**, tehát egy következő kör nem hagyhat
  bejegyzés nélküli aranyat anélkül, hogy helyben látszana.
- A settled asset alatt a §9 négy lábából **három** megvan (fixtúra, property, paritás,
  valódi-audió az ADR 0567-ből) — ténylegesen mind a négy; ami a bekötéshez még hiányzik, az
  a **Klangio-oldal in situ** ellenőrzése és maga a csere (ADR 0567 D4).
- A `strum_metric_channel_parity.json` mostantól nyilvántartott, a mért/szintetikus
  összetétele kimondva.

## Amit NEM állítunk

- **A CI állapotát nem mértük.** A „R32 óta piros" **következtetés** a CI
  `flutter test --coverage` (útvonal nélküli) hívásából és a Linux-oldali bejárás
  működéséből; gh-t nem hívok, tehát ezt az orchestrátornak kell visszaigazolnia.
- **A négy régebbi CRNN paritás-arany szövegét nem írtuk át.** Ugyanazt az artefaktum-osztályt
  a rövidebb „no third-party audio" fordulattal írják le; a két új bejegyzés pontosabb
  (származtatott log-mel jellemző, nem audió, nem invertálható). Az eltérés **kimondva** a
  bejegyzésben, de négy korábbi kör proveniencia-szövegét nem én írom át.
- **A metric-channel fixtúrát nem generáltuk újra**, hogy esetenként jelölje a mért és a
  szintetikus eseteket. Ez valódi javítás, de a fájl 221 KB-ját cserélné egy olyan körben,
  aminek nem ez a tárgya; a hiány a manifesztben **olvasható**.
