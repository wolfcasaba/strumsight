# Practice Engine — valódi eszközös tesztmátrix (E02-R20 A8)

A HORIZON-szabály értelmében a szintetikus zöld sosem „done" — a Practice
Engine Epic-2 zárásának végső elfogadási predikátuma a user valódi-gitáros
APK-tesztje. Ez a mátrix a teszteseteket és a kitöltési útmutatót tartalmazza;
**a felhasználó tölti ki** a „pass / részleges / fail" és a szabad szöveges
megjegyzés mezőket minden cellára.

> **Practice V2 elérhetőség (E02-R21, GOV-05a).** A
> `practiceSessionHostProvider` az aktív session inputokból állítja elő a
> controller-backed hostot; csak aktív input hiányában `null`. A Practice Hub
> → Setup → Session út ezért a `practiceEngineV2Enabled` flaggel elérhető
> lab buildben. A következő cellák készülékes bizonyítéka továbbra is a user
> menetéhez tartozik.

## 1. Kitöltési útmutató

### 1.1 Mit jelent a „pass"

- **pass** — a készüléken futó APK-val a teszteset lejátszható, a mért
  eredmény (pontszám / mért BPM / coach-üzenet) a dokumentált küszöbön
  belül van, és nincs megfigyelt crash / audio drop / UI fagyás.
- **részleges** — a teszteset lejátszható, de a mért eredmény a küszöbön
  kívül esik, VAGY egy-két specifikus eltérés van a mért és az elvárt
  között; a megjegyzés mezőben rögzíteni kell a pontos eltérést.
- **fail** — a teszteset nem játszható le (crash, hang nélküli session,
  empty state, stb.) VAGY a mért eredmény a küszöbön kívül esik és a
  használhatóság sérül.

### 1.2 Mit kell rögzíteni minden cellában

