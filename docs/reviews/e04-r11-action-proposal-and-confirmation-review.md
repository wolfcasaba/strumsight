# Review — E04-R11 — Action proposal, validáció és confirmation service

- **Kör:** E04-R11
- **Branch:** `codex/e04-r11-action-proposal-and-confirmation`
- **Reviewed HEAD:** `c30b6d4` (implementer commit), pre-flight base `1ba2b3d`
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 (független, read-only)
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 1 NOTE
- **ADR:** [0139](../adr/0139-ai-tutor-action-proposal-confirmation.md) (implementálja [0133](../adr/0133-ai-tutor-tool-confirmation.md))

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=c30b6d4`, gate „teljesen zöld".
A brief §10 „Implementation handoff" kitöltve, tételes acceptance→teszt
leképezéssel. A `done` bemondás **nem** elfogadva bizonyíték nélkül — a gate-et
és az acceptance-t a reviewer **maga** futtatta izolált klónban (lent).

## 2. Gate-újrafuttatás (izolált `/tmp/review-e04-r11` klón)

`git clone --branch <branch>` → `flutter pub get` + `flutter gen-l10n` (L48
klón-csapda elkerülve) → `tools/round-gate.sh test/features/ai_tutor/domain
test/features/ai_tutor/application`. **Minden lépés ZÖLD:**
format · analyze · test(domain) · test(application) · architecture · secrets · l10n.

## 3. Scope-audit

`tools/scope-audit.py --base 1ba2b3d`: **OK**, 7 changed path, 0 generated/ignored.
A 7 fájl mind a brief §4 (§0.0/D2-vel szűkített) `allowed_paths` listáján belül:
a 4 új `lib` fájl, 2 új teszt, és a brief maga (§10 handoff). `public.dart`
**érintetlen** (D2 betartva) — a fagyott boundary-teszt nulla-export invariánsa nem
sérül. `lib/app/routing/*` **nem importált** (domain-függetlenség, ADR 0139 §5).

## 4. Acceptance criteria — tételesen, bizonyítékkal

| AC | Bizonyíték | Állapot |
|---|---|---|
| valid proposal | `confirms an action when expiry is after confirmation time` (executor.actions == 1) | ✅ |
| unknown action reject | `rejects an unknown action proposal` → `blocked`/`unknownAction` | ✅ |
| stale expiry **alatta** | `blocks an action expired before confirmation time` | ✅ |
| stale expiry **rajta** | `blocks an action expiring exactly at confirmation time` (`!isAfter` inkluzív) | ✅ |
| stale expiry **fölötte** | `confirms an action when expiry is after confirmation time` | ✅ |
| stale song-revision | `blocks a song action whose revision changed after proposal` (confirm-időben) | ✅ |
| deleted-session | `blocks a session action whose source session was deleted` | ✅ |
| capability-lost | `blocks an action when its required capability is lost` (confirm-időben) | ✅ |
| double confirm idempotens | `executes concurrent double confirms only once by client action id` (in-flight dedup) + reviewer-próba a sequential confirmed-set ágra | ✅ |
| reject-flow tiszta | `keeps a rejected proposal clear of execution` | ✅ |
| arbitrary route blocked | `blocks an arbitrary raw route before it reaches an executor` + mutációs próba (lent) | ✅ |
| profile-update preview confirm ELŐTT | `provides the profile update preview before confirmation` | ✅ |

## 5. Próbatesztek (eldobhatók — lefuttatva, majd törölve)

1. **Sequential re-confirm idempotencia (a nem-tesztelt `_confirmedClientActionIds`
   ág):** egymás utáni két `confirm` ugyanarra a proposalra → mindkettő `confirmed`,
   `executor.actions.length == 1`. **ZÖLD** — a szekvenciális idempotencia ág is
   helyes (a shipped teszt csak a konkurens in-flight ágat méri). → NOTE-1.
2. **Raw-route valódi-sértés mutáció:** a validator `TutorRawRouteActionProposal`
   → `rawRouteForbidden` ága kikommentezve → a `blocks an arbitrary raw route…`
   teszt **RED** lett (`rawRouteForbidden` hiányzott). Visszaállítás után zöld.
   **Megjegyzés (defense-in-depth):** a mutáció mellett is BLOKKOLT maradt
   (`unknownAction`-ként), mert a `TutorRawRouteActionProposal` **nem** `TutorAction`,
   így strukturálisan sem érhet el executort. A guard-teszt a *konkrét* szabályt
   köti, a típushierarchia a backstop.

## 6. Architektúra + termékhatárok (AGENTS.md §5–§6)

- **Domain-függetlenség:** `tutor_action.dart` csak `dart:collection`-t importál;
  a capability saját enum, a revision opaque token; nincs `lib/app/routing/*` vagy
  más feature import. ✅
- **Nincs auto-write/launch kódút:** végrehajtás **kizárólag** `confirm` →
  `_confirmOnce` → `executor.execute` úton, pending állapotból, confirm-idejű
  újravalidációval; reject vagy invalid → nincs `execute`. ✅ (ADR 0133/0139)
- **Immutabilitás bizonyítva:** `preview.fields`, `changes`, validációs
  kollekciók `Unmodifiable*View`/`List.unmodifiable`; a domain-teszt a
  `throwsUnsupportedError`-t és a defenzív copyt méri. ✅
- **Erőforrás/lifecycle:** a szolgáltatás memóriás, nem szerez lease-t/streamet
  (mérve: `.acquire(` csak `mic_capture.dart`); nincs felszabadítandó handle. ✅
- **Secret/network/mic:** secret-scan zöld; nincs hálózat/mic/plugin érintés. ✅

## 7. Leletek

| # | Osztály | Fájl:sor | Leírás | Javasolt irány |
|---|---|---|---|---|
| NOTE-1 | NOTE | `action_confirmation_service.dart:108` | A szekvenciális re-confirm ág (`_confirmedClientActionIds.contains`) nincs dedikált shipped unit-teszttel lefedve; a konkurens in-flight ág igen. A viselkedés a reviewer-próbával bizonyítottan helyes. | Egy sequential-reconfirm teszt egy jövőbeli körben (nem blokkol; nem hizlalja indokolatlanul a diffet most). |

**Nincs OPEN BLOCKER/MAJOR/MINOR.** A merge feltételei (exact-SHA zöld CI, §4-en
belüli diff, nulla OPEN BLOCKER/MAJOR) teljesülnek a CI zöld után.
