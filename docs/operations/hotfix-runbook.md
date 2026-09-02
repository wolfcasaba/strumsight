# Hotfix runbook

- **Kör:** E12-R34 (ADR 0490)
- **Scope:** production hibaelhárítás GA (Kör 33) UTÁN. A gyorsaság a
  javítás SCOPE-jának szűkítéséből jön, nem a kapuk elhagyásából (ADR 0490,
  D1). A hotfix-út gépi mércéje: `tool/release/verify_hotfix.py` +
  `test/tooling/hotfix_policy_test.dart`.

## 1. Mikor hotfix, és mikor rendes kiadás

Hotfixet csak akkor indíts, ha:

- a hiba PRODUCTION-ban jelentkezik (nem staging/lab), ÉS
- a hatása súlyos (crash-loop, adatvesztés, biztonsági rés, fizetési/hitelesítési
  törés), ÉS
- a javítás SCOPE-ja szűk (egy konkrét, izolálható hiba — nem egy feature-csomag).

Ha bármelyik feltétel hiányzik, a következő rendes SDD-kör vagy a Kör 25
release-candidate útja a helyes csatorna, nem a hotfix.

## 2. Kötelező előfeltétel: incident-azonosító

Hotfix-kérés **incident-azonosító NÉLKÜL nem indítható** (ADR 0490 D2). Az
azonosító köti a kiadást a postmortemhez — enélkül a hotfix utólag nem
auditálható.

1. Nyiss vagy azonosíts egy incidenst (pl. `INC-2026-0001` alakban).
2. Az incidenshez tartozó postmortem VÁZAT hozd létre a
   [`postmortem-template.md`](postmortem-template.md) alapján — a kitöltés a
   javítással párhuzamosan halad, nem utólag.

## 3. MANDATORY regression test — RED before the fix, GREEN after

**Minden hotfixhez KÖTELEZŐ a hibát reprodukáló regressziós teszt (ADR 0490
D4).** Ez NEM helyettesíthető manuális ellenőrzéssel — a manuális ellenőrzés
a hibát visszaengedi a következő kiadásba.

A sorrend kötött:

1. Írd meg a tesztcellát, ami a hibát reprodukálja — **fusson PIROSAN** a
   javítatlan kódon (RED). Ez a bizonyíték arra, hogy a teszt tényleg a
   hibát méri, nem valami mást.
2. Implementáld a javítást.
3. Futtasd a tesztcellát újra — **legyen ZÖLD** (GREEN). Ez a bizonyíték
   arra, hogy a javítás tényleg elhárítja a hibát.
4. A RED→GREEN párt (a teszt neve + a két futás bizonyítéka) rögzítsd az
   incidens postmortemjében.

**NEM elfogadható gyengítés:** „a hiba nyilvánvaló, a teszt elhagyható" — ha
a hiba production-ba jutott, a jelenlegi tesztlefedettség már bizonyítottan
hiányos volt rá; a regressziós cella ezt a hiányt zárja be.

## 4. A hotfix-kérés indítása

A hotfix-workflow **javaslat-fájlként** él a fán
(`docs/release/workflows/hotfix.proposal.yml`) — a `.github/workflows/**`
védett zóna (ADR 0321), a telepítés orchesztrátor/emberi lépés (ADR 0490 D6).
Telepítés UTÁN a dispatch három kötelező inputtal indul:

- `incident_id` — a §2 szerinti azonosító (kötelező).
- `previous_version` — a production-ban jelenleg futó verzió.
- `version` — a hotfix verziója. **Szigorúan nagyobb** kell legyen az
  előzőnél (ADR 0490 D5) — a `tool/release/verify_hotfix.py` kérés-módja ezt
  a dispatch ELŐTT is ellenőrizhető:

  ```bash
  python3 tool/release/verify_hotfix.py --incident-id <incident_id> --previous-version <previous_version> --version <version>
  ```

- `summary` — egy soros emberi összefoglaló, az approval-rekordba kerül.

## 5. A kapuk NEM kerülhetők meg

A hotfix-workflow ugyanazt a két kaput futtatja, mint egy rendes kiadás:

- a közös Flutter mérce-lánc (`./.github/actions/flutter-gates` composite —
  format, analyze, architecture, secret/l10n/asset scan, teszt, property gate,
  a §3 regressziós cellával együtt);
- a release security scan és a production signing lépés — **feltétel
  nélkül**, nincs `if:`, nincs `continue-on-error:`, és nincs olyan
  `workflow_dispatch` input, ami kihagyná őket (ADR 0490 D1).

A jóváhagyás a build ELŐTT áll (`approve-hotfix` environment-kapu), és minden
építő/aláíró/feltöltő job tranzitívan `needs:`-eli (ADR 0490 D3).

## 6. Kiadás után

1. Zárd le a postmortemet a §2/§3 bizonyítékokkal (RED→GREEN teszt, root
   cause, javítás linkje).
2. Vezesd be a hotfix verzióját a következő 7./14. napi post-launch riportba
   ([`post-launch-day7.md`](../release/post-launch-day7.md) /
   [`post-launch-day14.md`](../release/post-launch-day14.md)) mint kiadási
   eseményt.
3. Ha a hotfix mögötti hiba a rendes tesztlefedettségben tárt fel rést, a
   §3 regressziós cellát VÉGLEGESEN tartsd a suite-ban — nem törölhető a
   hotfix lezárása után.
