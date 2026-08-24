"""Submission-side integrity policy for community challenge results
(E09-R22, ADR 0417).

The pure-helper module that the
``services.challenge_verification_service`` calls BEFORE the INSERT
attempt. Every function is a pure predicate over the inputs; the
service composes them into the §6 acceptance matrix.

The invariants this module encodes:

* **Metric-range (D4).** ``METRIC_VALUE_MIN = 0``,
  ``METRIC_VALUE_MAX = 1_000_000`` — the structural twin of the
  MÁR élő kliens-kontraktus
  (``kCommunityChallengeMetricMinValue`` /
  ``kCommunityChallengeMetricMaxValue``). The kliens-oldali
  kényszer megkerülhető (a kliens saját UI-ot ír), a Python-
  oldali védelem nem.

* **Impossible-score detection (A3).** A MÁSODIK,
  idő-alapú ellenőrzés — a metric_value és az eltelt idő aránya
  fizikailag lehetetlen. Két konkrét esetet fog:

  1. ``durationSeconds`` metrika: ``metric_value < 0`` (a
     RawInterval-érték a kliens-oldalon negatív nem lehet, és a
     szerver is elutasítja).
  2. ``score`` metrika nulla idő alatt: a ``score`` típusú
     challenge-nél a szerver az ``ends_at - starts_at`` ablakot
     nézi, és ha a metric_value > 0 és az ablak hossza ``<= 1``
     másodperc (konzervatív küszöb), az ``impossible_score``
     jelzéssel elutasít — ez a §6.1 A3-as cella egyik konkrét
     bemeneti esete (a "negatív idő alatt teljes pontszám"
     elfogadhatatlan) .

* **Version + window + invite-state (D1, A5).** A
  beküldés a szerver által tárolt ``community_challenges.version``
  -t, a ``starts_at <= now <= ends_at`` ablakot, és a
  ``community_challenge_invites.state ∈ {accepted, active}``
  olvasás-only halmazt ellenőrzi (mivel az ``active`` MA
  elérhetetlen a Kör 21 állapotgépben, a gyakorlatban ez az
  ``accepted`` halmazt jelenti — de az ``active`` benne marad,
  forward-compatible a Kör 23 felé).

* **No client-issued state (D1, §5.1).** Az
  ``assert_no_client_issued_trust_state`` függvény a
  Pydantic-szintű ``extra='forbid'`` mellett a service-oldali
  védelem — ha bármilyen jövőbeli kliens megpróbálja a
  ``verified`` / ``rank`` mezőt a body-ban küldeni, ez a
  service-oldali assert azonnal elutasítja a beküldést
  ``reason_code="client_issued_trust_state"`` döntéssel.

The module does NOT depend on the FastAPI stack — every helper
takes plain Python primitives and an ORM row (or a
session-and-id pair). The service layer composes them.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass


# ---------------------------------------------------------------------------
# Constants — the structural twin of the Kör 5 wire entity
# (D4 / §5.5). These MUST stay in sync with
# ``lib/features/community/domain/entities/community_challenge.dart`` ::
#   kCommunityChallengeMetricMinValue = 0
#   kCommunityChallengeMetricMaxValue = 1_000_000
# ---------------------------------------------------------------------------

METRIC_VALUE_MIN: int = 0
METRIC_VALUE_MAX: int = 1_000_000

# The server-side nonce TTL — a FÉLBEN maradt
# ``pending`` / ``review`` row ennyi idő után lejárt; a
# service a lejárat-utáni újrapróbálkozást ``rejected``,
# ``reason_code="nonce_expired"`` döntéssel kezeli.
NONCE_TTL_SECONDS: int = 24 * 60 * 60  # 24h


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read; the migration contract says
    ``DateTime(timezone=True)`` columns store UTC. PostgreSQL
    keeps tzinfo on the round-trip; the ``replace`` is then a
    no-op.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


# ---------------------------------------------------------------------------
# Decision types — the service composes these into
# (:class:`VerificationDecision`).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class IntegrityDecision:
    """The pure-helper outcome: either ``accepted`` (``ok=True``) or
    a reason-code the service translates to a
    :class:`CommunityChallengeResult`` row ``verification_state``
    and ``reason_code`` columns.

    A ``None`` reason_code means ``ok=True``; the dataclass uses
    the ``reason_code`` + ``code`` fields together so the
    service-level audit log keeps the structured code separate
    from a human-readable message (which is never wire-emitted —
    the audit-only ``reason_code`` is the contract).
    """

    ok: bool
    code: str | None
    reason_code: str | None


# ---------------------------------------------------------------------------
# Metric-range (D4, A3).
# ---------------------------------------------------------------------------


def evaluate_metric_range(metric_value: int) -> IntegrityDecision:
    """Return ``ok=True`` when ``metric_value`` is in
    ``[METRIC_VALUE_MIN, METRIC_VALUE_MAX]``.

    The bounds are the MÁR élő kliens-kontraktus tükre
    (``[0, 1_000_000]``), so the kliens és a szerver ua.azt a
    tartományt alkalmazza — a kliens-oldali kényszer megkerülhető
    (a kliens saját UI-ot ír), a szerveré nem. A3 cella: a
    ``metric_value < 0`` és a ``metric_value > 1_000_000`` egyaránt
    ``reason_code="metric_out_of_range"`` döntést kap.
    """
    if metric_value < METRIC_VALUE_MIN or metric_value > METRIC_VALUE_MAX:
        return IntegrityDecision(
            ok=False,
            code="metric_out_of_range",
            reason_code="metric_out_of_range",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# Impossible-score detection (A3 §2 — a MÁSODIK, idő-alapú
# ellenőrzés). A metric_value és az eltelt idő aránya fizikailag
# lehetetlen — két konkrét esetet fog.
# ---------------------------------------------------------------------------

# Konzervatív küszöb: ha a challenge ablaka ``<= 1`` másodperc,
# a maximális ``score`` metrikájú beküldés fizikailag lehetetlen
# (minden ilyen küszöb fölötti score-ot azonnal elutasítunk).
# A ``durationSeconds`` metrikájú challenge esetében NINCS ilyen
# küszöb — a bemenet ``metric_value < 0`` önmagában elég.
IMPOSSIBLE_SCORE_MIN_WINDOW_SECONDS: int = 1


def evaluate_impossible_score(
    *,
    metric_value: int,
    metric: str,
    starts_at: datetime,
    ends_at: datetime,
    now: datetime,
) -> IntegrityDecision:
    """Return ``ok=False`` when the metric_value vs challenge-window
    ratio is physically impossible (A3, §2).

    Two specific cases (each documents the §6.1 measure-matrix
    cell they guard):

    1. ``metric_value < 0`` — the duration-style metric is
       negative. The ``kCommunityChallengeMetricMinValue`` already
       catches this in :func:`evaluate_metric_range`, so this
       branch is defensive — but kept explicit so the A3 cell
       documents the underlying intent.
    2. ``metric == "score"`` és az ``ends_at - starts_at`` ablak
       hossza kisebb-egyenlő ``IMPOSSIBLE_SCORE_MIN_WINDOW_SECONDS``
       másodperc — a maximális score nulla idő alatt fizikailag
       lehetetlen.

    A ``durationSeconds`` metrikájú challenge esetében a metric-
    range ellenőrzés elég — a kliens-oldali kényszer
    ``metric_value >= 0``-t kényszerít ki, és a szerver-oldali
    mirror ua.azt teszi; nincs idő-alapú arány-ellenőrzés (a
    duration a session-hossz, nem a challenge-ablak hossza).
    """
    starts_utc = _as_utc(starts_at)
    ends_utc = _as_utc(ends_at)
    _as_utc(now)
    if metric == "score":
        window_seconds = (ends_utc - starts_utc).total_seconds()
        if window_seconds <= IMPOSSIBLE_SCORE_MIN_WINDOW_SECONDS and metric_value > 0:
            return IntegrityDecision(
                ok=False,
                code="impossible_score",
                reason_code="impossible_score",
            )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# Version + window check (D1, A5).
# ---------------------------------------------------------------------------


def evaluate_version(
    *,
    submitted_version: int,
    actual_version: int,
) -> IntegrityDecision:
    """Return ``ok=False`` when the client submitted a DIFFERENT
    ``version`` than the server has. A5 cell: a beküldés a
    szerver SAJÁT verziójával érkezik — a kliens a saját
    tárolt ``CommunityChallengeDefinition.version``-ját küldi,
    és ha az elavult, a szerver elutasítja
    ``reason_code="version_mismatch"``.

    EQUAL accepted. The check is OPT-IN: ``submitted_version == 0``
    (the §A5 default the router inserts when the client omits the
    field) skips the version-mismatch check (the §A5 "I am not
    asserting any specific version" surface). Otherwise
    ``submitted_version < 1`` is treated as a version-mismatch.
    """
    if submitted_version == 0:
        return IntegrityDecision(ok=True, code=None, reason_code=None)
    if submitted_version != actual_version:
        return IntegrityDecision(
            ok=False,
            code="version_mismatch",
            reason_code="version_mismatch",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


def evaluate_window(
    *,
    starts_at: datetime,
    ends_at: datetime,
    now: datetime,
) -> IntegrityDecision:
    """Return ``ok=False`` when ``now`` is outside the challenge
    window. A beküldés a ``starts_at <= now <= ends_at`` ablakban
    érkezik — a szerver-authoritatív window (A7 / §5.2).

    A beküldés a lezárt (``ends_at < now``) vagy még nem indult
    (``now < starts_at``) ablakban egyaránt elutasított
    ``reason_code="challenge_window_closed"``.
    """
    starts_utc = _as_utc(starts_at)
    ends_utc = _as_utc(ends_at)
    now_utc = _as_utc(now)
    if now_utc < starts_utc or now_utc > ends_utc:
        return IntegrityDecision(
            ok=False,
            code="challenge_window_closed",
            reason_code="challenge_window_closed",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# Invite-state (D1, A5) — read-only check.
#
# A Kör 21 lifecycle MA ``accepted`` -ig jut — az ``active``
# érték csak deklarálva van, 0 hozzárendelés-hely a kódban
# (mérve). A policy az ``invite.state ∈ {accepted, active}``
# halmazt kényszeríti (forward-compatible: az ``active``
# benne marad a halmazban, még ha ma sosem fordul elő).
# A policy NEM ír az invite-sorba — az
# ``accepted → active → completed | forfeited`` átmenetek
# egy KÉSŐBBI kör dolga (ADR 0417 D1).
# ---------------------------------------------------------------------------

INTEGRITY_INVITE_ACTIVE_STATES: frozenset[str] = frozenset({"accepted", "active"})


def evaluate_invite_state(
    *,
    invite_state: str,
) -> IntegrityDecision:
    """Return ``ok=False`` when the participant's invite is in a
    TERMINAL state (declined / expired / cancelled /
    completed / forfeited).

    A boole-elfogadás a ``{accepted, active}`` halmazra
    szűkül — a Kör 21 állapotgép ezt a halmazt tekinti
    "submission-allowed"-nak. A terminális állapotok a
    §A5 cella konkrét bemenetei.
    """
    if invite_state not in INTEGRITY_INVITE_ACTIVE_STATES:
        return IntegrityDecision(
            ok=False,
            code="invite_not_active",
            reason_code="invite_not_active",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# Nonce check (D3, A4) — read-only check on an EXISTING row whose
# ``nonce_expires_at`` a lejártban van.
# ---------------------------------------------------------------------------


def evaluate_nonce_expiry(
    *,
    nonce_expires_at: datetime,
    now: datetime,
) -> IntegrityDecision:
    """Return ``ok=False`` when the row's ``nonce_expires_at`` is in
    the past. A FÉLBEN maradt (``pending|review``) beküldés,
    melynek döntése nem született meg a TTL-en belül,
    véglegesen lejárt — a lejárat-utáni újrapróbálkozás
    ``rejected``, ``reason_code="nonce_expired"`` döntést kap.

    The A4 cell exercises this path by fabrikálva a service-en
    keresztül egy már lejárt ``nonce_expires_at``-jú sort —
    a service a kliens most-aktuális ``sourceEventId`` -
    beküldését kapja, és a service ezt a predicate-et hívja.
    """
    expires_utc = _as_utc(nonce_expires_at)
    now_utc = _as_utc(now)
    if expires_utc <= now_utc:
        return IntegrityDecision(
            ok=False,
            code="nonce_expired",
            reason_code="nonce_expired",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# Client-issued trust-state detection (§5.1, D1, A2).
#
# A SZERVER SOSEM fogad el kliens-oldali ``verified`` flaget
# vagy ``rank`` -ot — a submit-payload EGYETLEN megbízható
# mezője a metric_value / source_event_id / idempotency_key.
# A Pydantic-szintű ``extra='forbid'`` az első védelmi vonal;
# ez a service-oldali helper a MÁSODIK védelmi vonal a §6.1
# A2 cellához. Ha bármilyen jövőbeli kliens megpróbálja a
# ``verified`` / ``rank`` mezőt a body-ban küldeni, a service
# azonnal elutasítja a beküldést a ``client_issued_trust_state``
# döntéssel.
# ---------------------------------------------------------------------------


def assert_no_client_issued_trust_state(
    *,
    trusted_fields: dict[str, object],
    incoming_fields: dict[str, object],
) -> IntegrityDecision:
    """Return ``ok=False`` when the incoming payload carries any
    field the server never trusts (``verified`` / ``rank``).

    The function is invariant-shaped — it does NOT mutate the
    incoming payload, it just inspects it. The router-layer
    Pydantic ``extra='forbid'`` should keep these fields out
    of the request body in the first place; this helper is the
    belt-and-braces that a future round cannot accidentally
    turn off without triggering the §6.1 A2 measure-matrix.
    """
    trust_field_keys = set(trusted_fields.keys())
    forbidden: list[str] = []
    for key in incoming_fields:
        if key not in trust_field_keys:
            forbidden.append(key)
    if forbidden:
        return IntegrityDecision(
            ok=False,
            code="client_issued_trust_state",
            reason_code="client_issued_trust_state",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


# ---------------------------------------------------------------------------
# §6.1 measure-matrix helpers — extra constraints the A5 cell
# (terminál-allapotú invite) and the A6 cell (first/best policy
# depending on challenge type) exercise. These are load-bearing
# for the service layer, but live here as pure helpers to keep
# the policy module self-contained.
# ---------------------------------------------------------------------------


def evaluate_first_vs_best_policy(
    *,
    challenge_type: str,
    existing_best: int | None,
    submitted_value: int,
) -> IntegrityDecision:
    """Return ``ok=False`` (with ``reason_code="already_submitted"``)
    when a NON-personal-best challenge already has a verified
    submission for the same participant.

    A ``personalBest`` típusú challenge-nél egy újabb, jobb
    (``higher_is_better`` = True a jelenlegi contract; a future
    ``higher_is_better`` mező hatására a policy konfigurálható
    lesz) beküldés FELÜLÍRJA a korábbi ``best_metric_value`` -
    t (a service végzi a feltételes UPDATE-et). A többi 4
    típusnál az ELSŐ verified dönt — a további beküldések a
    ``rejected`` + ``already_submitted`` döntést kapják.

    A6 §6.1 measure-matrix két ága:

    * ``personalBest`` + rosszabb második beküldés → Piros (a
      service elutasítja ``already_submitted`` döntéssel, NEM
      írja a best-metric_value-t).
    * Nem-``personalBest`` + jobb második beküldés → Piros
      (a service elutasítja ``already_submitted`` döntéssel,
      NEM engedi a második írást).
    """
    if challenge_type == "personalBest":
        # Best-of policy: the service performs the conditional
        # UPDATE. This helper is only called when an ``existing``
        # BEST row ALREADY exists for a personalBest challenge
        # and the newly submitted value is strictly worse —
        # returning ``rejected`` is the §6.1 "personalBest
        # worse second submission" cell.
        if existing_best is not None and submitted_value <= existing_best:
            return IntegrityDecision(
                ok=False,
                code="already_submitted",
                reason_code="already_submitted",
            )
        return IntegrityDecision(ok=True, code=None, reason_code=None)
    # Non-personalBest: first-wins. Any second submission is
    # ``rejected`` regardless of metric.
    if existing_best is not None:
        return IntegrityDecision(
            ok=False,
            code="already_submitted",
            reason_code="already_submitted",
        )
    return IntegrityDecision(ok=True, code=None, reason_code=None)


__all__ = [
    "IMPOSSIBLE_SCORE_MIN_WINDOW_SECONDS",
    "INTEGRITY_INVITE_ACTIVE_STATES",
    "METRIC_VALUE_MAX",
    "METRIC_VALUE_MIN",
    "NONCE_TTL_SECONDS",
    "IntegrityDecision",
    "assert_no_client_issued_trust_state",
    "evaluate_first_vs_best_policy",
    "evaluate_impossible_score",
    "evaluate_invite_state",
    "evaluate_metric_range",
    "evaluate_nonce_expiry",
    "evaluate_version",
    "evaluate_window",
]
