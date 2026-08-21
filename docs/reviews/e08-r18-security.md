# E08-R18 — Security review

- **Reviewer:** Codex `gpt-5.6-sol`
- **Dátum:** 2026-08-21
- **Kockázat:** high — progress-integritás és nem büntető célképzés
- **Verdikt:** PASS a javítás után (1 MAJOR integritási finding lezárva)

## Független security finding

### S1 — MAJOR — Cross-objective progress/reward integrity

Az első `6300f497` implementáció unkeyed `previousCompletedUnits` értéke egy
measurement-szűrés után kiválasztott másik objective-re is átkerülhetett. A
független security-review ezt a correctness F1-t reward-integritási findingként
is megerősítette: false completion későbbi XP/reward alap lehetett.

**Státusz:** FIXED (`ef717615`). A snapshot stable `previousQuestId`-t kér;
same-ID esetben monotonic max, cross-ID esetben csak a replacement saját
observed progressze számít. Pozitív previous progress ID nélkül elutasított.
A shipping regresszió zöld, az unconditional-max reviewer-mutáció piros.

## Ellenőrzött határok

- A diff kizárólag pure Dart gamification application contractot, public
  exportot, tesztet és brief-handoffot érint; scope-audit `OK`.
- Nincs hálózat-, repository-, storage-, permission-, clock-, mikrofon-, kamera-
  vagy platform-plugin ownership az új generatorban.
- Nincs user-facing szöveg vagy nyers felhasználói adat; rollover csak zárt
  statuszt és integer tényeket ad.
- A reviewer izolált gate secret scanje: 3183 fájl, 0 finding.
- A production fájl csak relatív gamification domain-importokat használ; core
  és más feature belső rétege nincs importálva.

## Megjegyzés

A javítás után nincs nyitott security/privacy finding. Titkossági,
authorization-, privacy-, secret-, hálózat- vagy resource-ownership sérülés a
diffben nem volt.
