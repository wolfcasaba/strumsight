# E09-R07 — Review

Brief: `docs/rounds/e09-r07-follow-and-follow-request-graph.md`
ADR: `docs/adr/0401-follow-and-follow-request-social-graph.md`
Diff: `git diff 556cd269..1d4d6341` (pre-flight baseline → implementer HEAD, branch `minimax/e09-r07-follow-and-follow-request-graph`)
Reviewer: Claude Sonnet 5 (orchestrátor) + `security-reviewer` agent (kockázat=high, önálló futás)
Dátum: 2026-08-22
Verdikt: **APPROVED** (javító kör 1 után, commit `222a6782`)

## Összegzés (ELSŐ kör)

BLOCKER: 1 · MAJOR: 2 · MINOR: 1 · NOTE: 1 — **mind ZÁRVA a javító kör 1-ben**, l. „Javító kör 1" szakasz a jelentés végén.

Mindkét gate-lépés (Flutter cél-teszt, backend ruff/format) ZÖLD egy izolált
`/tmp` klónban. A `backend pytest` lépés viszont **NEM determinisztikusan
zöld** — ez az egyetlen BLOCKER, mérve 10 ismételt futtatással (l. F1). A
funkcionális/security tartalom egyébként erős: a DB-szintű race-védelem, az
IDOR-zárás és a block/mute stub mind helyesen implementált (l. lent), de két
MAJOR lelet (F2, F3) a router mountolása előtt/a diffben ma jelen lévő,
teszttel nem fogott hibát ír le.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Self-follow tiltott adatbázis-szinten | ✅ | `test_follow_service.py::test_a1_self_follow_rejected_by_check_constraint` zöld; migráció `CHECK (follower_profile_id != followed_profile_id)` mindkét táblán (`e09_r07_0005_community_follow.py` 91–99, 166–174 sor) |
| A2 | Duplikált follow retry vagy versenyhelyzet mellett sem keletkezik | ⚠️ RÉSZBEN | `follow_service.py:185–193` az `IntegrityError`→re-read mintát követi (helyes), DE a §6.1 KÖTELEZŐ valódi-sértés próbája (`test_swap_unique_constraint_breaks_a2`) NEM determinisztikus — l. **F1 BLOCKER** |
| A3 | Private profil accept/decline/cancel lifecycle helyes | ✅ | `test_follow_service.py` accept/decline/cancel-cellák zöldek (14/14 a flaky teszt nélkül); `decline` elutasít már-accepted state-en (`follow_service.py` ~335–340) |
| A4 | Follower removal nem igényel blockot | ✅ | `remove_follower` csak a `community_follows` sort törli, nincs block-tábla írás (`follow_service.py`, `social_graph.py:294–323`) |
| A5 | Cursor pagination stabil, nincs duplikált oldal | ✅ | `(created_at DESC, id DESC)` rendezés, teszt a cursorra |
| A6 | Optimistic follow rollback hálózati hiba esetén (Flutter) | ✅ | `relationship_controller_test.dart` zöld a gate-ben |
| A7 | Public profilnál a follow azonnali, private profilnál pending | ✅ | `relationship_controller_test.dart` zöld a gate-ben |

## Scope-audit

`tools/scope-audit.py --repo <klón> --brief docs/rounds/e09-r07-follow-and-follow-request-graph.md --base 556cd269` → **OK**, 11 changed path, 0 generated/ignored. A `lib/core/network/api_client.dart` diffje ellenőrizve: KIZÁRÓLAG az ADR 0401 §1-ben előírt új `delete()` metódus — a meglévő négy metódus (`getJson`/`postJson`/`putJson`/`post`) sora nem változott.

## Megállapítások

### F1 — BLOCKER — A §6.1 kötelező valódi-sértés próba (`test_swap_unique_constraint_breaks_a2`) nem determinisztikus, ~70%-ban PIROS

