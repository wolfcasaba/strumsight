# E08-R12 — Security és product-boundary review

Brief: `docs/rounds/e08-r12-streak-ui-v2-and-recovery-flow.md`  
Diff: `origin/main...b506516c`  
Reviewer: Sol high-risk audit · Dátum: 2026-08-20  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 0

## Pozitív határellenőrzés

- A három új production widget caller-fed és passzív: nincs provider,
  repository, route, clock, hálózat, storage, reward/ledger vagy lifecycle-owner.
- A heti input 0..7 tartományban validált, és broken állapotban sem számolódik
  újra.
- A CTA csak a hívó callbackjét hívja; nem navigál és nem ír állapotot.
- Reduced motion mellett a tartalom, ikon és szemantika megmarad.
- Secret scan: 3074 fájl, 0 lelet; architecture és l10n gate zöld.

## Megállapítások

### S1 — MAJOR — A high-risk együttérző copy-határ regressziós őre hiányos

- **Fájl:** `test/features/gamification/presentation/streak_detail_screen_test.dart:75–116`
- **Bizonyíték:** a `You lost your streak!` broken title + `Return within 2 days`
  CTA mutáció a teljes célzott suite-on 20/20 zöld maradt.
- **Hatás:** shame/urgency vagy büntető szöveges countdown átmehet a zöld kapun.
- **Kötelező javítás:** title + body + CTA, mindkét forrás-locale, tiltott szó /
  felkiáltójel / szöveges countdown őrrel; mutációs piros bizonyíték.
- **Státusz:** OPEN

### S2 — MINOR — Angol egyes számú képernyőolvasó-címke hibás

- **Fájl:** `lib/l10n/features/gamification_en.arb:8–24`
- **Probléma:** `count = 1` esetén `1 days`.
- **Javasolt javítás:** ICU plural + 0/1/2 cellák.
- **Státusz:** OPEN

## Merge-döntés

S1 nyitott MAJOR, ezért a high-risk termékhatár nem jóváhagyott; merge tilos a javítás és független re-review előtt.

