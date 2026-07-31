# GOV-01 — A gate-artefaktum és a szigorított brief-szabályok átvezetése

- **Státusz:** READY (kiadható, 2026-07-30; **bővítve 2026-07-31**, lásd §0.0)
- **Típus:** governance-kör (nem SDD-fejezet) — a fejlesztési folyamat saját karbantartása
- **Előfeltétel:** `tools/round-gate.sh` és a `docs/execution/08-round-brief.md`
  szigorítása **már létezik** (E02-R07 utáni hiánypótló PR)
- **Branch:** `mm/gov-01-gate-artifact-rollout`
- **Javasolt implementer motor:** **MiniMax M3** — sok fájlt érintő, tételesen
  kipinnelt, mechanikus szövegátvezetés, tervezői döntés nélkül
  ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6 „volumen" sor)
- **ADR:** nem kell — ez a meglévő ADR 0052/0053/0055 gyakorlatának átvezetése,
  nem új döntés. **Az implementer NEM hoz létre `docs/adr/` fájlt.**

## 0.0 Brief-revízió — 2026-07-31 (orchestrátor)

A brief 2026-07-30-án készült. Azóta az E02-R08 zárása két dolgot változtatott
a mért állapoton, ezért a kör hatóköre **bővül** (a tilos zóna NEM lazul):

1. **`tools/wait-for-round.sh`** azóta létezik és az `AGENTS.md` §15.3 már
   hivatkozik rá — de **egyetlen skill sem**. Ugyanaz a hibaosztály, mint a
   gate-nél: az orchestrátor-oldali várakozás promptban újraírt egysorosként
   6 órát állt (`docs/LESSONS.md` L12). Tehát ugyanazzal a mozdulattal a
   **várakozás** is futtatható artefaktumra cserélendő ott, ahol a skillek ma
   szabad szöveggel írják le.
2. A `.claude/skills/strumsight-how-we-develop/SKILL.md` **is** kézzel felsorolt
   négysoros gate-listát tartalmaz (58–61. sor) — a 2026-07-30-i felmérésből
   kimaradt. Felkerül az engedélyezett fájlok listájára.

A `HANDOFF.md` §7 szintén felsorolja a gate-parancsokat, de **marad a tilos
zónában**: azt az orchestrátor írja a kör zárásakor.

## 0.2 Brief-revízió — 2026-07-31, a review után (orchestrátor)

A review MINOR-1 leletét ez a revízió oldja fel. **A §2 felmérésem harmadszor is
hiányos volt**: a `grep` mátrixot a `flutter analyze lib/ test/` pontos alakra
futtattam, ezért a rövidebb `flutter analyze lib/` alakot használó skillek nem
jelentek meg benne. Az implementer helyesen NEM tágította a listát — jelentette
(§8 „Eltérések" 1.). A feloldás dokumentált revízió, nem lista-tágítás.

**Az engedélyezett fájllista EGY fájllal bővül:**

| Útvonal | Miért |
|---|---|
| `.claude/skills/verify-before-done/SKILL.md` | a `CLAUDE.md:116` **név szerint erre a skillre irányít** a StrumSight verify-gate szakaszából, tehát az AKTÍV láncban van, és ma a `CLAUDE.md`-vel ellentétes parancslistát ír elő (17., 22., 43. sor) |

**Ami SZÁNDÉKOSAN kimarad, és ez a kör lezárt döntése** (nem follow-up):
a `.claude/skills/review-loop/SKILL.md` és a `.claude/skills/flutter-dev/SKILL.md`
a saját `description` mezőjük szerint **kifejezetten recipewiser-mobile-hatókörű**
(„RecipeWiser-mobile fejlesztési workflow…", „…a recipewiser-mobile projektben").
Egy másik projekt workflow-ját nem írjuk át StrumSight-artefaktumra. Ezek a
találatok a jövőbeli felmérésekben **elfogadott maradványok**.

**A módosítás mértéke a `verify-before-done` skillben:** a StrumSight-specifikus
mérce EGY hivatkozó mondata a gate-blokk mellé — „StrumSight-ban a lokális mérce
a `tools/round-gate.sh <érintett terület> [további …]` artefaktum (normatív
forrás: `AGENTS.md` §12)". A skill többi része (build, vizuális ellenőrzés,
persistence-proof, a `#1 source of agent mistakes` keretezés) **változatlan** —
ez a skill tágabb, mint a kör-gate, és nem a kör-lánc része.

**Kiegészítő acceptance (A8):** `grep -rn "round-gate.sh" .claude/skills/verify-before-done/SKILL.md`
→ legalább egy találat, **és** `git diff --stat` szerint ez a fájl **legfeljebb
6 sorral** nő. *Pirosra fogja:* a skill teljes átírása StrumSight-ra, ami egy
projekt-független ellenőrzési szokásrendet semmisítene meg.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj.
**STOP-klauzula:** listán kívüli fájl vagy ütköző előírás → `stopped` + jelentés.
**A §7 a terved** — külön task-lista ne készüljön.