- **Fájl:** `backend/tests/community/test_follow_service.py:390–519`
- **Probléma:** a teszt két `threading.Thread`-et indít (`t.start()` majd `t.join()` szinkronizáció nélkül közöttük), és azt várja, hogy MINDKETTŐ átjusson az `existence check → INSERT` ablakon, mielőtt bármelyik commitolna — de a két szál indítása között nincs semmilyen bariér/esemény, ami a valódi versenyt kikényszerítené. Izolált `/tmp` klónban, a `round-gate.sh`-hoz identikus interpreterrel (`backend/.venv/bin/python`) 10 egymást követő futtatásból **7 PIROS, 3 ZÖLD** (`assert count == 2` — a mért `count` hol 1, hol 2). A teszt maga a `backend pytest` gate-lépés RÉSZE (`round-gate.sh` [9] lépés a TELJES backend suite-ot futtatja, nem csak a brief §7-ben megnevezett fájlt) — ez a mérce artefaktum tehát nem hozható megbízhatóan zöldre.
- **Hatás:** a kör saját, a brief §6.1 által KÖTELEZŐVÉ tett próbáját úgy commitolta permanens CI-tesztként, hogy az az esetek többségében hamis-pirosat ad — ez pontosan az ADR 0052 zöld kapu H7 kockázata (`tools/round-gate.sh nem hozható zöldre` megbízhatóan), és minden jövőbeli, ehhez a fájlhoz nem is kapcsolódó kör CI-futását véletlenszerűen elpirosíthatja.
- **Kötelező javítás:** VAGY (a) tedd determinisztikussá a race-t explicit szinkronizációval — pl. mindkét szál `threading.Barrier(2)`-on várjon közvetlenül az INSERT előtt, hogy egyszerre lépjenek be —, VAGY (b) vedd ki a permanens suite-ból, és a brief eredeti szándéka szerint (§6.1: "vedd ki... futtasd... állítsd vissza") egyszeri, kézzel futtatott próbaként dokumentáld a §10 handoffban (parancs + kimenet), a constraintet VISSZAÁLLÍTVA a commitolt migrációban (ami már most is helyes). Az (a) az erősebb védelem (permanens regressziós őr) — ezt részesítsd előnyben, ha 5–10 ismételt futtatással determinisztikusan zöldre hozható.
- **Ellenőrzés:** a választott javítást 15 egymást követő futtatással kell igazolni (`for i in $(seq 1 15); do .venv/bin/python -m pytest tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2 -q; done`), mind zöld.
- **Státusz:** **FIXED** (`222a6782`) — a Barrier NEM a szál-indítás előtt, hanem a `follow_service._existing_follow` helperbe monkey-patchelve, a PONTOS SQL-döntési pontnál szinkronizál (a naiv „Barrier a `writer()` elején" megoldás session-nyitási overhead miatt nem lett volna elég szoros ablak — az implementer ezt a diff kommentjében dokumentálta, helyesen). Saját, FÜGGETLEN 15×-ös futtatás izolált klónban: **15/15 ZÖLD**.

### F2 — MAJOR — `get_followers`/`get_following` teljesen hitelesítetlen (nincs `current_user` függőség)

- **Fájl:** `backend/app/community/routers/social_graph.py:356–413`
- **Probléma:** a két `GET` endpoint egyike sem vesz fel `current_user: CurrentUser` paramétert (szemben a router MINDEN mutáló endpointjával, amelyek `_caller_profile_public_id(db, current_user.id)`-t hívnak) — bárki, hitelesítés NÉLKÜL lekérheti bármely profil (akár `private` visibility-jű) teljes follower/following listáját, ha ismeri a `public_id`-t.
- **Hatás:** a §0.0 5. pontja szerint a router ma NEM mountolt (`build_community_router()` csak a `profile.router`-t adja vissza) — ez a hiba ezért ma LATENS, nem éles. De a kód a diff RÉSZE, és a mountolás egy jövőbeli kör (Kör 8/11/13-hoz közeli) egysoros döntése lehet — akkor ez a hiba minden előzetes figyelmeztetés nélkül éles IDOR/enumerációs sérülékenységgé válik. A brief §3 "NINCS benne" listája a láthatóság-szűrést (Kör 8/13) halasztja, de az AUTENTIKÁCIÓ hiánya egy más, súlyosabb kategória — a mutáló endpointok mind kikényszerítik.
- **Kötelező javítás:** vedd fel a `current_user: CurrentUser` paramétert mindkét endpointra (konzisztensen a router többi végpontjával) — a láthatóság-szűrés (ki látja a magánprofil listáját) továbbra is halasztható Kör 8/13-ra, DE a hitelesítés (van-e egyáltalán érvényes JWT) NEM egy jövőbeli kör felelőssége, ez a router saját belső konzisztenciája.
- **Ellenőrzés:** új teszt-eset: `current_user` nélküli (hiányzó `Authorization` fejléc) hívás 401-et ad mindkét endpointra.
- **Státusz:** **FIXED** (`222a6782`) — `current_user: CurrentUser` mindkét endpointon; `test_f2_get_followers_rejects_missing_authorization_header` / `test_f2_get_following_rejects_missing_authorization_header` (403, a projekt `HTTPBearer(auto_error=True)` konvenciója szerint — konzisztens `test_auth.py`-vel, nem 401) + egy valid-JWT round-trip teszt. A MEGLÉVŐ `test_a7_router_followers_pagination_endpoint` is frissült `Authorization` fejléccel (enélkül az auth-fix törte volna).

### F3 — MAJOR — A Flutter `unfollow()`/`removeFollower()` sosem küldi a backend által KÖVETELT `idempotency_key` query-paramétert

- **Fájl:** `lib/features/community/data/repositories/relationship_repository_impl.dart:193–219` (a `_client.delete(...)` hívások nem fűznek `?idempotency_key=` query-t az URL-hez, holott a metódus megkapja az `idempotencyKey` paramétert)
- **Probléma:** a backend `DELETE /profiles/{public_id}/follow` és `DELETE /profiles/{public_id}/followers/{follower_id}` mindkettő `idempotency_key: str = Query(..., min_length=1)` — KÖTELEZŐ, alapérték nélküli query-param (`social_graph.py:257, 296`). A Dart oldal ADR 0401 §1 szerint pontosan ezt a csatornát választotta ("DELETE mutáció... a kulcs query-paraméterként megy"), de az implementáció ezt elfelejtette megvalósítani.
- **Hatás:** minden ÉLES `unfollow()`/`removeFollower()` hívás a backend felől **422 Unprocessable Entity**-t kapna — a follow-lifecycle "unfollow" és "cancel" ága (a §0.0 3. pontja szerint UGYANEZ a hívás) és a follower-eltávolítás (A4) end-to-end TÖRVE lenne. Egyik jelenlegi teszt sem fogja meg: a `relationship_controller_test.dart` feltehetően a repository-t stubolja/fake-eli (nem valódi HTTP round-trip), a backend `test_follow_service.py` a routert közvetlenül, helyes paraméterekkel hívja (nem a Dart klienst).
- **Kötelező javítás:** a `delete()` hívásokat egészítsd ki a query-paraméterrel, pl. `'$path?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}'`.
- **Ellenőrzés:** widget/repository-teszt, ami a ténylegesen küldött URL-t (vagy a `Dio` interceptor/mock hívási argumentumait) asszertálja — nem csak a visszaadott `AppResult`-ot.
- **Státusz:** **FIXED** (`222a6782`) — mindkét `delete()` hívás `?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}`-t fűz az URL-hez. ÚJ `F3 — DELETE URLs carry the idempotency_key query parameter` teszt-csoport a ténylegesen elküldött `RequestOptions.uri.queryParameters['idempotency_key']`-t asszertálja (nem csak a visszatérési értéket).

### F4 — MINOR — `post_follow` nem kapja el a `FollowAlreadyExists`-t → nyers 500

- **Fájl:** `backend/app/community/routers/social_graph.py:130–139` (a `try`/`except` blokk csak `ValueError`-t és `SelfFollowNotAllowed`-et fog, a `follow_service.py:65`-ben deklarált `FollowAlreadyExists`-et nem)
- **Probléma:** a `follow_service.py` dokumentált, ritka race-ágon (`IntegrityError` után a re-read nem talál sort) `FollowAlreadyExists`-et dob — ez a router szintjén elkapatlan marad, FastAPI 500-at ad, a `str(exc)` (nyers `IntegrityError`, esetleg constraint-nevet tartalmazó szöveg) landol a válaszban.
- **Hatás:** egy ritka, de a service saját dokumentációja szerint VÁRHATÓ race-kimenetel csúnya 500-ként (és apró info-leakkel) landol a kliensnél ahelyett, hogy sikerként (a cél már úgyis "following") vagy tiszta 409-ként jelentkezne.
- **Kötelező javítás:** fogd el a `FollowAlreadyExists`-et is, és térj vissza vele ugyanúgy, mint egy sikeres idempotens follow-lal (`status: "following"`), a service dokumentációjának szellemében.
- **Ellenőrzés:** teszt, ami mesterségesen előidézi ezt az ágat (pl. a re-read mock-olásával) és 200-at vár.
- **Státusz:** **FIXED** (`222a6782`) — `except FollowAlreadyExists` most `{"status": "following", ...}`-gal tér vissza, ugyanúgy mint egy sikeres idempotens retry.

### F5 — NOTE — §10 Implementation handoff üresen maradt

- **Fájl:** `docs/rounds/e09-r07-follow-and-follow-request-graph.md` §10
- **Probléma:** a brief §10-et az implementernek kellett volna kitöltenie (a §6.1 valódi-sértés próba dokumentációjával együtt) — üres maradt. A próba TARTALMILAG megvan (F1 tesztje), csak nincs narrálva.
- **Hatás:** nem blokkol — a bizonyíték a tesztben megvan, csak a kért helyen nincs prózában összefoglalva.
- **Kötelező javítás:** a javító körben töltsd ki a §10-et: mit épített, a §6.1 próba parancsát/kimenetét (vagy F1 fix után az új determinisztikus verzió leírását).
- **Státusz:** **FIXED** (`222a6782`) — §10 kitöltve a valódi mért logokkal (F1 Barrier-döntés indoklása, F2/F3/F4 összefoglaló).

## Javító kör 1 — utólagos ellenőrzés (`222a6782`, önálló `/tmp` klón)

- `tools/scope-audit.py --repo <klón> --brief docs/rounds/e09-r07-follow-and-follow-request-graph.md --base 571bf80d` → **OK**, 5 changed path, 0 generated/ignored (pontosan az 5 lelethez tartozó fájl: `social_graph.py`, `test_follow_service.py`, a brief maga §10, `relationship_repository_impl.dart`, `relationship_controller_test.dart`).
- Diffenkénti kódellenőrzés (nem csak a jelzés-összegzés bemondása alapján): F1/F2/F3/F4 mindegyike a fenti Megállapítások alatt „FIXED" jelzéssel, konkrét sorhivatkozással igazolva.
- **F1 független 15×-ös reprodukció** (a review saját, a fix-előttitől eltérő futtatása): **15/15 ZÖLD** (`backend/.venv/bin/python -m pytest tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2 -q`, 15 egymást követő futás, mind exit 0).
- **Teljes `tools/round-gate.sh test/features/community/application/relationship_controller_test.dart` újrafuttatás** izolált klónban: `format`/`analyze`/`test`/`architecture`/`secrets`/`l10n`/`backend ruff format`/`backend ruff check`/`backend pytest` — **MIND ZÖLD** (a `backend pytest` a TELJES suite-ot futtatja, benne az F1 teszttel is).
- Új/frissített regressziós tesztek minden lelethez (F1 Barrier + 15× igazolás, F2 két 403-teszt + round-trip, F3 URL-assert teszt-csoport, F4 nincs külön unit, de a meglévő `test_follow_service.py` cellák továbbra is zöldek).

## Gate-bizonyíték ellenőrzése

Izolált klón: `/tmp/review-e09-r07` (fetch `origin`, branch `minimax/e09-r07-follow-and-follow-request-graph`, HEAD `1d4d6341`).

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját futtatás) |
| analyze | zöld | ✅ (saját futtatás) |
| `relationship_controller_test.dart` | zöld | ✅ (saját futtatás) |
| architecture | zöld | ✅ (saját futtatás) |
| secrets | zöld | ✅ (saját futtatás) |
| l10n | zöld | ✅ (saját futtatás) |
| backend ruff format/check | zöld | ✅ (saját futtatás) |
| backend pytest (teljes suite) | „176 teszt zöld" (implementer állítás) | ❌ — **NEM reprodukálható determinisztikusan**, l. F1 (10 futtatásból 7 PIROS pontosan a `test_swap_unique_constraint_breaks_a2` miatt; a maradék 14/14 community-teszt stabil zöld a flaky teszt kizárásával) |
| CI | nincs még dispatch-elve | — (F1/F2/F3 javítása UTÁN kerül sorra) |

