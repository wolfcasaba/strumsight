# E09-R21 — Review

Brief: `docs/rounds/e09-r21-challenge-and-invite-lifecycle.md`
ADR: `docs/adr/0415-community-challenge-invite-lifecycle.md`
Diff: `git diff origin/main...minimax/e09-r21-challenge-and-invite-lifecycle`
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 (follow-up, nem blokkoló) · NOTE: 0

Független review izolált `/tmp/review-e09-r21` klónban (GitHub-ról, NEM a
megosztott munkapéldányból). Gate 10/10 lépés ZÖLD saját kézzel
újrafuttatva. Scope-audit ZÖLD (`741f1d1c19b2..2e1bc98dcb77`, 15 módosult
útvonal, 0 sértés). Az összes A1–A7 acceptance-cellát VALÓDI termelés-kód
mutációval (nem az implementer saját, monkeypatch-alapú próbáival) mértem
újra — lásd alább.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Invalid transition elutasított | ✅ | `challenge_invite_service.py:512-752` — feltételes `UPDATE ... WHERE state IN (...)` + rowcount. Az implementer tesztjein FELÜL 4 saját eldobható pytest-cellával mérve (`accepted→declined`, `accepted→cancelled`, `declined→cancelled`, dupla-accept) — mind helyesen `InvalidChallengeInviteTransition`-t dobott. |
| A2 | Lejárt invite accept-je elutasított | ✅ | `accept_invite` `_as_utc(invite.expires_at) <= _as_utc(now)`, `now` a routerből MINDIG `datetime.now(timezone.utc)` (`routers/challenges.py:290-297`) — nincs kliens-oldali `now`/`clientTime` mező a request-sémában. |
| A3 | Blockolt fél nem hívható meg és nem hívhat meg | ✅ | `is_blocked_pair` hívás `create_invite`-ban (341-348, 453. sor) ÉS `accept_invite`-ban (569-573, defense-in-depth) — a MEGLÉVŐ `query_filters.py` helperen keresztül, nem újraírt logikával. |
| A4 | Duplikált invite retry nem hoz létre második rekordot | ✅ | VALÓDI mutáció: a pre-check kiiktatása önmagában NEM elég piros státuszhoz (a DB `UNIQUE(challenge_id, inviter_profile_id, invitee_profile_id, idempotency_key)` + `IntegrityError`→rollback→újraolvasás második védelmi vonal); a `try/except IntegrityError` KIVÉTELE viszont valódi PIROSAT adott (`sqlalchemy.exc.IntegrityError` a második INSERT-en), majd `git checkout` után zöld. Két független védelmi réteg — erősebb, mint amit a brief §6.1 egyetlen próbája bizonyít. |
| A5 | Cancel race determinisztikusan dől el | ✅ | VALÓDI mutáció: `accept_invite`/`cancel_invite` feltételes UPDATE-jét feltétel nélkülire cserélve a valódi race-teszt (`test_a5_concurrent_accept_and_cancel_is_deterministic`, tényleges threadeken + `_before_transition_seam` barrier-en át) 5/5 PIROS lett; visszaállítás után 10/10 ZÖLD. |
| A6 | Deep link csak kompatibilis Practice/Song flow-ra mutat | ✅ | `challenge_controller.dart:64-74` kimerítő switch az 5 `ChallengeType`-on — jelenleg csak `personalBest→personalBest`, a többi `none`. A widget-teszt (`community_challenges_test.dart:211-249`) POZITÍV és NEGATÍV irányt is mér (ikon jelen `personalBest`-nél, hiányzik a többi 4 típusnál). |
| A7 | A lejárat-számítás timezone-független (szerveridő) | ✅ | `test_a7_expiry_uses_server_clock_not_client_local` naiv ÉS 30 nappal eltolt kliens-órát is próbál a service-rétegen — egyik sem módosítja az ablakot; a router request-sémájában strukturálisan NINCS kliens-idő mező, ami befolyásolhatná (erősebb garancia, mint egy router-szintű spoof-teszt). |

## Scope-audit

