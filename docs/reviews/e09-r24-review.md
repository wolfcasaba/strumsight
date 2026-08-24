# E09-R24 — Review

Brief: docs/rounds/e09-r24-club-domain-membership-and-roles.md
Diff: `git diff b2cf3e35ce3ff7715446a890e988bc20b560478b...minimax/e09-r24-club-domain-membership-and-roles` (HEAD `9dc523c8`, javító kör után)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-24
Verdikt: APPROVED (javító kör után, ld. §Javító kör lent)

## Összegzés

BLOCKER: 0 · MAJOR: 0 (F1 javítva, ld. lent) · MINOR: 3 (follow-up, nem blokkol) · NOTE: 4 (nem blokkol)

Gate independently re-run in an isolated clone (`/tmp/review-e09-r24`,
`tools/prepare-flutter-generated.sh` + `tools/round-gate.sh
test/features/community/presentation/clubs/club_list_screen_test.dart`,
un-piped, foreground): all 9 steps ZÖLD, exit code 0. Scope-audit independently
re-run (`tools/scope-audit.py --repo /tmp/review-e09-r24 --brief
docs/rounds/e09-r24-club-domain-membership-and-roles.md --base b2cf3e35...`):
`OK, 10 changed path(s), 0 generated/ignored` — matches the `allowed_paths`
list exactly (9 code/test files + the brief itself).

**Note on `gate_shape=VIOLATION` in the implementer's own signal file:** the
first dispatch (3600s absolute timeout, no terminal signal) and the resume
dispatch's session log both contain an *earlier, non-final* debug invocation
of the form `tools/round-gate.sh ... | tail` (used while diagnosing a
shared-venv path question, not as the claimed evidence). The mechanical
`gate_shape` check greps the whole session log and cannot distinguish an
abandoned debug command from the final, correctly-formed evidentiary run — it
flagged VIOLATION on the presence of the substring alone. The FINAL gate
invocation in the log (`tools/round-gate.sh
test/features/community/presentation/clubs/club_list_screen_test.dart`, no
pipe) is the one whose output is quoted in brief §10.6, and I independently
reproduced that exact green result myself in a clean clone — so the
underlying claim is verified true despite the mechanical flag. This is
recorded here, not silently waived, per the round driver's evidence
discipline.

A dedicated `security-reviewer` sub-agent pass was run (risk = "high", ADR
0420 justification: owner-less-club invariant, server-authoritative role
matrix, Kör-8 block-filter reuse). Verdict: the three invariants the brief
flagged as high-risk (A1, A2, A6) all hold under inspection. It surfaced the
MAJOR below (a correctness bug, not an exploitable cross-actor leak) plus
several MINOR/NOTE items, folded into the table below.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Owner leave KÖTELEZŐ ownership transfert igényel | ✅ | `test_a1_lone_owner_leave_raises_owner_must_transfer_first`, `test_a1_owner_leave_with_second_owner_succeeds`; structurally the club never has >1 owner (create seeds exactly one, transfer keeps the count at 1, `remove_member` refuses an owner target) so no interleaving reaches 0 owners — club_service.py:980-996, :1104-1105 |
| A2 | Permission mátrix (owner/moderator/member) tesztelt minden művelethez | ✅ | `test_a2_permission_matrix_cells` (60+ parametrikus cella) · `test_a2_member_cannot_promote_self_via_service` · `test_a2_member_cannot_modify_other_member_role`; every mutating path re-derives the actor's role from the DB via `get_member_role` before `assert_may` — no client-supplied role trusted |
| A3 | Duplikált join nem hoz létre két tagságot | ✅ | `test_a3_duplicate_join_idempotent_at_service_layer`; backed by a DB UNIQUE on `(club_id, profile_id)` |
| A4 | Private klubba csak invite/elfogadott request útján lehet bekerülni | ✅ | `test_a4_private_club_join_creates_pending_request_not_member` · `test_a4_discoverable_club_join_creates_member_immediately` · `test_a4_private_club_accepted_request_creates_member` (D6 visibility-branch confirmed: private → pending, discoverable/public → immediate) |
| A5 | Member removal helyes jogosultsággal (owner/moderator) | ✅ | `test_a5_member_cannot_remove_another_member` · `test_a5_owner_can_remove_member` · `test_a5_moderator_can_remove_member` · `test_a5_cannot_remove_owner` |
| A6 | Blockolt tagok nem látják egymás tartalmát közös klubban | ✅ | `test_a6_blocked_viewer_member_list_drops_blocked_rows` · `test_a6_invite_blocked_pair_rejected`; confirmed via `query_filters.is_blocked_pair`/`filter_public_ids_against_viewer_blocks` reuse (not reimplemented) — see F4 for a write-side gap that does not itself breach this criterion |
| A7 | Membership/invite limitek konfigurációból érvényesülnek | ✅ | `test_a7_member_count_below_threshold_join_accepted` (499) · `test_a7_member_count_at_threshold_join_still_accepted` (500) · `test_a7_member_count_above_threshold_join_refused` (500+1); `MAX_CLUB_MEMBERS = 500` pins the Flutter `kCommunityClubMaxMembers` constant per ADR 0420 D3 |
| A8 | Ownership transfer sikeres, a régi owner role-ja PONTOSAN `member`-re vált | ✅ | `test_a8_transfer_ownership_old_owner_becomes_member` · `test_a8_transfer_to_self_rejected` · `test_a8_transfer_to_non_member_rejected` (ADR 0420 D4 wording, not "member vagy moderator") |
| §6.1 valódi-sértés próba | Az owner-leave transfer-guard eltávolítva → A1 PIROS → visszaállítva | ✅ | `test_a1_real_violation_probe_drop_transfer_guard_fails_cell` (brief §10.4 — inline broken-impl asserts the owner row survives member-delete with no guard, proving the removed check is load-bearing) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs** (`tools/scope-audit.py` →
`OK`, 10/10 changed paths inside `allowed_paths`, 0 violations).

