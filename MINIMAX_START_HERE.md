# MiniMax Start Here — StrumSight, E18 strum-ML arc

Ez a belépő az **E18 strum-felismerés mérési arc** folytatásához, nem általános onboarding.
Az ágensszerepek teljes szabálya: [`AGENTS.md` §15](AGENTS.md).

> **ELSŐ TEENDŐ:** a branch **piros a CI-ban**, ezért **nincs telepíthető APK**. A teljes,
> mért blokkoló-lista és a javítási sorrend a **§5b**-ben. A user kért egy APK-t — addig nem
> lesz, amíg az az öt teszt nem zöld. A §6 mérési köre csak utána jön.

## 0. Hol tart a munka (egy bekezdés)

A `down`/`up` pengetésirány-felismerés kétszintű („gyors" 70 ms / „letisztult" 238 ms)
bekötése **nem történt meg**, és szándékosan: a `settledTier` flag `false`, a szállított asset
(`assets/ml/strum_crnn_live_3c.bin`) és a szállított kapu (`noStrumThreshold = 0.85`)
**érintetlen**. Az elmúlt körök **mérések** voltak, és több saját korábbi következtetést
vontak vissza. A jelenlegi állás:

- **A letisztult tier MŰKÖDIK**, ha az asset mindkét levágáson tanult: a telepítési korpuszon
  (Klangio, telefon-mikrofon) **in situ +0,1236** macro, mindkét irány javul (ADR 0579).
- **A szállított asseten ugyanez −0,3628**, mert annak a csonkítatlan ablak eloszláson kívüli
  bemenet (ADR 0572 D3, lokalizálva ADR 0574: a 15 frame-ből a f7..14 sáv).
- **Nem tudjuk, melyik RECEPT jobb a telepítési korpuszon** (ADR 0578): a nettó előjele
  seedenként változik. A GuitarSet-oldal viszont stabil (**+0,3765 ± 0,0713**).
- A jelölt recept az **R4** (`ml/experiment_recipe_ladder.py`); az R5 (regularizáció nélkül)
  **elutasítva** (ADR 0580).

## 1. Olvasási sorrend (ebben a sorrendben, ne ugorj)

1. `AGENTS.md` — **§9 (DSP/ML), §12 (gate), §13 (git), §15 (ágensszerepek)** kötelező.
2. `HANDOFF.md` — **csak az utolsó ~200 sor**. A fájl 15 000+ sor, a teteje történelem.
   A legutóbbi kör-blokk végén a `KÖVETKEZŐ:` lista a feladatsor.
3. `docs/rag/chunks/018-strum-ml-pipeline.md` — **az utolsó ~400 sor**. Ez az arc angol nyelvű
   műszaki naplója; minden szám provenance-szal.
4. `docs/LESSONS.md` — **L681–L691**. Ez a legfontosabb olvasmány: tizenegy tanulság arról,
   hogyan lehet ezen a mérésen tévedni. A §4 alatt kiemelem, amit MINDENKÉPP be kell tartani.
5. `docs/adr/0573` … `0580` — a nyolc legutóbbi döntés. A `0578` és a `0580` a
   legfontosabbak, mert **saját korábbi állításokat vonnak vissza**.

## 2. Környezet (mért tények, ne térj el tőlük)

```
  worktree        C:\src\ss-e18        ← ASCII útvonal, KÖTELEZŐ
  branch          claude/e18-r06-verify-followup
  flutter         /c/src/flutter/bin/flutter     (3.44.2)
  dart            /c/src/flutter/bin/dart
  python          /c/Users/kcsab/.venv/Scripts/python   (TensorFlow 2.21, numpy, scipy)
  GuitarSet       GUITARSET_DIR=/c/Users/kcsab/Downloads/recipewis   (helyben olvasva)
  Klangio         ml/data/klangio/   82 × _phone.wav + 82 × .strums  (gitignore-olt)
```

**Az ASCII worktree nem kozmetika.** A valódi projekt-útvonal `gitár`-t tartalmaz, és attól a
`flutter analyze` **255-tel** kilép. Mindig a `C:\src\ss-e18`-ban dolgozz.

## 3. Nem tárgyalható korlátok

1. **Harmadik-fél audió SOHA nem kerül a repóba.** A licenc, ami a használatot engedi, a
   **terjesztést** nem. Csak MÉRÉS kerül le írásban. `ml/data/` és `*.npz` gitignore-olt — ezt
   ne bántsd, és ne commitolj `.wav`-ot. Ellenőrzés: `git ls-files | grep -c '\.wav$'` → **0**.
