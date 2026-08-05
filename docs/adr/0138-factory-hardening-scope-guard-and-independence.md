# ADR 0138 — Factory hardening: legacy scope-audit, mérce-őr és reviewer-függetlenség

**Státusz:** elfogadva (GOV-03, 2026-08-05, user-döntés: „a javaslataid alapján
illeszd be a rendszerünkbe").

Épít az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu),
[ADR 0055](0055-agent-role-protocol.md) (szerep-protokoll, független reviewer),
[ADR 0069](0069-two-engine-implementer-pool.md) (két implementer motor),
[ADR 0087](0087-autonomous-round-pipeline.md) (autonóm kör-pipeline),
[ADR 0088](0088-minimax-first-development-router.md) (MiniMax-first router),
[ADR 0112](0112-self-healing-pipeline.md) (önjavító lánc, H-GATEGUARD) és
[ADR 0115](0115-orchestrator-engine-fallback.md) (Terra orchestrátor-fallback)
döntéseire.

## Kontextus

A user egy külső, SDD-vezérelt „Autonomous Flutter Factory" starter-tervcsomagot
adott át (`autonomous_flutter_factory_starter_v1`) azzal a kérdéssel, hiányzik-e
belőle valami a mi rendszerünkből. Az összevetés szerint a csomag kb. 80%-át már
megvalósítottuk, több ponton (mérce-artefaktum, önjavító kör, error-fingerprint,
`docs/LESSONS.md` L01–L115, randomizált property gate) előrébb is vagyunk.

Hét valódi hiány maradt. Ez az ADR abból ötöt zár le; kettő mérési előfeltétel
miatt follow-up (§7).

### A három MÉRT gyökérok

**1. A legacy implementer-út scope-védelem nélkül futott.**
Az `engine=auto` úton a router minden modell-diffet auditál
(`tools/ai_router/security.py::audit_scope`): protected path, allowed path,
symlink, mozdult HEAD. A `tools/codex-round.sh` és `tools/mm-round.sh` úton
viszont a scope-ot **kizárólag a prompt szövege és a későbbi emberi/Claude
review** védte. A prompt szövege nem kényszerítő erő — mérve: az M3 a promptban
kimondott tiltás ellenére commitolt (`d0546f0`, `ss-router-e03-r05-2`), amit
csak a router auditja fogott meg (`tools/ai_router/git-guard/git` fejléce).

Az élesség mértéke: **az Epic 4 mind a 24 köre `engine=codex|minimax`**, tehát a
teljes futó epic védelem nélkül írt — miközben **mind a 24 brief már tartalmaz
gépi `allowed_paths` blokkot**. A védelemhez szükséges adat megvolt; az
ellenőrzés hiányzott.

**2. A `H-GATEGUARD` csak prózában létezett.**
Az ADR 0112 kimondja, hogy az egyetlen emberi határ a MÉRCE gyengítése, de ezt
semmi nem kényszerítette ki írás közben: az őr utólagos, a merge-elt PR
diffjéből dolgozott. Egy session, amely a `tools/round-gate.sh`-t vagy a
`.github/workflows/`-t írja át, csak a javítás UTÁN akadt fenn.