## Megállapítások

### F1 — MAJOR — `create_club` idempotency probe ignores the key value

- **Fájl:** `backend/app/community/services/club_service.py:587-610`
  (`_find_club_by_create_idempotency_key`)
- **Probléma:** the helper filters only by `owner_profile_id` and returns the
  most-recently-created club for that owner (`order_by(created_at.desc(),
  id.desc()).first()`) — the `idempotency_key` argument is used only for an
  `is None` guard, never compared against a stored value.
- **Hatás:** any owner who has ever created one club can never create a
  **second, genuinely different** club as long as they pass a non-null
  idempotency key on the next `create_club` call — the probe finds their
  existing club and silently returns it instead of creating the new one. This
  is not a retry-safety nuance, it breaks the *normal* multi-club-ownership
  path outright: `create_club(owner, name="A", key="k1")` → creates A;
  `create_club(owner, name="B", key="k2")` → returns A, B is never created.
  Not cross-actor (the probe is scoped to `owner_profile_id`, so actor X
  cannot obtain actor Y's club) — a correctness defect, not a data leak.
- **Kötelező javítás:** persist the create `idempotency_key` on the
  `community_clubs` row (or a side table, matching the pattern already used
  for the invite edge's composite UNIQUE) and match on `(owner_profile_id,
  idempotency_key)` exactly — return the existing club only when the key
  matches a stored prior request, not merely "most recent for this owner".
- **Ellenőrzés:** a test that creates two clubs for the same owner with two
  **different** idempotency keys and asserts both exist with distinct
  `public_id`s (this did not exist in the 27-test suite — its absence is why
  the bug shipped past a green gate); plus a same-key retry test asserting
  the original `public_id` is returned unchanged.
- **Státusz:** FIXED (`ff307d84`, `992e648b`) — `create_idempotency_key`
  persistált a `community_clubs` soron, composite UNIQUE
  `(owner_profile_id, create_idempotency_key)`, a probe pontos tuple-
  egyezésre vált (`.filter_by(...).one_or_none()`, NEM
  `.order_by(...).first()`). Mindkét kötelező teszt megírva
  (`test_create_club_distinct_idempotency_keys_create_distinct_clubs`,
  `test_create_club_same_idempotency_key_retry_returns_original`) és
  FÜGGETLENÜL újra-mérve: izolált `/tmp/review-e09-r24-fix1` klón,
  `tools/round-gate.sh test/features/community/presentation/clubs/club_list_screen_test.dart`
  (előtér, csővezeték nélkül) → mind a 9 lépés ZÖLD, `backend pytest` a
  teljes suite-tal (a 2 új F1-teszttel együtt) ZÖLD. Scope-audit független
  újramérés: `OK, 5/5 changed path(s) in allowed_paths, 0 violation`.

### F2 — MINOR — `get_member_role` has no caller-standing check and is exported

- **Fájl:** `backend/app/community/services/club_service.py:476-497`, `:1409`
  (`__all__`)
- **Probléma:** returns any `(profile, club)` pair's role with no check that
  the caller has standing to ask. Not exploitable this round (no router
  exposes it; every internal caller passes the *actor's own* id), but it is
  exported in `__all__`, and its docstring invites router use.
- **Hatás (jövőbeli):** a future router round that exposes this directly
  would create a membership/role oracle for private clubs — an arbitrary
  authenticated caller could probe whether profile P is a member of private
  club C and with what role.
- **Kötelező javítás:** either add a caller-standing check now, or narrow the
  docstring to "internal use only, caller must already hold standing" and
  drop it from `__all__` so a future router round doesn't reach for it
  directly without re-deriving authorization.
- **Ellenőrzés:** none required this round if scoped as a documentation/
  export fix; a router round that later wires this must add its own
  authorization test.
- **Státusz:** OPEN (follow-up acceptable — not merge-blocking, no live route
  reaches this function this round)

### F3 — MINOR — owner-count read has no row lock (moot today, real if co-owners ever ship)

- **Fájl:** `backend/app/community/services/club_service.py:983-991`
- **Probléma:** `leave_club`'s owner-count check is a plain `SELECT COUNT`,
  not `SELECT … FOR UPDATE`. Currently harmless because the club structurally
  never has more than one owner (A1 verified above), so there is no
  interleaving that reaches 0 owners. Would become a genuine TOCTOU race only
  if a future round introduces co-owners (multiple simultaneous `owner`
  rows).
- **Kötelező javítás:** none required for this round; leave a code comment
  or ADR 0420 addendum flagging this for whichever future round introduces
  co-ownership.
- **Ellenőrzés:** n/a this round.
- **Státusz:** OPEN (follow-up, non-blocking)

### F4 — NOTE — Matrix-bypass + block-filter write-side asymmetries

- **Fájl:** `club_service.py:1038-1052` (`transfer_ownership`),
  `:1258-1265` (`cancel_invite`), `:830-897` (`accept_join_request`),
  `:309-339` vs `:392-403` (`get_club` vs `list_clubs`)
- **Megfigyelés:** `transfer_ownership`/`cancel_invite` enforce permission via
  inline checks rather than `assert_may`, leaving two `club_permissions.py`
  matrix branches (`TRANSFER_OWNERSHIP` self-check, `CANCEL_INVITE`) as dead
  code — still server-authoritative, just a second, parallel authority that
  could drift from the matrix on a future edit. `accept_join_request`
  performs no block check (consistent with this round's read-side-filter
  model — a blocked pair could become co-members, but every read path that
  lists members already filters them out of each other's view); `get_club`
  applies no block filter while `list_clubs` does, so a blocked-owner's
  public/discoverable club is hidden from search but still directly
  fetchable by `public_id` (low impact — public content).
- **Kötelező javítás:** none required this round — recorded so a future round
  touching these paths doesn't re-derive the same analysis from scratch.
- **Státusz:** NOTE, non-blocking

### F5 — NOTE — Exception messages may echo internal detail once a router lands

- **Fájl:** `club_service.py:570,753,826,891,1224` (`ClubIdempotencyCollision`,
  `InvalidClubTransition`)
- **Megfigyelés:** these wrap raw `IntegrityError`/state text; harmless today
  (no router surfaces them as HTTP bodies), but the future router round
  should map them to a generic error body rather than echoing `str(exc)`
  verbatim (could include column names / bound parameter values).
- **Kötelező javítás:** none this round — flag for the router round.
- **Státusz:** NOTE, non-blocking

## Javító kör

MiniMax, ugyanaz a branch, `docs/rounds/e09-r24-club-domain-membership-and-roles.md`
§10.7. Commitok: `4e6131f4` (origin/main merge, a review-jelentés
behozatala), `ff307d84` (F1 fix), `992e648b` (F1 tesztek), `9dc523c8` (brief
§10 frissítés). HEAD `9dc523c8`. F1 zárva, a fenti F1 §Státusz sor a
bizonyíték. F2/F3/F4/F5 follow-up, nem blokkolják ezt a kört, de a leletek a
jövőbeli router-kör brief-jébe (Kör 25 vagy egy klub-router kör) átveendők.

**Verdikt: APPROVED.** Merge mehet zöld CI után (ADR 0052).