2. **A Chordino referencia GPL-2+**, a StrumSight privát (`publish_to: 'none'`). A **publikált
   módszert** valósítsd meg; referencia-forrást, kommentet vagy táblázott konstanst **ne
   másolj**. Őr: `test/tooling/reference_model_licence_guard_test.dart`.
3. **`git add .` és `git add -A` TILOS** (AGENTS.md §13). Tételesen stage-elj.
4. **Destruktív git külön engedély nélkül tilos**: `git reset --hard`, `git checkout -- .`,
   `git clean -fd`, `git stash drop`, force push.
5. **Soha ne láncold** a `flutter analyze && flutter test`-et egy parancsba — **OOM**.
6. **A MÉRCÉHEZ ne nyúlj**: `tools/round-gate.sh`, `tool/ci/**`, `.github/workflows|actions/**`,
   `schemas/**`. Egy PreToolUse-őr blokkolja. Ha a kör tényleg ezt kívánná: **állj meg és
   jelentsd**.
7. **Az APK-t és a teljes CI-t az orchestrátor indítja** (ADR 0053). Te ne hívj `gh`-t, csak ha
   a user kifejezetten kéri.
8. **Semmit ne kapcsolj fel** (`settledTier`, asset-csere, kapu-mozgatás) a §4 elfogadási
   kritériumai nélkül.

## 4. A mérési fegyelem, amit ez az arc MEGFIZETETT

Ez a szakasz a legtöbbet érő része ennek a fájlnak. Minden pont egy **visszavont saját
állítás** árán született.

1. **Két egyező seed NEM replikáció** ([[L691]], ADR 0580). Háromszor fordult elő, hogy az
   s42 és az s1 egyetértett, és az s2 megfordította. **Minden recept-állításhoz mind a három
   `honest_eval.STD_SEEDS = [42, 1, 2]` kell**, és ha egy delta előjele nem egyezik mind a
   háromon, az eredmény **„nem megállapított"**, nem „kisebb". Előjel-egyezés, NEM t-próba
   (n=3-nál a szórás-becslés maga is zajos).
2. **Nevezd meg, melyik ASSETET és melyik KORPUSZT mérted** ([[L682]]). Egyszer elosztottam
   egy szám egy modelltől egy számmal egy MÁSIK modelltől, „30 pontos résnek" hívtam, és
   órákig kerestem a mechanizmusát. Nem volt ott.
3. **A „held-out"-nak MÉRTÉKEGYSÉGE van** ([[L687]], ADR 0573). A `split_by_recording`
   **felvétel**-diszjunkt, **nem játékos**-diszjunkt: a szállított asset a 4-es gitáros 27
   felvételéből **22-t tanult**. Minden Klangio-száma **same-player**. Mielőtt két assetet
   összevetsz, kérdezd meg: **miben** diszjunkt a régebbi splitje?
4. **Mechanizmust csak mérve írj le** ([[L681]]). Ha nem mérted meg, írd ki, hogy nem tudod.
   Ebben az arcban három mechanizmus-állítást döntött meg a saját mérésem.
5. **Egy elfogadási kritériumot a SEJTEK dönthetőségére kell ellenőrizni** ([[L688]]). Az
   ADR 0569 D4 olyan kritériumot írt fel, amit **egyetlen jelölt sem teljesíthet**, mert nincs
   dönthető sejt. Írd fel a sejt-táblát, MIELŐTT a kritériumot felírod.
6. **„X nem elérhető ebben a környezetben" egy MÉRÉS** ([[L690]], ADR 0576). Három kör épült
   arra, hogy a Klangio korpusz nincs a gépen. **Ott volt**, 9,5 órával korábban, és a mérésben
   használt gyorsítótár éppen annak beolvasásából épült. Írd ki a parancsot, ami ellenőrizte.
7. **Egy fixtúra, amit senki nem olvas, nem bizonyíték** ([[L683]]). Minden új guardot
   **mindkét irányban** ellenőrizz: passzol a helyes állapoton, ÉS elsül a hibáson.

## 5. A gate — egyetlen futtatható artefaktum

