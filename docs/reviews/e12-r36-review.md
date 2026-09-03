# E12-R36 — Review (Claude, orchestrátor/reviewer)

- **Kör:** `E12-R36` — Program completion report és következő roadmap (Chapter 12 ZÁRÓ kör)
- **Brief:** `docs/rounds/e12-r36-program-completion-and-next-roadmap.md` (a §0.0.A pre-flight revízióval)
- **Branch:** `sonnet-impl/e12-r36-program-completion-and-next-roadmap`
- **Reviewelt commit:** `ed50587c` (implementer: Claude Sonnet 5, `sonnet-impl`)
- **Review dátuma:** 2026-09-03
- **Mód:** read-only, izolált klón (`/tmp/review-e12-r36`), saját gate-futtatás + eldobható próbatesztek

## VERDIKT: CHANGES REQUESTED — 1 MAJOR

---

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `head=ed50587c`, `dirty_files=1`
(a jelzésfájl maga; a munkafa a jelzés után `git status --short` → ÜRES).

A jelzésfájlból **hiányzott a `scope_audit=` kulcs**, ezért az audit nem
számít bizonyítéknak (prompt §1.1 táblázata: `skipped` → kézzel futtatandó).
Kézzel lefuttatva:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r36 \
    --brief docs/rounds/e12-r36-program-completion-and-next-roadmap.md \
    --base 9da6d2f307a2
Legacy scope audit OK (9da6d2f307a2..ed50587cc4a3, 6 changed path(s), 0 generated/ignored)
```

A hat érintett útvonal mind a brief §4 engedélyezett listáján van; tilos zónát
(`lib/`, `backend/`, `tool/`, fejezet-fájlok, `pipeline-queue.tsv`, `docs/adr/`)
a diff **nem** érint. A `docs/sdd/00-index.md` változása a §0.0.A P7 határain
belül marad: kizárólag a `Státusz` és az `Implementation progress` cellák
szövege módosult a Chapter 5–14 sorokban — a „Fejlesztési körök" számcellák,
a fájl-linkek és a zárójelentés-linkek érintetlenek (`git diff` ellenőrizve).

A §10 handoff állításai ellenőrizve: a gate-kimenet alakja, a kézi
valódi-sértés próba leírt bukó cellája és a `_extractLabelValue` Unicode-hibája
mind konzisztens a saját mérésemmel — nincs alá nem támasztott állítás.

## 2. Gate-újrafuttatás (saját kézzel, izolált klónban)

```
$ git clone --branch sonnet-impl/e12-r36-… /home/ubuntu/ss-sonnet-impl-e12-r36 /tmp/review-e12-r36
$ bash tools/prepare-flutter-generated.sh      # PREP_EXIT=0
$ tools/round-gate.sh test/tooling/program_completion_test.dart test/tooling/sdd_index_guard_test.dart
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/program_completion_test.dart             zöld   (20 cella)
    test test/tooling/sdd_index_guard_test.dart                zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.   GATE_EXIT=0
