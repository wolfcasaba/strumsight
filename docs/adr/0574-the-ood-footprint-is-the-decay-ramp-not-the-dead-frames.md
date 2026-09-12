# ADR 0574 — A csonkítatlan ablak OOD-lábnyoma a LECSENGŐ RAMPA, nem a négy halott frame: 8 frame a 15-ből, és a saját lokalizációs hipotézisemet a rá épített próba döntötte meg

- **Státusz:** elfogadva (mérés; az ADR 0572 D3 „nem magyarázzuk meg"-jét **szűkíti**, nem
  oldja fel; semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-12
- **Kör:** E18-R44
- **Kapcsolódó:** ADR 0572 D3 (az OOD-állítás, amit ez lokalizál), ADR 0571 (a letisztult
  tier in-situ nyeresége), ADR 0554 (a mindkét levágáson tanított asset — itt a **kontroll**),
  ADR 0570, `ml/probe_settled_window_frames.py`, `ml/probe_gate_window_jitter.py`,
  `docs/LESSONS.md` L681, L689

## Kontextus

Az ADR 0572 D3 kimondta, hogy a szállított assetnek csonkítatlan ablakot adni **eloszláson
kívüli** bemenet, és hogy egy OOD bemenet nem „rosszabb", hanem **kiszámíthatatlan** — két
korpusz, ellentétes előjel. Mechanizmust szándékosan nem írt rá (L681).

Van viszont egy **kisebb** kérdés, ami mérhető, és amit eddig senki nem tett fel: **a tenzor
MELYIK része hordozza a kárt.** Ez bemenet-geometria, nem modell-viselkedés.

## Döntés

### D1 — A geometria, a gyorsítótárakból mérve: a csonkítás lábnyoma egy RAMPA

Az ablak 15 frame (PRE 3 + POST 12), hop 256. A `live70` gyorsítótárban az audió az onset +
70 ms-nál elvágva, tehát a farok-frame-ek a csend log-melje. Mind a 11767 soron:

```
  klangio live70     sor-szórás frame-enként (mel-átlag)
    f0..f9    1,51 .. 2,08      <- valódi jel
    f10       1,736             <- a vágás EBBE a frame-be esik
    f11..f14  0,00153           <- KONSTANS. átlag −13,81, mind a 11767 ablakon.
  klangio live_full
    f0..f14   1,655 .. 2,069    <- minden frame hordoz jelet
```

Tehát 4 frame a 15-ből — a tenzor **26,7%-a** — halott konstansból élő jellé vált, amikor a
letisztult tier csonkítatlan ablakot ad. **Ez volt a hipotézis:** a kár ott van.

De a **különbség-profil** nem lépcső, hanem rampa:

```
  |Δ| (live70 − live_full), frame-enként
  f0    f1    f2    f3    f4    f5    f6    f7    f8    f9    f10   f11   f12  f13  f14
  0,12  0,24  0,40  0,59  0,84  1,19  1,73  2,62  4,20  7,38 14,04 15,03 14,99 14,95 14,90
```

Mert az 1024 mintás analízis-ablak **több frame-en át átlóg** a vágáson. A f9 átlaga a
`live70`-ben már −6,06, a `live_full`-ban +1,32 — a f9 tehát már félig elhallgattatott, pedig
a 70 ms-os határidőn belül van.

### D2 — Mérve: a halott régió a kár 40–56%-a, a rampa a 95%-a

Két egymást kiegészítő szerkesztés **ugyanazokon** az ütéseken: `RESTORE` (a csonkítatlanból
a `live70` értékeit visszatenni a k. frame-től) és `INJECT` (a 70 ms-osból a csonkítatlan
farkát átvenni). Minden k-ra végigsöpörve, tehát **k=0-nál a szerkesztés az ellenkező
alapvonal** — beépített kontroll, és mind a négy blokkban **pontosan** egyezik.

```
  szállított asset           fold A (n=3721)        fold B (n=2013)     mind 0,85-es kapun
  70 ms                      0,9490                 0,7950
  csonkítatlan               0,5712  (−0,3777)      0,5578  (−0,2372)
  RESTORE f11..14            0,7826  javít 56 %     0,6554  javít 41 %
  RESTORE f 9..14            0,8900         84 %    0,7521         82 %
  RESTORE f 7..14            0,9339         96 %    0,7828         95 %
  INJECT  f11..14            0,7964  reprodukál 40% 0,7372  reprodukál 24 %
  INJECT  f 7..14            0,5860             96% 0,6035             81 %
```

A halott konstans régió **egyik** foldon sem magyarázza a kár felét. Amit ~95%-ban magyaráz,
az a **f7..f14** — a csonkítás *teljes* lábnyoma, a lecsengő rampával együtt.

**Tehát: 8 frame a 15-ből, nem 4 — és a kárt túlnyomórészt azok a frame-ek hordozzák, amik
csak ELHALVÁNYULNAK, nem azok, amik kilapulnak.** A legszembetűnőbb különbség nem ott volt,
ahol a kár.

### D3 — És a settled asset UGYANAZOKBAN a frame-ekben a tükörképe

Ez a kontroll, ami a szállított asset számát értelmezhetővé teszi, nem csak rosszá:

```
  settled asset (mindkét levágáson tanult), fold A, 0,2929-es kapun
  70 ms                      0,5055
  csonkítatlan               0,6363   (+0,1309)
  RESTORE f 7..14            0,6399   <- a nyereség ugyanott ÁLL ELŐ
```

**Ugyanaz a bemeneti régió hordozza a veszteséget annak az assetnek, ami egy levágáson
tanult, és a nyereséget annak, ami kettőn.** Ez az ADR 0572 D3 állítása — most lokálisan és
mérve.

### D4 — A próba saját korlátja, kimondva

Minden szerkesztés olyan bemenetet épít, amit **egyik** tanító eloszlás sem tartalmaz, tehát
az egy-frame-es szerkesztések **nem tiszta kontrafaktuálisok**, és saját műtermékeket
termelnek. A legélesebb: a **settled** assetn **csak a f14**-et visszatenni konstansra
katasztrofális (fold A macro **0,3325**, le-F1 **0,1368**), miközben a f13..14 visszatétele
rendben van (0,6351) — egy egy-frame-es szakadék egy élő jel végén.

**Ezt nem értelmezzük.** Azt határolja be, **milyen felbontásig** olvasható a próba: a
8-frame-es következtetés áll (két foldon, két irányban, monoton), a frame-enkénti ingadozás
nem.

### D5 — Amit ez NEM old fel, és egy alternatíva, amit a saját korábbi mérésem zár ki

**Nem** magyarázzuk meg, *miért* reagál a modell úgy arra a régióra. Hogy melyik frame
hordozza a kárt: bemenet-geometria. Hogy miért: modell-viselkedés, és **mérve nincs** (L681).

És **nem** javasoljuk a kézenfekvő alternatívát sem („adjunk neki 70 ms-alakú, de későbbi
ablakot, hogy in-distribution maradjon"): a `ml/probe_gate_window_jitter.py` egy korábbi
körben megmérte, hogy a szállított asset az ablak-középre **meredeken aszimmetrikus**
(+15 ms → 0,802, +30 ms → 0,454 a 0,439-es kapun). Az ablak **elmozgatása** tehát nem ingyenes
alternatívája a **megnyújtásának**.

## Következmények

- A két-tier bekötésének egy **mért** korlátja van: egy olyan assetnek, ami a letisztult
  ablakot használni akarja, a **f7..f14** régión kell tanulnia — nem csak „több audiót adni".
  Ez pontosan az, amit a `train_live_3c_settled.py` két-levágásos pólusa tesz.
- A `probe_settled_window_frames.py` mostantól bármely jelölt assetre lefuttatható, és egy
  futásból megmondja, hogy a jelölt a rampán **tanult-e**.

## Amit NEM állítunk

- **Nincs mechanizmus.** Lásd D5.
- **Nincs in-situ szám**: orákulum-ablakok a gyorsítótárból, a Python úton.
- **A szintek egyik foldon sem új-játékos számok** (ADR 0573): a fold B a szállított assetre
  *felvétel*-diszjunkt, de nem *játékos*-diszjunkt, a fold A 78%-át pedig tanulta. A D2 és D3
  viszont **soron belüli** összevetés — ugyanaz az ablak, ugyanaz a modell, csak a farok
  szerkesztve —, tehát a fold nehézsége és a tanítási kitettség **kiesik**. A SZINTEKET az
  ADR 0573 szerint kell olvasni, az ARÁNYOKAT nem.
- **Egy korpusz.** Klangio. A GuitarSet oldalán ez a söprés nincs megismételve.