**3. Kvótazárlat alatt a Terra a saját diffjét review-zta volna.**
Mérve 2026-08-05: az implementer (`codex exec`, `~/.codex`) és az orchestrátor-
fallback (`~/.codex-terra`) `model` mezője **azonos: `gpt-5.6-terra`**. Az
ADR 0115 szerint Claude-kvótazárlatkor a review a Terráé, miközben a queue
`engine=codex` sorai szintén Terrát indítanak implementerként. Ez az egyetlen
pont a láncban, ahol független bizonyíték nélkül születhetett volna merge —
és pontosan az, amit az ADR 0055 és a starter-csomag SDD §2.2 is explicit
nem-célként nevez meg („egyetlen agent saját munkájának kizárólagos
jóváhagyása").

## Döntés

### 1. A legacy út is gépi scope-auditot kap

`tools/ai_router/legacy_scope.py` + `tools/scope-audit.py` + a wrapperekbe
kötött `tools/round-scope-audit.sh`.

- Az **illesztési szemantika közös** a router útjával (`_matches`,
  `_is_generated_ignored`, symlink-ellenőrzés), hogy a „scope-on kívül"
  mindkét úton ugyanazt jelentse.
- Két **szándékos** eltérés:
  - a legacy protokoll KÖVETELI a commitot (AGENTS.md §15.2), ezért a mozdult
    HEAD itt nem sértés; az audit a teljes `base..munkafa` deltát nézi,
    commitoltat és nem commitoltat egyaránt;
  - a `base` a munkapéldány HEAD-je az **indítás pillanatában**, nem az
    `origin/main`. Az orchestrátor pre-flight commitja (kör-ADR + brief-revízió)
    jogosan nyúl az `allowed_paths`-on kívülre; az innen mért verdikt az
    IMPLEMENTER saját munkájára szól. Élesben igazolva: az E04-R10 leállított
    munkapéldánya a pre-flight commitról mérve tiszta (9 fájl), az `acc84d9`-ről
    mérve viszont helyesen jelzi a pre-flight `docs/adr/0137-*.md` fájlját.
- A verdikt a `.codex-round-status` jelzésfájlba kerül (`scope_audit=ok |
  VIOLATION | skipped | error`), **mielőtt** az orchestrátor bármit olvasna.
  Sértéskor a jelzés `status`-a `stopped`-ra vált, az implementer eredeti
  jelzése az `implementer_status=` kulcsban marad — ugyanaz az elv, mint az
  időtúllépésnél: a burkoló mért ténye erősebb, mint az implementer
  önbevallása.
- Az audit csak akkor fut, ha az orchestrátor átadja a `ROUND_BRIEF`
  környezeti változót. Enélkül `scope_audit=skipped` — **láthatóan, nem
  némán**; a `skipped` nem bizonyíték, és a `docs/execution/pipeline-orchestrator-prompt.md`
  kötelezővé teszi az átadást.

### 2. `PreToolUse` mérce-őr minden Claude-oldali sessionre

`.claude/hooks/protect_factory_files.py` + a repóba commitolt
`.claude/settings.json`.

Védett (a MÉRCE): `tools/round-gate.sh`, `tool/ci/**`, `.github/workflows/**`,
`.github/actions/**`, `tools/ai_router/**`, `tools/model-router.py`,
`tools/scope-audit.py`, `tools/round-scope-audit.sh`, `.ai/router.toml`,
`schemas/**`, `.claude/hooks/**`, `.claude/settings.json`. Külön kategória a
titok (`.env*`, `secrets/**`, `*.jks`, `*.p12`, `*.keystore`) — arra az emberi
engedély sem érvényes.

**Szándékosan NEM védett**, mert a csővezeték maga írja őket:
`docs/execution/pipeline-queue.tsv`, `.pipeline/**`, `HANDOFF.md`, az RTM és a
kör-briefek. Ha ezeket zárnánk, a saját láncunk állna meg — ezt teszt rögzíti.

Az őr `Edit`/`Write`/`NotebookEdit` hívásokra pontos, `Bash`-re best-effort
(mutáló művelet + védett útvonal együtt). A hiteles, auditált visszaesési réteg
a scope-audit; ez védelmi mélység, nem helyettesítés. Fail-closed: olvashatatlan
payload vagy váratlan hiba is blokkol.

Emberi engedély: `STRUMSIGHT_GATE_EDIT_OK=1`, amit az őr a stderr-be is kiír,
hogy az escape a transcriptben LÁTSZÓDJON, ne némán történjen.

> **Mért korlát (2026-08-05, ebben a körben):** az env-alapú escape interaktív
> sessionben nem állítható be futás közben. Az őr ezért a gyakorlatban a
> saját szerzőjét is megállította. A `.claude/gate-edit-authorized` marker-fájl
> alapú escape a §7 follow-upja.

### 3. Reviewer-függetlenség kvótazárlat alatt

`resolve_independent_engine()` a `tools/round-pipeline.sh`-ban, kívülről
lekérdezhető teszthorgon (`--independent-engine <motor>`).

| Queue-motor | Claude elérhető | Claude zárlat alatt |
|---|---|---|
| `codex` | `codex` | **`minimax`** (a reviewer Terra, az implementer nem lehet szintén Terra) |
| `minimax` | `minimax` | `minimax` (már független) |
| `auto` | `auto` | `auto` (a router saját szerződése, l. §7) |
| `codex`, de nincs MiniMax kulcs | — | **`H-INDEP` halt** |

A feloldás **nem** halt, hanem motorváltás: az ADR 0115 célja az volt, hogy a
lánc ne szakadjon meg. Halt csak akkor, ha nincs másik motor — mert a
self-reviewed merge rosszabb, mint az állás.

### 4. `H-INDEP` és `H-GATEGUARD` nem önjavítható

Az `attempt_selfheal()` explicit listával utasítja el őket. Indok: az önjavító
session kvótazárlat alatt maga is Terra, tehát a H-INDEP-et **körben** oldaná
fel — épp az a baj, hogy a Terra vizsgálná a saját munkáját. A H-GATEGUARD-nál
ez az ADR 0112 eddig is kimondott, de kódban nem kényszerített szabálya.

### 5. Külön security-review szerep

`.claude/agents/security-reviewer.md`. Kötelező minden olyan kör review-jában,
ahol a brief `risk = "high"`, vagy a diff a `.ai/router.toml`
`high_risk_path_fragments` mintáira illeszkedik. READ-ONLY, kimenete
`docs/reviews/eXX-rYY-security.md`; a **CRITICAL** és **BLOCKER** lelet merge-et
tilt. Külön kitérője a prompt injection felület (ADR 0131–0136): külső tartalom
(importált dal, tudásbázis-chunk, provider-válasz) adat, nem utasítás.

## Következmények

**Nyereség**

- Az Epic 4 hátralévő 15 köre gépi scope-bizonyítékkal fut, nem prompt-ígérettel.
- A mérce gyengítése írás közben blokkolódik, nem utólag derül ki.
- A lánc nem tud self-reviewed diffet merge-elni.
- A biztonsági szempont önálló, blokkoló review-vá vált az AI-tutor epicre.

**Ár**

- Minden legacy körindításnak át kell adnia a `ROUND_BRIEF`-et; ha elmarad, a
  `scope_audit=skipped` jelzi, de nem állítja meg a kört (a `skipped` nem
  bizonyíték — a merge-döntés az orchestrátoré).
- A mérce-őr minden Claude-sessionre hat, beleértve a governance-munkát is;
  az emberi escape kényelmetlensége szándékos.
- A `codex`→`minimax` váltás kvótazárlat alatt más implementer-karakterisztikát
  hoz (az M3 mért gyengéi: `docs/LESSONS.md`), cserébe visszaadja a független
  reviewert.

## Ismert, NEM lezárt maradék (§7 follow-up)

Ezek mérési előfeltétel vagy külön kör hiányában maradtak nyitva; egyik sem
javítható őszintén „menet közben":

1. **`auto` + Terra-eszkaláció**: ha kvótazárlat alatt a router Terrára
   eszkalál, a reviewer is Terra. A pontos feloldáshoz a review-nak tudnia
   kell, MELYIK modell írta a diffet (`router-result.json`) — külön kör.
2. **Coverage-küszöb**: ma `flutter test --coverage` fut és az lcov feltöltődik,
   de nincs minimum. Küszöböt mért baseline nélkül felvenni önkényes lenne.
3. **Titok-scan és l10n-paritás kapu**: megírva, de a mérce-őr miatt emberi
   engedéllyel kell beilleszteni (`tool/ci/**` védett).
4. **Gépi acceptance-bizonyíték** (`schemas/agent-result.schema.json`):
   protokollváltás, minden brief és prompt érintett — külön kör.
5. **Accessibility és dependency/licenc audit kapu**: nincs megírva.

## Alternatívák, amiket elvetettünk

- **Az összes Epic 4 sort `auto`-ra állítani.** Egy sorral megoldotta volna a
  scope-védelmet, de átírta volna a futó epic motorválasztását és a router
  kvótakeretét — nagyobb viselkedésváltozás, mint a hiány, amit javít.
- **Scope-sértésre azonnali HALT.** A `stopped` jelzés ugyanide vezet, de
  meghagyja az orchestrátornak a dokumentált utat (listán kívüli fájlok
  visszaállítása), és nem kerüli meg az ADR 0087 halt-szerződését.
- **A `git-guard` shim ráhúzása a legacy útra.** Ott a commit KÖTELEZŐ
  (§15.2), tehát a shim a protokollt törte volna el.