- **Készülék:** pontos modell (pl. „Pixel 6a") és Android-verzió
  (pl. „Android 14, API 34").
- **Build:** az APK artifact neve (a CI-runjából, pl.
  `strumsight-1.0.0+1-N-sha-development.apk`).
- **Hang:** akusztikus gitár / elektromos gitár erősítőn / vonal-bemenet
  (audio interface) / szintetikus jel (teszt-benchmark).
- **Hangszóró/fejhallgató:** Bluetooth audio (opcionális, az R16-os és
  az R18-as reviewer jegyzőkönyvekben külön cella).
- **Mért eredmény:** numerikus érték, ahol van (pl. „73% overall").
- **Megjegyzés:** szabad szöveges, max 200 karakter.

### 1.3 Mikor „done"

A mátrix akkor tekinthető **lezártnak**, ha az alábbi 4 kötelező cella
**pass** minősítésű a készüléken:

1. Akusztikus gitár + 4/4 strum pattern + csendes környezet
2. Akusztikus gitár + 3/4 first waltz + csendes környezet
3. Akusztikus gitár + 10 perces free practice (aktív idő ≥ 9:30)
4. Háttérbe küldés futó session közben → session biztonságosan pausol

A többi cella **részleges** vagy **fail** is lehet — azokat a user
dokumentálja, és a **kovetkező Epic** (vagy javító kör) tervét ez alapján
frissíti.

---

## 2. Mátrix

### 2.1 Bemeneti eszköz

| # | Készülék | Android-verzió | API | Megjegyzés |
|---|---|---|---|---|
| 2.1.1 | (user tölti) | (user tölti) | | |

### 2.2 Self-practice (Hub → Setup → Session) — **PENDING készülékes ellenőrzés**

A GOV-05a rollout után ez az út a Learn fül Practice Hub belépési pontjáról
indul a `practiceEngineV2Enabled` ON ágon. A következő sorok PENDING-ek,
amíg a user valós eszközön ki nem tölti őket.

| # | Mód | Tempó | Zaj | Hangkeltés | Eredmény | Pass/Fail |
|---|---|---|---|---|---|---|
| 2.2.1 | Strum pattern | 70 BPM | csendes | akusztikus gitár | | |
| 2.2.2 | Strum pattern | 50% speed | csendes | akusztikus gitár | | |
| 2.2.3 | Strum pattern | 100% speed | mérsékelt háttérzaj | akusztikus gitár | | |
| 2.2.4 | Strum pattern | 100 BPM | csendes | elektromos gitár erősítőn | | |
| 2.2.5 | Chord changes (G↔D) | 60 BPM | csendes | akusztikus gitár | | |
| 2.2.6 | Chord progression (C–G–Am–F) | 80 BPM | csendes | akusztikus gitár | | |
| 2.2.7 | Rhythm only (quarters) | 80 BPM | csendes | akusztikus gitár | | |
| 2.2.8 | Free practice | szabad | csendes | akusztikus gitár | | |
| 2.2.9 | Free practice | szabad | mérsékelt háttérzaj | akusztikus gitár | | |

### 2.3 Migrated Learn (Learn képernyő, `migratedLearnEnabled` ON) — **PENDING készülékes ellenőrzés**

A GOV-05c rollout után a migrated Learn útvonal alapértelmezetten elérhető
development és lab buildben; productionben továbbra is kikapcsolt. A következő
sorok PENDING-ek, amíg a user valós eszközön nem tölti ki őket.

| # | Lecke | Tempó | Zaj | Hangkeltés | Eredmény | Pass/Fail |
|---|---|---|---|---|---|---|
| 2.3.1 | Első lecke (4/4, downstrokes) | default | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.2 | 3/4 lecke (waltz) | default | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.3 | Akkordváltás lecke (G↔D) | default | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.4 | Easy mód aktiválva | default | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.5 | 50% speed | 50% | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.6 | 75% speed | 75% | csendes | akusztikus gitár | PENDING | PENDING |
| 2.3.7 | 100% speed | 100% | csendes | akusztikus gitár | PENDING | PENDING |

### 2.4 Hangkeltési mátrix (self-practice és migrated Learn fölött)

| # | Hangkeltés | Szint | Eredmény | Pass/Fail |
|---|---|---|---|---|
| 2.4.1 | Akusztikus gitár | hangerő 5/10 | | |
| 2.4.2 | Akusztikus gitár | hangerő 8/10 | | |
| 2.4.3 | Elektromos gitár, hangerő 3/10 | | | |
| 2.4.4 | Elektromos gitár, hangerő 7/10 | | | |
| 2.4.5 | Vonal-bemenet (audio interface) | | | |
| 2.4.6 | Bluetooth audio kimenet | (opcionális, R18 reviewer megjegyzés) | | |

### 2.5 Állapot-átmenetek (a §11 reviewer-tesztek készülékes megfelelői)

| # | Állapot-átmenet | Elvárás | Eredmény | Pass/Fail |
|---|---|---|---|---|
| 2.5.1 | Permission denial | „Microphone permission is required" + Settings CTA | | |
| 2.5.2 | Permission grant | session a `preparing → ready` úton halad | | |
| 2.5.3 | Pause | session pausol, mikrofon ikon kialszik | | |
| 2.5.4 | Resume | count-in újraindul, session folytatódik | | |
| 2.5.5 | Háttérbe küldés (app lifecycle background) | session biztonságosan pausol | | |
| 2.5.6 | Képernyőzár | session pausol, feloldáskor resume | | |
| 2.5.7 | Mikrofon busy | „Couldn't start the microphone" + Retry | | |
| 2.5.8 | 10 perces session | nincs észlelt memóriaemelkedés (>50 MB), verdict history bounded | | |
| 2.5.9 | Finish → Result | overall score megjelenik, insight section ARB-szöveggel | | |
| 2.5.10 | Cancel | result képernyő nem jelenik meg, session cancelled | | |
| 2.5.11 | Speed Builder 3 pass → step up | tempó lépésenként nő (a Speed Builder policy szerint) | | |
| 2.5.12 | Speed Builder 2 fail → step down | tempó csökken, de start BPM alá nem megy | | |

### 2.6 Balkezes mód

| # | Beállítás | Eredmény | Pass/Fail |
|---|---|---|---|
| 2.6.1 | Balkezes mód ON + 4/4 strum pattern | highway tükrözve, scorer target direction nem invertálva (SDD §22.2) | | |
| 2.6.2 | Balkezes mód OFF + 4/4 strum pattern | highway normál irányban | | |

### 2.7 Akkumulátor-takarékos mód

| # | Beállítás | Eredmény | Pass/Fail |
|---|---|---|---|
| 2.7.1 | Akkumulátor-takarékos mód ON + 10 perces free practice | session nem szakad meg, mic lease megmarad | | |
| 2.7.2 | Akkumulátor-takarékos mód OFF + 10 perces free practice | összehasonlító baseline | | |

### 2.8 Kontraszt / reduced motion / screen reader

| # | Beállítás | Eredmény | Pass/Fail |
|---|---|---|---|
| 2.8.1 | 200% szövegméret + Hub | nincs overflow, minden gomb elérhető | | |
| 2.8.2 | Landscape (915×412) + Setup | nincs overflow | | |
| 2.8.3 | Reduced motion ON + Session | nincs animáció, az információ megmarad | | |
| 2.8.4 | TalkBack ON + Hub | minden kártya felolvasható, „Open <title>" formátumban | | |

### 2.9 Song Trainer V2 (Learn → Song Trainer) — **PENDING készülékes ellenőrzés**

A GOV-05a rollout után a Song Trainer könyvtár a Learn fülről a
`songTrainerV2Enabled` ON ágon érhető el. Minden sora PENDING, amíg a user
valós eszközön nem rögzíti az eredményt.

| # | Menet | Elvárás | Eredmény | Pass/Fail |
|---|---|---|---|---|
| 2.9.1 | Learn → Song Trainer | a könyvtár megnyílik crash nélkül | PENDING | PENDING |
| 2.9.2 | Song Trainer → új dal | az editor megnyílik és menthető dokumentumot ad | PENDING | PENDING |
| 2.9.3 | Song Trainer → import | az import belépési pont elérhető, hiba esetén érthető visszajelzést ad | PENDING | PENDING |

---

## 3. A készülékes menet eredményének visszacsatolása

A mátrix kitöltése után a user a következő dokumentumba foglalja össze az
eredményt (külön fájl, dátum + készülék + build):

```
docs/manual-testing/practice-engine-device-matrix-result-<YYYY-MM-DD>.md
```

A fájl kötelező mezői:

- Dátum és futtatott build (SHA)
- A 4 kötelező cella (2.1 §1.3) eredménye
- Az önálló Practice V2 §2.2 cellák eredménye
- A migrated Learn §2.3 cellák eredménye
- A Song Trainer V2 §2.9 PENDING celláinak eredménye
- Az akkumulátor-takarékos mód §2.7 cellák eredménye
- A screen reader / TalkBack §2.8 cellák eredménye
- Összesítés: hány pass / részleges / fail cella van
- Javaslat a következő Epic-3 / R21+ köreinek prioritásaira

A visszacsatolás után az Epic-2 §5 DoD-tábla „teljesül" / „részleges" /
„nem teljesül" cellái **véglegesítődnek** — amíg ez nincs meg, az Epic-2
„lezárt, de nem véglegesített" státuszban marad (HANDOFF §1).

---

## 4. Hivatkozások

- `docs/sdd/03-epic-02-practice-engine.md` §25.6 — a mátrix specifikációja.
- `docs/sdd/epic-02-completion-report.md` §6 — a zárójelentés „Valódi
  eszközös audio-regresszió" szakasza.
- `HANDOFF.md` §3 — a §16.3/§16.4 user-mérés hivatkozásai.
- Epic-1 precedens: `docs/sdd/epic-01-completion-report.md` §6 — ugyanez
  a struktúra, a HORIZON-szabállyal.
