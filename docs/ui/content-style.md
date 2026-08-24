# Content style

StrumSight ships en + hu from the same ARB source (ADR 0424). Every rule
below exists because a shortcut that reads fine in English breaks the moment
it is translated, machine-checked (`test/l10n/`), or read on a screen with
30–60% more Hungarian text in the same space.

## The two rules everything else follows

1. **One sentence, one ARB key.** Never assemble a sentence from two
   separately-translated pieces (`'${l10n.a} ${l10n.b}'`, `'$count ' +
   t.songs`) — Hungarian word order and inflection are not English's, so the
   "obvious" concatenation is wrong the moment it ships (ADR 0424 §5.1,
   enforced by `test/l10n/hardcoded_string_guard_test.dart`). A message that
   varies by a number is one ICU key with a `plural` clause — see
   `test/l10n/arb_parity_test.dart`'s Hungarian plural rules (§5.6): Hungarian
   keeps the noun singular after any numeral ("3 nap", never "3 napok"), so
   don't force an English-shaped plural onto it.
2. **Say what happened or what's needed, not just that something happened.**
   "Something went wrong" and "Success!" cost the same number of ARB keys as
   a specific sentence — write the specific one.

Five situations recur often enough to need a fixed pattern. Each pair below
is a real StrumSight string (or its direct shape) unless noted.

## 1. Feedback (success / error)

Name the thing that changed or failed. A toast or banner the user can't act
on should still tell them enough to decide whether to worry.

| | English | Magyar |
|---|---|---|
| **Good** | "Song saved." | "A dal mentve." |
| Bad | "Success!" | "Sikeres!" |
| **Good** | "Connection problem — something went wrong reaching the server." (`dsFailureNetworkGenericTitle`/`Message`) | "Kapcsolódási hiba — hiba történt a szerver elérésekor." |
| Bad | "Error 500" | "Hiba: 500" |

Why the bad column fails: "Success!"/"Sikeres!" doesn't say what succeeded —
if the user triggered two actions close together, they can't tell which one
this refers to. A raw status code is a debugging artifact, not a sentence a
non-technical user (or a screen reader) can act on.

## 2. Permission request

Explain the feature-level reason *before* the system dialog appears, in the
same words the feature uses elsewhere — never the Android/iOS permission
name.

| | English | Magyar |
|---|---|---|
| **Good** | "StrumSight needs the microphone to detect chords and strums." (`dsFailurePermissionMicrophoneMessage`) | "A StrumSightnek szüksége van a mikrofonra az akkordok és pengetések felismeréséhez." |
| Bad | "This app requires RECORD_AUDIO permission." | "Az alkalmazásnak szüksége van a RECORD_AUDIO engedélyre." |

Why the bad column fails: a permission constant means nothing to the person
deciding whether to grant it — it's an implementation detail leaking into a
trust decision.

## 3. AI-origin

Every AI-sourced suggestion carries a provenance label (`dsProvenanceBadgeCloudLabel`
/ `dsProvenanceBadgeLocalLabel` — "Cloud" / "On-device") and is presented as
a *proposal the user confirms*, not an instruction already acted on
(`aiTutorActionConfirmationRequired`).

| | English | Magyar |
|---|---|---|
| **Good** | "AI Tutor suggestion — nothing changes until you confirm it." | "AI Tutor-javaslat — semmi nem változik, amíg meg nem erősíted." |
| Bad | "Do this next." (no provenance, no confirmation step) | "Ezt tedd legközelebb." (nincs eredetjelölés, nincs megerősítési lépés) |

Why the bad column fails: presenting an AI suggestion in the app's own voice,
with no label and no confirm step, makes it indistinguishable from the app's
own deterministic behavior — the user can't calibrate trust or catch a bad
suggestion before it acts.

## 4. Offline

Say what still works before what doesn't — StrumSight's detection is
on-device by design, and that fact belongs in the copy, not just the
architecture (`dsFailureNetworkUnavailableTitle`/`Message`).

| | English | Magyar |
|---|---|---|
| **Good** | "You're offline — no connection right now, but most of StrumSight still works on-device." | "Nincs internetkapcsolat — most nincs kapcsolat, de a StrumSight nagy része a készüléken is működik." |
| Bad | "No internet connection." | "Nincs internet." |

Why the bad column fails: a bare connectivity notice reads as "this app is
now broken," which is false for an offline-first app — it needlessly scares
a user away from a session that would have worked fine.

## 5. Destructive action

Name exactly what is removed, state irreversibility plainly, and make the
confirm button's label repeat the action — never a bare "OK"/"Yes"
(`SsConfirmationSheet`/`SsToolConfirmationSheet`, `tutorDataDeleteAllTitle`/
`Body`/`Action`).

| | English | Magyar |
|---|---|---|
| **Good** | Title: "Delete all AI data?" Body: "This permanently removes the tutor's local memory. Your sign-in is kept." Button: "Delete all AI data" | Cím: "Minden AI-adat törlése?" Törzs: "Ez véglegesen eltávolítja a tutor helyi memóriáját. A bejelentkezésed megmarad." Gomb: "Minden AI-adat törlése" |
| Bad | Title: "Are you sure?" Buttons: "Yes" / "No" | Cím: "Biztos vagy benne?" Gombok: "Igen" / "Nem" |

Why the bad column fails: "Are you sure?" / "Yes" answers a question the
user has to reconstruct from context (sure about *what*?) and gives no
signal that the action is irreversible — the exact case
`SsConfirmationSheet` exists to prevent.