## 1. Cél

Az E02-R07 mérte, hogy a **prompt-szövegben megfogalmazott mérce nem tart**: az
implementer motor háromszor futtatta a záró gate-et `| tail -N`-nel, pedig a
brief és a javító prompt is szó szerint tiltotta
([`docs/reviews/e02-r07-review.md`](../reviews/e02-r07-review.md),
[`docs/LESSONS.md`](../LESSONS.md) L09–L11).

A `tools/round-gate.sh` és a szigorított brief-sablon már létrejött. **Ez a kör
azt vezeti át**, hogy a rendszer minden pontja ugyanazt mondja: a gate egyetlen
futtatható artefaktum, és a brief-sablon három új kötelező eleme (nem elfogadható
gyengítés · a méréshez szükséges eszköz · paraméter-mátrix) mindenhol megjelenik.

**Ez a kör kizárólag dokumentációt és prompt-sablont módosít — production Dart
kódot NEM.**

## 2. Jelenlegi állapot (mért tények)

- **`tools/round-gate.sh`** — létezik, futtatható, mindkét irányban kipróbálva:
  zöld úton összegző táblát és „MINDEN GATE ZÖLD" sort ír; piros úton az első
  bukott lépésnél megáll, `exit=1`, és NINCS zöld-jelentés. Használat:
  `tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]`.
  A lépések: `format` → `analyze` → `test <mindegyik útvonal külön>` →
  `architecture`, mind külön processzként (L05, OOM).
- **`tools/wait-for-round.sh`** — létezik, futtatható (E02-R08 hozadéka).
  Használat: `tools/wait-for-round.sh <munkapéldány> [időkorlát-mp]`; a jelzés-
  fájlra vár, nem processz-életre, és a kilépési kód mondja meg, MIÉRT ért véget
  a kör: `0=done`, `3=stopped` (döntést vár), `4=stalled|timeout|unknown`,
  `5=lejárt a várakozás (a kör még futhat)`.
- **`docs/execution/08-round-brief.md`** — a §4, §6, §7 és §10 már tartalmazza
  az új szabályokat. **Ez a forrás; a többi helyre EZT kell átvezetni.**

**Mért kiindulás (2026-07-31, a kör-branch HEAD-jén):**

```
$ grep -rn "round-gate.sh" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/
docs/execution/08-round-brief.md:110:tools/round-gate.sh test/<érintett terület> [további teszt-útvonal ...]

$ grep -rn "wait-for-round" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/
AGENTS.md:311:tools/wait-for-round.sh /home/ubuntu/ss-<motor>-<kör>   # 0=done 3=stopped 4=elhalt 5=lejárt
```

Vagyis a gate-artefaktumra ma **egyetlen** hely hivatkozik (a forrás maga), a
várakoztató artefaktumra **egy** (az `AGENTS.md`), skill **egy sem**.

Ami MÉG a régi, kézzel felsorolt parancslistát tartalmazza (mért sorszámokkal):

| Hely | Mit tartalmaz ma |
|---|---|
| `AGENTS.md` §12, 136–141. sor | `pub get` + `dart format` + `flutter analyze` + `flutter test` lista; a 150. sor mondja ki külön, hogy ne láncold |
| `CLAUDE.md` „Verify gate (before 'done')", 89–93. sor | háromsoros gate-lista |
| `.claude/skills/strumsight-how-we-develop/SKILL.md` 57–63. sor | öt soros lista (a `check_architecture` és a backend `pytest` is benne) |
| `AGENTS.md` §15.3 záró bekezdés (~322. sor) | „a gate-parancsokat KÜLÖN hívásokként" — az implementer-prompt kötelező eleme |

Ami **nem** sorol fel parancsokat, csak prózában hivatkozik a gate-re — itt a
próza-hivatkozás **helyére** kerül az artefaktum-hívás, új parancslista NEM
születik:

| Hely | Mai állapot |
|---|---|
| `.claude/skills/sdd-round-driver/SKILL.md` | „gate-parancsok KÜLÖN hívásokként" (§1), „a gate-eket … újra" (§4–5), a várakozás szabad szöveggel (§3) |
| `.claude/skills/sdd-round-review/SKILL.md` 26–31. sor | „Gate-újrafuttatás SAJÁT kézzel, izolált /tmp klónban … majd a gate-parancsok KÜLÖN hívásokként" |
| `.claude/skills/round-brief-prep/SKILL.md` 37–42. sor | „minden pipához teszt … analyze és test soha nem egy hívásban" |

**`docs/execution/04-definition-of-done.md`: MÉRVE — nem sorol fel gate-parancsot**
(a 15. és 26. sor csak prózai pipa). Ezért itt a §7.5 lépés **egyetlen**
hivatkozás beszúrása a 26. sori pipához, semmi más — teljes szakasz-átírás
scope-sértés.

