# ADR 0378 — Achievement presentation és privacy-safe evidence

- **Státusz:** elfogadva (E08-R15 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R15` — Achievement UI és részletes evidence
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0374`](0374-achievement-domain-and-catalog-contract.md),
  [`0377`](0377-indexed-idempotent-achievement-evaluation.md)

## Kontextus

Az R13 stabil, lokalizációs kulcsokra hivatkozó definíciókat és hidden flaget
ad. Az R14 kész, normalizált progresszt, completion timestampet, ledger-
hivatkozást és fail-closed technikai diagnosztikát szállít. Egyik contract sem
ad felhasználónak szánt részletes evidence-szöveget.

Az Analyze modell nyers, session-közeli chord- és strum-timeline-t,
confidence-ot és opcionális ML-diagnosztikát hordoz. Ezek megjelenítése vagy
presentation contractba emelése megsértené a privacy-by-default határt. A
hidden eredmény pedig nemcsak közvetlen szöveggel, hanem progressz-, category-
filter- vagy semantics-ágon is kiszivároghat.

## Döntés

1. **Caller-fed presentation.** A képernyők immutable katalógus- és R14
   progressz-projekciót kapnak. Nem olvasnak repositoryt, storage plugint,
   faliórát vagy Analyze sessiont, és nem számítanak rewardot.

2. **Zárt evidence reason code.** A részletes nézet egy zárt
   `AchievementEvidenceReasonCode`-ot és már aggregált current/target értékeket
   kap. A UI kizárólag ezt lokalizálja és formázza. A contract nem tartalmazhat
   event/session ID-t, waveformot, audio/video payloadot, chord/strum timeline-t,
   confidence-listát vagy szabad user-szöveget. Ismeretlen kód lokalizált,
   privacy-safe általános magyarázatra esik vissza.

3. **Hidden fail-closed.** Locked hidden állapotban cím, leírás,
   accessibility-leírás, progressz, category és evidence nincs a widget- vagy
   semantics-fában. Az `all` filter legfeljebb generikus lokalizált secret
   placeholdert mutat; `in-progress` és category filter completion előtt nem
   adja vissza az elemet. Unlock után a normál tartalom felfedhető.

4. **A progressz kész érték.** A UI az R14 `AchievementProgress.value`,
   `completedAt` és ledgerhez kötött completion állapotát jeleníti meg. Nem
   értékeli újra az objective-et, nem képez XP-t és nem ír főkönyvet. A
   százalék és locale-helyes dátum pusztán megjelenítési formázás.

5. **Validált detail argumentum.** A detail képernyő az achievement ID-t a
   caller-fed listában exact egyezéssel oldja fel. Hiányzó vagy ismeretlen ID
   lokalizált not-found állapot; nincs implicit első elem, prefix-egyezés vagy
   kivétel.

6. **Lokalizáció és accessibility.** A katalógus lowerCamelCase kulcsait a
   presentation explicit, fail-closed lokalizációs lookupja oldja fel. Minden
   új UI-copy a gamification feature ARB-szegmensből jön; a tile és detail
   teljes semantics labelt, kis képernyőn görgethető, legalább 200%-on
   túlcsordulásmentes layoutot ad.

## Következmények

Az achievement felület route- és storage-wiring nélkül is tesztelhető, és a
következő integrációs kör explicit adatot adhat neki. Új reason code vagy új
katalógus-lokalizációs kulcs presentation-frissítést igényel; ez szándékos
fail-closed ár a nyers vagy ismeretlen adat automatikus megjelenítésének
elkerüléséért.

## Mérce

Az E08-R15 brief A1–A8 cellái: filter-mátrix hidden category/in-progress
negatív esetekkel; locked hidden widget- és semantics-szivárgás; exact ID
not-found; zárt reason-code lokalizáció; source scan, amely tiltja az Analyze,
timeline, waveform, raw audio és session-ID contractot; EN/HU ARB-lefedettség;
1.99/2.0/2.01 és 1.0/2.0/3.0 text-scale layout-mátrix. A reviewer az
`Opacity(0)` hidden-title mutációval bizonyítja, hogy az A2 őr valóban piros.
