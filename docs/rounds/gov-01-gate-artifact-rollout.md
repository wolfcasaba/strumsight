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

*(Fájlonkénti összefoglaló · a futtatott `grep`-ek TÉNYLEGES kimenete ·
eltérések és okuk · nem futtatott ellenőrzések és okuk · follow-upok.)*

## 9. Review — Claude tölti ki

Link: `docs/reviews/gov-01-review.md`

**Megjegyzés a gate-ről:** ez a kör Dart kódot nem érint, ezért a
`tools/round-gate.sh` futtatása **nem** követelmény — a §6 grep-jei és a
`git diff --stat` a mérce. A CI-dispatch a merge előtt ettől függetlenül kötelező
(a `main`-re menő doksi-változás is végigfut a build-apk gate-en).
