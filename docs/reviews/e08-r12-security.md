# E08-R12 — Security és product-boundary review

Brief: `docs/rounds/e08-r12-streak-ui-v2-and-recovery-flow.md`
Diff: `origin/main...terra/e08-r12-streak-ui-v2-and-recovery-flow`
Reviewer: Sol high-risk audit · Dátum: 2026-08-20
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

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
- **Státusz:** FIXED (`6ee12f46`) — forrás-locale title/body/CTA őr; független tiltott-title és CTA-countdown mutáció külön-külön piros.

### S2 — MINOR — Angol egyes számú képernyőolvasó-címke hibás

- **Fájl:** `lib/l10n/features/gamification_en.arb:8–24`
- **Probléma:** `count = 1` esetén `1 days`.
- **Javasolt javítás:** ICU plural + 0/1/2 cellák.
- **Státusz:** FIXED (`6ee12f46`) — ICU plural + 0/1/2 cellák.

## Merge-döntés

Az S1/S2 lelet zárva. A high-risk caller-fed, offline, reward-mentes és együttérző copy-határ APPROVED; merge csak exact-SHA zöld CI után.

## Re-review — 2026-08-20

A friss izolált klón teljes gate-je zöld. A `You lost your streak!` mutáció
felkiáltójel/tiltott nyelv miatt piros; canonical title mellett a `Return
within 2 days` CTA külön is piros a szöveges-countdown őrön; restore után
zöld. Nincs provider/repository/route/network/clock/storage/reward owner,
secret vagy új lifecycle-erőforrás.

## Végső upstream-szinkron ellenőrzés — 2026-08-20

Az exact `01437c81` head már tartalmazza a H3 presentation-guard healjét.
Friss izolált klónban a 7/7 kör-gate és a scope-audit zöld; 0 listán kívüli
production útvonal és 0 secret lelet. Eldobható `SharedPreferences`
presentation-import célzottan pirosra vitte a réteghatár-őrt, miközben a
shipping Flutter-importok zöldek maradtak. A tiltott broken-title mutáció az
A1 copy-őrt célzottan pirosra vitte. Restore után mindkét célzott teszt zöld,
így a high-risk product/security verdikt változatlanul **APPROVED**.

## H8 protocol-heal utáni végső security re-review — 2026-08-20

Az exact `b084cf1d` kombinált HEAD tartalmazza a H8 protocol-healt és az
aktuális `origin/main @ c69653d1` csúcsot. Friss izolált klónban a scope-audit
0 sértést, a teljes kör-gate 7/7 zöld eredményt adott, a secret scan 3090
fájlon 0 leletet talált. A caller-fed production diff változatlan: nincs
provider, repository, route, hálózat, clock, storage, reward-owner vagy új
lifecycle-erőforrás.

A közvetlen `package:shared_preferences/` presentation-import a dedikált
architecture dependency cellát pirosra vitte; a tiltott broken-title mutáció
az A1 copy-őrt, a fix 80 px kártyamagasság az A7 a11y cellát vitte pirosra.
Restore után a célzott őrök zöldek, a review-klón tiszta. A high-risk verdikt
változatlanul **APPROVED**, nyitott security/product-boundary lelet nincs.
