# Consent enforcement — how a revocation actually stops data (E12-R17)

> Companion to [`docs/privacy/data-inventory.yaml`](data-inventory.yaml) (what leaves the
> device, and why) and [ADR 0479](../adr/0479-privacy-data-inventory-and-consent-enforcement.md)
> (why the checker walks the tree instead of trusting the inventory). This document covers the
> other half: for the two live egress routes plus the account-session gate the Community write
> path and settings-sync ride on, what MEASURABLY happens when the user revokes consent — not
> what the UI promises.
>
> Scope note (round brief §0.0): this round does not add a Consent Center screen — that UI is
> [E13-R35](../rounds/). This document is the machine-checked ground truth the future UI must
> not contradict.

## The three enforcement points

Every one of the three channels below is checked on the **turn/wire path** —
`test/privacy/consent_enforcement_test.dart` never renders a screen to prove a revocation
worked, because a provider-less screen proves nothing about the network (measured pitfall
[L140](../LESSONS.md#l140): `tutorHome` is a `StatelessWidget` with no providers — rendering it
starts no turn at all).

### 1. Tutor — `TutorConsent.modelUseGranted`

**Where it's read:** `reduceTutorTurn` (`lib/features/ai_tutor/application/orchestration/tutor_orchestrator.dart:47`)
checks `request.consent.modelUseGranted` as the FIRST thing it does with a `SendTutorMessage`
input — before `TutorOrchestrator._apply` ever calls `gatewayForAttempt(...)` or
`_gateway!.start(...)`. A revoked turn transitions straight to `TutorTurnStatus.consentRevoked`
and emits `TutorConsentRevoked`, which only cancels a subscription/gateway that was never
created. `LocalTutorFallback.resolve` (`application/offline/local_tutor_fallback.dart:120`)
mirrors the same check to report `TutorCapability.consent` + `.offline` for the UI's honest
capability summary.

**Immediacy:** the check runs fresh on every `SendTutorMessage` dispatch — there is no cached
"was consent on when this orchestrator started" flag. A single, long-lived `TutorOrchestrator`
that completes one turn with consent granted and is then asked for a second turn with consent
revoked stops on the second turn without ever being rebuilt (proven by
`test/privacy/consent_enforcement_test.dart`'s A6 tutor cell).

**What's NOT yet true:** the tutor cloud transport (`HttpTutorStreamTransport`, `POST
/tutor/stream`) has no production construction site anywhere in `lib/**` — `wired: false` in
the inventory. The turn path today can only ever reach a local/fake `TutorModelGateway`. The
consent gate above is what will stop the REAL cloud call once a future round wires it — this
round proves the gate fires before a gateway is even created, which is the strongest available
evidence today.

### 2. Diagnostics — `diagnosticsConsentProvider`

**Where it's read:** `diagnosticsConsentProvider` (`lib/features/diagnostics/providers/diagnostics_providers.dart:16`)
defaults to `false` (fail-closed). `DiagnosticsUploadNotifier.upload` reads it with `ref.read`
and returns immediately if it (or `FeatureFlags.diagnosticsEnabled`) is false — the uploader is
never touched. Even when the notifier does proceed, `DiagnosticsUploader.upload`
(`data/diagnostics_uploader.dart:52`) re-checks `consentGranted` as an explicit argument and
returns `.failed` without building a request if it is false — two independent points read the
same live value, not a value captured once.

**Production binding:** `lib/main.dart` overrides `diagnosticsConsentProvider.overrideWith((ref)
=> ref.watch(labModeProvider))` — a reactive `ref.watch`, not a snapshot. Flipping Lab mode off
changes what the very next `ref.read(diagnosticsConsentProvider)` returns, in the same running
app.

**Immediacy:** proven directly — `test/privacy/consent_enforcement_test.dart`'s A6 diagnostics
cell flips a live provider between two `upload()` calls on the SAME `ProviderContainer` and
shows the wire adapter sees exactly one request, not two.

### 3. Account-session — settings-sync and the Community write path

There is **no Community-specific consent switch on the client** (`grep -rn "consent"
lib/features/community/` → 0 matches, ADR 0479). The Community repositories
(`HttpCommunityProfileRepository` et al.) and `SettingsSync` both ride the single shared
`accountApiClientProvider` (`lib/features/auth/providers/auth_providers.dart`). The switch that
actually stops them is the **auth session generation**:

- `AuthController.logout()` / `.invalidateSession()` call `_publishLoggedOutAndClearToken()`,
  which advances `_AuthSessionGeneration` and clears `_AuthSessionCredentials.accessToken`
  (both private to `auth_providers.dart`, read fresh per-request via closures the `ApiClient`
  captured at construction — the closures are never bound to a specific generation/token value).
- `AuthInterceptor.onRequest` (`lib/core/network/auth_interceptor.dart:50,73`) reads
  `readSessionGeneration()`/the token on **every request**, before it reaches the transport
  adapter. A cleared token rejects the request as `AuthenticationFailure` at line 87–96 — the
  bytes never leave the interceptor, let alone the device.
- `SettingsSync._onLocalChange` (`lib/features/settings/providers/settings_sync.dart`)
  additionally short-circuits on `!_signedIn` before ever scheduling a push — a belt-and-braces
  guard on top of the interceptor.

**Immediacy:** `test/privacy/consent_enforcement_test.dart`'s two A5' cells prove this directly:
a Community `updateProfile()` call and a local settings edit each reach their target (wire
adapter / `SettingsRepository.update`) exactly once while signed in, then are called again,
unchanged, on the SAME `ProviderContainer` right after `logout()` — and the counts do not move.

**Consequence documented in ADR 0479 D4:** if a future round introduces a Community-specific
consent toggle, this document's §3 and the corresponding `consent_enforcement_test.dart` cells
must be re-pointed at it — today's account-session gate is the measured truth, not a permanent
design choice.

## What this document does not cover

- **Community media (`CommunityMediaUploader`)** — no production construction site exists
  (`wired: false`). There is nothing to turn-path test yet.
- **Retention / export / delete** — governed by the already-shipped
  [ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md) contract; this round's
  inventory cites it rather than re-deriving it.
- **The Consent Center UI** — [E13-R35](../rounds/), out of this round's scope (§0.0).

## §10 — the mandatory real-violation probe

Required by the round brief (§6.1/§7): prove the acceptance cells actually detect a consent
regression, not just render green on any input.

**Probe:** in `test/privacy/consent_enforcement_test.dart`'s A6 (diagnostics) test, the
reactive override

```dart
diagnosticsConsentProvider.overrideWith((ref) => ref.watch(consent))
```

was temporarily replaced with a frozen snapshot

```dart
diagnosticsConsentProvider.overrideWithValue(true)
```

— simulating exactly the regression class D2 forbids: a consent value that is captured once
(as if only re-evaluated at the next app launch) instead of re-read live on every request.

**Result — RED, as required:**

```
00:00 +3 -1: A6 (diagnostics) — revoking upload consent stops the NEXT upload in the SAME
container, no restart upload 1 (consent true) reaches the wire; upload 2 (consent flipped
false, same container) does not [E]
  Expected: an object with length of <1>
    Actual: [Instance of 'RequestOptions', Instance of 'RequestOptions']
     Which: has length of <2>
  the second, post-revocation upload must not reach the wire — the consent check re-reads the
  live provider value, not a snapshot taken at boot
```

Two requests reached the wire adapter instead of one — the post-revocation upload went out.

**A4 stayed green under the same probe** — and correctly so: A4 asserts consent is `false`
from the very first read (`overrideWithValue(false)`), a different scenario the frozen-snapshot
bug does not touch (a snapshot of `false` is still `false`). A6 is the cell whose entire job is
mid-session immediacy, and it is the one that caught this exact regression class. Claiming both
cells turned red would overstate what was measured — A6 alone is the evidence for D2's "azonnal
hat, nem a következő indításkor" requirement.

**Revert:** the override was restored to `overrideWith((ref) => ref.watch(consent))` verbatim
(`diff` against the pre-probe copy showed no difference), and the full suite was re-run green —
see the round doc's §10 for the final gate transcript.
