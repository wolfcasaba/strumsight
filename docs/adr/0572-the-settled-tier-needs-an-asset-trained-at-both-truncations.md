# ADR 0572 — A letisztult tier MINDKÉT levágáson tanított assetet kíván: a szállítotton Klangion −0,2455, és ez az egész arcot egyetlen hiányzó artefaktumra fűzi

- **Státusz:** elfogadva (mérés; az ADR 0571 GuitarSet-alapú esetét **korlátozza**, és egy
  korábbi állításomat **javítja**; semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0571 (a GuitarSet in-situ +0,168 — itt korlátozva), ADR 0570 (a
  margó-routing asset-specifikus), ADR 0569 (a csere visszavonva; a telepítési korpusz),
  ADR 0563 (a routing-szabály), ADR 0554 (az asset, ami mindkét levágáson tanult),
  ADR 0550 (kereszt-korpusz transzfer), ADR 0553 (adat-diagnózis — itt **korlátozva**),
  `docs/LESSONS.md` L684 §3, L686

## Kontextus

Az ADR 0571 megmérte in situ, hogy a **szállított** assetn a „minden ütést letisztítani"
szabály **+0,1679** macrót ér — GuitarSeten. Az ADR 0569 viszont ugyanebben a körben mutatta
meg, hogy GuitarSet és Klangio **előjelben** is eltérhet, és hogy a **Klangio** a telepítési
feltétel (telefon-mikrofon). A saját L684 §3 szabályom szerint tehát a kereszt-korpusz deltát
**nem szabad** a telepítési korpusz mérése nélkül döntésre vinni.

A Klangio korpusz-audió nincs a gépen, de a **gyorsítótárazott** ablakok mindkét levágáson
megvannak (`klangio_live70.npz`, `klangio_live_full.npz`, sor-azonosak), és az ADR 0571 D4
épp ezt a kérdés-típust korroborálta: az orákulum-műszer **delta-kérdésekre** érvényes.

## Döntés

### D1 — Mérve: a szállított assetn a letisztult tier Klangion −0,2455

A szállított asset **saját tiszta** foldján (`split_by_recording` eval fold, 2013 ütés, 39%
felütés), a szállított 0,85-es kapun:

```
  tier              macro     le-F1    fel-F1
  csak gyors       0,7950    0,8321   0,7579
  csak letisztult  0,5495    0,7872   0,3118     (−0,2455)
```

A **felütés omlik össze**: 0,7579 → 0,3118. A margó-routolt hibrid itt pozitív, de
jelentéktelen (+0,0043 a 0,30-as küszöbön, +0,0101 a 0,90-esen) — vagyis a „mindent
letisztítani" szabály a telepítési korpuszon **katasztrofális**, a margó-alapú pedig
**semleges**.

### D2 — De a MINDKÉT levágáson tanított assetn Klangion IS segít: +0,1299

Ugyanaz a próba, ugyanaz a korpusz, a settled asset a saját tiszta foldján (gitáros 4,
3721 ütés, 38% felütés), a saját 0,2929-es kapuján:

```
  tier              macro     le-F1    fel-F1
  csak gyors       0,5055    0,4753   0,5357
  csak letisztult  0,6354    0,6788   0,5920     (+0,1299)
```

*(A műszer hitelesítve: ez a két szám az ADR 0555 saját tábláján **0,5055** és **0,6363** —
az utóbbi 0,001-en belül, a kapu-kezelés apró eltérésével.)*

**Összefoglalva a négy cella:**

```
  asset                                 GuitarSet       Klangio (telepítés)
  szállított (csak live70-en tanult)    +0,1679 (in situ)    −0,2455
  settled     (mindkét levágáson)       +0,0655              +0,1299
```

### D3 — Amit ez mond: egy levágás, amin a modell nem tanult, NEM használható

A szállított asset a csonkítatlan ablakot sosem látta (`train_live_3c.py` csak `live70`-et
tölt). Az ott mutatott viselkedése a két korpuszon **ellentétes előjelű** — ami pontosan az,
ahogy egy eloszláson kívüli bemenet viselkedik: nem rosszul, hanem **kiszámíthatatlanul**.

Ez **nem mechanizmus-állítás**, hanem a bizonyíték általánosítása: két korpusz, azonos
eloszláson kívüli bemenet, **ellentétes** előjel. Hogy a telefon-mikrofon utóhangja, a
zengés, a lecsengés vagy más okozza, **nem tudjuk**, és nem írunk rá magyarázatot (L681).

**Ezért a két-tier döntés szükséges feltétele egy olyan asset, ami MINDKÉT levágáson
tanult** — pont az, amit az ADR 0554 megépített. Azon az assetn a letisztult tier **mindkét**
korpuszon pozitív.

### D4 — És ezzel az egész arc EGYETLEN hiányzó artefaktumra fűződik

```
  ADR 0563  a margó-routing szabálya    -> a settled assetn érvényes, a szállítotton nem
                                           (a margó ott lapos, ADR 0570)
  ADR 0571  „minden ütést letisztítani" -> a settled assetn érvényes MINDKÉT korpuszon,
                                           a szállítotton a telepítésin −0,2455
  ADR 0569  az asset cseréje            -> a settled asset a telepítési korpuszon
                                           visszaesik, tehát nem szállítható
```

Mindhárom ugyanarra vár: **egy asset, ami (a) mindkét levágáson tanul, (b) a szállítottat a
Klangion is legyőzi vagy hozza, (c) és amin a margó jelez.** Egy tanító kör **három** ADR-t
nyit fel. Ez a következő kör specifikációja, nem egy kívánságlista.

### D5 — Egy korábbi állításomat javítom: a felütés nem adat-kérdés, hanem transzfer

Az ADR 0571 D3-ban azt írtam, hogy „aminek több hang kellett, az a lefelé ütés volt; a
felütéshez **adat** kell". **Ez GuitarSet-alapú volt, és így általánosként téves.** Ugyanaz
a szállított asset a **Klangion** a felütést **0,7579**-cel hozza, GuitarSeten **0,2007**-tel:

```
  szállított asset, gyors tier, fel-F1     GuitarSet 0,2007     Klangio 0,7579
```

A modell tehát **tud** felütést — a saját korpuszán. Amit nem tud, az a **GuitarSetre
átvinni**, és ez az **ADR 0550** diagnózisa („a direction-defekt kereszt-korpusz transzfer,
nem hiányzó adat"), nem az ADR 0553-é. Az ADR 0553 adat-állítása a **settled** assetre és a
GuitarSet-felütésre áll; általános állításként nem.

*Egy korpuszon mért osztály-gyengeség az osztályról szóló állítás csak akkor, ha a másik
korpuszon is megvan.*

## Következmények

- A „minden ütést letisztítani" **nem kötődik be** a szállított assettel. Az ADR 0571
  mérése áll; a belőle olvasható **ajánlás** csak GuitarSetre volt érvényes.
- A `settledTier` marad **false**, és most már mindhárom lehetséges szabálya (margó-routing,
  mindent-letisztítani) meg van mérve mindkét korpuszon.
- A próba mostantól `--corpus=klangio [--fold=eval|guitarist4]`-gyal is fut, korpusz-audió
  nélkül, és **kiírja, melyik assetet és melyik korpuszt** mérte.

## Amit NEM állítunk

- **A Klangio-számok ORÁKULUM-ablakosak**, nem in situ (a korpusz nincs a gépen). Az ADR
  0571 D4 szerint ez **delta-kérdésekre** korroborált, szintekre nem — és itt delta a
  kérdés. Egy szállítási döntés előtt a Klangio in-situ söprése is kell.
- **Nem magyarázzuk meg**, miért fordul az előjel a két korpusz között egy eloszláson kívüli
  bemeneten.
- **A D2 két sora különböző foldokon van** (a szállított a saját eval-foldján, a settled a
  gitáros-4-en), mert mindegyik a **saját tiszta** foldján mérendő. Ezért a D2 két sora
  **nem** egymás ellen olvasandó — az asset-összevetés az ADR 0569 dolga; itt minden sor egy
  **önmagán belüli** fast→settled delta.
- **A GuitarSet settled-asset sora (+0,0655)** az ADR 0563 settled-only értéke
  (0,5262 → 0,5917), nem a margó-routolt +0,0551.
