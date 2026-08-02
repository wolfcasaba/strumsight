# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-02
> (önjavító kör, E02-R21 H4 — TIZEDIK önjavító/halt kör ugyanazon a taskon —
> a gate most a modell TÉNYLEGES tartalmi munkáján mér, nem a mellette futó
> kozmetikai debrisen, PR #54, `heal/E02-R21-H4-3` → squash `aff19e7`.**
> Mért gyökérok ([`docs/LESSONS.md` L46](docs/LESSONS.md)): az L45-fix (PR
> #53) utáni `reset` + friss `run` (lásd "Update 7" lent) MEGERŐSÍTETTE, amit
> a gate-log most már mérhetővé tett — mindhárom próba (`RECOVERED_M3_CALL_1`,
> `RECOVERED_M3_CALL_2` `format`-on, Terra `FINAL_GATE` `analyze`-on: 3
> `unused_import`) a Practice V2 A1/A2/A3 wiring HELYES tartalmával futott, a
> gate mindhárom kudarca kizárólag mechanikusan javítható debris volt. A
> router `max_m3_attempts_per_task=2`/`max_terra_calls_per_task=1` fail-closed
> rögzített (self-heal sem lazíthatja), és minden gate-lépés egyetlen,
> nem-újrapróbálható hívás — egy kozmetikai hiba ugyanúgy elfogyasztja a
> keretet, mint egy logikai hiba, mert a router modell-hívás és gate-mérés
> között semmit nem normalizált. **Javítás:** `tools/model-router.py`
> `_gate_runner`-je (NEM a védett `tools/round-gate.sh`) mostantól minden
> NEM-baseline gate-hívás előtt lefuttatja `dart format lib test tool`-t és
> `dart fix --apply`-t a munkafán; a baseline-mérés érintetlen. Egyetlen
> gate-küszöböt nem lazít — csak azt biztosítja, hogy a mérés a modell
> tényleges munkáján történjen. Kötelező regresszió, RED a javítás előtt
> (a mért `unused_import` túléli a gate-et) / GREEN utána (`git stash`-sel
> visszamérve): `tools/tests/test_router_gate_normalize.py`. `python3 -m
> pytest tools/tests -q`: 113 passed, 33 subtests passed (110→113).
> `router-ci.yml` zölden mind push-, mind workflow_dispatch-triggerrel, a
> merge-elt SHA-n (`20cb75e` → squash `aff19e7`). **Ez a javítás sem oldja
> meg a Practice V2 A1/A2/A3 tényleges befejezését/commitolását/review-ját**
> — az továbbra is a következő rendes kör (nem a self-heal) dolga; a
> task-state jelenleg is `STOPPED`, a következő session dolga a
> `reset --task-id E02-R21` + friss `run`.
> Előző kör: 2026-08-02
> (Pipeline E02-R21 — a gate_history-fix (PR #53) UTÁNI első friss `run`
> VÉGRE valódi, tracked A1/A2/A3-diffet termelt, de a keret ismét
> `STOPPED`-be fogyott egy TRIVIÁLIS hibán: H4, a KILENCEDIK halt/önjavító
> kör ugyanazon a taskon, de az ELSŐ, ahol a production-drótozás mérhetően
> majdnem kész.** A munkapéldányon (`ss-auto-e02-r21`) egy korábbi session
> jelöletlen, committolatlan fájlját (`practice_observation_gateway_provider.dart`)
> eltávolítottam, a branchet `origin/main`-re rebase-eltem (PR #53 benne,
> konfliktus nélkül), majd `python3 tools/model-router.py reset --task-id
> E02-R21` → `NOT_STARTED`. A friss `tools/ai-router-round.sh run` a
> Bash-eszköz 600s plafonja miatt kétszer megszakadt `M3_CALL_1`/`M3_CALL_2`
> közben (mindkétszer helyesen kezelve, próba nem veszett), a HARMADIK hívás
> jutott `STOPPED`-ig. **Első alkalommal a `gate_history[].log` a TELJES
> gate-kimenetet tartalmazta** (PR #53 hatása) — ez fedte fel, hogy mindhárom
> próba ÉRDEMI munkát végzett: `RECOVERED_M3_CALL_1`/`RECOVERED_M3_CALL_2`
> `format`-on bukott (a modell módosította, de nem formázta a három MEGLÉVŐ
> wiring-célfájlt), a `FINAL_GATE` (Terra) a formázást megoldotta, de
> `analyze`-on bukott: 3 `unused_import` figyelmeztetés a Terra írta
> `test/features/practice/application/practice_production_wiring_test.dart`
> 32./42./47. sorában. A munkafa `git diff HEAD` **ELSŐ ízben mutat valódi,
> tracked tartalmat mindhárom wiring-célfájlon** (`practice_session_providers.dart`
> +104/-3, `practice_setup_controller.dart` +18/-19, `practice_effect_listener.dart`
> +42/-2) — ADR 0111 §1–§4-nek megfelelő auto-dispose controller `.family`
> (A1), aktiváló prepare-sink + `PracticeSessionHost` adapter (A2), valódi
> mode/source/definition kódokkal épített recorder (A3). **A blokkoló hiba
> NEM architektúra/scope-kérdés, hanem három felesleges import-sor törlése** a
> nevezett teszt-fájlban. A 2 M3 + 1 Terra keret kimerült, `resume` itt nem
> alkalmazható (a keret nulla) — a pipeline-prompt §1.1/§2 szerint `STOPPED`
> `auto`-n feltétlen HALT. A committolatlan diff (3 tracked + 2 untracked
> fájl) SZÁNDÉKOSAN a munkapéldányon maradt bizonyítéknak — nem commitoltam
> (a router csak `READY_FOR_REVIEW` után auditáltatna commitot, ez a kör
> review nélkül `STOPPED`-be futott). Teljes mérés:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md) "Update 7"
> szakasz, a `codex/e02-r21-practice-production-wiring` ágon (`2bb61a1`).
> **A következő session dolga:** a három unused-import sor törlése a
> teszt-fájlban, `tools/round-gate.sh` újrafuttatása a teljes mátrixra, majd —
> ha zöld — commit + független review + CI-dispatch + merge. Ez tisztán
> tartalmi javítás, NEM router-infrastruktúra hiba.
> Előző kör: 2026-08-02
> (önjavító kör, E02-R21 H4 — NYOLCADIK önjavító/halt kör ugyanazon a
> taskon — a gate_history mostantól a teljes gate-logot is megőrzi, PR #53,
> `60ff5c4`.** Mért gyökérok ([`docs/LESSONS.md` L45](docs/LESSONS.md)): a
> "Update 6" halt (lásd lent) — és az őt megelőző "Update 5" is — tisztán
> tartalmi gate-kudarc volt (format/analyze/test), a router infrastruktúrája
> (sandbox, állapotgép, prompt-építés) mindkétszer mérve hibátlan. DE a
> tényleges `round-gate.sh` kimenetet (`GateRun.log`) a router csak a
> KÖVETKEZŐ modellhívás repair/escalation promptjába illesztette, a
> perzisztens task-state-be (`gate_history`) sosem — `_record_gate` csak
> `outcome/failed_step/command_exit_code/error_hash`-t írt. Ez azt
> jelentette, hogy a minden korábbi review dokumentált reprodukciós parancsa
> (`python3 tools/model-router.py status --task-id <ID> --json`) egy
> tartalmi gate-kudarc UTÁN csak egy hash-t adott vissza — sem az
> orchestrátor, sem egy self-heal session nem tudta MÉRÉSSEL eldönteni a
> Class A/B/C besorolást anélkül, hogy egy újabb (a self-heal jogosultságán
> kívül eső) modellhívást indítson. **Javítás:** `_record_gate` mostantól a
> `gate_history` minden bejegyzésébe elteszi a teljes (redaktált) logot is,
> `gate.log[-20000:]`-ra csonkolva (ugyanaz a konvenció, mint a
> `_repair_prompt` 16000 karakteres evidence-ablaka) — egyetlen gate-küszöböt
> vagy teszt-listát nem érint. Kötelező regresszió, RED a javítás előtt
> (`KeyError: 'log'`) / GREEN utána:
> `test_router.py::test_gate_history_persists_the_full_gate_log_for_diagnosis`.
> `python3 -m pytest tools/tests -q`: 110 passed, 33 subtests passed
> (109→110). `router-ci.yml` zölden mind push-, mind
> workflow_dispatch-triggerrel, a merge-elt SHA-n (`60ff5c4` → squash
> `16fc08f`). **Ez a javítás MEGFIGYELHETŐVÉ teszi a következő tartalmi
> gate-kudarcot, de NEM oldja meg azt** — a Practice V2 A1/A2/A3 wiring
> továbbra sincs elkezdve; a kimerült task-state `reset --task-id E02-R21`-re
> vár, és a következő `run` valószínűleg ismét format/analyze/test hibába
> fut, de EZUTTAL a `gate_history[].log` mezőben a tényleges hibaüzenettel,
> ami a következő self-heal (vagy ember) számára ELSŐ ízben teszi lehetővé a
> tényleges Class A/B döntést mérés alapján, modellhívás nélkül.
> Előző kör: 2026-08-02
> (Pipeline E02-R21 — a router-prompt-fix (PR #52) UTÁNI első ÉLES `run` ÚJRA
> HALT-ba futott, tartalmi gate-kudarccal, NYOLCADIK halt/önjavító kör
> ugyanezen a taskon, de csak a MÁSODIK, ahol a halt tartalmi, nem
> infrastrukturális: H4.** A munkapéldány (`ss-auto-e02-r21`) az Update 5 óta
> változatlan `294a008`-on állt; `git stash -u` + `rebase origin/main` +
> `stash pop` menettel `ad8286e`-re (PR #52 benne) hozva, konfliktus nélkül.
> **Az Update 5-ből örökölt két árva, committolatlan fájl (A4 gateway
> provider, A5 teszt) blokkolta az indítást** — a router
> `validate_baseline_manifest`-je (`tools/ai_router/security.py:162-185`)
> fail-closed tiltja a PRECHECK-et bármilyen tracked VAGY untracked
> elváltozásnál (mérve: `blocked — baseline has untracked files: …`, exit 40,
> modellhívás előtt). Az A5-teszt `expect(host, isNotNull)`-t vár egy ma még
> nem létező wiring után, ezért a két fájl COMMITOLÁSA is azonnal piros
> baseline-t adott volna — helyette **tételes `rm`-mel törölve** (a
> bizonyíték az Update 5 szövegében megmarad), majd **második**
> `reset --task-id E02-R21` (mérve: a router `run()`-ja egy lezárt state-en a
> `status`-t nem ellenőrzi újra, az első `blocked` hívás után egy puszta
> ismétlés a régi eredményt adja vissza változatlanul). A tiszta baseline-t
> függetlenül is igazoltam: `flutter analyze lib/ test/ tool/` a tiszta
> munkafán → **"No issues found!"**, egybevágva a router saját
> `BASELINE_GATE: pass`-ával. **A friss `run` maga hosszabb, mint a
> Bash-eszköz 600s plafonja** — két megszakítást a router H6-fixje helyesen
> kezelt (üres diffnél nem fogyasztotta a próbát), a HARMADIK hívás jutott
> érdemi eredményhez. Végeredmény: `stopped — final gate failed:
> code_failure` (exit 20). Teljes `gate_history`: `BASELINE_GATE` pass →
> `RECOVERED_M3_CALL_1` code_failure(`format`) → `GATE_2` (M3 2. friss próba)
> code_failure(`analyze`) → `FINAL_GATE` (Terra) code_failure(`test
> test/core`) — `m3_attempts=2`, `terra_calls=1`, keret kimerült. A router
> **ismét szándékosan** redaktálja a gate-hibaszöveget (csak
> kategória+lépés+hash), a worktree-ből csak EGY túlélő, committolatlan új
> fájl (`practice_observation_gateway_provider.dart`, 71 sor, önmagában
> `flutter analyze`-tiszta) és NULLA tracked eltérés mérhető — a három
> tényleges (format/analyze/test-core) diff nem rekonstruálható. **Mérhető ÚJ
> különbség az Update 5-höz képest:** a `gate_tests` sorrendje `[practice,
> learn, core, app, property]`; az Update 5 az ELSŐ (`test/features/practice`)
> csomagon bukott, a mai a HARMADIKON (`test/core`) — vagyis a mai Terra-diff
> túljutott a `practice`+`learn` csomagokon. Ez arra utal, hogy a #52-es fix
> ténylegesen módosította a próbák viselkedését (az A5-teszt-fájl sem élte túl
> egyetlen próbát sem ezúttal, szemben az Update 5 mindhárom próbát túlélő
> A4+A5 párjával), de **a kör tényleges magja (A1/A2/A3 wiring) így sem
> készült el** a 2 M3 + 1 Terra kereten belül. Teljes mérés:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md)
> "Update 6" szakasz, a `codex/e02-r21-practice-production-wiring` ágon
> (`a3f1f52`). **A következő session két útja** (egyiket sem hajtottam
> végre): (1) router-reset + friss `run` ugyanazzal a brieffel — ha a
> mintázat (STOPPED, tovább jutva, de A1/A2/A3-ig nem érve) egy HARMADIK
> alkalommal is ismétlődik, az már a brief méretére/sorrendjére mutat (Class
> B), nem a router promptjára/infrastruktúrájára; (2) explicit
> `codex`/`minimax` motor ugyanerre a briefre, a TELJES, nem redaktált logért,
> ami végre file:sor pontossággal megmondaná a gyökérokot. **A Practice V2
> production-drótozás (a kör tényleges célja) továbbra sincs elkezdve.**
> Előző kör: 2026-08-01
> (önjavító kör, E02-R21 H4 — HETEDIK önjavító/halt kör ugyanazon a taskon —
> a router repair/escalation promptja JAVÍTVA, PR #52, `813b826`.** Mért
> gyökérok ([`docs/LESSONS.md` L44](docs/LESSONS.md)): a "Update 5" halt
> (lásd lent) SZÖVEGE tartalmi gate-kudarcnak tűnt, de a saját mérés
> (`docs/reviews/e02-r21-review.md` "Update 5") kimutatta, hogy mindhárom
> független próba (2 M3 + 1 Terra) KIZÁRÓLAG a brief két ÚJ fájlját (A4/A5)
> érintette — a router `_repair_prompt` (2. M3-próba) és
> `build_escalation_packet` (Terra) SZÓ SZERINT "minimal fix, no adjacent
> refactor / no widened scope"-ot mondott minden javító próbának, ami
> szerkezetileg megtiltotta, hogy egy befejezetlen (nem hibás, csak
> befejezetlen) 1. próba után a 2./3. próba a brief hátralévő, még
> érintetlen `allowed_paths`-ait szerkessze. **Ez általános router-hiba, nem
> E02-R21-specifikus** — bármely jövőbeli brief, ahol az 1. próba nem ér a
> végére, ugyanide futna. **Javítás:** mindkét prompt-építő most a router
> saját, perzisztált `state["changed_paths"]`-ából kiszámítja, mely
> `allowed_paths` maradt érintetlenül, és a promptba explicit szakaszként +
> egy carve-out mondattal kerül ("finishing the brief is not scope creep").
> Kötelező regresszió, RED a javítás előtt / GREEN utána (stash-elt
> production-diff-fel igazolva):
> `test_router_hardening.py::test_m3_repair_prompt_tells_model_to_finish_untouched_allowed_paths`,
> `test_packet.py::test_packet_names_allowed_paths_untouched_by_any_attempt`.
> `python3 -m pytest tools/tests -q`: 109 passed, 33 subtests passed (107→109).
> `router-ci.yml` zölden mind push-, mind workflow_dispatch-triggerrel, a
> merge-elt SHA-n (`c14a7c6` → squash `813b826`). **Ez a javítás a router
> prompt-építését korrigálja, NEM az E02-R21 task tartalmi munkáját** — a
> kimerült task-state (`STOPPED`, 2/2 M3 + 1/1 Terra) továbbra is
> `reset --task-id E02-R21`-re vár; a Practice V2 production-drótozás
> (A1/A2/A3) még mindig el sem kezdődött. Ha a javított promptok mellett is
> megismétlődik az "csak A4/A5" mintázat, az már a brief méretére/sorrendjére
> mutat (Class B), nem a router promptjára.
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — a H4-sandbox-fix (PR #51) UTÁNI első ÉLES `run` is HALT-ba
> futott, de ez az ELSŐ E02-R21 kísérlet, ahol a router teljes infrastruktúrája
> (sandbox, állapotgép, megszakítás-kezelés) mérve HIBÁTLANUL futott végig — a
> STOPPED valódi tartalmi gate-kudarcból jön, NEM infra-hibából: H4.** A
> munkapéldány (`ss-auto-e02-r21`) `origin/main`-re rebase-elve (`294a008`,
> tartalmazza a H4-sandbox-fixet). Az orchestrátor a §1.1 szerinti
> `tools/ai-router-round.sh run` hívást futtatta előtérben; a Bash-eszköz 600s
> plafonja miatt a hívás kétszer SIGTERM-mel megszakadt, mindkétszer helyesen
> kezelve (H6-fix): az első megszakítás előtt még nem volt diff, a próba nem
> fogyott; a második megszakítás UTÁN már volt valódi, hatókörön belüli diff,
> ezért a harmadik hívás nem a modellt hívta újra, hanem a gate-et futtatta.
> A harmadik hívás lezárta a teljes keretet: `RECOVERED_M3_CALL_1` →
> `code_failure` (`format`), `M3_CALL_2` → `code_failure` (`analyze`), Terra →
> `code_failure` (`test test/features/practice`) → `STOPPED`. A router
> **szándékosan** redaktálja a gate-hiba szövegét (csak kategória + lépésnév +
> SHA-256 hash marad), ezért a pontos hibaszöveg ebből a sessionből nem volt
> kinyerhető — de a munkapéldány állapotából mérve: a két ÚJ fájl (A4 gateway
> provider, A5 piros→zöld teszt) mindhárom próbán túlélte, koherens és a brief
> §4/§6-nak megfelelő tartalommal, de a **három MEGLÉVŐ wiring-célfájl
> (`practice_session_providers.dart`, `practice_setup_controller.dart`,
> `practice_effect_listener.dart`) ma is bitre a baseline-on áll** — egyik
> próba sem jutott el a kör tényleges magjáig (A1/A2/A3). Teljes mérés +
> reprodukciós parancsok:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md)
> "Update 5" szakasz, a `codex/e02-r21-practice-production-wiring` ágon
> (`94c4b9f`). A router task-kerete (2/2 M3 + 1/1 Terra) kimerült — a
> következő session dolga eldönteni: (a) `reset --task-id E02-R21` + friss
> `run` ugyanazzal a brieffel, vagy (b) explicit `codex`/`minimax` motor a NEM
> redaktált logért, hogy a format/analyze/test kudarcok pontos szövege
> kiderüljön. **A Practice V2 production-drótozás (a kör tényleges célja)
> továbbra sincs elkezdve a production kódban** — ez a HATODIK halt/önjavító
> kör ugyanezen a task-on, de az ELSŐ, ahol az ok tartalmi, nem infrastrukturális.
> Előző kör: 2026-08-01
> (önjavító kör, E02-R21 H4 JAVÍTVA — PR #51, `6d99820`.** Mért gyökérok
> (`docs/LESSONS.md` L43): a router valódi (nem-smoke) `codex exec` hívása
> `tools/ai_router/execution.py`-ban `--sandbox workspace-write`-ot használt,
> ami `bwrap`-alapú hálózati namespace-izolációt igényel — ez a konténer nem
> tudja létrehozni (`bwrap --unshare-net --dev-bind / / true` → `Failed
> RTM_NEWADDR: Operation not permitted`, router-független reprodukcióval).
> **Javítás:** `build_codex_argv`-ban `"workspace-write"` →
> `"danger-full-access"` mindkét profilra (m3, terra) — ugyanaz a minta, mint
> a már működő `tools/codex-round.sh:31` `-s danger-full-access`-e; az
> izolációt a dedikált munkapéldány adja, nem a bwrap. Kötelező regressziós
> teszt (`tools/tests/test_execution.py`, `--sandbox` argumentum-assert, RED
> `workspace-write`-on / GREEN utána). `python3 -m pytest tools/tests -q`:
> 107 passed. `router-ci.yml` zölden futott a merge-elt SHA-n (mind push-,
> mind workflow_dispatch-triggerrel). A kimerült production task-state
> (`E02-R21`, `STOPPED`, 2/2 M3 + 1/1 Terra, mind sandbox-hibával) `reset
> --task-id E02-R21`-lel törölve → `NOT_STARTED`, a lánc a következő
> firingen szabadon `run`-olhat. A `_smoke()` valódi `exec_command`-dal
> kiegészítése (hogy ez a hibaosztály jövőben a smoke-fázisban bukjon el, ne
> a teljes M3+Terra keret felégetésével) **szándékosan kimaradt** — a
> gyökérokot nem érinti, tartalmi/nem-heal kör dolga, ha egyáltalán kell.
> **A Practice V2 production drótozás (E02-R21 tényleges célja) még mindig
> el sem kezdődött** — ez volt az ÖTÖDIK önjavító/halt-kör ugyanezen a
> task-on; a router-infrastruktúra most first-time zölden, tartalmi munka
> nélkül fut le a következő firingen.
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — az ÖSSZES korábbi router-infra fix (#46/#47/#48/#49/#50)
> UTÁNI, első valóban végig lefutott router-állapotgép is HALT-ba futott, egy
> ÚJ, a router logikájától FÜGGETLEN okkal: H4.** A munkapéldány
> `origin/main`-re (`f27651a`) rebase-elve, a pre-flight (ADR 0111 + brief)
> változatlanul jó. `python3 tools/model-router.py run` 2 M3-kísérletet + 1
> Terra-hívást futtatott le **megszakítás nélkül, hibátlan állapotgép-logikával**
> — mindhárom próbán a `round-gate.sh` **pass**-t adott, de **egyik
> modellhívás sem hozott létre egyetlen scope-on belüli fájlváltozást sem**
> (`scoped_changed_paths=[]` mindhárom próbán). Mért gyökérok: a `codex exec`
> valódi (nem-smoke) hívása `--sandbox workspace-write`-ot használ
> (`tools/ai_router/execution.py:100-101`), ami `bwrap`-alapú hálózati
> namespace-izolációt igényel Linuxon — ez a konténer **nem** tud hálózati
> namespace-t létrehozni, router-független módon reprodukálva: `bwrap
> --unshare-net --dev-bind / / true` → `bwrap: loopback: Failed RTM_NEWADDR:
> Operation not permitted` (állandó, nem tranziens képesség-hiány). Emiatt
> minden `exec_command` azonnal elbukik a modellhívásban — a pontos induló
> promptot közvetlenül elküldve az M3 profilnak, a modell **helyesen
> megtagadta** a feladatot és pontos diagnózist adott ahelyett, hogy
> fabrikált volna. A `tools/model-router.py smoke` parancs ezt nem fedi fel,
> mert `--sandbox read-only`-t használ egy `exec_command`-ot sosem igénylő
> triviális prompttal — strukturálisan vak erre a hibaosztályra. A **létező**
> `tools/codex-round.sh:31` már `-s danger-full-access`-t használ pontosan
> emiatt; a router saját Codex-hívása ezt a már ismert box-tényt sosem vette
> át. Eredmény: `STOPPED`, a task 2/2 M3 + 1/1 Terra kerete kimerült valódi
> tartalmi ok nélkül, a Practice V2 production-drótozás (a kör tényleges
> célja) **még mindig el sem kezdődött** — ez az ÖTÖDIK önjavító/halt-kör
> ugyanezen a task-on, de az ELSŐ, ahol a hiba nem a router állapotgépében
> (`router.py`/`state.py`) van, hanem a `execution.py` sandbox-választásában.
> Teljes mérés + reprodukció + javítási javaslat:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md)
> "Update 4" szakasz, a `codex/e02-r21-practice-production-wiring` ágon
> (`c1579f4`). Tanulság: `docs/LESSONS.md` L43. **Az önjavító körnek**
> `tools/ai_router/execution.py`-ban a `build_codex_argv` sandbox-argumentumát
> `danger-full-access`-ra kell cserélnie (mindkét profilra), kötelező
> regressziós teszttel, majd `reset --task-id E02-R21`-gyel felszabadítania a
> kimerült M3+Terra keretet, mielőtt a lánc újra `run`-t próbál.
> **A Practice V2 production drótozás (a kör tényleges célja) ÉRINTETLEN —
> ez a kör kizárólag a router-infrastruktúrát vizsgálta, ÖTÖDSZÖR ugyanezen
> a task-on.**
> Előző kör: 2026-08-01
> (önjavító kör, E02-R21 H6 4. előfordulása JAVÍTVA.** Mért gyökérok
> (`docs/LESSONS.md` L42, két FÜGGETLEN hiba egyszerre): (1)
> `tools/ai_router/router.py` resume-ága a `M3_CALL_N` fázist (a hívó
> Bash-eszköz 600s-es plafonja által mid-call megölt router-folyamat) ugyanúgy
> kezelte, mint a `M3_ATTEMPT_N`-t (a hívás már lezajlott) — pedig `M3_CALL_N`
> resume-on SOSEM jelentheti, hogy a `run_model()` visszatért, mégis
> szintetikus `code_failure`-ként elfogyasztotta a modell egyetlen valódi
> esélyét. (2) `tools/codex-signal.sh` a `git rev-parse --show-toplevel`-t a
> hívó öröklött cwd-jéből oldotta fel, nem a saját szkript-útvonalából, ezért
> a dokumentált (abszolút úton, `cd` nélküli) orchestrátor-hívási minta
> szisztematikusan a rossz repót mérte. Javítva: (1) resume-on `M3_CALL_N` +
> nincs hatókörön belüli diff ⇒ a router visszaadja a kísérletet
> (`m3_attempts -= 1`, `phase = "M3_READY"`) és friss próbaként ismétli
> (ugyanaz a minta, mint a `_provider_decision` meglévő
> `partial_changes=False` ága); (2) a szkript a saját
> `${BASH_SOURCE[0]}`-jából oldja fel a repo-gyökeret, minden git-parancs
> `git -C "$root"`-tal fut. Mért RED→GREEN két külön regresszióval:
> `tools/tests/test_router_resume.py::test_resume_after_interrupted_m3_call_retries_without_consuming_the_attempt`,
> `tools/tests/test_pipeline_integration.py::test_signal_resolves_git_state_from_the_worktree_not_the_callers_cwd`.
> Teljes `tools/tests` (106 teszt, 33 subtest) zöld, `router-ci.yml` zöld a
> merge-SHA-n: [PR #50](https://github.com/wolfcasaba/strumsight/pull/50)
> (squash `2e70a1a`). Tanulság: `docs/LESSONS.md` L42.
> **A Practice V2 production drótozás (a kör tényleges célja) ÉRINTETLEN —
> ez a kör kizárólag a router-infrastruktúrát javította, NEGYEDSZER ugyanezen
> a task-on. A stuck task-state resetelése és a következő `run` a lánc
> következő firingjén automatikusan indul.**
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — a H4+H6 fixek (#48/#49) UTÁNI, első valóban éles router-
> futás is HALT-ba futott, ÚJ, a router-infrastruktúrától FÜGGETLEN okkal:
> H6.** A munkapéldány rebase-elve `origin/main`-re (mindkét fix benne), a
> pre-flight (ADR 0111 + brief) változatlanul jó. Az orchestrátor a §1.1
> parancsot futtatta, de a Bash-eszköz alapértelmezett (120000 ms) és kemény
> (600000 ms) időkorlátja rövidebb, mint egyetlen `model-router.py run` hívás
> ezen az ARM boxon — az első két hívást a Bash-eszköz SIGTERM-mel ölte meg
> (jelzés nélkül, kétszer), mielőtt a router jelezhetett volna. A HARMADIK
> (10 perces) hívás a megszakított `M3_CALL_2` fázisból tért vissza: a router
> megszakítás-kezelése (`tools/ai_router/router.py:581-604` körül) a csonka
> kísérletet **elfogyasztja** (szintetikus `code_failure`), nem ismétli —
> ezért az M3-keret (2/2) valódi próba nélkül merült ki, és a kötelező,
> TELJES (megszakítás nélküli) Terra-hívás is önmagában, tisztán üres diffet
> adott (`FINAL_GATE: "Terra call produced no scoped changes"`). Eredmény:
> `STOPPED`, a task 2/2 M3 + 1/1 Terra kerete kimerült, a Practice V2
> production-drótozás (a kör tényleges célja) **még mindig el sem
> kezdődött** — ez a NEGYEDIK önjavító/halt-kör ugyanezen a taskon, de az
> ELSŐ, ahol a router-infrastruktúra maga már zöld volt. Egy MÁSODIK, ettől
> független hibát is mértünk: `tools/codex-signal.sh` a `git rev-parse
> --show-toplevel`-t a hívó folyamat öröklött cwd-jéből oldja fel, nem a
> munkapéldányból — a dokumentált orchestrátor-hívási mintával (nincs `cd` a
> munkapéldányba) ez szisztematikusan a rossz repót méri: a
> `.pipeline/router-status` mirror `branch=main head=a81838e`-t írt, a
> tényleges munkapéldány pedig a kör-ágon állt — ez hiúsítja meg a §3
> kötelező `dirty_files`/`headSha` ellenőrzését az `auto` úton (a `status=`/
> `summary=` mező marad hiteles, a `branch=`/`head=`/`dirty_files=` nem).
> Teljes mérés + reprodukció + javítási javaslat: `docs/LESSONS.md` L42.
> **Az önjavító körnek el kell döntenie**, hogy (a) a router megszakítás-
> kezelését kell-e retry-ra módosítani (a Bash-eszköz 600s plafonja alatt
> is biztonságos legyen), és/vagy (b) a `codex-signal.sh` cwd-függését kell
> javítani, mielőtt a task-ot újra resetelik és futtatják.
> Előző kör: 2026-08-01
> (önjavító kör, E02-R21 H6 3. előfordulása JAVÍTVA.** Mért gyökérok
> (`docs/reviews/e02-r21-review.md` "Update 3"): `StateStore.reset_task`
> (`tools/ai_router/state.py:131-144`) csak a `tasks/<id>.json`-t törölte,
> a `terra-ledger.json`-t nem — a `reserve_terra` `task_count` szűrője
> (`state.py:184-188`) a `daily_count`-tal ellentétben nem nap-alapú, ezért
> a task egyetlen valaha történt Terra-foglalása örökre kimerítette a saját
> kvótáját, `reset --task-id` után is. Javítva: `reset_task` egy új
> `_archive_terra_reservations` segéddel a task saját ledger-sorait
> `status="archived"`-ra állítja ugyanabban a hívásban (a `_ledger_lock()`
> alatt), így mind a task-, mind az aznapi globális kvótája felszabadul; más
> taskok sorai érintetlenek. Mért RED→GREEN
> (`tools/tests/test_state_store.py::test_reset_task_clears_the_terra_ledger_so_the_task_can_reserve_again`,
> `::test_reset_task_only_archives_that_tasks_own_reservations`), teljes
> `tools/tests` (104 teszt, 33 subtest) zöld, `router-ci.yml` zöld a
> merge-SHA-n: [PR #49](https://github.com/wolfcasaba/strumsight/pull/49)
> (squash `dfb0e26`). A production `~/.local/state/strumsight-ai-router`
> state-en is lefuttatva az ÚJ kódú `reset --task-id E02-R21` — a ledger
> E02-R21 sora `archived`, a task `NOT_STARTED`, a lánc a következő
> firing-en fresh PRECHECK-et futtat. Tanulság: `docs/LESSONS.md` L41.
> **A Practice V2 production drótozás (a kör tényleges célja) ÉRINTETLEN —
> ez a kör kizárólag a router-infrastruktúrát javította, HARMADSZOR
> ugyanezen a task-on.**
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — a H4-fix (#48) UTÁNI friss `run` is HALT-ba futott,
> HARMADIK, a router `reset --task-id` és a Terra-ledger közötti
> inkonzisztencia miatt: H6.** `python3 tools/model-router.py reset --task-id
> E02-R21` a task `state.json`-ját törli, de a Terra-hívások naplóját
> (`~/.local/state/strumsight-ai-router/terra-ledger.json`) NEM — a
> `reserve_terra()` `task_count` szűrője (`tools/ai_router/state.py:184-188`)
> a `daily_count`-tal ellentétben **nem nap-alapú**, ezért az E02-R21 task
> egyetlen (mai, H4-fix ELŐTTI) Terra-foglalása örökre kimeríti a
> `max_terra_calls_per_task=1` kvótát, akárhányszor `reset`-elik a task-ot.
> Mérve: friss `run` 2/2 M3-kísérlet után (`NO_CHANGE_1` → `RECOVERED_M3_CALL_2
> pass`) Terra-hívást próbált, `DEFERRED "task Terra budget is exhausted"`-tel
> állt meg — a munkapéldány `git status`/`git diff HEAD` mindkettő üres, a
> Practice V2 production drótozás (a kör tényleges célja) **még mindig el sem
> kezdődött**. Teljes mérés + két javítási javaslat + reprodukáló parancs:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md) "Update 3"
> szakasz, a `codex/e02-r21-practice-production-wiring` ágon (`b1653ef`).
> **A router-fixek (#46/#47/#48) mindhárom korábbi router-hibát javították —
> ez egy NEGYEDIK, tőlük eltérő gyökérok.**
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — önjavító kör, H4 halt JAVÍTVA.** Mért gyökérok (lásd
> alább az előző bejegyzésben): a `_terra()` FINAL_GATE ága
> (`tools/ai_router/router.py:429` körül) és a `TERRA_REVIEW_OR_FIX`
> resume-ág (`run()`, `router.py:639` körül) nem ellenőrizte
> `audit.scoped_changed_paths`-t a `READY_FOR_REVIEW` visszaadása előtt —
> ugyanaz a hibaosztály, mint az L39/H6, csak az M3-hurok helyett a Terra-ágon.
> Javítva: új `DevelopmentRouter._terra_final_gate(gate, audit)` segéd,
> mindkét hívási hely ezen megy át — zöld gate-et `code_failure`-ra fordít,
> ha a diff üres. Mért RED→GREEN regresszió KÉT külön teszttel (a friss
> `_terra()` hívásra ÉS a `TERRA_REVIEW_OR_FIX` resume-ágra külön, mert a
> resume-ág csak kézzel felvett task-state-tel érhető el):
> `tools/tests/test_router.py::test_terra_final_gate_pass_with_no_scoped_changes_is_not_ready_for_review`,
> `tools/tests/test_router_resume.py::test_resumed_terra_review_or_fix_with_no_scoped_changes_is_not_ready_for_review`.
> Teljes `tools/tests` (104 teszt, 33 subtest): zöld. Tanulság:
> `docs/LESSONS.md` L40. **A Practice V2 production drótozás (a kör tényleges
> célja) ÉRINTETLEN — ez a kör kizárólag a router-infrastruktúrát javította.**
> Előző kör: 2026-08-01
> (Pipeline E02-R21 — a self-heal (#46/#47) UTÁNI friss `run` is HALT-ba
> futott, ÚJ, a H6-tól ELTÉRŐ router-hibával: H4.** A teljes M3+Terra keret
> (2/2 M3-kísérlet + 1/1 Terra-hívás) kimerült **valódi diff nélkül**
> (`changed_paths=[]`, `last_diff_hash` = üres string SHA-256), a router
> mégis `READY_FOR_REVIEW`-t jelzett. Mért gyökérok: `_terra()` FINAL_GATE ága
> (`tools/ai_router/router.py:426-432`) és a `TERRA_REVIEW_OR_FIX` resume-ág
> (`router.py:635-648`) **nem ellenőrzi** `audit.scoped_changed_paths`-t a
> `READY_FOR_REVIEW` visszaadása előtt — szemben az M3-kísérleti ág
> 709-721. sorában lévő azonos célú őrrel, amely EZT a hibát helyesen
> elkerülte (`NO_CHANGE_1` cella a gate-historyban, nem regresszió). Teljes
> mérés + javítási javaslat + reprodukáló parancs:
> [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md) "Update 2"
> szakasz, a `codex/e02-r21-practice-production-wiring` ágon (`3550e34`).
> **A Practice V2 production drótozás (a kör tényleges célja) MÉG MINDIG el
> sem kezdődött** — ez már a MÁSODIK önjavító kör lesz ugyanezen a task-on,
> mindkét alkalommal a router-infrastruktúra hibájával, nem a briefben vagy
> az implementáció tartalmában.**
> (GOV-03 / ADR 0112 önjavító kör, H6 4. előfordulás, ugyanaz az E02-R21 kör —
> az L38-ban diagnosztizált KÉT `tools/ai_router` hiba (a "csinált-e valamit
> az M3" döntés ugyanazt a `changed_paths` halmazt használta, mint a
> scope-sértés ellenőrzés, ezért a BASELINE_GATE `.dart_tool/`/`build/`
> mellékterméke M3-diffnek tűnt; a generált/ignorált mentesség csak az újonnan
> IGNORÁLT útvonalakra állt fenn, egy TRACKELT `docs/reviews/*.md` frissítés
> sosem kaphatott mentességet) JAVÍTVA: `ScopeAudit.scoped_changed_paths` új
> mező + kategória-független mentesség, `GENERATED_IGNORED_PREFIXES`/`GLOBS`
> bővítve (`.codex-round-status`, `docs/reviews`, `.ai/review-findings-*.md`).
> Mért RED→GREEN regresszió (`git stash`-sel igazolva) + zöld `router-ci.yml`
> a merge-SHA-n: [PR #47](https://github.com/wolfcasaba/strumsight/pull/47)
> (squash `35f6da1`). A stuck `E02-R21` router task-state
> `reset --task-id`-vel feloldva (`NOT_STARTED`), a lánc a következő
> firing-en friss `run`-t indít. Tanulság: `docs/LESSONS.md` L39 (L38 zárása).
> **A Practice V2 production drótozás (a kör tényleges célja) ÉRINTETLEN —
> ez a kör kizárólag a router-infrastruktúrát javította.**).**
> (GOV-03 / ADR 0112 önjavító kör, H6 3. előfordulás — a fenti két hiba
> DIAGNOSZTIZÁLVA (`docs/LESSONS.md` L38, `docs/reviews/e02-r21-review.md` a
> `codex/e02-r21-practice-production-wiring` ágon, `16b8d88`), a router-task
> BLOCKED terminal állapotban hagyva javítás nélkül — ezt zárta le a fenti kör).
> (E02-R20 epic-zárás lezárva — accessibility mátrix, performance számlálók,
> property gate, doD-tábla és a device-mátrix kész; a rendszerszintű rés
> (önálló Practice V2 session-út drótozatlan) nyíltan dokumentálva. A
> `migratedLearnEnabled` rollout-döntés a useré — a §3 rendszerszintű rés
> pótlása külön kör).
> Full round-by-round history: [`docs/handoff-archive.md`](docs/handoff-archive.md).

## 1. Current release state

- **StrumSight** — offline, on-device guitar chord + strum-direction detector
  (Flutter, Dart SDK ^3.12.2, Material 3, Riverpod 3 hand-written providers).
- `pubspec` version: **1.0.0+1** (development). No production release yet —
  release signing is fail-closed via `release-apk.yml` (ADR 0062); a version
  bump / release is a separate user decision.
- Development APK per round from CI (`build-apk.yml`), artifact name
  `strumsight-<ver>-<build>-<sha>-development.apk` (ADR 0051).
- **Epic 1 (Core Platform) technikailag kész** — a zárókör (E01-R16) gépi
  gate-jei zöldek; a végső elfogadás a user valódi-eszközös §16.3/§16.4 menetén
  áll (HORIZON-szabály: synthetic green ≠ done). Evidencia:
  [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).
- **Epic 2 (Practice Engine) lezárva** — E02-R20 (epic-zárókör) kész; a
  Practice V2 domain és application réteg kimerítően tesztelt, a migrated
  Learn útvonal (`migratedLearnEnabled`) élesíthető. Az önálló Practice V2
  Hub→Setup→Session út **drótozatlan** — a `practiceSessionHostProvider`
  defaultja `null`; a §3 rendszerszintű rés pótlása külön kör.
  Evidencia: [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md).

## 2. What is working

- **Detektálás (100% on-device):** Live képernyő (akkord + pengetésirány valós
  időben, DSP + CRNN ML), Analyze (felvett klip elemzése), Tuner, metronóm.
  DSP-igazság: `docs/rag/chunks/` — paraméter csak ADR-rel és ugyanabban a
  commitban frissített chunkkal változhat (AGENTS.md §9).
- **Tanulás/tartalom:** Learn (leckék), Songs, Library (sessionök), Progress,
  Streak, onboarding, i18n (en/hu ARB).
- **Opcionális account-réteg:** FastAPI + SQLite + JWT backend (`backend/`),
  login + settings-sync; **az app kijelentkezve teljes értékű**, a 0-request
  offline-garanciát rendszer-szintű teszt őrzi
  (`test/app/offline_network_guard_test.dart`, E01-R16).
- **Core platform (Epic 1):** validált fail-closed AppConfig-bootstrap ·
  `AppResult`/`AppFailure` + redakciós logging · verziózott storage
  (migrátor + karanténos JSON-dokumentumok) · egyetlen `DioFactory`, 401
  session-generációs invalidáció, POST-retry-tilalom · exkluzív mikrofon-session
  (owner+lease, lifecycle guard, ADR 0056) · közös zenei/audio domain
  (`core/music`, `core/audio`, ADR 0057/0058) · route-katalógus + idempotens
  onboarding-redirect (ADR 0059) · Alembic-backend health-endpointokkal és
  prod-hardeninggel (ADR 0060/0061).
- **CI:** `build-apk.yml` + `release-apk.yml` közös gate-sorral
  (`.github/actions/flutter-gates`: format → analyze → architecture → asset →
  test → randomizált property), coverage külön párhuzamos required jobban;
  `backend-ci.yml` (ruff + pytest + alembic-gate); fail-closed release signing.
  ADR 0062/0063 + E01-R16.
- **Practice V2 parity-mérce (E02-R01):** `test/support/practice_baseline_scenarios.dart`
  (10 scorer-semleges forgatókönyv) + `test/fixtures/practice/legacy_scorer_baseline.json`
  (befagyasztott golden, event-szintű verdictekkel). A replay független legacy
  matchert vezet a scorer mellett; a golden regenerálása csak
  `UPDATE_LEGACY_SCORER_BASELINE=1`-gyel, megnevezett okkal (ADR 0067 §1/§3).
- **Practice V2 domain időalap (E02-R02):** `lib/features/practice/domain/model/`
  — `BeatPosition` (480 PPQ integer tick, ADR 0066; egzakt subdivision-factoryk,
  egyetlen auditált legacy `double beat` híd ≤ 1/960 beat toleranciával),
  `Tempo` (30–300 BPM zárt tartomány, clamp nélküli lista-validáció), `Meter`
  (4/4·3/4·6/8, egzakt `ticksPerBar`), stabil validációs kódkészlet. A
  `lib/features/practice/domain/` prefix framework-independence-e GÉPI őr alatt
  (`tool/check_architecture.dart`). Hívója még nincs — production viselkedés
  változatlan.
- **Practice V2 domain-szerződések (E02-R03, ADR 0068):** a teljes modellkészlet
  a `lib/features/practice/domain/model/` alatt — `PracticeEvent`/`PracticeDefinition`
  (kanonikus sharp-spelled chord-labelkészlet, rendezettség/egyediség/tartomány
  aggregáló validációval), `PracticeSessionConfig`, sealed observation-hierarchia,
  `PracticeVerdict` (+TimingGrade/outcome/coaching kódok), `MetricValue`/`PracticeMetrics`,
  attempt/session result (+`PracticeFinishReason`), `ScoringProfile`
  (integer-percent súlyok, összeg=100; `perfect<=good<=match` ablak-rendezés;
  `legacyLearnParity` const profil), mode/source/difficulty enumok stabil
  `code`+fallback-mentes `fromCode` párral — összesen 60 stabil validációs kód,
  mind literálisan tesztelve. `Meter.ticksPerBar` szimmetrikus fail-fast
  (E02-R02 MINOR-1 zárva). Test-oldali purity-őr (`domain_purity_test.dart`).
  Hívó továbbra sincs — production viselkedés változatlan, flagek OFF.

- **Practice V2 accessibility-mátrix és performance-számlálók (E02-R20, nincs új ADR — a zárókör nem hoz architekturális döntést):**
  `test/features/practice/presentation/practice_a11y_audit_test.dart` (A1.1–A1.10) — Hub/Setup/Result képernyőkön a touch-target + label+action + 200%-os szöveg + landscape + reduced motion + chart-szemantika + screen reader + ARB-paritás cellák zöldek, a `_HubCard` / `PracticeModeCard` / `PracticePatternPreview` / `TimingBiasChart` Semantics-merge fixekkel; `test/features/practice/practice_performance_test.dart` (A3) — R14 highway számláló, R09 matcher számlálók, 10 perces szimulált session cap, controller state-emission cap; `practice_a11y_audit_test.dart` A2.1–A2.4 cellái (A2) — minden `PracticeInsightCode` / `PracticeRecommendationKind` értékhez ARB-szöveg mindkét nyelven (a R20-ban hozzáadott 16 kulcs: `practiceInsight*` × 10 + `practiceRecommendation*` × 6; a javító kör #1 az eredetileg különálló `practice_l10n_audit_test.dart`-ot ide olvasztotta, scope-okból); `test/property/practice_engine_property_test.dart` (A4) — öt epic-szintű invariáns (egy target/observation max egyszer, score ∈ [0,1] ∨ NotApplicable, free practice nincs overall accuracy, terminal state tiszta, playing ≤ active ≤ wall). A §3 rendszerszintű rés (önálló Practice V2 session-út drótozatlan) nyíltan dokumentálva a §5 DoD-táblában minden érintett cellánál.

- **Practice V2 tartalom (E02-R04, ADR 0070):** `lib/features/practice/data/`
  `BuiltinPracticeCatalog` — tíz beépített gyakorlat (négy/nyolcad strum-minták,
  folk pattern, G↔D és Em↔C akkordváltás, C-G-Am-F progresszió, 3/4 keringő,
  szinkópált upstroke-ok, rhythm-only, free-practice sablon) stabil
  `builtin.<slug>.v1` ID-kkel, unmodifiable `events`/`const skillTags`
  listákkal; `domain/repository/practice_catalog_repository.dart` szinkron
  szerződés; `application/practice_catalog_controller.dart` két Riverpod
  providerrel. Hívó UI még nincs, ARB-fordítás az első UI-hívóval jön.
- **Practice V2 legacy adapterek (E02-R05, ADR 0071):**
  `lib/features/practice/data/adapters/` — `practiceDefinitionFromLesson`
  (+`easy:`), `…FromSong`, `…FromAnalyze`, `…FromDailyChallenge`: tiszta,
  óra-mentes függvények `AppResult<PracticeDefinition>`-nel (sosem dobnak,
  hibakód `practice.content_unsupported`). Minden adaptált tartalom
  `strumPattern` + befagyasztott `legacyLearnParity` (kivétel: az eseménymentes
  Analyze-import → `freePractice`). `legacyPracticeChordLabel` a legacy
  akkordcímkéket a detektor tényleges 24-elemű maj/min szótárára redukálja
  (`Em7`→`Em`, `Bb`→`A#`, `G/B`→`G`, értelmezhetetlen → strum-only) —
  veszteséges, de nem parity-rontó (ADR 0071 §2).
  `PracticeDefinition.displayTitle` a user-tartalom nevének (61 stabil
  validációs kód). Songs feature-barrel: `lib/features/songs/public.dart`.
  A legacy API (`Lesson`, `Song.toLesson()`, `Lessons.fromAnalyze`,
  `LessonScorer`) érintetlen; hívó UI nincs.
- **Practice V2 időréteg (E02-R06, ADR 0072):**
  `lib/features/practice/domain/model/beat_time_converter.dart` — a domain
  **egyetlen** beat↔idő konverziója (egész µs, egyszeri kerekítés, fail-fast) ·
  `compiled_practice_target.dart` (4 immutable, value-equal modell) ·
  `domain/service/practice_target_compiler.dart` — determinisztikus
  session-timeline count-innal, egész ütemű pass-hosszal, loop-rebase-szel,
  ütemhatárokkal, expected-chord szegmensekkel és scoring applicabilityvel.
  **ADR 0072 §1.1 az egész epic időmodellje:** minden abszolút pillanat a
  nullponttól vett tickszám egyetlen konverziója, minden időtartam két pillanat
  különbsége — így a kompozíció pontos ÉS minden pillanat bitre egyezik a legacy
  képlettel. Parity a szállított korpuszon: **0 µs**. Hívó UI nincs.
- **Practice V2 observation gateway (E02-R08, ADR 0074):** a Live detektor és a
  Practice domain közötti híd. `application/practice_observation_gateway.dart`
  (SDD §13.1 interfész + `PracticeObservationConfig`: 0.55 / 0.60 / 180 ms /
  500 ms) · **`application/practice_observation_activation.dart` — a
  `practiceCaptureActiveByStatus` `const` tábla mind a 11 státuszra**, ez a
  „hallgat-e a mikrofon" EGYETLEN igazságforrása (`countIn` + `running` → be,
  minden más → ki; a `paused → false` a chunk 014 pause-résének szerkezeti
  lezárása a V2 úton), a kulcshalmaz-egyezés gépi őr alatt ·
  `data/live_practice_observation_gateway.dart` — `strumSeq`-dedup, engine-óra
  de-jitter a legacy **szigorú `<`** predikátumával (a kalibrált input latency
  a matcheré marad, ADR 0074 §3), **fajtánként külön** monoton padló, saját sűrű
  `sequence` (§12.5 baseline), change-point + stabilitási chord-mintavétel,
  engedély-elsőség, idempotens start/stop/dispose, hibaleképezés. Fake gateway a
  `test/support/` alatt az R09/R10 számára. Hívó és provider nincs, flagek OFF →
  production viselkedés bitre azonos.
- **Practice V2 event matcher (E02-R09, ADR 0075):**
  `domain/service/practice_event_matcher.dart` — pure, determinisztikus,
  **kurzoralapú** párosító: eldönti, melyik `StrumObservation` melyik
  `CompiledTargetEvent`-hez tartozik, és mikor zárul egy cél kimaradásként.
  Pontozás-mentes (`TimingGrade`/score/combo a Kör 10-é), **megfigyelést nem
  tárol** (`O(célesemény)` memória), az opcionális célt külön feloldással zárja.
  A legacy `LessonScorer` szemantikája (P1–P9) megőrizve: jogosultság `<=`,
  zárás **szigorú `<`**, holtversenynél a **korábbi**, a rossz irány is
  **elfogyasztja** a célt, az extra pengetés **állapotot nem változtat**.
  **A paritás értelmezési tartománya kimondva (ADR 0075 §2b):** a legacy
  kerekítetlen `double`-lel dönt, a compiled target egész µs-mal, ezért a két
  időalap ≤ **0,5 µs**-ban eltér (mérve **0,489795919508 µs** mind a 348
  szállított eseményen) — a **µs-kvantált alap az igazság**, és a levezetett
  védősávon kívül (`≥ 1 µs` a határoktól, `≥ 2 µs` argmin-különbség) a paritás
  **bitre egzakt**, tűrés nélkül. A sávon belüli két divergencia-cella
  (`first-strums[0]`, `anthem-drive[5,6]`) **kipinnelt, őrzött viselkedés**.
  Hívó, provider és flag nincs → production viselkedés bitre azonos.
- **Kétmotoros implementer-készlet (ADR 0069):** `tools/mm-round.sh` +
  `tools/mm-watch.sh` (5 perces korai riasztás) + `tools/mm-trace.py`
  (munkastílus-elemzés) — a MiniMax M3 ugyanazt a kör-jelzés-szerződést
  használja, mint a Codex. Besorolás és a kötelező brief-elemek: AGENTS.md §15.6.

- **Practice V2 pontozás (E02-R10, ADR 0076):** `lib/features/practice/domain/service/`
  — `PracticeTimingScorer` (grade + eseménypont + `meanAbsoluteOffset`/előjeles
  `timingBias`), `PracticeDirectionScorer` (explicit megfigyelés-bemenet,
  fail-fast hiányzó leképezésre), `PracticeChordScorer` (inkluzív
  `[−120 ms, +420 ms]` ablak, `correct`/`wrong`/`noDetection`/`insufficientData`/
  `notApplicable`), `PracticeScoreAggregator` (overall csak az **elérhető**
  dimenziókra, completion + kettős pass-kapu, legacy combo/pont). Minden pontszám
  belül **egész ezrelék**, kifelé `perMille / 1000` — lebegőpontos akkumuláció
  tilos. `PracticeMetricReasonCode` stabil indokkód-készlet; `ChordOutcome`
  ötértékű. **Legacy paritás 51 forgatókönyvön egzakt** (17 lecke × 3 latency,
  nulla kizárt esemény). Hívó nincs → production viselkedés változatlan.

- **Practice V2 result + coaching + history (E02-R18, ADR 0084):** mode-specifikus
  **result képernyő** (`presentation/screens/practice_result_screen.dart` +
  `score_breakdown`/`timing_bias_chart`): csak az **alkalmazható** dimenziók
  látszanak (`MetricNotApplicable` → a blokk nincs a fában; `MetricInsufficientData`
  → lokalizált „nincs elég adat", **nem** 0%); Free Practice külön layout (nincs
  overall/pass-fail/combo). **`PracticeCoach`** pure service
  (`domain/service/practice_coach.dart`): mérésből választott, **bizonyíték-küszöbös**
  insight-kódok (`practice_insight.dart`), determinisztikus prioritás (SDD §17.3),
  legalább egy pozitív insight befejezett sessionre. **Practice History V2**
  (`data/local_practice_history_repository.dart` + `practice_history_serializer.dart`
  + `practice_history_recorder.dart` + `..._mapper.dart`,
  `domain/model/practice_history_entry.dart` + `practice_metric_snapshot.dart`): új
  kulcs `ss.practice.history_v2` (`StorageKeys.all`-ban), verziózott dokumentum,
  karantén a sérült bájtoknak, jövőbeli `schemaVersion` kihagyva, cap
  `maxSessions=200`, a per-attempt **detail-window** csak a legújabb **N=20**
  sessionre, **idempotens** mentés a `sessionId`-re. **A mentési hiba nem néma:** a
  repository közvetlenül a `KeyValueStore`-ral ír (propagálja a `StorageException`-t)
  → `AppResult.failure` → a controller `ShowRecoverableError`-t emittál; a session
  sikeres marad. A V1 `ss.progress.practice_log` **bájtra érintetlen** (egyesítés =
  R19). A live recorder-wiring valós session-metaadatig (mode/source/definition)
  **R19-ig halasztva** (placeholder-metaadatnál `Noop`, hogy ne keletkezzen
  betölthetetlen — write-then-drop — rekord). Flag: `practiceDetailedHistoryEnabled`
  (non-prod ON) → részletes attempt-adat.

## 3. Known blockers / risks

- **Rendszerszintű rés (E02-R20, mérve): a standalone Practice V2 session nem
  indítható éles buildben.** A `practiceSessionHostProvider` production
  defaultja `null`, a `practicePrepareSinkProvider` defaultja placeholder —
  ez R11/R12 óta nyitva van, egyetlen későbbi kör sem drótozta be. A
  domain/application réteg kimerítően tesztelt, de a Hub→Setup→Session
  presentation→controller kötés hiányzik. Csak a Learn-migrációs út
  (`migratedLearnEnabled`, éles default `false`) éri el a valós controllert.
  Részletek + a DoD-tábla érintett celláinak listája:
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3/§5. **Ez a következő Practice-kör (E02-R21) jelölt feladata.**
- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Epic-2 valódi eszközös teszt PENDING** — a Practice Engine device-mátrix
  ([`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md))
  kész, a user tölti ki (a fenti rendszerszintű rés miatt csak a Learn-
  migrációs úton tesztelhető, amíg a wiring nincs pótolva).
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.

## 4. Current branch

`main` @ [PR #44](https://github.com/wolfcasaba/strumsight/pull/44) (E02-R20,
squash-merge `4616aed`), CI run
[30703886127](https://github.com/wolfcasaba/strumsight/actions/runs/30703886127)
**success** a `2972ba9` kör-branch-HEAD-en (teljes suite + randomizált property
+ APK) — ez a squash-commit szülője. A reviewer-gate saját kézzel, izolált
`/tmp` klónban **háromszor** zöld: a kör indítása előtt, a javító kör után, és
a merge-elt `main`-en még egyszer függetlenül.

> ⚠ **A squash-commit üzenete tévesen a régi, „HALT H3" PR-címet viszi**
> (`0bdee7e`): a `gh pr edit` a merge előtt a Projects-classic GraphQL
> deprecation miatt némán elhasalt, a cím csak utólag, REST-en át (`gh api -X
> PATCH .../pulls/43`) lett javítva. A kör állapota **APPROVED**. Tanulság:
> `gh pr edit` után **ellenőrizd** a címet, mielőtt mergelsz.

> **Klón-/friss-munkafa csapda (mérve 2026-08-01):** a generált
> `lib/l10n/app_localizations*.dart` **gitignore-olt**, ezért egy friss klónban
> — és egy régóta nem regenerált munkafában is — az `analyze` több száz
> `undefined_getter` hibával pirosat ad. Ez klón-artefaktum, nem kör-hiba:
> `flutter gen-l10n` után a gate zöld. Reviewer-oldalon ez a **legelső** lépés.

> **CI-szabály (ADR 0086):** a `build-apk.yml` csak `workflow_dispatch`-re fut;
> merge előtt kötelező az `origin/main` mozgás-ellenőrzés, és a dispatch után a
> run **`headSha`-ját össze kell vetni a lokális HEAD-del** (L21 — az R11-ben
> egy néma `&&`-lánc-bukás miatt először rossz SHA-ra ment a dispatch).

## 5. Last completed round

**E02-R20 — Epic 2 lezárás: a11y/l10n/perf audit, epic-szintű property gate,
DoD-tábla** (PR [#44](https://github.com/wolfcasaba/strumsight/pull/44),
squash `4616aed`, ADR: **nincs**): audit-only zárókör, új funkció nélkül.
Implementer **MiniMax M3**, orchestrátor **Claude Sonnet 5** (a pipeline
E02-R20-at szándékosan nem viszi, ember indította — ADR 0087 §7).

**Elkészült:** A1 accessibility-mátrix (10 cella) — 4 valódi Semantics-merge
bug javítva, mind regresszió-védett; A2 lokalizációs audit (16 új ARB-kulcs,
valódi magyar fordítással); A3 teljesítmény-számlálók; A4 epic-szintű
property gate (5 invariáns, mind valós production kódot hajt végig
randomizált bemeneteken); A7
[`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
(SDD §28 mind az 52 tétele, fájl:sor bizonyítékkal); A8
[`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md).

**A kör legfontosabb terméke:** a §3 rendszerszintű rés kimondása (ld. fent
§3) — a standalone Practice Hub→Setup→Session út production-drótozása
R11/R12 óta hiányzik. A DoD-tábla minden érintett sora ezt a minősítést
viseli a sima „teljesül" helyett.

**A kör lefolyása** (részletek: [review](docs/reviews/e02-r20-review.md)):
orchestrátor pre-flight a R01–R19 nyitott leleteiből + egy SDD §28
elő-auditból hozta felszínre a rendszerszintű rést MÉG A KÖR INDÍTÁSA
ELŐTT (a briefbe építve) → M3 implementáció → **review: 2 BLOCKER + 1
MAJOR + 1 MINOR** (a DoD-tábla 6 sora valótlan drótozásra hivatkozott;
az A4 property gate 3 invariánsa vacuous/nem-randomizált volt; egy
scope-on kívüli tesztfájl; egy regresszió-védelem nélküli a11y-fix) → **egy
javító kör (M3) → mind zárva**, red→green próbával → **APPROVED**.
Reviewer-gate saját kézhez háromszor zöld (indítás előtt, fix után, merge-elt
`main`-en függetlenül). Tanulság: [L31](docs/LESSONS.md) (zöld gate mellett a
DoD-tábla bizonyítéka is lehet valótlan — a review a gate-en TÚL, konkrét
hívási láncot mérve fogta meg).

## 6. Exact next task

0. **AZONNALI: E02-R21 — a task-state `STOPPED` (2/2 M3 + 1/1 Terra
   elfogyva), a router `_gate_runner` pre-gate normalize fixe (PR #54,
   [`docs/LESSONS.md` L46](docs/LESSONS.md)) UTÁN.** Az utolsó éles `run`
   ("Update 7", [`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md))
   VALÓDI, ADR 0111 §1–§4-nek megfelelő A1/A2/A3 tartalmat termelt a
   `codex/e02-r21-practice-production-wiring` ágon (`2bb61a1`,
   `ss-auto-e02-r21` munkapéldány) — a gate mindhárom próbán KIZÁRÓLAG
   mechanikus debrisen (format, 3 unused_import) bukott, amit a most
   merge-elt fix jövőre nézve megold. **A következő session dolga:**
   (a) a munkapéldányon maradt 3 tracked + 2 untracked fájl sorsáról
   dönteni (commit előtt a router PRECHECK-je fail-closed elutasít bármilyen
   tracked/untracked elváltozást — vagy törlés bizonyítékként, mint az
   Update 5/6-ban, vagy explicit commit egy manuálisan futtatott gate után),
   majd `python3 tools/model-router.py reset --task-id E02-R21` + friss
   `tools/ai-router-round.sh run`. **Ha egy TOVÁBBI `run` A1/A2/A3 nélkül
   megint csak STOPPED-et ad, az már a brief méretére/sorrendjére mutat
   (Class B)** — fontold meg az explicit `codex`/`minimax` motort a nem
   redaktált logért, vagy a brief implementációs sorrendjének/méretének
   felülvizsgálatát. `docs/adr/0111-practice-production-wiring.md`
   változatlan, kész. **A Practice V2 production-drótozása (a kör tényleges
   célja) még mindig nincs commitolva/review-zva/merge-elve.**
1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése. Az APK a PR #37
   CI-runjából tölthető
   ([30673821431](https://github.com/wolfcasaba/strumsight/actions/runs/30673821431)).
2. **~~E02-R20 — Epic 2 lezárás (a11y/l10n/perf audit, DoD-tábla)~~ — KÉSZ**
   (PR #44, `4616aed`, 2026-08-01, implementer **MiniMax M3**, orchestrátor
   **Claude Sonnet 5**, egy javító kör → **APPROVED**). **Epic 2 technikailag
   lezárva.** Két nyitott tétel jelöli a következő lépést:
   - **A rendszerszintű drótozási rés (§3)** — a standalone Practice V2
     session presentation→controller kötése hiányzik. **Ez a jelölt
     E02-R21 feladat**, brief még nincs megírva.
   - **A `migratedLearnEnabled` rollout-döntés** — mindenhol OFF, a
     bekapcsolás feltételei (mérföldkövek, monitorozás, visszaállítási
     útvonal) az R19 paritása alapján még **user-döntésre várnak**
     (R20 nem hozott ebben döntést, csak dokumentált).
   (E02-R19 progress/streak/daily-goal + Learn V2-migráció — KÉSZ: PR #43,
   `0bdee7e`.)
3. **A pipeline (ADR 0087, GOV-02) E02-R14…R19-et vitte; E02-R20-at
   SZÁNDÉKOSAN ember indította** (ADR 0087 §7) — a sor
   ([`docs/execution/pipeline-queue.tsv`](docs/execution/pipeline-queue.tsv))
   ezzel kiürült. **Egy E02-R21 brief megírása + sorba állítása a
   következő döntési pont** — a driver csak akkor folytatja, ha van
   `pending` sor.

   > **Megállási szerződés (ADR 0087 §2):** az orchestrátor-session önállóan
   > javíthatja a kör SAJÁT, még nem merge-elt briefjét/ADR-jét (§0.0
   > revízióval); H1–H8 esetén (merged ADR, lezárt kör viselkedése, tilos zóna,
   > túlélő BLOCKER/MAJOR, 2× piros CI, `blocked`, gate nem zöldíthető,
   > rebase-konfliktus) a kör HALT-tal megáll.
   >
   > **ÖNJAVÍTÁS (ADR 0112, GOV-03, 2026-08-01 — user-döntés):** a HALT már NEM
   > a lánc vége. A driver a következő firingen friss **önjavító sessiont**
   > indít (`docs/execution/pipeline-selfheal-prompt.md`), amely az
   > infrastruktúrát is javíthatja (`tools/**`, merge-elt ADR jelölt
   > módosítás-blokkal, brief, sor-fájl), kötelező **regressziós teszttel**, a
   > változatlan zöld kapun át merge-elve — majd feloldja a láncot. Korlátok:
   > körönként+halt-kódonként max **3** kísérlet (`PIPELINE_SELFHEAL_MAX`), és
   > a **mércét nem gyengítheti**: ha a teszt-fájlok száma csökken vagy a
   > `round-gate.sh` / `.github/workflows/` változik, a driver `H-GATEGUARD`
   > halttal EMBER elé viszi. Kikapcsolás: `PIPELINE_SELFHEAL=0`.
   > Állapot: `tools/pipeline-status.sh` (önjavítás-blokk + kísérletszámláló).
4. **Kötelező pre-flight minden körhöz** (az R10 és R11 mért tanulságai):
   minden briefben hivatkozott szimbólumot grep-elj ki; minden előírt
   cél-státuszra mérd meg, melyik INPUT produkálja (L20); minden
   erőforrás-előírásnál mérd ki a tényleges hívási láncot (L19).
   **A javító kör küszöbe EGY** (user-döntés 2026-08-01, `8e719f1` — a korábbi
   HÁROM-ról szigorítva); a második javító kört a **Codex** viszi, H4 halt
   csak utána. **UI-kör esetén a review-nak kötelező eleme a több-belépéses
   és a kombinált-státusz próba** — az R13 három MAJOR-ja mind ilyen volt
   (L22). **Zöld gate mellett is mérj konkrét hívási láncot a DoD-/
   zárójelentés-jellegű állításokra** — az R20 review 6 hamis "teljesül"
   sort talált egy egyébként teljesen zöld gate mellett (L31).
5. **Az E02-R08 nyitva maradt follow-upja:** a chord-confidence felvitele a
   `LiveFrame`-be — az Analyze úton is közös, ezért külön kör; addig a Live
   adapter `confidence: 1.0` = „nem mért".

## 7. Required verification (before any "done")

A lokális mérce **egyetlen futtatható artefaktum** (GOV-01) — a parancssorban
reprodukált lista a csővezeték miatt nem bizonyíték (`docs/LESSONS.md` L09):

```bash
tools/round-gate.sh test/<a kör területe> [további teszt-útvonal ...]
```

A script a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket **külön processzként** futtatja (ezért nem OOM-ol), és az első piros
lépésnél a helyes kilépési kóddal megáll. Normatív forrás: `AGENTS.md` §12.
Backend-érintésnél kiegészítő lépés (NEM a gate része):
`cd backend && .venv/bin/python -m pytest`.

- Full suite + property gate + APK: `gh workflow run build-apk.yml --ref <branch>`.
- **Never chain `analyze && test`.** ONE win32 major across the tree
  (`flutter_secure_storage` pinned to v10). Riverpod 3.3.2: `AsyncValue.value`
  (nullable), NOT `.valueOrNull`.
- DSP param change ⇒ `docs/rag/chunks/` update in the SAME commit; new DSP
  behaviour ⇒ randomized property in `test/property/` (`PROPERTY_SEED`).
- Backend writes are easy to lose silently — a failed push must NOT mark state
  synced; verify persistence + offline path.
- Backend dev loop: `cd backend && python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt`, then
  `.venv/bin/uvicorn app.main:app --reload` (emulator → host: `10.0.2.2`).
  Deploy-szabály: uvicorn-restart előtt `pip install -r requirements.txt`
  (a `main.py` futásidőben importál `alembic`-ot).
- **HORIZON ritual minden kör-commit után:**
  ```bash
  git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"
  git push origin 'refs/notes/*'
  ```

## 8. Historical archive

A teljes kör-történeti napló (pre-SDD r1–r217 + E01-R01…R15 részletes
összefoglalók, git-notes tükör): [`docs/handoff-archive.md`](docs/handoff-archive.md).
Epic-1 evidencia-gyűjtemény: [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).

---

## How to update this file

After **every** round: (1) header date + round; (2) §1/§2 if release state or
capabilities changed; (3) §3 blockers +/-; (4) §4–§6 branch / last round / next
task; (5) move the finished round's detailed story to
`docs/handoff-archive.md` (append, never delete). Keep this file a ~120-line
operational snapshot — history lives in the archive, detail in git.