```

A gate zöldje **reprodukálva** — de a zöld gate nem bizonyíték, ezért a §4
próbatesztek.

## 3. Acceptance criteria tételesen

| # | Kritérium | Bizonyíték | Ítélet |
|---|---|---|---|
| A1 | A matrix minden fejezet-státusza egyezik a queue MÉRT állapotával | `A1 — every matrix row matches the measured queue counts` zöld; RED-cella szintetikus queue-val piros | ✅ a JELEN LÉVŐ sorokra — ⚠ lásd MAJOR-1 (hiányzó sor) |
| A2 | Nyitott (`hold`/`prepared`/`pending`) sávot a riport NEM jelöl késznek | `A2` zöld; RED-cella (`hold`-on álló E10 „lezárva, minden kör kész") piros | ✅ a JELEN LÉVŐ sorokra — ⚠ MAJOR-1 |
| A3 | Minden hivatkozott dokumentum létezik | `A3` zöld, 14 bizonyíték-útvonal mérve, mind létezik; RED-cella nem létező fájlra piros | ✅ (MINOR-1 megjegyzéssel) |
| A4 | A roadmap minden tétele mérhető outcome-ot nevez meg | `A4` zöld 7 tételre; két RED-cella (hiányzó `**Mérőszám:**`; csak kör-azonosítókból álló Outcome) piros | ✅ |
| A5 | Az emberi kapuk explicit jelöléssel szerepelnek | `A5` zöld 8 kapura (E12-R27…R33 + valós gitáros APK-teszt), mind `NYITOTT`; RED-cella `KÉSZ` állapotra piros | ✅ a JELEN LÉVŐ sorokra — ⚠ MAJOR-1 |
| A6 | A `00-index.md` a Kör 2 ellenőrzőjével valid | `sdd_index_guard_test.dart` zöld a gate [4] lépésében | ✅ |

A §6.1 mérce-mátrix négy sora közül mind a négy hibás implementációt tényleg
pirosra váltja egy cella (ellenőrizve a RED-cellák és a „(a)"/„(b)"
valódi-sértés cellák kimenetén).

## 4. Próbatesztek (eldobható, `/tmp/review-e12-r36/test/tooling/zz_review_probe_test.dart`, merge előtt törölve)

A próba azt kérdezte, amit a §6.1 mátrix NEM sorol fel: mi történik, ha a
riport nem **hamisan állít**, hanem **hallgat** — egy sort egyszerűen kihagy.

```
PROBE1 (a teljes E15 sáv sora törölve)   rows=16  A1_issues=[]  A2_issues=[]
PROBE2 (a teljes E10 sáv sora törölve)   rows=16  A1_issues=[]  A2_issues=[]
PROBE3 (egy emberi-kapu sor törölve)              A5_issues=[]
PROBE4 (bizonyíték-bullet felismerés)    evidence_paths=14 (a §7 lista pontosan)
All tests passed!   ← azaz MIND A HÁROM ELHALLGATÁS ZÖLD MARAD
```

## 5. Leletek

### MAJOR-1 — Az őr a hamis ÁLLÍTÁST méri, az ELHALLGATÁST nem: egy kihagyott nyitott sáv (vagy emberi kapu) minden cellán zöld marad

**Hol:** `test/tooling/program_completion_test.dart:125` (`compareMatrixToQueue`),
`:165` (`findOpenLaneMarkedClosed`), `:212` (`findHumanGatesMarkedDone`) — mindhárom
függvény **kizárólag a riportban JELEN LÉVŐ sorokon** iterál, és soha nem
kérdezi meg, hogy a queue-ban mért összes előtag (illetve a hét
`E12-R27`…`E12-R33` kapu + a valós gitáros APK-teszt) kapott-e egyáltalán sort.

**Bizonyíték:** a §4 PROBE1–PROBE3. Az `E10` sáv (mind a 32 kör `hold`-on)
vagy az `E15` sáv (6 `pending`) sorának TÖRLÉSE után `A1_issues=[]` és
`A2_issues=[]`; egy emberi-kapu sor törlése után `A5_issues=[]`. A teljes
gate ilyenkor is zöld lenne.

**Miért MAJOR:** a brief §0.0.A P1 nem stílus-javaslatként, hanem kötelező
tartalmi előírásként mondja ki: *„A riportnak MINDHÁRMAT fel kell sorolnia
mért, nyitott sávként… A hallgatólagos kihagyásuk a matrixot hamis »a program
kész« állítássá tenné — ez pontosan a §9 első kockázata."* A §9 első kockázata
szó szerint a „kozmetikai zárójelentés". Ma ezt az előírást **csak a szöveg
védi, gépi mérce nem** — pontosan az a hibaosztály, amit a kör-brief
protokoll („minden szövegesen leírt tartalmi előíráshoz gépi mérce")
és az `L118`/`L577` lecke tilt. A MAI riport helyes; a **regresszió** ellen
nincs őr, és épp ez a fájl az, aminek ezt őriznie kellene.

**Javasolt irány (a scope-on BELÜL, `test/tooling/program_completion_test.dart`):**
két lefedettség-cella, tartalom-paraméteres tiszta függvényként, mindkettőhöz
RED-bizonyító cellával:
1. *lane-coverage*: a `parseQueueCounts(queueTsv).keys` minden előtagjának
   legyen sora a matrixban (a `—` előtagú Ch1-sor kivételével) — RED-cella:
   szintetikus queue egy olyan előtaggal, ami a szintetikus riportban nincs;
2. *human-gate-coverage*: a hét `E12-R27`…`E12-R33` kör-hivatkozás és a valós
   gitáros APK-teszt sora mind jelen van a §5 táblában — RED-cella: ugyanaz a
   tábla egy törölt sorral.

Kész patch-et szándékosan nem adok (review-protokoll).

### MINOR-1 — `parseEvidencePaths` doc-commentje többet állít, mint amit a függvény tesz

**Hol:** `test/tooling/program_completion_test.dart:189-194`. A doc-comment
szerint „Extracts every `- \`path\`` bullet **from a report's evidence-sources
section**", a `_evidenceBulletPattern` viszont `multiLine`-ként a **TELJES
dokumentumon** fut, szakasz-határ nélkül.