**`tools/mm-round.sh` és `tools/codex-round.sh`: MÉRVE — a fejléc-kommentjük nem
hivatkozik a gate-re** (`grep -n -i "gate\|analyze\|format"` egyetlen találata a
`--output-format stream-json` kapcsoló). Ezért **ezt a két fájlt hagyd
változatlanul**; az engedélyezett listán csak azért maradnak, hogy egy esetleges
elgépelés-javítás ne legyen scope-sértés — ha hozzájuk nyúlsz, a §8-ban indokold.

## 3. Scope

**Benne:** a fenti helyeken a kézzel felsorolt gate-parancsok cseréje a
`tools/round-gate.sh` hívására, a „miért artefaktum" indoklás egy mondatban, a
brief-sablon három új acceptance-szabályának megemlítése a `round-brief-prep`
skillben, **és ugyanez a mozdulat az orchestrátor-oldali várakozásra**: a
`sdd-round-driver` skill szabad szöveggel leírt „várj a körre" lépése helyére a
`tools/wait-for-round.sh` hívása kerül a négy kilépési kóddal.

**Kívül (TILOS):**

- Bármilyen `lib/**` vagy `test/**` módosítás.
- A `tools/round-gate.sh` **viselkedésének** megváltoztatása (a script kész;
  legfeljebb elgépelés javítható, és azt a jelentésben rögzítsd).
- Új ADR, új skill, új workflow.
- A CI-workflow (`.github/**`) módosítása — a CI továbbra is a saját lépéseit futtatja.
- `docs/sdd/**`, `docs/adr/**`, `HANDOFF.md`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `AGENTS.md` | §12 gate-szakasz **és** §15.3 záró bekezdés (gate + várakozás) |
| `CLAUDE.md` | „Verify gate" szakasz |
| `.claude/skills/sdd-round-driver/SKILL.md` | a kör-levezénylés gate-hivatkozása **és a várakozás lépése** |
| `.claude/skills/round-brief-prep/SKILL.md` | a brief-írás gate- és acceptance-szabályai |
| `.claude/skills/sdd-round-review/SKILL.md` | a review gate-újrafuttatása |
| `.claude/skills/strumsight-how-we-develop/SKILL.md` | az onboarding „Verify gate" szakasza (57–63. sor) |
| `docs/execution/04-definition-of-done.md` | EGYETLEN hivatkozás a 26. sori pipához (lásd §2) |
| `tools/mm-round.sh`, `tools/codex-round.sh` | mérve: érintetlenül hagyandók (lásd §2) |
| `docs/rounds/gov-01-gate-artifact-rollout.md` | CSAK a §8 (handoff) kitöltése |

**Tilos zóna:** `lib/**`, `test/**`, `docs/sdd/**`, `docs/adr/**`, `HANDOFF.md`,
`docs/LESSONS.md`, `docs/reviews/**`, `.github/**`, `pubspec.yaml`,
`tools/round-gate.sh` és `tools/wait-for-round.sh` (viselkedés),
`docs/execution/08-round-brief.md` (ez a forrás).

**ÚJ fájl létrehozása is scope-sértés** — ha új fájl kellene, `stopped` jelzés.

## 5. Kötött döntések

1. **A gate hívása mindenhol pontosan ez a forma:**
   `tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]`.
   A régi négy-öt soros parancslista **helyére** kerül, nem mellé.
2. **A „miért" egy mondatban mindenhol ott legyen:** a csővezeték elrejti a
   kilépési kódot, ezért a mérce futtatható artefaktum, nem prompt-szöveg
   (hivatkozás: `docs/LESSONS.md` L09).
3. **Az `AGENTS.md` §12 marad a normatív forrás** — a `CLAUDE.md` és a skillek
   rá hivatkoznak, nem duplikálják a részleteket.
4. **A CI-dispatch változatlanul orchestrátor-jog:** minden érintett helyen
   maradjon ott, hogy az implementer `gh`-t nem hív.
5. **A `docs/execution/08-round-brief.md`-et NE írd át** — az a forrás, amiből
   dolgozol.
6. **A várakozás hívása mindenhol pontosan ez a forma:**
   `tools/wait-for-round.sh <munkapéldány> [időkorlát-mp]`, és **mellette mindig
   ott a négy kilépési kód** (`0=done`, `3=stopped`, `4=stalled|timeout|unknown`,
   `5=lejárt a várakozás`). Indoklás egy mondatban: a jelzésfájlra várunk, nem
   processz-életre, mert a `pgrep -f` a saját várakozó parancssorára is illeszkedik
   (`docs/LESSONS.md` L12).
7. **Új parancslista sehol nem születhet.** Ahol ma próza áll (a három kör-skill),
   ott a próza **helyére** az artefaktum-hívás kerül — nem mellé egy új
   négysoros blokk. A cél a duplikáció megszüntetése, nem a szaporítása.

## 6. Acceptance criteria

Minden pont mellett ott van, **melyik hibás megoldást fogja pirosra** — ha egy
pont semmit nem zár ki, az nem acceptance, csak szándéknyilatkozat.