```bash
cd /c/src/ss-e18
FLUTTER_BIN=/c/src/flutter/bin/flutter DART_BIN=/c/src/flutter/bin/dart \
  bash tools/round-gate.sh <teszt-útvonal> [további teszt-útvonalak...]
```

- **Legalább egy teszt-útvonal kötelező.**
- **Soha ne pipe-old** (`| tail` stb. a parancson belül) — a kilépési kódot elfedi.
- Lépések: format → analyze → minden megnevezett teszt → architecture → secrets → l10n.
- A teljes suite + property gate + APK a CI-ban fut, nem itt.

## 5b. ELŐBB EZ: a branch PIROS a CI-ban, és emiatt nincs APK

**Állapot (mérve, 2026-09-13, a `bfc255da` commiton):** a `build-apk.yml` az APK **előtt**
futtatja a quality gate-eket, tehát amíg ezek pirosak, **APK nem keletkezik**. Minden más
APK-út (`release-apk.yml`) ugyanezt a gate-et futtatja — kapu-mentes út nincs.

**A gyökér EGY dolog:** három feature-commit landolt a branchen, és **négy őrt nem frissített**
senki — `4cbd09fa feat(app): … route the community surface`, `677b72e6 feat(today): the daily
loop`, és a curriculum-körök. A termék jó; az őrök elavultak.

```
  CI-ban piros                                         állapot
  1. test/e2e/full_app_walkthrough_test.dart           MEGJAVÍTVA (lásd lent)
  2. test/tooling/placeholder_wiring_test.dart         RÉSZBEN: a walkthrough-hiba eltűnt,
                                                       az A4 partíció maradt
  3. test/core/architecture_dependency_test.dart       NYITOTT
  4. test/ui/goldens/e13_r17_screens_golden_test.dart  NYITOTT (pixel-diff)
  5. test/ui/goldens/e15_r13_full_variant_matrix_test.dart  NYITOTT (A1 completeness)

  CSAK LOKÁLISAN piros (Windows-útvonal, CI-ban ZÖLD — NEM blokkoló):
     test/core/events/event_schema_compatibility_test.dart
     test/core/store_race_sweep_test.dart
```

**1 — MEGJAVÍTVA.** A Today hub CTA-ja `recommendedMissionId == null ? practiceHub :
curriculumLadder`, és a `CurriculumTodayPlanRepository` friss telepítésen **is** ad ajánlott
fokot (a shipped course első rungja) — tehát a CTA a **ladderre** megy. A walkthrough
`PracticeAreaHubScreen`-t várt. **A teszt volt elavult, nem a termék**, ezért nem az assertion
lett visszahajlítva: a 3. megálló most a ladder (saját lokalizált címével), a 3b a practice hub
a fájl saját `session.router.go` idiómájával — a Setup/Session/Eredmény lánc és az A2/A3 fedés
változatlan. A `walked` halmaz és a záró elvárás frissült.

> **Feljegyzett hiány, NEM javítva:** a `today_hub_test.dart` csak azt ellenőrzi, hogy a CTA
> **létezik**, soha hogy **hová megy** — ezért tudott csendben elcsúszni. Egységszintű őr a
> `hub_navigation_test.dart`-ba illene (ott van a valódi router), de Today-plan
> provider-override-okat kíván. A kontraktust most az e2e pineli.

**2 — `placeholder_wiring_test.dart`, A4 partíció.** **10 újonnan elérhető képernyő** sem a
bejárásban, sem a dokumentált kizárás-táblában nincs: 9 community (`bookmarks`,
`clubs/club_list`, `comments`, `community_gate`, `community_notifications`, `followers`,
`following_feed`, `leaderboard`, `safety_relationships`) + `curriculum/rhythm_practice`. A
teszt **indokot ÉS megnevezett követő kört** kíván mindegyikre. **Ez emberi döntés** — tíz
kizárási indokot és egy kör-számot kitalálni pont az a placeholder-próza, amit ez az őr
megakadályozni hivatott. Kérdezd meg a usert: melyik képernyő kap bejárás-fedést, melyik
halasztott, és melyik körre.

**3 — `architecture_dependency_test.dart`.** Az `app_router.dart` **11** közvetlen importot
tesz a `features/community/**` belsőségeibe, és az E09-R05 community-specifikus szabály ezt
tiltja. Mérve: a router **minden** feature belsőségeit így importálja (song_trainer 7,
audio_analysis 7, ai_tutor 5, practice 4, library_v2 3…), tehát a generikus szabály alól a
router ki van véve — a community-specifikus alól nem. A `lib/features/community/public.dart`
létezik (22 export). Két járható út, és **dönteni kell**: (a) a 11 importot a barrelen át
vezetni (a hiányzó exportokat felvenni), vagy (b) a routert a community-szabály alól is
kivenni, ahogy a generikus teszi. Az (a) tartja a szabály szándékát.