## Security review (kockázat=high, önálló `security-reviewer` agent futás)

Teljes jelentés: `/home/ubuntu/ss-mm-e09-r07/docs/reviews/e09-r07-security-review.md`. Fő megállapítások (az agent saját szóhasználatával, ide integrálva a fenti sorszámozásba):

- A1/A2 DB-szinten rendben (migráció + `IntegrityError` re-read minta).
- IDOR zárva a MUTÁLÓ végpontokon: minden cselekvő-azonosítás a JWT-ből (`current_user`) származik, sosem kliens-adott ID-ból; accept/decline elutasít idegen kérésen; `delete_follower` explicit 403 nem-tulajdonosra.
- `get_followers`/`get_following` hitelesítetlensége → **ez a jelentés F2 lelete** (az agent MAJOR-nak, latensnek minősítette — egyetértek, l. fent).
- Block/mute stub `UnsupportedError`-t dob (nem csendes no-op) — helyes, a Kör 6/ADR 0400 precedens szerint.
- Raw SQL egyetlen helyen (`social_graph.py:429–434`), paraméterezett bind (`:uid`) — nincs injection-kockázat.
- A `test_swap_unique_constraint_breaks_a2` tartalmilag valódi próba (nem áltesztel) — az agent ezt "valódinak" ítélte a TARTALOM alapján; a saját, ISMÉTELT futtatásom fedte fel a DETERMINIZMUS-hiányt (F1), amit egy egyszeri agent-futtatás nem láthatott.
- A Dart `delete()` hiányzó idempotency-key query-je → **ez a jelentés F3 lelete** (az agent MINOR-nak, "nem biztonságinak" minősítette; funkcionális kontraktus-törésként MAJOR-ra emeltem, mert a follow-lifecycle egy teljes ága end-to-end törne).

## Merge-döntés

Mind az 5 lelet (1 BLOCKER + 2 MAJOR + 1 MINOR + 1 NOTE) **ZÁRVA** a javító kör 1-ben (`222a6782`), függetlenül újramérve (kód, teszt, 15×-ös determinizmus, teljes gate). Nincs nyitott BLOCKER/MAJOR. **Verdikt: APPROVED.** Következő lépés: CI-dispatch (`tools/round-ci-plan.py` szerinti workflow) exact-SHA-n, majd zöld kapu esetén squash-merge (ADR 0052).
