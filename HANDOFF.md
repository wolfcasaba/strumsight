# HANDOFF — StrumSight 🎸

## ✅ E09-R08 KÉSZ — Block, mute és safety kapcsolatkezelés — PR [#417](https://github.com/wolfcasaba/strumsight/pull/417), squash `5e086c10` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) NYOLCADIK KÖRE KÉSZ.** [ADR 0402](docs/adr/0402-block-mute-and-safety-relationships.md):
`community_blocks`/`community_mutes` tábla + `block_service.py` atomikus
tranzakció (mindkét irányú follow-él DELETE, pending follow-request UPDATE
`status="blocked"` — a Kör 7 `follow_service.py` MÉRT UPDATE-recycle
mintáját követve, NEM DELETE-elve a requestet). Élő block-first szűrés
(`is_blocked_pair`) a MA authentikált `get_followers`/`get_following`
endpointokba kötve (a Kör 4 `CommunityAccessPolicy` ELSŐ élő bekötése) —
caller↔owner block → 403 a lap materializálása ELŐTT, egyébként a
hívóval blokk-kapcsolatban álló profilok kimaradnak a lapból. ÚJ
`routers/safety.py` HTTP-felület (block/unblock/mute/unmute +
blocked/muted lista). Flutter: a Kör 7 kódjában MÁR "Kör 8 scope"-ként
megnevezett `SocialGraphRepository.block/unblock/mute/unmute`
`UnsupportedError` stub négyes valódi implementációra váltva; a domain
interfész két ÚJ metódussal bővült (`blockedProfilesPage`/
`mutedProfilesPage`, a meglévő 11 metódus változatlan); ÚJ
`safety_relationships_screen.dart` (Blocked/Muted lista, saját
képernyő-kolokált Riverpod state, teljes en/hu lokalizáció).

Előre kiosztott ADR (`0401`) a queue-fájlban STALE volt (a Kör 7 már
foglalta) — friss szám (`0402`) a `round-slots.py reserve-adr`-ból. A
pre-flight (§0.0, D1–D6) jelentős, mért revíziót hordoz: az eredeti
`allowed_paths` NEM tartalmazta a router-fájlokat, amikbe a block-szűrést
be kellett kötni, sem a Dart repository-implementációt — mindkettőt a
saját elődje (Kör 7) már explicit "Kör 8 scope"-ként nevezte meg a
shipped kódjában, csak a batch-elt brief ezt tévesen kihagyta. A
challenge-invite tábla (Kör 21) és a klub-domain (Kör 24) még nem
léteznek — a brief "pending challenge invite törlése"/"közös klub
placeholder" cellái ennek megfelelően pontosítva (D3/D4).

Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. **1 javító
kör** (`docs/reviews/e09-r08-review.md`): F1 MAJOR — a safety screen 0
lokalizált stringgel indult (minden testvér Community screen
`AppLocalizations`-t használ) → 11 kulcs `community_{en,hu}.arb`-hoz +
aggregátum-újragenerálás; F2 MAJOR — `block()`/`mute()` nem kapta el a
konkurrens `IntegrityError`-t (ellentétben a `follow_service.py` MÉRT
mintájával), és a saját concurrency-tesztje NÉMÁN nyelte el a szál-kivételt
assert nélkül (`docs/LESSONS.md` L349–L351 mintája) → mindkettő javítva,
függetlenül újra-igazolva friss izolált klónban. **1 CI-only fix**
(`test/ui/ui_inventory_test.dart` screen-számláló 67→68 — UGYANAZ a
drift-osztály, ami a Kör 7-nél is egy 3. javító kört igényelt). Dedikált
`security-reviewer` pass: PASS, nincs BLOCKER (2 MINOR/NOTE — block-létezés
oracle 403 vs 404 között, non-blocking follow-up). Review APPROVED, 0
nyitott BLOCKER/MAJOR. Exact `63890947`: `full-gate.yml` 32608627590 +
`router-ci.yml` 32608635566 mindkettő success.

**Mért folyamat-tanulság (a saját sessionöm hibái, nem az implementeré):**
a `tools/mm-round.sh` NEM push-ol automatikusan — az orchesztrátornak
minden implementer-/javító-forduló UTÁN saját kézzel kell push-olnia a
munkapéldányból, MIELŐTT a shared tree-n bármit commitolna a branchre;
elmulasztva ez egy forkolt, divergens branch-históriát okoz (mérve,
`cherry-pick` + `safe-force-push.sh`-sal helyreállítva, 2×). Az implementer
saját gate-önbevallása HÁROMSZOR jelzett `gate_shape=VIOLATION`-t (a
`round-gate.sh` `| tail`/`&&` mögé rejtve, a promptban explicit tiltás
ELLENÉRE) — mindhárom esetben a review saját kézzel, izolált `/tmp`
klónban futtatta újra csonkolatlanul, és ténylegesen zöld volt (a
csonkolás önmagában nem jelentett rejtett hibát ebben a körben, de a
bemondást egyszer sem fogadtam el enélkül).

## ✅ E09-R07 KÉSZ — Follow és follow request social graph — PR [#416](https://github.com/wolfcasaba/strumsight/pull/416), squash `1cc49e41` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HETEDIK KÖRE KÉSZ.** [ADR 0401](docs/adr/0401-follow-and-follow-request-social-graph.md):
idempotens, privacy-kompatibilis follow rendszer — public profilnál azonnali
follow, private profilnál explicit `requested → accepted | declined |
cancelled` request lifecycle. `community_follows`/`community_follow_requests`
migráció DB-szintű self-follow `CHECK` és race-biztos `UNIQUE` mindkét
táblán; `follow_service.py` (public/private lifecycle, `IntegrityError`→
domain-kivétel fordítás, állapot-átmenet-alapú idempotencia); `social_graph.py`
router (follow/accept/decline/unfollow/follower-removal/cursor pagination).
Flutter: `relationship_repository_impl.dart` a MEGLÉVŐ (Kör 5, ADR 0399)
`SocialGraphRepository` interfészt implementálja — `block`/`unblock`/`mute`/
`unmute` `UnsupportedError`-t dob (Kör 8 előfeltétele, a Kör 6/ADR 0400
precedens szerint, NEM csendes no-op); `relationship_controller.dart`
optimistic (public) / pending (private) állapotgép; `followers_screen.dart`;
`api_client.dart` egyetlen ÚJ `delete()` metódussal bővült (a `post()` pontos
tükre, a meglévő négy metódus érintetlen).

**Pre-flight mérve öt pontot revideált** (`docs/rounds/e09-r07-follow-and-follow-request-graph.md`
§0.0, [ADR 0401](docs/adr/0401-follow-and-follow-request-social-graph.md)):
(1) az előre kiosztott `ADR 0400` MÁR foglalt volt (E09-R06 saját ADR-je) —
`tools/round-slots.py reserve-adr` friss `0401`-et adott; (2) a Flutter
domain-interfész a MEGLÉVŐ `SocialGraphRepository` (Kör 5), NEM egy új
`RelationshipRepository`; (3) nincs külön "cancel" domain-metódus/endpoint —
a meglévő `unfollow()`/`DELETE .../follow` egyik ága fedi (a domain `**`
NULLA diffet kapott); (4) `lib/core/network/api_client.dart`-nak nem volt
DELETE-metódusa — szűken bekerült az `allowed_paths`-ra egyetlen additív
`delete()`-re; (5) `backend/app/community/__init__.py::build_community_router()`
NEM bővült — a Kör 3 (`handles.py`) precedens szerint a router tesztje önálló,
helyi `FastAPI()`/`TestClient` fixture-t épít.

**Review (`docs/reviews/e09-r07-review.md`): APPROVED, KÉT javító kör
után.** Az első review (Claude + dedikált `security-reviewer` agent, risk=high)
1 BLOCKER + 2 MAJOR + 1 MINOR + 1 NOTE-ot talált: **F1 BLOCKER** — a §6.1
kötelező valódi-sértés próba (`test_swap_unique_constraint_breaks_a2`) NEM
determinisztikus volt (10 ismételt futtatásból 7 PIROS, a két
`threading.Thread` között nem volt szinkronizációs bariér); **F2 MAJOR** —
`get_followers`/`get_following` teljesen hitelesítetlen volt (nincs
`current_user` függőség, szemben a router MINDEN mutáló endpointjével) —
ma latens (a router nincs mountolva), de éles IDOR/enumerációs kockázat lenne
mountoláskor; **F3 MAJOR** — a Dart `unfollow()`/`removeFollower()` sosem
küldte a backend által KÖVETELT `idempotency_key` query-paramétert (minden
éles hívás 422-t kapott volna — egyik teszt sem fogta meg, mert egyik oldal
sem gyakorolta a VALÓDI Dart→backend HTTP-szerződést); **F4 MINOR** —
`post_follow` nem kapta el a `FollowAlreadyExists`-t → nyers 500.
A javító kör 1 (`222a6782`) mind az ötöt zárta — az F1 fix a `threading.
Barrier`-t NEM a szál-indítás elé, hanem a `follow_service._existing_follow`
helperbe monkey-patchelte (a pontos SQL-döntési pontnál szinkronizál) —
FÜGGETLEN 15×-ös reprodukció a reviewer oldalán: 15/15 zöld (szemben a
fix előtti 7/10 PIROS-sal).

A friss exact-SHA CI (`full-gate.yml`) a TELJES suite-tal PIROS lett — nem a
kör tartalma miatt, hanem egy MEGLÉVŐ, körön kívüli gate-teszt
(`test/ui/ui_inventory_test.dart:14`, kemény kódolt production-screen-szám)
avult el a kör saját ÚJ `followers_screen.dart` fájla miatt (66→67, azonos
minta mint az E09-R06 F9 lelet). Javító kör 2 (`7f2e348d`, `allowed_paths`
szűken bővítve a brief §0.0.9-ben) egy sorban javította.

Scope-audit mindhárom fordulóban OK. Minden gate-futtatás FÜGGETLENÜL,
izolált `/tmp` klónokban: format/analyze/architecture/secrets/l10n/backend
ruff/backend pytest (teljes suite) mind zöld. CI a pontos merge SHA-n
(`f75f0007`): `full-gate.yml` 32603023648 + `router-ci.yml` 32603026921
mindkettő `success`.

**Nyitva maradt, EMBERI döntést NEM igénylő tartozás:** az E09-R08 queue-sora
(`docs/execution/pipeline-queue.tsv`) `0401`-et ad előre kiosztott ADR-ként —
ez a szám MOST már foglalt (ez a kör). Az E09-R08 pre-flightja a §1.0.1
szerint `tools/round-slots.py reserve-adr`-rel ÚJ számot kér, ne a queue-fájl
stale értékét használja — pontosan ugyanaz a minta, amit ez a kör is örökölt
az E09-R06-tól.

## ✅ E09-R06 KÉSZ — Profil létrehozás, szerkesztés és Community gate UI — PR [#415](https://github.com/wolfcasaba/strumsight/pull/415), squash `77bc0589` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HATODIK KÖRE KÉSZ.** ADR 0400: a Community
gate (disabled/logged-out/profile-missing/ready), a profil létrehozó/
szerkesztő flow és — a pre-flightban felfedezett, ADR 0396-ban MÁR ennek
a körnek kiosztott felelősség pótlásaként — a backend SERVICE-SZINTŰ
profil-létrehozás (`POST`/`PUT /community/profiles/me`, `CurrentUser`/
`DbSession` auth-lánc). A batch-elt brief (PR #405) tévesen a teljes
`backend/**`-et tilos zónának jelölte és hamisan állította, hogy a kör
"az ELSŐ, ami ténylegesen HTTP-n keresztül hívja" a Kör 3/4 policy-kat —
mérve: `grep -rn "INSERT INTO community_profiles" backend/` nulla
találat, egyetlen backend endpoint sem hozott létre profilsort. A
pre-flight (§0.0, ADR 0400) szűken, öt névvel megadott fájlra nyitotta
ki a tilos zónát; a `main.py`/`community/__init__.py` router-mounting és
bármilyen új migráció VÁLTOZATLANUL tilos zóna marad — külön, még ki nem
osztott kör dolga (`docs/reviews/e09-r04-review.md` F1/N2-vel együtt).

**Review (`docs/reviews/e09-r06-review.md`): APPROVED, KÉT javító kör
után.** Az első review 1 BLOCKER + 1 MAJOR leletet talált: F1 — a
`fetchMyProfile()` egy nem-létező `GET /community/profiles/me` végpontot
hívott (a gate `ready` állapota élesben sosem lett volna elérhető); F2 —
a `handle_policy.validate()` NFKC-normalizált visszatérési értéke
eldobva, Unicode-ekvivalens handle-ök (pl. fullwidth karakterek)
ütköztek volna — egy dedikált `security-reviewer` agent FÜGGETLENÜL
megerősítette, élesebb impersonation-szöggel. A javító kör 1 (`9592638e`)
mindkettőt fixálta, tesztekkel (a security-reviewer pontos fullwidth/
ASCII forgatókönyvét reprodukálva). Az ELSŐ exact-SHA CI-dispatch
(`full-gate.yml`) ekkor PIROS lett — a TELJES suite (nem a célzott gate)
2 ÚJ MAJOR leletet fedett fel: F9 (`ui_inventory_test.dart` elavult
screen-számláló, 64→66, a kör 2 új production screent ad) és F10
(`dio_factory_guard_test.dart` regex-alapú Dio-őr false positive egy
doc-kommenten, "Dio ("-mintára illeszkedve). A javító kör 2 (`ddbd4e9e`)
mindkettőt fixálta, egysoros javításokkal.

Scope-audit háromszor jelzett VIOLATION-t a kör során — mindhárom
alkalommal kis, additív, tartalmilag helyes fájlt, amit az orchesztrátor
§0.0.x brief-revíziókkal legitimált (nem mást implementáltatott):
`lib/core/foundation/app_failure.dart` (a projekt MEGLÉVŐ per-feature
`FailureCode` mintája), `lib/l10n/app_{en,hu}.arb` (az ARB-aggregátum
tartalmilag friss, `dart run tool/gen_l10n_segments.dart --check`
igazolta — csak a generátor helyett kézzel lett átmásolva),
`test/ui/ui_inventory_test.dart` (F9 fent). A `bio`/`skillInterests`/
`badges`/`avatarUrl` mezők ebben a körben UI-only maradnak (nincs
backend oszlop, nincs migráció) — egy jövőbeli migráció-hozó kör
előfeltétele.

Minden gate-futtatás FÜGGETLENÜL, izolált `/tmp` klónokban (mindkét
javító kör után újra): scope-audit OK, format/analyze/architecture/
secrets/l10n/backend ruff/backend pytest (349 teszt) mind zöld. A KÉT
kötelező valódi-sértés próba (Flutter A5 dupla-submit debounce, backend
A8 `commit_with_uniqueness_check` try/except) PIROS→ZÖLD dokumentálva. CI
a pontos merge SHA-n (`bf2f67da`): `full-gate.yml` 32596780267 +
`router-ci.yml` 32597616787 (manuálisan `workflow_dispatch`-csel pontos
SHA-ra kényszerítve) mindkettő `success`.

**Nyitva maradt, EMBERI döntést NEM igénylő tartozások:** F3/F4 (A6
logout-cache és A7 2.0 text-scale golden teszt hiányzik, a kód-szint
helyes, csak tesztekkel nincs bizonyítva); F6 (`deps.py`
`HTTPBearer(auto_error=True)` hiányzó auth-fejlécre 403-at ad 401 helyett
— projektszintű minta, `deps.py` tilos zóna volt ezen a körön); a
router-mounting kör (F1 review-eredetije, ADR 0396 "Következmények" +
E09-R04 F1/N2) továbbra is elkülönült, még ki nem osztott feladat.
**MÉRT ADR-ütközés a queue-ban:** `docs/execution/pipeline-queue.tsv`
E09-R07 sora `0400`-at ad előre kiosztott ADR-ként (a batch-elt PR #405
tervéből) — ez a szám MÁR foglalt (ADR 0400, ez a kör). Az E09-R07
pre-flightja a §1.0.1 szerint `tools/round-slots.py reserve-adr`-rel ÚJ
számot kér, ne a queue-fájl stale értékét használja.

## 🧭 [GOV] Motorváltás: Claude Sonnet 5 (high) orchestrátor + MiniMax M3 implementer (2026-08-21)

**User-döntés: „lejárt a GPT kvóta — állítsuk át a fejlesztést sonett 5 High
orchestrátor és minimax implementer felállásra."** A ChatGPT Pro keret
elfogyott, tehát a Codex-oldal (a **Sol** ÉS a **Terra** — közös
`~/.codex-terra` auth) NEM futtatható. A 2026-08-20-i Sol-pin ezzel LEZÁRULT.

A hatályos felállás, végig a repóban utazó (file > env > script-default)
szerződéseken — a cron exportált env-je egyiket sem írhatja felül:

| Szerep | Motor | Hordozó |
|---|---|---|
| orchestrátor / reviewer / heal | **Claude Sonnet 5, `--effort high`** | `PIPELINE_MODEL`/`PIPELINE_EFFORT` script-default (`tools/round-pipeline.sh`) |
| rotáció | **`claude`** | commitolt `docs/execution/orchestrator-rotation` |
| implementer | **`minimax`** (MiniMax-M3, `~/.claude-minimax`, saját API-kulcs) | a queue MINDEN nyitott sora (64 sor: 43 pending + 18 prepared + 3 hold) |
| slot | **1 sáv** | commitolt `docs/execution/pipeline-slots` |
| Codex-oldal | **kizárva** | `fallback_engine` default `none` → `orchestrator_available` a `terra`/`sol` széket ezen méri |

**Miért `high` és nem `max`:** a Codex-oldal kiesésével az EGYETLEN
orchestrátor a Claude — a 2026-08-06-i `max` akkor volt vállalható, amikor a
Codex-oldal még osztozott a munkán. **Miért 1 slot:** a Sol-pin alatt mindkét
sáv a Codex-keretből ment; most minden sáv orchestrátora a Claude, két
párhuzamos session ugyanabból az előfizetésből enne, és visszahozná az
ADR 0222-t kikényszerítő hibaosztályt (a keretnek nekifutó kör → H-NOSIGNAL
halt → önjavító kör, ami szintén a keretből megy). **Függetlenség:** Claude
Sonnet 5 ≠ MiniMax-M3, és a `minimax` sor külső kulcsos
(`engine_uses_claude_quota` hamis) — mindkét mérési kulcson független.

A Sol/Terra **gépezete szándékosan a helyén maradt** (registry-sorok, `sol`
ágak a driverben, a mérő cellák a `CODEX_SIDE_ALIVE` /
`fallback="terra"` fixture-ökkel): a Codex-előfizetés esetleges újraéledése
fájl-átírás, nem újraépítés — a pontos visszaállási lista a
`pipeline-orchestrator-prompt.md` MOTOR-FELÁLLÁS blokk utolsó pontja.

A mérce nem gyengült. A `test_open_rounds_follow_the_measured_engine_rule`
carve-outja szűk és fail-closed párja van: a pin CSAK `codex` → `minimax`
irányba mozdulhat (ahol a mért szabály `minimax`-ot ad, ott `minimax`-nak KELL
állnia), és nyitott sor Codex-oldali motort egyáltalán nem nevezhet meg.
Mérés: `python3 -m pytest tools/tests -q` → **712 passed, 2 skipped, 610
subtests passed**; az egyetlen piros
(`test_test_mode_dispatch_does_not_switch_the_working_tree_off_its_branch`) a
környezeté, nem a diffé — ezen a dobozon nincs `gh` CLI, a változtatás előtt
ugyanígy piros volt, a Router CI futóján zöld.

A PR nyitva léte alatt a boxon futó lánc még a RÉGI (Sol/Terra) felállással
lezárta az **E08-R18**-at (PR #394) — a `done` sor motorja ezért `terra`,
történeti tényként; a base-merge ezt megőrizte, és csak a NYITOTT sorok
állnak `minimax`-ra. Mérés a merge után, a friss main fölött:
`python3 -m pytest tools/tests -q` → **713 passed, 1 skipped, 610 subtests
passed** (az egyetlen piros a `gh` CLI hiánya ezen a konténeren, a diff előtt
is ugyanaz; a Router CI futóján zöld).

Pontos következő teendő: nincs kézi indítás — a lánc minden firingen
`git fetch origin main` + `merge --ff-only` (`main_sync_strategy`), tehát a
következő cron-firing már ezzel a felállással veszi ki a queue első `pending`
sorát: **E08-R24 — Practice és Learn integráció**; a Chapter 13 ága
változatlanul **E13-R05** (a revideált scope-pal, lásd a lenti
HEAL-bejegyzést). Boxon egyszer ellenőrizendő: `tools/engine-profile.sh
list` — egy megmaradt `.pipeline/engine-override=terra` minden queue-sort
felülírna.

## ✅ E09-R03 KÉSZ — Public identity és handle policy — PR [#412](https://github.com/wolfcasaba/strumsight/pull/412), squash `607695e9` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HARMADIK KÖRE KÉSZ.** ADR 0397 §5.1–§5.4:
injektálható UUID public-id generátor, NFKC+casefold-normalizált handle
egyediség DB-szinten (unique index a normalizált oszlopon, NEM app-szintű
check-then-insert), reserved/blocked handle katalógus, egyetlen-handle-per-
hívás rate-limitált availability endpoint (nincs enumerációs felület), és
handle-change cooldown (14 nap) + redirect-ablak (30 nap) history táblával.
Új fájlok: `backend/app/community/{policies/handle_policy.py,
services/identity_service.py, models/handle_history.py,
routers/handles.py}`, `backend/alembic/versions/e09_r03_0003_community_
handle.py`, `backend/tests/community/test_handle_policy.py` (77 teszt).

**A kör három fordulóban zárult, ez az orchestrátor-session a [[L413]] HEAL
(#411) utáni folytatást vitte végig:** (1) a felfüggesztett minimax
implementert a healelt brief §0.1 utasítása szerint resume-oltam
(`9ad6cb3a`, a három lánc-toleráns cross-round tesztjavítás); (2) független
funkcionális + **security-reviewer** review (risk=high) ÖNÁLLÓ mutation-
próbákkal — nem csak a jelentett gate-kimenetre hagyatkozva. A review 1
nyitott **MAJOR**-t és 3 MINOR-t talált:

- **F1 (MAJOR, mérve reprodukálva):** `_client_key` (`routers/handles.py`)
  a kliens által küldött `X-Forwarded-For` fejlécet vette rate-limit
  kulcsnak trusted-proxy nélkül — 60 hívás, mind más hamis fejléccel, **0**
  `rate_limited` választ kapott a 30/perces limit ellenére. A §5.3
  "rate-limitált, nem enumerálható" kontroll ÉRDEMBEN nem működött, bár a
  router ebben a körben még nincs bekötve `app/main.py`-ba (Kör 6 az auth).
- **F2 (MINOR):** duplikált handle-claim 500-at adott 409 helyett — SQLite
  az UNIQUE-sértést az `UPDATE execute()`-nál dobja, nem a `commit()`-nál, a
  router viszont csak a `commit_with_uniqueness_check`-et csomagolta
  `except HandleAlreadyClaimed`-be.

Mindkettő egy javító körben zárult (`6d354812`, a minimax ELSŐ javító köre —
Codex-eszkalációra nem volt szükség): `_client_key` kizárólag
`request.client.host`-ra esik vissza, a claim/change végpontok egyetlen közös
`try/except` alá kerültek. A reviewer MINDKÉT javítást függetlenül
igazolta — a javítás előtti kódra visszaállítva reprodukálta a piros
állapotot (60/60 bypass, illetve 500-as válasz), majd a javítással zöldre.
Két MINOR follow-up nyitva marad (nem blokkol): a küszöb-hármas teszt a
`MIN_LEN`/`MAX_LEN` konstansból, nem a brief literál 2/3/24/25 értékéből
származtat; nincs HTTP-szintű (végpont-szintű) teszt az A1 Unicode-ütközésre,
csak policy- és DB-szintű. Review: `docs/reviews/e09-r03-review.md` +
`docs/reviews/e09-r03-security-review.md`.

Gate mindkét fordulóban (pre-fix `9ad6cb3a`, post-fix `6d354812`/`d830a037`)
izolált `/tmp` klónban, saját `python3.12 -m venv` + friss `pip install`:
`tools/round-gate.sh test/core/architecture_dependency_test.dart` MINDEN
GATE ZÖLD, `backend: ruff check`/`ruff format --check` tiszta, `backend:
pytest -q` **282 passed, 0 failed**. Scope-audit mindkét fordulóban OK (a
javító kör diffje 2 fájl: `handles.py` + a teszt). CI a pontos merge SHA-n
(`d830a037`): Router CI + Full Gate (no APK) mindkettő `success`.

## ✅ [HEAL E09-R03/H3] KÉSZ — az L411 minta egy láncszemmel mélyebben: `allowed_paths` nem fedte a MÁSODIK cross-round migráció-tesztet — PR [#411](https://github.com/wolfcasaba/strumsight/pull/411), squash `2359b808` (2026-08-22, L413)

Az E09-R03 (Public identity és handle policy, ADR 0397) H3-mal állt meg,
MIUTÁN az implementer (minimax) már ledolgozta a kört (branch
`minimax/e09-r03-public-identity-and-handle-policy`, `3cca3ddd`, pushed, saját
scope 75/75 zöld). Gyökérok: a kör saját, helyes migráció-láncolási döntése
(`e09_r03_0003.down_revision = "e09_r02_0002"`) törvényszerűen tört HÁROM,
E09-R02-ben írt cross-round tesztasszerciót két fájlban —
`backend/tests/test_migrations.py::test_downgrade_one_revision_drops_only_community_tables`
és `backend/tests/community/test_profile_schema.py`
(`test_alembic_upgrade_head_applies_community_migration` +
`test_alembic_downgrade_drops_community_tables`) — mert az [[L411]] fixe a
KÉT-migrációs világra hardcode-olt maradt (pinned head-string, relatív
`downgrade -1`, konkrét tábla-nevek). Egyik fájl sem szerepelt az
`allowed_paths`-on, az implementer helyesen `stopped`-öt jelzett a §10.4-ben
pontosan diagnosztizálva mindhárom törött asszerciót. Class B (kör-tartalom:
a saját láncolási döntés kontra egy MÁSIK kör régi, hardcode-olt tesztje),
függetlenül reprodukálva: `cd backend && .venv/bin/python -m pytest
tests/test_migrations.py tests/community/test_profile_schema.py -q` → 3
FAILED.

Feloldás (`docs/rounds/e09-r03-public-identity-and-handle-policy.md` §0.1):
mindkét fájl szűken bekerült az `allowed_paths`-ra, és — mivel ez a MÁSODIK
előfordulása ugyanennek a mintának — a folytatáshoz adott instrukció nem egy
harmadik hardcode-olt javítás, hanem lánc-toleráns ellenőrzés: (1) "head
tartalmazza X-et ŐSKÉNT" (`ScriptDirectory.walk_revisions`) a pinned
head-string helyett; (2) `downgrade(config, "<explicit revízió>")` a relatív
`-1` helyett; (3) a tábla-HALMAZ változásának mérése a konkrét tábla-nevek
kimondása helyett — hogy az Epic 9 hátralévő ~29 köre közül egyik láncoló
migráció se ismételje meg ugyanezt. Regressziós védelem:
`tools/tests/test_e09_r03_migration_chain_test_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen;
mindkét mért halt-útvonal RED volt a javítás előtt, GREEN utána, egy
szomszédos backend-teszt fájl (`test_auth.py`) pedig továbbra is scope-on
kívül marad. Teljes gate izolált heal-worktree-ben: `python3 -m pytest
tools/tests -q` → 718 passed, 1 skipped, 639 subtests (az egyetlen skip a
`gh` CLI hiánya ezen a konténeren, a diff előtt is ugyanaz). `brief-lint
--level strict` tiszta (az S8 visszakeresett-előzmény jelet a §0.1 L411-
hivatkozása zárja). Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L413]].

Mivel az eredeti E09-R03 implementer-munka már kész és a saját branch-én ül,
ez a heal NEM vitte tovább a tartalmi munkát — a lánc a MEGLÉVŐ
`minimax/e09-r03-public-identity-and-handle-policy` ágon, a felfrissített
brieffel folytatja: a három tesztasszerció lánc-toleráns javítása még
hátravan az implementer oldalán, utána a §7 mindkét parancsa, majd
review/CI/merge a szokásos rend szerint.

## ✅ E09-R02 KÉSZ — Community backend modul és első Alembic migráció — PR [#410](https://github.com/wolfcasaba/strumsight/pull/410), squash `4fffe20e` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) MÁSODIK KÖRE KÉSZ.** A `backend/app/community/`
modulhatár és az első Community migráció (`community_profiles` +
`community_privacy_settings`, `e09_r02_0002` láncolva `e01_r12_0001`-re)
létrejött: BigInteger belső PK + `Uuid` public_id, DB-szintű 1:1 unique
constraint mindkét táblán, whitelist-only Pydantic válasz-séma (a belső `id`
sosem szivárog), `build_community_router(settings)` factory +
`community_readiness_failure()` — mindkettő ÖNÁLLÓAN a `community/` modulban,
`main.py` érintetlen marad (ADR 0396 §3–4, következő kör dolga a bekötés).

A kör két szakaszban futott: az első implementer-futás (`05fa154d`) H3-mal
állt meg, mert a kör saját migráció-láncolási döntése szükségszerűen
elrontotta a MEGLÉVŐ `test_migrations.py::test_downgrade_one_revision_removes_application_schema`
egyetlen-migrációs feltevését, a fájl pedig nem volt az `allowed_paths`-on — lásd
[[HEAL E09-R02/H3]] (PR #409). Ez a session a self-healt main-ről a
munkapéldányba merge-elte, majd az implementer (minimax) elvégezte a §0.1
szerinti tesztfelbontást: `test_downgrade_one_revision_drops_only_community_tables`
(egy lépés a fejtől — csak a Community táblák tűnnek el) és
`test_downgrade_to_base_removes_application_schema` (downgrade a base-ig — a
`users`/`user_settings` is eltűnik).

Független review (`docs/reviews/e09-r02-review.md`): APPROVED, 0
BLOCKER/MAJOR/MINOR, 1 eljárási NOTE. A reviewer izolált `/tmp` klónban
ÖNÁLLÓAN futtatta újra mind a 9 gate-cellát (zöld), a scope-auditot a
folytatás tényleges bázisán (`9be8e613`, a self-heal beépítése után — 2
változott fájl, 0 sértés), és elvégezte a kötelező A7 valódi-sértés próbát
(`user_id` unique constraint eltávolítva →
`test_duplicate_profile_for_same_user_is_rejected_by_db` PIROSRA vált →
visszaállítva, 17/17 zöld). Az orchestrátor a saját munkakönyvtár-hibáját
(egy ideiglenes prompt-fájl a megosztott worktree-ben, ami hamis
`scope_audit=VIOLATION`-t okozott a `mm-round.sh` beépített auditán) felismerte
és javította a review előtt — nem érintette a kód minőségét.

CI: Full Gate
[32575935889](https://github.com/wolfcasaba/strumsight/actions/runs/32575935889)
és Router CI
[32576081884](https://github.com/wolfcasaba/strumsight/actions/runs/32576081884)
success az exact merge-elő SHA-n (`17b899a7`), a helyi HEAD-del összevetve. A
`main` a dispatch óta nem mozdult (`a11608b8` mindkét oldalon).

Pontos következő kör: **E09-R03** — a Community router bekötése
`main.py::create_app()`-ba és a `/health/ready` végpontba (ADR 0395
Következmények 2–3. pont, ADR 0396 §3–4), a queue soros szerint.

## ✅ [HEAL E09-R02/H3] KÉSZ — `allowed_paths` nem fedte a migráció-láncolás által tört downgrade-tesztet — PR [#409](https://github.com/wolfcasaba/strumsight/pull/409) (2026-08-22, L411)

Az E09-R02 (Community backend modul + első Alembic migráció, ADR 0396) H3-mal
állt meg, MIUTÁN az implementer (minimax) már ledolgozta a modult (branch
`minimax/e09-r02-backend-community-module-and-migration`, `05fa154d`, pushed).
Gyökérok: a kör saját §0.0/§5 döntése (a `e09_r02_0002` migráció a MEGLÉVŐ
`e01_r12_0001` fejére láncolódik) szükségszerűen hamissá teszi a MEGLÉVŐ
`backend/tests/test_migrations.py::test_downgrade_one_revision_removes_application_schema`
egyetlen-migrációs feltevését (`downgrade -1` a fejtől == `users`/
`user_settings` eltűnik) — két láncszemmel `downgrade -1` csak a LEGÚJABB
migrációt vonja vissza. A fájl nem szerepelt az `allowed_paths`-on, az
implementer helyesen `blocked`-ot jelzett a STOP-protokoll szerint. Class B
(kör-tartalom: a saját láncolási döntés kontra a `allowed_paths` hiánya),
függetlenül reprodukálva: `cd backend && python -m pytest
tests/test_migrations.py -q` → `AssertionError: assert 'users' not in
{'alembic_version', 'user_settings', 'users'}`.

Feloldás
(`docs/rounds/e09-r02-backend-community-module-and-migration.md` §0.1):
`backend/tests/test_migrations.py` szűken, egyetlen fájlként bekerült az
`allowed_paths`-ra és a §4 táblázatba, konkrét instrukcióval a folytatáshoz —
a downgrade-teszt bontása "egy lépés a fejtől" (csak a Community táblák
tűnnek el) és "downgrade a base-ig" (a `users`/`user_settings` is eltűnik)
esetekre. Regressziós védelem:
`tools/tests/test_e09_r02_migration_downgrade_test_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen; a
mért halt-útvonal (`git show HEAD:...`-tal visszaállított, pre-fix brief-
tartalommal reprodukálva) RED volt a javítás előtt, GREEN utána, egy
szomszédos backend-teszt fájl (`test_auth.py`) pedig továbbra is scope-on
kívül marad. Teljes gate izolált heal-worktree-ben: `python3 -m pytest
tools/tests -q` → 716 passed/1 skipped/640 subtests/0 failed. `brief-lint
--level strict` tiszta. Router CI
[32574365404](https://github.com/wolfcasaba/strumsight/actions/runs/32574365404)
success az exact push SHA-n (`31573292`), amit a merge előtt a helyi HEAD-del
összevetve igazoltam. Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L411]].

Mivel az eredeti E09-R02 implementer-munka már kész és a saját branch-én ül,
ez a heal NEM vitte tovább a tartalmi munkát — a lánc a MEGLÉVŐ
`minimax/e09-r02-backend-community-module-and-migration` ágon, a felfrissített
brieffel folytatja: a `test_downgrade_one_revision_removes_application_schema`
kétesetes felbontása még hátravan az implementer oldalán, utána a §7
mindkét parancsa, majd review/CI/merge a szokásos rend szerint.

## ✅ E09-R01 KÉSZ — Community baseline, threat model és feature flag — PR [#408](https://github.com/wolfcasaba/strumsight/pull/408), squash `7ad4b28d` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) ELSŐ KÖRE KÉSZ.** Alkalmazáskód-változtatás
nélkül: öt Community feature flag (`communityEnabled` + 4 alkapcsoló,
Flutter + backend), egy nyolc-kategóriás threat model
(`docs/security/community-threat-model.md`), egy mért baseline leltár
(`docs/baseline/epic-09-community-start.md`) és a backend
`community_postgres_ready` readiness placeholder — mind az `ADR 0395`
szerint. Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5,
javító kör nélkül (0 BLOCKER/MAJOR, 1 MINOR, 1 NOTE —
`docs/reviews/e09-r01-review.md` APPROVED).

**Pre-flight ADR 0395 döntése:** a dart-define/env kill switch mechanizmus
(`STRUMSIGHT_COMMUNITY*`, `defaultValue` nélkül — hiány = `false` MINDEN
környezetben) a Flutter oldalon `FeatureFlags.forEnvironment` TÖRZSÉBEN
olvasódik, `app_config.dart` érintése nélkül, mert az a brief
`allowed_paths`-án kívül esik (az `accountEnabled` élő mintája
app_config.dart-ot olvasna, de az itt tiltott zóna). A backend öt mezője a
`tutor_enabled` mintáját követi (env-aware branch NÉLKÜL, mindig `False`
amíg egy explicit env-var be nem kapcsolja) — NEM a
`diagnostics_enabled`/`apk_download_enabled` nonProd-alapú mintát. A döntés
tudatosan ELTÉR a repó ellentétes precedensétől (ADR 0220, Epic 6:
hardcode-`false` MINDEN környezetben, dart-define NÉLKÜL, a teljes
építő-epic alatt) — az eltérés indoklása ADR 0395 „Elutasított
alternatívák" szakaszában.

Review: saját, izolált `/tmp` klónban újrafuttatott gate (9/9 zöld,
egyezik az implementer §10.2 táblázatával), scope-audit tiszta (7/7
`allowed_paths`, 0 kívüli fájl), §6.1 valódi-sértés próba
(`communityEnabled: true` szabotázs) reprodukálva. 1 MINOR: a baseline-
doksi három mért fájlszáma (`lib/features/auth/` teszt-fájl 7→4 tényleges,
`lib/features/learn/` 24/34→25/32 tényleges) eltér a tényleges
`find`-kimenettől — dokumentum-only, nincs gate-hatás, nem blokkoló; a
Kör 2 pre-flightja javítsa a §1.1 táblázatot, mielőtt rá támaszkodik. Exact
`745a9a15`: Full Gate
[32570982536](https://github.com/wolfcasaba/strumsight/actions/runs/32570982536)
+ Router CI
[32571697617](https://github.com/wolfcasaba/strumsight/actions/runs/32571697617)
success (utóbbi `workflow_dispatch`-csel manuálisan indítva, mert a review-
commit csak `docs/reviews/**`-t érintett, ami nincs a `router-ci.yml`
push-trigger path-listáján — az exact-SHA kapuhoz kellett).

## ✅ E08-R30 KÉSZ — Epic 08 closure: route activation + real-fixture legacy
verification + numerical deprecation gates — PR [#407](https://github.com/wolfcasaba/strumsight/pull/407), squash `a8ecb9f3` (2026-08-22)

**EPIC 8 (GAMIFICATION) LEZÁRVA — mind a 30 köre kész.** Implementer MiniMax
M3, orchesztrátor/reviewer Claude Sonnet 5, javító kör nélkül (0
BLOCKER/MAJOR/MINOR, 2 NOTE — `docs/reviews/e08-r30-review.md` APPROVED). A
kör pre-flightja saját `§0.0` brief-revíziót igényelt: a 2026-08-18-i brief
nem mérte, hogy (1) a tényleges `GoRoute` wiring `app_router.dart`-ban él, nem
az engedélyezett `app_route.dart`-ban ([[L97]]/[[L94]] mintázat), (2) a hat új
képernyő egyike sem volt valaha adathoz kötve (nulla példányosítás
production kódban), (3) a „Kör 24 migrációs kapcsoló" sehol nincs élesítve
(`dualWriteMode:` nulla találat), (4) a meglévő legacy-migrációs teszt
idealizált `PracticeEntry`-kkel dolgozott, nem valós V1-kulcs-alakú JSON-nal.
Az `allowed_paths` a revízióval bővült (`app_router.dart` + egy ÚJ
fixture-teszt), a scope-audit mindkét dispatch után OK (0 sértés). Exact-SHA
`3a6f10b3`: Full Gate
[32569011383](https://github.com/wolfcasaba/strumsight/actions/runs/32569011383)
+ Router CI
[32569012517](https://github.com/wolfcasaba/strumsight/actions/runs/32569012517)
success; a reviewer saját izolált `/tmp` klónban mind a kilenc gate-lépést
függetlenül újrafuttatta (zöld) és a scope-audit-ot is saját kézzel mérte.

Az Epic 8 ZÁRÓ köre. Hat új route élesítve, a régi `/streak` és `/progress`
deep link VÁLTOZATLANUL él (ADR §5.1), a legacy migrátorok valós V1-kulcs
alakú JSON-nal bizonyítottak. Nincs kódbeli kapcsoló-flip — a §0.0 rögzítette,
hogy a dual-write adapternek MA nincs production call chain hívója, tehát a
`newOnly` végállapot SZÁMSZERŰ jövőbeli feltételekhez kötve dokumentálva
([`docs/sdd/epic-08-completion-report.md`](docs/sdd/epic-08-completion-report.md) §3),
nem átbillentve. Ez a kör szándékosan NEM nyúlt a `lib/features/**`-höz —
a route-aktiváció és a minimális Riverpod-ragasztó kizárólag a most
engedélyezett `lib/app/routing/app_router.dart`-ba került, kizárólag már
publikus `keyValueStoreProvider` + `appLoggerProvider` + `gamification/public.dart`
importokból.

ÚJ:
- `lib/app/routing/app_route.dart` — hat új konstans (`gamificationHub`,
  `achievements`, `achievementDetail`, `quests`, `streakDetail`, `rewardInbox`).
- `lib/app/routing/app_router.dart` — hat új `GoRoute` + öt file-private
  provider (`_gamificationRepositoryProvider`, `_levelCurveProvider`,
  `_gamificationProfileProvider`, `_streakStateProvider`,
  `_rewardInboxProvider`); a meglévő útvonalak (`/streak`, `/progress`,
  …) sorai ÉRINTETLENEK.
- `test/app/routing/app_router_test.dart` — nyolc új cella: a két legacy
  deep link VÁLTOZATLANUL a V1 screen-re mutat, a hat új útvonal pedig a
  megfelelő V2 widgetre.
- `test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart`
  (ÚJ) — hét teszt, mind valós V1-kulcs alakú JSON-t ír a
  `LegacyStorageKeys` / `StorageKeys` tényleges kulcsnevei alá egy
  `InMemoryKeyValueStore`-ba, és a `LegacyStreakMigrator`-t (mindkét ág:
  pre-v22 nyers kulcs ÉS post-v22 namespaced envelope) és a
  `LegacyPracticeAdapter` / `GamificationMigrator`-t (valós
  `PracticeEntry.fromJson` dekódolással a `lib/features/progress/`-ból)
  hajtja végig. A fájlnév szándékosan kerüli a "migration" szót (az
  `ai-router` `high_risk_path_fragments` listája ezt a szót tartalmazza —
  ez a teszt nem indokol `risk = "high"` besorolást).
- `docs/sdd/epic-08-completion-report.md` — az Epic 8 lezáró jelentése:
  mért állapot (dual-write kapcsoló be nem kötve, hat képernyő soha nem
  volt adathoz kötve) + SZÁMSZERŰ kivezetési feltételek (wire-shape
  parity ≥30 fixture / 7 CI run, zero ledger loss 3 property-seed,
  production-side ingest mindkét adapterre, 14 napos dual-write soak
  nulla mismatch log mellett) + az A3 próba-jegyzőkönyv + a CI-link
  placeholder (a §7 gate UTÁN, de a végleges CI-linket az orchestrátor
  illeszti be dispatch után — ez a handoff rögzíti a helyét/szerkezetét).
- `README.md` — frissített státusz banner, frissített feature-sor, új
  Gamification szakasz (route lista, settings, storage envelope, offline,
  accessibility, completion-report link).

A no-op callbackek (`onOpenLevelDetail`, `onRecoveryPressed`, a quest
`onAction`, a reward inbox `onItemSelected` / `onMarkSeen`) explicit
`// TODO(E08-R30): <mit kell>` kommenttel vannak jelölve — ezek a
jövőbeli bekötő körök felé nyitott tételek, és a completion report §3
rögzíti, hogy a feature-oldali provider-lift NEM ennek a körnek a dolga.

**Kötelező valódi-sértés próba saját kézzel megismételve (§6.1):**
a completion report korai piszkozatába egy SZÁNDÉKOS PIROS CI-link
került, hogy az A6 cella bizonyíthatóan elutasítsa — cserélve a helyes
GREEN-link placeholderére, az A6 cella így a „rajta" küszöbön áll.

Mérce: `tools/round-gate.sh test/app/routing/app_router_test.dart
test/features/gamification test/features/streak test/features/progress` —
**MINDEN GATE ZÖLD**, előtérben, csonkítás nélkül futtatva. Scope-audit
(`git diff --stat`) nem mutat `lib/features/` útvonalat. A teljes
acceptance-tábla (A1–A8) és a mérce-mátrix minden sora a
[`docs/sdd/epic-08-completion-report.md`](docs/sdd/epic-08-completion-report.md)
§2 / §3 / §5 alatt dokumentálva.

Pontos következő E08 kör: az Epic 8 lezárult — a queue a Chapter 9
(`E09-R01`+) felé folytatódik (ellenőrizve: `pipeline-queue.tsv`-ben ez az
első `pending` sor E08-R30 után, megelőzi a Chapter 13 E13-R05-öt).

**Nyitott, EMBERI döntést NEM igénylő tartozások, EZUTÁN a bekötő kör
dolga** (`docs/sdd/epic-08-completion-report.md` §3 + a review N1/N2):

- a hat új képernyő adatvetületei jelenleg egyszeri (`Provider`, nem
  `StreamProvider`) olvasások `app_router.dart`-ban — a Hub/Streak-
  detail/Inbox nem frissül élőben, amíg az app-session újra nem indul;
- `activeQuestCount`, `masteryUnlockedCount`, az achievement-progressz és a
  napi/heti quest-listák ma hardkódolt `0`/üres értékek — nincs perzisztált
  quest-/achievement-progressz forrás a `GamificationRepository`-ban;
- a `RewardInboxScreen` üres marad, mert a storage-szintű
  `GamificationInboxItem` (csak id/createdAt/viewedAt) és a domain
  `RewardInboxItem` (a teljes `RewardEvent`-et hordozza) között nincs
  triviális leképezés;
- a streak-recovery gomb no-op (nincs publikus repository-metódus a
  vásárláshoz);
- a dual-write kapcsoló `newOnly` végállapotba állításának négy számszerű
  feltétele a completion report §3.2-ben.

## ✅ E08-R28 KÉSZ — Ledger sync contract, merge és verified státusz — PR #406, squash `571981b7` (2026-08-22)

Offline-first, duplikációmentes szinkron-szerződés a jövőbeli fiók- és
közösségi (Epic 9) használathoz — a legfontosabb szabály: **a szerver soha
nem fogad el kliens-oldali összesített XP-t**. ÚJ:
`lib/features/gamification/data/sync/{gamification_sync_contract,ledger_merge_policy}.dart`
(verziózott nyugta-alapú fel-/letöltés, összefésülés kettős dedup-kulccsal —
`ledgerId` ÉS `sourceEventId`), `backend/app/gamification/{schemas,service}.py`
(a szerver saját maga összegez, `totalXp` mező NINCS a bemeneten). ADR
[`0394`](docs/adr/0394-ledger-sync-contract-and-merge.md) — a brief előre
kiosztott `0319`-e stale volt (a `reserve-adr` foglaló `0394`-et adott,
ugyanaz a minta, mint az E08-R27 stale `0318`-ja).

A dedup-kulcs kettőssége a lényeg: csak `ledgerId`-ra dedupolás
duplikálna (két eszköz, két azonosító, ugyanaz az esemény), csak
`sourceEventId`-re dedupolás adatvesztene (két legitim, eltérő eseményű
nyugta ütköző azonosítóval összeolvadna). **Kötelező valódi-sértés próba
saját kézzel megismételve:** a `_collapseGroup` (cross-device
sourceEventId-összefésülés) eltávolítása a TÉNYLEGES
`LedgerMergePolicy.merge`-ből 2/20 tesztet pirosra váltott (A1 idempotencia
+ a §6.1 „on threshold" cella) — pontosan az implementer állítása szerint;
visszaállítva, 20/20 zöld.

**Egy javító kör, F1 MAJOR + F2 MINOR, mindkettő a reviewer saját kezű
mérésével fedve fel, nem az implementer önbevallásából:**

- **F1 (MAJOR, javítva):** a Dart `encodeUpload()` és a backend
  `ReceiptUpload` NEM ugyanazt a wire-alakot beszélték — a Dart minden
  nyugtát `{'schemaVersion':…, 'receipt': {…, 'status':…}}` beágyazásban
  küldött, a backend LAPOS `ReceiptUpload` listát várt. Saját kézzel,
  pydantic `model_validate`-tel igazolva: a Dart kimenet a backend modellen
  8 validációs hibát adott. A kör saját deklarált célja egy "szerződés" volt
  — a két fél nem ugyanazt beszélte, holott mindkettő EBBEN a körben
  készült. Javítás: a Dart-oldal a backend lapos alakjához igazodott
  (`totalXp` és `status` NINCS a wire-en), plusz ÚJ, kétoldali teszt: a Dart
  oldalon a TÉNYLEGES `encodeUpload()` kimenet kulcsait ellenőrzi, a
  backend oldalon egy kézzel felírt, a Dart kimenetet tükröző fixture-t old
  fel elfogadással.
- **F2 (MINOR, javítva):** nincs `max_length` a `ledgerId`/`sourceEventId`/
  `receipts` mezőkön (saját kézzel igazolva: 1M karakteres id és 100k elemű
  lista is elfogadásra került) — látens DoS egy jövőbeli, bekötött útvonalon.
  Javítás: `max_length=256`/`500`, négy határ-teszttel (fölötte/rajta mindkét
  oldalon).
- Köztes tooling-epizód (nem lelet): az első javító-kör futás közben az
  implementer egy ÜRES helyi `backend/.venv`-et hozott létre (a
  `pip install`-t helyesen blokkolta az `implementer_guard`), ami
  beárnyékolta a `tools/round-gate.sh` már meglévő, működő fallback-ját a
  közös `$HOME/music-theory/backend/.venv`-re — emiatt `stopped`-ot
  jelzett. Az orchesztrátor törölte a lokális, üres venv-et (gitignore-olt,
  önmagától létrehozott artefaktum), és egy rövid resume-prompttal
  folytatta a kört — a tényleges F1/F2 kódjavítások érintetlenek maradtak.

Dedikált biztonsági review (`risk = "high"`, `security-reviewer` agent):
**PASS, 0 CRITICAL/BLOCKER**. Egy látens (nem blokkoló) MAJOR-t is felszínre
hozott N1-ként: a `verified` ma kizárólag séma-érvényességet jelent, XP
felső korlát vagy policy-újraszámolás NÉLKÜL — nincs élő fogyasztó, ami ma
bizalmi jelzésként olvasná, de a jövőbeli router-kötő körnek explicit gátat
kell szabnia, mielőtt bármilyen felület `verified`-et bizalmi jelzésként
mutatna. Review: [`docs/reviews/e08-r28-review.md`](docs/reviews/e08-r28-review.md),
[`docs/reviews/e08-r28-security.md`](docs/reviews/e08-r28-security.md).

Mérce: `tools/round-gate.sh
test/features/gamification/data/ledger_merge_policy_test.dart` +
`python3 -m pytest backend/tests/test_gamification_ledger.py -q` — **MINDEN
GATE ZÖLD** (9 lépés, 22 Dart + 15 backend teszt), javítás előtt és után is
SAJÁT kézzel, izolált klónból (GitHub originből) reprodukálva. Scope-audit
mindkétszer OK. A kör alatt a `main` egyszer mozdult (E09 round-brief batch,
PR #405, `docs/rounds/e09-*` + `pipeline-queue.tsv`, diszjunkt fájlkör) —
`merge --no-ff` + teljes CI-újradispatch a §0.3 szerint. Exact `dda4534b`:
Full Gate [32565070603](https://github.com/wolfcasaba/strumsight/actions/runs/32565070603)
+ Router CI [32565071642](https://github.com/wolfcasaba/strumsight/actions/runs/32565071642)
success; post-merge célzott gate + backend pytest a friss `main`-en
önállóan is zöld. Ez a kör NEM köti be a HTTP-végpontot (router mounting) —
a `backend/app/gamification/` router-szintű regisztrációja egy jövőbeli
kör dolga. Pontos következő E08 kör: **E08-R30 — Epic 08 migráció,
regresszió és lezárás** (queue-ban `minimax`) — az **E08-R29** (Integritás,
analytics, balance) `hold`-on marad; a queue-scan a legelső `pending` sort
választja, ez a §0.3-nál mérten `E08-R30`, nem az újonnan batch-elt E09-R01
(annak ellenére, hogy fájl-sorrendben előrébb ér az E09-batch — az E08-R30
sora korábbi a fájlban).

## ✅ E08-R27 KÉSZ — Gamification akadálymentesség és beállítások — PR #404, squash `db6293f4` (2026-08-22)

A teljes gamifikációs réteg MOST már kikapcsolható, hozzáférhető és nem
tolakodó: ÚJ `GamificationPreferences` domain-modell (intenzitás/haptika/
hang/csökkentett mozgás/értesítés), egy szinkron-olvasású `NotifierProvider`
(`gamification_preferences_provider.dart`, kizárólag lokális perzisztencia —
a felhő-szinkron e körben tiltott, `settings_sync.dart` érintetlen), és egy
ÚJ `GamificationSettingsSection` a Settingsben. ADR:
[`0393`](docs/adr/0393-gamification-accessibility-and-settings.md) — a brief
előre kiosztott `0318`-a stale volt (egy korábbi, független kör már foglalta,
`tools/round-slots.py reserve-adr` adta a `0393`-at). A pre-flight (Claude
Sonnet 5) korrigálta az `allowed_paths`-ot is: az ÚJ l10n-kulcsok a
`lib/l10n/features/gamification_{en,hu}.arb` SZEGMENSBE tartoznak, nem a
generált `app_{en,hu}.arb` aggregátumba (ugyanaz a hibaosztály, ami az
E08-R20/E08-R22-ben mid-round fixet igényelt — itt előre elkerülve).

A kikapcsolás VIZUÁLIS — a ledger/széria/mastery kiértékelés a preferenciáktól
függetlenül fut (A1/A2), az értesítési engedély megadása SOSEM ad XP-t/oldja
fel (A3, sötét-minta tilalom), mind az öt beállítás önállóan hat a leképezett
megjelenítésre (A4), a változás azonnal érvényesül (A5), mind a 22
achievement kitöltött a11y-leírással rendelkezik mindkét nyelven (A6,
reverzibilis valódi-sértés próbával), és a WCAG AA kontraszt-küszöb a
MEGLÉVŐ, L381-ben már kijavított `tool/ui_contrast_check.dart`-ot használja
(helyes sRGB gamma-2,4 transzformáció) egy ÚJRA-implementálás helyett.

Egy javító kör: **F1 MAJOR** — a review saját kézzel elkapta, hogy a domain
`gamification_preferences.dart` egy `presentation/widgets/
reward_summary_sheet.dart`-ból importált (`show RewardSummaryFeedback`),
ami `package:flutter/material.dart`-tal kezdődik — a domain-osztály emiatt
TRANZITÍVAN függött a Fluttertől (AGENTS.md §6 sértés). A
`tool/check_architecture.dart` ezt NEM fogta meg, mert a
`sharedDomainMustRemainFrameworkIndependent` szabály `_isSharedDomain()`
allowlistje (`lib/core/music/`, `lib/core/audio/codec/`,
`lib/features/practice/domain/`) nem tartalmazza a
`lib/features/gamification/domain/`-t — GATE-LEFEDETTSÉGI RÉS, amit a
manuális review fogott meg, nem a gépi mérce. Javítás: a leképezés
(`gamificationFeedbackFor`) átköltözött a presentation-réteg providerbe.
Review: [`docs/reviews/e08-r27-review.md`](docs/reviews/e08-r27-review.md) —
APPROVED a javítás után, 0 nyitott BLOCKER/MAJOR, 1 MINOR (F2 — az A1/A2
„valódi-sértés próba" nem köti be ténylegesen a preferenciát a
`CelebrationCoordinator`-ba, mert ma nincs is éles bekötés; a jövőbeli
UI-bekötő kör pre-flightjának szól) + 2 NOTE (inline storage-kulcsok
`StorageKeys` nélkül, dokumentált indokkal; a `reward_summary_sheet.dart`
doc-kommentje még mindig „Kör 27"-re hivatkozik, a tényleges bekötő kör
javítja).

Mérce: `tools/round-gate.sh test/features/gamification/presentation/
gamification_accessibility_test.dart test/features/settings` → **MINDEN GATE
ZÖLD** (12+51 teszt), a javítás ELŐTT és UTÁN is SAJÁT kézzel, izolált
klónban reprodukálva. Scope-audit mindkétszer OK. CI a merge SHA-n
(`a20182a6`): `full-gate.yml` (32560163642) success, `router-ci.yml`
(32560901860, kézi `workflow_dispatch`, mert az utolsó commit csak a
review-jelentést érintette) success. Ez a kör NEM köti be a
`reward_summary_sheet.dart`-ot egyetlen élő hívóba sem (nincs is
`allowed_paths`-on, és MA nincs élő hívó egyáltalán) — egy jövőbeli,
feltehetően `E13-R32` (gamification-ui) kör dolga. Pontos következő E08 kör:
**E08-R28 — Ledger sync contract és merge** (queue-ban `minimax`, ADR 0319
előre kiosztva, ellenőrizendő a foglalóval).

## ✅ E08-R26 KÉSZ — Cross-feature gamification integráció (Analysis/Vision/Tutor/Plan) — PR #403, squash `ea2e22a4` (2026-08-22)

A maradék négy forrás — Analysis, Vision, AI Tutor, Practice Generator —
MOST már bekötve a gamification jutalom-láncba: négy ÚJ, tisztán caller-fed
adapter (`lib/features/{analyze,vision,ai_tutor,practice_generator}/
application/gamification_*_adapter.dart`). ADR: [`0392`](docs/adr/0392-cross-feature-gamification-adapter-caller-fed-boundaries.md)
— a pre-flight (Claude Sonnet 5) NÉGY ponton cáfolta meg a 2026-08-18-i brief
feltevéseit: (1) az `ai_tutor/public.dart` boundary VÉGLEGESEN üres, egy
merge-elt E04-R01 guard pinneli (`test/features/ai_tutor/
ai_tutor_boundary_test.dart`, L139) — a tutor-adapter ezért ZÉRÓ szimbólumot
importál az `ai_tutor`-ból, a beszélgetés-nulla-XP szabály (A1) strukturálisan
garantált, nem futásidejű `if`; (2) `AnalyzeResult`-nak nincs
`sourceHash`/`analyzerVersion` mezője — az analysis-adapter saját, hívó-fed
jel-típust definiál ezekkel; (3) a brief `minVisionConfidence` neve szó
szerint nem létezik — a mért megfelelő `VisionClaimGuard._minimumConfidence
= 0.70`, ami a `vision/domain/integration/public.dart` (egy MÁSIK, szűkebb
barrel) exportján érhető el, NEM a top-level `vision/public.dart`-on; (4) a
`PlanStatus.completed` (teljes terv) enum-érték SEHOL nem kerül beállításra
a mai kódban (L20 — elérhetetlen cél-státusz), csak a blokk-szintű
`PracticeItemStatus.completed`, ami MÁR ma is a meglévő practice/song
adapterekkel jutalmazódik — a plan-adapter ezért caller-fed
`planCompleted: bool` jelet fogad, és nem nyúl az `active_plan_controller.dart`/
`generation_orchestrator.dart` (tilos zóna) állapotgépéhez.

A terv-bónusz (§5.3) FLAT és nem-összegző: `bonusXp` kényszerítve `0`-ra, csak
a policy `baseXp`-je landol a ledgerben, hogy a blokkok (amik már fizettek a
saját forrásukon) ne duplázódjanak. A Vision-adapter két esemény (`vision-base`
mindig, `vision-technical` csak a `VisionClaimGuard` engedélye után) —
a §6.1 küszöb-hármas (0.69/0.70/0.71) szó szerint tesztelve, a küszöb maga
inkluzív-elfogadó. Az Analysis-adapter dedupja `(sourceHash, analyzerVersion)`
párra épül, nem csak a hash-re — egy verzióváltás legitim új jutalom.

Mérce: `tools/round-gate.sh test/features/gamification/integration/
cross_feature_reward_flow_test.dart test/core/architecture_dependency_test.dart`
→ **MINDEN GATE ZÖLD** (16+37 teszt), reprodukálva SAJÁT kézzel izolált
klónban a review-ban is. Az A6 architektúra-guard mind a négy adapterre
kiterjed, a vision-nél MINDKÉT elfogadott barrelt (top-level + `domain/
integration/`) kezeli. Három `_Broken*Adapter` valódi-sértés próba
(chat-farm, blokk-összegzés, hash-only dedup) — mindhárom önálló osztály, a
VALÓDI ingestor/eligibility/policy láncon fut át, nem csonka váz. Review:
[`docs/reviews/e08-r26-review.md`](docs/reviews/e08-r26-review.md) —
APPROVED, 0 BLOCKER/MAJOR/MINOR, 3 NOTE (mind unwired-today, jövőbeli
UI-wiring kör hatókörű: `analyzerVersion` hash nélkül landol a ledgerben; a
caller-fed id-mezők nem típusos/charset-lezárt id-k; a másolt `utf8Bytes()`
segédfüggvény — MÁR az E08-R25 dal-adapterből örökölve, nem ez a kör vezette
be — nem valódi UTF-8, csak ASCII-bemenetre helyes). `security-reviewer`
agent (risk="high") függetlenül: PASS.

Ez a kör NEM köti be az adaptereket a hívó UI-ba (nincs is az
`allowed_paths`-on) — a négy adapter kész, tesztelt felület, amit egy
jövőbeli kör hív majd az Analyze/Vision result-screenekből, a plan-befejezés
UI-jából. CI: `full-gate.yml` + `router-ci.yml` mindkettő zöld a merge SHA-n
(`d3c4a9a0`, PR #403 squash → `ea2e22a4`). Pontos következő E08 kör:
**E08-R27 — Gamification accessibility és settings** (queue-ban `minimax`,
ADR 0318 előre kiosztva).

## ✅ E08-R25 KÉSZ — Song Trainer és setlist integráció — PR #402, squash `204b3798` (2026-08-22)

A dalgyakorlás (szakasz/hurok, teljes dal, setlist-tétel) MOST már bekötve a
gamifikáció jutalom-láncába: `lib/features/songs/application/gamification_song_adapter.dart`
(ÚJ, kizárólag a gamification `public.dart`-on át importál; a `Song`
típust a `songs` feature SAJÁT `model/song.dart`-jából olvassa, a
`song_trainer/**`-hez nem nyúl). ADR: [`0391`](docs/adr/0391-song-gamification-adapter-standalone-bonus-and-hashed-song-id.md)
— a pre-flight mérés megcáfolta a 2026-08-18-i brief két állítását: (1) az
R06 `parentEventId` dedupja (ADR 0341) BINÁRIS mind-vagy-semmi — szó
szerinti használata a reális (szakaszok-előbb) sorrendben NULLÁRA, nem
csökkentett bónuszra ejtette volna a teljes dal jutalmát; (2) a dal
azonosítója (bizonyos kódutakon) cím-eredetű lehet, tehát a ledgerbe
KIZÁRÓLAG SHA-256-hashelt (16 hex karakter) alakban kerülhet. A javított
mechanizmus: minden `RewardPolicyRequest` önálló (`parentEventId: null`),
a bónusz-méretezés (alap egyszer + csökkentett bónusz, nem kétszeres, nem
nulla) az adapter SAJÁT, session-hatókörű könyveléséből adódik. Két
KÖTELEZŐ valódi-sértés próba ÁLLANDÓ regressziós tesztként megtartva
(`song_reward_flow_test.dart` §7): Probe 1 (bookkeeping kikapcsolva →
infláció PIROS) és Probe 2 (a `DefaultRewardPolicy`-t közvetlenül hívva,
`parentEventId`-vel → 0 XP mérve, megerősítve a bináris-dedup állítást).
A `songs` feature dal-haladása VÁLTOZATLAN (49/49 zöld). Az adapter MA
NINCS BEKÖTVE egyetlen hívóból sem (nincs UI/screen ebben a körben) — a
`security-reviewer` agent ezt függetlenül megerősítette, és rögzítette,
hogy a session/section/setlist-azonosítók ma nyersen (nem hash-elve)
kerülnek az `eventId`-be — ha egy jövőbeli bekötő kör cím-eredetű
session/section-id-t adna át, ugyanaz a hibaosztály nyílna meg egy MÁSIK
mezőn (`docs/reviews/e08-r25-review.md` F2, NOTE).

**Review APPROVED, javító kör nélkül** (`docs/reviews/e08-r25-review.md`):
0 BLOCKER/MAJOR. 1 MINOR (F1) — `hashedSongId()` belső `utf8Bytes()`
helper-je NEM valódi UTF-8 kódolás (a `String.codeUnits`-ot `& 0xff`-fel
maszkolja), ami elméletben nem-ASCII karaktereket tartalmazó azonosítóknál
ütközést okozhatna — MA nem elérhető (minden tényleges `Song.id`/`SongId`
forrás ASCII-only), triviális follow-up javítás (`utf8.encode()` a saját
helper helyett). **Kör közbeni process-hazárd:** a MiniMax implementer
`mm-round.sh` wrapper-je a `done` jelzés (05:14:52) UTÁN is tovább futott
(~20 percig), egy jogos, in-scope §10-korrekciós commitot készített
(`f7ade3e8`), majd az orchestrátor review-commitját egy `git pull --rebase`
után saját maga push-olta vissza (`180c8d40` — TARTALMILAG azonos az
orchestrátor eredeti `0d889cba` commitjával, csak más szülőn), és eközben
saját maga dispatch-elt egy `gh workflow run` CI-t is (ami nem az ő
szerepe). Az orchestrátor a folyamatot PID-del megölte (nem
`pkill -f`-fel), tartalom-vesztés nélkül — a jelenség naplózva a
git-notes `lesson=` mezőjében, `docs/LESSONS.md`-be is felveendő.

Mindkét CI (`full-gate.yml` run 32554547623, `router-ci.yml` run
32554548631/32554544697) zöld a pontos merge-jelölt SHA-n (`180c8d40`).

## ✅ E08-R24 KÉSZ — Practice Engine és Learn integráció — PR #401, squash `dc09f5fe` (2026-08-22)

A gyakorlási session és a lecke-befejezés eredménye MOST már bekötve a
gamifikáció jutalom-láncába (esemény → outbox → jogosultság → XP →
főkönyv): `lib/features/practice/application/gamification_practice_adapter.dart`
+ `lib/features/learn/application/gamification_lesson_adapter.dart` (mindkettő
ÚJ, kizárólag a gamification `public.dart`-on át importál, A4 architektúra-
guard védi). Meglévő R05/R06 kapuk (`ActivityOutcome.completed/cancelled/
failed`, `practiceOccurrenceCount` diminishing-returns) — nincs új szabály.
Lecke-csillagok és legjobb pontosság VÁLTOZATLANOK (`lesson_progress_repository.dart`
a diffben nem szerepel). Migrációs kapcsoló (`GamificationDualWriteMode.off/
dual/newOnly`) alapértéke KIKAPCSOLVA — a tényleges élő hívási pont
(`practice_session_controller.dart`, a `learn` eredmény-képernyő) a brief
tiltott zónájában maradt, KÉSŐBBI kör dolga. ADR: [`0390`](docs/adr/0390-practice-and-learn-gamification-adapter-boundary.md)
(a brief előre kiosztott `0317`-e stale volt, a foglaló `0390`-et adott).

**A review egy javító kört zárt (`docs/reviews/e08-r24-review.md`):** két
BLOCKER. **F1** — a lecke-adapter `stableEventId`-je a lecke KATALÓGUS-
azonosítójából (nem egy próbálkozás-szintű azonosítóból) számolt, tehát egy
adott lecke ELSŐ teljesítése után minden további teljesítés örökre elveszett
a ledger `appendIfAbsent` dedupja miatt (mérve, saját eldobható próbateszttel:
két különböző napi teljesítés → azonos `eventId` → 1 ledger-bejegyzés a 2
helyett). **F2** — a `GamificationLessonAdapter`/`recordLesson` nulla
tesztlefedettséggel landolt (`practice_reward_flow_test.dart` kizárólag a
practice adaptert gyakorolta) — ez az oka, hogy F1 zöld gate-en csúszott át.
A javító kör (`0853ae6e`) a `stableEventId`-et egy új, caller-fed
`attemptId` mezőből származtatja, és felvett egy teljes lecke-oldali A1/A3/
A5/A6/A7 tesztmátrixot + egy dedikált F1-regressziós cellát. Mindkét lelet
FIXED, saját, izolált `/tmp` klónban megismételt méréssel megerősítve
(scope-audit + próbateszt + teljes gate 8/8 zöld).

Mindkét CI (`full-gate.yml` run 32551495513, `router-ci.yml` run
32551519892) zöld a pontos merge-jelölt SHA-n (`33733eb6`).

## ✅ E08-R23 KÉSZ — Gamification Hub és level UI — PR #400, squash `384c89df` (2026-08-22)

Nem-domináló áttekintő felület: `gamification_hub_screen.dart` +
`level_detail_screen.dart` + `xp_progress_bar.dart`/`level_badge.dart` —
a `progress_screen.dart` (516 sor) marad az elsődleges napi fejlődés-
felület, érintetlenül (A7). A Hub level/XP-haladást, questeket, sériát,
mastery-összesítőt, legutóbbi eredményt és a postaláda-jelzőt (R22) mutatja
egy képernyőn, "Hogyan működik?" magyarázattal (R06 öt XP-komponens),
villogás/visszaszámláló nélkül (ADR 0290 §1), offline-projekcióból (nincs
főkönyv-újraszámolás megnyitáskor), 200%-os szövegskálán levágás nélkül.

**A review egy BLOCKER-t talált és zárt (F1, `docs/reviews/e08-r23-review.md`):**
a `LevelBadge` — bár VIZUÁLISAN helyesen elkülönült az XP-sávtól (kör medál
vs sáv) — a feliratában és szemantikájában **"Skill mastery"/"Measured
skill, not experience points"**-ot állított, miközben az egyetlen bemenete
(`profile.currentLevel`) egy kizárólag `totalXp`-küszöbökből számolt
`LevelDefinition` (`LevelCurve` — "the single source of truth for
monotonically increasing XP levels"), tehát a valóságban XP-derivált, nem
mért készség-bizonyíték — pontosan az az összemosás, amit az ADR 0289 és a
brief §5.1 a kör legfontosabb invariánsaként tilt. A hiba a §6.1 kötelező
valódi-sértés próbán ÁTCSÚSZOTT, mert az csak a widget-TÍPUS különbségét
mérte, nem a felirat TARTALMÁT (L403). Egy javító kör (`6c04dcf6`) az
"Level {level}" / "a szint a tapasztalati pontokból adódik" őszinte
framing-re cserélte a feliratokat (angolul ÉS magyarul), és egy ÚJ,
tartalom-alapú regresszió-őr tesztet adott — ezt a reviewer saját, független
valódi-sértés próbával igazolta (a régi hibás szöveget visszaírva a teszt
PIROSRA váltott, majd visszaállítás).

Mindkét CI (`full-gate.yml` run 32544553725, `router-ci.yml` run
32544579114) zöld a pontos merge-jelölt SHA-n (`cad80d7f`) — a review a
gate-et és a scope-audit-ot (`tools/scope-audit.py`) KÉTSZER, saját
izolált `/tmp` klónokban futtatta (a javítás előtt és után is).

## ✅ E08-R22 KÉSZ — Jutalom-postaláda és ünneplés-koordinátor — PR #399, squash `8bbe3715` (2026-08-22)

XP/beváltás-mentes, caller-fed ünneplés-koordinátor (ADR 0389, a brief
`0316` előre kiosztott száma stale volt, a foglaló `0389`-et adott —
ugyanaz a mintázat, mint az E08-R21/E08-R20-nál). Új
`lib/features/gamification/domain/profile/reward_inbox_item.dart` +
`application/celebration_coordinator.dart` (pure Dart, nincs Flutter-/
Riverpod-/`RewardLedgerRepository`-import) + `presentation/screens/
reward_inbox_screen.dart` + `presentation/widgets/reward_summary_sheet.dart`:
aktív gyakorlás közben SOHA nem jelenik meg felugró (§5.1, a jutalom a
postaládába kerül helyette), több szintlépés EGY összevont
összefoglalóban (§5.3, determinisztikus `switch`-alapú prioritás, nem
`Map`-bejárás), a postaláda NEM beváltás-mechanika (§5.2, nincs lejárat/
begyűjtés-gomb), reduced motion mellett az információ TELJES marad
(`MediaQuery.disableAnimationsOf`), haptika/hang caller-fed bool
(élő settings-provider még nincs, Kör 27 dolga).

Két mért kör-közbeni brief-revízió: **§0.0.1** — a 12 új ARB-kulcs a
GENERÁLT aggregátumba (`lib/l10n/app_{en,hu}.arb`) került az első
implementer-futásban a forrás-fragmentum (`lib/l10n/features/
gamification_{en,hu}.arb`) helyett (ugyanaz a hibaosztály, mint az
E08-R20 §0.0.1, L396) — egy javító kör a forrásba tette, az
aggregátumot regenerálta. **§0.0.2** — a merge előtti CI (`full-gate.yml`,
run 32538682580) a teljes suite alatt PIROS volt: `test/ui/
ui_inventory_test.dart` a 61-es baseline-t várta, az új
`reward_inbox_screen.dart` miatt 62 a valódi screen-szám — mechanikus
egysoros javító kör (`hasLength(61)` → `hasLength(62)`).

A review (`docs/reviews/e08-r22-review.md`) APPROVED, egy NOTE-tal (a
wrapper `gate_shape` heurisztikája hamis pozitívot adott, mert az
implementer a gate SCRIPTJÉNEK forrását `cat ... | head`-delte, nem
futtatta csonkítva — a nyers log tényleges Bash-hívásai mind tiszták
voltak). A review saját, izolált `/tmp` klónban futtatott valódi-sértés
próbát az A1 megszakítás-őrre (`isActiveSession` ág letiltva → 7 teszt
pirosra vált → visszaállítás → 18/18 zöld). **Mérve, jegyzésre méltó:**
a boxon egy PÁRHUZAMOS orchestrátor-session is dolgozott ugyanezen a
körön a `pipeline-slots=1` konfiguráció ELLENÉRE (mérve, nem
diagnosztizálva — a két session git-push-szinten békésen konvergált,
mindkét review APPROVED volt, a merge egyetlen, konzisztens tartalommal
zárult) — **follow-up**: a slot-kényszerítés versenyfeltétele
kivizsgálandó egy jövőbeli GOV-körben, mielőtt ismét bízunk benne.

Mindkét CI (`full-gate.yml` run 32540666809, `router-ci.yml` run
32540630020) zöld a pontos merge-jelölt SHA-n (`71a5dee6`); a
`tools/round-land.sh` a squash-merge előtt saját kombinált-HEAD gate-et
futtatott (zöld, a `tools/prepare-flutter-generated.sh` friss futása
után — enélkül a stale generált l10n-fájlok ugyanazt a hamis
undefined-getter hibát adták volna, amit a §0.0.1 javító kör már
egyszer elhárított).

## ✅ E08-R21 KÉSZ — Mastery mérföldkő domain és kiértékelő — PR #398, squash `26f83265` (2026-08-21, L399)

XP/ledger-mentes, több-sessionös, confidence-kapuzott, monoton mastery
kiértékelő (ADR 0289 legszigorúbb alkalmazása). Új `lib/features/
gamification/domain/mastery/` (`mastery_milestone.dart`, `mastery_progress.dart`,
`mastery_badge.dart`) + `application/mastery_evaluator.dart`: session-szintű
dedup inkluzív `minEvidenceSessions>=2` küszöbbel, `0.70`-es Vision/Analysis
confidence-kapu (`VisionClaimGuard` pozitív-claim precedenssel egyezően,
ADR 0388 3. döntés), és zárt mezőkészletű, privacy-safe, magyarázható
jelvény (`toSummary()` — nincs `sessionId`, `audio`, egészségügyi mező).

Az előre kiosztott `ADR 0315` a pre-flightban ütközőnek bizonyult (egy
korábbi, független kör azóta lefoglalta, `halt-guard-ledger.md`) — a
foglaló a tényleges szabad számot (**`ADR 0388`**) adta, a brief §0.0
revíziója ezt dokumentálja.

A review egy MAJOR-t talált és önálló próbával igazolt (L399): a monoton
(„egyszer elért mérföldkő nem regresszál") ág egy már elért progressre
`ArgumentError`-ral bukott, ha a friss evidence-batch KEVESEBB minősítő
session-t tartalmazott, mint a korábban tárolt érték — a beküldött `A5`
teszt csak azonos-vagy-nagyobb session-számú batch-csel bizonyított. Egy
MiniMax javító kör (`99c36e90`) a hívó oldalon `max(friss, korábbi)`
clampelést vezetett be és új tesztet adott a kisebb-batch esetre; a review
saját, független `/tmp` klónban futtatott gate-je (21/21 zöld) és
scope-audit-ja is megerősítette a javítást.

Mindkét CI (`full-gate.yml` run 32534927662, `router-ci.yml` run
32536016910 — utóbbi explicit `workflow_dispatch`-csel indítva, mert a
javító kör commitjai nem érintették a `docs/rounds/**` útvonalat, tehát a
push-trigger nem tüzelt volna a merge SHA-n) zöld a pontos merge-jelölt
SHA-n (`6df449a5`); a merge utáni `main`-en független gate-újrafutás
(`format+analyze+test+architecture+secrets+l10n`) szintén zöld.

## ✅ E08-R20 KÉSZ — Quest és kihívás felület — PR #397, squash `684e6334` (2026-08-21, L396–L398)

Áttekinthető napi/heti quest- és kihívás-élmény: `quests_screen.dart` +
`quest_card.dart`/`challenge_card.dart`. Beváltás (claim) gomb NINCS — a
teljesített küldetés jutalma automatikusan látszik (R16 §5.1); a lejárati
szöveg semleges, nincs visszaszámláló (ADR 0290 §1); a Start/Continue CTA
típusos (`QuestRouteAction` sealed hierarchia — `QuestStartPracticeAction`/
`QuestContinuePracticeAction`/`QuestTryLiveAction`/`QuestUnavailableAction`),
sosem szabad szöveges route; nem elérhető tartalomnál a CTA letiltott. Az
útvonal-REGISZTRÁCIÓ változatlanul a Kör 30-ra van halasztva.

Három dispatch volt szükséges, mindhárom mért, valódi ok miatt (nem
implementer-hibából): (1) az implementer jogosan `stopped`-ot jelzett, mert
`lib/l10n/app_en.arb`/`app_hu.arb` 2026-08-20 óta (ADR 0307 §4, PR #343)
GENERÁLT aggregátum — a brief 2026-08-18-i, nem ismerhette a váltást; §0.0.1
brief-revízió a tényleges forrást (`lib/l10n/features/gamification_{en,hu}.arb`)
vette fel az `allowed_paths`-ba (L396). (2) A célzott gate zöld volt, de az
első CI-dispatch (`full-gate.yml`) egyetlen, a kör saját `gate_tests`-én
kívüli tesztet buktatott: `test/ui/ui_inventory_test.dart` rögzített
60-elemű production-screen bázisvonala az ÚJ, jogos `quests_screen.dart`
miatt 61-re nőtt — ugyanaz a hibaosztály, mint az E08-R19
`architecture_dependency_test.dart` lelete (L395), most a screen-inventory
oldalon (L397); §0.0.2 brief-revízió + egysoros javító kör zárta.

A review saját mutáció-próbája (ideiglenes „Begyűjtés" gomb a production
`quest_card.dart`-on, `flutter test --plain-name "A1"` → PIROS, majd
visszaállítás) igazolta, hogy az A1 no-claim-button guard valódi, működő
védelem — a brief §6.1 KÖTELEZŐ próbáját az implementer egy szintetikus,
a production widgetet NEM mutáló teszttel „teljesítette", és a §10 handoff
üresen maradt (L398, MINOR, nem blokkolt). 0 BLOCKER/MAJOR, review APPROVED.

Mindkét CI (`full-gate.yml` + `router-ci.yml`) zöld a pontos merge-jelölt
SHA-n (`f9a5ea4e`); a merge utáni `main`-en független gate-újrafutás
(`format+analyze+2×test+architecture+secrets+l10n`) szintén zöld.

## ✅ E08-R19 KÉSZ — Challenge V2 és legacy napi kihívás migráció — PR #396, squash `a100ff9b` (2026-08-21)

Négy új, tipizált napi kihívás-típus (akkordváltás, ritmus, dal-szakasz,
időzítés) a meglévő, determinisztikus pengetés-minta generátor mellé — a
legacy `DailyChallenge.forDay` VÁLTOZATLAN, az adapter HÍVJA (nem
reprodukálja, `ADR 0387` Döntés 1). A napi példány azonosítója
`type|catalogVersion|epochDay`; a jutalom a meglévő reward-főkönyv
`appendIfAbsent`-jén megy át ugyanezzel a kulccsal, tehát az újrajátszás
szabad, a jutalom egyszeres. A katalógus-verzió a generáláskor rögzül —
egy nap közbeni app-frissítés nem cseréli ki az aznapi aktív kihívást.

Az előre kiosztott `ADR 0314` a pre-flightban ütközőnek bizonyult (egy
korábbi, független kör már lefoglalta) — a foglaló a tényleges szabad számot
(`ADR 0387`) adta, a brief §0.0 revíziója ezt dokumentálja (mérve, nem
`ls`-ből feltételezve, `AGENTS.md` §12).

A CI (`full-gate.yml`) a saját, szűk célzású `round-gate.sh`-nál szélesebb
kört mérve egy BLOCKER-t fogott: a `daily_challenge_service.dart`
`dart:math.Random`-ot használt a gamification `application/` rétegben, ami
sérti az E08-R08 „framework-free application layer" szabályt
(`test/core/architecture_dependency_test.dart`, nincs a kör két célzott
teszt-útvonalán, csak a teljes suite-ban). Egy MiniMax javító kör lecserélte
tiszta FNV-1a hash-projekcióra (`_projectHash(seed, discriminator)`), a
kódbázis meglévő `dailyQuestSortKey` mintáját követve — `dart:math` import és
`Random(` hívás nélkül. Mindkét CI-mátrix (`full-gate.yml`, `router-ci.yml`)
zöld a pontos merge-jelölt SHA-n (`331b8d97`); a merge utáni `main`-en
független gate-újrafutás (`format+analyze+3×test+architecture+secrets+l10n`)
szintén mind zöld.

Lecke: a kör-brief célzott gate-parancsa (`round-gate.sh` két teszt-útvonala)
nem fedte le a keresztmetsző architektúra-invariánsokat (`test/core/
architecture_dependency_test.dart` egy HARMADIK útvonalon él) — ez pontosan
azért mérce-rés, mert a saját review-gate-futásom is csak ezt a két
útvonalat futtatta újra. Jövőbeli gamification `application/`-réteget érintő
briefek gate-parancsába érdemes felvenni az architektúra-tesztfájlt is.

## ✅ E08-R18 KÉSZ — Rugalmas heti quest és consistency objective — PR #394 (2026-08-21, L394)

A pure, caller-fed heti generátor az elérhető percekkel egészértékűen skáláz,
az aktívnap-célt 3/4/5/6/7 napnál rendre 3/4/5/5/5-re korlátozza, és nulla
elérhetőségre nem gyárt kötelező questet. A négy típusos objective közül
stabil UTF-8/FNV-1a sorrenddel választ; improvement mérés nélkül fail-closed,
a rollover pedig nyelvfüggetlen, strukturált tényprojekció.

Az első Sol review két MAJOR rést talált. A scalar previous progress eltérő
replacement objective-re átvihető volt, a 3/7 availability-végpontok és a
`0..7` inputhatár pedig nem voltak közvetlenül őrizve. Egy Terra javító kör
után a progress stable quest ID-hoz kötött: same-ID esetén monoton maximum,
cross-ID esetben csak az új objective saját observed értéke számít. A cap és
az unconditional progress-transfer valódi mutációi pirosak; correctness
**APPROVED**, security **PASS**.

Exact `c131c47e`: Full Gate
[32472133400](https://github.com/wolfcasaba/strumsight/actions/runs/32472133400)
és Router CI
[32472092472](https://github.com/wolfcasaba/strumsight/actions/runs/32472092472)
success. PR [#394](https://github.com/wolfcasaba/strumsight/pull/394), squash
`29c27ab2`, ADR [0386](docs/adr/0386-flexible-weekly-quest-projection.md).
Pontos következő E08 kör: **E08-R19 — Challenge V2 és legacy DailyChallenge
migráció**.

## 🔧 [HEAL E13-R05/H3] Component Catalog scope helyreállítva (2026-08-21, L393)

Az E13-R05 javított `SsCard` kompozíciója helyesen egyetlen, az `SsSurface`
által birtokolt `Material`-réteget használ. A meglévő
`test/core/design_system/component_catalog_test.dart` route- és dark/light
smoke cellái azonban még legacy `Card` widgetet vártak. A PR #392 exact
`03788441` Full Gate-je emiatt 5519 zöld teszt mellett háromszor
`Found 0 widgets with type "Card"` hibát adott; a teszt nem szerepelt a kör
allowlistjében vagy célzott gate-jében. Ez B osztályú brief-scope hiány volt,
nem product- vagy gate-hiba.

A self-heal az E13-R05 briefet exact egyetlen meglévő fájllal bővítette:
`test/core/design_system/component_catalog_test.dart` bekerült az
`allowed_paths` és `gate_tests` listába, valamint az A8 tranzakciós
acceptance-cellába. A folytatott product körnek meg kell őriznie a route-kaput
és a két téma smoke contractját, miközben `SsCard`-ot és pontosan egy
`Material`-leszármazottat mér. Más design-system tesztút nem nyílt meg. A
regressziós `tools/tests/test_e13_r05_component_catalog_scope.py` a revízió
előtt 4/5 piros, utána 5/5 zöld; a teljes tooling suite 714 passed, 1 skipped
és 610 subtests passed. Branch: `heal/E13-R05-H3-1`; az exact-SHA Router CI és
a zöld squash-merge a `fixed` jelzés előfeltétele. A pontos következő Chapter
13 kör változatlanul **E13-R05**, a meglévő product-ág revideált scope-pal
történő folytatásával.

## ✅ E08-R17 KÉSZ — Determinisztikus, capability-safe napi quest generátor — PR #391 (2026-08-21, L388/L392)

Az offline, caller-fed generátor a nap + profil-pillanatkép + katalógusverzió
stabil FNV-1a seedjéből választ legfeljebb három, legalább egy rövid questet.
Kamera-, fiók- és cloud-hiány esetén fail-closed szűr, planned rest napon csak
opcionális rest-eligible eredményt ad, üres katalógusra, hiányzó tervre és új
profilra pedig local fallbacket készít. Permission-, repository-, óra- vagy
hálózathívást nem birtokol.

Az első Sol review két MAJOR mércerést talált. A Terra javító kör közvetlen
shipping-katalógus contractot adott, a H4 self-heal utáni második javítás pedig
camera/account/cloud tengelyenként két-entrys candidate poollal zárta a
truncation által elfedett regressziót. Mindhárom cross-wiring mutáció célzottan
piros; correctness **APPROVED**, security **PASS**. Exact `e96feef3`: Full
Gate [32465903185](https://github.com/wolfcasaba/strumsight/actions/runs/32465903185)
és Router CI
[32465903321](https://github.com/wolfcasaba/strumsight/actions/runs/32465903321)
success. PR [#391](https://github.com/wolfcasaba/strumsight/pull/391), squash
`a2ea758d`, ADR [0384](docs/adr/0384-deterministic-capability-safe-daily-quest-generation.md).
Pontos következő E08 kör: **E08-R18 — Heti quest és consistency objective**.

## ✅ E13-R04 KÉSZ — Accessible typography és text-scale resilience — PR #389 (2026-08-21, L389–L391)

Az immutable `SsTypography` a Chapter 13 teljes Poppins/Montserrat scale-jét
theme extensionként adja mindhárom design-system témához. A metric tokenek
tabular figures-t használnak, a value/unit helper nem törő szóközt ad, az
adaptív `SsChordHeroText` pedig a platform text scale megtartásával és
ellipszis nélkül skáláz le a rendelkezésre álló helyre. A hosszú magyar
fixture 1.0/1.3/2.0/2.5 skálán renderelhető.

Az első független Sol review egy MAJOR leletet reprodukált: a chord hero a
kézi label és a gyermek `Text` miatt kétszer került a semantics fába. Egy
Terra javító kör után `excludeSemantics: true` és exact label-regresszió zárja
a rést; correctness **APPROVED**, security **PASS**. Exact `55832396`: Full
Gate [32462896738](https://github.com/wolfcasaba/strumsight/actions/runs/32462896738)
és Router CI
[32462873685](https://github.com/wolfcasaba/strumsight/actions/runs/32462873685)
success. PR [#389](https://github.com/wolfcasaba/strumsight/pull/389), squash
`57d034be`, ADR [0383](docs/adr/0383-typography-and-text-scale-contract.md).
Pontos következő Chapter 13 kör: **E13-R05 — Spacing, radius, elevation és
surface primitives**.

## 🔧 [HEAL E08-R17/H4] Capability-axis mérce izolálva — PR #390 (2026-08-21, L388)

Az E08-R17 független review-ja az `account → cloud` production-mutációval
bizonyította, hogy a javító kör három availability-cellája közül az account
teszt hamisan zöld: a shipping katalógus négy eligible candidate-jéből a
max-3 korlát épp a hibás account questet vágta le. A production mapping helyes;
a halt B osztályú brief/mérce-contract rés volt.

A self-heal a product allowlist és gate bővítése nélkül előírta a camera,
account és cloud tengelyek külön, két-entrys candidate poolját (local short +
csak a vizsgált capability), a teljes shipping katalógushoz pedig megőrizte a
külön metadata-contract cellát. Mindhárom keresztkötési mutációnak célzottan
pirosnak kell lennie. A regressziós
`tools/tests/test_e08_r17_capability_axis_contract.py` a régi briefen 6
hibával piros, a revízió után 5 teszt + 6 subtest zöld; a teljes tooling suite
709 passed, 1 skipped és 610 subtests passed. Branch:
`heal/E08-R17-H4-1`, PR
[#390](https://github.com/wolfcasaba/strumsight/pull/390). Az exact végső SHA
Router CI success és squash-merge a `fixed` jelzés előfeltétele. A pontos
következő E08 termékkör változatlanul **E08-R17**, a revideált mércével.

## 🔧 [HEAL E13-R04/H3] Typography compatibility scope helyreállítva — PR #388 (2026-08-21, L387)

Az E13-R04 pre-flight ADR 0383 §D3-a az `SsTypography` tényleges
`ThemeData`-extension regisztrációját írja elő. A meglévő
`test/core/design_system/foundations_test.dart` ezzel szemben közvetlenül az
extension nélküli `AppTheme.dark()`/`light()` eredménnyel várta egyenlőnek a
legacy adaptert, de ez a teszt nem szerepelt a kör allowlistjében vagy célzott
gate-jében. A Terra implementer helyesen `stopped` jelzést adott production
módosítás nélkül; a halt B osztályú brief-scope hiány volt.

A self-heal az E13-R04 briefet exact egyetlen meglévő fájllal bővítette:
`test/core/design_system/foundations_test.dart` bekerült az `allowed_paths`
és `gate_tests` listába, valamint az A8 kompatibilitási cellába. A folytatott
product kör ugyanabban a commitban őrzi a legacy theme-forrás paritását és
méri az új extensiont; más design-system tesztút nem nyílt meg. A regressziós
`tools/tests/test_e13_r04_typography_foundations_scope.py` a revízió előtt
4/5 piros, utána 5/5 zöld; a teljes tooling suite 704 passed, 1 skipped és
604 subtest passed. Branch: `heal/E13-R04-H3-1`, PR
[#388](https://github.com/wolfcasaba/strumsight/pull/388). Router CI success
az exact végső SHA-n és squash-merge a `fixed` jelzés előfeltétele. A következő
Chapter 13 kör változatlanul **E13-R04**, a meglévő product-ág folytatásával.

## ✅ E08-R16 KÉSZ — Quest domain, objective és lifecycle — PR #387 (2026-08-21, L384–L385)

A framework- és IO-mentes quest domain zárt, típusos objective-vokabulárt,
verziózott napi/heti schedule-t, ötállapotú életciklust és automatikus,
claim nélküli reward receiptet ad. Az aktivitási felső határ exkluzív; expiry
megőrzi a valós progress/evidence adatot. Ugyanazon quest-instance ismételt
completionje változatlan receiptet ad, más generation day vagy cadence pedig
külön instance identityt kap.

Az első független Sol review két MAJOR leletet talált: a katalógus-ID alapú
receipt a következő napi példány jutalmát deduplikálta volna, a persisted
completed rekord pedig megkerülhette a receipt- és expiry-invariánst. Egy
Terra javító kör után mindkettőt regressziós cella zárja; correctness
**APPROVED**, security **PASS**. Exact `e4ececf4`: Full Gate
[32454251927](https://github.com/wolfcasaba/strumsight/actions/runs/32454251927)
és Router CI
[32454084052](https://github.com/wolfcasaba/strumsight/actions/runs/32454084052)
success. PR [#387](https://github.com/wolfcasaba/strumsight/pull/387), squash
`1e7ed2a3`, ADR [0382](docs/adr/0382-quest-objective-and-lifecycle-contract.md).
Pontos következő E08 termékkör: **E08-R17 — Napi quest generátor**.

## ✅ E13-R03 KÉSZ — Semantic colors and three themes — PR #386 (2026-08-21, L381–L383)

Az új, 23 mezős `SsColorScheme`, a névvel ellátott state overlayek és az
`SsThemeBehavior` egyetlen contractban adják a Dark Studio, Warm Light és
High Contrast témát. A confidence-, offline-, local-AI- és cloud-AI
állapotok páronként külön ikonmarkert kapnak, ezért jelentésük nem csak
színből olvasható. A Component Catalogban a három téma fejlesztői kapcsolóval
ellenőrizhető; a production theme-mode wiring és a legacy olvasási út
változatlan maradt.

Az első független Sol review két MAJOR leletet talált: a kontraszt-CLI a WCAG
sRGB 2,4-es hatványa helyett köbözött, a marker-tesztek pedig nem buktatták az
azonos ikonokra rontást. Egy Terra javító kör után canonical luminancia-vektor
és két all-same marker őr zárja ezeket; correctness **APPROVED**, security
**PASS**. Exact `3fc36778`: Full Gate
[32451933445](https://github.com/wolfcasaba/strumsight/actions/runs/32451933445)
és Router CI
[32451919508](https://github.com/wolfcasaba/strumsight/actions/runs/32451919508)
success. PR [#386](https://github.com/wolfcasaba/strumsight/pull/386), squash
`6e80a441`. Következő Chapter 13 kör: **E13-R04 — Typography and text-scale
resilience**.

## ✅ E08-R15 KÉSZ — Privacy-safe Achievement UI és 60-screen baseline — PR #383 (2026-08-21, L377/L380)

A caller-fed achievement lista és detail UI all/unlocked/in-progress/category
szűrőket, exact-ID kiválasztást, lokalizált üres/not-found állapotot és
1.99/2.0/2.01/3.0 text-scale kompatibilitást ad. Locked hidden állapotban cím,
leírás, progressz, kategória és evidence a widget- és semantics-fából is
hiányzik. Az evidence contract zárt reason code-ot és runtime-validált,
aggregált current/target értéket fogad; Analyze/session/raw audio adatot nem.

Az E08-R15/H3 self-heal után a két új screen ugyanabban a termék-tranzakcióban
emelte 58-ról 60-ra az UI inventoryt, miközben az AppRoutes/GoRoute baseline
40 maradt az E08-R30 wiringig. Implementer Terra, reviewer/orchestrátor Sol;
correctness **APPROVED**, security **PASS**. Exact `d4414f49`: Full Gate
[32449877483](https://github.com/wolfcasaba/strumsight/actions/runs/32449877483)
és Router CI
[32449853724](https://github.com/wolfcasaba/strumsight/actions/runs/32449853724)
success. PR [#383](https://github.com/wolfcasaba/strumsight/pull/383), squash
`22f5e1a0`. Következő E08 termékkör: **E08-R16 — Quest domain, objective és
lifecycle**.

## ✅ E13-R02 KÉSZ — Design System Foundation és compatibility layer — PR #384 (2026-08-21, L378–L379)

Az új `lib/core/design_system/public.dart` mögött megjelentek a kipinnelt
breakpoint-, spacing-, radius-, motion- és semantics-foundationök. A
`SsThemeExtensions` az átmeneti kompatibilitási rétegben közvetlenül a
meglévő `AppTheme`, `AppColors` és `AppPalette` API-kra delegál, ezért nincs
második színforrás. A Component Catalog csak a default-OFF compile-time flag
ÉS debug-build együttes teljesülésekor hoz létre route-ot; maga a screen
privát. Az architektúra-őr tiltja a feature-importot és a design-system
barrel megkerülését.

Implementer: Terra (`gpt-5.6-terra`), egy javító körrel. A Sol
(`gpt-5.6-sol`) független correctness review-ja **APPROVED**, a security
review **PASS**. A review mutációval pirosra vitte a másolt brand-színt, a
feature-importot és a debug-kapu kivételét; a privát catalog screenre tett
külső hivatkozás fordítási hibát adott. Exact branch-csúcs `05ec6276`: Full
Gate [32447387921](https://github.com/wolfcasaba/strumsight/actions/runs/32447387921)
és Router CI [32447381563](https://github.com/wolfcasaba/strumsight/actions/runs/32447381563)
success. PR [#384](https://github.com/wolfcasaba/strumsight/pull/384), squash
`8bd7dc98`. Következő Chapter 13 kör: **E13-R03 — Semantic colors and
themes**.

## 🔧 [HEAL E08-R15/H3] UI-inventory tranzakciós scope helyreállítva — PR #385 (2026-08-21, L377)

Az E08-R15 PR #383 két új achievement presentation screennel 58-ról 60-ra
emeli az E13-R01 production screen inventoryját. A Full Gate exact SHA-n 5442
tesztet zölden futtatott, és kizárólag a változatlan 58-as inventory-őr bukott.
A kör briefje nem engedte a teszt és a hozzá tartozó baseline-dokumentáció
frissítését, ezért a H3 megállás helyes volt.

A Class B self-heal nem emeli előre 60-ra a `main`-alapú Dart-tesztet, mert a
két product screen ezen az ágon még nincs jelen. Ehelyett az E08-R15 brief
exact három fájllal bővült: `test/ui/ui_inventory_test.dart`,
`docs/ui/migration-status.md`, `docs/ui/baseline/route-map.md`; az inventory-
teszt a kör második gate-tesztje. Az E08-R15 resume ugyanabban a product-
commitban frissíti a screen countot, a két exact útvonalat és az R30-ig fennálló
route-wiring kockázatot. Más `docs/ui/**`/`test/ui/**` út nem nyílt meg.

A regressziós `tools/tests/test_e08_r15_ui_inventory_scope.py` a revízió előtt
4/5 piros, utána 5/5 zöld. Branch: `heal/E08-R15-H3-1`; Router CI és squash-
merge a `fixed` jelzés előfeltétele. A merge után a pontos következő kör
változatlanul **E08-R15 — Achievement UI és részletes evidence**, a meglévő
PR #383 folytatásával és új exact-SHA Full Gate futással.

## ✅ [HEAL E13-R01/H8] KÉSZ — a duplikált körtörténet tiszta recovery PR-rel helyreállt — PR #382 (2026-08-21, L376)

Az E13-R01 eredeti PR-jének (`#381`, csúcs `31aab305`) története a tiszta,
rebase-elt `87f247f8` csúcs mögé visszamerge-elte a régi pre-rebase láncot.
A 12 nem-merge commit ezért pontosan hat, páronként azonos stabil patch-id-t
tartalmazott. A már merge-elt H8-SELFDUP őr helyesen blokkolta a landolást;
az eredeti PR-t force-push nélkül lezártuk, így a sérült történet auditálható
maradt.

A `heal/E13-R01-H8-1` recovery ág a jelenlegi `origin/main` fölött a hat
egyedi, már függetlenül APPROVED E13-R01 commitot tartalmazza. A recovered fa
byte-azonos a sérült PR fájával (`git diff --exit-code 87f247f8 31aab305` →
0), de csak hat egyedi patch-id maradt. A valós régi-csúcs-visszamerge fixture-t
tartalmazó `tools/tests/test_round_land.py` 13 tesztet és 3 subtestet zölden
futtatott; a teljes E13-R01 round-gate 7/7 zöld. A Full Gate és Router CI
exact-SHA bizonyítéka a recovery PR merge-feltétele; piros vagy eltérő SHA
esetén nincs merge.

Implementer: Terra (`gpt-5.6-terra`); független correctness reviewer és H8
self-heal orchestrátor: Sol (`gpt-5.6-sol`). Product tartalom nem változott a
javítás során. Következő Chapter 13 kör: **E13-R02 — Design System Foundation**,
új sessionben.

## ✅ E08-R14 KÉSZ — Achievement evaluator és progress projection — PR #380, squash `558b1258` (2026-08-21, L374–L375)

Az indexelt evaluator canonical event-historyból, stabil event-ID deduppal
építi újra a count, threshold, distinct, sequence és compound progresszt. Az
unlock exact `achievement:<id>` source-on atomikus, nulla-XP ledger receipt;
a completion timestamp a trigger eventből jön. A caller-anchored backfill
inkluzív 30 napos ablakot és nyers 10 000-es hard capet őriz, unknown vagy
ütköző evidence pedig fail-closed diagnosztikát ad.

Terra implementáció, Sol correctness/security review: **APPROVED / PASS**.
Három implementer-fázis scope-auditja zöld; a végső round-gate 6/6, a célzott
suite 11/11. Exact `b8b25721`: Full Gate
[32439860548](https://github.com/wolfcasaba/strumsight/actions/runs/32439860548)
és Router CI
[32439873084](https://github.com/wolfcasaba/strumsight/actions/runs/32439873084)
success. Következő termékkör: **E08-R15 — Achievement UI és részletes
evidence**, új sessionben.

## ✅ E08-R13 KÉSZ — Achievement domain és lokalizált katalógus — PR #376, squash `f9d5bbc8` (2026-08-21, L372–L373)

A gamification feature 22 stabil ID-jú, EN/HU lokalizált achievementből álló
verziózott katalógust kapott. A domain típusosan kezeli a count, threshold,
distinct, sequence és compound feltételeket; runtime validáció őrzi az
egyedi ID-kat, a tier-ciklus mentességét, a teljes lokalizációt, a korábbi
verzió ID-folytonosságát és a véges, monoton progresszértékeket. A
deprekáció megőrzi a már kiosztott achievement identitását.

Implementer Terra (`gpt-5.6-terra`), orchestrátor/reviewer Sol
(`gpt-5.6-sol`). Az első független review két MAJOR leletet talált: azonos
elemszám mellett eltűnhetett egy korábbi ID, továbbá `NaN`/végtelen küszöb és
progressz átjuthatott. Egy Terra javító kör után correctness **APPROVED** és
security **PASS**; a cycle-, retention- és finite-őr eldobható mutációi
célzottan pirosak, restore után 20/20 teszt zöld. Exact `679f030f`: Full Gate
[32433372231](https://github.com/wolfcasaba/strumsight/actions/runs/32433372231)
és Router CI
[32433323271](https://github.com/wolfcasaba/strumsight/actions/runs/32433323271)
success. Döntés: [ADR 0374](docs/adr/0374-achievement-domain-and-catalog-contract.md).
Következő termékkör: **E08-R14 — Achievement evaluator és progress
projection**; a másik sloton E13-R01 fut.

## ✅ [HEAL E13-R01/H3] KÉSZ — a hét screenshot és corpus-validátor exact scope-ja helyreállt — PR #377, squash `c505b26f` (2026-08-21, L371)

A Chapter 13 Kör 1 név szerint hét compact-portrait referencia screenshotot
(Live, Tuner, Analyze, Learn, Library, Settings, onboarding) és azok
megnyithatósági/nem-ürességi tesztjét kéri, de az előre megírt E13-R01 brief
egyetlen screenshot- vagy corpus-teszt útvonalat sem engedett. Ez Class B
brief-tartalmi ellentmondás volt; az implementer nem indult el, product diff és
kör-PR nem keletkezett.

A self-heal az SDD-t változatlanul hagyta, `lib/**`-ot nem nyitott meg, hanem
hét exact `docs/ui/baseline/screenshots/*-compact-portrait.png` fájllal és az
egy `test/ui/ui_baseline_screenshot_test.dart` validátorral bővítette a briefet.
A validátor a hét fájlt enumerálja, ténylegesen dekódolja, és pozitív byte- és
pixelméretet plusz portrait képarányt kér; a reviewer mind a hét képet manuálisan
is megnyitja. A `tools/tests/test_e13_r01_screenshot_scope.py` a javítás előtt
4/5 piros, utána 5/5 zöld, és bizonyítja, hogy egy nyolcadik testvérkép továbbra
is scope-sértés. Következő érintett SDD-kör: **E13-R01 — UI baseline inventory
és screenshot corpus**, friss sessionben, a javított briefből.

Branch: `heal/E13-R01-H3-1`; javítási commit: `27e5fc51`; PR:
[#377](https://github.com/wolfcasaba/strumsight/pull/377). A célzott őr
5/5 zöld, strict és open/base brief-lint leletmentes, a teljes tooling-suite
694 passed / 1 skipped / 605 subtest. Izolált klónban a broad screenshot-
directory grant 2/5 cellát pirosra vitt, restore után 5/5 zöld és tiszta fa.
Az exact `27e5fc51` Router CI
[32432394840](https://github.com/wolfcasaba/strumsight/actions/runs/32432394840)
success; Dart/native fájl nem változott, ezért APK/Full Gate nem volt kapu.

## ✅ E99-R22 (GOV-16) KÉSZ — ismétlődő halt-osztályok őrteszt-főkönyve — PR #375, squash `ebff600c` (2026-08-20, L370)

A stdlib-only, READ-ONLY `tools/halt-ledger.py` a verziókövetett
`.pipeline/halted-*.txt` rekordokat halt-osztályonként összesíti, és a
`docs/LESSONS.md` félkövér `**Őrteszt:**` hivatkozásai alapján `fedett`,
`hiányzik` vagy egyszeri `nem jelölt` állapotot ad Markdown és JSON alakban.
A figyelmeztetési határ pontosan két előfordulás; a CLI nem blokkol és valid
futásnál mindig 0-val tér vissza. A pipeline záró rituáléja mostantól halt
utáni leckénél gépi őrhivatkozást vagy kimondott hiányt kér.

Implementer Terra (`gpt-5.6-terra`), reviewer/orchestrator Sol
(`gpt-5.6-sol`). A független review APPROVED, 0/0/0/0 lelettel; a szóhatár
egyszerű részszöveg-keresésre és a `>= 2` küszöb `>= 1`-re rontása célzottan
piros lett, restore után 7/7 zöld. A végső, upstream-szinkronizált HEAD-en a
scope-audit 5 útvonalat látott (1 generated/ignored review), sértés nélkül;
a round-gate 6/6 zöld, a tooling gate 688 passed / 2 skipped / 606 subtest.
Exact `ee053ba8`: Full Gate
[32429315526](https://github.com/wolfcasaba/strumsight/actions/runs/32429315526)
és Router CI
[32429329475](https://github.com/wolfcasaba/strumsight/actions/runs/32429329475)
success. Az E08-R13 már fut a másik sloton; utána a következő termékkör
**E08-R14 — Achievement evaluator és projection**. A következő governance-kör
**E99-R23** jelenleg `hold`.

## ✅ [HEAL E08-R13/H3] KÉSZ — az achievement-fordítások source-segment scope-ja helyreállt — PR #373 (2026-08-20, L369)

Az E08-R13 brief 20–30 achievementhez új lokalizált cím-, leírás- és
akadálymentességi kulcsokat kért, de az E99-R17 óta generált
`lib/l10n/app_en.arb` és `app_hu.arb` aggregátumokat engedte elsődleges
szerkesztési pontként. A kötelező
`lib/l10n/features/gamification_{en,hu}.arb` forrásszegmensek hiányoztak az
allowlistből, ezért a kör a jóváhagyott scope-on belül nem volt
megvalósítható. Ez Class B brief-hiba, nem router baseline-drift és nem
külső szolgáltatási akadály.

A H3 scope-revízió a gamification-szegmenseket nevezi elsődleges forrásnak,
a két aggregátumot csak determinisztikus kimenetként engedi, és kötelezővé
teszi a `dart run tool/gen_l10n_segments.dart --write` lépést. A valódi
briefadatot olvasó `tools/tests/test_e08_r13_l10n_scope.py` a javítás előtt
2/2 piros, utána 2/2 zöld; strict brief-lint: nincs lelet; teljes
Python/router gate: 682 passed, 1 skipped, 604 subtests passed. Branch:
`heal/E08-R13-H3-1`, javítási commit: `24492a53`, PR:
[#373](https://github.com/wolfcasaba/strumsight/pull/373). Lecke: **L369**.
Következő SDD-kör továbbra is: **E08-R13 — Achievement domain és
katalógus**, friss sessionben, a javított briefből.

## ✅ E08-R12 KÉSZ — együttérző Streak UI V2 és recovery flow — PR #367, squash `8aa0010b` (2026-08-20)

A gamification feature caller-fed, passzív Streak V2 képernyőt kapott current,
longest, total days, freeze és 0–7 heti consistency kártyákkal. A broken
állapot kimondja, hogy a megszerzett tudás megmarad, a recovery CTA egyetlen
hívó-adta callbacket indít büntető countdown nélkül, a planned rest külön
védett állapot. A legacy `/streak` route változatlan; a későbbi wiring-kör
köti be a V2 képernyőt. A layout 1.0/2.0/3.0 text scale mellett görgethető,
teljes semantics címkéket ad, reduced motionnál pedig csak az átmenet ideje
lesz nulla.

Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Az első
review egy MAJOR copy-őr hiányt és egy MINOR angol plural hibát talált; az egy
javító kör után correctness és high-risk security review is APPROVED, nyitott
lelet nélkül. A végső scope-audit 12 útvonalat, 2 generated/ignored
review-jelentést és 0 sértést adott. A kombinált-HEAD gate 7/7 zöld (21 V2 +
20 legacy streak teszt); a fix 80 px magasság, storage-import és tiltott
broken-copy mutációk célzottan pirosak, restore után zöldek.

Exact reviewed head `fe175652`: Full Gate
[32406555330](https://github.com/wolfcasaba/strumsight/actions/runs/32406555330)
és Router CI
[32406581869](https://github.com/wolfcasaba/strumsight/actions/runs/32406581869)
success. PR [#367](https://github.com/wolfcasaba/strumsight/pull/367), squash
`8aa0010b`; ADR 0353. Következő SDD-kör: **E08-R13 — Achievement domain és
katalógus**, új sessionben.

## 📐 [TERV] Chapter 14 briefek: E14-R15…R19 — a strum recovery blokk mérési fele (2026-08-20)

**User-kérés:** „mehetsz tovább". A Chapter 14 §8 harmadik blokkja (R15–R24,
strum onset + direction recovery) első öt köre — mindegyik **mérés és döntés**,
nem hangolás: a production DSP-konstans egyikben sem mozdul.

| Kör | Tárgy | ADR |
|---|---|---|
| `E14-R15` | hard-negative taxonómia (10+ kategória) + **false visible arrow/chord per perc** termék-metrika | 0367 |
| `E14-R16` | canonical SuperFlux A/B (current / 24 sáv-oktáv / complex-domain / simple flux) CPU+latency-vel; a production konstans ÉRINTETLEN | 0368 |
| `E14-R17` | referencia-modell reprodukció + **külön** kód/checkpoint/dataset licenc-audit, gépi licenc-őrrel | 0369 |
| `E14-R18` | joint streaming onset+direction prototípus, verziózott IO-sémával; go/no-go az Alpha kapuhoz kötve | 0370 |
| `E14-R19` | augmentáció seedelve/manifestelve/kikapcsolhatóan + ablation; romló subgroup → nincs automatikus elfogadás | 0371 |

**Két mért tény, amire a briefek épülnek** (a pre-flight ezeket kéri újra):
`ml/negatives.py` (r174) rögzíti, hogy a heurisztikus onset ~minden hatodik
onsetje hamis, és a direction-CRNN ezekre ugyanolyan magabiztos (medián raw
0,94 vs 0,97) — **a confidence önmagában nem szűr**, ezért kell a no-strum
osztály ÉS a termék-oldali hamis-esemény metrika; `ml/augment.py` (r173)
PCM-szintű augmentációja pedig MÁR LÉTEZIK, tehát az R19 bővít és bizonyít,
nem újraír.

**Két kutatási kör (`R17`, `R18`) `blocked`-dal zárhat**, ha a research-
környezet vagy a checkpoint nem elérhető ezen a boxon — a brief ezt KÖTELEZŐ
úttá teszi (Chapter 14 §9/9: hiányzó környezetnél tilos sikeres verifikációt
állítani).

**Mérve:** `brief-lint --level strict` mind az öt briefre → nincs lelet;
`brief-lint --open --level base` → nincs lelet. A sorok `prepared`-ek.

**Hátralévő Chapter 14:** R20–R42 (strum tanítás grouped holdouttal, chord
recovery, adaptív termék-UI, field validation és rollout).

## ✅ [HEAL E08-R12/H8] KÉSZ — a publikus kör-ág veszteségmentesen tartalmazza a friss `main`-t — PR #371 (2026-08-20, L367)

Az E08-R12 landolója a friss `main`-re rebase-elte a kör hét nem-merge
commitját, majd a safe-force-push négy remote-only commitot talált: három
korábbi upstream-merge-et és a `524cf246` pre-flight briefet. Az izolált
cherry-pick próba pontosan a kör briefjén adott content-konfliktust. A
`main`-oldal bizonyítottan tartalmazta a merge-elt H6 scope-revíziót
(`425ad1d7`, PR #365), ezért a H8 brief-history protokoll volt alkalmazható.

A távoli PR-csúcsról (`02ae43af`) indított `git merge --no-ff origin/main`
konfliktus nélkül létrehozta a `c6a96fc1` csúcsot; a brief 73 soros
implementation handoffja és a H6 allowlist egyszerre megmaradt. A helyreállított
fa byte-azonos a korábban teljes round-gate-en zöld rebase-elt fával,
`origin/main` bizonyított őse a csúcsnak, és normál push történt force nélkül.
A H8 regressziós teszt 1/1 zöld; az exact-SHA Router CI
[32402823817](https://github.com/wolfcasaba/strumsight/actions/runs/32402823817)
success. A kör saját PR-je [#367](https://github.com/wolfcasaba/strumsight/pull/367)
nyitva marad; a következő firing ezen a helyreállított ágon folytatja a
landolást. Következő SDD-kör továbbra is: **E08-R12 — Streak UI V2 és recovery
flow**.

## ✅ [HEAL E08-R12/H3] KÉSZ — a presentation Flutter-függése és storage-határa külön őrzött — PR #369 (2026-08-20, L366)

Az E08-R12 exact-SHA Full Gate futása a három, brief által kötelező
gamification UI-fájlt azért utasította el, mert az E08-R08 architektúra-teszt
ugyanazzal a markerlistával vizsgálta az application és presentation réteget.
Ez a presentationben a legitim `package:flutter/` importot is tiltotta,
miközben az eredeti A5 szerződés csak a közvetlen storage-import kizárását
kérte ezen a rétegen.

A javított őr az application rétegben továbbra is tiltja a frameworköt,
storage-ot, faliórát és random forrást; a presentationben külön markerlista
tiltja a `SharedPreferences`, secure-storage és sqflite közvetlen importját,
de engedi a Flutter UI-t. A CI-ben mért három útvonalat használó regressziós
cella a javítás előtt fordítási hibával piros, utána zöld lett; egy ideiglenes
presentation `SharedPreferences` import a valódi-sértés próbában továbbra is
pirosra vitte az őrt. Lokális `tools/round-gate.sh
test/core/architecture_dependency_test.dart`: 6/6 zöld, 26/26 teszt.

Branch: `heal/E08-R12-H3-1`; PR: [#369](https://github.com/wolfcasaba/strumsight/pull/369).
Az E08-R12 saját PR-je [#367](https://github.com/wolfcasaba/strumsight/pull/367)
nyitva marad, mert a pipeline perzisztens queue-azonosítása saját kör-PR-ként
ismeri fel; a következő firing a heal merge-je után ugyanazt a kört folytatja.
Következő SDD-kör továbbra is: **E08-R12 — Streak UI V2 és recovery flow**.

## ✅ [HEAL E08-R12/H6] KÉSZ — generált l10n aggregátum helyett feature-szegmens scope — PR #365 (2026-08-20, L365)

Az E08-R12 Terra implementere a brief szerint közvetlenül módosította a
`lib/l10n/app_en.arb` és `app_hu.arb` fájlokat, de ezek E99-R17 óta generált
aggregátumok. A kötelező round-gate ezért reprodukálhatóan mindkét locale-ra
aggregate-freshness hibával állt meg; a generátor futtatása a hiányzó
forrás-szegmensek miatt eldobta volna az új kulcsokat. Ez Class B brief-hiba
volt, nem router baseline-drift és nem az E08-R10/L360 egyszeri
motor-kimenetcsonkítása.

A javított, kanonikus pre-flight brief név szerint engedi a
`lib/l10n/features/gamification_{en,hu}.arb` forrás-szegmenseket és a két
deterministikusan regenerált aggregátumot, tiltja az output közvetlen
szerkesztését, és előírja a `dart run tool/gen_l10n_segments.dart --write`
lépést. A `tools/tests/test_e08_r12_l10n_scope.py` a javítás előtt 2/2 piros,
utána 2/2 zöld volt; strict brief-lint: nincs lelet; teljes Python/router gate:
680 passed, 1 skipped, 587 subtests passed. A kör production diffje a Terra
worktree-ben érintetlen maradt; a következő firing ugyanazt az E08-R12 kört
folytatja az új source-segment contracttal. Lecke: **[[L365]]**.

## 📐 [TERV] Chapter 14 briefek: E14-R10…R14 — a „truthfulness és UX hotfix" blokk (2026-08-20)

**User-kérés:** „mehetsz tovább" — a Chapter 14 briefelésének folytatása az
R01–R09 blokk lezárása után. Ez az öt kör az, amelyik a user MÉRT panaszára
válaszol („hiába van kész a backend, az APK-n nem látszik semmi"): itt lesz
először igaz és látható a felismerés a felületen.

| Kör | Tárgy | ADR | Előfeltétel |
|---|---|---|---|
| `E14-R10` | direction abstention: bizonytalan iránynál NINCS ↓/↑ nyíl; a user-küszöb nem mehet a biztonsági minimum alá; a bizonytalan esemény nem hibás esemény a pontozásban | 0362 | R04 + R08 |
| `E14-R11` | külön chord- és strum-confidence, `noChord`/`unknownChord`/`lowSignal`, százalék helyett szöveges állapot | 0363 | R04 |
| `E14-R12` | `RecognitionStabilizer` (Free/Guided profil): provisional → confirmed, immutábilis esemény, nincs timeline-churn | 0364 | R04 |
| `E14-R13` | Live UI truthfulness: egy fő üzenet, history lenyitva NEM alapértelmezett, ok-szöveg bizonytalanságnál, 200% textscale | 0365 | R11 + R12 |
| `E14-R14` | Audio Setup és Accuracy Check lépés-gép + eszköz-profil (képernyő nélkül, §0.0 drift) | 0366 | R05 + R11 |

**Kötött döntés minden körben:** a shipping DSP/ML konstans NEM mozdul
(AGENTS.md §9) — az R10 kapuja a classifier FÖLÉ kerül, nem bele; a küszöb
held-out kalibrációs halmazon MÉRT érték, a `docs/eval/`-ban a futtatott
paranccsal együtt. Az `E14-R14` `risk = "high"` (mikrofon + eszköz-profil),
indoklás-sorral; a többi `normal`.

**Mérve:** `python3 tools/brief-lint.py --brief <mind az öt> --level strict` →
nincs lelet; `python3 tools/brief-lint.py --open --level base` → nincs lelet.
A sorok `prepared`-ek: a futó prioritás változatlanul a Chapter 13 UI-sáv.

**Hátralévő Chapter 14:** R15–R42 (hard-negative corpus, strum recovery,
chord recovery, adaptív termék-UI, field validation) — briefek még nincsenek.

## 📝 [TERV] Chapter 14 — az E14-R06…R09 briefjei megírva: a mérési blokk (R01–R09) teljes (2026-08-20)

**User-kérés:** „folytasd a briefek megírását". A Chapter 14 §8 szerinti első
blokk — **R01–R09: mérési és bizonyítási alap** — ezzel teljes: minden körhöz
van futtatható szerződés.

| Kör | Tárgy | ADR | Kockázat |
|---|---|---|---|
| `E14-R06` | Accuracy Lab csomag + consent-kapu (UI nélkül, §0.0 drift) | 0358 | high (mikrofon-felvétel, privacy) |
| `E14-R07` | annotációs séma + validator + annotátor-egyetértés (GUI nélkül, §0.0 drift) | 0359 | normal |
| `E14-R08` | csoportosított evaluation harness + leakage-védelem | 0360 | normal |
| `E14-R09` | baseline dashboard + fail-closed release gate | 0361 | normal |

**Két kötött scope-szűkítés (mindkettő §0.0-ban dokumentálva, mért indokkal):**
az R06 a Lab **adat- és adatvédelmi magját** építi képernyő nélkül (a
képernyők helye a Chapter 13 sáv, különben a két sáv ugyanarra a felületre
írna), az R07 pedig az annotáció **szerződését és validatorát** GUI nélkül (a
repónak nincs desktop/web célja, és a gate egy GUI-t nem tud vezetni). Mindkét
felület-rész külön körre (`E14-R06b`, `E14-R07b`) marad.

**Újrahasznosítás, nem újraírás:** az R07–R09 az `ADR 0249 / E06-R29` bevált
alakját viszi tovább (`evaluation/analysis/manifest_schema.json` +
`EvaluationManifestParser` + `tool/audio_analysis_evaluate.dart`): nyers audio
soha nem kerül a repóba, a CI kis szintetikus fixture-ön fut, a valós korpusz
külső manifesttel, kézzel. A `ml/honest_eval.py` (tanító oldal) NEM módosul.

**Mérve:** `brief-lint --level strict` mind a négy briefre → *nincs lelet*;
`brief-lint --open --level base` az összes nyitott körre → *nincs lelet*;
`python3 -m pytest tools/tests -q` → 679 passed, 1 failed (a szokásos
környezeti `gh`-piros), 595 subtests.

**A sorok `prepared`-ek** — a futó prioritás változatlanul a Chapter 13 UI-sáv.

## 📝 [TERV] Chapter 14 — az E14-R02…R05 briefjei megírva (PREPARED, user-kérés 2026-08-20)

**User-kérés:** „írd meg a briefeket az SDD tervek alapján" — a Chapter 14
(Recognition Accuracy & Useful UI Recovery) folytatása. Az `E14-R01` (recovery
kickoff + release guard) `done`, de a következő körökhöz **nem volt brief**,
tehát a lánc nem tudta futtatni őket.

**Megírva** (`tools/round-brief-prep` protokoll, mind a négy `brief-lint
--level strict` szerint TISZTA):

| Kör | Tárgy | ADR | Kockázat |
|---|---|---|---|
| `E14-R02` | reprodukálható felismerési baseline + evidence index | 0354 | normal |
| `E14-R03` | model activation telemetry, fail-visible fallback | 0355 | high (telemetria-redakció) |
| `E14-R04` | `RecognitionFrame` V2 domain contract (6 döntési állapot) | 0356 | normal |
| `E14-R05` | Live signal quality analyzer (8 állapot, hiszterézis) | 0357 | high (nyers mikrofon-PCM) |

**A briefek mért tényekre épülnek, nem a doksira** — a fontosabbak:
`StrumCrnn.tryLoad` néma `catch (_) → null` (`strum_crnn.dart:28-35`) és a
`_tryLiveCrnn` ugyanez (`live_pipeline.dart:21-30`), tehát ma nem látszik,
melyik felismerő fut; a `LiveFrame` 11 mezőjéből EGYETLEN `confidence` van, és
az a strumé (`live_frame.dart:69`), 19 fájl hivatkozik rá → kötelező adapter; a
Live minőségjelzés ma egyetlen skálázott RMS (`live_pipeline.dart:231`),
miközben a batch oldalon az `signal_quality_math.dart` (ADR 0224) mért
képletei KÉSZEN vannak — az R05 ezért újrahasznosít, nem újraír.

**A sorok `prepared`-ek, nem `pending`-ek:** a user prioritása most az UI-sáv
(Chapter 13). Amikor a felismerési sáv is indulhat, a négy sor `pending`-re
állítása egy commit — a `brief-lint --open --level base` már ma is tiszta rájuk.

**Nyitva marad:** a Chapter 14 R06–R42 briefjei (36 kör) — a következő adag.

## ✅ E08-R11 KÉSZ — Qualified day, planned rest és recovery policy — PR #363, squash `6a8d0b72` (2026-08-20)

A gamification application-réteg most csak legalább 120 másodperc érvényes
aktivitást minősít standard napnak; az explicit recovery út 60 másodpercnél
nyílik. A tervezett pihenőnap a Practice Generator publikus, reason-code-os
heti szerződéséből érkezik, nem fogyaszt freeze-t, az óra-visszalépés pedig
nem növeli és nem töri a streaket. A hétnapos consistency külön, egyedi
qualified napokból számolt projekció. A döntést ADR 0352 rögzíti.

Implementer: Terra (`gpt-5.6-terra`); független correctness és high-risk
security review: Sol (`gpt-5.6-sol`), mindkettő APPROVED. Az első review egy
MAJOR hibát reprodukált `TZ=Europe/Budapest` alatt: az UTC-alapú rest-day
konverzió eltért a shipping `StreakLogic.epochDayOf` helyi-midnight
napalapjától. A javítás után 12/12 célzott teszt és a teljes 6/6 round-gate
zöld; a „minden aktivitás kvalifikál" mutáció A1/A8/A9 cellákat pirosra
vitte. Exact `0674de52`: Full Gate
[32379760277](https://github.com/wolfcasaba/strumsight/actions/runs/32379760277)
és Router CI
[32379709904](https://github.com/wolfcasaba/strumsight/actions/runs/32379709904)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R12 — Streak UI V2 és recovery flow**.


## 🚦 [GOV] E13-R01 `prepared` → `pending` — elindul a Chapter 13 (UI/UX design system) sáv (user-döntés 2026-08-20)

**Miért:** a `pipeline-slots=2` merge után (PR #360) a második sáv MÉRHETŐEN
üres maradt, mert nem volt engedélyezett munka hozzá — nem slot-hiba. A
`tools/round-slots.py plan` az E08-R12 futása mellett ezt adta:
`free_slots: 1`, `rejected: E99-R22 — teljesítetlen előfeltétel: E99-R21`
(az R21 `hold`-on áll), az E13-sáv 36 sora pedig `prepared` volt, amit a
driver szándékosan nem futtat — ember állítja futtathatóra.

**A döntés (2026-08-20, két lépésben):** a Chapter 13 program-nyitó köre, az
**E13-R01** (UI baseline inventory és screenshot corpus) `pending` — majd a
user pontosítása után („hagy fejlessze a UI-t") a **teljes E13-sáv nyitva**:
mind a 36 sor `pending`. A sáv így magától halad R01 → R02 → …, ahogy az Epic
8 sáv teszi; bármelyik sor bármikor `hold`-ra tehető, ha közbe kell lépni.
Ugyanaz a minta, mint az Epic 6 sorainak megnyitása (user-döntés 2026-08-11).

**Mérve a teljes nyitásra:** `python3 tools/brief-lint.py --open --level base`
mind a 36 nyitott E13-briefre → *nincs lelet*, tehát a Router CI nyitott-kör
kapuja zöld marad.

**Tesztelhetőség (user-igény):** az E13-R01 diffje szándékosan NEM hoz látható
felületváltozást (leltár-tool + `docs/ui/**` baseline + teszt), a valódi UI a
R02-től épül. A Dart-only körökre a `tools/round-ci-plan.py` APK NÉLKÜLI Full
Gate-et ír elő, ezért a telefonos próbához az APK-t külön kell kérni:
`gh workflow run build-apk.yml --ref main` (a futás artefaktumként adja a
release APK-t).

**Mérve a döntés előtt (ezen a felhő-boxon, `main @ 7b5315b` + ez a sor):**

* `python3 tools/brief-lint.py --open --level base` → *nincs lelet* (az
  E13-R01 briefje a nyitott körök kapuján is átmegy);
* `tools/round-slots.py plan --slots 2` az E08-R12-t `running`-ra állítva,
  `inflight=E08-R12`: **admitted: E13-R01** — tehát a tervező fájl-diszjunktnak
  és előfeltétel-késznek méri a futó gamification-kör mellett. (Ugyanez a hívás
  az E08-R12 `pending` sorával az E08-R12-t admittálja: a `plan` a sor
  státuszát nézi, nem az inflight-regisztert — ez a mérés kerete, nem lelet.)

**Nem változott:** a slotszám (`2`), a rotáció (`sol`), a queue összes többi
sora, és a mérce egyetlen lépése sem. A kör motorja a sor szerint `terra`,
orchestrátora a Sol-pin szerint a Sol.

**Az E13-R01 briefje kötelező pre-flightot ír elő** (§2 számai `main @
17670d4f`-en készültek: képernyők, hex-találatok újramérése, eltérésnél §0.0
revízió) — ezt az orchestrátor a dispatch előtt elvégzi.

## ✅ E99-R20 (GOV-14) KÉSZ — kombinált-HEAD kör-landoló és H8-SELFDUP őr — PR #361, squash `5ad15b5f` (2026-08-20)

A `tools/round-land.sh` a merge-záron belül köti a PR identitását a mért
branchhez/SHA-hoz, friss `main`-re rebase-el, csak a két append-only naplót és
a kör saját briefjét oldja mechanikusan, a kombinált HEAD-en futtatja a
round-gate-et, majd safe-force-push után új exact-SHA CI-t kér. Változatlan,
már igazolt HEAD-en squash-merge-el. Az új H8-SELFDUP patch-id őr rebase előtt
blokkolja azt a mért hibát, amikor egy régi, rebase előtti csúcs
visszamerge-elése a kör saját patcheit megduplázza.

Implementer: Terra; független correctness és high-risk security review: Sol,
mindkettő APPROVED. Izolált review: scope-audit OK (6 útvonal, 2
generated/ignored), round-gate 6/6 zöld, tooling pytest 664 passed / 2 skipped
/ 574 subtest; a H8-SELFDUP mutáció guard nélkül RED, visszaállítva GREEN.
Exact `a73493f4`: Full Gate
[32373805059](https://github.com/wolfcasaba/strumsight/actions/runs/32373805059)
és Router CI
[32373785655](https://github.com/wolfcasaba/strumsight/actions/runs/32373785655)
success; post-merge round-gate a friss `main`-en 6/6 zöld. A részletes
történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R11 — Qualified day, planned rest és recovery
policy**.

## 🔥 [GOV] MIND A KÉT SLOT Sol+Terra — commitolt slot-döntés és Sol-vezényelt önjavítás (user-döntés 2026-08-20, branch `claude/sol-orchestrator-terra-implementator-jtf4z5`)

**User-döntés:** „mind a két sloton azt akarom, hogy a Sol orchestrátor és a
Terra implementátor dolgozzon" — a PR #351 Sol-pin kiterjesztése a párhuzamos
sávra. A kör-dispatch felállása (Sol vezényel, Terra implementál) már élt; ami
hiányzott, az a két MÉRT rés:

1. **A slotszám nem utazott a repóban.** A `PIPELINE_SLOTS` csak a cron
   env-jében élt (`slots=${PIPELINE_SLOTS:-1}`), tehát pontosan az az osztály,
   amit a rotációnál már megmértünk (E99-R14 lecke): a cron exportált env-je
   némán felülírja a git-en érkező user-döntést, és a lánc egysávosra esik
   vissza anélkül, hogy ez bárhol látszana. Mostantól a commitolt
   [`docs/execution/pipeline-slots`](docs/execution/pipeline-slots) (`2`)
   ERŐSEBB az env-nél (**file > env > script-default**), eltérő env-re
   log-sort ír (`SLOT-FÁJL: …`), üres/hiányzó fájlra marad a mai env-
   szemantika, nem pozitív egészre pedig `die` (fail-closed). A RAM-fedezet
   őre (`effective_slots`, ADR 0171 §1) VÁLTOZATLAN — a fájl a KÉRT sávokat
   mondja meg, a tényleges párhuzam ettől lefelé térhet el, naplózott
   `SLOT-KORLÁT` sorral. Új teszthorog: `--requested-slots` (a RAM-őr ELŐTTI,
   feloldott érték). A `tools/pipeline-status.sh` is ezt olvassa, különben
   „1 kért"-et hazudott volna két futó sáv mellett.

2. **Az önjavító kör is slotot foglal — de a Claude-keretből ment.** Az
   `attempt_selfheal` a rögzített `sonnet-impl` identitással és
   `orchestrator_preference=claude`-dal indult, vagyis a második sáv munkája
   épp azt a keretet fogyasztotta, amit a Sol-pin kímélni akar. Mostantól a
   pin alatt (`orch_rotation=sol` ÉS van Codex-oldal) a heal-ülést a **Sol**
   vezényli, rögzített identitása a nyilvántartás új `sol` sora, és a
   harmadik (utolsó) kísérlet innen vált MÁS modellre — a gyakorlatban a
   **Terrára** (ADR 0307 §2 lever, ami `sol` sor nélkül némán elmaradt volna:
   a `heal_engine_for_attempt` ismeretlen névre a saját motort adja vissza).
   Pin nélkül (alternate | claude | terra) minden BITRE a régi, kvóta-tudatos
   Claude→Terra úton marad; a `PIPELINE_FALLBACK_ENGINE=none` fail-safe
   ugyanígy visszaejt a Claude-útra.

**Függetlenség — nem nyílt rés.** Az új `sol` sor (`codex`, `~/.codex-terra`,
`gpt-5.6-sol`) implementernek választva a MODELL-azonosság miatt ütközik a
sol-orchestrátorral, tehát `H-INDEP` fail-closed; a `terra` (`gpt-5.6-terra`)
változatlanul független. A `orchestrator_conflicts_with_implementer` elavult
kommentje („ilyen sor ma nincs a nyilvántartásban") frissítve.

**Módosult:** `tools/round-pipeline.sh` (slot-fájl precedencia + fail-closed,
`--requested-slots` horog, Sol-vezényelt heal + `sol` heal-identitás, frissített
függetlenség-komment), `docs/execution/pipeline-slots` (ÚJ, `2`),
`docs/execution/engine-registry.tsv` (`sol` ülés + indoklás),
`tools/pipeline-status.sh` (őszinte „kért" slotszám),
`docs/execution/pipeline-orchestrator-prompt.md` (MOTOR-FELÁLLÁS + §4.1),
`AGENTS.md` (§15.7 GOV-blokk), tesztek: ÚJ
`tools/tests/test_sol_terra_both_slots.py` (13 cella: commitolt `2`, file>env,
env-szemantika fájl nélkül, 4 fail-closed eset, RAM-őr épsége, `sol`
registry-ülés, driver-default modell-egyezés, ütközés-mátrix, Sol-vezényelt
heal, pin nélküli Claude-heal, utolsó kísérlet → Terra, `fallback=none`
fail-safe), `tools/tests/test_selfheal_escalation.py` (a régi utat mérő cellák
explicit env-pinnel — ugyanaz a minta, mint a PR #351 `alternate`-celláinál).

**Mérés (ezen a boxon):** `python3 -m pytest tools/tests -q` — a kör előtt
650 passed / 1 failed / 2 skipped / 570 subtests, a kör után (lásd a commit
üzenetét) ugyanaz az egyetlen, KÖRNYEZETI piros
(`WorkspaceRestorationHermeticityTest` — nincs `gh` CLI ebben a sandboxban, a
VÁLTOZATLAN HEAD-en is ugyanígy piros). Az új cellák a production-változás
NÉLKÜL mérve pirosak (15 failed / 5 passed a fájlon belül), vele zöldek.

**Visszaálláskor** (a Pro lejárta után) a `docs/execution/pipeline-slots`
fájlt és a `test_the_committed_slots_file_value_is_two` cellát EGYÜTT kell
átírni; a rotáció-fájl `alternate`-re állítása magától visszaviszi a healt is
a Claude-útra.

**BOX-OLDALI TEENDŐK** (a felhő-sandboxból nem pótolhatók):

1. **HORIZON git-notes** — a `refs/notes/*` push innen 403-tiltott (ugyanaz,
   mint a 2026-08-20-i GOV-FIX 3. pontjánál). A merge után a boxon:

   ```bash
   git notes add -m "round=gov-both-slots-sol-terra verdict=pass tests=663 lesson=slot-decision-travels-in-the-repo-and-heal-follows-the-sol-pin" <a merge-elt squash-commit>
   git push origin 'refs/notes/*'
   ```

2. **Crontab-zaj (opcionális):** `crontab -l | grep PIPELINE_SLOTS` — a sor a
   fájl-elsőbbség miatt már hatástalan (log-sor jelzi, ha eltér), a zaj
   csökkentésére törölhető. A rotáció-sorral azonos megfontolás.
## ✅ E08-R10 KÉSZ — Streak V2 domain és read-only legacy migráció — PR #362, squash `892e04a6` (2026-08-20)

A gamification feature új, verziózott `StreakState` V2 contractot, tiszta és
óra-mentes `StreakPolicy`-t, típusos transition reasonöket, valamint read-only
legacy adaptert kapott. Az adapter a `ss.streak.state` envelope-ot részesíti
előnyben, majd a `practice_streak_v1` raw JSON-ra esik vissza; egyik forrást
sem írja vagy törli. Az öt shipping legacy érték veszteség nélkül megmarad,
a legacy feature és `/streak` útvonal érintetlen. A döntést ADR 0351 rögzíti.

Implementer: Terra (`gpt-5.6-terra`); független correctness és security
review: Sol (`gpt-5.6-sol`), mindkettő APPROVED, nyitott lelet nélkül. Az
izolált reviewer gate 7/7 zöld; a legacy↔V2 eldobható parity-próba több mint
4 000 kombinációt mért; a kötelező gap-2 mutáció az A4 cellát pirosra vitte.
Exact `f5a0a8de`: Full Gate
[32371975469](https://github.com/wolfcasaba/strumsight/actions/runs/32371975469)
és Router CI
[32371933077](https://github.com/wolfcasaba/strumsight/actions/runs/32371933077)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R11 — Qualified day, planned rest és recovery policy**.

## 🔁 [HEAL E08-R10/H6] `outcome=retry` — Terra `blocked` jelzés a kötelező round-gate.sh kimenet megszakadásáról; byte-azonos reprodukció 54s alatt 7/7 zölden zárt, kódjavítás nem kellett (2026-08-20, L360)

Az E08-R10 (Streak V2 domain + legacy migráció, ADR 0351) Terra
implementációja (`terra/e08-r10-streak-v2-domain-and-legacy-migration`, HEAD
`f2e368b3`, `scope_audit=ok`) `blocked`-ot jelzett: a kötelező
`tools/round-gate.sh test/features/gamification/domain/streak_policy_test.dart
test/features/streak` hívás kimenete a legacy streak-suite indításánál
megszakadt a Terra saját (Codex-exec) futtatókörnyezetében, jóllehet Terra
saját ad-hoc tesztfuttatásai (11+20 teszt), az architecture/secrets/l10n
ellenőrzés és a scope-audit mind zöldek voltak. A self-heal a PONTOS
halt-parancsot futtatta újra ugyanazon a munkapéldányon és HEAD-en, egy
MÁSIK, egyidejűleg futó self-heal (E99-R20/H8) mellett is: 54 másodperc
alatt mind a 7 lépés zöld (`format`/`analyze`/mindkét teszt-útvonal/
`architecture`/`secrets`/`l10n`), kilépési kód 0, „MINDEN GATE ZÖLD". Sem a
gate script, sem a termék-kód nem hibás — a megszakadás a Terra saját, ezen
a repón kívüli futtatókörnyezetének egyszeri jelensége volt. Nincs
kódváltoztatás; a meglévő branch/commit érintetlenül vár a következő
E08-R10 firingre, amely az örökség-ellenőrzés (§0.2) szerint megtalálja és
onnan folytatja. Lecke: **[[L360]]**.

## ✅ E08-R09 KÉSZ — Legacy progress adapter és activity backfill — PR #359, squash `842231f5` (2026-08-20)

A legacy `PracticeEntry` snapshot most determinisztikus, SHA-256-alapú opaque
activity ID-kre fordítható exact duplikátum-megőrzéssel; a backfill nulla
retroaktív XP-t ad, de változtathatatlan statisztikai reportot készít. A
`GamificationMigrationState.processedCount` az eredeti snapshot első fel nem
dolgozott indexét tárolja, ezért invalid rekordok mellett is restart-biztos.
Az első correctness review F1 BLOCKER + F2/F3 MAJOR, a security review S4
MAJOR leletét két javítás lezárta; a végső Sol re-review és security review
APPROVED. Exact `e25d3158`: Full Gate
[32365896298](https://github.com/wolfcasaba/strumsight/actions/runs/32365896298)
és Router CI
[32365922753](https://github.com/wolfcasaba/strumsight/actions/runs/32365922753)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R10 — Streak V2 domain és legacy migráció**.

## ✅ [HEAL E08-R09/H4] KÉSZ — checkpoint a szűrt event-listát indexelte az eredeti legacy snapshot helyett — kör-ágra pusholva, PR nélkül, `3a702692` (2026-08-20)

Az E08-R09 (legacy progress adapter + activity backfill, ADR 0307/0350) H4-gyel
állt meg: a Terra/Codex javító kör UTÁN a független security-reviewer S4
MAJORt talált nyitva (`docs/reviews/e08-r09-security.md`) —
`GamificationMigrator._checkpointFor` és a write-loop a
`LegacyPracticeAdapter.adapt(entries)` SZŰRT `events` listáját indexelte az
eredeti, caller-supplied `entries` snapshot helyett, így egy invalid rekord
jelenlétében a perzisztált `processedCount` (ADR 0350 D5: "az első fel nem
dolgozott EREDETI index") alulszámolt, és eltérhetett az `entries.length`-től
egy teljes, sikeres futás után is. Mért bizonyíték a review-ban: checkpoint=2,
4 elemű snapshot 1 invalid rekorddal → várt `[3,4]` írás helyett mért `[3]`.

Javítás (`lib/features/gamification/data/migration/gamification_migrator.dart`):
`_checkpointFor(events.length)` → `_checkpointFor(entries.length)`, a
write-loop és a belső bound-check ugyanígy. Négy állandó regressziós cella
(`legacy_practice_migration_test.dart` S4a-d: invalid a checkpoint
alatt/rajta/fölötte + teljes futás nulláról) — mérve piros a javítás előtt
(mutáció-visszaállítással, S4a byte-azonos a review saját reprodukciójával),
zöld utána; `tools/round-gate.sh` a két érintett teszt-fájlon zöld
(format/analyze/17+11 teszt/architecture/secrets/l10n). **Egy MÁSODIK,
független, izolált klónban egy security-reviewer subagenttel is
újra-ellenőrizve** — saját kézzel megismételt mutáció-kill ugyanazokat a
számokat adta, és a `_checkpointFor`/`processedCount` egyetlen más
hívóhelyénél sem talált a régi szemantikára támaszkodó kódot.

[[L304]] mintája szerint (`docs/LESSONS.md`) a hibás kód kizárólag a megállt
kör SAJÁT, `main`-be még nem olvadt ágán élt (a teljes migrátor/adapter
feature csak a kör 4 commitjában létezik, `main`-en — `9e18c68d` — nincs
jelen sem az ADR 0350, sem a `migration/` könyvtár), ezért a javítás NEM
`heal/E08-R09-H4-1` branch+PR-en ment, hanem 3 commitban közvetlenül a kör
saját ágára (`terra/e08-r09-legacy-progress-adapter-and-backfill`, HEAD
`3a702692`) lett pusholva, PR és CI-dispatch nélkül — `main` és
`docs/rounds/*.md` érintetlen. A `docs/reviews/e08-r09-security.md`
review-doksi frissült: S1-S4 mind CLOSED, Verdikt **APPROVED**. A lánc
következő E08-R09 firingje a szokásos PR/CI/merge lezárást viszi végig ezen
az ágon. Lecke: [[L358]].

## ✅ [HEAL E08-R09/H3] KÉSZ — `allowed_paths` nem tartalmazta az ADR 0344 D7 által R09-re kiosztott séma-fájlt — PR #357, squash `3d88d7d9` (2026-08-20)

Az E08-R09 (legacy progress adapter + activity backfill, ADR 0307) dispatchja
H3-mal állt meg **modellhívás előtt** — a `terra` implementer még el sem
indult (`.pipeline/HALTED` `implementer/PR/CI nem indult`). Gyökérok: a
brief kötött döntése (§5.3/A5, ADR 0307) egy **perzisztált migrációs
checkpointot** követel meg ("Félbeszakadt migráció az ellenőrzőponttól
folytatódik, nem elölről"), de az egyetlen hely, ahol ez élhet —
`GamificationMigrationState` a
`lib/features/gamification/data/gamification_storage_schema.dart`-ban — az
ELŐZŐ, már merge-elt E08-R08 kör (ADR 0344) D7 pontja szerint **szándékosan**
csak verzió-jelölő helyfoglaló: "A tényleges migrációs mezőket a Kör 9/10
... tölti ki." Az E08-R09 brief `allowed_paths`-a viszont sosem sorolta fel
ezt a fájlt — a kör a saját elfogadási kritériumát nem tudta volna
teljesíteni anélkül, hogy vagy scope-on kívülre lépjen, vagy csendben
tágítsa a listát. Class B (kör-tartalom: ADR + brief kontra `allowed_paths`),
nem implementer- vagy eszközhiba.

Feloldás (`docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
§0.0): a séma-fájl **egyetlen, szűken körülhatárolt** bővítésként bekerült
az `allowed_paths`-ba — kizárólag a `GamificationMigrationState` osztály
bővíthető checkpoint mezővel/mezőkkel, a másik három dokumentum és a
`GamificationStorageKeys`/`migrationStateMaxBytes` nem. Kimondott,
nem-tárgyalható korlát: az új mező(k)nek alapértelmezett értékkel kell
rendelkezniük, hogy a már merge-elt (és ebben a körben TILOS zónában maradó)
`gamification_repository_test.dart` A3 zéró-argumentumos round-trip cellája
érintetlenül zöld maradjon. A brief-lint S8 strict lelete (nincs
visszakeresett előzmény) is lezárva: `ADR 0117` Döntés 2 (E03-R08,
dalfájl-migráció) ugyanezt a mintát — checkpoint mint saját verziózott
JSON-dokumentum — már megalapozta.

Regressziós védelem:
`tools/tests/test_e08_r09_migration_state_schema_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen; a
mért halt-útvonal RED volt a javítás előtt (kézzel visszaállítva
`git show HEAD:...`-tal, nem kitalált feltevésből) és GREEN utána, egy
szomszédos fájl (`gamification_repository.dart`, ugyanabban a könyvtárban)
pedig továbbra is scope-on kívül marad — a bővítés egy fájl, nem az egész
`data/` könyvtár. Teljes gate izolált heal-worktree-ben:
`python3 -m pytest tools/tests -q` → 652 passed/1 skipped/570 subtests/0
failed (650/1/570 volt a kör előtt). `brief-lint --open --level base` és
`--level strict` is tiszta. Router CI
[32357936017](https://github.com/wolfcasaba/strumsight/actions/runs/32357936017)
success az exact push SHA-n (`c373f3f4`), amit a merge előtt a helyi HEAD-del
összevetve igazoltam. Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L357]].

Az eredeti E08-R09 dispatch modellhívás nélkül állt meg — nem volt félkész
munkapéldány, commit vagy nyitott PR a self-heal előtt, ezért ez a heal nem
vitt tovább tartalmi migrációs munkát; a lánc friss dispatch-csal folytatja
E08-R09-et a felfrissített brieffel.

## ✅ [HEAL E99-R20/H6] KÉSZ — `WrapperModeTest` hiányos leszivárgás-pop-listája — PR #356, squash `a0bf0d51` (2026-08-20)

A `terra` implementer E99-R20-on (GOV-14, round-landolás-automatizálás,
ADR 0313) `blocked`-ot jelzett: a kötelező §7 gate
(`python3 -m pytest tools/tests -q`) a
`WrapperModeTest.test_the_legacy_call_without_round_engine_stays_minimax`
cellán bukott, KÉTSZER egymás után (mérve a saját worktree-jében,
`/home/ubuntu/ss-terra-e99-r20`, head `21224fa9`). A self-heal saját, első
reprodukciós kísérlete (a HALTED szó szerinti parancsa egy FRISS shellben)
zöld lett — csak a nyers Terra-napló adta a tényleges gyökéroket: az L341
(UGYANAZON a napon, E99-R17 H6) négyelemű leszivárgás-pop-listája nem volt
teljes. A `tools/codex-round.sh` a `tools/engine-profile.sh env <motor>`
teljes kimenetét (`ENGINE_MODEL` és hat társa) exportálja a HÍVÓ session
sajátjaként, ami a §7 gate-en át ugyanúgy bekerül a `WrapperModeTest.
run_wrapper()` szimulált alfolyamatába, mint az L341-ben talált négyes —
csak EGY SZINTTEL FELJEBBI forrásból, és BÁRMELYIK motorral (nemcsak
minimax-szal) kiváltható. A pop-listát a teljes `engine-profile.sh env`
kulcskészletre bővítettük (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`,
`ENGINE_MODEL`, `ENGINE_STALL_MINUTES`, `ENGINE_ROUND_TIMEOUT`,
`ENGINE_CONTEXT_WINDOW`, `ENGINE_MAX_OUTPUT`, `ENGINE_REASONING`), és egy
regressziós tesztet adtunk hozzá, amely a valódi mért `terra`-exportot
szimulálja (`test_ambient_engine_profile_env_does_not_leak_into_the_legacy_run`).
RED a bővítés nélkül, GREEN vele; teljes `tools/tests` gate izolált
heal-worktree-ben 650 passed/1 skipped/570 subtests/0 failed, Router CI
[32354341693](https://github.com/wolfcasaba/strumsight/actions/runs/32354341693)
success az exact push SHA-n; post-merge egy FÜGGETLEN, friss klónból a
célzott fájl újra zöld (21 passed). Nincs törölt/gyengített teszt, nincs
küszöb-lazítás, `tools/round-gate.sh`/`.github/workflows/**` érintetlen.
Lecke: [[L356]] (a lecke egy mellékesen mért ballépést is dokumentál: az
`engine-profile.sh env <motor>` diagnosztikai futtatása kulcsot birtokló
motoroknál a NYERS API-kulcsot írja stdoutra — a self-heal ezt a boxon,
sajátjának minősülő kulcsokkal, egy interaktív diagnosztikai lépésben tette,
harmadik fél felé nem jutott ki, de jövőbeli self-healnek ezt kerülnie kell).

Az eredeti E99-R20 (GOV-14) kör TARTALMI munkája (D1–D5, `tools/round-land.sh`
+ `tools/tests/test_round_land.py`) ÉRINTETLEN maradt a `terra` worktree-ben
(`/home/ubuntu/ss-terra-e99-r20`, 3 commitolatlan fájl) — ezt a self-heal
szándékosan NEM vitte tovább (ADR 0112 hatókör), a pipeline driver folytatja
friss sessionben. Két, a körhöz nem tartozó, előzőleg is létező maradvány
érintetlen maradt (nem ennek a self-healnek a hatóköre): a
`gov/round-lander` remote branch (`da80e4d8`, a régi ADR 0313 + brief
pre-flight-branchje, tartalma már máshonnan mergelve) és a
`/home/ubuntu/ss-heal-E08-R04-1` worktree (egy korábbi self-heal maradványa).

## ✅ E08-R08 KÉSZ — Gamification repository és tároló-séma — PR #355, squash `ebb03d9d` (2026-08-20)

Négy különálló, verziózott `JsonDocumentStore`-dokumentum EGY sémafájlban
(`gamification_storage_schema.dart`): profil-pillanatkép (`schemaVersion` +
`totalXp` — a domain `GamificationProfile`-tól független DTO, a `progress`
mindig a hívó `LevelCurve`-jével újraszámolva), katalógus-verzió, jutalom-
postaláda (a MEGLÉVŐ `JsonCollectionStore<T>` wrapperrel, `maxItems:
inboxRetentionLimit=50`, inkluzív küszöb) és egy szándékosan minimális
migrációs-állapot placeholder (Kör 9/10 tölti majd ki). `LocalGamificationRepository`:
atomikus egy-hívásos pillanatkép-csere, explicit `available/missing/corrupt`
olvasási státusz, broadcast watch-stream. Új architektúra-guard: a
gamification `application/` (és a még nem létező `presentation/`) NEM
importálhat `SharedPreferences`-t — a MEGLÉVŐ E08-R02 marker-lista és helper
újrafelhasználásával. ADR [`0344`](docs/adr/0344-gamification-storage-schema-versioned-documents-and-layer-purity.md)
(a briefben előre kiosztott `0306` stale volt — a foglaló `0344`-et adta).
Implementer: Codex (`~/.codex`, gpt-5.6-terra).

A független review (`docs/reviews/e08-r08-review.md`) az implementer saját
zöld tesztjei MÖGÖTT egy MAJOR rést talált, eldobható próbateszttel mérve:
**F1** — `readInbox()` egy redundáns, saját előzetes validáló ciklust
futtatott a `JsonCollectionStore` rekordonkénti hibatűrése ELŐTT, ezért egy
EGYETLEN hibás postaláda-bejegyzés a TELJES listát (akár 49 érvényes
bejegyzést is) „sérültnek" jelentette — ez pontosan az ellenkezője [ADR
0054](docs/adr/0054-versioned-user-content-documents.md) garanciájának
("corruption now costs one record, not one feature's entire content").
Mérve egy 3 elemű (2 jó + 1 hiányzó-`id` közepes) envelope-próbával:
`status=corrupt, value=null` a javítás előtt. Egy javító kör törölte a
redundáns ciklust és állandó regressziós tesztet adott hozzá; a reviewer
saját, izolált újraklónban függetlenül megerősítette (11/11 zöld a célzott
tesztben). N1 (a watch-stream optimistán sugároz egy elnyelt írási hiba
esetén — meglévő, projektszintű kockázat öröklődik, nem új regresszió) nyitva
maradt, NEM blokkoló.

A kör alatt a `main` HÁROMSZOR mozdult (E99-R19 GOV-13 lezárása, PR #353
Sol-pin env-fix, E99-R20 GOV-14 induló munkája — mind diszjunkt fájlkör) —
mindháromszor `merge --no-ff` + teljes CI-újradispatch a §0.3 szerint,
IZOLÁLT `/tmp` klónokból (a megosztott munkafa közben egy párhuzamos E99-R19
session `git reset`-je + commitja átmenetileg felülírta a helyi branch-
mutatót a megosztott fán — az `origin`-on lévő, már pusholt munka
érintetlen maradt, a felismerés után minden további git-művelet izolált
klónból ment). Exact `91821f22`: Full Gate 32349845398 + Router CI 32349841249
success; post-merge célzott gate a friss `main`-en (`ebb03d9d`) önállóan is
zöld (7/7, izolált klónban mérve). Következő SDD-kör: **E08-R09** (Legacy
progress adapter és backfill).

## 🔧 [GOV-FIX] A Sol-pin env-biztos: commitolt rotáció-fájl + modell-ID megerősítve + box-teendők (2026-08-20, a PR #351 follow-upja)

A PR #351 három nyitott kockázatának zárása:

1. **Crontab-felülírás KIZÁRVA (repo-oldali fix):** a rotáció mostantól a
   **commitolt `docs/execution/orchestrator-rotation`** fájlban utazik
   (tartalma: `sol`), és a `round-pipeline.sh` ezt ERŐSEBBNEK veszi a
   `PIPELINE_ORCH_ROTATION` env-nél (file > env > script-default; eltérő
   env-nél log-sor). MÉRT ok: a cron a E99-R14 lecke szerint exportálja az
   env-t, ami némán felülírta volna a git-en érkező user-döntést. Üres/
   hiányzó fájl → env/default; érvénytelen érték → die (fail-closed).
   Teszt-horog: `PIPELINE_ORCH_ROTATION_FILE` (=/dev/null → env-szemantika).
   Guard-cellák: file>env precedencia, commitolt érték = `sol` pin,
   invalid → die. **Visszaálláskor a fájlt ÉS a
   `test_the_committed_rotation_file_value_is_sol` cellát együtt írd át.**
2. **Sol modell-ID MEGERŐSÍTVE (nincs teendő):** külső források szerint a
   Codex CLI GPT-5.6 szintjei pontosan `gpt-5.6-sol` / `gpt-5.6-terra` /
   `gpt-5.6-luna` (a Sol a flagship) — a driver defaultja helyes,
   `PIPELINE_SOL_MODEL` felülírás nem kell.
3. **HORIZON git-notes — A KÖVETKEZŐ BOX-OLDALI SESSION ELSŐ TEENDŐJE**
   (a felhő-sandboxból a `refs/notes/*` push 403-tiltott, ott nem pótolható):

   ```bash
   git notes add -m "round=gov-sol-pin verdict=pass tests=627 lesson=burn-expiring-pro-quota-sol-orchestrator-terra-implementer" 8fb5beb5
   git push origin 'refs/notes/*'
   ```

   Opcionális takarítás ugyanott: `crontab -l | grep PIPELINE_ORCH_ROTATION`
   — a sor a fájl-elsőbbség miatt már hatástalan, de a zaj csökkentésére
   törölhető. Elvégzés után ez a 3. pont a bejegyzésből kihúzható.

## 🔥 [GOV] Sol-orchestrátor + Terra-implementer MINDEN körben — Pro-keret égetése a lejáratig (user-döntés 2026-08-20, PR #351, branch `claude/router-config-changes-odzv8m`)

**User-döntés:** a ChatGPT Pro előfizetés **napokon belül lejár**, és a
keretének ~90%-a megmaradt — „hadd fogyjon el". Amíg él, MINDEN kör:

- **Orchestrátor/reviewer: Sol** (`gpt-5.6-sol`) — a `tools/round-pipeline.sh`
  rotáció-defaultja `alternate` → **`sol`** (env-vel felülírható:
  `PIPELINE_ORCH_ROTATION`). A Sol a Codex CLI-vel, a Terra
  `~/.codex-terra` CODEX_HOME-jában fut (közös auth), explicit
  `-m gpt-5.6-sol`-lal (`PIPELINE_SOL_MODEL` env-vel állítható). A Sol-pin a
  Claude-zárlat mérése ELŐTT dönt (a Sol nem a Claude-keretből fogyaszt), a
  körönkénti rögzítés (ADR 0242 D1) változatlanul működik rá.
- **Implementer: `terra`** (`gpt-5.6-terra`) — a queue mind a 65 nyitott
  (pending/hold/prepared) sora explicit `terra`-ra állt; az ADR 0069 mért
  motor-szétosztási szabálya erre az időszakra FELFÜGGESZTVE (a queue
  fejléce + `test_open_rounds_follow_the_measured_engine_rule` carve-out
  dokumentálja). A lezárt sorok motorja történeti tény, változatlan.
- **Függetlenség:** a Sol↔Terra pár a meglévő modell-azonossági kulcson
  (`orchestrator_conflicts_with_implementer`) független — két különböző
  modell; a közös Pro-ELŐFIZETÉS a döntés tudatos ára (épp a keret égetése a
  cél). Az `orchestrator_available` a Codex-oldali kapcsolóhoz köti a Solt
  (`PIPELINE_FALLBACK_ENGINE=none` → claude, fail-safe változatlan).

**Módosult:** `tools/round-pipeline.sh` (sol rotációs mód + default, Sol
session-indítás `-m`-mel, ütközés/elérhetőség/`--orchestrator-engine` horog),
`docs/execution/pipeline-queue.tsv` (65 sor engine → `terra` + fejléc),
`docs/execution/pipeline-orchestrator-prompt.md` (MOTOR-FELÁLLÁS blokk
újraírva 2026-08-20-ra, benne a lejárat utáni visszaállás lépései),
`docs/execution/pipeline-codex-orchestrator-preamble.md` (3. ok: Sol-pin),
tesztek: `test_orchestrator_rotation.py`, `test_round_resume_independence.py`,
`test_reviewer_independence.py`, `test_pipeline_integration.py` — az
`alternate`/fallback gépezet cellái explicit env-pinnel mérik a régi utat,
ÚJ cellák mérik a Sol-defaultot (default→sol zárlat alatt is; kör-pin sol;
resume sol+terra; enum `terra`; `--validate-engine terra`).

**Mérés (ezen a boxon):** `python3 -m pytest tools/tests -q` → **597 passed,
1 failed** — az egy piros a `WorkspaceRestorationHermeticityTest` (nincs
`gh` CLI ebben a sandboxban; a VÁLTOZATLAN HEAD-en ugyanígy piros, tehát
környezeti, nem regresszió). CI-n (gh jelen) zöldnek kell lennie.

**A lejárat UTÁN (visszaállás):** rotáció-default vissza `alternate`-re, a
nyitott `terra` queue-sorok visszaosztása (a lejárt előfizetéssel a
`codex`/`terra` sor nem futtatható — `minimax`/`sonnet-impl` a mezőny), és a
prompt MOTOR-FELÁLLÁS blokkjának frissítése. A pontos lépések a blokkban.

## ✅ E99-R19 (GOV-13) KÉSZ — lánc-higiénia, PR #354, squash `4dc8f7d1` (2026-08-20)

A pipeline tiszta, lemaradt `main`-je most csak fast-forwarddal frissül;
valódi divergencia és piszkos fa továbbra is fail-closed megáll. A záró
ritualé a queue `pending → done` átírását a HANDOFF-dokumentációval közös,
egyetlen commitba írja, a driver korábbi `chore(pipeline)` ága pedig
idempotens fail-safe marad. A strict brief-lint S7 csak az indoklás nélküli,
nem router-kockázatos `risk = "high"` briefet jelzi; a base CI-szint nem
szigorodott. A correctness review egy valódi lemaradt+piszkos-fa cellát
kért; az F1 javítás után a review APPROVED, a security review PASS.

Exact branch-head `c17ed660`: Full Gate
[32347005385](https://github.com/wolfcasaba/strumsight/actions/runs/32347005385)
és Router CI
[32347032703](https://github.com/wolfcasaba/strumsight/actions/runs/32347032703)
success. A merge-elt `main` (`4dc8f7d1`) post-merge gate-je is zöld;
tooling-suite: 647 passed, 571 subtests. Lecke: [[L353]].

## ✅ [HEAL E99-R19/H3] KÉSZ — governance-kör SAJÁT `allowed_paths`-ban felsorolt pipeline-fájlja nem H3-alap — PR #352, squash `c4104234` (2026-08-20)

A rotált (Terra) orchesztrátor megtagadta E99-R19 (GOV-13) implementer-
indítását: a brief `allowed_paths`-ának első eleme `tools/round-pipeline.sh`
(D1/D2 kifejezett céltárgya, ADR 0307 §6), a
`docs/execution/pipeline-orchestrator-prompt.md` §4 viszont minősítő nélkül
mondja, hogy ez a session sosem módosítja azt. A forrás,
`docs/adr/0087-autonomous-round-pipeline.md` §7 ugyanezt **„kör közben"**
(ad hoc, útközben talált akadály) minősítővel írja — ez a szó a prompt
átiratából hiányzott. Az ADR 0087 §2 H3-fogalma szerint tilos zóna kizárólag
az `allowed_paths`-on **kívüli** útvonal; öt korábbi governance-kör
(E99-R08/14/15/16/18) gyakorlata igazolja, hogy a fájl a szabványos
implementer → review → merge úton rendszeresen módosul. Ugyanaz a mintázat,
mint [[L251]] (E99-R08/H3): egy rotált motor a hallgatólagos Claude-
tapasztalat nélkül a betű szerint olvas egy kontextusfüggő tiltást.

Javítás: a prompt §4 és az ADR 0087 §7 (jelölt „Módosítás" blokk) explicit
carve-outot kapott a governance-kör saját, előre engedélyezett briefjére; a
`.github/` és a `round-gate.sh` határa VÁLTOZATLAN maradt normál körre.
Regressziós doksi-teszt (a `test_reviewer_scope_exemption_docs.py` mintáját
követve): `tools/tests/test_pipeline_file_governance_round_exemption_docs.py`
— RED a javítás előtt, GREEN utána, mindkettő lokálisan igazolva. E99-R19
brief `allowed_paths`-a és D1–D3 terve VÁLTOZATLAN, csak egy §0.0 addendumot
kapott. Teljes `pytest tools/tests`: 625 passed, 565 subtests (310s); Router
CI exact-SHA `a2f94f97`: [32341677224](https://github.com/wolfcasaba/strumsight/actions/runs/32341677224)
success (nincs Dart-változás, `build-apk` nem indult). Lecke: [[L352]].

Takarítás: a halted round MiniMax pre-flight-only debris ága
(`minimax/e99-r19-gov-13-chain-hygiene`, csak egy státusz-bump commit, sosem
nyílt rá PR) törölve. A lánc feloldva — a következő firing E99-R19-et friss
sessionnel, a javított prompttal újrapróbálja.

## ✅ E08-R07 KÉSZ — Szintgörbe és profil-projekció — PR #349, squash `010989f3` (2026-08-20)

Monoton `LevelCurve` (egyetlen forrás, inkluzív küszöb, `int64`-közeli
szaturáció), verziózott `GamificationProfile` a lapozott reward ledgerből
teljesen újraépíthetően, és egy `ProfileProjector` (teljes újraépítés +
inkrementális projekció azonos logikával, minden egy eseményben átlépett
szint megjelenik). ADR 0342 (a briefben előre kiosztott `0305` stale volt —
36 szám fogyott el 2026-08-18 óta, a foglaló adta a valódit).

A független review az implementer saját zöld tesztjei MÖGÖTT három valódi
rést talált — mindegyiket mutációs próbával mérve, nem csak olvasással: **F1
BLOCKER** — `rebuild()` kivételt dobott egy vadonatúj (üres) ledgeren,
pontosan a brief fő use case-én (a produkciós `LocalRewardLedgerRepository`
ellen is reprodukálva); **F2 MAJOR** — a „szint soha nem csökken"
lefelé-korrekciós guard teszteletlen volt, törlése mellett minden teszt zöld
maradt; **F3 MAJOR** — az A8 unlock-tiltó regexe egy raw stringbeli dupla
escaping miatt soha nem talált semmit. Egy javító kör mindhármat zárta,
mindegyiket a reviewer külön-külön visszaellenőrizte (fix visszamutálva →
az új teszt pirosra vált → visszaállítva). Lecke: [[L349]]–[[L351]].

A kör alatt a `main` egyszer mozdult (E99-R18/H3 self-heal negyedik
önjavítása, diszjunkt fájlkör) — rebase + teljes CI-újradispatch fogta meg.
Full Gate exact-SHA: 32337856382 success; Router CI: 32337858078 success;
post-merge célzott gate a friss `main`-en önállóan is zöld (6/6). Következő
SDD-kör: E08-R08 — gamification repository és storage schema.

## ✅ [HEAL E99-R18/H3] KÉSZ — a scope-audit jelentése feloldott SHA-t ír `origin/main` helyett, a kör-ág újraszinkronizálva — PR #348, squash `4105c695` (2026-08-20)

Negyedik H3-halt ugyanazon a körön, de a korábbi hármtól ELTÉRŐ gyökérokkal.
`docs/execution/pipeline-queue.tsv` egyszerre védett ÉS a pipeline saját
üzemeltetése által folyamatosan, a kör tartalmától függetlenül íródik (minden
kör-átmenet módosítja). A kör-ág szinkron-merge-e (`e75ae7a4`) néhány
másodperccel egy önálló, a pipeline-tól származó könyvelő commit
(`634562d7`, „E08-R06 done") előtt fagyasztotta be az `origin/main`
pillanatképét — a kör SAJÁT, nem-merge commitjai bizonyíthatóan sosem
érintették a queue-fájlt, mégis a végső `--base origin/main` scope-audit
`protected path changed`-et jelzett, MERT a kör-ág merge-elt másolata
(`E08-R06 … pending`) ténylegesen eltért a friss `main`-től (`E08-R06 …
done`) — egy squash-merge ezt a sort tényleg visszaírta volna. **Ez nem a
scope-audit hibája**: a `legacy_scope.py` fejléce szerint a végső audit
szándékosan a mergelhetőség kérdésére válaszol ([[L347]] már tisztázta ezt a
kettéválasztást a launch-HEAD implementer-scope kérdéstől) — a jelzés IGAZ
volt.

A tényleges javítás: a scope-audit JELENTÉSE a nyers `--base` argumentumot
(a szimbolikus `"origin/main"` sztringet) írta ki feloldott SHA helyett, ami
elrejtette, hogy két, néhány perccel eltérő futás a mögöttes bázis
elmozdulása ellenére azonosnak látszott — ez a self-healben is valódi
nyomozási időt vett el (a megosztott kör-munkapéldány elavult helyi
`origin/main` referenciája miatt egy reprodukciós kísérlet hamis `OK`-t
adott, amíg a blob-hash-ek közvetlen összevetése fel nem fedte az
eltérést). Fix: `tools/ai_router/legacy_scope.py::audit_legacy_scope` a
`base`-t egyetlen `git rev-parse` hívással a függvény elején SHA-ra oldja.

Feloldás: a kör-ág (`minimax/e99-r18-gov-12-generated-public-barrels`) friss
`origin/main`-nel újraszinkronizálva (a H8/`7458ca83` és a második H3/
`96f1ada2` mintáját követve, közvetlen push, PR nélkül — a szinkron csakis
upstream tartalmat húz be); a szinkron közben egy párhuzamosan pusholt F1
review-javítás (`8eeb3146`, architektúra-guard visszaállítás) is
becsatlakozott egy normál, force nélküli merge-dzsel. Végállapot: `dfbfb789`.

Saját méréssel igazolva a HALTED saját reprodukciós parancsával, FRISS `git
fetch` után: `tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e99-r18
--brief docs/rounds/e99-r18-gov-12-generated-public-barrels.md --base
origin/main` → `Legacy scope audit OK (origin/main..dfbfb789bff1, 16
changed path(s), 1 generated/ignored)` (előtte: `FAILED, protected path
changed: docs/execution/pipeline-queue.tsv`). Router CI zöld a heal-ágon
([32336566185](https://github.com/wolfcasaba/strumsight/actions/runs/32336566185),
headSha egyezik); `python3 -m pytest tools/tests -q`: 596 passed, 565
subtests passed (+2 új regressziós teszt, 0 törölve) —
`test_base_symbolic_ref_resolves_to_a_concrete_sha` (RED a fix előtt: a
jelentett `base` a nyers `"origin/main"` sztring; GREEN utána: 40-hex SHA)
és `test_protected_bookkeeping_file_flagged_by_upstream_drift_clears_after_resync`
(a valódi eset kicsinyített, valós útvonalat használó mása). Merge után
independens ellenőrzés friss `main`-en: `pytest tools/tests/
test_legacy_scope.py -q` 12/12 zöld.

**Előretekintő szabály** (rögzítve ADR 0112-ben): ha ugyanez a minta
(folyamatosan íródó védett fájl + hosszan nyitott kör-ág) ötödször
jelentkezik ugyanezen a körön, az már nem pontjavítást igényel, hanem
`outcome=escalate`-et.

Lecke: [[L348]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R06 KÉSZ — XP policy engine és diminishing returns — PR #347, squash `29e78eaf` (2026-08-20)

Magyarázható, verziózott ötkomponensű XP policy készült napi cap-pel,
practice-repeat csökkenő hozammal és explicit parent/child deduppal. A review
egy farmolható gyermek-event újraküldést talált; a javítás külön
`rewardedEventIds` history-állapottal és A5 RED→GREEN regressziós teszttel
zárta. Full Gate exact-SHA: 32333321826 success; Router CI: 32333305673
success. Következő SDD-kör: E08-R07 — level curve és profile projection.

## ✅ [HEAL E99-R18/H3] KÉSZ — a H8 ADR-0112 blokk landolt `main`-en, a kör-ág visszaszinkronizálva — PR #346, squash `ee010d39` (2026-08-20)

Harmadik H3-halt ugyanazon a körön: a kör-ág az `origin/main`-hez képest a
tiltott `docs/adr/0112-self-healing-pipeline.md`-et is módosította. Gyökérok
(class A, folyamat/precondition): a H8 self-heal (`7458ca83`) a saját,
kör-ág-specifikus javítását — helyesen — a kör SAJÁT ágára pusholta (L343
mintája), de ugyanabban a merge-commitban a saját ADR-0112 „Módosítás"
könyvelő blokkját is odaírta, és sosem mozgatta át `main`-re. Egyetlen
termék-brief `allowed_paths`-ának sem kellene ezt az utat tartalmaznia (ADR
0112 §2: ez kizárólag a self-heal saját, brieftől független joga) — az
`allowed_paths` bővítése tehát téves irányú fix lett volna.

Feloldás: a H8-blokk byte-azonosan landolt `main`-en (PR #346, `ee010d39`;
egy apró szám-ütközés-javítás `a109edbc` — az L346 számot időközben az
E08-R05 saját maga foglalta le), plusz egy új ADR-0112 blokk ([[L347]]) a
szabály rögzítésére: a L343 kör-ág-push kivétel kizárólag a FUNKCIONÁLIS
javításra érvényes, az ADR-0112 könyvelő commit sosem utazhat vele egy
bundle-ben. A kör-ág ezután visszamergelte a friss `main`-t (`96f1ada2`,
`6b9bf12f`) — a `docs/adr/0112` diffje emiatt teljesen eltűnt a kör-ág
`origin/main`-hez képesti diffjéből, allowlist-módosítás nélkül.

Saját méréssel igazolva a HALTED saját reprodukciós parancsával:
`tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e99-r18 --brief
docs/rounds/e99-r18-gov-12-generated-public-barrels.md --base origin/main` →
`Legacy scope audit OK (origin/main..6b9bf12f005c, 15 changed path(s), 0
generated/ignored)` (előtte: `FAILED, path outside allowed scope:
docs/adr/0112-self-healing-pipeline.md`). Router CI zöld a heal-ág fején
([32329319021](https://github.com/wolfcasaba/strumsight/actions/runs/32329319021));
`python3 -m pytest tools/tests -q`: 594 passed, 565 subtests passed (+1 új
hermetikus regressziós teszt, 0 törölve) —
`tools/tests/test_legacy_scope.py::LegacyScopeTest::
test_selfheal_adr_bookkeeping_must_land_on_base_not_only_the_round_branch`
szintetikus git-fixture-rel méri mindkét mintát (bundle → sértés; landolás+
visszamerge → a path eltűnik).

**Mellékesen feltárt, NEM javított lelet** (H8-mintát követve, [[L343]]): a
mergelt kör-ágon a teljes `pytest tools/tests -q` 2 piros tesztet mutat
(`test_e99_r18_scope_debris_revert.py`), mert a kör SAJÁT, ezt a self-healt
MEGELŐZŐ §0.0e munkája egy 12. bejegyzéssel bővítette az `allowed_paths`-t
(`docs/adr/0339-...`), a két korábbi H3 self-heal által pinnelt tuple-ök
viszont 11-et várnak. Igazoltan a resync ELŐTT is fennállt (a merge sem a
briefet, sem a guard-tesztet nem érintette konfliktussal). A round saját
allowlist-bookkeeping munkája — a brief §0.0f-je és a következő E99-R18
dispatch dolga, nem a self-healé.

Lecke: [[L347]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R05 KÉSZ — Reward eligibility és trust policy — PR #345, squash `30fa8138` (2026-08-20)

Determinisztikus `RewardEligibilityPolicy` (application) +
`DefaultRewardEligibilityPolicy`/`RewardEligibilityPolicyConfig`
(infrastructure): négy KÜLÖN dönthető kapu (alap-XP, quality bonus, mastery,
verified), mindegyik stabil `RewardReason`-nal elutasításkor, verziózva
(`policyVersion: int`, konzisztens az R03 `RewardLedgerEntry.policyVersion`
mezőjével). A bizalom (`EvidenceTrust`, a mastery/verified kapukhoz) és a
mért jelminőség (`quality`, a quality bonus + mastery kapukhoz) SZÁNDÉKOSAN
független tengely — alacsony bizalom önmagában sosem tiltja a quality
bonust, és a hiányzó/fatális minőség sosem alakul át néma számmá (ADR 0286
§1). Döntés: [ADR 0338](docs/adr/0338-reward-eligibility-policy-four-gates.md).

**A brief előre kiosztott `ADR 0303`-a elavult volt** — a
`.pipeline/inflight/adr/0303` marker valójában az E07-R17 körhöz tartozott
(mérve a pre-flightban); az élő `tools/round-slots.py reserve-adr` **0338**-at
adott, dokumentált §0.0 brief-revízióval. [[L267]] precedense („pre-asszignált
ADR-szám elavulhat") itt egy ÚJ változatban jelentkezett: a szám NEM
sosem-foglalt volt, hanem egy MÁSIK kör markere alatt élt — lásd [[L346]].

Független review egy MAJOR leletet talált: a `verified` kapu `mastery`-től
való függetlensége egyetlen teszttel sem volt bizonyítva — mért,
reprodukált mutációs próba (`_evaluateVerified` ideiglenes cseréje
`return mastery;`-re, izolált `/tmp` klónban) a teljes 15/15 tesztet
zöldön hagyta a rontás ALATT is. Javító kör (ugyanaz a motor, codex) egy
cellával zárta (`mastery` adott, `verified` `insufficientTrust`-tal
elutasítva); a mutáció megismétlése utána PIROSRA vált, ahogy kell.
Security review (risk=high, kötelező) PASS, 0 BLOCKER/MAJOR, 3 alacsony
kockázatú NOTE (két már ebben a körben dokumentált: `EvidenceTrust`
sorrend-függés az ADR 0338 §7-ben; a purity-őr még nem fedi a
gamification `application/`-t — jövőbeli bekötő kör dolga).

A kör alatt a `main` egyszer mozdult (párhuzamos E99-R18 self-heal-lánc,
ugyanabban a megosztott munkafában) — `git merge --no-ff origin/main`
konfliktus nélkül, majd Full Gate ÉS Router CI (utóbbi manuálisan
dispatch-elve, mert a sync-merge diffje már nem érintett trigger-útvonalat
— [[L344]] pontosan ezt írja elő) mindkettő zöld a merge SHA-n
(`82b8b683`): [Full Gate](https://github.com/wolfcasaba/strumsight/actions/runs/32327526505),
[Router CI](https://github.com/wolfcasaba/strumsight/actions/runs/32328486649).
Post-merge célzott gate a friss `main`-en (`30fa8138`) önállóan is zöld
(format, analyze, 16/16 teszt, architecture, secrets, l10n). Scope-audit:
a kör saját commitjai (pre-flight + implementáció + javítás) mind az 5
`allowed_paths` bejegyzésen belül, 0 kívül.

Review: [docs/reviews/e08-r05-review.md](docs/reviews/e08-r05-review.md)
(APPROVED, F1 FIXED `8a989af5`). Leckék: [[L267]], [[L344]], [[L346]].
Következő kijelölt SDD-kör: **E08-R06 — Kör 6 (XP policy engine és
diminishing returns)**, előfeltétele ez a kör (jogosultsági policy) és az
R03 ledger.



## ✅ [HEAL E99-R18/H3] KÉSZ — H8 kör-ági coexist-teszt bekerül az allowed_paths-ba, két bejegyzéssel — kör-ág `6a494d5e` (2026-08-20)

A D4 §0.0c narrowing fix (glob → explicit `practice_generator`-regisztráció)
technikailag zöld volt, de a scope-audit egy fájlon bukott:
`tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py` — ezt
a **H8** self-heal (ugyanaznap korábban) írta közvetlenül a kör-ágra, a
normál brief-szerkesztési folyamaton kívül, ezért sosem került az eredeti
`allowed_paths`-ba. A D4 fix legitim módon érintette (pontosan azt a
mechanizmust méri, amit átalakít) — ez a `tools/tests/
test_e99_r18_scope_debris_revert.py` (az ELŐZŐ, 2026-08-19-i H3-önjavítás
terméke) saját docstringje szerinti E07-R29 „valódi bővítés" minta, nem a
§0.0 debris-revert minta ismétlődése.

**Mért csavart:** a bővítés magába az ELŐZŐ H3 debris-revert regressziós
őrbe ütközött, ami bájtra-egyezést követel a pinnelt `allowed_paths`-ra — az
őr frissítése pedig, mivel saját maga sem szerepelt az eredeti listán,
önmagában ÚJ scope-rést nyitott volna. `grep -rl` igazolta, hogy harmadik
fájl nem hivatkozik a pinnelt konstansra, tehát a lánc pontosan **két**
bejegyzésnél zár (a coexist-teszt + maga az őr fájlja); az új regressziós
bizonyítékot a meglévő őr-fájlba kellett összevonni, nem külön fájlba, hogy
ne nyisson egy harmadikat.

Saját méréssel igazolva: a HALTED-ben rögzített reprodukciós paranccsal
(`tools/scope-audit.py --base 7458ca83...`) `Legacy scope audit OK (11
changed path(s))` (előtte: `FAILED`, 1 sértés); `python3 -m pytest
tools/tests -q`: 614 passed, 2 skipped (611-ről, +3 új regressziós teszt, 0
törölve). Router CI a kör-ág friss fejjel
([32326908611](https://github.com/wolfcasaba/strumsight/actions/runs/32326908611))
zöld. A H8 mintáját követve ([[L343]]) NEM main-merge: normál (nem force)
push a kör saját ágára (`6a494d5e`), a PR/review a következő E99-R18
dispatch dolga marad.

Lecke: [[L345]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R04 KÉSZ — Activity outbox és megbízható feldolgozás — PR #344, squash `318edd6d` (2026-08-20)

A Gamification feature most korlátos, perzisztens lokális activity outboxot
kapott explicit enqueue/drain contracttal. A ledger-írási hiba nem jut vissza
a már mentett feature-sessionhöz; az ack csak sikeres, idempotens
`appendIfAbsent` után történik. Sérült rekord, retry-limit és kapacitás feletti
legrégebbi pending rekord lekérdezhető karanténba kerül. A konstruktor pozitív
kapacitást és retry-limitet követel, a karantén snapshotja restart után is
visszaolvasható. Döntés: [ADR 0333](docs/adr/0333-activity-outbox-reliable-processing.md).

Független correctness review **APPROVED**, security review **PASS**; a végső
izolált A4 mutáció (ack a ledger-írás előtt) pirosra vitte a célteszteket,
visszaállítás után 15/15 zöld. Exact pre-merge CI a `8402ee42` headen: Full
Gate [32323029473](https://github.com/wolfcasaba/strumsight/actions/runs/32323029473)
és Router CI [32324054702](https://github.com/wolfcasaba/strumsight/actions/runs/32324054702)
success. A post-merge `flutter analyze` zöld; a teljes post-merge gate
ismételt futtatása a root worktree-ben a gate-scripten belül az analyze lépés
után nem adott terminális összegzést, ezért nem tekinthető további gate-bizonyítéknak.

Következő kijelölt SDD-kör: **E08-R05 — Reward eligibility és trust policy**.

## ✅ [HEAL E99-R18/H8] KÉSZ — origin/main szinkron, unió generated-path feloldás — kör-ág `7458ca83` (2026-08-20)

A lánc az E99-R18 (GOV-12) kör-ágának `origin/main` szinkronjánál H8-cal
állt meg: a briefen kívül `tools/round-slots.py`-ban is tartalmi ütközés
volt az E99-R17 (squash `8d7b6a67`) exact-set `GENERATED_PATHS`-a és az
E99-R18 D4 saját, glob-alapú `GENERATED_PATH_PATTERNS`/`is_generated_path`
mechanizmusa között — ez NEM a dokumentált brief-only H8 minta. Mérve: a
két mechanizmus additív (mindkét oldal SAJÁT regressziós csomagja csak a
sajátját méri); a feloldás mindkét konstanst megtartja, az `effective_paths`
predikátumát unióvá bővíti, és egy új teszt
(`test_round_slots_generated_paths_and_patterns_coexist.py`) méri a
kombinált esetet. Normál (nem force) push a kör SAJÁT ágára — **ez NEM
`main`-merge**, a H8-recept szerint a PR/review a következő E99-R18
dispatch dolga marad.

**A kötelező teljes `pytest tools/tests -q` gate egy MÁSIK, a H8-tól
független, a kör SAJÁT D4 kódjában már a merge előtt is jelen lévő hibát
tárt fel** (empirikusan igazolva a kör pre-merge HEAD-jén is):
`SlotPlanningTest::test_real_epic_four_rounds_are_correctly_rejected`
piros, mert a D4 broad glob minden feature `public.dart`-ját generáltnak
minősíti, holott csak a `practice_generator` lett migrálva — 25+18 nyitott
brief két másik feature-ön ütközne felügyelet nélkül, ha ez elérné a
`main`-t. Router CI ezért piros (run
[32321598642](https://github.com/wolfcasaba/strumsight/actions/runs/32321598642)) — **ez a self-heal TUDATOSAN nem javította**: a helyes hatókör
(pl. migrált-feature allowlist) a kör saját implementer+reviewer
ciklusának termékdöntése, nem az ADR 0112 §2 szűk (brief/eszköz)
jogosultságáé. A lelet a brief saját `## 0.0b` szakaszába, a
`docs/LESSONS.md` **L343**-ba és a heal-status `detail=`-jébe is bekerült,
hogy a következő E99-R18 dispatch az ELSŐ olvasatnál lássa, review előtt
zárja.

Lecke: [[L343]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E99-R17 (GOV-11) KÉSZ — szegmentált ARB-források és determinisztikus aggregátum — PR #343, squash `8d7b6a67` (2026-08-20)

Az angol és magyar ARB-k immár `base/` és feature-fragmentum forrásokból
épülnek; a `tuner` 14 kulcsa önálló fragmentumba került, az `app_{en,hu}.arb`
deterministikus, kulcsrendezett aggregátum. A gate a `--check` úton a
frissességet és a 1 405 üzenet kulcs-/placeholder-paritását is méri. Az
aggregátumok a slot-tervezőben regenerálhatók, ezért nem blokkolják a
párhuzamos köröket, a feature-fragmentumok viszont továbbra is ütköznek.

Független review APPROVED; high-risk security re-review PASS WITH NOTE. A
reviewer valódi-sértés próbája a fragmentumközi `@key` tulajdonlás guardját
ideiglenesen kikapcsolva két regressziós tesztet pirosra vitt, majd
visszaállítás után zöldet mért. Exact-SHA CI: Full Gate
[32318857856](https://github.com/wolfcasaba/strumsight/actions/runs/32318857856)
és Router CI
[32318859249](https://github.com/wolfcasaba/strumsight/actions/runs/32318859249)
success. Post-merge célzott gate a friss `main`-en 7/7 zöld. Következő,
kapcsolódó SDD-kör: **E99-R18 (GOV-12)** — generált `public.dart` barrelek.

## ✅ [HEAL E99-R17/H6] KÉSZ — hermetikus WrapperModeTest az ambiens MiniMax-endpoint szivárgás ellen — PR #342, squash `bdad2a64` (2026-08-20)

Az E99-R17 minimax implementer `blocked`-ot jelzett: a kötelező §7 gate
(`python3 -m pytest tools/tests -q`) 2 hibán bukott a
`tools/tests/test_claude_harness_engines.py::WrapperModeTest`-ben, mindkettő
a kör `allowed_paths` listáján kívül — jogos blokk, nem implementer-hiba.

**Gyökérok (Class A, mérve):** a `run_wrapper()` teszt-fixture
`dict(os.environ)`-ból indul. Amikor ez a pytest-gate egy ÉLŐ
`ROUND_ENGINE=minimax` session Bash-hívásaként fut (pont ez az eset — a
minimax implementer a saját gate-jét futtatja), a szülő session saját,
jogos `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`MINIMAX_API_KEY` exportjai öröklődnek a
szimulált `sonnet-impl` (natív, "nincs override") alfolyamatba, és két
asszerció a szivárgást méri, nem a `mm-round.sh` tényleges viselkedését.
Önálló, kód nélküli reprodukció megerősítette: pontosan ugyanez a 2 hiba.
Ez **tisztán teszt-izolációs** hiba — egy valódi, friss `sonnet-impl`
dispatch a driver saját tiszta al-folyamatából indul, a `mm-round.sh`
termék-kód méve NEM hibás.

**Javítás:** `run_wrapper()` explicit törli a négy szivárgás-gyanús
változót az ambiens env-másolatból, mielőtt a teszt saját `extra_env`-je
rákerülne. Regressziós teszt (RED→GREEN mérve, izolált worktree-ben):
`test_ambient_endpoint_env_does_not_leak_into_a_subscription_mode_run`.
Csak ez az egy tesztfájl változott (47 sor +, 0 −); `tools/mm-round.sh` és
minden termék-fájl érintetlen. Teljes `tools/tests` mindkét irányban zöld
(tiszta env 587 passed; a pontos szivárgás-reprodukcióval 586 passed 1
skipped — 0 failed mindkétszer). Router CI zöld a merge SHA-n. Részletek:
[[L341]].

**A self-heal SZÁNDÉKOSAN nem vitte előre E99-R17 tartalmi munkáját** — a
kör saját ága (`minimax/e99-r17-gov-11-l10n-parallel-safety`, benne a már
zöld-tesztelt F1 javítással) érintetlen marad; a lánc ezután egy FRISS
kör-sessionben folytatja E99-R17-et, immár hermetikus gate mellett.

## ✅ E08-R03 KÉSZ — Reward ledger és idempotencia-index — PR #340, squash `39c0bd5f` (2026-08-19)

Append-only egyetlen igazságforrás a jutalmakra: immutable `RewardLedgerEntry`
(`sourceEventId`, policy-verzió, XP-komponensek, `RewardReason` kód) +
`RewardReason` stabil enum + `RewardLedgerRepository` interfész (nincs
`update`/`delete`) + `LocalRewardLedgerRepository` a `JsonDocumentStore`
mintáján (NEM `JsonCollectionStore` — nincs `capRecords`/`maxItems`, egy
audit-ledger nem veszíthet néma evictionnel). Az `appendIfAbsent` egyetlen
atomikus Future-tail-lel szerializált (`SongTransport._commandTail` mintája,
ADR 0301 2. pont) — a `contains`-majd-`append` szétválasztás technikailag
kizárva. `lib/features/gamification/domain/rewards/`, `data/`, bővített
`public.dart` (csak export-sor, a konkrét implementáció szándékosan NEM
exportált). Implementer: Codex (`~/.codex`, `gpt-5.6-terra`), orchesztrátor/
reviewer Claude Sonnet 5. [ADR 0301](docs/adr/0301-reward-ledger-append-only-idempotency.md).

**Ez a kör második nekifutása.** Az első (21:25 UTC) H6-tal állt meg — a
Codex implementer `blocked`-ot jelzett egy hiányzó generált Flutter l10n
miatt, amit egy `git worktree add`-dal (nem klónnal) nyitott munkapéldány
okozott. Egy self-heal (PR #338, [[L339]]) a burkoló scripteket javította
(`codex-round.sh`/`mm-round.sh` mostantól minden dispatch előtt önmaga
futtatja a `prepare-flutter-generated.sh`-t a saját workdirjén). Ez a futás
egy friss `git clone`-ból indult; a korábbi két félkész, COMMITOLATLAN
munkapéldányt (`ss-codex-e08-r03` — `stopped`, egy párhuzamos implementer
által már foglalt branch miatt main-en ragadt uncommitolt diffel;
`ss-codex-e08-r03-impl` — `blocked`, a fenti l10n-hiba) nem használtam fel:
a brief §0.2 „félkész, jelöletlen munka → indíts tisztán" szabálya szerint.

**A review saját kézhez, izolált `/tmp` klónban reprodukálta az A2
mutációs próbát, nem az implementer önjelentésére hagyatkozott.** Az
atomikus Future-tail-et ideiglenesen egy `hasProcessedEvent` + `await
Future.delayed` + feltétlen append párra cserélve az A2 cella pontosan a
várt módon (`Actual: WhereIterable<bool>:[true, true]`) PIROSRA vált,
visszaállítás után ZÖLD. A [review](docs/reviews/e08-r03-review.md)
**APPROVED** (0 BLOCKER/MAJOR/MINOR, 1 NOTE — a jelzésfájl `gate_shape=
VIOLATION` mezője mért HAMIS POZITÍV volt: a `codex-round.sh` `verify_claim()`
regexe a `codex exec` induló, teljes prompt+preambulum szöveget EGYETLEN
log-sorba író hívása miatt két, egymással össze nem függő idézetet — a
brief `round-gate.sh` hivatkozását és a preambulum MÁSIK példájából
származó `git add -A && git commit` mintát — egyetlen találatnak látott a
sortörés nélküli kereséssel; minden TÉNYLEGES `/bin/bash -lc 'tools/
round-gate.sh ...'` végrehajtás a naplóban csővezeték/lánc nélküli volt,
lásd [[L340]]).

**A kör alatt a `main` HÁROMSZOR mozdult** (más, párhuzamos munka: a
`ops/rag-retrieval-quality` PR #336 és két pipeline-feloldó commit, az
egyik egy VALÓDI párhuzamos kör, E99-R17, ugyanebben a megosztott
munkafában). Mindhárom alkalommal `git merge --no-ff origin/main` +
teljes CI-újradispatch a §0.3 szerint, mielőtt a merge SHA-n bármilyen
zöld kapu evidencia számított volna. A záró rituálékat (ez a
HANDOFF-frissítés, RTM, LESSONS, git-notes) a `tools/round-merge-lock.sh`
zárral sorosítva készítettem, az E99-R17 branch-ét/PR-ját nem érintettem.

**Zöld kapu, mind a végleges, main-mozgás utáni HEAD-en (`02477969`):**
Full Gate [32313777603](https://github.com/wolfcasaba/strumsight/actions/runs/32313777603)
és Router CI [32313779449](https://github.com/wolfcasaba/strumsight/actions/runs/32313779449)
success. Post-merge célzott gate a friss `main`-en (`39c0bd5f`) önállóan is
zöld (7/7: format, analyze, 9 alteszt, architecture, secrets, l10n).
Scope-audit: 7/7 megváltozott fájl az engedélyezett listán, 0 kívül.

Egy mért lecke: **[[L340]]** (a `gate_shape` anti-hallucináció-őr hamis
pozitívot adhat egy hosszú, sortörés nélküli log-sorra — a reviewer NE a
mezőre, hanem saját izolált gate-újrafuttatásra hagyatkozzon). Nyitott
tétel az E08-R02-ből öröklődve, még mindig releváns a Kör 4-nek: a
security-review MINOR-1 leletét (architektúra-guard marker-lista
hálózati/fájl-IO kiegészítése) rendezni kell, mielőtt az outbox valódi
sink-szomszédot hoz a gamification domain mellé. Következő kör:
**E08-R04** (Activity outbox és megbízható feldolgozás), új sessionben.

## ✅ [HEAL E08-R03/H6] KÉSZ — round wrapperek önelőkészítik a Flutter l10n-t dispatch előtt — PR #338, squash `911e5145` (2026-08-19)

E08-R03 H6-tal állt meg: a Codex implementer `blocked`-ot jelzett, mert a
`flutter analyze` 1071 független hibával blokkolt a hiányzó generált
`lib/l10n/app_localizations.dart` miatt. A nyomozás saját méréssel (a
`.pipeline/session-E08-R03-20260819T212506.log` és `/tmp/codex-e08-r03.log`
teljes visszakövetésével, nem bemondásra) igazolta a gyökérokot: az
orchesztrátor a `/home/ubuntu/ss-codex-e08-r03` klónt HELYESEN készítette elő
(`tools/prepare-flutter-generated.sh` lefutott, a generált fájlok ott
léteztek), de a TÉNYLEGES Codex-dispatch a `/home/ubuntu/ss-codex-e08-r03-
impl` útvonalra ment — ami `git worktree list` szerint egy `git worktree
add`-dal nyitott WORKTREE volt a klónról, nem önálló klón. A gitignore-olt
generált kimenet worktree-k közt nem öröklődik, ezért a `-impl` sosem kapta
meg a saját `gen-l10n` futtatását, noha `.dart_tool/` (tehát valamilyen `pub
get`) már lefutott ott. Az implementer helyesen `blocked`-ot jelzett ahelyett,
hogy saját maga hívta volna a `tools/prepare-flutter-generated.sh`-t — az a
saját tiltott zónáján (`tools/**`) kívül esett.

Ez a **negyedik** mérés ugyanerre a hibaosztályra (korábbi: L222/E06-R07,
L228/E06-R10, L230/E06-R11) — mindegyik javítása eddig egy PRÓZAI lépés volt
az orchesztrátor promptjában/skill-jében, legutóbb a `sdd-round-driver`
SKILL.md §3-ba ágyazva. Ez a lépés MOST IS a helyén volt és le is futott —
csak épp egy másik könyvtárra, mint ahova a tényleges dispatch ment. A
javítás ezért a mechanikus legalsó rétegbe került: `tools/codex-round.sh` és
`tools/mm-round.sh` mostantól minden dispatch ELŐTT lefuttatja a **workdir
saját másolatát** (`"$workdir/tools/prepare-flutter-generated.sh"`,
argumentum nélkül — L232/E06-R13), fail-open, függetlenül attól, mit tett az
orchesztrátor, és függetlenül attól, hogy a workdir klón vagy worktree.
Regressziós teszt (`tools/tests/test_round_wrapper_flutter_prerequisite.py`,
valódi mért adat: a `ss-codex-e08-r03` → `ss-codex-e08-r03-impl` worktree-alak
szó szerinti reprodukciója hamis codex/claude/flutter binárisokkal) — piros a
javítás előtt (a flutter binárist egyik burkoló sem hívta meg), zöld utána
(`pub get` → `gen-l10n` → engine-hívás, ebben a sorrendben, a fájl a
worktree-ben jön létre). `python3 -m pytest tools/tests -q`: 580 passed, 566
subtests passed; a négy érintett burkoló-tesztfájl (`test_qwen_
implementer_hardening.py`, `test_claude_harness_engines.py`, `test_fix_
workspace_origin.py`, `test_prepare_flutter_generated.py`) külön futtatva is
zöld (53 passed) — nincs regresszió. Router CI
[32308153558](https://github.com/wolfcasaba/strumsight/actions/runs/32308153558)
success a merge-előtti exact `32aa633a` SHA-n (nincs Dart-változás, tehát a
Router CI az egyetlen szükséges CI-bizonyíték). Lecke: [[L339]].

A self-heal nem nyúlt a leftover `/home/ubuntu/ss-codex-e08-r03` /
`ss-codex-e08-r03-impl` munkapéldányokhoz (nincs bennük nyitott PR — az
implementer a félkész implementációt commit nélkül hagyta) — a következő
E08-R03 dispatch a saját §0.2 „Örökség-ellenőrzés" lépésével dönt a
sorsukról, és mostantól, akármelyiket is választja, a saját workdir-jét maga
a burkoló készíti elő.

## ✅ [HEAL E99-R18/H3] KÉSZ — revert-not-expand: implementer scratch debris — PR #337, squash `80b70d1e` (2026-08-19)

A MiniMax implementer (`/home/ubuntu/ss-minimax-e99-r18`, ág
`minimax/e99-r18-gov-12-generated-public-barrels`, HEAD `e9c4a26b`) három
nyomkövetetlen fájlt hagyott a brief `allowed_paths`-án kívül
(`test_project/lib/features/demo/{public.dart,public/application.dart,
public/domain.dart}`). A Terra orchesztrátor-session ezt H3-mal állította le
(`.pipeline/HALTED`, 20:43:38Z), holott `docs/execution/
pipeline-orchestrator-prompt.md` VIOLATION-sora már eleve két utat ismer: „a
listán kívüli fájlokat **vissza kell állítani**, vagy H3 halt" — és a §2
„Önállóan dönthetsz" felsorolása kifejezetten megnevezi „az
engedélyezett-fájllista **szűkítését**" mint a kör saját hatáskörét.

Az önjavítás (ADR 0112, 1/3. kísérlet) méréssel igazolta, hogy a három fájl
NEM legitim munka — nulla hivatkozás bármely tracked/untracked forrásban,
tartalma bájtra megegyezik a `gen_public_barrel_test.dart` saját, már
`Directory.systemTemp`-be izolált fixture-jével, egyik D-feladatot vagy
„Tilos zóna" cellát sem fedi — és ezt dokumentált `## 0.0 Pre-flight
revízió`-ként írta a brief-be: a helyes folytatás REVERT, `allowed_paths`
bővítése NÉLKÜL (a `test_e07_r29_accessibility_privacy_scope.py` precedens
tükörképe, ahol a listán kívüli fájlok igazoltan hiányzó deliverable-ek
voltak). Az ADR 0112-t egy dated Módosítás-blokk egészíti ki, amely ezt a
precedenst SZŰKEN általánosítja (csak akkor alkalmazható, ha a kifogásolt
útvonalak mérhetően függetlenek minden deliverable-től — egyébként H3/
escalate marad az alapértelmezés). Regressziós teszt (`tools/tests/
test_e99_r18_scope_debris_revert.py`, real measured data): egy eset
valóban piros-a-javítás-előtt/zöld-utána (a brief §0.0 dokumentációja), a
többi a mért adatot zárja a valódi `audit_legacy_scope()`-pal mindkét
irányban. `python3 -m pytest tools/tests -q`: 578 passed, 565 subtests
passed (833→834 teszt-fájl, egyetlen gate-artefaktum hash sem változott).
Router CI [32302589265](https://github.com/wolfcasaba/strumsight/actions/runs/32302589265)
success a merge-előtti exact `547e524e` SHA-n (nincs Dart-változás, tehát a
Router CI az egyetlen szükséges CI-bizonyíték).

A self-heal SZÁNDÉKOSAN nem nyúlt a megállt implementer saját
worktree-jéhez/ágához — az ADR 0112 §2 jogosultsága a briefre és az
engedélyezett-fájllistára szól, nem egy még nem review-zott implementer-ág
tartalmára. A következő E99-R18 dispatch dönt: újrahasznosítja-e a meglévő
worktree-t (a három fájl törlése után) vagy frissen indul.

**Mért mellékhatás, dokumentálva ([[L338]]):** a self-heal PR-be előre írt
`[[L333]]` lecke-hivatkozás a merge KÖZBEN ütközésbe került az egyidejűleg
záruló E08-R02 saját `L333–L336` foglalásával (`6db8abcc`) — a helyes,
frissen leolvasott szám `L337` lett, és ez a záró commit javítja a már
merge-elt hivatkozásokat (ADR 0112, a brief) is.

## ✅ E08-R02 KÉSZ — Kanonikus tanulási esemény-szerződések — PR #335, squash `a3d98ed2` (2026-08-19)

A gamifikáció EGYETLEN bemenete: a feature-agnosztikus, immutable, verziózott
`LearningActivityEvent` sealed hierarchia (`lib/features/gamification/domain/
activity/`) hat altípussal (Practice, Song, Analysis, Plan, Tutor, Vision),
hívó-adta stabil `eventId`-vel, kötelező `schemaVersion`-nel (ismeretlen
érték hibát dob, nem csendes default), és explicit `type`-discriminatorral a
JSON round-tripben (nem mezőkitalálás). `ActivitySource`/`EvidenceTrust`
enumok, `RewardEligibility` adatkontraktus (típus, nem logika — a döntési
logika Kör 5), `lib/features/gamification/public.dart` egyetlen belépő. A kör
NEM integrál egyetlen feature-t sem — Kör 24–26 dolga. Implementer: Codex
(`~/.codex`, `gpt-5.6-terra`).

**A pre-flight egy KRITIKUS, mért hibát javított dispatch előtt: az előre
kiosztott `ADR 0300` már foglalt volt.** `.pipeline/inflight/adr/0300`
`round=E07-R15` tartalommal létezett (foglalva 2026-08-16, a brief 2026-08-18-i
írása ELŐTT), de a `docs/adr/`-ban nincs `0300-*.md` — a számot egy korábbi
kör foglalta, sosem fogyasztotta el. A friss `tools/round-slots.py
reserve-adr` a valódi **`ADR 0329`**-et adta. A pre-flight egy második,
technikai kérdést is tisztázott: az A6 architektúra-őr nem bővítheti a
`tool/check_architecture.dart` hardcode-olt `_isSharedDomain()` listáját (az
a fájl nincs a kör engedélyezett listáján), ezért a bevált E07-R02 mintát
követve egy önálló teszt-csoport épült `test/core/architecture_dependency_
test.dart`-ban, a meglévő `_forbiddenDomainMarkerOffenders`/`_withoutTrivia`
segédfüggvények újrafelhasználásával — az implementer ezt pontosan a
pre-flight §0.0.2 útmutatása szerint valósította meg.

**A review saját kézhez, izolált `/tmp` klónban mindkét kötelező
valódi-sértés próbát megismételte, nem az implementer önjelentése alapján
fogadta el.** A `schemaVersion` guard ideiglenes eltávolítása az A2 cellát
pontosan a várt hibaüzenettel vitte pirosra; egy befecskendezett
`package:flutter/foundation.dart` import az új architektúra-guardot vitte
pirosra, pontos hibaüzenettel. Mindkettő tiszta visszaállítás után zöld. A
[correctness review](docs/reviews/e08-r02-review.md) **APPROVED** (0
BLOCKER/MAJOR/MINOR, 3 NOTE — enum wire-formátum a Dart `.name`-en, nem
explicit kódtérképen, ADR 0257 precedenséhez képest; az A1 „const
konstruktor" bizonyítéka forráskód-szintű, nem futásidejű teszt; a
`score`/`duration` minden altípuson univerzális mező, a Kör 24-26
integrátornak érdemes lehet altípusonként felülvizsgálnia). A kötelező
[security review](docs/reviews/e08-r02-security.md) (`risk=high`) **PASS**
(0 CRITICAL/BLOCKER/MAJOR, 1 MINOR, 4 NOTE) — az egyetlen MINOR: az új
architektúra-guard marker-listája nem fed hálózati/fájl-IO markert
(`dart:io`/`dart:convert`/`package:dio/`/`package:http/`), ami MA nem aktív
sértés (a domain tiszta), de a Kör 3 (ledger) / Kör 4 (outbox) előtt
javítandó, mielőtt azok valódi sink-szomszédot hoznak a domain mellé.

**Két mért process-hiba a záráshoz vezető úton, mindkettő javítva, mindkettő
lecke.** (1) Az implementer `done`-t jelzett, de a commitja nem volt
pusholva — az orchesztrátor pusholta, mielőtt bármilyen review érvényes
lehetett volna ([[L334]]). (2) A biztonsági review ELSŐ futása ezt az
pusholatlan állapotot mérte (egy worktree-izoláció a push ELŐTT ágazott le),
és emiatt téves BLOCKER-t adott — a push megerősítése után frissen
klónozva megismételve **PASS** lett ([[L335]]). Egy harmadik lecke a
CI-exact-SHA ellenőrzésről: a záró review-dokumentum-commitok nem mindig
váltanak ki friss Router CI-futást, ha nem érintik a `docs/rounds/**`
útvonalat — a brief §11 kitöltése (ami ÉRINTI) végül friss, a tényleges
végső SHA-n mért Router CI-futást adott ([[L336]]).

**Zöld kapu.** A `round-ci-plan.py` `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, mindkét review-t és a brief §11-et is tartalmazó HEAD-en
(`4b46ef44` — egy köztes SHA-n dispatch-elt Full Gate-et a §11-lezáró commit
miatt újra kellett dispatch-elni, hogy pontosan a merge SHA-n legyen
evidencia): Full Gate
[32300885059](https://github.com/wolfcasaba/strumsight/actions/runs/32300885059)
és Router CI
[32300867375](https://github.com/wolfcasaba/strumsight/actions/runs/32300867375)
success. Post-merge célzott gate a friss `main`-en (`a3d98ed2`) önállóan is
zöld (7/7: format, analyze, 2 teszt-útvonal, architecture, secrets, l10n).

**A kör alatt egy párhuzamos self-heal (E99-R18, egy másik kör H3 haltjának
javítása) futott ugyanebben a megosztott munkafában** — a záró rituálék
(ez a HANDOFF-frissítés, RTM, LESSONS, git-notes) a `tools/round-merge-lock.sh`
zárral sorosítva készültek, a másik kör branch-ét/PR-ját nem érintettem.

Négy mért lecke: **[[L333]]** (egy brief-be előre írt ADR-szám a brief-írás
és a kör-indítás között elavulhat, verseny nélkül is), **[[L334]]** (a
legacy Codex-motor commitol, de nem feltétlenül pushol), **[[L335]]** (a
security review dispatch-elése az implementer push-ja előtt hamis BLOCKER-t
termel egy elavult snapshot miatt), **[[L336]]** (a CI-dispatch utáni,
csak `docs/reviews/**`-et érintő commit nem vált ki friss Router CI-t —
merge előtt mindig a tényleges végső SHA-n kell ellenőrizni). Nyitott tétel
a Kör 3/4-nek: a security review MINOR-1 leletét (guard marker-lista
hálózati/fájl-IO kiegészítése) rendezni kell, mielőtt a ledger/outbox valódi
sink-szomszédot hoz a gamification domain mellé. Következő kör: **E08-R03**
(Reward ledger és idempotency index), új sessionben.

## ✅ E08-R01 KÉSZ — Gamification baseline és mért migrációs szerződés — PR #334, squash `0e19f67d` (2026-08-19)

Az Epic 8 nyitókörének kimenete az
[`epic-08-start.md`](docs/baseline/epic-08-start.md): file:line alapú leltár a
Progress, Streak, Learn és Share tényleges feature- és import-éleiről, aktuális
és legacy storage-kulcsokról/wire-alakokról, streak-freeze, Daily Challenge és
lesson-star határokról, a meglévő guardokról és az ADR 0289/0290 dark-pattern
checklistről. Az új [ADR 0328](docs/adr/0328-measured-gamification-baseline-contract.md)
rögzíti, hogy a baseline migrációs szerződés, nem új jutalom-policy.

Az első független review két MAJOR leletet mért: a baseline tévesen tagadta a
Share production forrásait és a Learn közvetlen Progress/Streak importjait,
valamint több ADR-követelményt olyan teszttel jelölt lefedettnek, amely csak
szomszédos viselkedést vizsgált. A MiniMax javító köre mindkettőt zárta; a
végső [review](docs/reviews/e08-r01-review.md) APPROVED (0 BLOCKER/MAJOR,
1 MINOR tipográfiai NOTE). Full Gate
[32293515991](https://github.com/wolfcasaba/strumsight/actions/runs/32293515991)
és Router CI
[32293556103](https://github.com/wolfcasaba/strumsight/actions/runs/32293556103)
success a merge-előtti exact `1949f96c` SHA-n; post-merge célzott gate a friss
`main`-en (`0e19f67d`) 9/9 zöld. Következő kör: **E08-R02**, új sessionben.

## ✅ E07-R30 KÉSZ — Evaluation harness, shadow rollout és Epic 7 lezárás — PR #333, squash `ee5821dd` (2026-08-19) — **EPIC 7 LEZÁRVA**

Epic 7 (AI Practice Generator) záró köre. Implementer: Codex (`~/.codex`).
`ShadowPlanGenerator` (`lib/features/practice_generator/application/service/
shadow_plan_generator.dart`, ÚJ) az Epic 7 **első éles, vég-az-végig
kompozíciója**: evidence → skill estimate → priority → candidate selection →
time budget → weekly schedule → a VALÓDI `GenerationOrchestrator.generate()`,
egy saját, no-op `GenerationPlanActivation`-nel (hívásszámláló, nulla
perzisztencia) — a shadow-terv ugyanazon a determinisztikus kódúton születik,
mint az éles út, de sosem aktivál valódi állapotot. A fájl szerkezetileg sem
importál semmit a `data/local/`-ból vagy az `active_plan_controller.dart`-ból,
és nincs `lib/` consumere / `public.dart` exportja — a futó appból
elérhetetlen.

**Pre-flight (§0.0) két, a mért CI-vel ütköző brief-útvonalat javított
dispatch ELŐTT.** (1) A brief (és az SDD-fejezet saját fájllistája is)
`test/features/practice_generator/property/`-t írt elő a két új property
tesztnek — mérve viszont, hogy `.github/actions/flutter-gates/action.yml:47`
a CI randomizált-seedes lépését KIZÁRÓLAG a `test/property` könyvtáron
futtatja (`PROPERTY_SEED: ${{ github.run_id }}`); a brief eredeti útvonalán
a tesztek soha nem kapták volna meg a randomizált seedet, csak a fix 42-t a
sima Test gate-en belül, ami aláásta volna A2/A3-at. Revízió: mindkét teszt
`test/property/`-be került, a meglévő `planner_repair_property_test.dart`/
`planner_time_budget_property_test.dart` mintáját követve. (2) A
`golden_profiles` fixture `.json`-ról `.dart`-ra váltott, mert
`PracticeGenerationRequest`-nek (és beágyazott típusainak) nincs
`fromJson`/`toJson`-ja — a feature MINDEN meglévő fixture-je Dart
builder-függvény. A pre-flight emellett dokumentálta (nem-blokkoló
iránymutatásként), hogy `GenerationPlanInput`-ot korábban SOHA nem épített
`lib/` kód — a `shadow_plan_generator.dart` ezt először teszi élesben.

**Mindkét review zöld, mindkettőt Claude saját kézzel, izolált `/tmp`
klónban ellenőrizte — nem az implementer önjelentése alapján.** A
[correctness review](docs/reviews/e07-r30-review.md) APPROVED (0
BLOCKER/MAJOR/MINOR, 1 NOTE): a gate-et egy friss, GitHub originről klónozott
`/tmp` munkapéldányban újrafuttatta, a hiteles `tools/scope-audit.py`-val
mérte a scope-ot (7 fájl, 0 sértés), saját kézzel megismételte a brief
kötelező valódi-sértés próbáját (egy golden profil elvárását elrontva a
golden-fixture teszt PIROSRA váltott, visszaállítás után zöld), és egy
harmadik, korábban ki nem próbált `PROPERTY_SEED` értékkel is lezöldítette a
property tesztet. A kötelező [security review](docs/reviews/e07-r30-security.md)
(`risk=high`) **PASS** — 0 CRITICAL/BLOCKER/MAJOR/MINOR, 3 előretekintő NOTE
(egyik sem blokkol): `AdaptivePracticePlan.toJson()` egy jövőbeli szabad
szöveges golden profilnál a determinizmus-teszt logjába kerülhetne (ma
inaktív); az aktiválási határ továbbra is fuzionált a
`GenerationOrchestrator`-ban (a completion report ezt maga nevezi meg nyitott
tételként); az eval-tool `test/`-ből importál (réteg-higiénia, nem szállítási
kockázat).

**Zöld kapu.** A `round-ci-plan.py` `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, mindkét review-commitot is tartalmazó HEAD-en (`d40e2050` — a
review-dokumentumok commitolása UTÁN a korábbi, `404b9b76`-on dispatch-elt
futásokat újra kellett indítani a helyes exact-SHA-n): Full Gate
[32289312900](https://github.com/wolfcasaba/strumsight/actions/runs/32289312900)
és Router CI
[32289316122](https://github.com/wolfcasaba/strumsight/actions/runs/32289316122)
success, `gh run view --json headSha` mindkettőn egyezett a merge előtti
lokális HEAD-del. Post-merge célzott gate a friss `main`-en (`ee5821dd`)
önállóan is zöld (7/7: format, analyze, 2 teszt-útvonal, architecture,
secrets, l10n). Két mért lecke: **[[L330]]** (a property-teszt könyvtárat a
tényleges CI composite action hardcode-olt argumentumával kell mérni, nem a
brief/SDD-fejezet szövegével — mindkettő egyszerre tévedhet ugyanabban az
irányban) és **[[L331]]** (a `sdd-round-review` skill saját
review-klónozó parancsa a megosztott lokális fából elhasal, ha a kör-branch
egy izolált implementer-klónból pusholt közvetlenül originre — GitHub
remote URL-ből klónozva a hiba osztálya kizárt).

**Nyitott tételek (a completion report — `docs/sdd/epic-07-completion-report.md`
— és a security review NOTE-2 által megnevezve, jövőbeli körnek/emberi
döntésnek):** a `practiceGeneratorEnabled`/`plannerAssistEnabled` flagek
bekapcsolása emberi release-döntés; a teljes CI-suite/property/APK
CI-bizonyíték továbbra is kötelező (ez a helyi korpuszfutás nem helyettesíti);
valós Android-eszközös offline flow és eszköz-specifikus latency/memória
baseline még hátravan; a `GenerationOrchestrator.generate()` továbbra is
egyetlen hívásban fuzionálja a validálást/javítást az aktiválással — egy
jövőbeli preview-confirmation implementáló körnek külön kell választania,
mielőtt valódi (perzisztáló) activation bekötődik; a Planner Assist-nek
nincs élő transport-rolloutja ebben a körben.

**Epic 7 (AI Practice Generator) ezzel lezárva** (R01–R30, SDD Ch8). A lánc
**Epic 8-cal (Gamification, SDD Chapter 9, 30 kör) folytatódik: E08-R01**
(Gamification baseline és principles), új sessionben.

## ✅ E07-R29 KÉSZ — Accessibility, localization, privacy és safety hardening — PR #332, squash `73e7876e` (2026-08-19)

A friss orchesztrátor-session (Sonnet 5) a H-NOSIGNAL self-heal (lent) által
otthagyott állapotot vette át: az implementer- és javító-munka
(`minimax/e07-r29-accessibility-privacy-hardening`,
`codex/e07-r29-accessibility-privacy-hardening-fix`) már push-olva volt, a
dolog csak a hátralévő review-zárás, CI-dispatch és merge volt.

**A review három leletet talált, mind zárva.** F1 (MAJOR — a `_writtenKeys`
in-memory lista miatt restart után a draft/archive-only tervek eltűntek a
delete-all/export sweepből) és F2 (BLOCKER — a `null` `outcomePlanLookup`
alapértelmezett `owner = planId` miatt egy plan-scoped törlés más terv
evidence-ét is elvitte) a MiniMax-nak járó EGY javító körben zárult
(`0a6315d2`…`3e05d243`, perzisztált manifest + adat-alapú plan-ownership). A
review egy MÁSODIK, friss valódi-sértés próbával F3-at is talált (MAJOR — a
manifest-írás `_trackWrite`/`_trackRemove` nem `await`-elte a
`keyValueStore.writeString`-et, a hiba silent no-op-ként veszett el); mivel a
MiniMax egy javító köre már elfogyott, a motor-eszkaláció szabálya szerint
(AGENTS.md/ADR 0087 §2) a Codex vitte a második javítást (`8212b0cb`).

**Az orchesztrátor a Codex-javítást NEM a `.codex-round-status` önjelentése
alapján fogadta el.** Elolvasta a `8212b0cb` teljes diffjét, majd saját,
izolált `flutter test test/features/practice_generator/data/
local_repository_test.dart` futtatással megerősítette — **36/36 zöld**,
köztük az új `F3 — manifest persistence failures` eset. Csak ez után
frissítette `docs/reviews/e07-r29-review.md`/`e07-r29-security.md`-t
CHANGES REQUIRED/BLOCKED → **APPROVED/PASS**-ra, és töltötte ki a brief §11-et.

**Mért gotcha a §0.3 upstream-szinkron lépésben (lásd [[L329]]):** a
`git clone --branch <round-branch>` (SKILL.md §3) implicit single-branch
refspecet ad a munkapéldánynak — egy csupasz `git fetch origin main` ebben
NEM frissíti a lokális `origin/main` követő-ágat, és a `merge-base
--is-ancestor` emiatt HAMIS POZITÍVOT adott, mielőtt az explicit
`git fetch origin +refs/heads/main:refs/remotes/origin/main` alakra váltva a
valódi (két commitnyi) elmaradást ki nem mértem. Csak ez után volt biztonságos
a review-t és a gate-et lezárni.

**Zöld kapu.** A round-ci-plan.py `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, `origin/main`-nel egyesített HEAD-en: exact `1aa7923a` → Full Gate
[32282687647](https://github.com/wolfcasaba/strumsight/actions/runs/32282687647)
és Router CI
[32282629066](https://github.com/wolfcasaba/strumsight/actions/runs/32282629066)
success, `gh run view --json headSha` mindkettőn egyezett a lokális HEAD-del
merge előtt. Post-merge célzott gate a friss `main`-en (`73e7876e`)
önállóan is zöld (14/14: format, analyze, 9 teszt-útvonal, architecture,
secrets, l10n). Lecke: **[[L329]]**.

Az implementáció maga: teljes hu/en ARB-paritás (25 új kulcs), nagy
betűméret/screen-reader/reduced-motion audit a meglévő planner-képernyőkön,
nem-szín-alapú státuszjelölés (`TodayPlanMode` szöveg+ikon badge), redakciós
audit (`ExportPracticePlanningData._redactPlanJson` kitörli a
comfort-constraint értéket és minden goal `userNote`-ját), és a
felhasználó-kezdeményezett teljes törlés/export (`plan_privacy_screen.dart`,
`delete_practice_planning_data.dart`, `export_practice_planning_data.dart`) —
az ADR 0260 §5 szűk, csak erre a hívási útra fenntartott kivételként
(`docs/privacy/practice-planning-data.md` rögzíti a policy-kört).
`practiceGeneratorEnabled`/flag-ek változatlanul `false`. Következő kör:
**E08-R…** vagy a soron lévő pipeline-tétel, új sessionben.

## ✅ [HEAL E07-R29/H-NOSIGNAL] KÉSZ — preambulum: alparancs sikeres lezárása ≠ kör lezárása — PR #331, squash `90cf0628` (2026-08-19)

Az E07-R29 friss orchesztrátor-sessionje (Terra, rotáció szerint) a H3
self-heal (fent) után helyesen újraindult, és ~72 percen át helyesen
vezényelte a kört: implementer-dispatch, review, javítás, majd egy
Codex/Terra escalation-javítás az utolsó nyitott leletre. A záró, független
`tools/round-gate.sh` friss klónban 16:56:47Z-kor VALÓDI, sikeres
eredménnyel zárt (mind a 14 lépés zöld) — a turn mégis hat másodperccel
később, 16:56:53Z-kor egyetlen szöveges összegzéssel ért véget
(„…14/14 zöld, de a kötelező CI-dispatch, exact-SHA ellenőrzés és merge még
hátravan.") jelzésfájl nélkül. A pipeline ELAKADÁS-GYORSÍTÓja 20
másodpercen belül H-NOSIGNAL-ként ismerte fel (`.pipeline/chain.log`,
16:57:12).

**Mért, dokumentált precedenshez illeszkedő gyökérok.** Ugyanennek a
`docs/execution/pipeline-codex-orchestrator-preamble.md`-nek két KORÁBBI,
szomszédos rését az L282 (E07-R04, yielded parancs újraindítása) és az L290
(E07-R09, turn vége csonka poll közben) már bezárta — de egyik szabály sem
mondta ki, hogy egy alparancs SIKERES, terminális eredménye ugyanúgy nem
helyettesíti a kör-jelzést. A Codex/Terra rollout-JSONL
(`~/.codex-terra/sessions/2026/08/19/rollout-2026-08-19T15-45-07-*.jsonl`)
pontosan ezt mérte: a modell hűen, hazugság nélkül idézte a valódi „14/14
zöld" eredményt, majd egy alparancs lezárását a kör lezárásával azonosítva
állt meg.

**A javítás egyetlen új szabály-bullet + regressziós teszt.** A preambulum
§2-je egy új, névvel idézett bullet-et kapott az L290-bullet után: „egy
alparancs sikeres lezárása attól még nem azonos a kör lezárásával" — ha a
§3 checklist bármelyik eleme (push, CI-dispatch, exact-SHA ellenőrzés,
merge, kör-jelzés) hátravan, a válasz KÖVETKEZŐ eleme kötelezően újabb
tool-hívás. Regresszió: `tools/tests/test_pipeline_codex_orchestrator_preamble.py`
új `CodexOrchestratorPreambleNoStopAfterSuccessfulSubtaskTest` osztálya (3
eset), PIROS a javítás előtt → ZÖLD utána, a 7 meglévő preambulum-teszttel
együtt is zöld. Teljes `tools/tests`: **574 passed, 567 subtests passed, 0
hiba** (571→574). Router CLI smoke és `brief-lint.py --open --level base`
lokálisan is zöld, egyezően a CI lépéseivel. Exact SHA `3ca6d07d`: Router CI
([32280795044](https://github.com/wolfcasaba/strumsight/actions/runs/32280795044))
`conclusion=success`, `headSha` és a PR `headRefOid`-ja a merge előtt
egyezett a lokális HEAD-del. Nincs Dart-változás, ezért `build-apk.yml` nem
releváns — a Router CI volt az egyetlen szükséges kapu. Lecke: **[[L328]]**.
A lánc E07-R29-cel folytatódik a következő cron-firingen; a már elkészült
implementer- és javító-munka (`minimax/e07-r29-accessibility-privacy-hardening`,
`codex/e07-r29-accessibility-privacy-hardening-fix` ágak, mindkettő
push-olva originre) érintetlen — a friss orchesztrátor-session dolga csak a
hátralévő CI-dispatch + merge.

## ✅ [HEAL E07-R29/H3] KÉSZ — brief-bővítés: storage-owner, evidence-port és auditált planner-képernyők — PR #330, squash `7176875d` (2026-08-19)

Az E07-R29 (Accessibility, localization, privacy és safety hardening) saját
pre-flightja (Terra orchesztrátor, `29863cba` a sosem push-olt
`minimax/e07-r29-accessibility-privacy-hardening` ágon) helyesen HALT-olt:
a §3/§5.5 teljes törlés/export és a meglévő planner-képernyők
accessibility-auditja a brief régi `allowed_paths`-ában NEM elérhető
fájlokban él — a tényleges storage-tulajdonosok
(`data/local/local_practice_plan_repository.dart`,
`generation_draft_repository.dart`), az evidence-port
(`domain/repository/practice_evidence_repository.dart` — szándékosan SOSEM
töröl, ADR 0260 §5) és a már létező `today_plan_screen.dart`/
`weekly_plan_screen.dart`/`plan_setup_screen.dart` mind a régi tiltott
zónában voltak. Ez a session soha nem érte el a `main`-t — a Terra-session a
mérés után korrektül `H3`-mal állt le, implementer-dispatch nélkül.

Az önjavítás (ADR 0112, 1/3. kísérlet) portolta ezt a mérést `main`-re §0.0
gyanánt, majd §0.0.1-ben oldotta fel — **egyetlen** brief-bővítéssel, új ADR
nélkül (a pre-flight saját szövege szerint ide nem tartozik elfogadott ADR):
17 névre szóló bejegyzés `allowed_paths`-ban (10 meglévő `lib/`-tulajdonos +
7 saját, már létező tesztjük), ebből 7 `gate_tests`-ben is, hogy a kör SAJÁT
gate-je — ne csak a végső CI — védje a bővített területet. Egy új §5.7
rögzíti az ADR 0260 §5 viszonyát: az automatikus/lekérdezés-idejű elévülés
VÁLTOZATLAN marad mindenhol, az új evidence-törlő metódus egy szűk, csak a
felhasználó-kezdeményezett „mindent törölj" útra fenntartott kivétel.

**Mért, a pre-flight saját szövegénél szűkebb megoldás:** `lib/core/storage/
key_value_store.dart` (a megosztott, minden feature-t kiszolgáló
`KeyValueStore` interfész) NEM kellett megnyitni — a
`LocalPracticePlanRepository` minden saját kulcsát maga generálja, és már ma
is egyenként hívja `keyValueStore.remove()`-ot a bounded-history evikció
során (`appendRevision`/`appendOutcome`) —, tehát egy teljes, egy-terv-re
szóló törlés ugyanezzel a mintával, KIZÁRÓLAG ebben az egy fájlban megírható.

**Kötelező regresszió (PIROS a revízió előtt → ZÖLD utána, mindkét irányban
mérve):** `tools/tests/test_e07_r29_accessibility_privacy_scope.py` — a
valódi `audit_legacy_scope()`-ot futtatja a committolt brief ellen; méri a
mért halt-útvonalak és a teljes §0.0.1-grant hatókörbe kerülését, hogy egy-egy
szomszédos fájl mind a négy bővített területen (megosztott storage-interfész,
szomszédos repository, már biztonságosnak mért service, szomszédos képernyő)
kívül marad, hogy `allowed_paths`/`gate_tests` pontosan az eredeti + az új
bejegyzésekkel bővült, és hogy minden újonnan engedélyezett útvonal ma is
létezik. Teljes `tools/tests`: **571 passed, 567 subtests passed, 0 hiba**.
`tools/brief-lint.py --level strict` és a Router CI saját `--open --level
base` kapuja: tiszta. Nincs Dart-változás, ezért `build-apk.yml` nem
releváns; a Router CI (a diff `tools/**`/`docs/rounds/**`-t érint) volt az
egyetlen szükséges kapu, `tools/wait-for-ci.sh`-sal várva előtérben, a merge
előtt SHA-egyezés igazolva. Lecke: **[[L327]]**. A lánc E07-R29-cel
folytatódik a következő cron-firingen, a most bővített `allowed_paths` alatt.

## ✅ E07-R28 KÉSZ — Tutor és PlannerAssistGateway integráció — PR #329, squash `b021eff2` (2026-08-19)

Az opcionális, nem-autoritatív **PlannerAssist** gateway (SDD Ch8 Kör 28,
[ADR 0270](docs/adr/0270-planner-assist-allowlist-and-untrusted-input.md),
előre megírva 2026-08-15) egy strukturált request/response sémán és
**exact** goal-/skill-/candidate-allowlisten (nincs fuzzy illesztés) keresztül
enged nem megbízható nyelvimodell-választ a determinisztikus tervező elé —
a modell SOHA nem aktivál tervet, minden felhő-hiba (timeout, rate limit,
hálózat, kikapcsolt flag) determinisztikus tartalékra esik vissza, és a
tanuló szabad szövege külön, nem-megbízható mezőként utazik, sosem az
instrukció-mezőben.

**Pre-flight mérés fordította meg az implementáció irányát.** A brief §1 (az
Epic 7 SDD-forrása, `08-epic-07-ai-practice-generator.md` Kör 28) szó szerint
azt írta elő, hogy az adapter a Chapter 5 `ai_tutor`
`PracticePlanDraft`-ját képezze le — a mérés viszont azt mutatta, hogy
`lib/features/ai_tutor/public.dart` **fagyasztott üres** (`library;`, 0
export), egy E04-R01-ben merge-elt regressziós teszt
(`ai_tutor_boundary_test.dart`) őrzi, és ugyanez a hibaosztály HÁROMSZOR
mérve, MINDHÁROMSZOR scope-szűkítéssel oldva (`docs/LESSONS.md` L121/L133/
L139). A §0.0 pre-flight revízió ugyanezt az utat követte: a
`TutorPlanProposalAdapter` egy SAJÁT, e körben definiált `TutorPlanOutline`
típusból épít requestet a practice-generator SAJÁT publikus
katalógus-/skill-felületéről — `ai_tutor` import **nélkül**. Az implementer
(Codex) a §0.0-t szó szerint követte, és a saját docstring-jében is rögzítette
az indokot.

**Mindkét review zöld.** A [correctness review](docs/reviews/e07-r28-review.md)
APPROVED (0 BLOCKER/MAJOR/MINOR, 3 NOTE) — a reviewer saját, független
valódi-sértés próbával mérte az A2 allowlist-et (a candidate-ellenőrzés
ideiglenes gyengítése PIROSRA vitte a tesztet, visszaállítás után zöld). A
kötelező [security review](docs/reviews/e07-r28-security.md) (brief
`risk = "high"`) **PASS** — 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR (a séma
`goalIds`/`skillIds`/`candidateIds` tömbjei ma méretkorlát nélküliek —
ártalmatlan, mert nincs élő transport, de a jövőbeli hálózati bekötés előtt
egysoros cappal érdemes zárni), 5 NOTE (a jövőbeli transport/UI-bekötő
körnek: a prompt-elkülönítés STRUKTURÁLIS, csak akkor marad az, ha a jövőbeli
HTTP-transport nem fűzi össze `instructions` + `untrustedLearnerNote`-ot egy
stringgé). Exact `dc413fd8`: Full Gate
[32266022078](https://github.com/wolfcasaba/strumsight/actions/runs/32266022078)
és Router CI
[32266095192](https://github.com/wolfcasaba/strumsight/actions/runs/32266095192)
success; post-merge célzott gate a friss `main`-en (`b021eff2`) önállóan is
zöld. `plannerAssistEnabled` változatlanul `false`, nulla production hívó.

**Folyamat-lecke ([[L326]]).** Az implementer-wrapper (`codex-round.sh`) NEM
push-ol automatikusan — a commit a review indulásakor CSAK az izolált
`ss-codex-e07-r28` munkapéldányban létezett. Az orchestrátornak kellett
push-olnia originre a review-klónozás ELŐTT; enélkül SEM a saját `/tmp`-klón,
SEM a párhuzamosan dispatch-elt security-reviewer subagent (aki a megosztott
fából klónozott) nem látta volna a valódi kódot. Ez a [[L325]] (E07-R26,
stale local ref) ROKON, de ELTÉRŐ gyökérokú hibaosztálya: ott a push
megtörtént, csak a lokális ref nem követte; itt a push MAGA hiányzott, ezért
az L325 „fetch origin előbb" receptje önmagában nem lett volna elég.

**Utólag mért, EBBEN a pre-flightban felfedezett, NYITOTT tartozás
(nem E07-R28 hibája, hanem E07-R27-é):** az E07-R27 (PR #328, squash
`a0c61044`) brief-je `risk = "high"`-ra volt állítva, de a kötelező
biztonsági review (`docs/reviews/e07-r27-security.md`) SOHA nem készült el —
a kör a correctness review-val (APPROVED) egyedül merge-elt, és a záró
rituálék (HANDOFF/RTM/LESSONS) is elmaradtak, csak a
`docs/execution/pipeline-queue.tsv` `done` jelzése készült el
(`chore(pipeline): E07-R27 done`, `e95bd937`). Ez a HANDOFF-bejegyzés ezt a
hiányt UTÓLAG dokumentálja (ld. lentebb), de a hiányzó security review-t NEM
pótolja — az egy jövőbeli kör vagy emberi döntés dolga. Következő kör:
**E07-R29** (Accessibility, localization, privacy és safety hardening, SDD
Ch8 Kör 29), új sessionben.

## ✅ [UTÓLAGOS DOKUMENTÁCIÓ] E07-R27 KÉSZ — Missed day, catch-up, pause és returning flow — PR #328, squash `a0c61044` (2026-08-19, retroaktívan rögzítve az E07-R28 pre-flightjában)

**Ez a bejegyzés utólag készült** — az E07-R27 saját sessionje a merge után
nem futtatta le a záró rituálékat (HANDOFF/RTM/LESSONS-frissítés
elmaradt, csak a pipeline-queue `done` jelzése történt meg). A tartalom a PR
törzséből és a meglévő [review](docs/reviews/e07-r27-review.md)-ból
rekonstruált, NEM az eredeti orchestrátor első kézből írt összegzése.

Domain-pure `MissedDayPolicy` a múltbeli napokat completed/missed/future
kategóriákba sorolja és reschedule-módot választ; a 21 napos rés a
konzervatív oldalra esik, ezért `readinessProposal`-t ad
([ADR 0269](docs/adr/0269-non-punitive-missed-day-handling.md) §5.4).
`PausePracticePlan` `paused` státuszra vált új revízióval;
`ResumePracticePlan` újra-horgonyozza a naplistát (a `resumeDate` lesz az új
`startDate`), eldobja a hátralékos napokat, és `returningAfterBreak` módra
vált, ha a rés eléri a küszöböt. Nem büntető, "bűntudatkeltés-mentes"
catch-up UI.

**A review egy javító kör után APPROVED** (`docs/reviews/e07-r27-review.md`,
0 BLOCKER/MAJOR/MINOR/NOTE nyitva): F1 (MAJOR — a resume felülírta egy
completed nap történeti dátumát) és egy második MAJOR javítva, re-review
`1c5d4562`-n. **A kötelező biztonsági review HIÁNYZIK** — a brief
`risk = "high"`, de `docs/reviews/e07-r27-security.md` sosem készült el; ezt
az E07-R28 pre-flightja fedte fel utólag (ld. fent). Exact `10ed4874`: Full
Gate [32259717044](https://github.com/wolfcasaba/strumsight/actions/runs/32259717044)
és Router CI
[32259719677](https://github.com/wolfcasaba/strumsight/actions/runs/32259719677)
success.

## ✅ E07-R26 KÉSZ — Outcome ingestion, review update és plan revision — PR #326, squash `d7e894de` (2026-08-19)

A befejezett gyakorlás-blokkok eredményének feldolgozása és az **átlátható**
jövőbeli tervmódosítás (SDD Ch8 Kör 26) egy tisztán application-rétegbeli,
**hívó-táplált** csővezetékként épült meg: `OutcomeIngestionService`
(revízió-egyezés, dedup, `SpacedRepetitionPolicy`-alapú review-frissítés,
technikai hiba nem adaptálható — ADR 0268), `RecordPracticeOutcome` (a
service + `AdaptationDecider` összefűzése), `RevisePracticePlan`
(immutable-múlt guard a meglévő `PracticeItemStatus.completed`
mintával — ADR 0256; kis/nagy változás szétválasztás, a "fókusz váltása" is;
elutasított proposal auditálható marad; `PlanRevision(previous:)` meglévő
monotonitás-védelme — nincs saját számláló) és `PlanChangeReviewScreen`
(lokalizált before/after diff a nagy változáshoz). **Egyik új fájl sem hív
repository-metódust** — a §0.0 pre-flight mérése szerint a repository-lokális
és az R23 execution-oldali `PracticeOutcome` két, AZONOS NEVŰ, eltérő alakú
típus (a `public.dart` `hide`-olja az előbbit); a perzisztencia-bekötés
szándékosan egy jövőbeli wiring-körre marad, az R16/R17/R19/R22/R23 mintáját
követve (`practiceGeneratorEnabled` marad `false`, nulla production hívó).

A független review (`docs/reviews/e07-r26-review.md`) egy javító kör után
APPROVED: az F1 MAJOR (a brief §5.2 "fókusz váltása" structural-change ága a
kódban helyesen működött, de a kör saját teszt-suite-ja 0%-ban fedte —
reviewer-oldali eldobható próbateszttel mérve, nem a kód olvasásából
következtetve) egyetlen új teszttel zárult, valódi-sértés próbával
(PIROS→ZÖLD) igazolva. A kötelező biztonsági review
(`docs/reviews/e07-r26-security.md`, `risk=high`) **PASS** — 0
CRITICAL/BLOCKER/MAJOR/MINOR, 5 előretekintő NOTE (sink-mentes, be nem
kötött réteg). Két nem-blokkoló follow-up nyitva maradt: F2 (MINOR) — a
`PlanChange.target` új `day:<id>[:block:<id>]` formátuma nem fedi a MEGLÉVŐ
termelők (`plan_repairer.dart`, `active_plan_controller.dart`,
`time_budget_allocator.dart`) `block:`/`plan:`/`timeBudget` alakjait, mérve
egy eldobható próbateszttel (elkapatlan `ArgumentError`) — nincs élő hívó,
egy jövőbeli wiring-körnek kell tudnia róla; F3 (NOTE) — a review screen
nyers belső értékeket (mikroszekundum, enum-kód) jelenít meg humanizálás
nélkül. Exact `254a4efe`: Full Gate
[32251015719](https://github.com/wolfcasaba/strumsight/actions/runs/32251015719)
és Router CI
[32251108229](https://github.com/wolfcasaba/strumsight/actions/runs/32251108229)
success.

**Folyamat-lecke ([[L325]]):** a review-oldali `/tmp` klón NÉMÁN elavult
ágat adhat, ha a `git clone --branch <kör-branch>` a megosztott
`/home/ubuntu/music-theory` fából történik, miközben az implementáció egy
KÜLÖN klónból (`ss-codex-<kör>`) pusholt közvetlenül originre — a megosztott
fa lokális branch-refje csak explicit `git fetch origin <branch>:<branch>`-re
mozdul. Kétszer mérve ugyanebben a körben (a fő reviewer és a párhuzamosan
dispatch-elt security-reviewer subagent is ugyanabba a csapdába futott,
mindkettő önállóan helyreállt).

Ehhez a körhöz **nem kellett új ADR** — a brief saját indoklása szerint a
határokat a MEGLÉVŐ ADR 0256/0265/0268 rögzíti (az E07-R22 precedensével
egyezően); a defenzíven lefoglalt `0325` szám nem került felhasználásra.
Következő kör: **E07-R27** (Missed day, catch-up, pause és returning flow),
új sessionben.

## ✅ A LÁNC ÚJRA MEGY — a `H-GATEGUARD` mostantól KÖRT tart vissza, nem a LÁNCOT (ADR 0321, 2026-08-19)

**A probléma, mérve.** Az `E99-R17` háromszor állt meg ugyanazzal a gyökérokkal
(05:31 / 09:56 / 10:38 UTC), és mivel a `.pipeline/HALTED` jelzés GLOBÁLIS, a
lánc 05:31–10:40 között **nulla kört vitt előre** — miközben a sorban **32
olyan nyitott kör** állt (E07/E08 termék-munka), aminek semmi köze a gate-hez.
A halt gyökéroka TERVEZÉSI hiba volt: a brief `allowed_paths` listáján védett
fájl (`tool/ci/check_l10n_parity.dart`) szerepelt, amit autonóm session
strukturálisan nem tud megírni (L322–L323).

**A javítás három rétege (ADR 0321):**

1. **Kör-szintű hold.** Kör-session `H-GATEGUARD` haltja → a kör sora `hold`
   (commit + push), halt-archívum + `.pipeline/gateguard-holds.tsv` főkönyv +
   ntfy, és a lánc a következő pending körrel MEGY TOVÁBB.
2. **Az őrszem haltja LÁNC-szintű marad.** Ha a haltot az önjavítás fölötti
   őrszem írta (`gateguard_origin=selfheal` gépi mező), a mércét gyengítő
   commit már a main-en állhat → az egész lánc áll, ahogy eddig.
3. **Pre-flight a dispatch ELŐTT.** `tools/gateguard-scan.py` a védett listát
   **magából az őrből** importálja (nincs második igazság), és a driver a
   kiválasztott kör briefjét ezzel méri. Ütközés → azonnali `hold`,
   implementer-futás és halt nélkül.

**Amit NEM változtat meg:** a mércét és az emberi határt. Gate-érintő kör
továbbra sem fut le emberi döntés nélkül (ADR 0112 §3 érintetlen).

**Emberi döntésre váró (hold) körök — egy közös alkalommal, kötegben:**
`E99-R17` (`tool/ci/check_l10n_parity.dart`), `E99-R20`, `E99-R21`
(`tools/round-gate.sh` + workflow), `E99-R22`, `E08-R29` (workflow).
Gépi lista: `tools/gateguard-scan.py --all` · státusz:
`tools/pipeline-status.sh` „emberi gate-döntésre váró körök" szakasz.
A feloldás menete (E99-R16 precedens): a user SZEMÉLYESEN szerkeszti és
pusholja a védett fájlt a kör ágára, majd a sorban `hold` → `pending`.

**Őrteszt:** `tools/tests/test_gateguard_autohold.py` (12 eset, zöld) ·
tanulság: `docs/LESSONS.md` L324 · brief-szabály: `docs/execution/08-round-brief.md` §4.

## ✅ Router CI paths-szűrő: családi glob — PR #324, squash `a2d64831` (2026-08-19)

Az E99-R16 escalate HIBAOSZTÁLYÁNAK megszüntetése (nem a tünetéé): a `paths:`
blokk 36 fájlonkénti bejegyzése helyett `tools/**` + `docs/execution/**`.
Mérve: lefedettség **127 → 143 fájl (+16)**, elveszett lefedettség **nincs** —
szigorúan bővítő változás, az őr védelme érintetlen. A teljes `tools/tests`
suite elkapott egy minta-SZÖVEGHEZ kötött tesztet
(`test_pipeline_throughput.py`); a javítás lefedettség-alapú állítás lett,
mutációval igazolva, hogy szigorúbb (`tools/**` eltávolítására PIROS).
Zöld kapu: Router CI + Full Gate (no APK) success. Részletek: `docs/LESSONS.md`
**L322** záró blokkja. Mindkét gate-szerkesztést EMBER futtatta — az őr
módosítása szándékosan ELMARADT.

## ✅ E99-R16 (GOV-10) KÉSZ — kör-granularitás mérőeszköz + brief-merge-plan — PR #323, squash `825c7215` (2026-08-19)

**A pipeline első `outcome=escalate` esete lezárva — emberi gate-szerkesztéssel.**

A kör tartalmi munkája (F1/F2/M1 lelet javítva) már korábban APPROVED volt
(`docs/reviews/e99-r16-review.md`). Az EGYETLEN maradvány az F3 volt: a kör új
eszközére (`tools/brief-merge-plan.py`) hivatkozik a `tools/tests` csomag, de a
Router CI push-triggere nem indult volna el rá — a guard-teszt
(`tools/tests/test_router_ci_path_filter.py::test_every_test_referenced_file_is_in_the_ci_filter`)
ezt mérte és pirosra állt.

Három önjavító kísérlet (a 3. már Terra motorral, GOV-09 szerint) egybehangzóan
`escalate`-tel zárult: a javítás helye a `.github/workflows/` — a self-heal
abszolút tiltott zónája (ADR 0112 §3, `docs/LESSONS.md` **L322**), és a teszt
lazítása vagy a fájl kizárása ugyanannak a tiltásnak a másik alakja lett volna.

**Feloldás (2026-08-19, ~05:00 UTC):** a user telefonról explicit engedélyt adott,
és Ő futtatta a gate-szerkesztést (a H-GATEGUARD hook ÉS a harness auto-mode
osztályozója is blokkolta az ügynök-oldali szerkesztést — két független őr).
A változtatás **egy sor**: `"tools/brief-merge-plan.py"` a Router CI `paths:`
blokkjában, a `tools/brief-lint.py` mellé (ADR 0171 áteresztő-eszközök blokkja).
Commit `e71ded2f` — 1 fájl, 1 beszúrt sor, semmi más.

**Mérés (izolált /tmp klón, `ea6e763a`):** javítás előtt
`missing=['tools/brief-merge-plan.py']` → FAILED; utána `Ran 2 tests … OK`.
Teljes `tools/tests` suite (72 modul): **552 teszt, 1 skipped**, az egyetlen
failure környezeti (`test_empty_queue_is_not_a_failure` kifelé hívja a
`python3 -m pytest`-et, ami ezen a boxon nincs telepítve — a CI telepíti).

**Zöld kapu:** Router CI `success` (5m11s, run 32217738001) · Full Gate (no APK)
`success` (run 32217883172) · `gh pr checks 323` mind pass · `mergeStateStatus=CLEAN`.
A friss `main` a merge előtt beolvasztva a branchbe (`174ac6e3`, konfliktusmentes),
mert a guard-teszt a branch SAJÁT workflow-másolatát méri, nem a `main`-ét.

**Tanulság:** az `escalate` kimenet működött — a lánc nem erőltette és nem
kerülte meg a mércét, hanem megállt és emberre várt. A költség ötóra állás
volt; a feloldás egy sor. Következtetés a jövőre: ha egy kör ÚJ, tesztek által
hivatkozott `tools/` fájlt vezet be, a Router CI `paths:` bővítése EMBERI
előkészítő lépés — a kör-brief §0-jában kell jelezni, nem a self-healre bízni.

## ✅ E07-R25 KÉSZ — Analyze és Vision származtatott evidence integráció — PR #322, squash `3ab2a147` (2026-08-19)

Az Analyze és a Vision csak származtatott, confidence-aware evidence-et adhat
át a Practice Generatornak. Az új adapterek a publikus Audio Analysis API-t,
illetve a szűk `vision/domain/evidence/public.dart` contractot használják;
nyers audio, frame, landmark, koordináta és fájlútvonal nem kerül át. A Vision
hiánya üres, hibamentes eredmény, a `notObservable` port-bemenet adapter-szinten
fail-closed, az alacsony confidence pedig súlykorlátozott marad. A független
review APPROVED (0 BLOCKER/MAJOR/MINOR); a reviewer valódi-sértés próbája a
`notObservable` őr eltávolításakor két cellát pirosra váltott, visszaállítás
után 10/10 Vision adapter teszt zöld. Exact `cbcb30c7`: Full Gate
[32210677497](https://github.com/wolfcasaba/strumsight/actions/runs/32210677497)
és Router CI
[32210693573](https://github.com/wolfcasaba/strumsight/actions/runs/32210693573)
success. A merge utáni célzott gate a záró rituálé része.

## ✅ [HEAL E07-R25/H5] KÉSZ — két, egymástól független, self-heal-generált bidirekcionális regressziós pin egyirányúsítva (ADR 0112) — PR #321, squash `a1613fa5` (2026-08-19)

Az E07-R25 (Analyze/Vision evidence integráció) Router CI-ja kétszer pirosra
váltott a kör saját, még nem merge-elt ágán
(`minimax/e07-r25-analysis-and-vision-evidence`), és a driver H5-tel
megállt: `tools/tests/test_e07_r25_vision_evidence_scope.py` (a H3 self-heal
sajátja, [[L319]]) két bidirekcionális `assertEqual`-lel pinnelte az
`EvidenceSource` értékkészletét 4 elemre — a kör implementere közben a SAJÁT
ágán, a H3 által jóváhagyott módon hozzáadta `EvidenceSource.vision`-t
(5. érték), ami a bidirekcionális pint elkerülhetetlenül pirosra váltotta.
**Ez byte-pontosan [[L279]]/[[L280]] hibaosztálya** (E99-R13, 2026-08-15) —
egy self-heal-generált pin szerkezetileg összeegyeztethetetlen egy AKTÍV,
brief-szentesített kör-branch-csel, ami definíció szerint előrébb jár
`main`-nél. A javítás [[L279]] receptjét szó szerint alkalmazza: mindkét
teszt egyirányú, nem-zsugorodás invariánsra vált (a founding 4 érték egyike
sem tűnhet el csendben); `ORIGINAL_EVIDENCE_SOURCE_VALUES` MAGA változatlan
maradt — bővítése "megjavította" volna a kör-ágat, de eltörte volna `main`
SAJÁT, merge utáni Router CI-ját (4 értéke van, amíg a kör ténylegesen nem
merge-el).

**Egy MÁSODIK, a HALT által nem jelentett, ugyanebbe a hibaosztályba tartozó
gyökérokot a SAJÁT fix gate-futtatása fedett fel:** `main` Router CI-ja a
H5-fixem ELŐTT is pirosra váltott (`32207252052`, `32208143911`) egy MÁSIK
self-heal-generált teszten,
`test_knowledge_rag.py::test_brief_lint_flags_a_brief_without_retrieved_precedent`,
amely egy VALÓDI kör briefjére (`e99-r15-gov-09-halt-escalation.md`)
mutatott. A `brief-lint.py` S8 (ADR 0312) checkje szándékosan néma egy
`done` kör briefjén (mért precedens: `e06-r10`) — mihelyt E99-R15 lezárult,
az S8 helyesen elhallgatott, és a teszt nem regresszió, hanem az S8 saját,
szándékos működése miatt tört el. Bármely valódi kör brief-je időzített
bomba ehhez a fixture-höz; a javítás egy szintetikus, a valódi sorban soha
nem szereplő task-id-jú (`E00-R00`) brief, ami a csatolást szünteti meg, nem
csak odébb tolja a lejáratot. Változatlanul hagyva ez a második gyökérok is
blokkolta volna MINDEN jövőbeli kör Router CI zöld merge-ét, nem csak
E07-R25-ét.

**Mindkét irányban mérve** egy izolált heal worktree-ben (a kör-ág valódi
`skill_evidence.dart`/`evidence_weight_policy.dart`-ját commit nélkül a
plain `main` fölé rétegezve): javítatlan teszt + kör-ág kód → PIROS
(byte-azonos a valódi CI-hibával, futások
[32204906795](https://github.com/wolfcasaba/strumsight/actions/runs/32204906795),
[32206385772](https://github.com/wolfcasaba/strumsight/actions/runs/32206385772));
javított teszt + plain `main` kód → ZÖLD; javított teszt + kör-ág kód →
ZÖLD. Egy önálló diff-méréssel (nem a kör saját jelentése alapján) igazolva:
`git diff origin/main...origin/minimax/e07-r25-analysis-and-vision-evidence`
minden érintett fájlja pontosan a H3 által jóváhagyott
`ORIGINAL_ALLOWED_PATHS ∪ NEW_ALLOWED_PATHS` unióját fedi, scope-tágítás
nélkül; a kör saját, független review-ja (`docs/reviews/e07-r25-review.md`)
APPROVED, 0 BLOCKER/MAJOR/MINOR, A1–A8 mind bizonyítva. Sem a
`tools/round-gate.sh`, sem a `.github/workflows/` nem változott; a
teszt-fájlok metódusszáma változatlan (7, 13) — csak átírva, egy sem törölve.
Teljes `python3 -m pytest tools/tests -q`: **537 passed, 1 skipped, 565
subtests passed, 0 failure**. Router CI (egyetlen szükséges kapu, nincs
Dart-változás) zöld a pontos merge SHA-n
([32209227423](https://github.com/wolfcasaba/strumsight/actions/runs/32209227423)),
`tools/wait-for-ci.sh`-sal várva előtérben. Post-merge egy FRISS klónból
(GitHub-ról, nem a helyi, elmaradt `main`-ből) függetlenül újramérve: a két
javított teszt zöld; egy MÁSIK, a MEGELŐZŐ kör (E99-R15) HANDOFF-jában már
dokumentált, élő sor-fájl-állapotra érzékeny flake
(`test_pipeline_integration.py::test_a_full_firing_retries_the_round_
instead_of_healing_a_resolved_terra_wall`) a megosztott, párhuzamosan
terhelt Oracle-boxon inkonzisztensen jelentkezett (a pre-merge commit
UGYANAZON pillanatban zöld volt) — bájt-azonos fájltartalommal a két commit
közt az érintett útvonalakon, tehát NEM ennek a fixnek a regressziója; a
SAJÁT PR Router CI-ja (izolált, terheletlen GitHub-runner, pontos merge SHA)
az irányadó bizonyíték, és az zöld volt. Lecke: **[[L321]]**. A lánc
E07-R25-tel folytatódik a következő cron-firingen, a most javított
mércén.

> **E99-R15 (GOV-09) KÉSZ — Halt-eszkaláció: motorváltás az utolsó önjavító
> kísérletnél és ismétlődő riasztás throttle-lel** — PR
> [#320](https://github.com/wolfcasaba/strumsight/pull/320), squash
> `dcbfb469` (2026-08-19). `heal_engine_for_attempt` az utolsó
> (`selfheal_max`-adik) self-heal kísérletnél determinisztikusan más,
> statikusan elérhető, más `model`-ű motort választ a nyilvántartásból (mai
> alapértelmezés: `codex`), ha van ilyen; az 1–2. kísérlet és az alternatíva
> nélküli utolsó kísérlet a rögzített `sonnet-impl` identitáson marad. A
> kimerült self-heal riasztása (`notify … high`) — amely a `.pipeline/
> chain.log` mérése szerint korábban **5 percenként, throttle nélkül**
> ismétlődött (455 találat, egyetlen 42 órás ablakban ~504 push) —
> `PIPELINE_HALT_REMINDER_MIN` (60 perc) throttle-t és
> `PIPELINE_HALT_REMINDER_MAX_H` (24 óra) felső korlátot kapott; a `KIMERÜLT`
> naplósor változatlanul minden firingkor ír.
>
> **A pre-flight (§0.0) egy MÉRT, TÉVES brief-állítást korrigált** a
> dispatch előtt: a brief „a riasztás egyszer ment ki, nem ismétlődött"
> mondata a `chain.log`-gal szemben hamis volt — a valódi mai hiba
> kontrollálatlan spam, nem csend; ez eldöntötte, hogy D2 a MEGLÉVŐ `notify`
> hívást kapuzza, nem egy másodikat ad hozzá mellé.
>
> **A független review (`docs/reviews/e99-r15-review.md`) 1 MAJORT talált és
> zárt egy javító körben:** az implementer első commitja (`05d81543`) egy ÚJ
> `run_selfheal_session` dispatch-útra váltott MINDEN kísérletnél, elveszítve
> a régi `run_orchestrator_session` beépített Claude-kvótazárlat→Terra
> automatikus fallbackjét — nemcsak az utolsó, motorváltós kísérletnél, hanem
> az 1–2.-nál is, ami sértette a brief saját „a mai viselkedés nem érintett
> ágakon bitre azonos" ígéretét. A review saját falszifikációval mérte
> (`claude_unavailable_until` szimulált zárlat), a javítás (`e938588a`)
> minimális: a változatlan motor a régi, kvóta-tudatos úton marad, a
> `run_selfheal_session` kizárólag valódi motorváltásnál fut. A kötelező
> biztonsági review (`docs/reviews/e99-r15-security.md`, `risk=high`) PASS —
> 0 CRITICAL/BLOCKER/MAJOR/MINOR, függetlenül nyomon követve a MiniMax
> auth-token teljes futásidejű útját (nincs szivárgás argv-be, naplóba vagy
> commitba). Exact-SHA: Full Gate
> [32205415850](https://github.com/wolfcasaba/strumsight/actions/runs/32205415850)
> és Router CI [32204921953](https://github.com/wolfcasaba/strumsight/actions/runs/32204921953)
> success a merge-előtti `e938588a` fejen.
>
> **Post-merge gate (mind saját, izolált klónban futtatva):** a Dart gate
> (`tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`)
> zöld. A `python3 -m pytest tools/tests -q` egyetlen determinisztikus (nem
> flaky) hibával állt le
> (`test_pipeline_integration.py::test_a_full_firing_retries_the_round_instead_of_healing_a_resolved_terra_wall`)
> — méréssel kizárva, hogy ez a kör kódjának regressziója: a hiba KIZÁRÓLAG
> attól függ, hogy az E99-R15 sora a `docs/execution/pipeline-queue.tsv`-ben
> még `pending` (a driver ezt a saját `.pipeline/round-status-E99-R15`
> jelzésem feldolgozása UTÁN, egy KÉSŐBBI firingen frissíti — nem az
> orchesztrátor dolga, §4). A `pipeline-queue.tsv` sort NEM módosítottam
> (tiltott zóna). Lecke: **[[L320]]**.

## ✅ [HEAL E07-R25/H3] KÉSZ — brief-bővítés: hiteles `EvidenceSource.vision` + egy exhaustive-switch fordítási csapda + szűk Vision-owned evidence contract — PR #319, squash `ea042640` (2026-08-19)

Az E07-R25 (Analyze/Vision evidence integráció) saját pre-flightja (ADR 0319,
Terra→minimax, `main @ 90df4d04`) helyesen HALT-olt: a Practice Generator
`EvidenceSource` enumja (`skill_evidence.dart:17-21`) nem ismer `vision`
értéket, és az egyetlen scope-on belüli Vision-kontraktus
(`vision/domain/integration/public.dart`, ADR 0193) nem ad át skillhez
kötött numerikus evidence-et — a §1 cél és az A5/A6/A8 elfogadási pontok
emiatt nem teljesíthetők a régi `allowed_paths`-on belül.

Az önjavítás (ADR 0112, 1/3. kísérlet) a saját, független kódmérésével egy
MÁSODIK, ADR 0319-től független rést is talált: `EvidenceWeightPolicy.
sourceReliability` (`evidence_weight_policy.dart:66-71`) egy `default` ág
nélküli, kimerítő `switch`-et futtat a jelenlegi 4 `EvidenceSource` értéken.
Az ADR 0319 saját listája ezt a fájlt nem nevezte meg — egy `vision` érték
hozzáadása enélkül NEM ugyanazt a HALT-ot hozta volna vissza a következő
dispatchkor, hanem egy kevésbé olvasható `flutter analyze`
non-exhaustive-switch hibát, ugyanabban a tiltott zónában.

**Javítás:** `docs/rounds/e07-r25-analysis-and-vision-evidence.md` §0.0.1
öt névre szóló fájllal bővíti `allowed_paths`/`gate_tests`-t:
`skill_evidence.dart`, `evidence_weight_policy.dart`, a két teszt-társuk, és
egy ÚJ, szűk, raw-media-mentes `lib/features/vision/domain/evidence/
public.dart` (ADR 0193/L193 nested-barrel minta — additív fájl, a megosztott
architektúra-guard és minden más Vision-fogyasztó változatlan). Az ADR 0319
egy dátumozott záró-bekezdést kapott, ami a második rést és a feloldást
rögzíti. Semmilyen production kód nem változott — tisztán
folyamat/dokumentáció-scope (ADR 0112 §2/§3).

**Kötelező regresszió (PIROS a revízió előtt → ZÖLD utána, mindkét irányban
mérve):** `tools/tests/test_e07_r25_vision_evidence_scope.py` — a mért
`EvidenceSource`/`sourceReliability` alakot, a három újranyitott
Vision-típus raw-mentességét és az `allowed_paths` pontos, öt bejegyzésű
bővülését zárolja (egy szomszédos, a bővítésen kívüli útvonal továbbra is
scope-on kívül marad). Teljes `tools/tests`: **535 passed, 560 subtests
passed, 0 hiba**. `tools/brief-lint.py --level strict`: tiszta. Nincs
Dart-változás, ezért `build-apk.yml` nem releváns; a Router CI (a diff
`tools/**`/`docs/rounds/**`/`docs/execution/pipeline-queue.tsv`-t érint) volt
az egyetlen szükséges kapu, `tools/wait-for-ci.sh`-sal várva előtérben, a
merge előtt SHA-egyezés igazolva. Lecke: **[[L319]]**. A lánc E07-R25-tel
folytatódik a következő cron-firingen, a most bővített `allowed_paths` alatt.

> **E07-R24 KÉSZ — Song goal és Song Trainer integráció** — PR
> [#318](https://github.com/wolfcasaba/strumsight/pull/318), squash
> `b08c00e9` (2026-08-19). A Practice Generator most explicit, caller-fed
> `SongDocument`-ből normalizál song goalokat; az ismeretlen, hibás vagy
> előfeltétel nélküli cél fail-closed kiesik. A blokkfordítás determinisztikus,
> és csak a ténylegesen megvalósított prerequisite után enged célt tervbe.
> [ADR 0318](docs/adr/0318-song-goal-public-boundary-and-caller-fed-input.md)
> rögzíti a szándékosan szűk, Song Trainer belső rétegét meg nem nyitó
> nyilvános határt. A correctness review az F1 MAJOR-t valódi no-producer
> próbával találta és a MiniMax javító kör zárta; a security delta-review PASS.
> Exact `028ea117`: Full Gate
> [32200092798](https://github.com/wolfcasaba/strumsight/actions/runs/32200092798)
> és Router CI
> [32200094318](https://github.com/wolfcasaba/strumsight/actions/runs/32200094318)
> success. Következő kör: **E07-R25**, új sessionben.

> **E99-R14 KÉSZ — GOV-08 motor-override lejárat és motor-statisztika** — PR
> [#317](https://github.com/wolfcasaba/strumsight/pull/317), squash
> `52200a81` (2026-08-18). Az `engine-profile.sh use` TTL-t és indoklást
> tároló, háromsoros override-formátumot kapott, miközben a régi egysoros
> forma változatlanul olvasható. A driver lejárt override-nál töröl, a
> motornevet megtartó audit/ntfy üzenetet ír; lejárat nélküli, 72 órásnál
> idősebb override-nál naponta legfeljebb egy értesítést küld. A
> `round-metrics.py --engines --epic` immár chain.log-alapú mintaszámot,
> mediánt, átlagot, kiugrót és önjavítást mutat motoronként.
>
> A [független review](docs/reviews/e99-r14-review.md) APPROVED: M1–M5
> (epic-szűrés, izolált falszifikáció, egyetlen valódi kiértékelési út,
> hermetikus driver-teszt, lejárt motor auditálhatósága) zárva. Exact-SHA:
> Full Gate [32197051577](https://github.com/wolfcasaba/strumsight/actions/runs/32197051577)
> és Router CI [32197078395](https://github.com/wolfcasaba/strumsight/actions/runs/32197078395)
> success a `9fdf556e` fejen; post-merge gate a `52200a81` mainen is zöld.
> A teljes tooling-suite az izolált projekt pytest-környezetben `527 passed,
> 1 skipped, 560 subtests passed`; a rendszer `/usr/bin/python3` interpreter
> nem tartalmaz `pytest` modult. Következő kör: **E99-R15**, új sessionben.

> **E07-R23 KÉSZ — PlanCompiler és Practice Engine végrehajtás** — PR
> [#316](https://github.com/wolfcasaba/strumsight/pull/316), squash
> `d02718fb` (2026-08-18). `PlanCompiler` egy validált terv-blokkot fordít
> pontos, végrehajtható Practice Engine lépéssé — revízió- és
> capability-ellenőrzéssel indítás előtt, a recept konfigjának
> közelítés-mentes átadásával. `PracticeOutcomeAdapter` a Practice Engine
> **hívó-táplált** terminál-bemenetét normalizálja (`completed` /
> `cancelled` / `failedTechnical` / `skipped` / `unavailable`), mert a §0.0
> pre-flight kimérte: a Practice Engine ma KIZÁRÓLAG a `completed` ágon
> állít elő `PracticeSessionResult`-ot (ADR 0077 §9,
> `practice_session_controller.dart:245-256`) — a `cancelled`/`failed` ág
> nem. `PlanExecutionCoordinator` indít + idempotensen könyvel
> (`blockExecutionId` replay-nél first-write-wins). [ADR
> 0268](docs/adr/0268-technical-failure-is-not-skill-failure.md)
> végrehajtva: a technikai hiba SOSEM tanuló-teljesítmény, a megszakítás
> részleges (nem kudarc), az elavult/unavailable blokk nem indul.
>
> [Correctness review](docs/reviews/e07-r23-review.md) APPROVED egy javító
> kör után: az F1 MAJOR azt mérte, hogy a session-konfig pontos-egyezés
> hiba-ága (§5.4 — „nem körülbelül") tesztelve NINCS — a review saját kézzel
> eltávolította a védelmet, és mind a 7 akkori teszt zöld maradt. A javítás
> (`mismatchedSessionConfig()` + egy negatív teszt) után a review
> MEGISMÉTELTE a próbát: PIROS a védelem nélkül, ZÖLD vele — a zárás valódi,
> nem bemondás. [Security review](docs/reviews/e07-r23-security.md) PASS
> (kötelező, brief `risk = "high"`): 0 CRITICAL/BLOCKER/MAJOR/MINOR, 5
> előretekintő NOTE a jövőbeli wiring körnek (elsősorban: a `metricEvidence`
> kulcsok és a `failureCode` maradjanak gép-eredetűek, ne kerüljön bele
> szabad szöveg). Exact-SHA: Full Gate
> [32194483344](https://github.com/wolfcasaba/strumsight/actions/runs/32194483344)
> és Router CI
> [32194473562](https://github.com/wolfcasaba/strumsight/actions/runs/32194473562)
> success a merge-előtti pontos fejen; post-merge célzott gate a friss
> `main`-en önállóan újrafuttatva is zöld (7/7). `practiceGeneratorEnabled`
> marad `false`, nulla production hívó — tisztán domain/application/data
> réteg-bővítés.
>
> **Folyamat-megjegyzés (két külön mérve, mindkettő a review-oldali
> független friss klónozás fogta meg, nem a bemondás):** (1) a javító kör
> `.codex-round-status` `done` jelzése után a HEAD nem volt push-olva
> originra — ugyanaz a hibaosztály, mint `docs/LESSONS.md` L311; (2) a `main`
> a kör folyamán ötször mozdult (más, párhuzamos governance-körök
> docs/tools-commitjai miatt) — minden alkalommal újra-szinkronizálva és a
> CI-t (Full Gate + Router CI) újra-dispatch-elve az ADR 0086 §2 exact-SHA
> szabálya szerint, mielőtt a végső merge megtörtént. Következő kör:
> **E07-R24**, új sessionben.

> **E07-R22 KÉSZ — Weekly Plan és Today screen** — PR
> [#307](https://github.com/wolfcasaba/strumsight/pull/307), squash
> `dd80179e` (2026-08-18). Az aktív terv napi ("ma") és heti nézete
> **helyi dátumból**, injektált órával (`final DateTime Function() clock`,
> a plan_setup_controller.dart-ban már bevett minta) — nincs `.toUtc()` a
> vezérlőben. A pihenőnapot a `PracticeDay.reasonCodes.contains(
> ScheduleDecisionReason.restDay.code)` jelzés különbözteti meg a
> kihagyott/nem-elérhető naptól (a `PracticeItemStatus`-nak NINCS `rest`
> értéke, és a `BlockKind.rest` sosem épül — a §0.0 pre-flight ezt mérte ki
> a dispatch ELŐTT). Rövidítés/csere/kihagyás/szüneteltetés akciók
> `PlanChangeReason.learnerReschedule` change-settel, storage-írás nélkül —
> a mentés egy jövőbeli composition-kör dolga. Típusos,
> `Map<String,String>`-alapú deep-link contract (`TodayPlanRouteRequest`),
> nincs nyers URI-parse. [Correctness review](docs/reviews/e07-r22-review.md)
> APPROVED, [security review](docs/reviews/e07-r22-security.md) PASS — 2
> javító kör után, a MÁSODIK kört egy FÜGGETLEN, második
> `security-reviewer` agent-futás ellenőrizte, nem csak az orchestrátor
> olvasata. Exact-SHA: Full Gate
> [32176316917](https://github.com/wolfcasaba/strumsight/actions/runs/32176316917)
> és Router CI zöld az `5cae87d2` fejen. `practiceGeneratorEnabled` marad
> `false`, nulla production hívó.
>
> **A biztonsági review 2 MAJORt zárt, és 1 nem-blokkoló, KÖTELEZŐEN
> tovább-adandó MINORt hagyott nyitva a következő wiring körnek:**
> `TodayPlanRouteRequest.tryParse` egy `Map<String,dynamic>.cast<String,
> String>()` (a JSON-payloadból jövő IDIOMATIKUS konverzió) view-n
> `TypeError`-t dobott a statikus `is Map<String,String>` kapu Dart-lazy-cast
> gyengesége miatt — mérve: `type '_Map<String, int>' is not a subtype of
> type 'String?' in type cast`; javítva elem-szintű `is String`
> ellenőrzéssel + `try/on TypeError` védelemmel. A `today_plan_screen.dart`
> egy ELUTASÍTOTT deep linket megkülönböztethetetlenné tett a "nincs is
> deep link" esettől, ezért a flag-ellenőrzés kimaradt és egy manipulált
> paraméter TÖBBET kapott, mint egy jólformált, de letiltott — javítva egy
> explicit `isDeepLinkLaunch` paraméterrel. **Nyitott MINOR (kötelezően a
> jövőbeli notification/router wiring kör briefjébe kerül, nem örökölhető
> csendben):** az `isDeepLinkLaunch` hívó-beállítású és alapértelmezetten
> `false` — ha egy jövőbeli hívó ELFELEJTI kitenni egy elutasított
> `launchRequest` mellett, a screen STRUKTURÁLISAN nem tudja megkülönböztetni
> ezt a normál belső navigációtól (a MAJOR-2 eredeti mintája). A wiring
> körnek `tryParse`-t TOTÁLISSÁ kell tennie (`accepted`/`rejected` sealed
> eredmény) vagy sealed `TodayLaunchContext`-et kell bevezetnie, ÉS egy a
> VALÓDI router-hívási úton futó elfogadási cellát kell írnia. Lecke:
> **L309**. Következő kör: E07-R23 (PlanCompiler és Practice Engine
> végrehajtás, SDD Ch8 Kör 23), új sessionben.


> ## 🛡️ [IMPLEMENTER-ŐRÖK + SLOT-ZÁR] Gépi őrök a claude-harness köröknek, és a párhuzam MÁSODIK gyökéroka — ADR 0309 (2026-08-18)
>
> **Implementer-őrök (PR #309, ADR 0309).** A MiniMax/Sonnet implementer három
> mért hibaosztálya (listán kívüli fájl, gate-csonkítás, jelzés nélküli kilépés)
> szövegesen tiltva volt, mégis megtörtént — ezért gépi réteg került alá:
> `tools/hooks/implementer_guard.py` (scope-őr fail-closed, tiltott
> parancsalakok, korlátos Stop-jelzésőr, `dart format` írás után), amit a
> `tools/mm-round.sh` `--settings tools/implementer-settings.json`-nal CSAK az
> implementer-sessionre tölt be. Emellé `tools/implementer-agents.json`
> (`round-auditor` alügynök a KÖTELEZŐ önellenőrzéshez), a nyilvántartás
> `max_out` oszlopa végre hat (`CLAUDE_CODE_MAX_OUTPUT_TOKENS`), és a kör utáni
> scope-audit is megkapja a briefet (eddig némán kimaradt).
> **Mérve élesben:** a modell kiadta a `Write`-ot egy listán kívüli fájlra →
> `PreToolUse:Write hook error: IMPLEMENTER-ŐR …` → a fájl nem jött létre.
>
> **Slot-zár szivárgás (PR #310).** Egyetlen futó kör mellett a driver „minden
> slot foglalt (2)"-t naplózott: a `.pipeline/lock` FD-jét a **tmux szerver**
> tartotta (E07-R22 drivere indította 18:13-kor, a 19:47-es merge után is élt).
> `PIPELINE_SLOTS=2` mellett az 1-es slot tartósan foglalt maradt — ez a
> „0 párhuzamos kör" mérés MÁSODIK, a sor-szerializációtól független oka.
> Javítva: a tmux-hívások fd 9-et lezáró alhéjban futnak; funkcionális
> falszifikációs teszt őrzi (`tools/tests/test_slot_lock_inheritance.py`).

> ## 🚀 [PIPELINE v2] Áteresztő-program beütemezve — ADR 0307, E99-R14…R19 (2026-08-18)
>
> A lánc saját sebességének MÉRT átvizsgálása után hat governance-kör került a
> sor élére (`E99-R14` … `E99-R19`, mind `pending`), és a mérési alap az
> [ADR 0307](docs/adr/0307-pipeline-throughput-program-v2.md)-ben áll.
> **Azonnali intézkedés már megtörtént:** a `.pipeline/engine-override` tíz napja
> `terra`-n ragadt (a 08-06-i kvótaválság maradéka, M3 közben 92%-on) — törölve,
> a sor `engine` oszlopa dönt újra. Mérve: azonos epicen belül `terra` medián
> **63 p**, `minimax` **49 p**, `sonnet-impl` **41 p** kör-idő.
>
> A hat kör: **R14** lejáró motor-override + motor-statisztika · **R15**
> halt-eszkaláció (az utolsó self-heal kísérlet MÁS motorral) és ismétlődő
> riasztás (mérve 42 órás néma állás, 08-16→08-18) · **R16** kör-granularitás
> mérése + összevonási javaslat · **R17** l10n-fragmentumok (az `app_*.arb` 36
> nyitott briefben ütközik) · **R18** generált `public.dart` barrelek (25/18/8
> brief) · **R19** main-szinkron, egyetlen záró commit, őszinte `risk` besorolás.
>
> A `PIPELINE_SLOTS=2` mérve 08-04 óta NULLA párhuzamot adott (120 kör, 1 átfedő
> pár): a sor függőségi értelemben soros volt. Az E99-sáv az első valóban
> diszjunkt munkafolyam — a `tools/round-slots.py plan` az E07-R22 mellé már
> admittálja az E99-R14-et.

> ## 🔁 [HEAL E99-R14/H7] `outcome=retry` — exact-SHA Full Gate 1 tesztje pirosra váltott, de a kör diffje `tools/**`+`docs/**`-re szorítkozik; izolált 5× repro a pontos SHA-n zöld, a rerun is zöld — ismétlődő, kör-független `song_import_controller_test.dart` flake (2026-08-18, L316)
>
> Az E99-R14 exact-SHA Full Gate futása (`32190289173`, fej `bfd43bf9`) 5072
> zöld/1 piros eredménnyel állt le: `test/features/song_trainer/application/
> import/song_import_controller_test.dart: cancellation during import closes
> the workspace without a record` — `Expected: empty`, `Actual:
> [_Directory: '.../import-1']`. A kör brifje kizárólag GOV-08 motor-policy
> tooling (`tools/engine-profile.sh`, `tools/round-metrics.py`,
> `tools/round-pipeline.sh` + tesztek, `docs/rounds/e99-r14-*`) — `git diff
> origin/main...bfd43bf9` nulla `song_trainer` találatot ad, nincs ok-okozati
> út. **Ugyanaz a teszt, ugyanaz az assert**, mint [[L182]] (E05-R21,
> 2026-08-08) — ott egy normál kör oldotta fel inline, itt HALT-ot és
> dedikált self-healt igényelt. Ez a heal a [[L182]]/[[L183]] mért eljárását
> követte, nem fogadta el bemondásra: izolált `git worktree --detach` a
> PONTOS `bfd43bf9` SHA-n, `flutter test
> test/.../song_import_controller_test.dart` **5×** → **5/5 zöld**. Utána
> `gh run rerun 32190289173 --failed`, várakozás `tools/wait-for-ci.sh`-sal
> ELŐTÉRBEN (sosem csupasz `gh run watch`) → **`completed success`, ugyanazon
> `bfd43bf9`-n**; Router CI erre a SHA-ra függetlenül is már zöld volt. Nincs
> kódváltoztatás — a self-heal hatóköre (`tools/**`/`.ai/**`/`docs/adr/**` +
> a megállt kör brifje) nem terjed ki a `song_trainer`-import rétegre, még ha
> a race-nek volna is kézenfekvő javítása. **Nyitva maradt, dokumentált
> tartozás:** ez a flake MOST MÁR KÉTSZER okozott mérhető költséget azonos
> gyökérokkal, javítatlanul — egy jövőbeli, a `song_trainer`-import réteget
> explicit célzó NORMÁL kör brifjének fel kellene vennie (`cancel()`
> várja meg a workspace-cleanup Future-jét, vagy a teszt egy
> determinisztikus completion-jelre várjon a nyers `list()` helyett).
> Lecke: **[[L316]]**.

> ## 🔁 [SELF-HEAL E07-R23/H6, 2. előfordulás] `outcome=retry` — az alábbi „KÉSZ" API-kulcsos javítás ~10 percen belül nyomtalanul eltűnt; nincs kód-gyökérok, a user kötelező kulcs-politikát hozott, és előfizetéses `codex login` állította helyre — VALÓDI hívással igazolva (2026-08-18, L315)
>
> Az alábbi [HEAL E99-R14/H6] bejegyzés „KÉSZ" jelzése **RÉSZBEN ELAVULT**: a
> 21:03-kor API-kulccsal helyreállított `~/.codex/auth.json` 21:03 és E07-R23
> 21:18-as újabb H6-ja között **nyomtalanul eltűnt** — nem lejárt, a fájl
> maga hiányzott. Ez a self-heal megmérte: `tools/**` egyetlen scriptje sem
> nyúl `~/.codex/auth.json`-hoz (Class A kizárva), a
> `~/.codex/log/codex-login.log`-ban 20:57:51Z után nincs újabb login/logout
> esemény — a fájl nem egy újabb `codex login`-tól tűnt el, dokumentált nyom
> nélkül. Vizsgálat közben a `main` egy párhuzamos, emberi-vezérelt session
> commitjával bővült (`ba621b8d`): **kötelező policy**
> (`docs/execution/pipeline-selfheal-prompt.md` „Kulcs-politika") — a boxon
> talált `RAG_OPENAI_API_KEY` (`~/.rag-openai.env`, egy vakvágány, amit ez a
> heal NEM használt) és bármely hasonló kapóra jövő kulcs motor-hitelesítésre
> fordítása **TILOS** (a user API-számláját terhelné), lejárt motor-authnál a
> helyes válasz `blocked`+indoklás vagy működő motor-profilra váltás. Percekkel
> később `~/.codex/auth.json` visszatért `"Logged in using ChatGPT"`
> (előfizetéses mód) — ezt EZ a self-heal független, VALÓDI
> `codex exec -s read-only` hívással igazolta (5 025 token, exit 0), nem
> fogadta el bemondásra. A `terra` profil élő E99-R14-folyamat alatt állt a
> mérés pillanatában, ezért az `engine-profile.sh use terra` nem lett volna
> biztonságos workaround. Nincs PR, nincs kód-diff: `outcome=retry`, a lánc
> feloldódik, E07-R23 a megőrzött pre-flighttal (`9c2aa9bb`) újra sorra kerül.
> Lecke: **[[L315]]**.

> ## 🔐 [HEAL E99-R14/H6] KÉSZ — Codex CLI OAuth refresh token „already used" (401), a boxon frissen megjelent API-kulccsal helyreállítva, VALÓDI `codex exec` hívással bizonyítva — nincs kód-diff, egyúttal E07-R23/H6-ot is feloldja (2026-08-18)
>
> Az E99-R14 saját, review M5 leletét záró **kötelező Codex-javító köre**
> (eredeti kísérlet + 2 automatikus folytatás) `status=unknown`-nal halt el;
> HAT másodperccel az erre indított önjavítás elindulása után egy TŐLE
> FÜGGETLEN kör, az E07-R23 (implementer=codex) is H6-tal állt le ugyanazzal
> a mintával. Mindkét kör Codex-alfolyamat-logja (`/tmp/codex-e99-r14-m5.log`,
> `/tmp/codex-e07-r23.log`) azonos, mért hibát adott: `codex_login::
> auth::manager: Failed to refresh token: 401 … code: "refresh_token_reused"`
> — a `~/.codex/auth.json` refresh tokenjét egy másik folyamat már
> felhasználta, ezért a CLI onnantól minden hívásra 401-et kapott. Mivel
> MINDEN `engine=codex` sor (és az E99-R14 MiniMax→Codex javító-eszkalációja
> is) ugyanazt a megosztott `~/.codex` CODEX_HOME-ot használja, a gyökérok
> közös infrastruktúra, nem a két kör tartalma.
>
> **Nem kód-javítás, hitelesítés-helyreállítás.** Az önjavítás indulása körüli
> percekben megjelent a boxon egy `~/.openai.env` (`OPENAI_API_KEY=`,
> friss időbélyeg, helyes jogosultság, **nincs** hozzá tartozó cron/
> systemd/repo-eredet — mérve, kizárva) — a jelek (+ két aktív kézi SSH-
> session) kézi emberi elhelyezésre mutatnak, amit a self-heal jelentése
> KÖRÜLMÉNY-alapú következtetésként jelöl, nem tanúsítványként. A
> `codex login --help` dokumentált headless-útját követve
> (`printenv OPENAI_API_KEY | codex login --with-api-key`), a
> `~/.codex/auth.json` időbélyegzett mentése után, a self-heal
> helyreállította a hitelesítést, és — mivel a `codex login status` a törött
> állapotban is „Logged in"-t mutatott (csak a LOKÁLIS fájlt nézi) — EGY
> VALÓDI `codex exec -s read-only` hívással igazolta: helyes válasz, 23 303
> token, valódi session-id. Lecke: **[[L314]]**.
>
> **Nyitva maradt, dokumentált mellékhatás (emberi döntés kell):** a
> `~/.codex` mostantól API-kulcsos, TOKENENKÉNTI díjazású hitelesítéssel megy,
> NEM a korábbi ChatGPT Pro előfizetéssel — a
> `docs/execution/engine-registry.tsv` `codex` sora (`auth_env: -`) ezt még
> nem tükrözi. Ha ez nem szándékos tartós váltás, `codex login`
> (böngészős vagy `--device-auth`) visszaállítja az előfizetéses módot.

> ## ✅ [HEAL E99-R14/H3] KÉSZ — a lánc cronja minden firingre `PIPELINE_ORCH_SWAP_ENGINE=minimax`-ot exportál, amit a driver-tesztek ambiensként örököltek — PR #311 (más session írta, ez a heal függetlenül újramérte), `80cdb46a` (2026-08-18)
>
> Az E99-R14 (GOV-08) a saját brief-diffjén zölden állt, de a kötelező teljes
> `tools/tests` suite négy motor-függetlenségi teszttel
> ([review](docs/reviews/e99-r14-review.md) M4: `4 failed, 508 passed, 546
> subtests`) pirosra váltott, és H3-mal megállt
> (`halted_at=2026-08-18T20:05:40Z`). A self-heal (1/3. kísérlet) megmérte a
> gyökérokot: a `.pipeline`-t vezénylő cron-sor (`crontab -l`) MINDEN firingre
> `PIPELINE_ORCH_ROTATION=alternate PIPELINE_ORCH_SWAP_ENGINE=minimax`-ot
> exportál — ez öröklődik a tmux szerver globális környezetén és minden
> onnan induló session/gyerekfolyamaton át, a `tools/tests/
> test_orchestrator_rotation.py`/`test_reviewer_independence.py`
> driver-segédje pedig `dict(os.environ)`-ból építette a tesztelt
> `round-pipeline.sh` gyerekfolyamat környezetét. A MÉRT alapértelmezést
> (`orch_swap_engine=sonnet-impl`, user-döntés 2026-08-11) így csendben
> felülírta az üzemeltetői override, és a teszt a kettő ÜTKÖZÉSÉT mérte, nem a
> kódot — `bash -x` közvetlen reprodukcióval igazolva. Ugyanez a hibaosztály
> már egyszer félrevezetett egy self-healt (HEAL E07-R21/H2, kézi
> env-tisztítással megkerülve, a defekt megmaradt), és szerkezetileg [[L312]]
> rokona (ADR 0307 §1.3.1 — ott egy FD-t, itt egy env változót szivárogtat a
> tmux szerver).
>
> **A tényleges javítást egy párhuzamosan futó másik governance-session adta**
> (`/tmp/ss-hermetic`, branch `gov/hermetic-driver-tests`, PR
> [#311](https://github.com/wolfcasaba/strumsight/pull/311), squash
> `80cdb46a`, Router CI zöld a pontos head SHA-n): mindkét driver-segéd a
> bázis környezetből mostantól kiszűri a `PIPELINE_*` kulcsokat, plusz egy
> falszifikált regressziós őr (`AmbientEnvironmentLeakTest` — RED a szűrés
> kiszedésével, GREEN vissza). Ez a self-heal — AGENTS.md §13 szellemében —
> NEM indított versengő második javítást ugyanazon a két fájlon: bevárta a
> már futó CI-t (`tools/wait-for-ci.sh`, védett timeouttal), majd a merge
> UTÁN egy izolált klónban, a SAJÁT szennyezett ambiensében
> (`PIPELINE_ORCH_SWAP_ENGINE=minimax` élve a futtató shellben) függetlenül
> újramérte: `python3 -m pytest tools/tests -q` → **496 passed, 550
> subtests, 0 hiba**.
>
> **Nyitva maradt, dokumentált megfigyelés (nem ennek a healnek a scope-ja):**
> a crontab `PIPELINE_ORCH_SWAP_ENGINE=minimax` sora ma is ÉLESben minden
> Terra-vezényelt kör csere-implementerét `minimax`-ra kényszeríti a
> dokumentált `sonnet-impl` alapértelmezés helyett — pontosan az az
> „elfelejtett, sosem lejáró override" minta, amit maga az E99-R14 D1/D2 a
> `.pipeline/engine-override` FÁJLRA kíván kezelni. Emberi/governance döntés,
> ezt a self-heal nem módosította. Lecke: **L313**. A lánc E99-R14-gyel
> folytatódik a következő cron-firingen.


> **E07-R19 KÉSZ — PR #303, `2ce22f3b` (2026-08-18).** A local plan
> repository elkülönített draft/active/archive névterekkel, checksumos
> rekord-szintű korrupció-containmenttel, v0→v1 migrációval és korlátos
> történettel merge-elve. A független review és security re-review APPROVED;
> Full Gate exact-SHA: `32147063069`, Router CI exact-SHA: `32148470452`.
> Következő kör: E07-R20, új sessionben.

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-19
> (E07-R26 done — outcome ingestion + plan revision, caller-fed / zero
> repository writes, see banner above.) Prior: 2026-08-19
> (E99-R15/GOV-09 done — self-heal engine escalation + halt-reminder throttle,
> see banner further below.) Prior: 2026-08-18
> (E07-R18 done — application-level, cancellable, state-machine-driven
> GenerationOrchestrator: immutable `GenerationState` (idle/running/completed/
> cancelled/failed + 4 stage checkpoints), a `GenerationOrchestrator` that
> chains the R05–R17 evidence/priority/candidate/time-budget/scheduling/
> review-queue/validator/repairer services into one cancellable, per-request
> single-flight run, and a Flutter-free `PlanGeneratorController` bridge. A
> §0.0 pre-flight revision resolved a measured gap the first dispatch
> correctly stopped on (no scope-approved `WeeklyScheduleDecision →
> AdaptivePracticePlan` assembly contract existed) by assigning that assembly
> to the already-allowed orchestrator file, no new production file. Independent
> review found and closed 1 BLOCKER (a same-request double-`generate()` call
> on `PlanGeneratorController` threw an uncaught `StateError` instead of
> resolving `AppResult` — violated ADR 0266's "no raw exception crosses the
> boundary") + 1 MAJOR (the validate-reject/repair-fail no-activation branch
> had zero test coverage) in one fix round, both confirmed fixed via a
> disposable probe test run by hand in an isolated clone; security review
> (risk=high) PASS with 4 forward-looking NOTEs for the future activation
> implementation. Full Gate and Router CI exact-SHA green, PR #300. Both
> flags remain `false`, zero production callers. Prior: E07-R17 done — bounded deterministic review queue: typed targets/outcomes,
> explicit local-date interval policy, strict daily budget, deduplication and
> replacement-required handling; review APPROVED, exact-SHA CI green, PR #296.
> Prior: E07-R16 done — bounded, evidence-based progression/regression policy for
> the AI Practice Generator: centralized `ProgressionPolicy` bounds
> (one-step-max adaptation, tempo clamp, cooldown, minimum evidence),
> discomfort/safety always blocks advance regardless of performance,
> repeated-struggle-only regression (a single weak session is noise),
> immediate "too hard" self-report override, every decision
> evidence-referenced; independent review + security PASS, Full Gate and
> Router CI exact-SHA green, PR #295. Prior: E07-R15 done — domain-pure,
> deterministic WeeklyScheduler with daily focus, rest/unavailable,
> high-load, bounded-review and signed song-target performance guards;
> independent review + security PASS, Full Gate and Router CI exact-SHA
> green, PR #294. The E07-R15 H3 self-heal narrowed its brief scope to the
> shared scheduling-fixture directory with an executable scope-audit
> regression guard; the subsequent H7 self-heal made the signed target-date
> performance boundary explicit and added its brief-contract regression
> guard (PR #290, Router CI exact-SHA green); a repeated H7 then exposed
> that resumed branches were not required to integrate that merged brief
> before review, so the pipeline prompt now gates repair/review on measured
> `origin/main` ancestry (HEAL E07-R15/H7, upstream-sync).)**

> ## ✅ [HEAL E07-R19/H4] KÉSZ — a v0→v1 envelope-migráció nem relabelte a schemaVersion-t; a fix a kör saját ágára ment, nem `main`-re (2026-08-18)
>
> A független review (`docs/reviews/e07-r19-review.md`, branch
> `minimax/e07-r19-local-plan-repository` @ `dce4f957`) egy nyitott MAJORt
> (M-01) mért: `PracticePlanMigrator._migrateVxToCurrent` a v0 envelope-ot
> változatlanul adta vissza, így a migrált eredmény `schemaVersion`-je `0`
> maradt az elvárt `1` helyett (ADR 0267 §6, brief A7 below-cell) —
> eldobható próba: `Expected: <1>; Actual: <0>`. A review „a kör korábbi
> MiniMax- és Codex-javítási kerete a handoff szerint már elfogyott"
> indoklással H4-gyel halt.
>
> A self-heal (1/3. kísérlet) megmérte, hogy a branch `.codex-round-status`
> jelzése (`head=0d505ca7`, `signalled_at=12:30:06Z`) a MiniMax implementer
> SAJÁT, első befejezés-jelzése volt, nem egy review-utáni javító kör; a
> kör két korábbi self-healje (H3 — brief-scope, PR #301; H-NOSIGNAL —
> `wait-for-round.sh` infra, PR #302) egyike sem érintette a
> migrátort. A hibás kód kizárólag a kör SAJÁT, `main`-be még nem olvadt
> ágán él (a fájl `main`-en nem is létezik), ezért a javítás célja a kör
> ága lett — nem egy `main`-alapú `heal/`-branch —, a
> `pipeline-orchestrator-prompt.md` H8-szakaszának „normál push a
> kör-worktree-re" mintáját követve. `tools/round-pipeline.sh`
> mérce-őrszeme (`heal_pr_number` / `gate_test_count` /
> `gate_artifact_hashes`) ezt kifejezetten tolerálja, amíg `main` és a
> védett gate-artefaktumok (`tools/round-gate.sh`,
> `.github/workflows/{build-apk,router-ci}.yml`) érintetlenek.
>
> A javítás: `_migrateVxToCurrent` másolatot ad vissza
> `schemaVersion: currentSupportedSchemaVersion` felülírással (a checksum
> csak a `body`-t fedi, tehát ez nem érvényteleníti); a meglévő
> `practice_plan_migrator_test.dart` "below cell" esete maga is a régi,
> hibás `0` értéket várta — ez az oka, hogy a gate korábban zölden ment át
> M-01 mellett — most a current verziót várja. Elkülönített worktree-ben
> mérve piros a javítás előtt (`Expected: <1>; Actual: <0>`), zöld utána;
> `tools/round-gate.sh test/features/practice_generator/data/
> local_repository_test.dart test/features/practice_generator/data/
> practice_plan_migrator_test.dart` minden lépése zöld
> (format/analyze/mindkét célzott teszt/architecture/secrets/l10n). Fix
> commit a kör ágán: `45395d9f`. `main` és a round-brief érintetlen.
> `docs/LESSONS.md` **L304**. A lánc E07-R19-cel folytatódik a következő
> cron-firingen — a következő orchestrátor-session friss review-t indít a
> most javított ágon.

> ## ✅ [HEAL E07-R19/H-NOSIGNAL] KÉSZ — `wait-for-round.sh`/`wait-for-router.sh` baseline-ja folyamat-memóriában élt, nem vette észre a köztes-hívások közt már kész jelzést (2026-08-18)
>
> Az E07-R19 folytató köre (orchestrátor=Terra, implementer=minimax) jelzés
> nélkül halt el 12:37:10-kor — a pipeline elakadás-gyorsítója (E99-R13 óta)
> ~2 mp alatt helyesen észlelte, hogy a `codex` motor-folyamat kilépett. A
> tényleges implementer-munka (MiniMax kezdeti implementáció + 1 MiniMax- +
> 1 Codex-javítókör) eközben MÁR KÉSZ és pusholva volt
> (`minimax/e07-r19-local-plan-repository` @ `0d505ca7`, `.codex-round-status`
> `status=done`/`signalled_at=12:30:06Z`).
>
> A session rollout (`~/.codex-terra/sessions/…/rollout-2026-08-18T11-55-08-…jsonl`,
> strukturált JSON, nem a redundáns TUI-újrarajzolással dagadó tmux-log)
> megmérte a gyökérokot: a Terra `exec_command`/`wait` eszköze csendes
> parancsnál önmagától „yield"-el, ezért a dokumentált „exit 5 → hívd meg
> újra" szerződés szerint `tools/wait-for-round.sh`-t ~20, egyenként FRISS
> folyamatként hívta (cell ID 65–87), nem egyetlen hosszan futó hívásként.
> A script a stale-signal védelmét (E02-R08) egy `baseline` shell-változóban
> tartotta, amit MINDEN friss folyamat a SAJÁT indulásakor, a jelzésfájl
> AKKORI tartalmából számolt újra — egy, a tényleges befejezés (12:30:06Z)
> UTÁN induló friss hívás ezért a friss `done`-t tekintette baseline-nak, és
> sosem jelentette késznek. Az orchestrátor 7 percen át kizárólag üres
> kimenetet kapott, majd stale szöveges státusszal ("a Codex javító kör még
> fut") zárta a választ jelzés nélkül — pontosan az E07-R09 self-heal
> (2026-08-16) által már dokumentált és tiltott minta.
>
> A javítás a baseline-t egy, a munkapéldányban élő MARKER-fájlba
> (`.wait-for-round-baseline`/`.wait-for-router-baseline`, gitignore-olt)
> perzisztálja az első hívástól a terminális kézbesítésig, hogy a köztes
> friss újraindítások UGYANAZT lássák; `wait-for-router.sh` (`engine=auto`)
> byte-azonos mintát örökölt, ezért ugyanazt a javítást kapta. Két
> regressziós teszt (RED a javítás előtt, `5 != 0`, GREEN utána, mindkét
> scriptre) + egy nem-regressziós társteszt (az eredeti E02-R08 védelem
> változatlan). `tools/tests`: 467/467 zöld, 524 subtest. PR
> [#302](https://github.com/wolfcasaba/strumsight/pull/302), squash
> `5b520739`; Router CI zöld a pontos head SHA-n (router-only fix, nincs
> Dart-változás, build-apk nem indult). `docs/LESSONS.md` **L303**. A lánc
> E07-R19-cel folytatódik a következő cron-firingen.
>
> ## ✅ [HEAL E07-R19/H3] KÉSZ — a brief pre-flight calloutja Core/domain hiányra méretett, de nem mondta ki: a hiány meglévő típusokkal és írási sorrenddel is teljesíthető (2026-08-18)
>
> Az E07-R19 (Local repository, migráció és korrupcióvédelem) saját
> pre-flightja (sonnet-impl via Terra, branch
> `sonnet-impl/e07-r19-local-plan-repository`, commit `1801a399`) helyesen
> mérte, hogy sem `PracticePlanRepository`/`PracticeOutcome` domain-kontraktus
> (SDD Ch8 §30.1), sem Core atomikus write API nem létezik — de abból, hogy
> MINDKÉT hiány tilos-zónás fájlt igényel, H3-mal halt (`.pipeline/HALTED`,
> halted_at=2026-08-18T11:24:19+00:00).
>
> A self-heal (1/3. kísérlet) megmérte, hogy a következtetés túlterjeszkedő
> volt: a brief saját §0 callout-ja már megnevezte az R04
> `GenerationDraftRepository`-t — egy KONKRÉT osztályt, `abstract interface
> class` nélkül, meglévő domain típusra építve —, ami pontosan a
> „repository-szerződés" mintája; és egyetlen `KeyValueStore.writeString`
> hívás a hívó szemszögéből már all-or-nothing, tehát a „megszakított írás
> nem hagy félkész rekordot" invariáns kulcs-sorrenddel (ÚJ kulcs előbb,
> mutató-váltás utoljára) old meg, Core-módosítás nélkül — pontosan úgy,
> ahogy a repóban máshol (`storage_migrator.dart`, `json_document_store.dart`)
> már bizonyítottan működik.
>
> A feloldás kizárólag dokumentált §0.0 brief-revízió: `allowed_paths`
> byte-for-byte változatlan, 0 produkciós fájl módosult. Regressziós őr:
> `tools/tests/test_e07_r19_repository_contract_scope.py` (mért típus-tények
> zárolása + a §0.0 szöveg jelenléte — RED a mérje-fel briefen, GREEN a
> revízió után). PR [#301](https://github.com/wolfcasaba/strumsight/pull/301),
> squash `b87c7479`; Router CI zöld a pontos head SHA-n (nincs Dart-változás,
> build-apk nem indult). `docs/LESSONS.md` **L302**. A lánc E07-R19-cel
> folytatódik a következő cron-firingen.
>
> ## ✅ [E07-R11] KÉSZ — PlanValidator és korlátos deterministic repair (2026-08-16)
>
> A `PlanValidationContext` explicit catalog/availability/identity inputtal
> fail-closed validál; `error`/`fatal` nem aktiválható. A `PlanRepairer`
> determinisztikus, korlátos és minden lépést `systemAdaptation` okkal naplóz;
> sosem módosít completed múltat vagy növeli a hard időmaximumot. A független
> review egy active day completed-block múltmódosítási rést talált, amit a
> regressziós teszttel javítottunk. PR #285, squash `3178508c`; Full Gate
> `31933205113` és Router CI `31933789551` zöld. Következő: E07-R12.
>
> ## ✅ [E07-R10] KÉSZ — AdaptivePracticePlan, day, block és revision domain (2026-08-16)
>
> Az ADR [0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)
> (revízió-alapú immutable múlt) megvalósítása: `lib/features/practice_generator/domain/model/`
> — `AdaptivePracticePlan` (verziózott, veszteségmentes round-trip JSON,
> `generationProvenance`+`policyVersions`, `PracticePlanSummary` DTO), `PracticeDay`/
> `PracticeBlock` (közös, pinnelt `PracticeItemStatus` — 8 érték az SDD §16.5-ből
> szó szerint, `practice_block.dart`-ban, `PracticeGoalStatus`/`PracticeGoal`
> mintáját tükröző `canTransitionTo`/`transitionTo` + completed-content guard),
> `PlanRevision` (szigorúan monoton szám, TELJES immutable snapshot — nem diff),
> `PlanChangeSet`/`PlanChange` (strukturált before/after, typed `PlanChangeReason`,
> szabad szöveg nélkül).
>
> **Két scope-kérdést a pre-flight/kör közbeni §0.0/§0.0.1 brief-revízió oldott
> fel** (a brief eredetileg egy nem-létező `planned` státuszértékre hivatkozott
> — az SDD-ben csak §16.5 „Block status” 8-elemű listája létezik, külön „Day
> status” szakasz nélkül; illetve az implementer egy negyedik, megosztott
> teszt-fixture fájlt kért a brief 3-fájlos korlátján túl — a repo már meglévő
> `test/fixtures/<feature>/<terület>/<név>_fixtures.dart` konvencióját követve
> engedélyezve, `plan_enums.dart` érintése nélkül). A független review 1 MINOR-t
> talált (`PlanChangeType` a domain stabil-kódú konvenciója helyett nyers
> `.name`-et perzisztált) — egy rövid javító körben javítva (`0a479818`),
> függetlenül újramérve. A kötelező biztonsági review (`risk = "high"`) PASS:
> a `PracticePlanSummary` strukturálisan kizárja a `PracticeGoal.userNote`-ot
> (poison-pill teszttel bizonyítva), minden `fromJson` fail-closed, 4
> nem-blokkoló NOTE jövőbeli köröknek (perzisztencia/AI-tutor export).
>
> Két saját, független valódi-sértés próba (A2 revízió-immutabilitás, A4
> completed-block-tartalom-immutabilitás): mindkettő PIROSRA váltott a guard
> ideiglenes eltávolításával, majd zölden visszaállt. Review:
> [`e07-r10-review.md`](docs/reviews/e07-r10-review.md) (APPROVED),
> [`e07-r10-security.md`](docs/reviews/e07-r10-security.md) (PASS). PR
> [#283](https://github.com/wolfcasaba/strumsight/pull/283), squash `c2778bbc`,
> exact `4d4c3ee4`: Full Gate
> [31929041014](https://github.com/wolfcasaba/strumsight/actions/runs/31929041014)
> + Router CI [31929076484](https://github.com/wolfcasaba/strumsight/actions/runs/31929076484)
> success (Router CI manuálisan dispatch-elve, mert a csúcs-commit önmagában
> nem érintett trigger-útvonalat). Mindkét flag (`practiceGeneratorEnabled`,
> `plannerAssistEnabled`) `false` marad, nulla production hívó — production
> viselkedés változatlan. Következő kör: **E07-R11** (PlanValidator és
> deterministic repair, `docs/rounds/e07-r11-plan-validator-and-repair.md`).
>
> ## ✅ [HEAL E07-R11/H3] KÉSZ — az E07-R11 brief hiányzott egy megosztott validáció-fixture könyvtárat (2026-08-16)
>
> Az E07-R11 brief `allowed_paths`-a a két validáció-tesztfájlt
> (`plan_validator_test.dart`, `plan_repairer_test.dart`) és a property-tesztet
> névre szólóan sorolta fel, de egyetlen megosztott fixture-helyet sem —
> miközben §6/§6.1 mindkét tesztfájltól ugyanazt a nem-triviális
> `AdaptivePracticePlan`/`PracticeDay`/`WeeklyAvailability` felépítést várta
> el. A sonnet-impl (engine=minimax-m3) implementer emiatt listán kívül hozta
> létre `test/fixtures/practice_generator/validation/validation_fixtures.dart`-ot
> (munkapéldány `/home/ubuntu/ss-sonnet-impl-e07-r11`, `head=a82bef17`, 7
> piszkos fájl, egyik sem commitolva) — a scope-audit helyesen `stopped`-ra
> váltotta (H3, `.pipeline/HALTED` halted_at=2026-08-16T06:06:06Z).
>
> **Nem új hibaosztály.** A közvetlen precedens az ELŐZŐ kör, ugyanebben a
> feature-fában: `E07-R10` §0.0.1 — alig öt órával korábban (R10 merge
> `05:50:55`, R11 dispatch `05:51:04`) pontosan ugyanezt a hiányt mérte
> (`test/fixtures/practice_generator/plan/plan_fixtures.dart`), de az R11
> brief korábban (2026-08-15) lett előre megírva, és a két dispatch között
> nem futott olyan pre-flight, ami az R10-frissen-mért konvenciót átvezette
> volna. Lásd még `docs/LESSONS.md` **L242** (E06-R20) és **L246** (E06-R23) —
> ez a NEGYEDIK mérés ugyanarra a gyökérokra. A self-heal elolvasta a fájl
> teljes tartalmát: kizárólag a már engedélyezett `public.dart` típusaiból
> épít paraméterezhető teszt-builder függvényeket, 0 domain-döntés.
>
> Feloldás: `allowed_paths` bővült a `test/fixtures/practice_generator/
> validation` bare directoryval (R10/L242 mintáját követve, nem az egyetlen
> jelenleg létező fájlnevet rögzítve) — 0 tartalmi/architekturális döntés
> változott. Regressziós védelem:
> `tools/tests/test_e07_r11_validation_fixture_scope.py` — a mért
> halt-útvonalat futtatja `audit_legacy_scope()`-on a committolt brief ellen,
> és egy `validation/`-on kívüli szomszéd útvonalat is mér, bizonyítva, hogy
> a bővítés szűk maradt. Teljes `tools/tests` gate: 454 passed, 498 subtests
> passed. PR [#284](https://github.com/wolfcasaba/strumsight/pull/284),
> squash `46f8c23f`, Router CI
> [31931326850](https://github.com/wolfcasaba/strumsight/actions/runs/31931326850)
> success az exact `be5826a0` SHA-n (docs/tools-only, nincs Dart-változás,
> Full Gate nem releváns). Lecke: `docs/LESSONS.md` **L294**.
>
> A megállt kör saját munkapéldánya (`/home/ubuntu/ss-sonnet-impl-e07-r11`,
> commitolatlan, PR nélkül) SZÁNDÉKOSAN érintetlen maradt: ez a self-heal a
> megállt kör levezénylése helyett kizárólag az akadályt szüntette meg (ADR
> 0112 mandátum). A lánc a következő firingen E07-R11-et friss dispatchként
> vagy folytatásként veszi fel, a most javított `allowed_paths` alatt.

> ## 📦 Korábbi kör-narratívák → archívum
>
> A lezárt körök részletes története a
> [`docs/handoff-archive.md`](docs/handoff-archive.md) fájlban van.
> MIÉRT: ezt a fájlt MINDEN session és MINDEN kör elolvassa (orchestrátor +
> implementer), ezért a lezárt körök narratívája itt tiszta kontextus-adó.
>
> **Szabály (ADR 0175 §4):** a fejlécben a friss állapot és a **két legutóbbi**
> kör bannere marad; minden korábbi banner az archívumba kerül a kör lezárásakor.
> 2026-08-18 (E07-R23 zárása): az E07-R21 és HEAL E07-R21/H2 banner
> archiválva; a fejlécben az E07-R23 és E07-R22 banner marad. 2026-08-18
> (E07-R22 zárása): az E07-R20 banner archiválva; a fejlécben az E07-R22,
> E07-R21 és HEAL E07-R21/H2 banner marad (a kettő együtt az R21 narratíva).
> 2026-08-16 (HEAL E07-R11/H3 zárása): a HEAL E07-R09/H5 banner archiválva;
> a fejlécben az E07-R10 és HEAL E07-R11/H3 banner marad.
> A korábbi diéta-bejegyzések teljes szövege: `docs/handoff-archive.md`.

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
  Hub→Setup→Session út production-drótozása **KÉSZ** (E02-R21, PR #55,
  `6e5cec7`) — a `practiceSessionHostProvider` élesben él, a §3
  rendszerszintű rés pótolva.
  Evidencia: [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md).
- **Epic 3 (Song Trainer) elkezdve** — E03-R01 (kickoff, baseline+ADR-ek+flag),
  E03-R02 (SongDocument V2 identitás/metaadat domain modell + codec),
  E03-R03 (section/measure struktúra + determinisztikus tempo/meter/key map +
  SongTimeMap), E03-R04 (track/event domain modell + monophonic elemzés),
  E03-R05 (validator/normalizer/capability resolver), E03-R06 (legacy
  Song/Setlist migrációs adapter) és E03-R07 (fájlrendszeres Song repository
  és asset store) kész. A modell flagek mögött, hívó UI/import-runner nincs
  — production viselkedés változatlan.
- **Epic 5 (Computer Vision) implementáció TELJES** — E05-R01…R30 mind
  merge-elve: capability audit + hat alapozó ADR, hand/pose landmark
  provider, guitar geometry, metric engine, feedback policy, session
  controller, audio–vision szinkron, observation fusion, posture safety,
  Practice/Song Trainer/AI Tutor/Analyze integráció, device tier + thermal
  hardening, és a záró minőségi kapuk (architektúra-guard, model-integritás,
  vision-off paritás, evaluation harness, completion report, rollout
  runbook). **Mind a 11 vision flag `false` marad minden környezetben** — a
  végső elfogadási kapu a user valódi-eszközös HORIZON-menete (§6 „Kötelező
  sorrend"), nem a technikai készenlét. Evidencia:
  [`docs/sdd/epic-05-completion-report.md`](docs/sdd/epic-05-completion-report.md).
- **Epic 6 (Audio Analysis 2.0) elkezdve** — E06-R01 (kickoff: V1 baseline
  mérés + hat kötött ADR: [0215](docs/adr/0215-analysis-document-versioning.md)–[0220](docs/adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)),
  E06-R02 (`lib/features/audio_analysis/domain/` — verziózott,
  immutable V2 domainmodell, 14 fájl + `public.dart` barrel; 1 MINOR
  security follow-up nyitva), E06-R03 (`lib/features/audio_analysis/data/`
  — determinisztikus `AnalysisDocumentCodec` + `LegacyAnalyzeAdapter`/
  `LegacyViewAdapter` veszteségmentes V1↔V2 migráció, [ADR
  0221](docs/adr/0221-legacy-analysis-v2-migration-mapping.md); 1 MINOR
  follow-up R21-re), E06-R04 (`lib/features/audio_analysis/engine/` +
  `domain/analysis_progress.dart` — moduláris, megszakítható,
  progresszt publikáló pipeline-szerződés fake stage-ekkel, konkrét DSP
  nélkül; 1 MINOR follow-up kötelező R07 pre-flight ellenőrzéssel),
  E06-R05 (`lib/features/audio_analysis/data/input/` +
  `domain/analysis_input.dart` — közös, validált input-boundary a
  mikrofonos és importált audio köré, [ADR
  0217](docs/adr/0217-analysis-raw-audio-retention.md) végrehajtása,
  bounds-safe `WavDecoderAdapter` a bitre változatlan core dekóder körül),
  E06-R06 (`lib/features/audio_analysis/data/capture/` +
  `domain/recording_level.dart` — V2 `AnalysisRecorder`, run ID-alapú
  stale-chunk szűrés, inkluzív maximum kliphossz nem-hibás lezárással,
  öt cellás lifecycle-mátrix, olcsó peak/RMS + hysteresises
  clipping-preview, a meglévő `MicCapture`/`AudioSessionCoordinator`
  (ADR 0056) kompozíciójával, `ClipRecorder` érintése nélkül; a 2 nem
  blokkoló MINOR follow-up (F2/S3/S4) az R07 pre-flightban ÉRTÉKELVE, de
  NYITVA marad — a köztes-chunk preview-hiány a valós idejű `RecordingLevel`
  korlátja, nem az R07 offline stage-jéé, ld. §3) és **E06-R07**
  (`lib/features/audio_analysis/engine/quality/` — determinisztikus,
  verziózott jelminőség-riport: `SignalQualityMath`/`QualityThresholds`/
  `SignalQualityStage`, [ADR
  0224](docs/adr/0224-signal-quality-stage-measurement-boundary.md), a
  riport a felvételről szól, sosem a játékról; `dsp_config.dart` bitre
  változatlan; bekötetlen), **E06-R08** (preprocessing/resampling policy,
  [ADR 0225](docs/adr/0225-analysis-preprocessing-and-resampling-policy.md)),
  **E06-R09** (V1 `ClipAnalyzer` stage-adapter és parity, [ADR
  0226](docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md))
  **E06-R10** (event evidence modell + onset/strum timeline builder,
  [ADR 0228](docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md))
  **E06-R11** (chord frame evidence, verziózott V1-paritásos szegmens-
  összeállítás + DSP-primary/ML-advisory decoder-provenance flag mögött,
  [ADR 0229](docs/adr/0229-analysis-chord-decoder-fusion-strategy.md)),
  **E06-R12** (beat grid + tempo curve, target-first becslő,
  [ADR 0230](docs/adr/0230-beat-grid-tempo-curve-boundary.md)) és
  **E06-R13** (target alignment engine — monoton, sávos DP-illesztő +
  tempófüggő tolerancia-policy, [ADR
  0231](docs/adr/0231-target-alignment-engine-boundary.md)),
  **E06-R14** (target/free-play timing- és rush/drag-metrikák, release-safe
  `MetricGate`, [ADR
  0232](docs/adr/0232-timing-metric-identity-and-publication-boundary.md))
  **E06-R15** (rhythm consistency + groove-proxyk — IOI-konzisztencia,
  subdivision-illesztés, target-only swing, [ADR
  0233](docs/adr/0233-rhythm-consistency-and-groove-proxy-boundary.md)),
  **E06-R16** (dynamics + stroke balance — attack-strength/local-RMS/
  dinamikai tartomány/accent-balance, release-safe `DynamicsGate`, [ADR
  0234](docs/adr/0234-dynamics-evidence-and-gating-boundary.md)) és
  **E06-R17** (monofonikus pitch capability — YIN-alapú frame→szegmens→
  capability-gate→hét metrika, [ADR
  0235](docs/adr/0235-monophonic-pitch-capability-boundary.md)),
  **E06-R18** (technique-proxy kísérleti modul — öt Lab-only, mérésre
  korlátozott proxy név/tartalom-tiltással, [ADR
  0236](docs/adr/0236-analysis-technique-proxy-safety-and-naming.md)) és
  **E06-R19** (confidence combiner + capability resolver — egyetlen döntési
  pont minden capability státuszára/kalibrált confidence-ére, geometriai
  kombináció, verziózott küszöbök és identity-kalibráció, [ADR
  0237](docs/adr/0237-analysis-confidence-combiner-and-capability-resolver.md))
  **E06-R20** (determinisztikus insight engine — kilenc evidence-backed
  coaching-szabály, maximum-policy ranker, hotspot ranker, [ADR
  0238](docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md)),
  **E06-R21** (fájl-alapú `AnalysisRepository` + legacy Library migráció,
  atomikus temp→verify→rename írás, rekord-szintű korrupció-karantén, [ADR
  0239](docs/adr/0239-analysis-document-storage.md)), **E06-R22**
  (analysis runner: 11-állapotos state machine, run-ID-alapú controller,
  futásonkénti isolate-futtató, pipeline-agnosztikus `T = AnalysisDocument`
  határ, [ADR 0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md)),
  **E06-R23** (overview screen + metric cardok, ötállapotú metric card,
  insight-/signal-quality card, [ADR
  0241](docs/adr/0241-analysis-overview-presentation-boundary.md)) és
  **E06-R24** (többrétegű, zoomolható timeline — nyolc capability-vezérelt
  lane, tiszta `TimelineViewport`, adaptív ruler, hotspot-navigátor,
  virtualizáció, [ADR
  0243](docs/adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md)),
  **E06-R25** (session-összehasonlítás és fejlődési trend,
  `CompatibilityEvaluator`/`TrendBuilder`, [ADR
  0246](docs/adr/0246-analysis-session-comparison-and-trend-contract.md)) és
  **E06-R26** (Practice/Song/Tutor/Progress integrációs adapterek
  kizárólag publikus barreleken át, redaktált Tutor-snapshot, egyszeri
  progress-kreditálás — új ADR nincs, ADR 0176/0132/0141/0202 végrehajtása),
  **E06-R27** (export/share/privacy: allowlist-alapú `RedactionPolicy`,
  `AnalysisExportCodec`, `ShareCardBuilder`, `ExportAnalysisUseCase`,
  `DeleteAnalysisUseCase`, [ADR 0247](docs/adr/0247-analysis-export-share-and-delete-contract.md))
  **E06-R28** (cache, performance és model-lifecycle infrastruktúra —
  `AnalysisCacheKey`/`AudioFingerprint`/`AnalysisCache`/`ModelByteCache`,
  bekötetlen, [ADR 0248](docs/adr/0248-analysis-cache-key-and-performance-budget.md))
  és **E06-R30** (shadow rollout, migráció, Epic-lezárás — ZÁRÓ KÖR:
  `AnalysisRolloutStage`/`ShadowAnalysisRunner`/`ShadowDiffReport`, teljes
  50-session migrációs+rollback teszt, 29 ADR státusz-frissítés,
  [`docs/sdd/epic-06-completion-report.md`](docs/sdd/epic-06-completion-report.md))
  **kész — az Epic 6 mind a 30 köre lezárult.** A `docs/execution/pipeline-queue.tsv`
  minden sora `done`, a rollout shadow szinten marad, a folytatás
  (valódi kalibráció/GOV-30a, CI evaluation wiring/GOV-30b, V2 pipeline
  összeszerelés/GOV-30c, opt-in/V1-kivezetés) emberi döntést igényel, lásd
  §6. **`audioAnalysisV2Enabled`
  (+ al-flagek) `false` marad minden környezetben a teljes Epic alatt** (ADR
  0220) — a V1 Analyze marad a shipping út, production viselkedés bitre
  változatlan (a V2 domain + a codec/adapter/input-gateway/recorder teljesen
  bekötetlen). Evidencia:
  [`docs/baseline/epic-06-audio-analysis-start.md`](docs/baseline/epic-06-audio-analysis-start.md),
  [`docs/reviews/e06-r06-recorder-audio-session-integration-review.md`](docs/reviews/e06-r06-recorder-audio-session-integration-review.md).
- **Epic 7 (AI Practice Generator) — LEZÁRVA E07-R30-cal (2026-08-19, PR #333,
  squash `ee5821dd`).** `ShadowPlanGenerator` (evaluation-only, no-op
  activation) + golden-korpusz property gate + `docs/sdd/
  epic-07-completion-report.md`; `practiceGeneratorEnabled`/
  `plannerAssistEnabled` mindvégig `false` maradt, a rollout emberi döntés.
  Részletek a fejléc ✅-blokkjában és §5-ben. Az építkezés sorrendje —
  **E07-R01** (nyitókör:
  baseline, [ADR 0255](docs/adr/0255-deterministic-first-practice-planning.md)
  deterministic-first, [ADR 0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)
  immutable múlt, `practiceGeneratorEnabled` + `plannerAssistEnabled` feature
  flag), **E07-R02** (`domain/id/planner_ids.dart` — hat típusos ID —,
  `domain/model/plan_enums.dart` — öt stabil kódú enum-család —,
  [ADR 0257](docs/adr/0257-planner-typed-ids-and-stable-enum-codes.md)) és
  **E07-R03** (`domain/model/practice_goal.dart` — cél, metric target, goal
  lifecycle —, `domain/model/weekly_availability.dart` — `LocalDate`-alapú
  napi elérhetőség —, `domain/model/learner_constraints.dart` — hard/soft
  korlátok, a keménység a kategóriától független mező —,
  `domain/service/request_validator.dart` — pure konfliktus-detektor —,
  [ADR 0258](docs/adr/0258-hard-and-soft-planning-constraints.md)),
  **E07-R04** (`PracticeGenerationRequest` verziózás + draft persistence,
  [ADR 0259](docs/adr/0259-generation-request-versioning-and-draft-isolation.md)),
  **E07-R05** (`SkillEvidence` normalizálás — csak származtatott mérőszám,
  provenance és strukturált discomfort-kategória, a self-report szabad
  szövege a repository előtt eldobódik —, evidence repository outcome-ID
  dedup + inkluzív expiry + bounded query,
  [ADR 0260](docs/adr/0260-skill-evidence-privacy-and-deduplication.md)) és
  **E07-R06** (`domain/model/skill_estimate.dart` — explicit `unknown`
  állapot, sosem `0.0` default —, `domain/policy/evidence_weight_policy.dart`
  — explicit bounded-influence cap —, `application/service/
  skill_estimate_reducer.dart` — determinisztikus, konfliktus-tudatos
  reducer, a discomfort külön csatornán fut —,
  [ADR 0261](docs/adr/0261-skill-estimate-bounded-influence-and-unknown-state.md))
  kész, **E07-R07** (explicit, versioned Legacy Learn/Progress
  `SkillSnapshotReader` adapterek; ismeretlen/hiányos legacy adatból nincs
  inference vagy fabricated identity, [ADR 0293](docs/adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md))
  **E07-R08** (`ExerciseCandidate`/`PracticeCatalogSnapshot` — csak
  létező, végrehajtható forrásra mutató, revíziózott katalógus-jelöltek;
  `PracticeCatalogReader` port + két hívó-táplált adapter (Practice Engine,
  Legacy Learn fallback); a nem támogatott capability kimondott
  `unsupported`, sosem hiányzó mező, [ADR 0262](docs/adr/0262-catalog-snapshot-revisions-and-capability-truth.md)),
  **E07-R09** (`domain/model/exercise_prescription.dart` — bounded, immutable
  execution recept egy választott `ExerciseCandidate`-hez: explicit maximumos
  repetition, capability-hez kötött tempo/success criteria, azonos
  skill-target fallback, inkluzív hard elapsed-limit validáció,
  [ADR 0294](docs/adr/0294-exercise-prescription-measurability-and-bounded-execution.md))
  és **E07-R10** (`AdaptivePracticePlan`/`PracticeDay`/`PracticeBlock` —
  közös, pinnelt `PracticeItemStatus` átmenet-kontraktus,
  `PlanRevision` szigorúan monoton, TELJES immutable snapshot,
  `PlanChangeSet` strukturált diff typed indokkal, user-note-mentes
  `PracticePlanSummary` — az ADR 0256 megvalósítása).
  **Mindkét flag `false` marad minden környezetben**, nulla
  `lib/features/practice_generator/` production hívó — az R01–R10 kizárólag
  a határokat és a típusos domaint rögzítette (a köztes **E07-R11…R21**
  köröket, amik a validátort/repairert/wizardot/preview-t adták, ez a
  bekezdés még nem gördítette bele — lásd a fejléc bannereit és
  `docs/handoff-archive.md`-t). **E07-R22** hozzáadta az aktív terv napi/heti
  presentation-rétegét (`today_plan_controller.dart`/`active_plan_controller.dart`/
  `today_plan_screen.dart`/`weekly_plan_screen.dart`) — helyi dátum injektált
  órával, pihenőnap ≠ mulasztás, típusos deep-link contract, tanuló-indított
  change-setek storage-írás nélkül. SDD forrás:
  [`docs/sdd/08-epic-07-ai-practice-generator.md`](docs/sdd/08-epic-07-ai-practice-generator.md).
  A generátor a legacy Learn/Progress/Songs/Analyze adaptereken keresztül lát
  (az Audio Analysis V2 lánc futtatható, de minden flagje OFF — a generátor
  domainje **nem** igazodhat az ideiglenes adapterhez, SDD Ch8 §4.3).

## 2. What is working

- **SongDocument V2 identitás/metaadat (E03-R02, ADR 0089 §Döntés 2/3):**
  `lib/features/song_trainer/domain/models/` — hat típusos ID (`SongId`,
  `SongSectionId`, `SongTrackId`, `SongEventId`, `SongAssetId`,
  `SongMarkerId`) közös `SongIdValidator`-ral (trim/nem-üres/≤128
  karakter/determinisztikus `safeFilename`); `SongMetadata` (cím kötelező,
  capo 0–15, dedup+lowercase tag-lista, immutable); `SongSource`
  (proveniencia: 7 stabil forrás-típus, SHA-256, importer-verzió,
  warning-summary); `SongAssetReference`, `SongMarker`; a minimális
  `SongDocument` identitás-vázlat (`schemaVersion`/`id`/`revision`/
  `metadata`/`source`/`assets`/`markers`/`createdAt`/`updatedAt` —
  section/track/tempoMap E03-R03-ban bővíti). `data/local/
  song_document_codec.dart` — determinisztikus kulcssorrendű UTF-8 JSON,
  UTC ISO-8601 timestamp policy, ismeretlen source type fail-closed.
  Framework-/Riverpod-/storage-mentes (`Domain purity` teszt-scanner őrzi,
  reviewer-oldali valódi-sértés próbával verifikálva). Hívó UI/repository
  még nincs — production viselkedés változatlan.
- **Songstruktúra és determinisztikus időmodell (E03-R03, ADR 0093):**
  `lib/features/song_trainer/domain/models/` — `SongSection` (kind-enum,
  measure-range validáció), `SongMeasure` (index/durationBeats/pickup/
  repeat-mezők); `TempoMap`/`MeterMap`/`KeyMap` **lokális, tick-alapú**
  idő-primitívekkel (a Practice Engine `BeatPosition`/`Tempo`/`Meter`
  importja a domain-purity scanner és ADR 0092 miatt kizárva — csak a
  tervezési elvek öröklődnek, a típusok nem). `domain/services/
  song_time_map.dart` — 480 PPQ tick, szegmensenkénti egész-mikroszekundum
  összegzés egyetlen kerekítési ponttal, **≤1 tick round-trip tolerancia**
  (500 rendezett, seedelt property-mintán mérve), left-closed tempo/meter
  boundary policy (reviewer-oldali mutáció-tesztelt próbával verifikálva),
  speed-multiplier a forrás mapet nem mutálja. `SongDocument` (R02) bekötve
  az öt új mezővel, **value-equal** `operator==`/`hashCode`-dal minden
  strukturális mezőn (a review F1 MAJOR leletének javítása). Hívó UI/
  repository még nincs — production viselkedés változatlan.
- **Track/event domain modell és monophonic elemzés (E03-R04, ADR 0113):**
  `lib/features/song_trainer/domain/models/` — sealed `SongTrack`
  (`ChordTrack`/`StrumTrack`/`NoteTrack`/`LyricsTrack`/`MarkerTrack`/
  `BackingAudioTrack`) + sealed-szerű event-készlet (`SongChordEvent`
  core `Chord` szimbólummal, `SongStrumEvent` nullable core
  `StrumDirection?` iránnyal — `null` = unknown, `SongNoteEvent` MIDI
  pitch/string/fret/velocity validációval, `SongLyricEvent`,
  `SongMarkerEvent`); `SongInstrument` (opcionális core `Tuning` — az
  EGYETLEN canonical tuning contract); `SongNoteTechnique` (8 ismert
  technika + `unknown` raw/display escape hatch, sosem ad hamis scoring
  capabilityt). `domain/services/note_track_analyzer.dart` —
  `NoteTrackAnalyzer` **active-notes sweep-line**-nal (nem
  adjacent-pair-only — ez volt a review BLOCKER leletének gyökere, ld. §5)
  határozza meg az overlap/tie/monophonic reportot. Codec bővítés
  kanonikus (start asc → track id → event id) sorrenddel és fail-loud
  ismeretlen-altípus kezeléssel (`trackTypeUnknown`/`eventTypeUnknown`).
  `SongDocument.tracks` mező bekötve. Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Validator, normalizer és capability resolver (E03-R05, ADR 0114):**
  `lib/features/song_trainer/domain/services/` — `SongValidator`
  (cross-collection ellenőrzés: section range vs. `measures.length`,
  section-overlap, `StrumEvent.targetChordId` cél-hivatkozás — sorrend-
  független két lépéses gyűjtés+validálás, ld. §5 review-tanulság —,
  ismeretlen chord-root/technique/strum-direction, `NoteTrackAnalyzer`
  polyphony-reuse; sosem dob, mindig `SongValidationReport`-ot ad
  determinisztikus `severity asc, code asc` sorrenddel), `SongNormalizer`
  (idempotens: `normalize(normalize(x)) == normalize(x)`, kanonikus
  `(kind, id)`/`(start, id)` rendezés minden track/event típusra, ID-t
  soha nem ír át), `SongCapabilityResolver` (severity→capability
  szerződés: `fatal` ⇒ minden profil — importPreview/persist/trainer/
  export — `canPersist=false`; chord/pitch display/scoring ÖNÁLLÓ
  tengely a severity-től, a §6 négy kombináció mind reprezentálható).
  Chord-support grammar önálló, domain-lokális (`Root[m?]`), sosem a
  `practice`-feature szótára (ADR 0114 §Döntés 1 — cross-feature import
  + kívül esik az `allowed_paths`-on). Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Legacy Song/Setlist migrációs adapter (E03-R06, ADR 0116):**
  `lib/features/song_trainer/data/migration/` — `LegacySongReader` (JSON
  DTO boundary, `LegacySongRecord`/`LegacySetlistRecord`, kanonikus
  SHA-256, nincs presentation import), `LegacySongAdapter` (legacy
  `Song` record → `SongDocument`: `ChordTrack`+`StrumTrack`+egy
  `SongSectionKind.custom` „Full Song" section, egyetlen mikroszekundum-
  kerekítési pont eseményenként, `Meter` denominator mindig 4),
  `LegacySetlistAdapter` (sorrend/duplikáció megőrzés, missing id →
  unresolved report, nincs crash), `LegacyMigrationReport` (önálló,
  adapter-lokális fidelity report — NEM a `SongValidationReport`/
  `ImportWarning` kiterjesztése, ADR 0116 §Döntés 1). Veszteségmentes,
  determinisztikus, tartós írás vagy legacy törlés nélkül. Hívó
  UI/migration-runner még nincs — production viselkedés változatlan.
- **Fájlrendszeres Song repository és asset store (E03-R07, ADR 0090):**
  `lib/features/song_trainer/domain/repositories/` — `SongRepository`
  (`list`/`get`/`create`/`update`/`moveToTrash`/`restore`/
  `permanentlyDelete`, optimistic `expectedRevision`), `SongAssetRepository`
  (`put`/`get`/`summary`/`incrementReference`/`decrementReference`/
  `permanentlyDelete`). `data/local/` — `FileSongRepository` (validate→
  temp-serialize→flush→verify→atomic document rename→temp index→atomic
  index rename, `SongValidator`/`SongCapabilityResolver` a mentés előtt),
  `FileSongAssetRepository` (streamelt SHA-256 content-hash store,
  reference count, korrupt sidecar/asset stabil hibakóddal, sosem néma
  playback), `AtomicFileWriter` (temp/flush/verify/rename, staging a
  songs-root `temp/` alatt, előzetes törlés nélküli atomikus rename),
  `SongRepositoryRecovery` (nem-destruktív startup scan: orphan temp,
  orphan document, corrupt index, orphan asset), `InMemorySongRepository`
  (fake). `application/song_trainer_providers.dart` — éles Riverpod
  wiring `path_provider.getApplicationSupportDirectory()` felett
  (tranzitív import, ugyanaz a precedens, mint az E03-R06 `crypto`
  használata). Nincs `SongDocument`/asset SharedPreferences-ben. Három
  független review pass + két javító kör után **APPROVED**
  ([`docs/reviews/e03-r07-song-repository-asset-store-review.md`](docs/reviews/e03-r07-song-repository-asset-store-review.md)) —
  a második pass egy, a saját első javító kör bevezette regressziót
  talált (streamelt-hash `writeFromSync` length/end-index csere,
  `docs/LESSONS.md` L60), amit az orchestrátor javított (implementer-oldal
  mérve nem elérhető: M3 kerete + Terra napi kerete egyaránt kimerült).
  Hívó UI/import-runner még nincs — production viselkedés változatlan.
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
- **E06-R28 cache — 6 lezárandó előfeltétel a jövőbeli BEKÖTŐ körnek, nincs
  kijelölt kör (mérve, `docs/reviews/e06-r28-…-security.md` §6).** A cache-nek
  ma nulla production hívója van (`audioAnalysisV2Enabled` false), úgyhogy
  ezek NEM aktív hibák, csak a wiring-kör előtti kötelező hardening-lista:
  (1) explicit payload-tartalmi szerződés (nyers PCM sosem cache-elhető) +
  a cache-hely újraértékelése Android Auto Backup-jogosultság szempontjából
  (`getTemporaryDirectory()`/backup-kizárás `getApplicationSupportDirectory()`
  helyett); (2) `put()`/`getOrCompute()` ma kivételt propagál a hívóra
  filesystem-hibán (mérve `chmod 500`-zal) — az ADR Döntés 5 szellemével
  ellentétes; (3) a cache minden `*.json` fájlt sajátjának tekint a
  könyvtárában, mérve egy idegen `index.json` törlésével — fájlnév-mintaszűrő
  kell (`^[0-9a-f]{64}\.json$`); (4) `AudioFingerprint` némán clamp-el a
  `[-1,1]` tartományon kívül, ami két KÜLÖNBÖZŐ bemenetet azonos kulcsra
  képezhet — tartományon kívüli mintát el kell utasítani; (5) a mért
  baseline-számok (`docs/baseline/epic-06-analysis-performance.md`) 4 bájtos
  payloadról származnak, a cap közelében (50 MiB) a valós költség ~20×
  nagyobb (mérve: 609 ms + ~90 MiB tranziens allokáció egy `put()`-ra) —
  újramérés kell cap-közeli payloaddal, mielőtt bárki erre budget-döntést
  épít; (6) a `purge()` bekötése a törlési útvonalba (az R27
  `AnalysisCachePort`, `delete_analysis_use_case.dart:10-12`), hogy a
  `ss.analysis.cache` katalógus-bejegyzés valódi törölhetőséget takarjon.
  Content review 2 további MINOR-t is dokumentál (tautologikus
  fingerprint-névfüggetlenségi teszt; a handoff-próza tesztszám-elszámolási
  pontatlansága) — mindkettő dokumentációs, nem kódhiba.
- **E06-R20 follow-up (5 NOTE, review + security) — gate-feltételek egy
  jövőbeli bekötő körnek, nincs kijelölt kör.** (1) review N1: a
  `LowSignalQualityInsightRule` (`lib/features/audio_analysis/engine/insights/insight_rules.dart:268-297`)
  a `dynamics.clipped_event_ratio.v1`-et méri, nem a nyers
  `AnalysisDocument.signalQuality` (R07) riportot — mert az utóbbi nem
  katalogizált metrika, tehát nem használható `factId`-ként; ha egy
  jövőbeli kör a nyers jelminőséget is katalogizálja, érdemes megfontolni,
  hogy a szabály erre váltson-e. (2) review N2: a caller-supplied
  evidence-osztályok (`TimingInsightEvidence` stb.,
  `lib/features/audio_analysis/domain/insights/insight_rule.dart:164-234`)
  csak érték-tartományt validálnak, nem `CapabilityStatus`-t — a „csak
  megbízható mérésből" garancia a jövőbeli hívóra hárul, akinek ezt
  pre-flightban explicit ellenőriznie kell. (3) security NOTE-1 (**a
  bekötés ELŐTT megoldandó**, nem csak follow-up): a
  `ChordTransitionHotspotInsightRule` (`insight_rules.dart:259,261-263`)
  a `hotspot.id`-t verbátim messageArgba és egy action-payload kulcsba
  teszi; ma nincs élő harmony-kind hotspot-termelő, de egy jövőbeli
  decoder/import/sync útvonal szanitálatlan stringet hozhatna be. (4)
  security NOTE-2: a hotspot-alapú `factId`-eknek nincs `isUsable` őre
  (`insight_rules.dart:249`), a `CompatibleImprovementInsightRule`
  mintájára (`:313`) érdemes pótolni egy jövőbeli körben. (5) security
  NOTE-3/NOTE-4: a property-gate nem generál hotspotot (a
  `chord_transition_hotspot` útvonal kívül esik a randomizált mérésen), és
  a `HotspotRanker` duplikált ID esetén nem specifikált sorrendet ad (ma
  nincs élő duplikáció). Mérve:
  `docs/reviews/e06-r20-deterministic-insights-and-hotspots-review.md`
  N1/N2, `docs/reviews/e06-r20-deterministic-insights-and-hotspots-security.md`
  NOTE-1..4.
- **E06-R19 follow-up (F2 review + security NOTE-1) — gate-feltételek egy
  jövőbeli bekötő/kalibrációs körnek, nincs kijelölt kör.** (1) F2: a
  `CapabilityResolver.resolve()` (`lib/features/audio_analysis/engine/confidence/capability_resolver.dart:105-123`)
  a „kritikus capability → min" brief-elvet (§5.2) ma egy bináris hard-gate
  helyettesíti — bármelyik kritikus capability (`signalQuality`/
  `onsetTimeline`) `unavailable` állapota az overall confidence-t nullára
  kényszeríti (`overallStatus` mindig `unavailable`-re esik, sosem
  ténylegesen `degraded`-re), egy MERELY-`degraded` kritikus capability
  pedig csak egyetlen tényezőként hígul a geometriai átlagban a többi
  (akár 13) capabilityvel egyenlő súllyal. Nem sérti a §6 mérhető
  acceptance criteriont, de eltér a brief prózájától — egy jövőbeli
  bekötő/kalibrációs kör (R29 vagy a retrofit-kör) döntse el explicit
  módon, hogy a bináris kapu szándékos-e (ADR 0237 kiegészítéssel), vagy
  a fokozatos „min" viselkedés kell. (2) security NOTE-1: az
  `AnalysisDocument` codec (`lib/features/audio_analysis/data/analysis_document_codec.dart:180-195`,
  a diffen kívül, nem módosult) ma NEM perzisztálja az új
  `CapabilityReport.calibrationVersion`/`calibrationSource` mezőt — egy
  perzisztált-majd-visszatöltött report csendben `identity`-re esik vissza.
  Fail-safe irány (sosem a veszélyes raw→calibrated), de a source-enum
  megfigyelhetőségi célját kiüti perzisztált dokumentumoknál — E06-R29-nél
  a codec round-tripelje mindkét mezőt. Mérve:
  `docs/reviews/e06-r19-confidence-calibration-capability-resolver-review.md`
  F2, `docs/reviews/e06-r19-confidence-calibration-capability-resolver-security.md`
  NOTE-1.
- **E06-R17 security MINOR-1/NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli
  bekötő körnek, nincs kijelölt kör.** (1) MINOR-1:
  `buildPitchMetrics` (`lib/features/audio_analysis/engine/metrics/pitch_metrics.dart`)
  O(szegmens×célhang) — `_targetFor` szegmensenként az összes célhangot
  vizsgálja, `_dropoutRatio` célhangonként az összes szegmenst; mérve:
  8000 célhangra 619 ms, szuperlineáris görbe, ~15 s-ra extrapolál 40 000-re
  (ugyanaz a mérce, mint az E06-R11/E06-R15 precedens). MA elérhetetlen
  (0 fogyasztó, `analysisPitchEnabled=false` mindenhol) — egy jövőbeli
  untrusted/hosszú audióra kötő kör **MUST-fix-before** ezt egyetlen
  bejárásra/indexelésre kell váltania. (2) NOTE-1:
  `PitchCapabilityGate(minimumVoicedRatio: 0)` (nem a default 0.35) csupa
  unvoiced bemenettel `RangeError`-t dobna (`_median([])`) — a default
  biztonságos, csak a konstruktor nem zárja ki a `0` határértéket
  (`maximumPitchSpreadCents` mintájára `<= 0`-ra kellene szigorítani). (3)
  NOTE-2: az exportált `centsBetween` (`monophonic_pitch_segment_builder.dart`,
  `public.dart`-on át cross-feature elérhető) nem-pozitív Hz-re nem-véges
  eredményt adna — ma nincs ilyen belső hívó. Mérve:
  `docs/reviews/e06-r17-monophonic-pitch-capability-security.md`.
- **E06-R11 security NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli bekötő
  körnek, nincs kijelölt kör.** (1) `ChordSegmentAssembler._mergeShortSegments`
  (`lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart`)
  `removeAt`-alapú O(S²) — mérve: 13 mp @ 40 000 szegmens, `minimumSegment`/
  `mergeTransientSegments` opt-in policy alatt. MA elérhetetlen (a default
  policy `minimumSegment=0` kihagyja ezt az ágat, és a feature bekötetlen) —
  de ha egy jövőbeli kör untrusted/hosszú importált audióra köti be pozitív
  merge-policyval, a security review explicit **MAJOR-ra sorolja át**: a
  merge-t egyetlen bejáráson épített új listával kell megvalósítani,
  `removeAt` nélkül, MIELŐTT a bekötés megtörténik. (2) `ChordSegment.id`
  (`lib/features/audio_analysis/domain/analysis_segment.dart`,
  `_defaultId`) a `label`-t szanitálás nélkül interpolálja
  (`'chord-${startUs}-${endUs}-$label'`) — ha egy jövőbeli hívó ezt fájlnévként/
  DB-kulcsként/log-sorként használja, és egy jövőbeli ML-decoder tetszőleges
  stringet ad `label`-ként, path-traversal- vagy injekció-alakú kulcs
  keletkezhet. Javítás a bekötés ELŐTT: a `label`-komponenst szanitálni/
  hash-elni az ID-ben, vagy dokumentálni, hogy az `id` nem biztonságos útként/
  kulcsként. Mérve: `docs/reviews/e06-r11-chord-evidence-segmentation-provenance-security.md`
  NOTE-1/NOTE-2.
- **E06-R06 F2/S3/S4 follow-up — NYITVA, nincs kijelölt kör.** A live
  level-preview (`RecordingLevel`, E06-R06) csak az éppen throttle-ablakot
  lezáró chunkot méri peak/RMS-re, a köztes chunkokét nem — egy rövid,
  hangos tranziens, ami teljesen egy köztes chunkba esik, nem jelenik meg a
  preview-n (a végleges, teljes PCM-puffer nem érintett). Az E06-R07
  pre-flightja értékelte és kimondta, hogy ez NEM az ő scope-ja (az offline,
  egyszer futó jelminőség-stage más költségszinten dolgozik, mint a valós
  idejű preview) — a follow-up így nyitva marad, jelenleg nincs hozzá
  kijelölt kör.
- **E06-R07 review NOTE-2 — R02 domain-report NaN-vak arány-guard, alacsony
  prioritás.** A meglévő (E06-R02, E06-R07 által NEM módosított)
  `SignalQualityReport` konstruktora (`lib/features/audio_analysis/domain/
  signal_quality_report.dart`) a `clippedSampleRatio`/`silentRatio` mezőkre
  csak `< 0 || > 1` ellenőrzést fut, `isFinite`-et nem — mivel `NaN < 0` és
  `NaN > 1` egyaránt hamis, egy `NaN` arány elméletileg megkerülné az őrt (a
  mai producerek sosem termelnek ilyet). Mérve és dokumentálva:
  `docs/reviews/e06-r07-signal-quality-stage-security.md` NOTE-2. Javítás
  amikor legközelebb valaki ezt a konstruktort érinti: vegye fel a két
  arányt is az `isFinite` ellenőrzésbe.
- **~~A Claude 5 órás session-kerete rendszeresen kimerül és H-NOSIGNAL-lal
  körökbe kerül~~ — MEGOLDVA (ADR 0222, 2026-08-11, user-döntés).** Mért ok: a
  lánc MINDEN körben a Claude-ot ültette az orchestrátor+reviewer székbe
  (~85 perc/kör, `--effort max`, szünet nélkül) → egy 5 órás ablakba ~3,5 kör
  fér. A védőháló (ADR 0115) ráadásul vak volt: a limit-minta egyetlen valós
  CLI-bannerre sem illeszkedett (11 mérés 90→97%-ig az E06-R05 naplójában), a
  második detektor pedig nem létező fájlra mutatott. **Ma:** a körök felét a
  Terra vezényli (`PIPELINE_ORCH_ROTATION=alternate`), ilyenkor a Claude
  implementál (`sonnet-impl`) — a szerepek cserélnek, a mezőny nem gyengül. A
  fogyásmérő a banner százalékát olvassa, és 85% fölött nem indít új kört a
  Claude-dal (futó munkát soha nem szakít meg). Állapot:
  `tools/pipeline-status.sh`. Tanulság: `docs/LESSONS.md` L215.
- ~~**Rendszerszintű rés (E02-R20, mérve): a standalone Practice V2 session nem
  indítható éles buildben.**~~ **JAVÍTVA (E02-R21, PR #55, `6e5cec7`).** A
  `practiceSessionHostProvider`/`practicePrepareSinkProvider` production
  drótozása (A1-A5, ADR 0111) elkészült és merge-elve — a Hub→Setup→Session
  presentation→controller kötés él. Részletek:
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3/§5 (a §3 leírás a régi állapotot rögzíti, evidenciaként megmarad).
- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Epic-2 valódi eszközös teszt PENDING** — a Practice Engine device-mátrix
  ([`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md))
  kész, a user tölti ki — a standalone Practice V2 út (E02-R21 óta) és a
  Learn-migrációs út egyaránt elérhető éles buildben.
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.
- **~~A `lib/` 43%-a elérhetetlen~~ — TOVÁBB FELOLDVA (GOV-05a+GOV-05c,
  2026-08-09).** Eredeti mérés (2026-08-07): `song_trainer` V2 (25 308 sor),
  `ai_tutor` (14 091), `vision` (5 132) mind hard-kódolt `false` mögött; a
  Learn a legacy motoron futott minden környezetben.
  **Ma:** a `song_trainer` V2 és a `migratedLearnEnabled` is
  `development`/`lab`-ban ON (a Practice V2 szintén — a flagje eddig is ON
  volt, csak belépési pont nem vezetett hozzá); a Learn a Practice Engine
  V2-n fut `production`-ön kívül. **Hátra van:**
  - `ai_tutor` (14 091 sor) — flagje `false` mindenhol, **BLOKKOLT**: hiányzó
    production-drótozás ÉS hiányzó modell-átjáró, emberi döntést igényel →
    **GOV-05b**, lásd alább;
  - `vision` (5 132 sor) — flagje `false`, és **BLOKKOLT**: nem
    flag-kérdés, hanem hiányzó modell-bináris → **GOV-05d**, lásd a
    következő pontot.
  A termék központi állítására eddig egyetlen mért valós-audio szám létezett
  (CRNN pengetés-irány 86,7% vs heurisztika 38,9%, r164 A/B) — akkord-
  pontosságra, onsetre és BPM-re valós felvételen nem volt szám.
  **JAVÍTVA (GOV-06, E99-R04, 2026-08-09):** a szállított, változatlan
  `ClipAnalyzer` mérve 82 valódi telefonos felvételen — akkord-pontosság
  **67,069%** (18,832%-os többségi-osztály baseline fölött), onset F1@50ms
  **67,391%**. Teljes riport:
  [`docs/eval/real-audio-dsp-baseline.md`](docs/eval/real-audio-dsp-baseline.md).
  A korpusz nincs verziókövetve (external, csak ezen a boxon), a mérés ezért
  elkötelezett riport, nem CI-kapu — a verziókövetés nevesített follow-up.
  **A GOV-06 harmadik száma (BPM-MAE 45,067) ÉRVÉNYTELEN volt — VISSZAVONVA
  ÉS JAVÍTVA (GOV-06b, E99-R05, 2026-08-09, ADR 0212, PR #208):** a szám nem
  DSP-tempóhibát mért, hanem a `.strums` pengetés-eseményekből (nem
  ütem-annotációkból) származtatott „ground truth" ellen — két pengetés-
  sűrűség-becslés egyezetlensége volt, nem tempóé. Független
  librosa-beat-tracker referenciával újramérve: szigorú tempó-egyezés
  **11/82 = 13,415%**, metrikai-szint toleráns egyezés (1/3·1/2·2/3·1·3/2·2·3
  szorzók) **32/82 = 39,024%**; a régi szám megőrizve `visszavonva`
  jelöléssel, pengetés-sűrűségként átcímkézve. **A BPM ezen a korpuszon nem
  mérhető, mert nincs validált (kézi) tempó-annotáció** — ez kimondott,
  elfogadott kimenet, nem hiba. Új eszköz: `ml/chords/tempo_reference.py`.
  Az akkord-pontosság és onset F1 (fent) újramérve bitre változatlan.
  **User-döntés (2026-08-07):** az Epic 6 NEM indul, amíg ez nincs meg — a
  §6 „Kötelező sorrend" 3. ÉS 4. pontja is lezárult. **Az 5. pont (Epic 6
  feloldása) is megtörtént** (user-döntés 2026-08-11, „mehet tovább az
  epic 6") — E06-R01 (Kör 1) kész, lásd a fejléc ✅-blokk és §6.
- **Az AI Tutor rollout — a drótozási blokkoló ÉS a backend-adapter FELOLDVA,
  a bekötés és az üzemeltetés hiányzik (frissítve 2026-08-09, GOV-05b-2 /
  E99-R07 merge után).**
  1. ~~Három provider `throw UnimplementedError`-ral indul~~ — ✅ **MEGOLDVA**
     az **E99-R06** (GOV-05b-1, PR #209, `23fdf30a`, ADR 0213) körrel: a
     `tutorOrchestratorProvider`, a `tutorConversationRepositoryProvider` és a
     `tutorMemoryRepositoryProvider` a `lib/main.dart`
     `buildTutorProductionOverrides` függvényén át kap éles implementációt
     (`LocalTutorConversationRepository`, `LocalTutorMemoryRepository`,
     `TutorOrchestrator`). Az avult `tutorMain()` doc-comment-ígéret törölve
     (`grep -rn "tutorMain" lib/` → 0). **Az `aiTutorEnabled` bekapcsolása
     többé nem crash.**
  2. ~~Nincs konkrét `TutorStreamTransport`~~ — ✅ **MEGOLDVA** ugyanabban a
     körben: `HttpTutorStreamTransport` (Dio `ResponseType.stream` a
     `POST /tutor/stream` SSE végpontra, nyers `data:` payloadokat ad tovább;
     a parse és a `seq`-sorrendezés a `RemoteTutorModelGateway` dolga).
     A kliens–backend szerződést a review kézzel összevetette a
     `TutorStreamRequest` `extra="forbid"` sémájával — illeszkedik.
  3. ~~MÉG HIÁNYZIK — a valódi modell-átjáró~~ — ✅ **MEGOLDVA** (**E99-R07**,
     GOV-05b-2, PR [#210](https://github.com/wolfcasaba/strumsight/pull/210),
     squash `f1d57c69`, **ADR 0214**, implementer **Codex (Terra)** 1
     forduló, javító kör nélkül): `OpenAiProviderGateway`
     (`backend/app/tutor/provider_gateway.py`) nyers `httpx`-szel
     implementálja a `ProviderGateway` szerződést — mind a hét hibaágra
     (timeout, 4xx/5xx, kapcsolati hiba, nem-JSON, hiányzó/nem-string
     `content`) normalizált, szivárgásmentes kivétellel (13 új teszt,
     `httpx.MockTransport`, nulla valós hálózat). Review **APPROVED, 0
     BLOCKER/MAJOR/MINOR, 2 NOTE** (reviewer SAJÁT izolált klónban
     újrafuttatott 9/9 zöld gate-tel ÉS a §6.1 valódi-sértés próba KÉTSZERI
     független megismétlésével — a brief mutációja + egy saját
     kulcs-szivárgásra célzó mutáció, mindkettő a várt cellát buktatta meg).
     Dedikált security-review (risk=high) **PASS, 0
     CRITICAL/BLOCKER/MAJOR/MINOR, 4 NOTE** (mind a bekötő körre szóló
     előre-mutató follow-up: `exc.__context__` defense-in-depth,
     `tutor_openai_base_url` validáció, `AsyncClient` lifecycle, válasz-méret
     korlát) — a security-reviewer a kör saját `str(exc)` tesztjén túlmenve a
     teljes traceback + valós `logging.exception()` szintjén is megmérte mind
     a 7 hibaágat szándékosan beültetett titokkal, 7/7 tiszta. **A
     `FakeProviderGateway` érintetlen** (a diffje üres), **a `main.py`
     bekötése ebben a körben TUDATOSAN NEM történt meg** (ADR 0214 Döntés
     2/OD-04): `tutor_provider` marad `"fake"`, `tutor_enabled` marad
     `False`. Zöld kapu exact-SHA `19002611`: Full Gate + Router CI +
     Backend CI mindhárom **success**. Melléktermék: a pre-flight mért egy
     pre-létező, byte-azonos duplikátumot a `config.py` `tutor_*`
     blokkjában (E04-R14 eredetű, `c1c0a771`) — összevonva, viselkedés
     változatlan.
  4. **MÉG HIÁNYZIK — a bekötés.** A backend `main.py`-ban a registry/gateway
     kiválasztás (ma kizárólag `FakeProviderGateway`-t épít, `main.py:147–184`)
     bekötése az OpenAI-adapterre. Külön kör — a briefje **szándékosan még
     nincs megírva**, a pre-flightjának az E99-R07 utáni állapotot kell
     mérnie.
  5. **MÉG HIÁNYZIK — üzemeltetés.** Hosztolt backend + OpenAI API-kulcs; ez
     **user-feladat**. A `/tutor/stream` **JWT-t vár** (`CurrentUser`), tehát a
     `RemoteTutorModelGateway`-t élesítő körnek **authentikált `Dio`-t** kell
     átadnia a transportnak (E99-R06 review NOTE-1).
  **A flagek változatlanul `false` minden környezetben** — az `aiTutorEnabled`
  bekapcsolása a 4. és 5. pont után, külön körben.
- **A vision rollout BLOKKOLT — hiányzó modell-binárisok (mérve 2026-08-09,
  GOV-05a pre-flight; ez NEM flag-kérdés):** az
  `assets/ml/model_manifest.json` `vision_models` mindkét bejegyzése
  (`hand_landmarker` 1.0.0, `pose_landmarker` 1.0.0) `status: "deferred"`,
  `sha256` csupa nulla, és a hivatkozott
  `hand_landmarker_deferred.tflite` / `pose_landmarker_deferred.tflite`
  fájlok **nincsenek a repóban** (`ls assets/ml/` → négy audio `.bin` + a
  manifest). A `NativeHandLandmarkProvider:77` és a
  `NativePoseLandmarkProvider:76` `deferred` bejegyzésre `AppResult.failure`-t
  ad. Következmény: a `visionEnabled` bekapcsolása MA egy zsákutcába futó
  setup-folyamatot tenne láthatóvá — az Epic 5 mind a 30 köre kész, de
  készüléken egyetlen vision-képesség sem tud futni. **Előfeltétel a
  rollouthoz:** a modell-binárisok beszerzése, licenc- és checksum-átvezetés
  a manifestbe (a `test/tooling/vision_model_integrity_test.dart` valódi
  SHA-256-ellenőrzése csak `active` bejegyzésnél fut) → külön **GOV-05d** kör,
  a döntés emberi.
- **`vision/public.dart` wide-barrel szimbólum-rés — a KONKRÉT R26-eset
  zárva, az ÁLTALÁNOS enforcement-rés nyitva (mérve E05-R25 security-review
  MINOR-1 + E05-R26, nem blokkoló):** a wide barrel máig aggregát
  (privacy-safe) ÉS nyers landmark/pose/geometry/koordináta-típusokat +
  landmark-provider osztályokat is exportál, szimbólum-szintű korlát
  nélkül. **E05-R26 lezárta a SAJÁT belépési pontját**: a Song Trainer új
  fájljai egy ÚJ, szűk, domain-safe nested barrelen
  (`lib/features/vision/domain/integration/public.dart`, ADR 0193 Döntés
  4–7) keresztül érik el a vision-t, ami mechanikusan (könyvtár-prefix
  tiltólistával) kizárja a nyers típusokat — ezt gépi őr védi
  (`vision_integration_barrel_boundary_test.dart`). **Nyitva marad:** (1) a
  wide barrel maga változatlan, a Practice (E05-R25) meglévő importja is
  azt célozza még (migrálásuk külön, jövőbeli kör, nem sürgős — a
  security-review szerint ma sem áthágás); (2) a szűk barrel ÖNMAGA is
  csak a saját KÖZVETLEN export-sorait ellenőrzi, a TRANZITÍV
  mező-típus-gráfot nem — E05-R26 review F1/NOTE-1 mérte, hogy a
  `posture_metrics.dart` (domain-safe, exportált) egy mezőjén
  (`PostureMetricDefinition.requiredPoseLandmarkIds`) át egy tiltott enum
  ÉRTÉKEI olvashatók voltak (javítva R26 saját javító körében egy `show`
  kombinátorral, de a MINTA — egy re-exportált „biztonságos" fájl saját
  mezője hordozhat tiltott típust — általánosan nyitva marad). Egy
  dedikált architektúra-kör (tranzitív gráf-ellenőrzés a checkerben, vagy a
  wide barrel teljes migrálása) follow-up marad. Részletek:
  [`docs/reviews/e05-r26-song-trainer-vision-integration-review.md`](docs/reviews/e05-r26-song-trainer-vision-integration-review.md)
  F1, [`docs/reviews/e05-r26-song-trainer-vision-integration-security.md`](docs/reviews/e05-r26-song-trainer-vision-integration-security.md)
  NOTE-1, [`docs/adr/0193-song-trainer-vision-integration-contract.md`](docs/adr/0193-song-trainer-vision-integration-contract.md),
  [`docs/LESSONS.md`](docs/LESSONS.md) L190, L193.
- **A valódi, több-stage V2 DSP pipeline összeszerelése MÉG NEM ÜTEMEZETT
  kör.** Mérve E06-R22 pre-flightjában (2026-08-12): nulla konkrét,
  egymással összefűzhető `AnalysisStage<T, T>` lánc létezik a `lib/`-ben — a
  három meglévő konkrét stage (`SignalQualityStage`, `PreprocessingStage`,
  `ClipAnalyzerStage`) egymással össze nem fűzhető I/O-jú. [ADR
  0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md) a runner
  réteget (E06-R22) tudatosan pipeline-agnosztikusra rögzítette
  (`T = AnalysisDocument`, `analysisV2RunnerProvider` fail-closed
  `StateError`-ral) — egy jövőbeli kör tervezze meg a közös munka-kontextust
  és szerelje össze a valódi láncot; ez ma NEM blokkolja a V2 utat (a flag
  változatlanul `false`), de a `analysisV2RunnerProvider` felülírás nélkül a
  V2 Analyze képernyő sosem tudna valódi eredményt produkálni.
- **E06-R21 a saját kötelező, dedikált biztonsági review-ja nélkül
  merge-elt** (a brief `risk = "high"`-at jelölt, §11 kifejezetten kérte —
  mérve E06-R22 zárásakor: minden más E06 kör R02-től párosan rendelkezik
  `-review.md` + `-security.md` jelentéssel, R21-nek csak az előbbije volt).
  Az E06-R22 orchesztrátora egy UTÓLAGOS, retroaktív security review-t
  dispatch-elt a már merge-elt kódra (read-only audit, nem blokkol
  semmilyen már megtörtént merge-et) — az eredményt lásd:
  [`docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md`](docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md),
  ha időközben elkészült, vagy jelezze egy jövőbeli session, ha még hiányzik.

## 4. Current branch

**Aktuális állapot (2026-08-23):** `main` @ `5e086c10` — E09-R08 Block, mute
és safety kapcsolatkezelés, PR
[#417](https://github.com/wolfcasaba/strumsight/pull/417), squash-merge.
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5, EGY javító
kör (F1 MAJOR hiányzó l10n a safety screen-en, F2 MAJOR el nem kapott
konkurrens `IntegrityError` `block()`/`mute()`-ban + a saját concurrency-
tesztje néma kivétel-nyelése — mind a review 1. fordulójában) + egy
CI-only fix (`ui_inventory_test.dart` screen-számláló 67→68, ugyanaz a
drift-osztály, mint az E09-R07 3. javító köre). Dedikált security-reviewer
pass: PASS. Review APPROVED, 0 nyitott BLOCKER/MAJOR. Exact `63890947`:
`full-gate.yml` 32608627590 + `router-ci.yml` 32608635566 mindkettő
success. Részletesen a fejléc ✅-blokkban.

**Aktuális állapot (2026-08-22):** `main` @ `1cc49e41` — E09-R07 Follow és
follow request social graph, PR
[#416](https://github.com/wolfcasaba/strumsight/pull/416), squash-merge.
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5, KÉT javító
kör (F1 BLOCKER nem-determinisztikus valódi-sértés próba, F2/F3 MAJOR
hitelesítetlen GET-endpoint + törött DELETE idempotency-key kontraktus, F4
MINOR elkapatlan kivétel — mind a review 1. fordulójában; egy 3. javító kör
a CI-only `ui_inventory_test.dart` screen-számláló driftjét zárta). Review
APPROVED, 0 nyitott BLOCKER/MAJOR. Exact `f75f0007`: `full-gate.yml`
32603023648 + `router-ci.yml` 32603026921 mindkettő success. Részletesen a
fejléc ✅-blokkban.

**Aktuális állapot (2026-08-22):** `main` @ `77bc0589` — E09-R06 Profil
létrehozás, szerkesztés és Community gate UI, PR
[#415](https://github.com/wolfcasaba/strumsight/pull/415), squash-merge.
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5, KÉT javító
kör (F1 BLOCKER hiányzó `GET /community/profiles/me`, F2 MAJOR NFKC-
normalizáció eldobva, F9/F10 MAJOR a TELJES CI-suite fedte fel). Review
APPROVED, 0 nyitott BLOCKER/MAJOR. Exact `bf2f67da`: `full-gate.yml`
32596780267 + `router-ci.yml` 32597616787 (manuális `workflow_dispatch`)
mindkettő success. Részletesen a fejléc ✅-blokkban.

**Aktuális állapot (2026-08-22):** `main` @ `79865233` — E09-R05 Flutter
Community domain és public API, PR
[#414](https://github.com/wolfcasaba/strumsight/pull/414), squash-merge.
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5, egy javító
kör (F1 MAJOR — `ModerationState` hiányzó A3 wire-decodere, `d52a10c5`).
Review APPROVED, 0 nyitott BLOCKER/MAJOR, 1 NOTE (a `mm-round.sh`
`gate_shape` regex-őr hamis pozitívja, nem blokkoló). Exact `25ac7f75`:
`full-gate.yml` 32590914358 + `router-ci.yml` 32591010189 (manuális
`workflow_dispatch`, mert a review-only commit nem érintette a Router CI
trigger-útvonalait) mindkettő success. Merge `tools/round-land.sh`-sal.
Részletesen a fejléc ✅-blokkban.

**Aktuális állapot (2026-08-22):** `main` @ `a8ecb9f3` — E08-R30 Epic 08
migráció, regresszió és lezárás, PR
[#407](https://github.com/wolfcasaba/strumsight/pull/407), squash-merge.
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5, javító kör
nélkül (review APPROVED, 0 BLOCKER/MAJOR/MINOR, 2 NOTE). **EPIC 8 LEZÁRVA.**
Exact `3a6f10b3`: Full Gate 32569011383 + Router CI 32569012517 success;
`origin/main` a dispatch és a merge között nem mozdult. Részletesen a fejléc
✅-blokkban.

**Aktuális állapot (2026-08-22):** `main` @ `571981b7` — E08-R28 Ledger
sync contract és merge, PR
[#406](https://github.com/wolfcasaba/strumsight/pull/406), squash-merge.
Implementer MiniMax M3, orchestrátor/reviewer Claude Sonnet 5. Egy javító
kör (F1 MAJOR — a Dart `gamification_sync_contract.dart` kódoló és a
backend `schemas.py` dekóder nem ugyanazt a wire-alakot beszélte, saját
kézzel a Dart kimenetet a pydantic modellen keresztülfuttatva mérve; F2
MINOR — hiányzó `max_length` korlát, látens DoS; mindkettő javítva,
review: `docs/reviews/e08-r28-review.md` APPROVED +
`docs/reviews/e08-r28-security.md` PASS). A kör alatt a `main` egyszer
mozdult (E09 round-brief batch, PR #405, diszjunkt fájlkör) — `merge --no-ff`
+ teljes CI-újradispatch a kombinált HEAD-en. Exact `dda4534b`: Full Gate
32565070603 + Router CI 32565071642 success; post-merge célzott gate a
friss `main`-en önállóan is zöld (Dart 6/6 + backend pytest 15/15). ADR
0394 (a brief előre kiosztott `0319`-e stale volt). Következő: **E08-R30**
(Epic 08 migráció, regresszió és lezárás) — az **E08-R29** (Integritás,
analytics, balance) `hold`-on marad; a queue-scan a legelső `pending` sort
választja, ami a fájlban E08-R30, korábbi mint a most batch-elt E09-R01.

**Aktuális állapot (2026-08-22):** `main` @ `db6293f4` — E08-R27
Gamification accessibility és settings, PR
[#404](https://github.com/wolfcasaba/strumsight/pull/404), squash-merge.
Implementer MiniMax M3, orchestrátor/reviewer Claude Sonnet 5. Egy javító kör
(F1 MAJOR — a domain `gamification_preferences.dart` tranzitívan a
Fluttertől függött egy `presentation/widgets/reward_summary_sheet.dart`
importon át, AGENTS.md §6 sértés, a `tool/check_architecture.dart`
allowlist-je nem fedte le a `gamification/domain/`-t; javítva: a leképezés a
provider — presentation — rétegbe költözött, review-jelentés:
`docs/reviews/e08-r27-review.md`, 2 NOTE + 1 MINOR follow-up nyitva). Exact
`a20182a6`: Full Gate 32560163642 + Router CI 32560901860 (kézi
`workflow_dispatch`, mert az utolsó commit csak a review-jelentést érintette,
nem `docs/rounds/**`-t) success; post-merge célzott gate a friss `main`-en is
zöld. ADR 0393 (a brief előre kiosztott `0318`-a stale volt, egy korábbi,
független kör már foglalta). Következő: **E08-R28** (Ledger sync contract és
merge).

**Aktuális állapot (2026-08-22):** `main` @ `ea2e22a4` — E08-R26
Cross-feature gamification integráció, PR
[#403](https://github.com/wolfcasaba/strumsight/pull/403), squash-merge.
Implementer MiniMax M3, orchestrátor/reviewer Claude Sonnet 5. Nincs javító
kör (0 BLOCKER/MAJOR/MINOR, 3 NOTE, review-jelentés:
`docs/reviews/e08-r26-review.md`). Exact `d3c4a9a0`: Full Gate 32557142579 +
Router CI 32557160705 success; post-merge célzott gate a friss `main`-en is
zöld. ADR 0392. Következő: **E08-R27** (Gamification accessibility és
settings).

**Aktuális állapot (2026-08-22):** `main` @ `dc09f5fe` — E08-R24 Practice
Engine és Learn integráció, PR
[#401](https://github.com/wolfcasaba/strumsight/pull/401), squash-merge.
Implementer MiniMax M3, reviewer Claude Sonnet 5. Egy javító kör (F1 lecke-
adapter eventId BLOCKER + F2 teszthiány BLOCKER, review-jelentés:
`docs/reviews/e08-r24-review.md`). Exact `33733eb6`: Full Gate 32551495513 +
Router CI 32551519892 success; post-merge célzott gate a friss `main`-en is
zöld. ADR 0390. Következő: **E08-R25** (Song Trainer és Setlist
integráció).

**Aktuális állapot (2026-08-21):** `main` @ `29c27ab2` — E08-R18 rugalmas
heti quest és consistency objective, PR
[#394](https://github.com/wolfcasaba/strumsight/pull/394), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`c131c47e`: Full Gate 32472133400 + Router CI 32472092472 success;
correctness APPROVED, security PASS. Következő E08 kör: **E08-R19**.

**Aktuális állapot (2026-08-21):** `main` @ `6e80a441` — E13-R03 semantic
színek és három theme, PR
[#386](https://github.com/wolfcasaba/strumsight/pull/386), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`3fc36778`: Full Gate 32451933445 + Router CI 32451919508 success;
correctness APPROVED, security PASS. Következő Chapter 13 kör: **E13-R04**.

**Aktuális állapot (2026-08-21):** `main` @ `22f5e1a0` — E08-R15
privacy-safe Achievement UI, PR
[#383](https://github.com/wolfcasaba/strumsight/pull/383), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`d4414f49`: Full Gate 32449877483 + Router CI 32449853724 success;
correctness APPROVED, security PASS. Következő E08 kör: **E08-R16**.

**Aktuális állapot (2026-08-21):** `main` @ `8bd7dc98` — E13-R02 Design
System Foundation és compatibility layer, PR
[#384](https://github.com/wolfcasaba/strumsight/pull/384), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`05ec6276`: Full Gate 32447387921 + Router CI 32447381563 success;
correctness APPROVED, security PASS. Következő Chapter 13 kör: **E13-R03**.

**Aktuális állapot (2026-08-21):** `main` @ `f9d5bbc8` — E08-R13 Achievement
domain és katalógus, PR [#376](https://github.com/wolfcasaba/strumsight/pull/376),
squash-merge. Implementer Terra (`gpt-5.6-terra`), reviewer Sol
(`gpt-5.6-sol`). Exact `679f030f`: Full Gate 32433372231 + Router CI
32433323271 success; correctness APPROVED, security PASS. Következő
termékkör: **E08-R14**; E13-R01 a másik sloton fut.

**Aktuális állapot (2026-08-20):** `main` @ `6a8d0b72` — E08-R11 Qualified
day, planned rest és recovery policy, PR
[#363](https://github.com/wolfcasaba/strumsight/pull/363), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`0674de52`: Full Gate 32379760277 + Router CI 32379709904 success;
correctness és security review APPROVED. Következő: **E08-R12**.

**Aktuális állapot (2026-08-20):** `main` @ `5ad15b5f` — E99-R20 GOV-14
kombinált-HEAD kör-landoló, PR [#361](https://github.com/wolfcasaba/strumsight/pull/361),
squash-merge. Implementer Terra (`gpt-5.6-terra`), reviewer Sol
(`gpt-5.6-sol`). Exact `a73493f4`: Full Gate 32373805059 + Router CI
32373785655 success; correctness és security review APPROVED. Következő:
**E08-R11**. Post-merge round-gate: 6/6 zöld.

**Aktuális állapot (2026-08-20):** `main` @ `842231f5` — E08-R09 Legacy
progress adapter és activity backfill, PR
[#359](https://github.com/wolfcasaba/strumsight/pull/359), squash-merge.
Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Exact
`e25d3158`: Full Gate 32365896298 + Router CI 32365922753 success; correctness
és security review APPROVED. Következő: **E08-R10** (Streak V2 domain és
legacy migráció).

**Aktuális állapot (2026-08-20):** `main` @ `ebb03d9d` — E08-R08 Gamification
repository és tároló-séma, PR [#355](https://github.com/wolfcasaba/strumsight/pull/355),
squash-merge, implementer Codex (`~/.codex`, gpt-5.6-terra) + 1 javító kör
(F1 MAJOR, review-jelentés: `docs/reviews/e08-r08-review.md`). A kör alatt a
`main` háromszor mozdult (E99-R19 lezárása, PR #353, E99-R20 induló munkája)
— mindháromszor `merge --no-ff` + teljes CI-újradispatch a §0.3 szerint.
Exact `91821f22`: Full Gate 32349845398 + Router CI 32349841249 success;
post-merge célzott gate a friss `main`-en önállóan is zöld (7/7). Következő:
**E08-R09** (Legacy progress adapter és backfill).

**Aktuális állapot (2026-08-20):** `main` @ `4dc8f7d1` — E99-R19 GOV-13
lánc-higiénia, PR [#354](https://github.com/wolfcasaba/strumsight/pull/354),
squash-merge. Implementer MiniMax; correctness review APPROVED, security
review PASS. Exact `c17ed660`: Full Gate 32347005385 + Router CI 32347032703
success; post-merge gate zöld. Az E08-R08 külön, izolált körben már fut.

**Aktuális állapot (2026-08-20):** `main` @ `010989f3` — E08-R07 Szintgörbe
és profil-projekció, PR [#349](https://github.com/wolfcasaba/strumsight/pull/349),
squash-merge, implementer Codex (`~/.codex-terra`, gpt-5.6-terra) + 1 javító
kör (F1 BLOCKER + F2/F3 MAJOR, review-jelentés: `docs/reviews/e08-r07-review.md`).
A kör alatt a `main` egyszer mozdult (E99-R18/H3 self-heal negyedik
önjavítása, PR #348, diszjunkt fájlkör) — rebase + teljes CI-újradispatch a
§0.3 szerint. Exact `6ba6ca89`: Full Gate 32337856382 + Router CI 32337858078
success; post-merge célzott gate a friss `main`-en önállóan is zöld (6/6).
Következő: **E08-R08** (Gamification repository és storage schema).

**Aktuális állapot (2026-08-19):** `main` @ `39c0bd5f` — E08-R03 Reward
ledger és idempotencia-index, PR [#340](https://github.com/wolfcasaba/strumsight/pull/340),
squash-merge. Exact `02477969` (a kör alatt a `main` háromszor mozdult, mindig
`merge --no-ff` + teljes CI-újradispatch a §0.3 szerint): Full Gate
32313777603 + Router CI 32313779449 success; post-merge célzott gate a friss
`main`-en önállóan is zöld (7/7). Következő: **E08-R04** (Activity outbox és
megbízható feldolgozás).

**Aktuális állapot (2026-08-19):** `main` @ `ee5821dd` — E07-R30 Evaluation
harness, shadow rollout és Epic 7 lezárás, PR
[#333](https://github.com/wolfcasaba/strumsight/pull/333), squash-merge.
Exact `d40e2050`: Full Gate 32289312900 + Router CI 32289316122 success;
post-merge célzott gate a friss `main`-en önállóan is zöld. **Epic 7 kész** —
a lánc E08-R01-gyel (Gamification baseline, SDD Chapter 9) folytatódik.

**Aktuális állapot (2026-08-19):** `main` @ `b021eff2` — E07-R28
PlannerAssistGateway integráció, PR [#329](https://github.com/wolfcasaba/strumsight/pull/329),
squash-merge. Exact `dc413fd8`: Full Gate 32266022078 + Router CI 32266095192
success; post-merge célzott gate a friss `main`-en zöld.

**Aktuális állapot (2026-08-19):** `main` @ `a0c61044` — E07-R27 missed-day/
pause/returning flow, PR [#328](https://github.com/wolfcasaba/strumsight/pull/328),
squash-merge. Exact `10ed4874`: Full Gate 32259717044 + Router CI 32259719677
success. (Retroaktívan rögzítve — a záró rituálék az eredeti sessionben
elmaradtak, ld. a fejléc-blokkot.)

**Aktuális állapot (2026-08-19):** `main` @ `3ab2a147` — E07-R25 Analyze és
Vision evidence integráció, PR [#322](https://github.com/wolfcasaba/strumsight/pull/322),
squash-merge. Exact `cbcb30c7`: Full Gate 32210677497 + Router CI 32210693573
success; a post-merge célzott gate futása a záró rituálé része.

**Aktuális állapot (2026-08-19):** `main` @ `b08c00e9` — E07-R24 song-goal
integráció, PR [#318](https://github.com/wolfcasaba/strumsight/pull/318),
squash-merge. Exact `028ea117`: Full Gate 32200092798 + Router CI 32200094318
success; a post-merge célzott gate futása a záró rituálé része.

**Aktuális állapot (2026-08-18):** `main` @ `c4e0bd0b` — E07-R18
GenerationOrchestrator, PR [#300](https://github.com/wolfcasaba/strumsight/pull/300),
squash-merge. Exact `74916469`: Full Gate
[32129580603](https://github.com/wolfcasaba/strumsight/actions/runs/32129580603)
+ Router CI [32129429169](https://github.com/wolfcasaba/strumsight/actions/runs/32129429169)
success; `origin/main` mozdult a dispatch és a merge között (2 nem-átfedő
pipeline-commit, `#298`/`#299`) — a round branch mergelte, újra-dispatch-elve
az egyesített SHA-n. Egy javító kör (`bf821515`) zárta F1 BLOCKER + F2 MAJOR
leletet, saját kézzel újramérve. Post-merge célzott gate zöld a friss,
fast-forwardolt `main`-en.

**Aktuális állapot (2026-08-18):** `main` @ `e95f9f67` — E07-R17 bounded
spaced-repetition review queue, PR #296 squash-merge. Exact `6d4261f7`:
Full Gate 32122497306 + Router CI 32122499507 success; post-merge célzott
gate zöld.

**Aktuális állapot (2026-08-18):** `main` @ `2dabfd9f` — E07-R16 progression
policy, PR [#295](https://github.com/wolfcasaba/strumsight/pull/295),
squash-merge. Exact `b72408ca`: Full Gate
[32117512693](https://github.com/wolfcasaba/strumsight/actions/runs/32117512693)
+ Router CI [32117514820](https://github.com/wolfcasaba/strumsight/actions/runs/32117514820)
success; post-merge célzott gate zöld.

**Aktuális állapot (2026-08-16):** `main` @ `7f4be792` — E07-R15
WeeklyScheduler, PR [#294](https://github.com/wolfcasaba/strumsight/pull/294),
squash-merge. Exact `e100564d`: Full Gate
[31948064288](https://github.com/wolfcasaba/strumsight/actions/runs/31948064288)
+ Router CI [31948065345](https://github.com/wolfcasaba/strumsight/actions/runs/31948065345)
success; post-merge célzott gate zöld.

**Aktuális állapot (2026-08-16):** `main` @ `70e6e718` — E07-R14 daily
time-budget allocator, PR [#288](https://github.com/wolfcasaba/strumsight/pull/288),
squash-merge. Exact `de95bd30`: Full Gate
[31940629128](https://github.com/wolfcasaba/strumsight/actions/runs/31940629128)
+ Router CI [31940614513](https://github.com/wolfcasaba/strumsight/actions/runs/31940614513)
success; a post-merge célzott gate a friss `main`-en zöld.

**Aktuális állapot (2026-08-16):** `main` @ `18630834` — E07-R12
SkillPriorityEngine és verziózott priority policy, PR
[#286](https://github.com/wolfcasaba/strumsight/pull/286), squash-merge.
Exact-SHA `2295063e`: Full Gate
[31935775887](https://github.com/wolfcasaba/strumsight/actions/runs/31935775887)
+ Router CI [31935764217](https://github.com/wolfcasaba/strumsight/actions/runs/31935764217)
mindkettő success; `origin/main` nem mozdult a dispatch és a merge között. A
post-merge célzott gate a friss, fast-forwardolt `main`-en zöld.

**Aktuális állapot (2026-08-16):** `main` @ `c2778bbc` — E07-R10
AdaptivePracticePlan/day/block/revision domain, PR
[#283](https://github.com/wolfcasaba/strumsight/pull/283), squash-merge.
Exact-SHA `4d4c3ee4`: Full Gate
[31929041014](https://github.com/wolfcasaba/strumsight/actions/runs/31929041014)
+ Router CI [31929076484](https://github.com/wolfcasaba/strumsight/actions/runs/31929076484)
mindkettő success (Router CI manuálisan dispatch-elve, mert a csúcs-commit
önmagában docs/reviews-only, nem érintett trigger-útvonalat — a korábbi,
`docs/rounds/**`-et érintő push-ok a saját SHA-jukon már zölden lefutottak).
`origin/main` nem mozdult a dispatch és a merge között; a post-merge célzott
gate friss, fast-forwardolt `main`-en zöld.

**Aktuális állapot (2026-08-16):** `main` @ `3fd35781` — E07-R08 Practice
catalog capability adapter, PR
[#278](https://github.com/wolfcasaba/strumsight/pull/278), squash-merge.
Exact-SHA `4556a2ce`: Full Gate
[31918372154](https://github.com/wolfcasaba/strumsight/actions/runs/31918372154)
+ Router CI [31918359641](https://github.com/wolfcasaba/strumsight/actions/runs/31918359641)
mindkettő success. `origin/main` nem mozdult a dispatch és a merge között;
a post-merge célzott gate friss, fast-forwardolt `main`-en zöld.

**Aktuális állapot (2026-08-16):** `main` @ `afd7e9c4` — E07-R07 Legacy
Learn és Progress evidence adapterek, PR
[#277](https://github.com/wolfcasaba/strumsight/pull/277), squash-merge.
Exact-SHA `2d75d8b1`: Full Gate
[31915638913](https://github.com/wolfcasaba/strumsight/actions/runs/31915638913)
+ Router CI [31915639663](https://github.com/wolfcasaba/strumsight/actions/runs/31915639663)
mindkettő success. `origin/main` nem mozdult a dispatch és a merge között;
a post-merge célzott gate friss, fast-forwardolt `main`-en zöld.

**Aktuális állapot (2026-08-15):** `main` @ `d1f36c8c` — E07-R06 SkillEstimate
reducer és konfliktuskezelés, PR
[#276](https://github.com/wolfcasaba/strumsight/pull/276), squash-merge.
Exact-SHA `698ceccb`: Full Gate
[31913532960](https://github.com/wolfcasaba/strumsight/actions/runs/31913532960)
+ Router CI [31913526737](https://github.com/wolfcasaba/strumsight/actions/runs/31913526737)
mindkettő success. A branch egy örökölt (jelzés nélkül megszakadt) session
után `main`-től eggyel lemaradva állt (`817ea579`, E13 queue-engine mező
javítás — a kör `allowed_paths`-ától diszjunkt fájl); konfliktusmentesen
rebase-elve és `safe-force-push.sh`-sal pusholva lett, `origin/main` a
rebase utáni CI-újradispatch és a merge között nem mozdult.

**Aktuális állapot (2026-08-15):** `main` @ `fc494ef6` — E14-R01 Recognition
Accuracy & Useful UI Recovery kickoff, PR
[#275](https://github.com/wolfcasaba/strumsight/pull/275), squash-merge.
Exact-SHA `ab615c6f`: Full Gate
[31910980257](https://github.com/wolfcasaba/strumsight/actions/runs/31910980257)
+ Router CI [31910963645](https://github.com/wolfcasaba/strumsight/actions/runs/31910963645)
mindkettő success. A branch a dispatch előtt `903e7a7d`-re
konfliktusmentesen rebase-elve lett, és `origin/main` a dispatch és merge
között nem mozdult.

**Aktuális állapot (2026-08-15):** `main` @ `ac12b017` — E07-R04
PracticeGenerationRequest és draft persistence, PR
[#272](https://github.com/wolfcasaba/strumsight/pull/272), squash-merge.
Exact-SHA `864cf4ab`: Full Gate
[31905168438](https://github.com/wolfcasaba/strumsight/actions/runs/31905168438)
+ Router CI [31905169678](https://github.com/wolfcasaba/strumsight/actions/runs/31905169678)
mindkettő success. A branch `344c2fdc`-re konfliktusmentesen rebase-elve lett,
és `origin/main` a dispatch és a merge között nem mozdult.

**Aktuális állapot (2026-08-15):** `main` @ `e5cae94d` — E99-R11
GOV-30c-3 progress-phase decoupling, PR
[#262](https://github.com/wolfcasaba/strumsight/pull/262), squash-merge.
Exact-SHA `211b53c2`: Full Gate
[31872874525](https://github.com/wolfcasaba/strumsight/actions/runs/31872874525)
+ Router CI [31873455184](https://github.com/wolfcasaba/strumsight/actions/runs/31873455184)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között;
post-merge `tools/round-gate.sh` zöld a friss `main`-en.

**Aktuális állapot (2026-08-14):** `main` @ `82cfa588` — E99-R10
GOV-30c-2 evaluation stage composition, PR
[#261](https://github.com/wolfcasaba/strumsight/pull/261), squash-merge.
Exact-SHA `e3c681b6`: Full Gate
[31795147660](https://github.com/wolfcasaba/strumsight/actions/runs/31795147660)
+ Router CI [31795149311](https://github.com/wolfcasaba/strumsight/actions/runs/31795149311)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között.

**Aktuális állapot (2026-08-14):** `main` @ `cb76db0f` — E99-R09
GOV-30c-1 PCM ingest pipeline composition, PR
[#259](https://github.com/wolfcasaba/strumsight/pull/259), squash-merge.
Exact-SHA `5d2e0da0`: Full Gate
[31780988606](https://github.com/wolfcasaba/strumsight/actions/runs/31780988606)
+ Router CI [31781917615](https://github.com/wolfcasaba/strumsight/actions/runs/31781917615)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között.

**Aktuális állapot (2026-08-14):** `main` @ `f257afa7` — E06-R30 (shadow
rollout, migráció és Epic 6 lezárás, ZÁRÓ KÖR), PR
[#257](https://github.com/wolfcasaba/strumsight/pull/257), squash-merge.
Exact-SHA `719c534c`: Full Gate
[31758004379](https://github.com/wolfcasaba/strumsight/actions/runs/31758004379)
+ Router CI [31758041194](https://github.com/wolfcasaba/strumsight/actions/runs/31758041194)
mindkettő success. `origin/main` nem mozdult dispatch és merge között.
Post-merge `tools/round-gate.sh test/features/audio_analysis test/app
test/features/analyze test/features/library` a lokálisan fast-forwardolt,
friss `main`-en 9/9 zöld — lásd a fejléc ✅-blokk a teljes
pre-flight/review/security/javító-kör történetért. **Epic 6 (Audio
Analysis 2.0) mind a 30 köre kész** — a V2 shadow-szinten marad, a V1 a
shipping út, opt-in/default-on rollout és V1-kivezetés külön, jövőbeli,
ember által jóváhagyott GOV-kör dolga (a completion report `GOV-30a/b/c`
néven nevesíti).

**Korábbi állapot (2026-08-13):** `main` @ `d325d601` — E06-R28 (cache,
performance és model lifecycle), PR
[#255](https://github.com/wolfcasaba/strumsight/pull/255), squash-merge.
Exact-SHA `59810b4`: Full Gate
[31744318906](https://github.com/wolfcasaba/strumsight/actions/runs/31744318906)
+ Router CI [31744374712](https://github.com/wolfcasaba/strumsight/actions/runs/31744374712)
mindkettő success. `origin/main` nem mozdult dispatch és merge között. Post-merge
`tools/round-gate.sh test/features/audio_analysis test/property test/core`
egy REMOTE-ról klónozott, friss munkapéldányon (L264) — lásd
`docs/handoff-archive.md` a teljes pre-flight/review/security történetért.

> Ez a §4 log ITT nem lett folyamatosan karbantartva E06-R19…R27 között — a
> fejléc ✅-blokkja (mindig a két legutóbbi kör) és `docs/handoff-archive.md`
> a hiteles, folyamatos forrás azokra a körökre. Az alábbi, E99-R08-cal kezdődő
> szakasz a korábbi (2026-08-12-i) állapotot rögzíti — történeti kontextusként
> hagyva, nem frissítve visszamenőleg.

**Korábbi állapot (2026-08-12):** `main` @ `7a594db6` — E99-R08 H3
self-heal (ADR 0112, NEM egy SDD-kör — pipeline-infra fix), PR
[#243](https://github.com/wolfcasaba/strumsight/pull/243), squash-merge.
Router CI [31682955616](https://github.com/wolfcasaba/strumsight/actions/runs/31682955616)
success az exact-SHA `86c4719f`-en (PR-ág), majd
[31683234986](https://github.com/wolfcasaba/strumsight/actions/runs/31683234986)
success a merge-elt `7a594db6`-on (post-merge `main`). `main`-t NEM
érintette Dart-kód, `build-apk.yml` nem indult. Az E99-R08 SDD-kör saját
commitjai (`ba9b65ea`…`bf413355`) a **round saját branchén**
(`sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation`) landoltak,
nem itt — a kör review-jelentése és a merge még hátravan, lásd a fejléc 🔧
blokkját. `origin/main` nem mozdult dispatch és merge között.

**Előző állapot (2026-08-12):** `main` @ `6be36efa` — E06-R23 H3
self-heal (ADR 0112, NEM egy SDD-kör — pipeline-infra fix), PR
[#240](https://github.com/wolfcasaba/strumsight/pull/240), squash-merge.
Router CI [31649793492→31650104969](https://github.com/wolfcasaba/strumsight/actions/runs/31650104969)
success az exact-SHA `569ad2fe`-n (első próba pirosra futott egy CI-shallow-
checkout-specifikus tesztbuggal — ld. lecke L247 —, javítva, a végleges HEAD
zöld). `main`-t NEM érintette Dart-kód, `build-apk.yml` nem indult. Az
E06-R23 SDD-kör saját commitjai (`12bb66d`, `3d4ace8`) a **round saját
branchén** landoltak, nem itt — lásd a fejléc 🔧 blokkját. `origin/main` nem
mozdult dispatch és merge között.

**Korábbi állapot (2026-08-12):** `main` @ `6abdd408` — E06-R22, PR
[#239](https://github.com/wolfcasaba/strumsight/pull/239), squash-merge.
Exact-SHA `ae22ff50`: Full Gate
[31642984516](https://github.com/wolfcasaba/strumsight/actions/runs/31642984516)
+ Router CI [31642980491](https://github.com/wolfcasaba/strumsight/actions/runs/31642980491)
mindkettő success a végleges (javító kör utáni) HEAD-en. `origin/main` nem
mozdult dispatch és merge között. A post-merge
`tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze`
mind a nyolc lépése zöld (`audio_analysis=438`, `app=69`, `analyze=64`).

**Előző állapot (2026-08-12):** `main` @ `98f4c1e1` — E06-R21, PR
[#238](https://github.com/wolfcasaba/strumsight/pull/238), squash-merge.
Exact-SHA `fa736e39`: Full Gate
[31636632388](https://github.com/wolfcasaba/strumsight/actions/runs/31636632388)
+ Router CI [31636633676](https://github.com/wolfcasaba/strumsight/actions/runs/31636633676)
mindkettő success. `origin/main` nem mozdult dispatch és merge között.

**Korábbi állapot (2026-08-12):** `main` @ `f2674099` — E06-R18, PR
[#234](https://github.com/wolfcasaba/strumsight/pull/234), squash-merge.
Az exact merge-előtti SHA `f8ed50b2`: Full Gate
[31609390475](https://github.com/wolfcasaba/strumsight/actions/runs/31609390475)
success (`full-gate` + `Coverage`). A CI-terv `full-gate.yml`-t adott
(`apk_required=false`); Router CI [31607444433](https://github.com/wolfcasaba/strumsight/actions/runs/31607444433)
success az `ae11543c` releváns ősön, mert az utókommitok nem triggerelték.
`origin/main` nem mozdult dispatch és merge között. A post-merge
`tools/round-gate.sh test/features/audio_analysis test/tooling test/app`
mind a nyolc lépése zöld.

**Ennél is korábbi állapot (2026-08-12):** `main` @ `aa41db54` — E06-R09, PR
[#223](https://github.com/wolfcasaba/strumsight/pull/223), squash-merge.
Az exact merge-előtti SHA `29feb745` (a review-dokumentumok utáni végleges
HEAD): Full Gate és Router CI success, mindkettő kézzel `workflow_dispatch`-
elve, mert a review-doksi-only commit egyik workflow push-path-szűrőjét sem
érintette (L112). A post-merge
`tools/round-gate.sh test/features/audio_analysis test/property test/tooling test/features/analyze`
mind a kilenc lépése zöld (lásd lent). Az alábbi régebbi rész történeti kontextus.

`main` @ [PR #211](https://github.com/wolfcasaba/strumsight/pull/211), squash
`62516a4b` (E06-R01, Epic 6 kickoff — Analyze V1 baseline, mérés és hat
kötött ADR; lásd a fejléc ✅-blokk a teljes pre-flight/review/security
történetért). Implementer **Terra (Codex)**, 1 forduló, javító kör nélkül.
`lib/`/`test/` diff üres — `tool/audio_analysis_baseline.dart` (ÚJ),
`docs/baseline/epic-06-audio-analysis-start.md` (ÚJ),
`docs/manual-testing/analysis-eval-matrix.md` (ÚJ), `docs/adr/0215`…`0220`
(ÚJ, orchesztrátor pre-flight) és a brief §0.0/§10 → Full Gate
[31477469515](https://github.com/wolfcasaba/strumsight/actions/runs/31477469515)
+ Router CI mindkettő **success** az exact merge-előtti tip `d7adf53e`-n
(a Router CI automatikus push-trigger, mert a diff `docs/rounds/**`-t
érint; a Full Gate kézzel dispatch-elve, a CI-terv `full-gate.yml`-t írt
elő, `native_gate=false`). Review **APPROVED, 0 BLOCKER/MAJOR/MINOR**, 3
NOTE — a reviewer SAJÁT, izolált `/tmp` klónban a teljes 7-lépéses gate-et
függetlenül újrafuttatta (mind zöld) ÉS a determinisztikus mérő-harnesst
egy HARMADIK, tőle független futtatással bájtra egyező
`DETERMINISM_SHA256`-ra futtatta. Dedikált security-review (risk=high)
**PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
dispatch és a merge között **nem mozdult** (`2334136a` mindvégig), rebase
nem kellett (H8 tiszta). Post-merge gate a friss `main`-en (`62516a4b`) is
önállóan újrafuttatva: mind a 7 lépés zöld.

**Pre-flight kétszeres mért drift-javítás (§0.0 R1+R2, a lánc mintázata
immár hatodszor mérve, `docs/LESSONS.md` L194):** a brief 2026-08-07-i
fejléce `ls`-alapú extrapolációval 0200–0205 ADR-tartományt írt elő; a
`reserve-adr` foglaló a valós, 2026-08-11-i állapotot **0215–0220**-ként
adta (három közbeeső governance-kör foglalta el a köztes számokat anélkül,
hogy a 0200–0211 sávot ténylegesen lefoglalta volna). A `lib/features/analyze/`
fájl/sorszáma is driftelt a brief mérése óta (12→14 fájl, 1866→2168 sor,
E05-R27 eredetű) — mindkettő dokumentált revízióval javítva a dispatch előtt.

> **[Superseded ref — E99-R05 branch]:** `main` @ PR #208, squash
> `c4ce2cc0` (E99-R05, GOV-06b — a GOV-06 BPM-metrikájának javítása).
> Mérce-javító kör, `lib/` diff üres (ADR 0212 Döntés 6). Full Gate
> [31325609456](https://github.com/wolfcasaba/strumsight/actions/runs/31325609456)
> + Router CI [31325597238](https://github.com/wolfcasaba/strumsight/actions/runs/31325597238)
> mindkettő **success** az exact merge-előtti tip `94fb2f6f`-n. Review
> **APPROVED, 2 forduló** (1 impl. + 1 javító kör); dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`caa7751e` mindvégig), rebase
> nem kellett (H8 tiszta). Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E99-R04 branch]:** `main` @ PR #207, squash `5ceed22d`
> (E99-R04, GOV-06 — Valós-audio DSP baseline mérés). Mérési kör, `lib/` diff
> üres (A1) → Full Gate [31302531695](https://github.com/wolfcasaba/strumsight/actions/runs/31302531695)
> + Router CI [31302494856](https://github.com/wolfcasaba/strumsight/actions/runs/31302494856)
> mindkettő **success** az exact merge-előtti tip `ab4024a6`-n. Review
> **APPROVED, 1 forduló, javító kör nélkül**; dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`dc201524` mindvégig), rebase
> nem kellett (H8 tiszta). A BPM-MAE szám azóta **visszavonva** — lásd fent,
> GOV-06b. Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E99-R03 branch]:** `main` @ PR #206, squash `0e9d211c`
> (E99-R03, GOV-05c — Learn migráció a Practice Engine V2-re). Flag+teszt+
> doksi diff (nincs `lib/features/**`, kizárólag
> `lib/app/config/feature_flags.dart`) → Build APK
> [31298706423](https://github.com/wolfcasaba/strumsight/actions/runs/31298706423)
> + Router CI [31298707173](https://github.com/wolfcasaba/strumsight/actions/runs/31298707173)
> mindkettő **success** az exact merge-előtti tip `87ca3f54`-n. Review
> **APPROVED, 1 forduló, javító kör nélkül**; dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`69ecc661` mindvégig), rebase
> nem kellett (H8 tiszta). Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E05-R30 branch]:** `main` @ PR #204, squash `d3b2caf9`
> (E05-R30, Dataset, evaluation, minőségi kapuk és Epic 5 lezárás — ZÁRÓ
> KÖR). Full Gate [31282481824](https://github.com/wolfcasaba/strumsight/actions/runs/31282481824)
> + Router CI [31282482794](https://github.com/wolfcasaba/strumsight/actions/runs/31282482794)
> **success** a `bbb23079` merge-előtti tipen; review **APPROVED javító kör
> nélkül**, dedikált security-review **PASS**. Teljes történet:
> [`docs/handoff-archive.md`](docs/handoff-archive.md). Lecke: **L202**,
> **L189 kiegészítve**.

**Az Epic 5 (Computer Vision) MIND A 30 KÖRE kész**, és a §6 „Kötelező
sorrend" GOV-05 shipping-rollout hármasa (GOV-05a/b/c) is lezárult. A
pipeline queue egyetlen fennmaradó sora (`E06-R29`/`E06-R30`) `hold`-on van
— nincs automatikusan indítható következő kör. Lásd §6.
_(Történeti product-merge referencia: PR #205 / `d958b75e`, E99-R01
(GOV-05a); PR #204 / `d3b2caf9`, E05-R30; PR #203 / `8e7eb6f9`, E05-R29; PR #202 /
`a9698557`, E05-R28; PR #201 /
`7e43019`, E05-R27; PR #200 /
`242cccb`, E05-R26; PR #199 /
`9b608cf`, E05-R25; PR #197 /
`e9257f4`, E05-R24; PR #196 /
`b54490e`, E05-R23; PR #195 / `997e7be`, E05-R22; PR #194 /
`7b11f26`, E05-R21; PR #193 /
`be38e11`, E05-R20; PR #192 / `a38e0e0`, E05-R19; PR #191 / `75f8766`,
E05-R18; PR #189 / `e979d41`, E05-R17; PR #188 / `6f9c0e1`, E05-R16; PR #187
/ `a351ad3`, E05-R15; PR #185 / `efa4bbe`, E05-R14; PR #184 / `148469c`,
E05-R13; PR #183 / `f39d7b6`, E05-R12; PR #182 / `113976a`, E05-R11; PR #181
/ `39d1c29`, E05-R10; PR #180 / E05-R09, frame quality assessor; PR #169 /
`b5837d9`, E05-R07; PR #168 / `a43f8c1`, E05-R06; PR #162 / `cef864c`,
E05-R01, Epic 5 INDUL; PR #160 / `0cf6323`, E04-R24.)_

> **[Superseded ref — E05-R07 branch]:** `main` @ PR #169, squash
`b5837d9` (E05-R07). Pure Dart/teszt diff → full-gate
[31105913601](https://github.com/wolfcasaba/strumsight/actions/runs/31105913601)
+ router-ci [31105957563](https://github.com/wolfcasaba/strumsight/actions/runs/31105957563)
**success** az exact merge-előtti tip `9c52d74`-n; review **APPROVED 1 javító
kör után** (Terra implementer). Az `origin/main` a dispatch óta **nem
mozdult** (`b6408f0` → merge `b5837d9`), rebase nem kellett (H8 tiszta).

> **[Superseded ref — E04-R22 branch]:** `main` @ PR #157, squash
`faa3f32` (E04-R22). Tisztán Dart/dokumentum-diff → a CI-terv `full-gate.yml`-t
írt elő (nincs natív út), és a `docs/rounds/**` érintés miatt a **router-ci** is a
kapu része: full-gate [31071295264](https://github.com/wolfcasaba/strumsight/actions/runs/31071295264)
+ router-ci [31071295063](https://github.com/wolfcasaba/strumsight/actions/runs/31071295063)
**success** az exact merge-előtti tip `05c7006`-on; review **APPROVED** 1 javító
kör után (MiniMax M3). A dispatch óta a `main` mozdult (#158 DeepSeek engine-registry),
ezért a branchet `origin/main`-re **rebase**-eltem (konfliktus nélkül) és a CI-t
**újra-dispatcheltem** az `05c7006` tip-en (ADR 0086 §2 / H8).
(Történeti product-merge referenciák: PR #156 / `6000b57`, E04-R21; PR #153 / `3ce4afc`, E04-R20; PR #151 / `104e685`, E04-R18;
PR #148 / `1e9b2db`, E04-R17; PR #147 / `df25806`, E04-R16; PR #145 / `1fe91d2`,
E04-R15; PR #140 / `c5b14e5`, E04-R12; PR #137 / `479550f`, E04-R11; PR #129 / `f3d69ef`,
E04-R06; PR #128 / `55d640d`, E04-R05; PR #127 / `0d7ab1b`, E04-R04.)

> **L48 clone-pitfall recurred on a fresh `auto`-router worktree
> (mérve 2026-08-02, E03-R06):** a brand-new worktree's first
> `BASELINE_GATE` run BLOCKED on 625 `AppLocalizations` analyze errors
> (gitignored `lib/l10n/app_localizations*.dart` missing from the fresh
> `git worktree add`). Fix: `flutter pub get && flutter gen-l10n` in the
> worktree, then `python3 tools/model-router.py reset --task-id <ID>`
> (sanctioned, zero-cost) — same recipe as L48, now confirmed systemic
> across `auto`-router worktrees, not a one-off. Also measured in the
> same pre-flight (NOT this session's to fix — a closed round's
> artifact): the currently-`main` E03-R05 brief's `ai-router` TOML
> `allowed_paths` incorrectly includes the ADR 0114 path, which is why
> Router CI (`router-ci.yml`) is red on `main` right now — left for a
> future self-heal round. Details: `docs/LESSONS.md` L59.

> **Two router infra dead ends closed/documented on the E03-R05 branch
> before that round's own work started:** the branch had already been
> through two H6 self-heal cycles (PR #61/#62/#63, `docs/LESSONS.md`
> L54–L56 — async router dispatch, gate-guard scope, and finally a PATH
> git-guard shim closing M3's illegal self-commit at the shell layer).
> That session's pre-flight found the salvageable, scope-clean M3 diff
> sitting uncommitted in an abandoned worktree and reconciled it (L50
> pattern: `git reset --soft` + rebase + independent gate re-run +
> orchestrator commit) instead of re-running the round from scratch.

> **Router `resume` false-`BLOCKED` from a premature orchestrator commit
> (mérve 2026-08-02, E03-R03):** teljes leírás `docs/LESSONS.md` L51-ben —
> röviden: NE commitold a diffet/review-t a `resume` hívás előtt (audit +
> review UNCOMMITTED, vagy külön klón); findings-fájl `.ai/review-findings-
> <slug>.md` néven; csak a TELJES ciklus lezárása után, egyetlen lépésben
> commitolj.

> **`BLOCKED`→`READY_FOR_REVIEW` recovery (mérve 2026-08-02, E03-R02):** ha
> `m3_attempts >= 1` és a self-heal már bizonyította a diff scope-tisztaságát,
> a `model-router.py reset --task-id` + friss `run` a JELENLEGI worktree
> tartalmát kapja új baseline manifestként — ha a diff még a worktree-ben
> van, azonnal újra `BLOCKED`-ba fut ("baseline has untracked files"); ha
> pristine-re tisztítod előbb, egy felesleges, ismételt M3-attempt-et fizetsz
> a már kész munkáért. A helyes út: `git reset --soft <pre-flight commit>` a
> worktree-ben (M3 saját commitját visszabontja uncommitted diffre),
> `git rebase origin/main` a healed baseline-ra, scope-audit a brief
> `allowed_paths` ellen, majd az orchestrátor saját authorship-szel
> commitolja — a router task state-hez nem kell nyúlni. Részletek:
> `docs/LESSONS.md` L50.

> **Router baseline-precheck clone pitfall (mérve 2026-08-02, E03-R01):** egy
> vadonatúj izolált munkapéldány első `ai-router-round.sh run` hívása a lenti
> klón-csapdába fut, de a router SAJÁT `BASELINE_GATE` precheckjében, `BLOCKED`
> státusszal és **`m3_attempts=0`**. A javítás: `flutter pub get && flutter
> gen-l10n` a klónban, majd `python3 tools/model-router.py reset --task-id
> <ID>` (sanctioned, zéró-fogyasztású reset — NEM a tiltott kézi
> state-törlés). Részletek: `docs/LESSONS.md` L48.

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

**E09-R07 — Follow és follow request social graph** (PR
[#416](https://github.com/wolfcasaba/strumsight/pull/416), squash
`1cc49e41`, [ADR 0401](docs/adr/0401-follow-and-follow-request-social-graph.md)).
Idempotens, privacy-kompatibilis follow rendszer (public azonnali, private
request-lifecycle); DB-szintű self-follow CHECK + race-biztos UNIQUE. 0
nyitott BLOCKER/MAJOR review-lelet HÁROM javító kör után (F1 BLOCKER
nem-determinisztikus valódi-sértés próba FIXED Barrier-szinkronizációval, F2/
F3 MAJOR auth-gap + törött idempotency-kontraktus FIXED, F4 MINOR FIXED; a 3.
javító kör egy körön kívüli CI-only screen-számláló driftet zárt,
`docs/reviews/e09-r07-review.md`). Exact `f75f0007`: Full Gate 32603023648 +
Router CI 32603026921 success. Részletesen a fejléc ✅-blokkban.

**E09-R06 — Profil létrehozás, szerkesztés és Community gate UI** (PR
[#415](https://github.com/wolfcasaba/strumsight/pull/415), squash
`77bc0589`, [ADR 0400](docs/adr/0400-profile-onboarding-service-and-community-gate-ui.md)).
Community gate (4 állapot) + profil onboarding/edit flow + backend
service-szintű profil-létrehozás (ADR 0396-ban MÁR ennek a körnek
kiosztott, a batch-elt brief által kihagyott felelősség). 0 nyitott
BLOCKER/MAJOR review-lelet KÉT javító kör után (F1 BLOCKER, F2 MAJOR,
F9/F10 MAJOR mind FIXED; F3/F4/F6 MINOR nem blokkolnak,
`docs/reviews/e09-r06-review.md`). Exact `bf2f67da`: Full Gate 32596780267
+ Router CI 32597616787 success. Részletesen a fejléc ✅-blokkban.

**E08-R30 — Epic 08 migráció, regresszió és lezárás** (PR
[#407](https://github.com/wolfcasaba/strumsight/pull/407), squash `a8ecb9f3`,
ADR nincs — mérce-lezáró kör, nem hozott kötött architekturális döntést).
**EPIC 8 (GAMIFICATION) MIND A 30 KÖRE KÉSZ.** Hat új gamifikációs route
élesítve (`app_router.dart`, minimális Riverpod-ragasztó kizárólag már
publikus core-providerekből, `lib/features/**` érintetlen); real-shape
legacy-fixture teszt a streak/practice migrátorokra; a be nem kötött
dual-write „kapcsoló" mért állapota + négy számszerű jövőbeli
aktiválási feltétel dokumentálva flip helyett. 0 BLOCKER/MAJOR/MINOR review-
lelet (2 NOTE, `docs/reviews/e08-r30-review.md`). Exact `3a6f10b3`: Full Gate
32569011383 + Router CI 32569012517 success; a reviewer saját izolált `/tmp`
klónban mind a kilenc gate-lépést függetlenül újrafuttatta. Részletesen a
fejléc ✅-blokkban.

**E08-R28 — Ledger sync contract és merge** (PR
[#406](https://github.com/wolfcasaba/strumsight/pull/406), squash `571981b7`,
[ADR 0394](docs/adr/0394-ledger-sync-contract-and-merge.md)). Offline-first,
duplikációmentes főkönyv-szinkron szerződés; a szerver soha nem fogad el
kliens-oldali összesített XP-t; unió-alapú összefésülés `ledgerId` +
`sourceEventId` kettős dedup-kulccsal; `unverified`/`verified` szerver-
autoritatív szétválasztás. Egy javító kör (F1 MAJOR wire-shape mismatch a
Dart-kódoló és a backend-dekódoló között + F2 MINOR hiányzó `max_length`
korlát, mindkettő javítva; review APPROVED, dedikált biztonsági review
PASS). Exact `dda4534b`: Full Gate 32565070603 + Router CI 32565071642
success. Részletesen a fejléc ✅-blokkban.

**E08-R26 — Cross-feature gamification integráció** (PR
[#403](https://github.com/wolfcasaba/strumsight/pull/403), squash `ea2e22a4`,
[ADR 0392](docs/adr/0392-cross-feature-gamification-adapter-caller-fed-boundaries.md)).
Négy caller-fed adapter (Analysis/Vision/Tutor/Plan); tutor-adapter ZÉRÓ
`ai_tutor`-importtal (pinned empty boundary, L139); plan-bónusz flat, nem
összegző (`bonusXp` fixen 0); vision technikai haladás `VisionClaimGuard`
mögött (0.70 küszöb, inkluzív). 0 BLOCKER/MAJOR/MINOR review-lelet, javító
kör nélkül; 3 nem-blokkoló NOTE (mind unwired-today). `security-reviewer`
(risk="high"): PASS. Exact `d3c4a9a0`: Full Gate 32557142579 + Router CI
32557160705 success. Részletesen a fejléc ✅-blokkban.

**E08-R25 — Song Trainer és setlist integráció** (PR
[#402](https://github.com/wolfcasaba/strumsight/pull/402), squash `204b3798`,
[ADR 0391](docs/adr/0391-song-gamification-adapter-standalone-bonus-and-hashed-song-id.md)).
Session-bookkeeping alapú bónusz-méretezés (NEM a bináris R06
`parentEventId` dedup) + SHA-256-hashelt privacy-safe dal-azonosító. 0
BLOCKER/MAJOR review-lelet, javító kör nélkül; 1 nem-blokkoló MINOR
follow-up (`utf8Bytes()` helper). Exact `180c8d40`: Full Gate 32554547623 +
Router CI 32554548631/32554544697 success. Részletesen a fejléc ✅-blokkban.

**E08-R18 — Heti quest és consistency objective** (PR
[#394](https://github.com/wolfcasaba/strumsight/pull/394), squash `29c27ab2`,
[ADR 0386](docs/adr/0386-flexible-weekly-quest-projection.md)). Pure,
caller-fed heti projekció; availability-arányos egész target; öt napos
aktívnap-cap; stabil FNV-választás; improvement fail-closed; same-ID monoton,
cross-ID izolált progress; típusos rollover. A két MAJOR review-lelet egy Terra
javító körben zárult. Correctness APPROVED, security PASS. Exact `c131c47e`:
Full Gate 32472133400 + Router CI 32472092472 success. Részletesen:
`docs/handoff-archive.md`.

**E13-R03 — Semantic colors and three themes** (PR
[#386](https://github.com/wolfcasaba/strumsight/pull/386), squash `6e80a441`,
[ADR 0381](docs/adr/0381-semantic-theme-and-accessibility-contract.md)). A
23 mezős semantic color contract, state overlayek, három `ThemeData`, külön
High Contrast behavior és nem-csak-szín marker contract elkészült. Két MAJOR
review-lelet egy Terra javító körben zárva; a canonical WCAG-vektor és az
all-same ikonmutációk piros bizonyítékot adtak. Végső correctness APPROVED,
security PASS. Exact `3fc36778`: Full Gate 32451933445 + Router CI
32451919508 success. Részletesen: `docs/handoff-archive.md`.

**E08-R15 — Achievement UI és részletes evidence** (PR
[#383](https://github.com/wolfcasaba/strumsight/pull/383), squash `22f5e1a0`,
[ADR 0378](docs/adr/0378-achievement-presentation-and-privacy-safe-evidence.md)).
Caller-fed, hidden fail-closed lista/detail UI; zárt aggregált evidence;
60-screen inventory és változatlan 40 route. Az első review 4 MAJOR
correctness + 1 MAJOR privacy leletét Terra javította; a H3 self-heal utáni
inventory-korrekció végső re-review-ja APPROVED/PASS. Exact `d4414f49`: Full
Gate 32449877483 + Router CI 32449853724 success. Részletesen:
`docs/handoff-archive.md`.

**E13-R02 — Design System Foundation és compatibility layer** (PR
[#384](https://github.com/wolfcasaba/strumsight/pull/384), squash `8bd7dc98`,
[ADR 0273](docs/adr/0273-design-system-token-source-of-truth.md)). Kipinnelt
foundation tokenek, legacy-theme delegáló adapter, kétkapus privát Component
Catalog és design-system architektúra-őr. Az F1/F2 MAJOR és F3 MINOR leletek
egy Terra javító körben zárva; végső correctness APPROVED és security PASS.
Exact `05ec6276`: Full Gate 32447387921 + Router CI 32447381563 success.
Részletesen: `docs/handoff-archive.md`.

**E08-R13 — Achievement domain és katalógus** (PR
[#376](https://github.com/wolfcasaba/strumsight/pull/376), squash `f9d5bbc8`,
[ADR 0374](docs/adr/0374-achievement-domain-and-catalog-contract.md)). 22
stabil ID-jú lokalizált achievement, típusos feltétel-fa, verzió-/deprekáció-
és progressz-invariánsok. Két MAJOR lelet egy Terra javító körben zárva;
végső correctness APPROVED és security PASS. Exact `679f030f`: Full Gate
32433372231 + Router CI 32433323271 success. Részletesen:
`docs/handoff-archive.md`.

**E99-R20 — GOV-14 kör-landolás automatizálás** (PR
[#361](https://github.com/wolfcasaba/strumsight/pull/361), squash `5ad15b5f`,
[ADR 0313](docs/adr/0313-round-landing-automation.md)). Kétfázisú exact-SHA
landolás, fail-closed konfliktus-osztályozás, PR-identitás-kötés és
H8-SELFDUP guard. F1/F3 BLOCKER + F2 MAJOR javítva; végső
correctness/security review APPROVED. Exact `a73493f4`: Full Gate 32373805059
+ Router CI 32373785655 success. Részletesen: `docs/handoff-archive.md`.

**E08-R09 — Legacy progress adapter és activity backfill** (PR
[#359](https://github.com/wolfcasaba/strumsight/pull/359), squash `842231f5`,
[ADR 0350](docs/adr/0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md)).
Deterministic SHA-256 activity ID, exact duplicate ordinal, nulla retroaktív
XP, immutable baseline-report és eredeti-snapshot-indexű checkpoint. Az F1
BLOCKER + F2/F3/S4 MAJOR leletek javítva; végső correctness/security review
APPROVED. Exact `e25d3158`: Full Gate 32365896298 + Router CI 32365922753
success. Részletesen: `docs/handoff-archive.md`.

**E99-R19 — GOV-13 lánc-higiénia** (PR
[#354](https://github.com/wolfcasaba/strumsight/pull/354), squash `4dc8f7d1`,
ADR 0307 §6). A D1 main-szinkron csak tiszta, szigorúan lemaradt `main`-t
fast-forwardol; a D2 záró dokumentáció és queue-státusz közös commitját, a
D3 pedig az indoklás nélküli magas kockázat strict leletét méri. F1 MAJOR
(a piszkos-fa teszt nem a tényleges őrt mérte) javítva; review APPROVED és
security PASS. Exact `c17ed660`: Full Gate 32347005385 + Router CI 32347032703
success; post-merge gate zöld (647 passed, 571 subtests).

**E08-R03 — Reward ledger és idempotencia-index** (PR
[#340](https://github.com/wolfcasaba/strumsight/pull/340), squash `39c0bd5f`,
[ADR 0301](docs/adr/0301-reward-ledger-append-only-idempotency.md)).
Append-only `RewardLedgerEntry` főkönyv + `RewardReason` kódok +
`RewardLedgerRepository` (nincs update/delete) + `LocalRewardLedgerRepository`
a `JsonDocumentStore` mintáján, atomikus Future-tail-lel szerializált
`appendIfAbsent` (a `SongTransport._commandTail` mintája). Review APPROVED
(0 BLOCKER/MAJOR/MINOR, 1 NOTE — `gate_shape` hamis pozitív, [[L340]]),
az A2 párhuzamos-race cellát a reviewer saját izolált klónban, saját
mutációs próbával reprodukálta. Exact `02477969`: Full Gate 32313777603 +
Router CI 32313779449 success; post-merge gate zöld (7/7). Lásd a
fejléc-blokkot a teljes történetért (második nekifutás egy H6-infra-hiba
után, három `main`-szinkron a kör alatt egy valódi párhuzamos kör miatt).

**E07-R30 — Evaluation harness, shadow rollout és Epic 7 lezárás** (PR
[#333](https://github.com/wolfcasaba/strumsight/pull/333), squash `ee5821dd`,
nincs új ADR). `ShadowPlanGenerator` — az Epic 7 első éles, vég-az-végig
determinisztikus pipeline-kompozíció, no-op activationnel (sosem aktivál
valódi állapotot). 3 golden tanulói profil, invariáns + golden-fixture
property tesztek (`test/property/`, nem a brief eredeti, CI-vel nem egyező
útvonalán — pre-flight §0.0 javította), `plan_quality_report.dart` riport,
Epic 7 completion report a nyitott tételekkel. Review APPROVED (0
BLOCKER/MAJOR/MINOR, saját izolált-klónos gate-újrafuttatással és saját
valódi-sértés próbával igazolva); kötelező security review PASS (0
CRITICAL/BLOCKER/MAJOR/MINOR, 3 NOTE). Exact `d40e2050`: Full Gate + Router
CI success; post-merge gate zöld. Egyetlen flag sem mozdult. **Epic 7 lezárva.**

**E07-R28 — Tutor és PlannerAssistGateway integráció** (PR
[#329](https://github.com/wolfcasaba/strumsight/pull/329), squash `b021eff2`,
[ADR 0270](docs/adr/0270-planner-assist-allowlist-and-untrusted-input.md)).
Strukturált request/response séma, exact goal-/skill-/candidate-allowlist
(nincs fuzzy), determinisztikus fallback minden felhő-hibára, tanuló-szöveg
elkülönítve nem-megbízható mezőként. Pre-flight §0.0 mérte: `ai_tutor`
`public.dart` fagyasztott üres ([[L121]]/[[L133]]/[[L139]] osztálya) —
`TutorPlanProposalAdapter` SAJÁT `TutorPlanOutline` típust definiál, `ai_tutor`
import nélkül. Review APPROVED (0 BLOCKER/MAJOR/MINOR, saját valódi-sértés
próba az A2-n); kötelező security review PASS (1 MINOR follow-up: uncapped
ID-array a sémában). Exact `dc413fd8`: Full Gate + Router CI success;
post-merge gate zöld. `plannerAssistEnabled` változatlanul `false`.

**E07-R27 — Missed day, catch-up, pause és returning flow** (PR
[#328](https://github.com/wolfcasaba/strumsight/pull/328), squash `a0c61044`,
ADR 0269 — meglévő). Domain-pure `MissedDayPolicy`, 21 napos küszöb
`readinessProposal`-t ad, Pause/Resume revíziók, non-shaming catch-up UI.
Review APPROVED egy javító kör után. **Hiányzó kötelező security review**
(brief `risk=high`) — utólag mérve, ld. a fejléc-blokkot. Exact `10ed4874`:
Full Gate + Router CI success. (Retroaktívan rögzítve.)

**E07-R24 — Song goal és Song Trainer integráció** (PR [#318](https://github.com/wolfcasaba/strumsight/pull/318),
squash `b08c00e9`, [ADR 0318](docs/adr/0318-song-goal-public-boundary-and-caller-fed-input.md)).
Caller-fed `SongDocument` boundary, fail-closed reader/normalizer, deterministic
song-block compiler és planner-integráció. Correctness review APPROVED egy
MiniMax-javító kör után; security delta-review PASS. Exact `028ea117`: Full
Gate + Router CI success; post-merge gate futása folyamatban.

**E07-R17 — Spaced repetition és maintenance queue** (PR #296, squash
`e95f9f67`, [ADR 0303](docs/adr/0303-spaced-repetition-review-queue-contract.md)).
Domain-pure typed review identity, explicit `LocalDate` interval-ladder,
strict daily review budget, replacement-required handling for missing targets
and deterministic deduplication. Review APPROVED (0 BLOCKER/MAJOR; 1 NOTE);
the unknown→failure mutation made A2 red. Exact `6d4261f7`: Full Gate +
Router CI success; post-merge gate zöld. Flags remain `false` with zero
production callers.

**E07-R16 — Progression és regression policy** (PR
[#295](https://github.com/wolfcasaba/strumsight/pull/295), squash `2dabfd9f`,
[ADR 0265](docs/adr/0265-bounded-evidence-based-difficulty-adaptation.md)).
Domain-pure `AdaptationDecider`: centralizált `ProgressionPolicy` (max egy
nehézségi fok/lépés, tempo-clamp, cooldown, minimum evidence — mind egy
helyen), discomfort/biztonsági blokk a teljesítménytől függetlenül, csak
ismételt küzdelem okoz regressziót, explicit „túl nehéz" self-report azonnali
regressziót ad a küszöb megkerülésével, minden döntés stabil evidence-
hivatkozást hordoz. Review APPROVED (0 BLOCKER/MAJOR, 1 MINOR follow-up, 4
NOTE); security PASS (0 CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE). A kötelező
valódi-sértés próba (2 lépéses ugrás engedélyezése) az A1 cellát ténylegesen
pirosra vitte, majd állandó regressziós tesztté vált. Exact `b72408ca`: Full
Gate + Router CI success; post-merge gate zöld. `practiceGeneratorEnabled`/
`plannerAssistEnabled` változatlanul `false`, nulla production hívó.

**E07-R15 — WeeklyScheduler és terhelésrotáció** (PR
[#294](https://github.com/wolfcasaba/strumsight/pull/294), squash `7f4be792`,
[ADR 0299](docs/adr/0299-weekly-scheduler-contract.md)). Domain-pure,
determinista heti döntés availability-, R14 `TimeBudget`-, explicit today- és
song-target inputtal. Unavailable/rest nap üres, primary/secondary fókusz,
inkluzív high-load-run és review-ratio korlátos; `target - scheduledDate <= 0`
performance, ezért csak review jelölt lehet. Review APPROVED, security PASS;
F1–F5 javítva, a phase-boundary mutáció ténylegesen piros. Exact `e100564d`:
Full Gate + Router CI success; post-merge gate zöld.

**E07-R14 — TimeBudgetAllocator és micro-plan** (PR
[#288](https://github.com/wolfcasaba/strumsight/pull/288), squash `70e6e718`,
[ADR 0298](docs/adr/0298-time-budget-allocation-contract.md)). Domain-pure,
determinista napi felosztó az SDD öt typed idejére: active playing, rest,
setup, reflection és elapsed session. Az inkluzív hard maximum, a policy
ceilinge és a floor-rounding sosem lép át napi korlátot; rövidítés és explicit
`extendToday` typed `systemAdaptation` change-setet ad. A review két MAJOR-t
talált (hiányzó extend út, inert policy mezők), egy MiniMax javító kör zárta,
az ismételt független review APPROVED; egy stale belső doc-link MINOR maradt.
Exact `de95bd30`: Full Gate + Router CI success; post-merge gate zöld.

**E07-R12 — SkillPriorityEngine és policy config** (PR
[#286](https://github.com/wolfcasaba/strumsight/pull/286), squash `18630834`,
[ADR 0264](docs/adr/0264-explainable-priority-and-versioned-policy.md)). Pure,
caller-supplied `asOf`-ra épülő SkillPriorityEngine: signed, normalizált
faktorokkal magyarázható score, unknown skillhez közepes assessment-prioritás,
primary-goal/prerequisite/coverage-debt boost, uncertainty/fatigue/novelty
penalty és discomfort safety override. A `PriorityPolicy` immutable,
verziózott; holtversenyben stabil lexikografikus skill-ID dönt. A review
APPROVED (0 BLOCKER/MAJOR): az unknown-assessment mutáció A2-t ténylegesen
pirosra vitte, a safe/painful sorrendet külön eldobható teszt mérte.

Exact `2295063e`: Full Gate
[31935775887](https://github.com/wolfcasaba/strumsight/actions/runs/31935775887)
+ Router CI [31935764217](https://github.com/wolfcasaba/strumsight/actions/runs/31935764217)
success; post-merge gate zöld.

**E07-R10 — AdaptivePracticePlan, day, block és revision domain** (PR
[#283](https://github.com/wolfcasaba/strumsight/pull/283), squash `c2778bbc`,
[ADR 0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)).
`AdaptivePracticePlan` (verziózott, veszteségmentes JSON round-trip,
`generationProvenance`+`policyVersions`, `PracticePlanSummary` DTO amely
strukturálisan kizárja a `PracticeGoal.userNote`-ot), `PracticeDay`/
`PracticeBlock` (közös, pinnelt 8-értékű `PracticeItemStatus` — SDD §16.5
szó szerint, `practice_block.dart`-ban — a `PracticeGoalStatus`/
`PracticeGoal.canTransitionTo`/`transitionTo` mintáját tükröző kikényszerített
átmenet-kontraktus + completed-content guard), `PlanRevision` (szigorúan
monoton szám, TELJES immutable snapshot — sosem diff az élő tervhez képest),
`PlanChangeSet`/`PlanChange` (strukturált before/after, typed
`PlanChangeReason`, szabad szöveg nélkül).

Két scope-kérdést a pre-flight/kör közbeni §0.0/§0.0.1 dokumentált
brief-revízió oldott fel (a brief eredeti `planned` státusz-példája egy
sehol nem létező enumra hivatkozott; az implementer egy negyedik, megosztott
teszt-fixture fájlt kért — a repo már meglévő
`test/fixtures/<feature>/<terület>/<név>_fixtures.dart` konvenciója szerint
engedélyezve, `plan_enums.dart` érintése nélkül).

Independent review **APPROVED** egy javító kör után: F1 MINOR — a
`PlanChangeType` a domain stabil-kódú konvenciója (`code`+`fromCode()`)
helyett a nyers Dart `.name`-et perzisztálta a JSON-ban, ami egy jövőbeli
identifier-átnevezést csendes adatkorrupcióvá tehetett volna — javítva
(`0a479818`), függetlenül újramérve friss `/tmp` klónban (mind a 8 gate-lépés
zöld, scope-audit OK). Két saját, független valódi-sértés próba (A2 revízió-
immutabilitás, A4 completed-block-tartalom-immutabilitás): mindkettő
PIROSRA váltott a guard ideiglenes eltávolításával, majd zölden visszaállt.

A kötelező biztonsági review (`risk = "high"`, AGENTS.md §15.1) **PASS**: 0
CRITICAL/BLOCKER/MAJOR/MINOR, 4 nem-blokkoló NOTE jövőbeli köröknek (a teljes
`toJson()` a perzisztenciához szükségszerűen hordozza a `userNote`-ot — egy
jövőbeli off-device/AI-export útnak a `toSummary()`-n vagy egy redaktoron
kell mennie, nem a nyers dokumentumon; `PlanChange.before`/`after` tartalom
ma validálatlan; `fromJson` kollekciók hossz-korlát nélküliek; `exerciseId`
charset-aszimmetria az ID-típusokhoz képest). Review:
[`e07-r10-review.md`](docs/reviews/e07-r10-review.md),
[`e07-r10-security.md`](docs/reviews/e07-r10-security.md). Mindkét flag
(`practiceGeneratorEnabled`, `plannerAssistEnabled`) `false` marad, nulla
production hívó — production viselkedés bitre változatlan.

**E07-R08 — Practice catalog capability adapter** (PR
[#278](https://github.com/wolfcasaba/strumsight/pull/278), squash `3fd35781`,
[ADR 0262](docs/adr/0262-catalog-snapshot-revisions-and-capability-truth.md)).
`ExerciseCandidate`/`PracticeCatalogSnapshot` — csak létező, végrehajtható
forrásra mutató jelöltek, két független (katalógus/tartalom) revízió,
determinisztikus `source:id:revision` rendezés, hiányzó kötelező metaadat →
kimarad + figyelmeztetés (default-pótlás tilos). Két pure, hívó-táplált
adapter: `PracticeEngineCatalogAdapter` (`practice/public.dart`) és
`LegacyLessonCandidateAdapter` (`learn/public.dart`, az R07
`LegacyMappingTable` újrafelhasználásával).

Pre-flight mérés talált egy valódi rést: a `practice/public.dart` nem
exportálja a katalógus repository/controller réteget
(`PracticeCatalogRepository`/`BuiltinPracticeCatalog`/Riverpod providerek) —
csak a `PracticeDefinition` value-típust. Dokumentált §0.0 brief-revízióval
oldva (`allowed_paths` változatlan): mindkét adapter pure, hívó-táplált
transzformátor, az élő katalógus-beolvasás egy jövőbeli kör dolga —
konzisztens az Epic 7 eddigi minden adapterének nulla-hívós mintájával.

Independent review **APPROVED** egy javító kör után: F1 MAJOR — a
`requiresMicrophone`/`supportsTempo`/`supportsLoop` mindkét adapteren
hamisan `unsupported` maradt minden jelöltre, holott mindhárom
determinisztikusan ismert (100%-ban mikrofonos detektálású tartalom; a
`PracticeSessionConfig` tempó/loop mezői definíciófüggetlenek — ez pontosan
az ADR 0262 saját, kiemelt tempó-vezérlés példája) — javítva, a Legacy
adapter tempó/loop mezője explicit, indokolt forráskorlátból marad
`unsupported`. F2 MINOR — a hat új value-típus nem implementált
`operator==`/`hashCode`-ot — javítva. Mindkettő eldobható próbateszttel,
friss izolált klónban függetlenül megerősítve. A javító kör jelzésének
`gate_shape=VIOLATION` mezője kivizsgálva és hamis pozitívnak bizonyult (a
modell a gate-script FORRÁSÁT olvasta ki `sed`-del, `&&`-lánccal más git
parancsokhoz kötve — a tényleges gate-futtatás önálló, láncolás nélküli
volt).

Exact-SHA `4556a2ce`: Full Gate
[31918372154](https://github.com/wolfcasaba/strumsight/actions/runs/31918372154)
+ Router CI [31918359641](https://github.com/wolfcasaba/strumsight/actions/runs/31918359641)
mindkettő success; post-merge gate friss `main`-en is zöld (7/7).
Implementer **Terra**, egy javító kör. Review:
[`docs/reviews/e07-r08-review.md`](docs/reviews/e07-r08-review.md).

**E07-R07 — Legacy Learn és Progress evidence adapterek** (PR
[#277](https://github.com/wolfcasaba/strumsight/pull/277), squash `afd7e9c4`,
[ADR 0293](docs/adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md)).
Az explicit, versioned mappingot használó `SkillSnapshotReader` adapterek
csak teljesen attesztált legacy outcome-ból gyártanak evidence-et; nincs
heurisztika, fabricated identity vagy raw secondsből képzett performance.
Correctness review APPROVED egy javító kör után: F1 a valódi shipping lesson
ID-kat, F2 az egy outcome → egy skill repository-kompatibilis szerződést
rögzítette regressziós tesztekkel. Exact-SHA Full Gate + Router CI zöld;
post-merge gate friss `main`-en is zöld. Implementer `sonnet-impl`, egy
javító dispatch.

**E07-R06 — SkillEstimate reducer és konfliktuskezelés** (PR
[#276](https://github.com/wolfcasaba/strumsight/pull/276), squash `d1f36c8c`,
[ADR 0261](docs/adr/0261-skill-estimate-bounded-influence-and-unknown-state.md)).
Determinisztikus, bounded-influence reducer: az `unknown` állapot explicit
(`level=null`, sosem `0.0`), egyetlen evidence hatása felülről korlátozott
(`singleEvidenceInfluenceCap`), konfliktus magas bizonytalanságot ad (nem
átlagot), a discomfort külön csatornán fut, sosem a teljesítmény-értékben.
Két MAJOR review-lelet javítva (időben szétváló, valódi javulás ne
minősüljön konfliktusnak; egyező időpontú evidence trendje ne az
outcome-ID sorrendjéből jöjjön) — mindkettő időbélyeg-bucketelt
konfliktus-detektálással zárva, regressziós tesztekkel igazolva.
Correctness review APPROVED, kötelező (`risk="high"`) security review PASS
(1 non-blocking MINOR egy jövőbeli fogyasztónak). Egy örökölt (korábbi,
jelzés nélkül megszakadt) session hagyta implementálva + review-zva +
javítva + jóváhagyva, nyitott PR-ral; ez a session örökölte, egy közbeeső
`main`-commit (E13 queue-engine mező javítás, diszjunkt fájl) miatt
konfliktusmentesen rebase-elt, `safe-force-push.sh`-sal pusholt és
CI-t újradispatch-elt. Exact-SHA Full Gate + Router CI mindkettő zöld;
post-merge gate friss `main`-en is zöld. Implementer Terra, egy javító kör.

**E14-R01 — Recognition recovery kickoff és release guard** (PR
[#275](https://github.com/wolfcasaba/strumsight/pull/275), squash `fc494ef6`,
[ADR 0271](docs/adr/0271-recognition-recovery-program.md)). A három recovery
flag opcionális és minden `AppEnvironment` alatt explicit `false`; nincs
felhasználói útvonal, DSP/ML-konstans, modell vagy CI-workflow módosítás. A
release activation contract az evaluation reportot, baseline/candidate
manifestet, corpus hash-t és rollback-receptet fail-closed előfeltételként
rögzíti. Isolated review mutáció-próba `false → nonProd` gyengítéskor a lab és
development tesztcellákat pirosra váltotta, majd visszaállt. Correctness és
security review APPROVED; Full Gate + Router CI exact-SHA success.

**E07-R04 — PracticeGenerationRequest és draft persistence** (PR
[#272](https://github.com/wolfcasaba/strumsight/pull/272), squash `ac12b017`,
[ADR 0259](docs/adr/0259-generation-request-versioning-and-draft-isolation.md)).
Immutable, schema-verziózott generation request készült kanonikus SHA-256
content-hash-sel és származtatott seeddel; a hashből kizárt idő/provenance nem
rontja a reprodukálhatóságot. A v1→v2 migráció támogatott, jövőbeli vagy sérült
séma kontrollált hibát ad. A wizard-draft a `KeyValueStore` külön namespaced
kulcsán él, ezért nem írhat aktív tervet; olvasási hiba `StorageFailure`, a
törlés idempotens. Egy MAJOR review-lelet javítva regressziós tesztekkel:
hibás típusú opcionális `targetDate`/`metricTarget` nem veszhet el némán.
Correctness review APPROVED, local gate és exact-SHA Full Gate + Router CI
zöld; flag/provider/UI érintetlen. Implementer `sonnet-impl`, egy javító kör.

**E99-R11 — GOV-30c-3 progress-phase decoupling** (PR
[#262](https://github.com/wolfcasaba/strumsight/pull/262), squash `e5cae94d`,
[ADR 0252](docs/adr/0252-analysis-progress-phase-decoupling.md)).
Az explicit stage-ID → `AnalysisProgressPhase` map a hét ingest és tizenegy
evaluation stage-et egyetlen élő `AnalysisPipeline<AnalysisWorkState>`-ben
futtatja; azonos fázis ismételhető, visszalépés konstrukciókor és futáskor is
tiltott. Map nélküli hívó a legacy 9-stage capet kapja. A correctness review
APPROVED, a high-risk security review F1 MAJOR-ja (hívóoldali map-mutáció)
defensive immutable snapshot + regressziós teszttel zárva PASS. Exact-SHA
CI és post-merge gate zöld. Provider és flag érintetlen. Implementer
`sonnet-impl`, egy javító dispatch.

**E99-R10 — GOV-30c-2 evaluation stage composition** (PR
[#261](https://github.com/wolfcasaba/strumsight/pull/261), squash `82cfa588`,
[ADR 0251](docs/adr/0251-analysis-target-seeding-and-evaluation-stage-composition.md)).
`AnalysisWorkState` bővítve referencia/illesztés/metrika/capability
mezőkkel; tizenegy granular evaluation-stage vékony adaptere a meglévő,
review-zott alignment/metrics/confidence modulok fölött; üres/hiányzó
referencia degradál, nem fabrikál hamis illesztést (mérve, önállóan
megismételt valódi-sértés próbával). Első dispatch `stopped` egy valós
`AnalysisPipeline<T>` stage-count-cap ütközésen, dokumentált §0.0
brief-revízióval + ADR 0251 §5-tel feloldva (composition-teszt szekvenciális
`stage.run(...)`-nal, nem `AnalysisPipeline` példányosítással); második
dispatch `done`, javító kör nélkül. Correctness review APPROVED (0
BLOCKER/MAJOR/MINOR, 4 NOTE) és dedikált security review PASS (0
CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE), mindkettő exact-SHA CI zöld.
Implementer Terra (Codex).

**E99-R09 — GOV-30c-1 PCM ingest pipeline composition** (PR
[#259](https://github.com/wolfcasaba/strumsight/pull/259), squash `cb76db0f`,
[ADR 0250](docs/adr/0250-v2-analysis-work-state-and-ingest-stage-composition.md)).
Immutable V2 work state + hét meglévő lokális engine-modul vékony adaptere;
PCM-only lánc a timeline-alapig, provider/flag érintetlen. 1 MAJOR javítva
(külső legacy evidence helyett `ClipAnalyzerStage`-ből származó evidence);
correctness és security review APPROVED, exact-SHA CI zöld. Implementer
`sonnet-impl`, 1 javító dispatch.

**E06-R28 — Cache, performance és model lifecycle** (PR
[#255](https://github.com/wolfcasaba/strumsight/pull/255), squash `d325d601`,
új [ADR 0248](docs/adr/0248-analysis-cache-key-and-performance-budget.md)).
Determinisztikus, bekötetlen V2 cache-infrastruktúra (`AnalysisCacheKey`,
`AudioFingerprint`, `AnalysisCache`, `ModelByteCache`); a benchmark
DETERMINISM_SHA256-ja bitre egyezik az R01 baseline-éval. Content review
APPROVED (0 BLOCKER/MAJOR, 2 MINOR), dedikált security review APPROVED (0
BLOCKER/MAJOR, 5 MINOR + 5 NOTE, mind latens — lásd fejléc ✅-blokk és §3).
Exact-SHA CI és post-merge gate zöld. Implementer Terra, 1 dispatch `done`,
javító kör nélkül.

> (§5 folytonossági rés E06-R19…R27 között — lásd a §4 megjegyzését fent.)

**E06-R18 — Technique proxy experimental module** (PR
[#234](https://github.com/wolfcasaba/strumsight/pull/234), squash `f2674099`,
új [ADR 0236](docs/adr/0236-analysis-technique-proxy-safety-and-naming.md)).
Lab/flag/confidence-gated proxy report, transition evidence és claim-safe
metrika-katalógus készült; UI/pipeline/persistence/V1 érintetlen. A végső
review APPROVED, a független security re-review PASS; exact-SHA CI és
post-merge gate zöld.

**E06-R10 — Event evidence modell és onset/strum timeline V2** (PR
[#225](https://github.com/wolfcasaba/strumsight/pull/225), squash `eec0aeab`,
új [ADR 0228](docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md)).
A meglévő `OnsetEvent`/`StrumEvent` additív evidence-mezőkkel bővült
(attack/RMS/confidenceSource/fallbackReason mindkét levéltípuson,
directionConfidence+onsetEventId csak StrumEventen); új `EventId`
(determinisztikus `<runId>:<type>:<sampleIndex>`) és `EventTimelineBuilder`
(`Duration`-alapú 50 ms minimum-separation, pár-atomikus suppression,
onset→strum holtverseny-sorrend); `LegacyViewAdapter` zéró kódváltozással
fogyasztja. Pre-flight egy ADR-t írt és három egymást követő, mért
brief-rést zárt (Duration vs. rögzített mintaszám; `onsetEventId`
szintetizálási szabály hiánya; rendezettségi ütközés a párszintézissel) —
mindegyiket Terra saját dispatch-e fedte fel `stopped`-dal, tiszta
munkafával, elvesztett munka nélkül. Egy negyedik dispatch `blocked`-ot
jelzett a L222 fresh-clone l10n-codegen mintázatra (orchesztrátor mulasztás,
azonnal javítva). General review első köre CHANGES REQUESTED (1 MAJOR: a
builder sosem futott a valódi kilenc R09-fixture-ön; 1 MINOR: attack/RMS
számított érték nem mérve) — a javító kör KIZÁRÓLAG két tesztet adott hozzá,
végső verdikt APPROVED. Security review PASS (0 CRITICAL/BLOCKER/MAJOR, 1
látens MINOR a jövőbeli R19-nek, 5 NOTE). Az alábbi régebbi rész történeti
kontextus.

**E06-R09 — ClipAnalyzer stage adapter és V1↔V2 parity** (PR
[#223](https://github.com/wolfcasaba/strumsight/pull/223), squash `aa41db54`,
új [ADR 0226](docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md)).
A bitre változatlan V1 `ClipAnalyzer` bekötve `ClipAnalyzerStage`-ként,
kizárólag a `runClipAnalysis` exportált belépőn át; kettős-hívásos
fallback-provenance technika (`none`/`heuristic`+ok/`crnn`); 9 fixture +
60-mintás randomizált property paritás ≤1 µs / ≤1e-9 tolerancián belül;
architektúra-allowlist bitre változatlan (12); nincs hívó, production
viselkedés bitre azonos. Pre-flight két mért brief-rést zárt dokumentáltan
(ADR 0226): a fallback-provenance mérési technika hiánya és egy hiányzó
`test/tooling` allowed_paths bejegyzés. General review APPROVED (0
BLOCKER/MAJOR/MINOR, 2 NOTE, három saját mutációs próbával igazolva),
security review PASS (0 CRITICAL/BLOCKER/MAJOR/MINOR, 5 NOTE, mind a
jövőbeli E06-R22 bekötő körre). Az alábbi régebbi rész történeti kontextus.

**E06-R08 — Preprocessing context és resampling policy** (PR
[#222](https://github.com/wolfcasaba/strumsight/pull/222), squash `d3ce39b2`,
új [ADR 0225](docs/adr/0225-analysis-preprocessing-and-resampling-policy.md)).
Immutable, native-rate/canonical PCM előfeldolgozási contract, explicit
downmix és fail-closed feature flag; nincs hívó és nincs változás a V1
Analyze/Live DSP útvonalakon. A review F1/MAJOR-ját a canonical PCM-ből
mért valós DC-onset határesettel zártuk; general review APPROVED, security
review PASS, nyitott BLOCKER/MAJOR nélkül. Az alábbi régebbi rész történeti
kontextus.

**E05-R25 — Practice Engine vision integration** (PR
[#199](https://github.com/wolfcasaba/strumsight/pull/199), squash `9b608cf`,
**ÚJ ADR 0192** practice-vision-integration-contract szerződésre (a brief
`nincs` mezője szerint az orchesztrátor írta a pre-flightban); implementer
**Codex (Terra)** (egyetlen forduló, köztes pre-flight-eredetű `stopped`
önjavítva), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `VisionPracticeContract`/
`PracticeVisionAdapter`/additív `PracticeSessionResult.vision`/önálló
`PracticeVisionDimension` widget — lásd a fejléc ✅-blokk a teljes
pre-flight/köztes-megállás/review történetért. **Pre-flight (§0.0, 8 pont)**
mérte, hogy `PracticeSessionResult`-nak nincs saját JSON-kódja (a §6 negyedik
cellája ezért revideálva), hogy a `practice → vision/public.dart` import
mindkét gépi őrrel legális, és hogy a három pilot NEM
`BuiltinPracticeCatalog`-bejegyzés. **0 javító kör**, de egy köztes `stopped`
a pre-flight SAJÁT hibájából (az ADR 0192 útvonala kimaradt az
`allowed_paths`-ból) — Terra megállás-kori munkája hibátlannak bizonyult,
egy §0.0-revízióval és UGYANAZON session folytatásával zárva. Az
orchesztrátor SAJÁT, izolált `/tmp` klónban futtatott gate-tel ÉS egy saját
falszifikációs próbával (a vision-változat `scorePoints`-ját 900→999-re
rontva a parity-fixture PIROSRA fordult, majd visszaállítva) ellenőrizte a
munkát, függetlenül az implementer önjelentésétől. A dedikált security-review
1 nem-blokkoló MINOR-t talált (a `vision/public.dart` barrel nyers
landmark/pose/geometry-típusokat is exportál a ténylegesen használt
aggregátumok mellett, szimbólum-szintű korlát nélkül) — E05-R26 pre-flight
bemenetként rögzítve (§3). Gate zöld az `fb93cb7` merge-előtti SHA-n: Full
Gate ✅ · Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó push
nem érintett trigger-útvonalat). Post-merge gate a friss `main`-en (`9b608cf`)
is zöld, 913+522 teszt. Lecke: **L188**, **L189**, **L190**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r25-practice-vision-integration-review.md) +
[security](docs/reviews/e05-r25-practice-vision-integration-security.md).

**E05-R24 — Vision session controller and realtime overlay** (PR
[#197](https://github.com/wolfcasaba/strumsight/pull/197), squash `e9257f4`,
**nincs új ADR**; implementer **Codex (Terra)** (kezdeti + **2 javító kör**),
orchesztrátor/reviewer **Claude Sonnet 5**, dedikált **security-reviewer**
ágens `risk = "high"` miatt). `VisionSessionController`/`VisionSessionState`/
`VisionSession`/`VisionSessionResult`/`VisionPreviewOverlay` — teljes
történet: [`docs/handoff-archive.md`](docs/handoff-archive.md). **2 javító
kör**: 1. kör zárta F1 BLOCKER-t (silent-null a `start()` async
acquire-ablakában) + F2 MAJOR-t (hiányos állapotgép-mátrix) + F3 MINOR-t; a
review saját próbateszttel egy ÚJ, a javítás saját regressziójaként
bevezetett F4 BLOCKER-t talált (a `dispose()` kivétellel elszállt), amit a
2. kör zárt. A dedikált security-review függetlenül ugyanarra az F1
gyökérokra jutott. **H5 self-heal** (ADR 0112, PR
[#198](https://github.com/wolfcasaba/strumsight/pull/198)): a kör saját
pre-flight `allowed_paths`-bővítése átbillentette a queue mért-motor
szabályát, Router CI kétszer pirosra futott, önjavító kör szinkronizálta a
queue-t. Gate zöld az `e069140` merge-előtti SHA-n (H5 self-heal utáni tip):
Full Gate ✅ · Router CI ✅. Post-merge gate a friss `main`-en (`e9257f4`) is
zöld, izolált klónban újrafuttatott teljes pytest suite (347/347). Lecke:
**L187**. Részletek:
[review](docs/reviews/e05-r24-vision-session-controller-and-overlay-review.md) +
[security](docs/reviews/e05-r24-vision-session-controller-and-overlay-security.md).

**E05-R23 — Feedback policy and realtime cue budget** (PR
[#196](https://github.com/wolfcasaba/strumsight/pull/196), squash `b54490e`,
**ÚJ ADR 0191** feedback-policy-és-cue-budget szerződésre (a brief előzetes
„0162" hivatkozása sosem lett fájl); implementer **Codex (Terra)** (kezdeti
+ **1 javító kör**), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `InsightCode`/
`FeedbackPolicy`/`CueBudget`/`FeedbackPolicyEngine` — lásd a fejléc ✅-blokk a
teljes pre-flight/javítókör/review történetért. **Pre-flight** mért egy
scope-rést (a safety-katalógus fájl hiányzott az `allowed_paths`-ból, a
saját doc-commentje és ADR 0188 §Következmények explicit ezt a kört nevezte
meg a bővítés végrehajtójaként) és reserválta az ADR 0191-et. **1 javító
kör**: F1 BLOCKER-t (a setup-elsőbbség nem tartott a saját cooldown alatt —
a szállított teszt saját `reason`-je a hibás viselkedést pinnelte
elvárásként) + F2/F3 MAJOR-t (a `comparisonEvidence` ungated volt; az
emittált confidence a küszöb alá eshetett) + 4 MINOR-t zárt egyszerre.
Az orchesztrátor mindkét fordulót SAJÁT, minden alkalommal friss klónon
függetlenül futtatott gate-tel ellenőrizte — az ELSŐ próba véletlenül egy
elavult (a saját pre-flight-commitra álló) klónon futott 0 új teszttel,
felismerve és korrigálva (L186). Gate zöld a `943be13` merge-előtti SHA-n:
Full Gate ✅ · Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó
push nem érintett trigger-útvonalat). Post-merge gate a friss `main`-en
(`b54490e`) is zöld, 387/387 teszt. Lecke: **L185**, **L186**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r23-feedback-policy-and-cue-budget-review.md) +
[security](docs/reviews/e05-r23-feedback-policy-and-cue-budget-security.md).

**E05-R22 — Vision observation fusion and evidence engine** (PR
[#195](https://github.com/wolfcasaba/strumsight/pull/195), squash `997e7be`,
**ÚJ ADR 0190** observation-fusion-és-evidence szerződésre (a brief előzetes
„0162" hivatkozása sosem lett fájl); implementer **Codex (Terra)** (kezdeti
+ **2 javító kör**), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `VisionObservation`/
`VisionEvidence`/`EvidenceProvenance`/`ConfidenceModel` + `ObservationFusion`
pipeline — lásd a fejléc ✅-blokk a teljes pre-flight/javítókörök/review
történetért. **Pre-flight (§0.0, 8 pont)** mérte a négy confidence-komponens
tényleges kód-forrását és pinnelte le az `ObservationState` gyártási
szabályát MIELŐTT az implementer elindult volna. **2 javító kör**: 1. kör
zárta F1 MAJOR-t (memóriakorlát csak `fuse()` mellékhatásaként érvényesült
— saját adverzális próbával 12012 megtartott observation egy sosem-fuse-olt
metrikára) + F2 MINOR-t; 2. kör zárta F4 MINOR-t (a dedikált security-review
saját leletét: `ConfidenceComponents` assert-only határ, release-ben
strippelt). Az orchesztrátor mindhárom fordulót SAJÁT, minden alkalommal
friss GitHub-klónon függetlenül futtatott gate-tel ÉS adverzális
próbatesztekkel (a review saját, nem az implementer tesztjei) újra-
ellenőrizte. Gate zöld a `c63f355` merge-előtti SHA-n: Full Gate ✅ ·
Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó push nem
érintett trigger-útvonalat). Post-merge gate a friss `main`-en (`997e7be`)
is zöld, 367/367 teszt. Lecke: **L184** (`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r22-observation-fusion-and-evidence-review.md) +
[security](docs/reviews/e05-r22-observation-fusion-and-evidence-security.md).

**E05-R21 — Audio–vision clock mapping and latency calibration** (PR
[#194](https://github.com/wolfcasaba/strumsight/pull/194), squash `7b11f26`,
**ÚJ ADR 0189** audio–vision szinkron-szerződésre (a brief előre kiosztott
0170-e a batch-írás óta elavult); implementer **Codex (Terra)** (egyetlen
forduló, `continuations=0`), orchesztrátor/reviewer **Claude Sonnet 5**).
`VisionClock`/`AudioClock` boundary + immutable `ClockMapping` (offset+korlátos
drift+confidence) + `SyncQuality` bucketek + `SyncCalibrationController`
(medián-outlier-elutasítás, opcionális lineáris drift-fit, immutable
observation-provenance recalibráció alatt) — lásd a fejléc ✅-blokk a teljes
pre-flight/review történetért. **Pre-flight (§0.0, 4 pont)** mérte a két
tényleges időalapot (vision: monotonic Stopwatch-eredetű µs; audio: wall-clock
`DateTime`) és rögzítette a boundary-konverziós tervezési szabályt egy új
§5.1-ben, MIELŐTT az implementer elindult volna. **APPROVED elsőre, javító kör
nélkül** — 0 BLOCKER/MAJOR, 4 NOTE (mind follow-up). Az orchesztrátor a gate-et
SAJÁT, izolált `/tmp` klónban futtatta újra, ÉS a §6 „valódi-sértés próba"
kritériumot egy harmadik, eldobható klónban maga is reprodukálta
(`DateTime.now()` beszúrása → a forrás-guard teszt PIROS lett, semmi más).
Gate zöld az `f1bc31a` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅
(mindkettő kézzel dispatch-elve, mert az utolsó push nem érintett
trigger-útvonalat). A Full Gate első futása egy kapcsolhatatlan, load-érzékeny
`song_import_controller_test.dart` flake-en pirosra váltott — a pristine
`main`-en 5× izoláltan reprodukálva (0/5 bukás) igazolva kör-független
flake-ként, mielőtt rerun-t futtattam. Post-merge gate a friss `main`-en
(`7b11f26`) is zöld. Lecke: **L182**, **L183** (`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r21-audio-vision-clock-mapping-review.md).

**E05-R20 — Posture metric engine and safety claim guard** (PR
[#193](https://github.com/wolfcasaba/strumsight/pull/193), squash `be38e11`,
**ÚJ ADR 0188** safety-claim-guard-ra, posture-metrika réteg ADR 0179
végrehajtása; implementer **MiniMax M3** (kezdeti + **1 javító kör**),
orchestrátor/reviewer **Claude Sonnet 5**, dedikált **security-reviewer**
ágens `risk = "high"` miatt). Négy pure-Dart proxy-metrika
(`lib/features/vision/domain/metrics/`) + fail-closed safety claim guard
(`lib/features/vision/domain/safety/`) — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **Pre-flight (§0.0, 9 pont)**
javította a stale ADR-hivatkozást, írt egy ÚJ ADR-t (0188), és beépített
egy az E05-R14 lezárt kör security-review-jából KIFEJEZETTEN E05-R20-ra
hagyott, a brief szövegéből korábban hiányzó follow-upot (R8/§5 pont 7:
`PostureObservation.state` sosem mérvadó, mert MINDIG `good`, ha akár
egyetlen landmark közös a baseline-nal). **1 javító kör** zárt 2 MAJOR-t:
a security-reviewer saját próbája (egy orvosi kód ALLOWED osztályba
deklarálva átjutott a guardon) és a saját lelet (`confidenceFormula`
dokumentáció-vs-kód ellentmondás + egy §6 acceptance-kritérium csendesen
nem teljesült). Az orchestrátor mindkét fordulót SAJÁT, friss
GitHub-klónon függetlenül futtatott gate-tel ÉS a kód közvetlen
olvasásával (nem a handoffra hagyatkozva) újra-ellenőrizte. Gate zöld a
`7ad5c49` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅ (mindkettő kézzel
dispatch-elve, mert az utolsó push nem érintett trigger-útvonalat).
Post-merge gate a friss `main`-en (`be38e11`) is zöld, 334/334 teszt.
Lecke: **L179**, **L180**, **L181** (`docs/LESSONS.md`). A dedikált
security-reviewer teljes jelentése a review-fájlba integrálva, nem külön
fájlban. Részletek:
[review](docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md).

**E05-R19 — Picking-hand stroke metric engine** (PR
[#192](https://github.com/wolfcasaba/strumsight/pull/192), squash `a38e0e0`,
nincs új ADR (ADR 0179/0181 végrehajtása a picking kézre); implementer
**MiniMax M3** (kezdeti + **1 javító kör**), orchestrátor/reviewer
**Claude Sonnet 5**). Hét pure-Dart proxy-metrika
(`lib/features/vision/domain/metrics/`) — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **Pre-flight (§0.0, 5 pont)**
korrigálta a mirror-paritás kritériumot (4→2 cella, E05-R18 F4/L176
megismétlésének megelőzése) és a picking-zóna enum hivatkozást (SDD §20.2,
nem R15 `GuitarRegion`) MIELŐTT az implementer elindult volna. **1 javító
kör** zárta F1 BLOCKER-t (`StrokeWindow.cut()` szomszédos ablakok
mintáit duplikálta gyors váltogatásnál — a review saját, eldobható
próbateszttel reprodukálta ÉS a javítás után újra megerősítette). Az
orchestrátor mindkét fordulót SAJÁT, friss GitHub-klónon függetlenül
futtatott gate-tel ÉS eldobható mutáció-próbákkal (a review saját, nem az
implementer tesztjei) újra-ellenőrizte. Gate zöld a `79c4f49`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Post-merge gate a friss
`main`-en (`a38e0e0`) is zöld, 292/292 teszt. Lecke: **L177**, **L178**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r19-picking-hand-stroke-metrics-review.md).

**E05-R18 — Fretting-hand metric engine** (PR
[#191](https://github.com/wolfcasaba/strumsight/pull/191), squash `75f8766`,
nincs új ADR (ADR 0179/0181 végrehajtása); implementer **MiniMax M3**
(kezdeti + **2 javító kör**), orchestrátor/reviewer **Claude Sonnet 5**).
Hat pure-Dart proxy-metrika (`lib/features/vision/domain/metrics/`) — lásd
a fejléc ✅-blokk a teljes pre-flight/javítókörök/review történetért.
**2 javító kör**: 1. kör zárta BLOCKER-1/F1 (`readyPositionTime`
szerep+visibility-kapu hiánya) + F2/F3/F5 MAJOR; 2. kör (szűkre skálázva)
zárta F4 MAJOR-t (a szállított „4 cellás" paritás teszt bitre azonos
bemenettel semmit nem bizonyított). Az orchestrátor mindhárom fordulót
SAJÁT, minden alkalommal friss GitHub-klónon függetlenül futtatott
gate-tel ÉS eldobható mutáció-próbákkal (a review saját, nem az
implementer tesztjei) újra-ellenőrizte. Gate zöld a `77d6ee0`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Post-merge gate a friss
`main`-en (`75f8766`) is zöld, 225/225 teszt. Lecke: **L175**, **L176**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r18-fretting-hand-metric-engine-review.md).

**E05-R17 — Automatic guitar detector go/no-go decision** (PR
[#189](https://github.com/wolfcasaba/strumsight/pull/189), squash
`e979d41`, **ADR 0187** (új); implementer **MiniMax M3** (kezdeti + 1
javító kör), orchestrátor/reviewer **Claude Sonnet 5**). Go/no-go/
experimental-only döntési keret egy jövőbeli automatikus gitár/nyak-
geometria detektorhoz (nem épít detektort) — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review/önjavítás történetért. **1 javító kör**:
BLOCKER-1 (a `decision()` promóciós logika inverz irányú egy
hiba-metrikán) + MAJOR-1 (dedikált security-review lelete: consent-séma
6/7 kötelező mező). Gate zöld a `8e71e80` merge-előtti SHA-n: Full Gate ✅
· Router CI ✅. A merge utáni closing-rituálokat egy H-NOSIGNAL szakította
meg, self-heal PR #190 zárta. Lecke: **L173**, **L174**. Részletek:
[`docs/handoff-archive.md`](docs/handoff-archive.md) +
[review](docs/reviews/e05-r17-auto-guitar-detector-decision-review.md).

**E05-R16 — Guitar geometry tracking és calibration loss** (PR
[#188](https://github.com/wolfcasaba/strumsight/pull/188), squash
`6f9c0e1`, nincs új ADR (ADR 0179/0181 bővítése); implementer **MiniMax
M3** (kezdeti + 1 javító kör), orchestrátor/reviewer **Claude Sonnet 5**).
`GeometryTracker`/`EdgeGeometryTracker` (könnyű él-/feature-alapú adapter,
nem ML) + `GeometryConfidence` (drift + confidence) + `CalibrationLossMachine`
(`tracking`→`degraded`→`lost` hiszterézises állapotgép) — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review történetért. **1 javító kör**: BLOCKER-1 (a
tracker `null`-refusala halott kóddá tette a gép SAJÁT, helyesen
implementált forward-escalation logikáját a valódi integrációban — egyik
egységteszt sem kötötte össze a két komponenst) + MINOR-1 (dedikált
security-review lelete: `GeometryConfidence` csak `assert`-tel
validált, release-módban nem futott volna). Az orchestrátor mindkét
lezárt leletet SAJÁT, függetlenül futtatott gate-újrafuttatással ÉS egy
a MiniMax tesztjeitől független eldobható próbateszttel újra-ellenőrizte.
Gate zöld a `43a7bc2` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅.
Post-merge gate a friss `main`-en (`6f9c0e1`) is zöld. Lecke: **L172**
(`docs/LESSONS.md`). Részletek:
[`docs/handoff-archive.md`](docs/handoff-archive.md) +
[review](docs/reviews/e05-r16-geometry-tracking-and-calibration-loss-review.md).

**E05-R15 — Guitar coordinate system és homography** (PR
[#187](https://github.com/wolfcasaba/strumsight/pull/187), squash
`a351ad3`, nincs új ADR; implementer **MiniMax M3** teljes egészében —
javító kör 2 a Codex CLI usage-limit önjavítása után user-döntéssel
folytatva ugyanazon a leleten —, orchestrátor/reviewer **Claude Sonnet 5**).
Pure Dart geometriai mag (`Point2`/`Polygon2`/`Homography`/`GuitarSpace`) +
`GuitarLandmarkMapper`/`GuitarRegion` — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **2 javító kör**: MAJOR-1
(`Polygon2.contains` előjel-hiba) + MAJOR-2 (hiányzó side/top fixture-ök)
javító kör 1-ben; BLOCKER-1 (kondíciószám-őr vak a projektív sorra) HÁROM
tervezési iteráción át javító kör 2-ben, mindegyiket egy implementer
helyes `stopped` jelzése zárt (nem hiba) — a végleges megoldás közvetlen
`|uv|`-magnitúdó ellenőrzés, nem küszöb-proxy. Az orchestrátor mindhárom
lezárt leletet SAJÁT, függetlenül futtatott gate-újrafuttatással ÉS egy
valódi-sértés (mutáció) próbával újra-ellenőrizte, nem az implementer
önjelentésére hagyatkozva. Dedikált security-review (risk=high) — innen
indult a BLOCKER-1. Gate zöld a `6b2f854` merge-előtti SHA-n: Full Gate ✅
· Router CI ✅. Post-merge gate a friss `main`-en (`a351ad3`) is zöld.
Lecke: **L171** (`docs/LESSONS.md`), **L27 megerősítve**. Részletek: fejléc
✅-blokk +
[review](docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md) +
[security](docs/reviews/e05-r15-guitar-coordinates-and-homography-security.md).

**E05-R14 — Pose landmark provider és posture baseline** (PR
[#185](https://github.com/wolfcasaba/strumsight/pull/185), squash
`efa4bbe`, **ADR 0186** (új, ADR 0178/0185 kiterjesztéseként); implementer
**MiniMax M3** (kezdeti + javító kör 1) → **Codex/Terra** (javító kör 2,
motor-eszkaláció), orchestrátor/reviewer **Claude Sonnet 5**).
Adatminimalizált felsőtest-pose pipeline arcelemzés nélkül — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review történetért. **2 javító kör**: F1 MAJOR
(hamis „format: ZÖLD" önjelentés) + S-MAJOR-1 MAJOR (privacy-audit gépi
őr fedezete gyengébb volt, mint ígért), mindkettő az orchestrátor SAJÁT
próbáival újra-ellenőrizve. Dedikált security-review (risk=high) **PASS**
(S-MAJOR-1 fixed). Gate zöld a `fe9d756` merge-előtti SHA-n: Build APK ✅
· Router CI ✅. Lecke: **L167, L168, L169**. Részletek:
[docs/handoff-archive.md](docs/handoff-archive.md) +
[review](docs/reviews/e05-r14-pose-provider-and-posture-baseline-review.md) +
[security](docs/reviews/e05-r14-pose-provider-and-posture-baseline-security.md).

**E05-R13 — Hand track assignment és temporal smoothing** (PR
[#184](https://github.com/wolfcasaba/strumsight/pull/184), squash
`148469c`, nincs új ADR; implementer **MiniMax M3**, orchestrátor/reviewer
**Claude Sonnet 5**). Stabil fretting/picking hand-track jitter és rövid
takarás ellen — lásd a fejléc ✅-blokk a teljes pre-flight/javítókör/review
történetért. **1 javító kör** (MiniMax), mindhárom lelet (F1 BLOCKER — a
jump-rejection nem épült fel valós, tartós pozícióváltásból; F2 MAJOR — a
`TrackContinuity` latency/jitter mezői élettelenek voltak; F3 MINOR — a
simított visibility monoton MAX volt) az orchestrátor SAJÁT, függetlenül
futtatott próbateszteivel újra-ellenőrizve, nem az implementer
önjelentésére hagyatkozva. Dedikált security-review (risk=high) **PASS**,
futott a merge ELŐTT (L162 helyesen alkalmazva). Gate zöld a `2ef9455`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Lecke: **L165, L166**.
Részletek: fejléc ✅-blokk +
[review](docs/reviews/e05-r13-hand-track-assignment-and-smoothing-review.md) +
[security](docs/reviews/e05-r13-hand-track-assignment-and-smoothing-security.md).

**E05-R10 — Camera + guitar calibration domain és verziózott tárolás**
(PR [#181](https://github.com/wolfcasaba/strumsight/pull/181), squash
`39d1c29`, nincs új ADR; implementer **MiniMax M3**, orchestrátor/reviewer
**Claude Sonnet 5**). Verziózott kalibrációs domain (kamera + gitárgeometria)
öt-cellás validity-mátrixszal és determinisztikus, migrálható JSON codeckel.
**Örökség-eset** (ADR 0087 §0.2): pre-flight+implementáció egy korábbi,
jelzés nélkül megszakadt sessionből örökölve. **3 javító kör**, mindegyik az
orchestrátor saját mutáció-kill próbáival függetlenül újra-ellenőrizve: (1)
MiniMax — F1 hiányzó falszifikáció a migrációs mátrix vN+1 cellájában (csak
a meglévő envelope-őrt mérte, nem a kör saját codec-szintű őrét) + F2
`neckPolygon` nem valódi immutable; (2) Codex — dedikált security-review
MAJOR-1: `ArgumentError` (nem `Exception`) megszökik a `read()`
`on Exception` őrén korrupt orientationre, crash karantén helyett; (3)
Codex — MAJOR-2, az orchestrátor SAJÁT felfedezése MAJOR-1 javításának
újra-ellenőrzése közben: öt kézzel írt teszt (a MiniMax eredeti köréből
négy, a MAJOR-1 regressziós cellája az ötödik) a hiányzó belső
`schemaVersion` mező miatt csendben a legacy migrációs ágra tévedt, mindegyik
véletlen okra bukva — az acceptance #4/#7 az aktuális (nem-legacy) útra
bizonyítatlan maradt egészen eddig. Review **APPROVED**; dedikált
security-reviewer **PASS**. Gate zöld a `40a3d44` merge-előtti SHA-n:
Full Gate ✅ · Router CI ✅. Lecke: **L160**. Részletek: fejléc ✅-blokk +
[review](docs/reviews/e05-r10-calibration-domain-and-store-review.md) +
[security](docs/reviews/e05-r10-calibration-domain-and-store-security.md).

**E05-R07 — Frame transform és overlay koordinátarendszer** (PR [#169](https://github.com/wolfcasaba/strumsight/pull/169), squash `b5837d9`, nincs új ADR; implementer **Terra**, orchestrátor/reviewer **Claude Sonnet 5**). Pure Dart koordináta-transzformáció-réteg (`CameraTransform<From, To>`, `CameraCoordinateSpace`, `PreviewFit`) a sensor→upright→normalized→preview→overlay terek között. 1 javító kör (F1/MAJOR: az overlay-mapping a brief §1 célja szerint kötelező volt, de eredetileg elérhetetlen maradt — `CameraTransform.previewToOverlay()` identitás-transzformmal zárva). Review **APPROVED** javító kör után; dedikált security-reviewer **PASS** (1 carry-forward MAJOR — assert-only validáció — kötelező R13/R15/R24 előtt). Gate zöld a `9c52d74` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Részletek: fejléc ✅-blokk + [review](docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-review.md) + [security](docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-security.md).

**E05-R01 — Vision baseline, capability audit & hat alapozó ADR** (PR [#162](https://github.com/wolfcasaba/strumsight/pull/162), squash `cef864c`, **hat új ADR: [0178](docs/adr/0178-vision-privacy-by-default.md)–[0183](docs/adr/0183-vision-no-raw-frame-persistence.md)**; implementer **DeepSeek v4 Pro**, az ADR-eket az orchestrátor (**Claude Opus 4.8**, ADR 0055) írta a pre-flightban). Az Epic 5 (Computer Vision) INDUL: mérhető baseline (nyers parancs+kimenet), kétoszlopos metrika-lista, device-mátrix/benchmark sablon és a hat kötelező vision architekturális döntés. **Production kód NEM változott** (docs-only Kör 1). Review **APPROVED** javító kör nélkül (0 BLOCKER/MAJOR/MINOR, 1 NOTE). Gate zöld a `7a9d9e0` merge-SHA-n: Full Gate ✅ · Router CI ✅. Lecke: **L143**. Részletek: fejléc ✅-blokk + [review](docs/reviews/e05-r01-vision-baseline-and-adrs-review.md).

**E04-R23 — Tutor safety, prompt-injection, usage & evaluation gate** (PR [#159](https://github.com/wolfcasaba/strumsight/pull/159), squash `04787fa`, **ADR [0177](docs/adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md)**; implementer **DeepSeek v4 Pro** (`deepseek/deepseek-v4-pro`, Kilo-profil), orchestrátor/reviewer **Claude Opus 4.8**).

**Elkészült:** a tutor production-rollout előtti formális kapui — safety-policy (strictest-wins kategória → verdikt), claim-provenance validator (R16 grounding-taxonómia **újrahasználva**, invented-metric hard blokk), backend safety+redaction+size-guard, evaluation CLI + adversarial/capability dataset + `tutor-eval.yml` merge-gate **négy géppel számított** metrikára (schema/action/groundedness/safety). Injection nem emel tool-permissiont; CI fake/approved provider (nincs cloud-secret).

**Falszifikációs cellák (kipinnelve):** minden safety-kategóriához input→block/refuse unit-cella; invented-metric hard blokk (`unsupportedClaimEvidence`); injection-no-permission dataset-cella; a küszöb-mátrix below/at/above hármasa. Piros-út bizonyítva: `dart run … run_eval.dart` küszöb alatti dataseten safety_coverage 94% → exit 1; tiszta dataseten 100% → exit 0.

**Javító kör (1, DeepSeek) + orchestrátor scope-akciók:** 3 MAJOR zárva — ruff-check red (import-sort+F401, `8ed8db5`), hardcode-olt schema/action metrikák → tényleges dataset-számítás (`aeca3fe`), dispatchelt zöld + reprodukált piros evidencia. Orchestrátor: `public.dart` **scope-szűkítés** vissza az üres baseline-re (a merge-elt E04-R01 boundary-guard miatt, export halasztva; `3d93839`) + backend `ruff format` (`0dd9ed7`). Re-review **APPROVED**; security review **PASS** (0 BLOCKER). Gate zöld a `0dd9ed7` merge-SHA-n: Full Gate ✅ · Router CI ✅ · Backend CI ✅.

_(A korábbi körök részletes története: [`docs/handoff-archive.md`](docs/handoff-archive.md) — E04-R22 és korábbiak; E04-R22 összefoglalója a fejléc ✅-blokkjaiban.)_

**E04-R22 — Tutor Profile, Privacy, Data & Consent UI** — KÉSZ (PR #157, `faa3f32`, nincs új ADR — ADR 0132+0134 hatálya; MiniMax M3; ld. fejléc ✅-blokk).

## 6. Exact next task

**Pontos következő termékkör (2026-08-23): E09-R09 — Profilkeresés és
biztonságos discovery** (`docs/rounds/e09-r09-profile-search-and-discovery.md`,
engine a queue-ban `minimax`, előre kiosztott ADR a queue-fájlban `nincs` —
a pre-flight a §1.0.1 szerint kérjen számot
`tools/round-slots.py reserve-adr --round E09-R09`-cal). **Az E09-R08
(Block, mute és safety kapcsolatkezelés) KÉSZ** (PR #417, squash
`5e086c10`) — lásd a fejléc ✅-blokkot. A Kör 8 mérte, hogy
`profile.py::read_profile`/`privacy.py::get_privacy`/`handles.py` két
GET-je MA authentikáció nélküliek (nincs `CurrentUser`), és ezt szándékosan
kihagyta a block-szűrésből (D2, ADR 0402) — a Kör 9 pre-flightja mérje meg,
igényel-e a keresés/discovery felület authentikációt ezekhez (vagy a Kör 9
saját, ÚJ endpointokat ad, amik már `CurrentUser`-esek, és a régi
`read_profile`/`get_privacy` authentikáció-hiánya továbbra is nyitott
follow-up marad). A Kör 8 `query_filters.py::is_blocked_pair` pure-helperje
a Kör 9 keresési eredményekből is ki kell zárja a blokkolt profilokat — a
Kör 9 brief-jének explicit hivatkoznia kell erre a függvényre, ne írjon
saját, párhuzamos block-ellenőrzést. **Az Epic 8 (Gamification) mind a 30
köre KÉSZ** (E08-R30, PR #407) — az **E08-R29** (Integritás, analytics,
balance szimuláció és CI) továbbra is `hold`-on marad. A queue-scan a
legelső `pending` sort választja. Ez a session nem indítja el; új
sessionben fut.

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E09-R08 — Block,
mute és safety kapcsolatkezelés** (`docs/rounds/e09-r08-block-mute-and-safety-relationships.md`,
engine a queue-ban `minimax`). Lásd a fejléc ✅-blokkot.

**F1/F2 nyitott MINOR-ok az E09-R04 review-ból** (backend
`update_privacy_settings` router-bekötő kör előfeltételei — Python-szintű
TOCTOU + félrevezető docstring, `docs/handoff-archive.md` E09-R04
szakasza), **és a Kör 5 wire-decode mintája** (minden ÚJ Community
wire-enum kapjon `xFromWire`/`xToWire` párt a bevezetéssel EGY körben, ne
utólag — Kör 5 F1 pontosan ezt mérte meg `ModerationState`-en) továbbra is
a jövőbeli bekötő/data-réteg körök előfeltétele.

Pre-flightban érdemes újra mérni: az Epic 9 (Community Platform) mind a 32
körének briefje egy batchben készült (PR #405, 2026-08-22) — az E09-R01
saját pre-flightja ellenőrizze, hogy a `main` időközbeni mozgása (E08-R29/
R30 stb.) nem driftelt-e el olyan fájltól/enum-értéktől, amire a batch-elt
brief hivatkozik (a §1 mérési szabály: grep-eld ki a hivatkozott
enum-értékeket/mezőket a tényleges kódból, ne az átmenettáblát mérd).

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E08-R30 — Epic 08
migráció, regresszió és lezárás** (`docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md`,
engine a queue-ban `minimax`). Lásd a fejléc ✅-blokkot. Vegye figyelembe az
E08-R28 mért tanulságait:

- **A wire-szerződés két fele (Dart-kódoló + backend-dekódoló) KÜLÖN
  implementer-diffben könnyen szétcsúszik, még akkor is, ha ugyanaz a kör
  írja mindkettőt** — az E08-R28 F1 MAJOR-ja pontosan ezt mutatta: mindkét
  oldal SAJÁT gate-je zöld volt, mert egyik sem tesztelte a MÁSIK oldal
  tényleges kimenetét. Ha egy jövőbeli kör (a router-mounting follow-up)
  élesíti ezt a szerződést, a pre-flight ELSŐ lépése egy kézzel futtatott
  `LedgerUploadEnvelope.model_validate(<a Dart encodeUpload() aktuális
  kimenete>)` ellenőrzés legyen — ne a két oldal külön-külön zöld gate-jére
  hagyatkozzon.
- **A `verified` ma séma-érvényességet jelent, NEM XP-újraszámolást**
  (dedikált biztonsági review N1 lelete, `docs/reviews/e08-r28-security.md`).
  Mielőtt bármely jövőbeli felület a `verified` mezőt bizalmi jelzésként
  mutatná, a szervernek ténylegesen vissza kell vezetnie az XP-t a
  forrás-eseményből — a mai `evaluate_upload` minden séma-érvényes nyugtát
  `verified`-nek jelöl, felső XP-korlát vagy policy-alapú újraszámolás nélkül.
- **Nincs `max_length` a nyugta-listán/id-mezőkön** most már javítva (F2),
  de a mintázat (kliens-adatot fogadó pydantic séma felső korlát nélkül)
  minden jövőbeli, `backend/app/`-ot bővítő körnél ellenőrizendő.
- Egy önkezűen létrehozott ÜRES `backend/.venv` beárnyékolja a
  `tools/round-gate.sh` közös venv-fallbackját (L408) — ha a backend gate
  `ModuleNotFoundError`-ral hasal el, ELŐSZÖR ellenőrizd, hogy a munkapéldány
  saját `backend/.venv`-je létezik-e és NEM üres-e.

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E08-R28 —
Ledger sync contract és merge.** Lásd a fejléc ✅-blokkot.

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E08-R27 —
Gamification accessibility és settings.** Lásd a fejléc ✅-blokkot.

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E08-R26 —
Cross-feature gamification integration** (`docs/rounds/e08-r26-cross-feature-gamification-integration.md`,
engine a queue-ban `minimax`). Lásd a fejléc ✅-blokkot.

**Korábbi kijelölt SDD-kör (2026-08-22, azóta lezárult): E08-R25 — Song
Trainer és Setlist integráció** (`docs/rounds/e08-r25-song-trainer-and-setlist-integration.md`,
engine a queue-ban `minimax`). Lásd a fejléc ✅-blokkot.

**Korábbi kijelölt SDD-kör (2026-08-21, azóta lezárult): E08-R19 — Challenge V2 és legacy
DailyChallenge migráció** (`docs/rounds/e08-r19-challenge-v2-and-legacy-migration.md`,
engine a queue-ban `terra`). Ez a session nem indítja el; új sessionben fut.
Az önálló Chapter 13 sáv következő köre E13-R05.

**Pontos következő Chapter 13 kör: E13-R05 — Spacing, radius, elevation és
surface primitives** (`docs/rounds/e13-r05-spacing-and-surfaces.md`, engine a queue-ban
`terra`). Az E08 terméksáv önálló queue-ja ettől függetlenül halad; ezt a
session nem indítja el. A governance-sáv következő sora, **E99-R23**, jelenleg
`hold`.

**Nyitott, EMBERI döntést NEM igénylő tartozás (2026-08-20, E08-R08 review):**
a watch-stream (`LocalGamificationRepository.watchProfileSnapshots`)
optimistán sugározza a kért értéket, mielőtt a `JsonDocumentStore.write()`
tényleges sikerét ellenőrizné — egy elnyelt platform-írási hiba esetén a
figyelő a ténylegesnél frissebb (esetleg nem is perzisztált) profilt látná
egy session erejéig. Meglévő, projektszintű kockázat öröklődik (egyetlen
`JsonDocumentStore`-alapú írás sem különbözteti meg ma a sikeres és az
elnyelt írást a hívó felé), NEM új regresszió — de a Kör 9/10 migráció vagy
egy jövőbeli gamification-UI kör előtt érdemes rendezni: a stream a
ténylegesen visszaolvasott állapotot sugározza a bemeneti érték helyett.
Lásd `docs/reviews/e08-r08-review.md` N1.

**Korábbi kijelölt SDD-kör (2026-08-20, azóta lezárult): E08-R08**
(Gamification repository és storage schema, SDD Chapter 9). Lásd a
fejléc ✅-blokkot.

**Nyitott, EMBERI döntést NEM igénylő, de a következő pár körben érdemes
tartozás (2026-08-20, E08-R07 review):** a `docs/reviews/e08-r07-review.md`
F1–F3 mintája — egy zöld gate/teszt-suite mögött is lehet teszteletlen guard
vagy garantáltan-zöld guard-teszt; a review-protokoll (mutációs próba a
guard-on, NEM csak a mért kódon) e nélkül nem fogta volna meg. Lásd
[[L349]]–[[L351]] a `docs/LESSONS.md`-ben — jövőbeli review-k „X sosem
csökkenhet/gyengülhet" jellegű brief-előírásainál alkalmazzák ugyanezt a
mintát alapból, ne csak utólag.

**Korábbi kijelölt SDD-kör (2026-08-20, azóta lezárult): E08-R04** (Activity
outbox és megbízható feldolgozás, SDD Chapter 9 —
`docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md`, engine
`codex`, előre kiosztott ADR `0302`). Lásd a fejléc ✅-blokkot.

**Nyitott, EMBERI döntést igénylő tartozás, E08-R02-ből örökölve, még
mindig releváns:** a `docs/reviews/e08-r02-security.md` MINOR-1 lelete — az
architektúra-guard marker-listája nem fed hálózati/fájl-IO markert
(`dart:io`/`dart:convert`/`package:dio/`/`package:http/`). Ma nem aktív
sértés, de az outbox (E08-R04) valódi hálózati/tárolási sink-szomszédot hoz
a gamification domain mellé — érdemes ELŐTTE rendezni.

**Nyitott, EMBERI döntést igénylő tartozások, Epic 7-ből örökölve:**

- (2026-08-19, E07-R30 completion report + security review NOTE-2) a
  `GenerationOrchestrator.generate()` továbbra is egyetlen hívásban
  fuzionálja a validálást/javítást az aktiválással — egy jövőbeli
  preview-confirmation / valódi rollout implementáló körnek külön kell
  választania, mielőtt perzisztáló activation bekötődik.
- (2026-08-19, E07-R30 completion report) `practiceGeneratorEnabled` és
  `plannerAssistEnabled` bekapcsolása emberi release-döntés, a release gate
  után; a teljes CI-suite/property/APK továbbra is kötelező merge-evidencia,
  ezt a helyi golden-korpusz mérés NEM helyettesíti; valós Android-eszközös
  offline flow és eszköz-specifikus latency/memória baseline hátravan.
- (2026-08-19, E07-R28 pre-flightja fedte fel) az E07-R27 (PR #328)
  `risk=high` briefje mellett a kötelező biztonsági review sosem készült el
  (`docs/reviews/e07-r27-security.md` hiányzik) — egy jövőbeli kör vagy
  emberi döntés pótolhatja retroaktívan.

**Korábbi kijelölt SDD-kör (2026-08-19, azóta lezárult): E07-R29**
(Accessibility, localization, privacy és safety hardening, SDD Ch8 Kör 29).
Lásd a fejléc ✅-blokkot.

**Nyitott, EMBERI döntést igénylő tartozás (2026-08-19, E07-R28 pre-flightja
fedte fel):** az E07-R27 (PR #328) `risk=high` briefje mellett a kötelező
biztonsági review sosem készült el (`docs/reviews/e07-r27-security.md`
hiányzik) — egy jövőbeli kör vagy emberi döntés pótolhatja retroaktívan.

**🛑 [ELAVULT, MEGOLDVA] A lánc jelenleg ÁLL...** — az alábbi bekezdés
E99-R16/H3-ra vonatkozott; az ADR 0321 (H-GATEGUARD kör-szintű hold, ld. a
fejléc-blokkot fentebb) és a család-glob javítás (PR #324) azóta feloldotta,
a lánc E07-R27/R28-cal folytatódott. Megtartva történeti kontextusnak:

**A következő Epic 7 SDD-lépés: E07-R26** (outcome ingestion és revision).
Friss sessionben indul; az E07-R25 eredményét csak a szűk public boundary-kon
át használhatja, és a nyers audio-/kamera-adat tilalma változatlan.

**A soron következő SDD-lépés: E07-R22** (Chapter 8, Weekly Plan és Today
screen). A friss session pre-flightban mérje újra az R21 preview ma még
fixture-alapú aktiválási határát: a `GenerationOrchestrator.generate()` továbbra
is egyetlen hívásban validál/javít/aktivál, tehát a valódi
generation→preview bekötés továbbra is külön follow-up. A R22 csak az aktív
tervhez tartozó használati felületét vegye fel; `practiceGeneratorEnabled` és
`plannerAssistEnabled` flagek változatlanul `false` maradnak.

**Korábbi kijelölt SDD-kör (2026-08-18, azóta lezárult): E07-R20 — Plan
setup wizard és input UX** (Chapter 8, Kör 20). Lásd a fejléc ✅-blokk.

**Korábbi kijelölt SDD-kör (2026-08-18, azóta lezárult): E07-R19 —
Local repository, migráció és korrupcióvédelem** (Chapter 8, Kör 19). Lásd
`docs/handoff-archive.md`.

**Korábbi kijelölt SDD-kör (2026-08-18, azóta lezárult): E07-R18 —
GenerationOrchestrator, progress és cancellation** (Chapter 8, Kör 18). Lásd §4.

**Egyéb, Epic 7-től FÜGGETLEN, EMBERI döntést igénylő irányok** (az Epic 6
completion report `docs/sdd/epic-06-completion-report.md` „Nyitott tételek"
táblája nevezi meg, változatlan az E06-R30 óta — a GOV-30c mind az öt
lépcsője kész az E99-R13 óta, lásd `docs/handoff-archive.md`):

1. **Valódi eszközös elfogadás** — a 14 pontos Kör 30 lista + a teljes
   `docs/manual-testing/analysis-eval-matrix.md` PENDING sorai (EVAL-01…41,
   Epic 5 device-mátrix is még nyitott) — user-feladat, real gitáros
   teszt.
2. **GOV-30a** — valódi kalibrációs dataset/riport (ma `identity.v1`,
   szintetikus).
3. **GOV-30b** — az R29 evaluation CI-lépés bekötése (`.github/workflows/**`,
   `tool/ci/**` — ez a fájlkör szándékosan tilos zóna minden eddigi GOV-30c
   körben, H-GATEGUARD).
4. **Opt-in/default-on rollout és a V1 kivezetése** — külön, jóváhagyott
   GOV-kör, Product/User döntés (a GOV-30c lezárása óta sem lett elfogadva
   semmilyen flag `true`-ra állítása, sem az Epic 6, sem az Epic 7 flagjeire).
5. **GOV-05b bekötő köre** (AI Tutor `main.py` OpenAI-adapter bekötés) —
   régóta nyitott track, brief-je még nincs megírva (ld. lent, változatlan).

Egyik irány sem automatikusan folytatható a queue-ból — mindegyik vagy
emberi döntést, vagy egy még meg nem írt briefet igényel. **A pipeline a
következő session-ben NE találjon ki magától egy irányt** — kérdezze meg a
usert, melyik legyen a következő SDD-kör vagy GOV-kör.

> (A lenti, E06-R19-cel kezdődő szakasz a 2026-08-12 előtti GOV-05/06
> governance-sagát rögzíti — történeti kontextusként hagyva.)

**Korábbi kijelölt SDD-kör (2026-08-12, azóta lezárult): E06-R19 —
Confidence calibration és capability resolver** (Chapter 7, Kör 19). Új
sessionben induljon; E06-R18 lezárult.
Pre-flightban az új technique-proxy contractot, a flag/Lab kaput és minden
confidence-producer tényleges elérhetőségét újra mérje.

> ### 🔒 Kötelező sorrend az Epic 5 után (user-döntés, 2026-08-07)
>
> **„várjuk meg amíg az Epic 5-tel végzünk, majd csináljuk a shipping kört
> először, majd egy valós audio mérés, és csak ezek után lépjünk az Epic 6-ra."**
>
> 1. ~~**Epic 5 befejezése**~~ — ✅ **KÉSZ** (E05-R30, `d3b2caf9`).
> 2. ~~**Az Epic 5 APK-ellenőrzése** a usernél~~ — **KIHAGYVA, user-döntés
>    2026-08-09** („mehet a 3. 4. pont"). Mért indok: a 11 vision flag
>    hard-kódolt `false` volt minden környezetben, tehát egy akkori APK-menet
>    csak regressziót tudott volna mérni, a vision-t nem. A készülékes
>    bizonyíték a GOV-05a/b/c rollout-körök device-mátrix sorain gyűlik.
> 3. **GOV-05 — Shipping rollout.** **HÁROM körre bomlott** (orchesztrátor-
>    döntés 2026-08-09; mért indok a 3.0 pontban):
>    - **GOV-05a** = `E99-R01` — Practice V2 + Song Trainer V2 → ✅ **KÉSZ**
>      (PR #205, `d958b75e`, ADR 0197).
>    - **GOV-05b** = `E99-R02` — **AI Tutor internal rollout → ⛔ BLOKKOLT,
>      EMBERI DÖNTÉST IGÉNYEL** (mérve 2026-08-09, lásd §3 „AI Tutor
>      production-drótozás"). NEM indítható, amíg a döntés nincs meg.
>    - **GOV-05c** = `E99-R03` — **Learn migráció** (`migratedLearnEnabled`).
>      A legkockázatosabb: egy MÁR szállított feature mögött cseréli a motort.
>      Meglévő őrök: `test/features/learn/learn_migration_parity_test.dart`,
>      `learn_rollback_test.dart`; az `AppConfig.resolve` már kényszeríti a
>      `practiceEngineV2Enabled` függőséget.
> 3.0 **Miért három kör, és miért NEM tartalmazza a vision-t.** Két mérés
>    döntötte el, mindkettő `main @ bbc95187`-en:
>    (a) **Belépési pontok:** a flag-gated route-okra **nulla** hivatkozás
>    mutatott a `lib/`-ben, tehát minden feature-családhoz külön UI-mozdulat
>    kell — három család egyszerre nem lenne review-zható, és egy készülékes
>    hiba nem lenne betudható.
>    (b) **A vision rollout BLOKKOLT** (→ **GOV-05d**, lásd §3): az
>    `assets/ml/model_manifest.json` `vision_models` mindkét bejegyzése
>    (`hand_landmarker`, `pose_landmarker`) `status: "deferred"`, `sha256`
>    csupa nulla, és a hivatkozott `.tflite` fájlok **nincsenek a repóban**
>    (`ls assets/ml/` → négy audio `.bin` + a manifest). A
>    `NativeHandLandmarkProvider:77` / `NativePoseLandmarkProvider:76`
>    `deferred` bejegyzésre `AppResult.failure`-t ad, tehát a `visionEnabled`
>    bekapcsolása egy zsákutcába futó setup-folyamatot tenne láthatóvá. A
>    flag-flip előfeltétele a modell-binárisok beszerzése + licenc-átvezetés.
> 4. ~~**GOV-06 — Valós-audio DSP baseline mérés.**~~ — ✅ **KÉSZ** (E99-R04,
>    `5ceed22d`; BPM-metrikája javítva **GOV-06b, E99-R05, `c4ce2cc0`**). A
>    meglévő shipping DSP pontossága valódi gitárfelvételeken: akkord-
>    pontosság **67,069%** (18,832%-os baseline fölött), onset F1@50ms
>    **67,391%**. A harmadik szám (a GOV-06 eredeti, `.strums`-alapú
>    „BPM-MAE 45,067") **érvénytelennek bizonyult és visszavonva** (GOV-06b) —
>    a helyette mért független (librosa) tempó-egyezés **11/82 = 13,415%**
>    szigorú / **32/82 = 39,024%** metrikai-szint toleráns; a BPM ezen a
>    korpuszon validált kézi annotáció híján **nem mérhető**. A korpusz
>    (`ml/data/klangio/`, 82 felvétel) NEM verziókövetett — a mérés
>    elkötelezett riport, nem CI-kapu; a verziókövetés nevesített follow-up.
>    Teljes riport: [`docs/eval/real-audio-dsp-baseline.md`](docs/eval/real-audio-dsp-baseline.md).
> 5. ~~**Csak ezután Epic 6**~~ — ✅ **FELOLDVA, user-döntés 2026-08-11**
>    („mehet tovább az epic 6"): a 3. ÉS 4. pont lezárult (2026-08-09), az
>    5. pont feltétele teljesült, mind a 30 Epic 6 sor `hold`→`pending`
>    (`docs/execution/pipeline-queue.tsv`, `7d5bfd4a`). **E06-R01** (Epic 6
>    Kör 1: V1 baseline + hat kötött ADR) ✅ **KÉSZ** — lásd a fejléc
>    ✅-blokk. A lánc a szokásos módon folytatható, `PIPELINE_SLOTS=1`
>    (user-döntés 2026-08-11: „nem kell dupla kör haladunk sorban").
>
> A GOV-05b/GOV-05c/GOV-06 briefje **szándékosan még nincs megírva**: mindegyik
> pre-flightjának az ELŐZŐ kör utáni állapotot kell mérnie (mind ugyanazt a
> `feature_flags.dart` / `lesson_list_screen.dart` felületet érinti, tehát az
> előre írt fájllisták ütköznének és avulnának). Az Epic 6 queue-sorai
> addig is `hold`-on védik a sorrendet.
>
> **Governance-kör azonosítás:** a GOV-körök `E99-RNN` alakot kapnak, mert a
> `tools/ai_router/brief.py:19` és a `tools/round-pipeline.sh:278` mintája a
> „GOV-05a" alakú nevet kiejtené a gépi kapukból. Az `E99` **nem valódi epic**.
> A GOV-körök a queue-n KÍVÜL futnak (kézi orchesztrálás), a GOV-01 mintájára.

0a. **Az Epic 6 lánc KÖVETKEZŐ KÖRE: E06-R02** (AnalysisDocument V2
   domainmodell, `docs/rounds/e06-r02-analysis-document-v2-domain.md`) — a
   queue `pending`, a pipeline a szokásos módon dispatch-eli. Az E06-R01
   (Kör 1) ✅ **KÉSZ** (lásd a fejléc ✅-blokk); 28 további Epic 6 kör van
   hátra (`epic-06-batch-index.md`). A queue soronként, EGYESÉVEL halad
   (`PIPELINE_SLOTS=1`, user-döntés 2026-08-11).

0b. **Ettől FÜGGETLENÜL, még nyitva: a GOV-05b bekötő köre — a backend
   `main.py` bekötése az OpenAI-adapterre (briefje még nincs megírva).**
   A GOV-körök a queue-n KÍVÜL futnak (kézi orchesztrálás) — ez a track
   nem az Epic 6 lánc része, és az Epic 6 dispatch-ok nem érintik. A backend adapter
   (E99-R07) és a Dart-oldali transport+provider-bedrótozás (E99-R06) is
   kész; ami hátravan, a `main.py` registry/gateway-kiválasztásának bekötése
   az `OpenAiProviderGateway`-re (ma kizárólag `FakeProviderGateway`-t épít),
   a `RemoteTutorModelGateway` Dart-oldali élesítése (authentikált
   `Dio`-val — a `/tutor/stream` JWT-t vár, E99-R06 review NOTE-1) és a
   flag-rollout. A pre-flightnek az E99-R07 utáni állapotot kell mérnie.

   **A user 2026-08-09-én újranyitotta a GOV-05b-t** („a négy konkrét darab is
   csináljuk meg", provider: „open ai legyen"). A négy darabból:

   | # | Darab | Állapot |
   |---|---|---|
   | 1 | Backend OpenAI provider-adapter | ✅ **KÉSZ** (E99-R07, PR #210, ADR 0214) |
   | 2 | Dart konkrét `TutorStreamTransport` | ✅ **KÉSZ** (E99-R06, PR #209) |
   | 3 | A három provider bedrótozása | ✅ **KÉSZ** (E99-R06, PR #209) |
   | 4 | Hosztolás + OpenAI API-kulcs | **user-feladat** |

   Mind a négy darab elkészült vagy user-feladatra vár — de az adapter (#1)
   MÉG NINCS bekötve a `main.py` bootjába (E99-R07 tudatosan nem tette, ADR
   0214 Döntés 2/OD-04): `tutor_provider` alapértéke `"fake"` marad, az
   `aiTutorEnabled` bekapcsolása változatlanul crash-mentes, de valódi
   OpenAI-hívás még nem érhető el éles úton. Ez a bekötés a fenti következő
   kör dolga.

   **A §6 sorrend mind az 5 pontja LEZÁRULT** (GOV-05a ✅, GOV-05c ✅, GOV-06
   ✅ + GOV-06b ✅, Epic 6 feloldása ✅ 2026-08-11). A GOV-05b lánca ettől
   FÜGGETLENÜL fut, és változatlanul nyitva (0b pont).

   **A pipeline-lánc AKTÍV:** `docs/execution/pipeline-queue.tsv` minden
   E05-sora `done`, E06-R01 `done`, a többi 29 E06-sor **`pending`** — a
   lánc E06-R02-vel folytatódik, `PIPELINE_SLOTS=1` szerint egyesével.

   **~~E06-R01 — Analyze V1 baseline, mérés és ADR-ek~~ — KÉSZ** (PR #211,
   `62516a4b`, **ÚJ ADR 0215–0220**; implementer Codex/Terra, 1 forduló,
   javító kör nélkül; lásd a fejléc ✅-blokk a teljes történetért).

   **~~E99-R04 (GOV-06) — Valós-audio DSP baseline mérés~~ — KÉSZ** (PR
   #207, `5ceed22d`, **ÚJ ADR 0199**; implementer Codex/Terra, 1 forduló,
   javító kör nélkül; lásd a fejléc ✅-blokk a teljes történetért).

   **~~E99-R03 (GOV-05c) — Learn migráció a Practice Engine V2-re~~ — KÉSZ**
   (PR #206, `0e9d211c`, **ÚJ ADR 0198**; implementer Codex/Terra, 1
   forduló, javító kör nélkül — a pre-flight mérése pontosan a szállított
   módosítás alakját írta le; review APPROVED, 0 BLOCKER/MAJOR/MINOR, 1
   NOTE, reviewer SAJÁT izolált-klón gate-újrafuttatással (10/10 zöld) +
   SAJÁT valódi-sértés próbával függetlenül ellenőrizve; dedikált
   security-reviewer risk=high **PASS**, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 2
   NOTE; ld. fejléc + §4).
   **~~E99-R01 (GOV-05a) — Practice V2 + Song Trainer V2 shipping rollout~~ — KÉSZ**
   (PR #205, `d958b75e`, **ÚJ ADR 0197**; implementer Codex/Terra, 1
   implementációs + 1 javító forduló — az első fordulóban helyes `stopped`
   scope-jelzés, dokumentált §0.0 R1 revízióval feloldva; review APPROVED,
   0 BLOCKER/MAJOR, 1 MINOR + 3 NOTE; ld. fejléc).
   **~~E05-R30 — Dataset, evaluation, minőségi kapuk és Epic 5 lezárás~~ — KÉSZ**
   (PR #204, `d3b2caf9`, nincs új ADR — záró-kör waiver; implementer
   Codex/Terra, egyetlen forduló, javító kör nélkül; dedikált
   security-reviewer risk=high PASS; 1+2 MINOR mind forward-looking/lezárva,
   7 NOTE; ld. fejléc + §4 + §5).
   **~~E05-R29 — Device tier, performance és thermal hardening~~ — KÉSZ**
   (PR #203, `8e7eb6f9`, **ÚJ ADR 0196**; implementer Codex/Terra, egyetlen
   forduló, javító kör nélkül; dedikált security-reviewer risk=high PASS;
   1 MINOR + 4 NOTE; ld. `docs/handoff-archive.md`).
   **~~E05-R25 — Practice Engine vision integration~~ — KÉSZ**
   (PR #199, `9b608cf`, **ÚJ ADR 0192** practice-vision-integration-contract
   szerződésre; implementer Codex/Terra, egyetlen forduló (köztes
   pre-flight-eredetű `stopped` önjavítva, 0 javító kör); dedikált
   security-reviewer risk=high PASS, 1 nem-blokkoló MINOR (barrel-szimbólum-
   rés) → E05-R26 pre-flight bemenet; ld. fejléc + §3 + §5).
   **~~E05-R24 — Vision session controller and realtime overlay~~ — KÉSZ**
   (PR #197, `e9257f4`, nincs új ADR; implementer Codex/Terra, 2 javító kör;
   dedikált security-reviewer risk=high; 1 BLOCKER + 1 MAJOR + 1 MINOR pass 1,
   1 önjavítás-eredetű BLOCKER pass 2; H5 self-heal PR #198 a queue
   mért-motor szinkronjára; ld. §5 + `docs/handoff-archive.md`).
   **~~E05-R23 — Feedback policy and realtime cue budget~~ — KÉSZ**
   (PR #196, `b54490e`, **ÚJ ADR 0191** feedback-policy-és-cue-budget
   szerződésre; implementer Codex/Terra, 1 javító kör; dedikált
   security-reviewer risk=high; 1 BLOCKER + 2 MAJOR + 4 MINOR a javító
   körben zárva; ld. fejléc + §5).
   **~~E05-R22 — Vision observation fusion and evidence engine~~ — KÉSZ**
   (PR #195, `997e7be`, **ÚJ ADR 0190** observation-fusion-és-evidence
   szerződésre; implementer Codex/Terra, 2 javító kör; dedikált
   security-reviewer risk=high PASS; 1 MAJOR + 2 MINOR a javító körökben
   zárva; ld. fejléc + §5).
   **~~E05-R21 — Audio–vision clock mapping and latency calibration~~ — KÉSZ**
   (PR #194, `7b11f26`, **ÚJ ADR 0189** audio–vision szinkron-szerződésre;
   implementer Codex/Terra, egyetlen forduló; APPROVED elsőre, javító kör
   nélkül; ld. fejléc + §5).
   **~~E05-R20 — Posture metric engine és safety policy~~ — KÉSZ**
   (PR #193, `be38e11`, **ÚJ ADR 0188** safety-claim-guard-ra, posture-fél
   ADR 0179 végrehajtása; implementer MiniMax M3, 1 javító kör; dedikált
   security-reviewer risk=high, 2 MAJOR a javító körben zárva; ld. fejléc + §5).
   **~~E05-R19 — Picking-hand stroke metric engine~~ — KÉSZ**
   (PR #192, `a38e0e0`, nincs új ADR — ADR 0179/0181 végrehajtása;
   implementer MiniMax M3, 1 javító kör; ld. fejléc + §5).
   **~~E05-R18 — Fretting-hand metric engine~~ — KÉSZ**
   (PR #191, `75f8766`, nincs új ADR — ADR 0179/0181 végrehajtása;
   implementer MiniMax M3, 2 javító kör; ld. fejléc + §5).
   **~~E05-R17 — Automatic guitar detector go/no-go decision~~ — KÉSZ**
   (PR #189, `e979d41`, **ADR 0187** (új); implementer MiniMax M3, 1
   javító kör; dedikált security-reviewer risk=high, MAJOR lelet a javító
   körben zárva; ld. fejléc).
   **~~E05-R16 — Guitar geometry tracking és calibration loss~~ — KÉSZ**
   (PR #188, `6f9c0e1`, nincs új ADR — ADR 0179/0181 bővítése; implementer
   MiniMax M3, 1 javító kör; dedikált security-reviewer risk=high, MINOR
   lelet a javító körben zárva; ld. fejléc).
   **~~E05-R15 — Guitar coordinate system és homography~~ — KÉSZ**
   (PR #187, `a351ad3`, nincs új ADR; implementer MiniMax M3 (mindkét
   javító kör); dedikált security-reviewer risk=high — innen indult
   BLOCKER-1; ld. fejléc + §5).
   **~~E05-R14 — Pose landmark provider és posture baseline~~ — KÉSZ**
   (PR #185, `efa4bbe`, ADR 0186; implementer MiniMax M3 → Codex/Terra
   (javító kör 2); dedikált security-reviewer PASS; ld. docs/handoff-archive.md + §5).
   **~~E05-R13 — Hand track assignment és temporal smoothing~~ — KÉSZ**
   (PR #184, `148469c`, nincs új ADR; implementer MiniMax M3; 1 javító kör;
   dedikált security-reviewer PASS, futott a merge előtt; ld. fejléc + §5).
   **~~E05-R12 — Hand landmark provider adapter és model manifest~~ — KÉSZ**
   (PR #183, `f39d7b6`, ADR 0185; implementer MiniMax M3; 1 javító kör;
   dedikált security-reviewer PASS (post-merge, orchestrátor-mulasztás
   pótolva); ld. fejléc).
   **~~E05-R11 — Manual guitar geometry calibration UI~~ — KÉSZ** (PR #182,
   `113976a`, nincs új ADR; implementer MiniMax M3; 1 javító kör (3
   BLOCKER); dedikált security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).
   **~~E05-R10 — Camera + guitar calibration domain és verziózott tárolás~~ — KÉSZ**
   (PR #181, `39d1c29`, nincs új ADR; implementer MiniMax M3; 3 javító kör
   (MiniMax 1 + Codex 2); dedikált security-reviewer PASS; ld. fejléc + §5).
   **~~E05-R09 — Frame quality assessor~~ — KÉSZ** (PR #180; 1. kísérlet
   külső GitHub-incidensbe futott, önjavító retry; ld. fejléc).
   **~~E05-R08 — Vision setup wizard és camera profile~~ — KÉSZ** (PR #170,
   `eff1eaf`, nincs új ADR; implementer Terra; 0 javító kör; dedikált
   security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).
   **~~E05-R07 — Frame transform és overlay koordinátarendszer~~ — KÉSZ** (PR #169, `b5837d9`,
   nincs új ADR; implementer Terra; 1 javító kör (overlay-mapping pótlása);
   dedikált security-reviewer PASS, 1 carry-forward MAJOR R13/R15/R24 elé; ld. fejléc + §5).
   **~~E05-R06 — Android camera production adapter~~ — KÉSZ** (PR #168, `a43f8c1`,
   nincs új ADR; implementer Terra; 1 javító kör (teszt-minőség); dedikált
   security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).

   _(A korábbi, Epic 4-es „exact next task" bejegyzések innentől lefelé
   történeti maradványok — az Epic 4 lezárult E04-R24-gyel, ld. fejléc-archívum.)_
   **~~E04-R23 — Tutor safety, injection, usage & evaluation gate~~ — KÉSZ** (PR #159, `04787fa`,
   ADR 0177; implementer DeepSeek v4 Pro; 1 javító kör + 2 orchestrátor scope-akció; ld. fejléc + §5).
   **~~E04-R22 — Tutor Profile, Privacy, Data & Consent UI~~ — KÉSZ** (PR #157, `faa3f32`,
   nincs új ADR — ADR 0132+0134 hatálya; implementer MiniMax M3; ld. fejléc + §5).
   **~~E04-R21 — Song Trainer debrief & range action integráció~~ — KÉSZ** (PR #156, `6000b57`,
   nincs új ADR — ADR 0132+0089 hatálya; implementer Codex/Terra; a re-scoped §0.0
   struktúra+capability+redaction szelet; korábbi H3 BLOCKER-1-et a merge-elt ADR 0176
   oldotta fel — rebase a javított main-re; a halasztott result/range/setlist szelet
   külön prerekvizit kört igényel; ld. fejléc + §5).
   **~~E04-R20 — Practice & Analyze post-session tutor integráció~~ — KÉSZ** (PR #153, `3ce4afc`,
   nincs új ADR — ADR 0132 hatálya; implementer Codex/Terra; §0.0-R1 public.dart
   scope-narrowing az E04-R01 boundary-teszt miatt; ld. fejléc + §5).
   **~~E04-R19 — Evidence, source & action card UI~~ — KÉSZ** (PR #152, `f0f74fb`,
   nincs új ADR — ADR 0132+0133 hatálya; implementer MiniMax M3; első futás stalled →
   folytató dispatch salvage; ld. fejléc + §5).
   **~~E04-R18 — Tutor Home, Chat UI & streaming UX~~ — KÉSZ** (PR #151, `104e685`,
   nincs új ADR — ADR 0131+0134 hatálya; implementer MiniMax M3; box-timeout salvage
   + 2 teszt-fix javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R17 — Conversation repository, summary & inspectable memory~~ — KÉSZ** (PR #148, `1e9b2db`,
   nincs új ADR — ADR 0134 hatálya; implementer Codex; 2 MAJOR zárva javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R16 — Tutor orchestration state machine & output validator~~ — KÉSZ** (PR #147, `df25806`,
   ADR 0174; implementer Codex; ld. fejléc + §5).
   **~~E04-R15 — Backend + Flutter streaming transport~~ — KÉSZ** (PR #145, `1fe91d2`,
   ADR 0142; implementer qwen38-max; H3 self-heal #143 után; ld. a fejléc-összefoglalót és §5).
   **~~E04-R14 — Backend tutor proxy, provider registry & usage guard~~ — KÉSZ** (PR #142, `c1c0a77`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-coder-plus; ld. §5 archívum).
   **~~E04-R13 — TutorModelGateway & scripted fake~~ — KÉSZ** (PR #141, `b9d2950`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-plus; ld. a fejléc-összefoglalót és §5).
   **~~E04-R12 — Prompt templatek, output schema & injection boundary~~ — KÉSZ** (PR #140, `c5b14e5`,
   ADR 0141, ld. a fejléc-összefoglalót és §5).
   **~~E04-R11 — Action proposal & confirmation~~ — KÉSZ** (PR #137, `479550f`,
   ADR 0139, ld. §5 snapshot).
   **~~E04-R10 — Tutor Tool contract & read-only registry~~ — KÉSZ** (PR #136, `2f7fffc`,
   ADR 0137, ld. §5 snapshot).
   **~~E04-R08 — Deterministic debrief coaching~~ — KÉSZ** (a queue sora, ld. archívum).
   **~~E04-R07 — Offline knowledge index & retrieval~~ — KÉSZ** (PR #130, `8182204`,
   ADR 0136, ld. a fejléc-összefoglalót és §5).
   **~~E04-R06 — Knowledge schema & content pack~~ — KÉSZ** (PR #129, `f3d69ef`,
   ADR 0135).
   **~~E04-R05 — Context adapters & snapshot~~ — KÉSZ** (PR #128, `55d640d`).
   **~~E04-R04 — Skill taxonomy & evidence reducer~~ — KÉSZ** (PR #127, `0d7ab1b`).
   **~~E04-R03 — Student/guitar profile, goals & consent~~ — KÉSZ** (PR #126,
   `06ae3f7`).
1. **~~E03-R22 lezárási lánc~~ — KÉSZ** (PR #123, `3ae368a`, Epic 3 zárva).
1. **Historical pipeline snapshot (superseded): ~~E03-R01~~, ~~E03-R02~~, ~~E03-R03~~, ~~E03-R04~~, ~~E03-R05 —
   Validator, normalizer, capabilities~~, ~~E03-R06 — Legacy Song/Setlist
   migrációs adapter~~ és ~~E03-R07 — Fájlrendszeres Song repository és
   asset store~~ — KÉSZ, ld. §5.** Következő:
   **E03-R08 — Legacy adatok tartós V2 migrációja**
   ([docs/rounds/e03-r08-persistent-v2-migration.md](docs/rounds/e03-r08-persistent-v2-migration.md)).
   A `docs/execution/pipeline-queue.tsv` E03-R08 sora `pending` — a driver
   automatikusan folytatja (mid-epic round, nincs emberi kapu, ADR 0087 §7).
1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése. Az APK a PR #37
   CI-runjából tölthető
   ([30673821431](https://github.com/wolfcasaba/strumsight/actions/runs/30673821431)).
2. **~~E02-R20 — Epic 2 lezárás (a11y/l10n/perf audit, DoD-tábla)~~ — KÉSZ**
   (PR #44, `4616aed`, 2026-08-01, implementer **MiniMax M3**, orchestrátor
   **Claude Sonnet 5**, egy javító kör → **APPROVED**). **Epic 2 technikailag
   lezárva.**
   - **~~A rendszerszintű drótozási rés (§3)~~ — KÉSZ (E02-R21, ld. §5).**
   - **A `migratedLearnEnabled` rollout-döntés** — mindenhol OFF, a
     bekapcsolás feltételei (mérföldkövek, monitorozás, visszaállítási
     útvonal) az R19 paritása alapján még **user-döntésre várnak**
     (R20 nem hozott ebben döntést, csak dokumentált).
   (E02-R19 progress/streak/daily-goal + Learn V2-migráció — KÉSZ: PR #43,
   `0bdee7e`.)
3. **A pipeline (ADR 0087, GOV-02) E02-R14…R19-et és E02-R21-et vitte
   (utóbbit a self-heal round 10/H4 zárta le); E02-R20-at és E03-R01-et
   SZÁNDÉKOSAN ember indította** (ADR 0087 §7 — epic-kickoff és epic-zárás
   emberi döntési pont); E03-R02-t és E03-R03-at a user már `pending`-re
   állította, a driver ezeken a körökön keresztül automatikusan folytatta
   (self-heal L49/L50, majd L51 közbeiktatásával) — a
   ([`docs/execution/pipeline-queue.tsv`](docs/execution/pipeline-queue.tsv))
   E03-R01/R02/R03/R04/R05 sora `done`, E03-R06 sora a fájlban még
   `pending` (a driver saját könyvelése frissíti `done`-ra a következő
   firing-en — ez a session nem nyúl a queue-fájlhoz), E03-R07…R21
   `pending` — a driver körönként automatikusan halad, amíg HALT nem éri.

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
   >
   > **REVIEW-MOTOR FALLBACK (ADR 0115, 2026-08-02 — user-döntés):** ha a
   > **Claude-kvóta** kimerül, a lánc nem áll meg: ugyanazt a kör- vagy
   > önjavító promptot a **Terra** (`codex exec`, `CODEX_HOME=~/.codex-terra`,
   > `gpt-5.6-terra`) viszi tovább, a
   > `docs/execution/pipeline-codex-orchestrator-preamble.md` motor-előszóval.
   > A váltás kiváltója KIZÁRÓLAG a mért kvóta-minta a session-naplóban —
   > minden más néma halál marad halt. A zárlat 5 óra
   > (`.pipeline/claude-blocked-until`), visszaállítás:
   > `tools/pipeline-status.sh --unblock-claude`; kikapcsolás:
   > `PIPELINE_FALLBACK_ENGINE=none`. **Az implementer-routing (ADR 0088:
   > M3 → Terra) ettől FÜGGETLEN és változatlan** — ez csak arról szól, ki
   > vezényel és ki review-z.
   >
   > **E03-R05 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > `router_result` egyetlen szinkron `ai-router-round.sh run` hívása a
   > Bash-eszköz 600s-es kemény plafonjánál tovább tartó MiniMax-hívásoknál
   > (`model_timeout_seconds=7200`) jelzés nélküli SIGTERM-mel halt meg —
   > docs/LESSONS.md L42 pontos ismétlődése, most az `engine=auto` úton.
   > Javítás: `engine=auto` is a már szentesített leválaszt-és-előtérben-várj
   > mintát követi (`setsid ... & ; tools/wait-for-router.sh`); az örökölt
   > `wait-for-round.sh` a router `progress`/`blocked` jelzéseit nem ismeri
   > fel terminálisnak (mérve, regressziós teszttel dokumentálva), ezért egy
   > ÚJ, dedikált poller kellett. `tools/ai-router-round.sh` és a Python
   > router (`tools/ai_router/**`) VÁLTOZATLAN — a szükséges state-alapú
   > állapotlekérdezés már létezett. PR #61, `3b4707f`, `router-ci` zöld.
   > Részletek: docs/LESSONS.md L54.
   >
   > **E03-R05 H-GATEGUARD önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:**
   > a H6 heal (PR #61) UTÁN a driver `H-GATEGUARD`-dal állt le, holott a PR
   > #61 saját diffje a mércét NEM érintette — a heal ~07:50–08:08 közötti
   > futása KÖZBEN egy tőle FÜGGETLEN, jogos commit (`8715773`, ADR 0115)
   > módosította a `router-ci.yml`-t, és a régi őrszem a teljes main
   > előtte/utána állapotát hasonlította össze, nem a heal SAJÁT diffjét.
   > Javítás: `heal_pr_number`/`heal_pr_gate_violation` a determinisztikus
   > `heal/{ROUND}-{HALT_CODE}-{ATTEMPT}` branch-névhez tartozó, merge-elt PR
   > SAJÁT diffjét nézi (immunis a konkurens, független commitokra); nincs
   > megtalálható PR esetén óvatosságból a régi teljes-fingerprint marad
   > fallback. Regressziós tesztek a VALÓDI PR #61/`3b4707f` (negatív eset) és
   > a VALÓDI, `round-gate.sh`-t módosító `6d61e23` (pozitív eset) adatain.
   > Részletek: docs/LESSONS.md L55.
   >
   > **E03-R05 H6 önjavító kör #2 (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > H-GATEGUARD heal (PR #62) UTÁN a friss `auto` M3-hívás ÚJRA commitolt
   > (`d0546f0`, worktree `ss-router-e03-r05-2`) a prompt "Do not commit,
   > push..." tiltása ellenére — `security.py` helyesen hard-BLOCKolt, de a
   > `HALTED` saját gyökérok-elmélete ("a tiltás sosincs kimondva") mérve
   > téves volt (a `router.py:353-364` prompt élén ott áll). Ez ugyanaz a
   > tünet, mint L49 (E03-R02) — ott a self-heal SZÁNDÉKOSAN elvetett egy
   > `security.py`-lazítást mércegyengítésként. Javítás most: egy ÚJ,
   > korábbi rétegen ülő kontroll, nem az elvetett lazítás újramérlegelése —
   > `tools/ai_router/git-guard/git` PATH-shim, amit `execution.py`
   > `run_codex()` minden M3/Terra hívás elé tesz, és ami `git commit`/
   > `git push`-t a shell-rétegen utasít el (minden más git-alparancs
   > változatlanul átmegy); `security.py` audit_scope-ja és hard-blockja
   > ÉRINTETLEN. Regressziós tesztek (fix előtt RED, utána GREEN):
   > `tools/tests/test_execution.py::test_git_guard_blocks_commit_and_push_but_passes_through_other_subcommands`,
   > `::test_run_codex_blocks_a_model_commit_at_the_shell_layer` (a `d0546f0`
   > mintát reprodukálja egy hamis "codex" folyamattal). Részletek:
   > docs/LESSONS.md L56.
   >
   > **E03-R08 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** az
   > auto-router M3 1. próbálkozása `changed_paths=0` mellett terminális
   > `STOPPED`-ot adott vissza; `classification.py`'s catch-all-ja futott,
   > mert egyik ismert minta (quota/429/timeout/network/credential/env) sem
   > talált — a `HALTED` fájl innen csak ezt az egy szót tudta jelenteni,
   > mert `execution.py`'s `run_codex()` a MiniMax CLI nyers `stdout`-ját
   > sorról sorra JSON-ra próbálta parse-olni, és minden NEM-JSON sort
   > (pont ahol egy szöveges self-halt üzenet állna) némán eldobott — a
   > `CodexResult`-nak nem is volt `stdout` mezője. Class A gyökérok (a
   > router SAJÁT diagnosztikai csatornája hiányos, nem a MiniMax-hívás
   > tartalma). Javítás: `CodexResult.stdout` mező (az `events`/
   > `agent_messages` MELLETT) + `router.py`'s új `_record_provider_call()`
   > (az `_record_gate()` mintája) minden M3-/Terra-hívás után a task-state
   > `provider_calls`-listájába teszi a nyers (20000 karakterre vágott)
   > `stdout`/`stderr`-t, a `FailureClass`-szal együtt. Regressziós tesztek
   > (RED a fix előtt, GREEN utána):
   > `test_execution.py::test_run_codex_preserves_raw_stdout_for_non_jsonl_output`,
   > `test_router.py::test_provider_call_history_persists_raw_stdout_for_stopped_diagnosis`.
   > A `tools/tests -q` egy MÁSIK, ehhez a halthoz nem tartozó sub-teszttel
   > (`test_epic3_brief_metadata.py`, E03-R05 brief TOML-drift) továbbra is
   > pirosít — ez az [[L59]]-ben már dokumentált, önálló felhatalmazású
   > önjavító kört vár, SZÁNDÉKOSAN érintetlen ebben a körben (§2 hatóköre
   > csak a MEGÁLLT — E03-R08 — kör briefjére terjed ki). PR #67, `3725f09`.
   > Részletek: `docs/LESSONS.md` L61.
   >
   > **E03-R08 H6 önjavító kör, 2. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti javítás után a H6 más gyökérokkal két
   > egymást követő 5 perces cikluson (15:19, 15:29 UTC) belül ismét
   > lecsapott: a brief `migration`-fragmenst érint, ezért a kötelező Terra
   > high-risk review (ADR 0088 §2) szükséges, de a napi automatikus
   > Terra-budget (`.ai/router.toml` `max_automatic_terra_calls_per_utc_day
   > = 3`) MÉRVE (`terra-ledger.json`, `daily_count=3`) kimerült — ez csak
   > `2026-08-03T00:00:00Z`-kor nyílik meg újra. C osztályú (külső,
   > naptár-kapuzott) akadály, de a driver 5 percenkénti retry-ciklusa
   > ~20-30 percen belül elhasználta volna mind a 3 önjavítási kísérletet
   > egy olyan haltra, ami emberi döntést nem is igényelt. Javítás:
   > `tools/round-pipeline.sh` kör-specifikus, időkorlátos "hold" — egy
   > Terra napi-budget-kimerülésre visszavezetett `retry` után a driver
   > `terra-budget-hold` fájlt ír (`round`, `hold_until=UTC éjfél`), és
   > minden firing a zár után, halt-kezelés/kör-indítás ELŐTT ellenőrzi:
   > ha a soron lévő kör megegyezik, session és önjavítási-kísérlet
   > fogyasztása NÉLKÜL lép ki. Új, tisztán olvasó
   > `StateStore.daily_terra_count()` (state.py) + `terra-status`
   > alparancs (model-router.py, JSON + nemnulla exit kimerülésnél) — a
   > driver ugyanazt a forrást kérdezi, amit `reserve_terra` a döntéséhez
   > használ, nincs duplikált szabály. Regressziós tesztek (RED a fix
   > előtt, GREEN utána): `test_state_store.py::
   > test_daily_terra_count_matches_the_active_status_rule_reserve_terra_enforces`,
   > `test_router_cli.py::
   > test_terra_status_exits_nonzero_and_reports_the_utc_midnight_reset_once_exhausted`,
   > `test_pipeline_integration.py::
   > test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`.
   > A `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít — mérve azonosan a
   > módosítás nélküli `main`-en is, ezen kör hatóköre kívül esik rajta.
   > Részletek: `docs/LESSONS.md` L62.
   >
   > **E03-R08 H6 önjavító kör, 3. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti L62-hold BEVEZETVE volt (PR #68/#69), a
   > driver mégis NÉGYSZER futott ugyanabba a Terra-budget falba egy nap
   > alatt (14:26, 15:19–15:29, 16:05, 16:15 UTC) — `find .pipeline
   > -iname '*hold*'` a 4. haltkor is ÜRES találatot adott. Gyökérok:
   > `terra_hold_if_exhausted()`-ben `status_json=$(terra_status_json) ||
   > return 0` — de a `terra-status` a DOKUMENTÁLT viselkedése szerint
   > pontosan akkor tér vissza NEMNULLA exit-tel, amikor kimerült; a `||`
   > ezt is lekérdezési hibaként kezelte, a függvény visszatért, mielőtt
   > egyszer is megírta volna a hold-fájlt. A meglévő
   > `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
   > csak az OLVASÓ függvényt (`terra_hold_active_for`) tesztelte, kézzel
   > megírt hold-fájllal — az ÍRÓ ág sosem futott le teszt alatt. Javítás:
   > az `|| return 0` törölve, a meglévő `[ -n "$status_json" ] || return
   > 0` marad a valódi lekérdezési hiba (üres kimenet) védelmére. Új
   > `--terra-hold-if-exhausted` teszthorog (a `--terra-hold-active`
   > mintájára) + `test_pipeline_integration.py::
   > test_terra_hold_if_exhausted_writes_the_hold_file_when_terra_status_reports_exhausted`
   > (PATH-stub `python3`, ami a `terra-status` mért exhausted/exit-1
   > viselkedését szimulálja) — RED a régi sorral, GREEN az újjal. A
   > `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít, mérve azonosan a
   > módosítás nélküli `main`-en is; `router-ci.yml` (push-only, nem
   > GitHub-required check) ezért erre a heal branch-re is pirosat
   > mutatott, PR #70 a #68/#69 mintáját követve a CodeRabbit-checkkel
   > merge-elődött. Részletek: `docs/LESSONS.md` L63.
   >
   > **E03-R08 H6 önjavító kör, 4. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** az L63-fix (PR #70, 16:27) UTÁN is jött egy 6.
   > azonos H6 halt (16:38 UTC) — a hold-fájl megint hiányzott. Gyökérok:
   > a hold-írás (`terra_hold_if_exhausted`) KIZÁRÓLAG `attempt_selfheal()`
   > `retry`-ágából íródott ki, sosem a driver `halted)` ágából (a HALT
   > ELSŐ, session előtti észlelése). A 3. előfordulás heal-köre
   > (16:20–16:30) maga egy MÁSIK gyökérokra javított (a hold-író saját
   > hibája) — `outcome=fixed`, nem `retry` —, ezért a `retry`-ág EBBEN a
   > ciklusban sem futott le, a hold-fájl a fix után is üres maradt.
   > Javítás: új `handle_round_halt()` (`tools/round-pipeline.sh`) a
   > `halt_file` írása MELLÉ meghívja `terra_hold_if_exhausted()`-et is —
   > a HALT ELSŐ észlelésekor, MIELŐTT bármilyen self-heal elindulna,
   > FÜGGETLENÜL a self-heal későbbi `outcome`-jától. Az
   > `attempt_selfheal()` retry-ágának hívása változatlanul marad
   > (idempotens második réteg). Új `--handle-round-halt` teszthorog +
   > `test_pipeline_integration.py::
   > test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry`
   > — RED a hook nélkül (a hívás a case-ágból kiesve a teljes
   > driver-folyamatba zuhan), GREEN a hookkal. A `tools/tests -q` ezen a
   > javításon átfutva is UGYANAZZAL a [[L59]]-ben dokumentált E03-R05
   > brief-TOML sub-teszttel pirosít, mérve azonosan a módosítás nélküli
   > `main`-en is; `router-ci.yml` ezért erre a heal branch-re is pirosat
   > mutatott ugyanazzal az EGY sub-teszttel, a #68/#69/#70 mintáját
   > követve a CodeRabbit-checkkel merge-elődött. Részletek:
   > `docs/LESSONS.md` L64.
   >
   > **A napi Terra-korlát eltávolítása (PR #72, `53b9637`, L65):**
   > user-döntésre `max_automatic_terra_calls_per_utc_day = 0` mostantól
   > korlátlant jelent — a `daily_count=3/3` fal maga szűnt meg, nem csak a
   > driver retry-viselkedése rá. A taskonkénti 1 Terra-hívásos korlát és a
   > magas kockázatú review kötelezettsége változatlan.
   >
   > **E03-R08 H6 önjavító kör, 7. előfordulás (2026-08-02 18:45 UTC) — KÉSZ,
   > `outcome=fixed`:** a napi korlát megszűnése (fent) után az első
   > cron-firing helyesen törölte az elavult `terra-budget-hold` fájlt, de a
   > MELLETTE élő `.pipeline/HALTED` (a MÉG korlátozott policy alatt,
   > `halted_at=16:58:03Z`-kor kiírva) érintetlen maradt — a driver 2.
   > szakasza ettől függetlenül egy ÚJABB, valódi önjavító sessiont indított
   > egy már megszűnt okra (ez a session). **1. javító kör (PR #73):**
   > `terra_clear_stale_halt_for()` a hold-törléssel EGYÜTT, csak akkor
   > futva, ha még LÉTEZIK hold-fájl. **MÉRT hiányosság:** élesben a
   > hold-fájl a HALT előtti firingen már törlődött, tehát PR #73 hívási
   > pontja SOHA nem futott le a valódi incidensen — csak a driver
   > `outcome=fixed` standard könyvelése (a `halt_file` archiválása)
   > oldotta fel EZT a konkrét haltot, nem az új függvény. **2. javító kör
   > (PR #74, ugyanebben a sessionben):** `terra_clear_stale_halt_for()`
   > mostantól ÖNÁLLÓAN kérdezi le a Terra-policy-t, és a driver főágában a
   > hold-fájl létezésétől FÜGGETLENÜL, feltétel nélkül fut — a KÖVETKEZŐ
   > hasonló esetben már ez fog reagálni, nem egy újabb heal-session. Új
   > `--terra-clear-stale-halt` teszthorog + 3 regressziós teszt (RED PR #73
   > állapota ellen, GREEN PR #74 után); `tools/tests -q` 151/151 zöld.
   > **Biztonsági incidens a saját tesztelés közben:** a tesztek első
   > verziója egy ismeretlen CLI-flaget hívott a pre-fix scripten, ami a
   > TELJES driver-folyamatba esett és egy VALÓDI tmux+claude
   > önjavító sessiont indított — azonnal észlelve és leállítva, állapot-
   > károsodás nélkül; javítva az attempt-budget-határ biztonsági minta
   > minden ilyen teszthez való hozzáadásával. Részletek: `docs/LESSONS.md`
   > L66.
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