**4 — `e13_r17_screens_golden_test.dart`.** Valódi pixel-diff: `practice area hub — compact`
**12,71%, 47915 px**, plus `profile hub` és `today hub` (compact és `_scale2` is). Mérve, hogy
**szándékos** változásokról van szó: a `profile_hub_screen.dart` **12** community-hivatkozást
tartalmaz (a `4cbd09fa` után), a Today hub pedig a daily loop miatt más. Felvevő:
`tools/golden-x86.sh record` (ADR 0426 — a goldenek x86-on rögzítettek, a CI `ubuntu-latest`
szintén x86_64). **Felvétel ELŐTT nézd meg a diffet** (`test/ui/goldens/failures`): a golden
vak újrafelvétele ugyanaz a hiba, mint egy assertiont a viselkedéshez hajlítani.

**5 — `e15_r13_full_variant_matrix_test.dart`, A1 completeness.** Ugyanaz a 10 képernyő, mint
a (2)-ben: vagy bekerülnek a mátrixba (pumpálva), vagy a kizárás-listába indokkal.

**Sorrend javaslat:** (3) → (5) → (2) → (4). A (3) önálló és mechanikus; a (5)/(2) ugyanazt a
10-es döntést kívánja, tehát egyszerre; a (4) legyen utolsó, mert a goldeneket a UI végleges
állapotán kell rögzíteni.

**Amikor mind zöld:** a user indítsa (vagy engedélyezze neked) a dispatch-et:
`gh workflow run build-apk.yml --ref claude/e18-r06-verify-followup`. ADR 0086 §2: a branch
legyen naprakész az `origin/main`-nel (most **0 commit** lemaradás). Az artefaktum a run
oldalán, `strumsight-<verzió>-<build>-<sha>-development.apk`. Release mód, **debug
aláírással** — a telefonon engedélyezni kell az ismeretlen forrást.

## 6. A KÖVETKEZŐ KÖR — pontosan specifikálva

**Cél:** a szállított **artefaktum** GuitarSet-száma a **RECEPT** tulajdonsága, vagy egy
szerencsés futás?

**Miért ez a kérdés.** Az ADR 0573 D6 megállapította: a szállított asset és egy mindkét
korpuszon tanító jelölt között **nincs dönthető sejt** (minden Klangio-sejt a szállítottnak
kedvez, minden GuitarSet-sejt a jelöltnek). Van azonban egy kivétel: ha a jelölt **CSAK
Klangión** tanul, akkor az **egész GuitarSet harmadik korpusz mindkettőnek**. Ezt a módot már
megírtam és assertekkel védtem: `--data=allklangio`. Ott minden kar mind a **három** Klangio
gitároson tanul, ugyanannyi adaton és ugyanolyan fajta splittel, mint a szállított asset —
tehát az ADR 0573 D4 kimondott konfoundja (a játékos-diverzitás harmadának elvétele)
**megszűnik**.

**Parancs (három seed, egy kar):**

```bash
cd /c/src/ss-e18/ml
for s in 42 1 2; do
  GUITARSET_DIR=/c/Users/kcsab/Downloads/recipewis TF_CPP_MIN_LOG_LEVEL=2 \
    /c/Users/kcsab/.venv/Scripts/python experiment_recipe_ladder.py \
      --data=allklangio --seed=$s --arms=R0
done
```

Kimenet: `ml/recipe_ladder_allklangio_seed{42,1,2}.json`. A JSON **merge-öl**, nem klobberol.
Karonként ~17 perc, összesen ~50 perc. Futtasd háttérben.

**A mérce, MÁR MEGMÉRVE** (ugyanez a mód, `--arms=` üresen, csak a szállított asset):

```
  szállított asset, GuitarSet@70 (mind a 3056 pengetés, sosem látta)
    saját class-blind kapuján (0,4388)   0,2812
    a produkciós kapun (0,85)           0,2997
```

**Elfogadási kritérium / hogyan olvasd:**