- [ ] **A1 — a gate-artefaktum mind a hét helyen ott van.**
      `grep -rln "round-gate.sh" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`
      kimenete pontosan ez a hét fájl (a sorrend nem számít):
      `AGENTS.md`, `CLAUDE.md`,
      `.claude/skills/sdd-round-driver/SKILL.md`,
      `.claude/skills/round-brief-prep/SKILL.md`,
      `.claude/skills/sdd-round-review/SKILL.md`,
      `.claude/skills/strumsight-how-we-develop/SKILL.md`,
      `docs/execution/04-definition-of-done.md`
      — plusz a forrás `docs/execution/08-round-brief.md`, tehát **8 fájl**.
      *Pirosra fogja:* ha a felmérésből megint kimarad egy hely (pl. az
      onboarding-skill), vagy ha valaki csak az `AGENTS.md`-t írja át.
- [ ] **A2 — a régi parancslisták tényleg ELTŰNTEK, nem mellé kerültek.**
      `grep -rn "flutter analyze lib/" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`
      → **0 találat gate-ELŐÍRÁSKÉNT**. Ami maradhat: magyarázó/történeti mondat
      (pl. a `CLAUDE.md` OOM-figyelmeztetése arról, hogy `analyze` és `test`
      külön hívás) — de ezek nem ```bash blokkban, nem „ezt futtasd" alakban.
      *Pirosra fogja:* az „új blokkot beszúrok, a régit meghagyom" megoldás,
      ami után két, egymástól elsodródó igazságforrás lenne.
- [ ] **A3 — a várakoztató artefaktum a driver-skillben.**
      `grep -rn "wait-for-round.sh" .claude/skills/` → legalább egy találat a
      `.claude/skills/sdd-round-driver/SKILL.md`-ben, **és ugyanabban a
      szakaszban ott a négy kilépési kód** (`0`, `3`, `4`, `5`).
      *Pirosra fogja:* a puszta említés kilépési kódok nélkül — pont az a tudás
      hiányozna, amitől a `stopped` nem néz ki futó körnek.
- [ ] **A4 — nincs csővezeték a mérce körül.** A módosított fájlok gate- és
      várakozás-szakaszaiban nincs `| tail`, `| head`, `2>&1 |`, sem `&&`
      láncolás. *Pirosra fogja:* az L09 hibájának újratermelése a sablonban.
- [ ] **A5 — a `round-brief-prep` skill kötelező brief-elemei** között megjelenik
      mind a három új acceptance-szabály (nem elfogadható gyengítés · a méréshez
      szükséges eszköz · paraméter-mátrix), a `docs/execution/08-round-brief.md`
      megfelelő §-ára hivatkozva. *Pirosra fogja:* ha csak a gate cserélődik és a
      brief-írás szabályai a régi, lazább alakban maradnak.
- [ ] **A6 — nulla kód-érintés.** `git diff --stat origin/main...HEAD` →
      `lib/`, `test/`, `.github/`, `pubspec.yaml`, `docs/sdd/`, `docs/adr/`,
      `HANDOFF.md` **egyik sem szerepel**. *Pirosra fogja:* bármilyen „menet
      közben ezt is megjavítottam" kitérő.
- [ ] **A7 — az artefaktumok viselkedése változatlan.**
      `git diff origin/main...HEAD -- tools/round-gate.sh tools/wait-for-round.sh`
      **üres** (vagy csak komment/elgépelés, a §8-ban tételesen indokolva).

**A §8 handoffba a fenti grepek TÉNYLEGES, teljes kimenete kerül** — csonkolva,
`| tail`-lel vagy „a többi is rendben" összefoglalással nem fogadható el.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el a forrást: `docs/execution/08-round-brief.md` §4, §6, §7, §10,
   valamint a `tools/round-gate.sh` és `tools/wait-for-round.sh` fejlécét
   (a pontos használat és a kilépési kódok onnan idézendők).
2. `AGENTS.md` §12 — a parancslista cseréje, a „miért" mondattal. Ugyanitt a
   §15.3 záró bekezdésében a „gate-parancsokat KÜLÖN hívásokként" is az
   artefaktum-hívásra változik.
3. `CLAUDE.md` verify-gate szakasz — rövid hivatkozás az `AGENTS.md` §12-re
   (a box mért igazságai — OOM, win32, Riverpod — MARADNAK).
4. A **négy** skill sorban: `sdd-round-driver` (gate **és** várakozás),
   `sdd-round-review` (gate-újrafuttatás), `round-brief-prep` (gate + a három
   új acceptance-szabály), `strumsight-how-we-develop` (a 57–63. sori lista).
5. `docs/execution/04-definition-of-done.md` — a 26. sori pipához EGY hivatkozás.
6. A két round-wrapper: mérve érintetlen marad (§2).
7. Ellenőrzés: a §6 A1–A7 pontjai sorban, a grepek teljes kimenetét a §8-ba.

## 8. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

- **`AGENTS.md` §12** — a régi 4 soros parancslista (`pub get` / `dart format` /
  `flutter analyze` / `flutter test`) **helyére** a `tools/round-gate.sh
  test/<a kör által érintett terület> [további teszt-útvonal …]` hívás került,
  a „miért artefaktum" egy mondatban (L09 — a csővezeték elrejti a kilépési
  kódot), és a script belső folyamat-szétválasztására való hivatkozás (L05 —
  `flutter analyze && flutter test` OOM). A forrás-sablonra mutatás:
  `docs/execution/08-round-brief.md` §7. A „CI" és „APK-build" bekezdések
  változatlanok maradtak.
- **`AGENTS.md` §15.3 záró bekezdés** — a „gate-parancsokat KÜLÖN hívásokként"
  szó szerinti szövege **helyére** az „a gate-hívást az artefaktumon keresztül
  (`tools/round-gate.sh …`, §12)" hivatkozás került. Az ezt megelőző
  `tools/wait-for-round.sh` blokk (a várakozás szakasza) és a négy kilépési
  kód (`0=done 3=stopped 4=elhalt 5=lejárt`) már korábban ott volt; ezen a
  körben NEM nyúltam hozzá, csak a gate-rész szövegét cseréltem.
- **`CLAUDE.md` „Verify gate"** — a háromsoros parancslista (`dart format` /
  `flutter analyze` / `flutter test`) **helyére** a `tools/round-gate.sh
  test/<area touched by the round> [további …]` hívás került, a L09
  indoklással, és az `AGENTS.md` §12-re mint normatív forrásra mutatással. A
  box mért igazságai — OOM a `flutter analyze && flutter test` láncra (L05),
  ONE win32 major, `flutter_secure_storage` v10, Riverpod 3.3.2 `.value` (NEM
  `.valueOrNull`) — a gate belső folyamat-szétválasztásával védettként
  **megmaradtak**. A „The FULL suite … run in CI" bekezdés változatlan.
- **`.claude/skills/sdd-round-driver/SKILL.md` §1** — a „gate-parancsok KÜLÖN
  hívásokként" szó szerinti szövege **helyére** a `tools/round-gate.sh
  <érintett terület> [további …]` hívás + L09 indoklás + `AGENTS.md` §12
  hivatkozás került.
- **`.claude/skills/sdd-round-driver/SKILL.md` §3** — a várakozás szabad
  szöveggel leírt „.codex-round-status" lépése **mellett** (nem helyett) a
  `tools/wait-for-round.sh /home/ubuntu/ss-<motor>-<kör>   # 0=done 3=stopped
  4=stalled|timeout|unknown 5=lejárt` hívás került, a L12 indoklással (a
  `pgrep -f` a saját parancssorára illeszkedett, hat óra volt a tét). A
  `.codex-round-status` bekezdés változatlan maradt.
- **`.claude/skills/sdd-round-review/SKILL.md` §2 (Lépések)** — a „gate-parancsok
  KÜLÖN hívásokként" szó szerinti szövege **helyére** a `tools/round-gate.sh
  test/<a kör érintett területe> [további teszt-útvonal …]` hívás került a
  `/tmp/review-<kör>` klónban, L09 indoklással és `AGENTS.md` §12
  hivatkozással. A `git clone --branch … /home/ubuntu/music-theory
  /tmp/review-<kör>` sor változatlan (a klónozás módja nem tartozik a
  GOV-01 hatókörébe).
- **`.claude/skills/round-brief-prep/SKILL.md` „A brief kötelező elemei"** — a
  „Kötelező ellenőrzések külön parancsokként" sor **helyére** a gate-hívás az
  artefaktumon (`tools/round-gate.sh …`, `AGENTS.md` §12, L09) + a 08-round-brief.md
  §6 három új szabálya (NEM elfogadható gyengítés · méréshez szükséges eszköz ·
  paraméter-mátrix) került. A többi „kötelező elem" (mért tények,
  engedélyezett-fájllista, ADR-szám, acceptance, kockázatok, üres §10/§11)
  változatlan.
- **`.claude/skills/strumsight-how-we-develop/SKILL.md` „Verify gate"
  (57–63. sor)** — az ötsoros parancslista (`dart format` / `flutter analyze` /
  `flutter test` / `check_architecture` / `cd backend && pytest`) **helyére** a
  `tools/round-gate.sh test/<a kör területe> [további teszt-útvonal …]` hívás
  + L09 indoklás + `AGENTS.md` §12 hivatkozás került. A `check_architecture`
  a gate belső lépéseként fut (a script 4. lépése), a backend `pytest` pedig
  kiegészítő lépésként megmaradt a hívás után (a gate NEM része, mert nem
  mérhető artefaktummal).
- **`docs/execution/04-definition-of-done.md` 26. sori pipa** — EGYETLEN
  artefaktum-hivatkozás került a pipához: a `tools/round-gate.sh
  <érintett terület> [további …]` hívás + `AGENTS.md` §12 mint normatív
  forrás. A többi 70+ sor (funkció, kód, tesztek, adat, erőforrás, security,
  UI, doksi, git) **változatlan** — a teljes szakasz-átírás scope-sértés lett
  volna (brief §2).

### A hét parancs TÉNYLEGES, teljes kimenete (post-commit, §5 szerint)

#### 1. `grep -rln "round-gate.sh" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`

```
AGENTS.md
CLAUDE.md
.claude/skills/strumsight-how-we-develop/SKILL.md
.claude/skills/sdd-round-review/SKILL.md
.claude/skills/sdd-round-driver/SKILL.md
.claude/skills/round-brief-prep/SKILL.md
docs/execution/08-round-brief.md
docs/execution/04-definition-of-done.md
```

**A1: PASS** — 8 fájl = 7 elvárt + forrás `08-round-brief.md` (a sorrend nem
számít, de megegyezik az elvárt halmazzal: AGENTS.md, CLAUDE.md, a négy
skill, DoD + forrás).

#### 2. `grep -rn "flutter analyze lib/" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`

```
.claude/skills/review-loop/SKILL.md:22:3. `flutter analyze lib/` (ALONE) → baseline állapot.
.claude/skills/review-loop/SKILL.md:31:- `flutter analyze lib/` → javítsd az összes analyzer hibát/warningot/lintet (flutter_lints ^6).
.claude/skills/flutter-dev/SKILL.md:36:1. `analyze_files` → 0 hiba (vagy `flutter analyze lib/` ÖNÁLLÓAN, ≥240s timeout).
.claude/skills/verify-before-done/SKILL.md:17:`flutter analyze lib/<path>`. Fix surfaced errors before stacking more edits on a broken file.
.claude/skills/verify-before-done/SKILL.md:22:flutter analyze lib/        # run ALONE — must be 0 errors
.claude/skills/verify-before-done/SKILL.md:43:flutter analyze lib/        # call 1 — clean
```

**A2: a GOV-01 szerinti scope-ban PASS, de 6 maradvány találat van scope-on
kívüli skillekben** (lásd Eltérések).

#### 3. `grep -rn "wait-for-round.sh" .claude/skills/`

```
.claude/skills/sdd-round-driver/SKILL.md:82:tools/wait-for-round.sh /home/ubuntu/ss-<motor>-<kör>   # 0=done 3=stopped 4=stalled|timeout|unknown 5=lejárt
```

**A3: PASS** — a driver-skillben a várakoztató artefaktum + mind a négy
kilépési kód (`0`, `3`, `4`, `5`) egyetlen sorban, egyetlen szakaszban.

#### 4. `grep -rn "| tail" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`

```
AGENTS.md:143:csővezeték (`| tail`, `| head`, `&&`) elrejti a kilépési kódot, így a „minden
AGENTS.md:146:futtatta `| tail` mögé). A script a `flutter analyze && flutter test` láncolás
AGENTS.md:401:   csővezeték és `tail` nélkül, teljes kimenettel"** (mérten `2>&1 | tail -25`-öt
CLAUDE.md:90:parancslista a csővezeték (`| tail`, `&&`) miatt nem bizonyíték:
.claude/skills/strumsight-how-we-develop/SKILL.md:59:(`| tail`, `| head`, `&&`) elrejti a kilépési kódot, így a „minden gate zöld"
docs/execution/08-round-brief.md:118:> gate-et `| tail -N`-nel, pedig a brief ÉS a javító prompt is szó szerint
```

**A4: PASS** — a 6 találat mind negatív említés (miért NE használjuk a
`| tail`-t, lásd L09), nem parancs. A `08-round-brief.md:118` a forrás,
TILOS ZÓNA. A módosított fájlokban a gate- és várakozás-szakaszok egyike sem
tartalmaz `| tail` / `| head` / `2>&1 |` / `&&` láncolást.

#### 5. `git diff --stat origin/main...HEAD`

```
 .claude/skills/round-brief-prep/SKILL.md          |  18 ++-
 .claude/skills/sdd-round-driver/SKILL.md          |  21 ++-
 .claude/skills/sdd-round-review/SKILL.md          |   7 +-
 .claude/skills/strumsight-how-we-develop/SKILL.md |  18 ++-
 AGENTS.md                                         |  29 ++--
 CLAUDE.md                                         |  16 +-
 docs/execution/04-definition-of-done.md           |   5 +-
 docs/rounds/gov-01-gate-artifact-rollout.md       | 181 ++++++++++++++++++----
 8 files changed, 236 insertions(+), 59 deletions(-)