**Bizonyíték:** PROBE4 — ma 14 útvonalat ad vissza, ami történetesen pontosan a
§7 lista, mert a §2/§4/§6 bullet-jei nem backtick-kel kezdődnek. Ez **véletlen
egybeesés, nem invariáns**: bármely jövőbeli, backtick-kel kezdődő bullet
(bárhol a riportban) néma A3-követelménnyé válik.

**Miért MINOR:** a mai viselkedés helyes, a diffet nem hizlalja a javítás
(vagy a szakasz-határra szűkítés, vagy a doc-comment pontosítása arra, amit a
függvény tényleg tesz — a repó szabálya szerint doc-commentben csak bizonyított
állítás szerepelhet).

### NOTE-1 — Az A2 zárás-szótára két szóra korlátozódik

`findOpenLaneMarkedClosed` a `kész` / `lezárva` szavakat keresi (a `nyitva` /
`nyitott` kvalifikátor felmentésével). Egy nyitott sáv „befejezve", „100%" vagy
„done" szövegű Riport-státusszal ma átcsúszna. A jelen riport szóhasználata
konzisztens, ezért ez nem blokkol — de a szótár bővítése olcsó.

### NOTE-2 — A jelzésfájlból hiányzott a `scope_audit=` kulcs

A `sonnet-impl` (claude-harness, `tools/mm-round.sh`) jelzése nem tartalmazta a
kulcsot, noha a `ROUND_BRIEF` át lett adva. Az auditot kézzel futtattam (§1),
tehát a kör scope-ja **bizonyított** — de a burkoló-oldali hiány
infrastruktúra-lelet, nem ezé a köré (ADR 0112: az önjavító kör hatásköre).

## 6. Architektúra és termékhatárok

A diff kizárólag dokumentum + egy teszt-fájl; `lib/`, `backend/`, hálózat,
mikrofon, secret, plugin-határ **nem érintett** (AGENTS.md §5/§6 nem
alkalmazandó). Az architecture-gate zöld, 12 allowlisted deviation —
változatlan az `E12-R35` mért alapvonalhoz képest.

## 7. Merge-döntés

**MAJOR-1 nyitva → merge TILOS.** A javító kör a lánc normál útja: ugyanaz a
motor (`sonnet-impl`), a fenti leletlistával, ugyanazon a branchen. A javítás
után a gate-eket friss klónban újra futtatom, a leleteket tételesen lezárom, és
a CI-t az új HEAD-en újra dispatch-elem (a tesztfájl változik).