- Ha a matched-data **R0** GuitarSet@70 átlaga ~0,28–0,30 **és mind a három seed ugyanott
  van** → a szállított asset out-of-corpus generalizációja a **RECEPT** tulajdonsága,
  reprodukálható, és az ADR 0573 D4 konfoundja ezzel kvantifikálva van.
- Ha lényegesen **alacsonyabb** (pl. ~0,15) → a szállított **artefaktum** egy szerencsés
  futás, amit nem tudunk újraelőállítani. Ez **fontosabb lelet**, és a szállítási döntést
  érinti: nem lehet „a receptet javítjuk" alapon érvelni egy olyan alapvonal ellen, ami maga
  sem reprodukálható.
- **Mindkét kimenet publikálható eredmény.** Ne hajszold a „jó" irányt.
- Az [[L691]] szabálya szerint: ha a három seed szórása összemérhető a szállítotthoz mért
  különbséggel, az eredmény **„nem megállapított"**.

**Amit a körnek NEM szabad:** assetet cserélni, `settledTier`-t felkapcsolni, a
`noStrumThreshold`-ot mozgatni, harmadik-fél audiót commitolni, vagy a `tools/`+`.github/`
mércéhez nyúlni.

**A kör zárása:** ADR a `docs/adr/0581-…md` névvel, RAG-szakasz a
`docs/rag/chunks/018-strum-ml-pipeline.md` végére, `HANDOFF.md` kör-blokk a meglévők
mintájára, gate zöld, tételes staging, Conventional Commit.

## 7. Ha a fenti kör nem megy

Sorrendben a következő tételek, mindegyik önállóan zárható:

1. **A `pool_tier` kapu bekötése** — az `ml/train_live_3c_settled.py` már **rögzíti** a
   tierenkénti `class_blind` kapukat (ADR 0575 D7), de a szállított választás nem változott.
   A headroom ≤0,03, tehát **helyességi** javítás, nem kar.
2. **Az utolsó-ütés él-eset** (ADR 0570 D4): a kísérlet lezárását az utolsó onset + 238 ms-ig
   ki kell várni, különben az az ütés bizonyíték nélkül marad.
3. **A §9 hiányzó lábai** a „letisztult irány minden ütésre" útra: **fixtúra + property**. A
   valódi-audió láb megvan (ADR 0579), a paritás megvan
   (`crnn_live_3c_settled_parity_test.dart`).

## 8. Másolható első prompt

```text
A wolfcasaba/strumsight repositoryban dolgozol, a C:\src\ss-e18 worktree-ben
(ASCII útvonal KÖTELEZŐ: a valódi út `gitár`-t tartalmaz, attól a flutter analyze
255-tel kilép). Branch: claude/e18-r06-verify-followup.

Olvasd el ebben a sorrendben:
1. MINIMAX_START_HERE.md  (ez a fájl — a §3 korlátok és a §4 mérési fegyelem KÖTELEZŐ)
2. AGENTS.md §9, §12, §13, §15
3. HANDOFF.md utolsó 200 sora
4. docs/rag/chunks/018-strum-ml-pipeline.md utolsó 400 sora
5. docs/LESSONS.md L681–L691
6. docs/adr/0578 és docs/adr/0580

Hajtsd végre kizárólag a MINIMAX_START_HERE.md §6 körét:
a matched-data létra R0 karja három seeden (--data=allklangio), és a válasz arra,
hogy a szállított asset GuitarSet-száma (0,2997 a produkciós kapun) a RECEPT
tulajdonsága vagy egy szerencsés futás.

Kötelező:
- mind a három seed (42, 1, 2); előjel-egyezés nélkül az eredmény "nem megállapított" (L691);
- semmit ne kapcsolj fel, assetet ne cserélj, kaput ne mozgass;
- harmadik-fél audiót ne commitolj (git ls-files | grep -c '\.wav$' → 0);
- a gate-et külön, csővezeték nélkül futtasd:
  FLUTTER_BIN=/c/src/flutter/bin/flutter DART_BIN=/c/src/flutter/bin/dart \
    bash tools/round-gate.sh <teszt-útvonalak>
- tételes staging, `git add .` tilos.

Zárásként: ADR (docs/adr/0581-…md), RAG-szakasz, HANDOFF kör-blokk, és tényszerű
jelentés — módosított fájlok, mért számok provenance-szal, futtatott parancsok
TÉNYLEGES kimenettel, és ami NEM lett megmérve.
```