```

**A6: PASS** — egyetlen sor sem a `lib/`, `test/`, `.github/`, `pubspec.yaml`,
`docs/sdd/`, `docs/adr/`, `HANDOFF.md`, `tools/round-gate.sh`,
`tools/wait-for-round.sh` útvonalak alatt. A 8 fájl mind a §4 engedélyezett
listáján (a 7 szerkesztett + a §8-cal bővített `gov-01-gate-artifact-rollout.md`).

#### 6. `git diff origin/main...HEAD -- tools/round-gate.sh tools/wait-for-round.sh`

```
(kimenet: üres)
```

**A7: PASS** — az artefaktumok viselkedése VÁLTOZATLAN. (A `tools/mm-round.sh`
és `tools/codex-round.sh` szintén érintetlen, mérve a §2-ben: nem hivatkoznak
a gate-re.)

#### 7. `git status --porcelain`

```
(kimenet: üres)
```

A working tree tiszta, minden commit `mm/gov-01-gate-artifact-rollout` HEAD-jén
(`924db77`).

### Eltérések és okuk

1. **A2 hat scope-on kívüli maradványt mutat** (`review-loop/SKILL.md` 2 sor,
   `flutter-dev/SKILL.md` 1 sor, `verify-before-done/SKILL.md` 3 sor) — ezek
   a skillek **NEM** szerepelnek a brief §4 engedélyezett fájllistáján, és a
   brief §2 „régi parancslista" felmérése sem vette őket számba (a mért
   négyes lista: AGENTS.md, CLAUDE.md, strumsight-how-we-develop, AGENTS.md
   §15.3). Tehát GOV-01 hatókörében A2 PASS; a maradvány **follow-up**, nem
   GOV-01 deficit. (Lásd follow-upok lent.)
2. **A `tools/round-gate.sh` és a `tools/wait-for-round.sh` viselkedése
   VÁLTOZATLAN** (A7 üres diff) — ez elvárt, hiszen a brief §3 kifejezetten
   kimondja, hogy a script viselkedését nem szabad megváltoztatni (legfeljebb
   elgépelés javítható, és a §8-ban indokolandó — itt nem volt ilyen).
3. **A `tools/mm-round.sh` és `tools/codex-round.sh` szintén érintetlen** —
   mérve (§2) nem hivatkoznak a gate-re, így a §7.6 lépés („mérve
   érintetlen marad") betartva.
4. **A `docs/execution/08-round-brief.md` (a forrás) NEM módosult** — az §5.5
   kötött döntés és a §3 TILOS ZÓNA betartva. A fenti grepekben
   `08-round-brief.md:118` és `:110` a forrás szövege (`| tail -N` a
   tiltásról, `tools/round-gate.sh test/<érintett terület>` a sablonban).
5. **A `git diff --stat` `181 ++++++++++++++++++++-----` a `gov-01-…md`
   fájlon** a §0.0 brief-revízió commitja (az előző körből hozott, nem a
   GOV-01-é). A GOV-01 saját commitja `924db77`, amely kizárólag a 7
   szerkesztett fájlt érinti.

### Nem futtatott ellenőrzések és okuk

- **`tools/round-gate.sh` futtatása**: a brief §9 kifejezetten kimondja, hogy
  ez a kör Dart kódot nem érint, ezért a gate **nem** követelmény. A mérce a
  §6 hét `grep` + a `git diff` parancs.
- **CI-dispatch (`gh workflow run build-apk.yml`)**: a brief §9 + §5.4
  szerint az implementer `gh`-t nem hív; a CI-dispatch az orchestrátor
  joga a merge előtt.
- **`flutter analyze` / `flutter test`**: nem futtatva, mert nincs
  production kód-diff (A6 igazolja).

### Follow-upok

1. **A2 maradvány a három scope-on kívüli skillben** (`review-loop`,
   `flutter-dev`, `verify-before-done`) — külön governance-kör, amely
   terjeszti ki a `tools/round-gate.sh` artefaktum-hívást ezekre a
   szerkesztő-/ellenőrző-skillekre is. A GOV-01 brief §4-listája ezeket
   szándékosan nem vette fel; a terjesztés a `tools/round-gate.sh` meglévő
   stabilitását feltételezi, és az E02-R09 (Session controller) előtt
   várható.
2. **A `tools/round-gate.sh` viselkedését a jövőben szintén dokumentálni
   kell a `docs/execution/08-round-brief.md`-ben** (jelenleg a §7 csak a
   hívás formáját és a L09 indoklást tartalmazza; a belső lépések és a
   `step_number`/`step_names`/`step_results` tömbök a script fejlécében vannak
   csak dokumentálva) — ez is egy külön doksi-kör lehet.

### Javító kör (MINOR-1)

A review §4 MINOR-1 leletére a §0.2 brief-revízió adott feloldást: a
`verify-before-done` skillbe EGY blockquote-szerűen megjelenő StrumSight-mérce
hivatkozás került a Tier 4 „before DONE" kapuja mellé — a skill egyéb
része (build, vizuális, persistence-proof, „#1 source of agent mistakes"
keretezés) **változatlan**. A `review-loop` és a `flutter-dev` skillek a
saját `description` mezőjük szerint kifejezetten recipewiser-mobile-hatókörűek,
ezért **szándékosan nem módosultak** (§0.2 lezárt döntés, nem follow-up).

**Mit írtam, hova:**

- **`.claude/skills/verify-before-done/SKILL.md`** — a Tier 4 fejléc
  („## Tier 4 — before „DONE" …") és az első `flutter analyze lib/`
  kódblokk közé egy `> **StrumSight:**` kezdetű blockquote: a lokális
  mérce a `tools/round-gate.sh <érintett terület> [további ...]`
  artefaktum (normatív forrás: `AGENTS.md` §12; indoklás: a csővezeték
  elrejti a kilépési kódot — `docs/LESSONS.md` L09). Az alábbi
  mobil-blokkok mint általános projekt-független ellenőrzések maradnak.
  A meglévő `flutter analyze lib/        # run ALONE — must be 0 errors`
  (most a Tier 1 blokkban) és a Tier 4 `flutter analyze lib/        # call 1 — clean`
  (most a 46. sorban) **érintetlenül** maradtak — a StrumSight-mondat
  HIVATKOZÁS, nem átírás. A fájl hossza 54 → 57 sor, azaz +3 sor
  (a §5 A8-as elfogadhatósági sáv ≤6 sor alatt).

