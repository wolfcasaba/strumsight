# ADR 0309 — Implementer-oldali gépi őrök (hook-réteg) a claude-harness körökhöz

**Státusz:** elfogadva (2026-08-18, user-kérés: „minimax implementerre lenne még
hasznos beállítás hogy ne hibázzon használjon ügynököket és jól dolgozzon").

Kiegészíti az [ADR 0138](0138-scope-audit-and-independent-review.md) scope-auditját,
az [ADR 0173](0173-qwen-implementer-hardening.md) implementer-preambulumát és az
[ADR 0112](0112-self-healing-pipeline.md) `H-GATEGUARD` határát. Egyiket sem
írja felül: a mérce, a review és a merge-kapu változatlan.

## 1. Kontextus — a szöveges tiltás mérve nem tartott

A claude-harness implementerek (MiniMax M3, `sonnet-impl`) mért hibái közül
három olyan van, amit a brief ÉS a preambulum is szó szerint tiltott, és mégis
megtörtént:

| Hibaosztály | Mérés | Ára |
|---|---|---|
| listán kívüli fájl létrehozása | két külön kör (fixture-, illetve ütemező-kör), `docs/LESSONS.md` | javító kör mindkétszer |
| a gate `\| tail` mögé rejtése | E02-R07: **háromszor**, a javító prompt tiltása ellenére | a „minden zöld" bizonyíthatatlan |
| lezáró jelzés nélküli kilépés (`H-NOSIGNAL`) | 18 önjavító kör; a lánc két valaha mért self-heal-kimerülése MINDKETTŐ ez | egyikük **42 órás** állás |

A repó erre a mintára már ismer választ: a MÉRCE védelme 2026-08-05 óta nem
próza, hanem hook (`.claude/hooks/protect_factory_files.py`). Ez az ADR ugyanezt
a mintát terjeszti ki a **kör-szerződésre** (az `allowed_paths` listára, a
tiltott parancsalakokra és a lezáró jelzésre).

Külső megerősítés: a mezőny szerint az ügynök-megbízhatóság kulcsa nem a jobb
prompt, hanem a **verifikáció és a determinisztikus korlát** — a friss
kontextusú, független ellenőrző kevésbé elfogult, mint a saját munkáját néző
modell ([Anthropic: Claude Code best practices](https://www.anthropic.com/engineering/claude-code-best-practices)),
az elakadt/hurokba került ügynököt pedig külső őr fogja meg, nem önbevallás
([AgentCenter, 2026](https://www.agentcenter.cloud/blogs/how-to-detect-agent-stuck-or-looping)).

## 2. Döntés

### §1 A hook implementer-hatókörű, és NEM a `.claude/**` zónában él

* A szkript: `tools/hooks/implementer_guard.py`.
* A regisztráció: `tools/implementer-settings.json`, amit a `tools/mm-round.sh`
  a `--settings` kapcsolóval **csak az implementer-sessionre** tölt be.
* A kapcsoló: a burkoló `STRUMSIGHT_ROUND_BRIEF` (és `STRUMSIGHT_ROUND_ID`)
  változót exportál; enélkül a hook teljes no-op.

Miért nem a `.claude/settings.json`-ba került: az a fájl a `H-GATEGUARD` védett
zónája (a mércét nem javíthatja az, akit mér), és a projekt-szintű hook minden
sessionre hatna — az orchesztrátoréra és az emberi munkára is. Így a kör-őr
pontosan ott él, ahol a kör-szerződés érvényes, és sehol máshol.

### §2 Scope-őr — fail-closed

`PreToolUse` (`Edit`/`Write`/`MultiEdit`/`NotebookEdit`): a cél útvonalnak a
brief `ai-router` blokkjának `allowed_paths` listáján kell lennie (könyvtár-elem
prefixként számít). Kívüli írás → blokk, és az üzenet a STOP-protokollt adja
vissza parancs formájában (`tools/codex-signal.sh stopped "…"`), nem tanácsként.

Ha a brief nem elemezhető, a hook **blokkol** — az elemezhetetlen szerződés nem
engedély. (Ugyanaz az elv, mint a mérce-őrnél: az bizonyíthatatlan őr = bukott őr.)

### §3 Tiltott parancsalakok — a MÉRT lista

`PreToolUse` (`Bash`): gate-csonkító pipe; a gate háttérbe küldése;
`analyze && test` lánc (L05 OOM); `git stash` a megosztott fán; force-push a
`tools/safe-force-push.sh` megkerülésével; csomagtelepítés; a MEGOSZTOTT fő
munkafa mutáló `git` művelete. Minden blokk-üzenet megnevezi az alternatívát.

### §4 Jelzés-őr — korlátos és fail-open

`Stop`: ha nincs terminális jelzés (`status=done|stopped|blocked`) a
`.codex-round-status`-ban, a hook megállítja a session lezárását, és kiírja a
három lehetséges jelzés-parancsot. **Legfeljebb kétszer**
(`STRUMSIGHT_STOP_GUARD_MAX`), utána átenged.

Miért korlátos: egy hibás őr, ami nem engedi befejezni a session-t, rosszabb a
hiányzó őrnél — a láncnak van elakadás-őre és self-healje, a végtelen ciklusból
viszont nincs kiút. Ugyanezért fail-open minden belső hibára.

### §5 Formázás írás után

`PostToolUse` (`Edit`/`Write`): `.dart` fájlra `dart format`. Sosem blokkol
(hiányzó `dart`, hiba, timeout → átenged). Célja a mért „format-piros gate"
javító körök megszüntetése.

### §6 Visszafelé kompatibilis

Ha a kör ága még nem tartalmazza a hookot vagy a settings fájlt, a burkoló
pontosan úgy viselkedik, mint eddig (`guard_enabled=0`). Egy régi ágra
visszatérő folytatás nem törik el.

## 3. Amit ez a réteg NEM tesz

* **Nem váltja ki a scope-auditot** (`tools/scope-audit.py`): a hook a
  gyors, lokális réteg; az auditált kontroll továbbra is a kör utáni audit és a
  független review. Bash-en át (`sed -i`, átirányítás) írt fájlt a hook
  szándékosan nem próbál teljesen lefedni — a mérce-őr tapasztalata szerint az
  ilyen elemzés hamis pozitívokat szül.
* **Nem érinti a codex-harness motorokat** (`codex`, `terra`, qwen-ek): ott a
  Codex CLI saját mechanizmusa és a preambulum + audit marad.
* **Nem gyengíti és nem is erősíti a gate-et.** A kör mércéje változatlan.

## 4. Ügynökök: a verifikáció kötelezővé tétele

A `Task` eszköz a MiniMax-körökben 2026-08-18 óta engedélyezett, és mérve
működik a MiniMax endpointon. Az implementer-preambulum ezzel a körrel egy
**kötelező** lépést kap: a lezáró `done` jelzés ELŐTT friss kontextusú
alügynök nézi át a diffet a brief acceptance-mátrixa ellen, és a §10 handoffba
a verdikt is bekerül. A mért indok: a MiniMax gyengéi (invariáns-lazítás,
fixture-default vakfolt, nem futtatott állítás a handoffban) mind olyanok,
amiket friss szem elkap, a saját kontextusában dolgozó modell viszont nem.

## 4.1 Ismert rés — emberi engedélyt igényel

Két lépés MARADT nyitva, mert mindkettő a mérce saját, védett zónáját írná
(`H-GATEGUARD`), és ehhez emberi engedély kell
(`STRUMSIGHT_GATE_EDIT_OK=1` vagy a `.claude/gate-edit-authorized` marker):

1. `.github/workflows/router-ci.yml` push-szűrője nem ismeri a
   `tools/hooks/**` és `tools/implementer-settings.json` útvonalakat — egy
   CSAK ezeket módosító PR-en a Router CI el sem indulna. (Ugyanaz a
   hibaosztály, amit a 2026-08-18-i 17-utas bővítés már egyszer javított.)
2. A `.claude/hooks/protect_factory_files.py` `PROTECTED_GLOBS` listája nem
   tartalmazza a `tools/hooks/*`-ot, tehát elvben egy kör a saját őrét
   szerkeszthetné — a gyakorlatban ehhez a briefjének fel kellene sorolnia a
   fájlt, amit a scope-őr és a review is látna.

Amíg ezek nyitva vannak, a védelmet a scope-audit és a független review adja.

## 5. Bizonyíték

* `tools/tests/test_implementer_guard.py` — 15 teszt: no-op nem-körben,
  scope-engedély/-blokk, könyvtár-prefix, `MultiEdit`, elemezhetetlen brief
  (fail-closed), hét tiltott és öt legitim parancsalak, jelzés-őr korlátja,
  `PostToolUse` sosem blokkol, valamint a bekötés (settings + burkoló).
* **Élő füst-teszt a MiniMax endpointon (2026-08-18), három futással:**
  1. teljes burkoló-út (`tools/mm-round.sh`, preambulummal): a modell a brief
     STOP-protokollja alapján `stopped`-ot jelzett — helyes kimenet, de ez a
     PROMPTOT méri, nem a hookot;
  2. preambulum nélkül: a modell megkereste és elolvasta a hook forrását, majd
     `stopped` — megint nem a mechanizmus bizonyítéka;
  3. **döntő mérés** (a hook a munkafán KÍVÜL, „ne olvass semmit, írd meg
     azonnal" prompttal): a modell kiadta a `Write` hívást, és a válasz
     `PreToolUse:Write hook error: … IMPLEMENTER-ŐR: lib/tiltott_segito.dart
     NINCS a(z) E99-R99 engedélyezett fájllistáján` lett; **a fájl nem jött
     létre**, a modell pedig helyesen jelentette a blokkot.

  A három futás sorrendje maga is lecke: az első kettő „zöld" eredménye a
  mechanizmusról SEMMIT nem bizonyított volna.
* **A `round-auditor` alügynök élő mérése** ugyanezen az endpointon: a
  `--agents` kapcsolóval átadott definíció betöltődött, a `Task` hívás lefutott,
  és az auditor bizonyítékkal alátámasztott leletet adott vissza (a füst-teszt
  briefjéről helyesen mondta ki, hogy hiányzik belőle az acceptance-mátrix és a
  handoff, illetve hogy a hivatkozott fájlok nem léteznek).
* A nyilvántartás `max_out` oszlopa mostantól tényleges hatás:
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (minimax 32768, sonnet-impl 64000).
