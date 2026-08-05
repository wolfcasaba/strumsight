# Review — E04-R18 Tutor Home, Chat UI & streaming UX

- **Reviewer:** Claude (Opus 4.8), orchestrátor-oldali független review (ADR 0055)
- **Implementer:** MiniMax M3 (legacy override, `mm-round.sh`)
- **Branch:** `minimax/e04-r18-tutor-home-chat-ui` @ `608319d`
- **Verdikt:** **APPROVED** — nulla OPEN BLOCKER/MAJOR
- **Gate:** `tools/round-gate.sh test/features/ai_tutor/presentation` — MINDEN ZÖLD
  (format, analyze `No issues found`, test `All tests passed` +20, architecture,
  secrets, l10n), a review-oldalon **függetlenül újrafuttatva** a `/home/ubuntu/
  ss-mm-e04-r18` klónban.

## Scope

`scope_audit=ok` (12 fájl, mind az `allowed_paths` listán; base `c5cee9f`). Az
importhatár tiszta: a `tutor_providers.dart` kizárólag `ai_tutor/` (application/
data/domain) + flutter + l10n importokat használ — nincs kereszt-feature belső
import, nincs `remote`/cloud gateway, nincs `Dio`/`http`. A §0.0-REV-1
route-fájl korrekció (`lib/app/routing/app_route.dart` + `app_router.dart`)
additív; a `feature_flags.dart` érintetlen.

## Acceptance (§6) — leletenként, a runnable teszttel

| Kritérium | Bizonyíték | Állapot |
|---|---|---|
| Flag-mátrix ON→route, OFF→Live fallback (mindkét route) | R18-R1..R4 (home_screen_test) | ✅ |
| empty-state / send / stream / cancel / retry | R18-A1..A5 | ✅ |
| banner-állapotok **különböznek** (offline≠consent≠rate≠error) | R18-A8..A10 (distinct semantics label) | ✅ |
| unknown-block **biztonságos** (monospaced, nem futtatható HTML) | R18-A11 | ✅ |
| large-text scroll + composer megmarad; scroll-anchoring | R18-A12, A13 | ✅ |
| screen-level semantics; streaming-batching (nem token-enként) | R18-A14, A16 | ✅ |
| hu/en semantics | R18-A15 | ✅ |

## Falszifikáció (mutációs próbák)

- **Flag-gating él:** az `app_router.dart` `if (aiTutorEnabled)` blokk
  eltávolítása az R18-R2/R18-R4 (OFF→Live) cellákat pirosra váltja — a flag-check
  ténylegesen mérve van, nem csak az ON-oldal.
- **A4 (visible Stop):** a Stop akciót a `status.isActive` gate rendereli;
  eltávolítva R18-A4 pirosra vált.
- **A13 (new-bubble rebuild):** a `Listenable` listener + `setState` a
  controller-notify-ra épít; a listener nélkül R18-A13 pirosra vált.

## Megjegyzések (NOTE, nem blokkoló)

- A cloud gateway szándékosan kimaradt (E04-R19); a UI a fake/local útra köt,
  a tesztek `FakeController` override-dal hajtják — a §5.1/§3 TILOS („valódi
  cloud/gateway") betartva.
- Két teszt (R18-A4, A13) az első futásban piros volt; a MiniMax **egy javító
  körben** (`608319d`) zöldre vitte — a lánc normál útja, H4 nem áll fenn.

## Megjegyzés a futásról

Az első implementer-futás a box lassúsága miatt a 3600s abszolút időkorlátot
elérte a gate teszt-lépésében (`status=timeout`, `scope_audit=ok`), commit
előtt; az orchestrátor a scope-tiszta munkát megmentette (`f959041`), a
`dart format` gate-lépést kézzel rendezte (`7d2783f`, mechanikus), a két valódi
teszt-bukást pedig a MiniMax javító köre oldotta fel. A merge-kapu ettől
független: exact-SHA zöld CI (full-gate + router-ci).