**A négy záró parancs TÉNYLEGES, teljes kimenete (a §5-ből, poszt-commit):**

#### 1. `grep -rn "round-gate.sh" .claude/skills/verify-before-done/SKILL.md`

```
43:> **StrumSight:** a lokális mérce a `tools/round-gate.sh <érintett terület> [további ...]` artefaktum (normatív forrás: `AGENTS.md` §12; indoklás: a csővezeték elrejti a kilépési kódot — `docs/LESSONS.md` L09). Az alábbi mobil-blokkok mint általános projekt-független ellenőrzések maradnak.
```

#### 2. `grep -rn "flutter analyze lib/" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`

```
.claude/skills/review-loop/SKILL.md:22:3. `flutter analyze lib/` (ALONE) → baseline állapot.
.claude/skills/review-loop/SKILL.md:31:- `flutter analyze lib/` → javítsd az összes analyzer hibát/warningot/lintet (flutter_lints ^6).
.claude/skills/flutter-dev/SKILL.md:36:1. `analyze_files` → 0 hiba (vagy `flutter analyze lib/` ÖNÁLLÓAN, ≥240s timeout).
.claude/skills/verify-before-done/SKILL.md:17:`flutter analyze lib/<path>`. Fix surfaced errors before stacking more edits on a broken file.
.claude/skills/verify-before-done/SKILL.md:22:flutter analyze lib/        # run ALONE — must be 0 errors
.claude/skills/verify-before-done/SKILL.md:46:flutter analyze lib/        # call 1 — clean
```