```
Legacy scope audit OK (741f1d1c19b2..2e1bc98dcb77, 15 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. `lib/features/community/domain/**`,
`backend/app/community/policies/**`, `backend/app/community/services/block_service.py`
(tilos zóna) — `git diff` üres ezekre.

## Gate-evidencia (saját kézzel, izolált klónban)

```
format                                                     zöld
analyze                                                    zöld
test test/features/community/presentation/community_challenges_test.dart zöld (8/8)
test test/ui/ui_inventory_test.dart                        zöld (74→75 stabil)
architecture                                               zöld (12 allowlisted eltérés)
secrets                                                    zöld (3551 fájl, 0 találat)
l10n                                                        zöld (aggregátum friss, parity OK 1808 üzenet)
backend ruff format                                        zöld (108 fájl)
backend ruff check                                         zöld
backend pytest                                             zöld (teljes suite)
```

## Megállapítások

### F1 — MINOR — Az implementer saját A5 "valódi-sértés próbája" monkeypatch-alapú, nem valódi termelés-kód mutáció

- **Fájl:** `backend/tests/community/test_challenge_invite_service.py:883-1020` (`test_a5_real_violation_probe_unconditional_update_breaks_race`)
- **Probléma:** a teszt egy HELYI, monkeypatchelt helyettesítő függvényt (`_accept_no_check`) hív a valódi `accept_invite` helyett — ez gyengébb bizonyíték, mint amit a brief §6.1 szó szerint kért ("vedd ki a tényleges ellenőrzést").
- **Hatás:** ha egy jövőbeli módosítás visszavezetné a feltétel nélküli UPDATE-et a VALÓDI `accept_invite`/`cancel_invite`-ba, ez a konkrét "probe" teszt akkor is zöld maradna (hamis biztonságérzet a próba nevéből). A tényleges regressziós védelmet a MÁSIK teszt adja (`test_a5_concurrent_accept_and_cancel_is_deterministic`), ami valódi termelés-kódot hajt végre valódi szálakon — ezt a review saját kézzel is megerősítette (5/5 piros a mutált kódon, 10/10 zöld visszaállítva).
- **Kötelező javítás:** nem blokkoló — a tényleges védelem MÁS teszten keresztül megvan és a review önállóan igazolta. Follow-up: egy jövőbeli körben a "probe" tesztet térje át valódi `monkeypatch.setattr(service_module, "accept_invite", ...)` mintára, ami a HÍVÓ oldalon a modul-attribútumot cseréli, nem egy helyi függvényt hív közvetlenül.
- **Ellenőrzés:** a review saját mutációja (`accept_invite`/`cancel_invite` feltétel nélküli UPDATE-re cserélve) → `test_a5_concurrent_accept_and_cancel_is_deterministic` 5/5 PIROS → visszaállítás → 10/10 ZÖLD.
- **Státusz:** OPEN (follow-up, nem merge-blokkoló — a valódi védelem MÁS, éles teszten keresztül bizonyítottan megvan).

### F2 — NOTE — Két apró dokumentációs/holt-kód pontatlanság

- **Fájl:** `docs/adr/0415-community-challenge-invite-lifecycle.md` (Kontextus 7. pont) + `lib/features/community/presentation/screens/community_challenges_screen.dart:208-210`
- **Probléma:** (a) az ADR azt állítja, a `RateLimiter`-t a router importálja "mint `search.py`/`handles.py`" — valójában a SERVICE rétegben van (`challenge_invite_service.py:91,179`), funkcionálisan egyenértékű, csak a réteg-elhelyezés eltér a leírt precedenstől. (b) a screen-ben van holt ternary-ág egy "Song" tooltip-hez, amit a `ChallengeDeepLinkTarget` mapper sosem produkál (csak `.personalBest`/`.none` fordul elő ma).
- **Hatás:** egyik sem funkcionális hiba — (a) dokumentációs pontatlanság, (b) elérhetetlen, de ártalmatlan kódág (a routing szigorúbb, mint amit az enum sugallna).
- **Kötelező javítás:** nincs, nem blokkoló.
- **Státusz:** OPEN (nem blokkoló, tájékoztató).

## Összegző döntés

0 BLOCKER, 0 MAJOR → **merge engedélyezett** a CI-zöld-kapu (ADR 0052) teljesülése után. A két MINOR/NOTE lelet nem indokol javító kört — mindkettő a diff bővítése nélkül, egy jövőbeli körben zárható.
