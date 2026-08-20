# E08-R12 — Correctness review

Brief: `docs/rounds/e08-r12-streak-ui-v2-and-recovery-flow.md`  
Diff: `git diff origin/main...b506516c`  
Reviewer: Sol (`gpt-5.6-sol`) · Dátum: 2026-08-20  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | Mindkét forrás-locale title/body/CTA őre; tiltott cím és CTA mutáció külön-külön piros, canonical copy zöld. |
| A2 | ✅ | CTA egyszeri callback + időformátum- és szöveges-countdown őr; `Return within 2 days` mutáció piros. |
| A3 | ✅ | `streak_status_card.dart:72–76`; planned-rest/broken páros widgetcella. |
| A4 | ✅ | `streak_detail_screen.dart:17–23,92`; 0/4/7 + broken×4 és forbidden-owner forrásőr. |
| A5 | ✅ | `app_router.dart:139` változatlan legacy `StreakScreen`; a legacy suite 20/20 zöld. |
| A6 | ✅ | A három production fájlban nincs felhasználói literál vagy adat-owner; l10n freshness/parity zöld. |
| A7 | ✅ | 1.0/2.0/3.0 × két méret zöld; fix `height: 80` mutáció a 2.0 cellát 264 px overflow-val pirosra vitte, restore után zöld. |
| A8 | ✅ | Teljes, mértékegységes semantics-címkék; normál/reduced duration páros cella, a szöveg/ikon/szemantika megmarad. |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-terra-e08-r12 --brief docs/rounds/e08-r12-streak-ui-v2-and-recovery-flow.md --base a7611946...` → `Legacy scope audit OK`, 10 módosított útvonal, 0 generated/ignored. A working tree a wrapper utófeldolgozása után tiszta. Az implementer `gate_shape=VIOLATION` jelzését nem tekintettem gate-bizonyítéknak; a teljes artefaktumot friss review-klónban újrafuttattam.

## Megállapítások

### F1 — MAJOR — A shame/urgency/countdown őr nem a teljes felhasználói copy-határt méri

- **Fájl:** `test/features/gamification/presentation/streak_detail_screen_test.dart:75`
- **Probléma:** az A1 cella csak a `streakV2BrokenBody` értéket vizsgálja. A broken címet és a recovery CTA-t nem ellenőrzi; az A2 cella csak `NN:NN` mintát tilt, ezért a szöveges countdown átcsúszik.
- **Mért bizonyíték:** eldobható review-mutációban `streakV2BrokenTitle = "You lost your streak!"` és `streakV2RecoveryCta = "Return within 2 days"`; segment-generálás + `flutter gen-l10n` után a teljes új widget-suite **20/20 zöld** maradt.
- **Hatás:** a high-risk együttérző nyelvi termékhatár regressziója zöld CI mellett kerülhetne be.
- **Kötelező javítás:** mindkét forrás-locale broken title/body/CTA szövegét vizsgáló tiltott-nyelv és írásjel őr; szöveges countdown minták (`within/napon belül`, szám + időegység) tiltása; mutációs bizonyíték a handoffban.
- **Státusz:** FIXED (`6ee12f46`) — mindkét forrás-locale title/body/CTA őrzött; reviewer-mutáció külön title és külön CTA esetben is piros, restore után zöld.

### F2 — MINOR — Az angol egyes számú semantics nyelvtanilag hibás

- **Fájl:** `lib/l10n/features/gamification_en.arb:8`
- **Probléma:** a current/longest/total semantics sablon mindig `days`, így érvényes `count = 1` esetén `1 days` hangzik el.
- **Hatás:** képernyőolvasós minőségromlás, az A8 „teljes, mértékegységes” címkéjének gyenge széle.
- **Javasolt javítás:** ICU plural form és 0/1/2 semantics cellák; ez a körben kis diffel javítható.
- **Státusz:** FIXED (`6ee12f46`) — ICU plural form és 0/1/2 cellák.

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| format | 1727 fájl, 0 változás | ✅ |
| analyze | No issues found | ✅ |
| új widgettesztek | 21/21 zöld | ✅ |
| legacy streak suite | 20/20 zöld | ✅ |
| architecture / secrets / l10n | zöld / 3074 fájl, 0 lelet / 1437 pár | ✅ |
| valódi-sértés A7 | fix 80 px → 264 px overflow + explicit assertion failure | ✅ |
| re-review mutáció | tiltott title piros; csak CTA countdown piros; restore zöld | ✅ |
| CI teljes suite + property | re-review után dispatchelendő | ⏳ |

## Merge-döntés

Az F1/F2 lelet zárva, a független re-review APPROVED. Merge csak a változatlan exact SHA-n zöld Full Gate és Router CI után.

## Re-review — 2026-08-20

Javító commit: `6ee12f46`. Friss klón:
`/tmp/rereview-e08-r12-71eAeY/repo`. A teljes `tools/round-gate.sh` 7/7
zöld; 21 V2 + 20 legacy teszt. A reviewer külön próbálta a tiltott broken
title-t és — canonical title mellett — a szöveges CTA-countdownt; mindkettő az
A1 cellát pirosra vitte. Restore után a célzott cella zöld és a klón tiszta.