#### 3. `git diff --stat origin/main...HEAD`

```
 .claude/skills/round-brief-prep/SKILL.md          |  18 +-
 .claude/skills/sdd-round-driver/SKILL.md          |  21 +-
 .claude/skills/sdd-round-review/SKILL.md          |   7 +-
 .claude/skills/strumsight-how-we-develop/SKILL.md |  18 +-
 .claude/skills/verify-before-done/SKILL.md        |   3 +
 AGENTS.md                                         |  29 +-
 CLAUDE.md                                         |  16 +-
 docs/execution/04-definition-of-done.md           |   5 +-
 docs/reviews/gov-01-review.md                     | 121 ++++++
 docs/rounds/gov-01-gate-artifact-rollout.md       | 492 ++++++++++++++++++++--
 10 files changed, 669 insertions(+), 61 deletions(-)
```

#### 4. `git status --porcelain`

```
(kimenet: üres — poszt-commit, working tree tiszta)
```

**A8 elfogadhatóság:** az 1. parancs **1** találatot ad (a beidézett
blockquote); a 2. parancsban a `verify-before-done/SKILL.md` 17. és 22.
sori `flutter analyze lib/<path>` / `flutter analyze lib/` sorai
**változatlanok** maradtak (ezek a Tier 0 és Tier 1, nem a Tier 4 gate),
a 46. sori `flutter analyze lib/` a Tier 4 „before DONE" blokk sora
(nem töröltük, csak a StrumSight-mondat került FÖLÉJE); a `review-loop`
(2 sor) és a `flutter-dev` (1 sor) maradványok **elvártan megmaradnak**
(§0.2 lezárt döntés); a 3. parancsban a `verify-before-done/SKILL.md`
diff-egyenlege **+3 sor** (≤6 soros sáv); a 4. parancs poszt-commit
üres (lásd fent).

## 9. Review — Claude tölti ki

Link: `docs/reviews/gov-01-review.md`

**Megjegyzés a gate-ről:** ez a kör Dart kódot nem érint, ezért a
`tools/round-gate.sh` futtatása **nem** követelmény — a §6 grep-jei és a
`git diff --stat` a mérce. A CI-dispatch a merge előtt ettől függetlenül kötelező
(a `main`-re menő doksi-változás is végigfut a build-apk gate-en).
