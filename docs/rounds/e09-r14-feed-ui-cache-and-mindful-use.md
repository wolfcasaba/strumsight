# E09-R14 — Feed UI, cache és tudatos használat

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 14
- **Kör-azonosító:** `E09-R14`
- **Branch:** `<motor>/e09-r14-feed-ui-cache-and-mindful-use`
- **Előfeltétel:** `E09-R13` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 13 cursor-szerződést és a Kör 10 artifact-típusokat — a card-registry ezekre a MEGLÉVŐ típusokra épül, ismeretlen artifact-típusra fallback-kártyát ad, nem hibázik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/application/controllers/feed_controller.dart",
  "lib/features/community/data/local/feed_cache.dart",
  "lib/features/community/presentation/screens/following_feed_screen.dart",
  "lib/features/community/presentation/widgets/feed_card_registry.dart",
  "test/features/community/presentation/following_feed_test.dart",
  "docs/rounds/e09-r14-feed-ui-cache-and-mindful-use.md",
]
gate_tests = [
  "test/features/community/presentation/following_feed_test.dart"
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Reszponzív, hozzáférhető feed offline cache-sel, végtelen engagement-minták NÉLKÜL — explicit "Továbbiak betöltése", nincs autoplay, van vége (end-of-feed).

## 2. Jelenlegi állapot — mért tények

- A Kör 13 backend feed MA készen áll — ez a kör az első UI-fogyasztója
- A Kör 10 artifact-típusok (hét altípus) MA léteznek — a card-registry ezekre mappelt, ismeretlen típusra fallback-kártyát ad

## 3. Scope

**Benne van:** feed controller state: initial/loading/content/refreshing/paging/offline/error/end · lokális, user-scope-olt, bounded feed cache · pull-to-refresh scroll-pozíció megőrzéssel + új-poszt jelzéssel · explicit "Továbbiak betöltése" (kontrollált pagination) · nincs autoplay; média csak user interactionre indul · end-of-feed nézet + "Gyakorlás indítása" CTA · feed card registry artifact-típusonként, ismeretlen típusra fallback.

**NINCS benne (tilos):**

- Reakció/komment interakció — Kör 15/16.
- Explore feed — külön, jövőbeli feature flag mögötti kör.
- `docs/adr/**`, `tools/**`, `.github/**`, `backend/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/application/controllers/feed_controller.dart` | ÚJ |
| `lib/features/community/data/local/feed_cache.dart` | ÚJ |
| `lib/features/community/presentation/screens/following_feed_screen.dart` | ÚJ |
| `lib/features/community/presentation/widgets/feed_card_registry.dart` | ÚJ |
| `test/features/community/presentation/following_feed_test.dart` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/features/community/domain/**` (csak fogyasztás) · `lib/features/community/application/outbox/**` (Kör 12 lezárt szerződése) · `docs/adr/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs autoplay, nincs kötelező végtelen görgetés

A média user-interactionre indul; a lapozás explicit "Továbbiak betöltése" gombbal vagy egyértelmű kontrollal történik, nem automatikus infinite-scroll triggerrel.

**NEM elfogadható gyengítés:** egy scroll-listener, ami a lista aljához közeledve AUTOMATIKUSAN tölt be több oldalt — ez pontosan a §13.6 SDD-invariáns tiltott mintája.

### 5.2 A cache accountonként izolált, sosem keveredik

A lokális feed-cache kulcsa tartalmazza a profil-azonosítót — account-váltás után a régi cache nem jelenik meg átmenetileg sem.

### 5.3 Ismeretlen artifact-típus fallback-kártyát kap, nem crash-t

A card-registry defenzív: egy jövőbeli, még nem ismert artifact-típus egy generikus "tartalom nem jeleníthető meg" kártyát ad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A feed hálózati hiba esetén sem omlik össze (error state) | `following_feed_test.dart` |
| A2 | A cache nem keveredik accountok között | `following_feed_test.dart` |
| A3 | Nincs automatikus hang- vagy videólejátszás | `following_feed_test.dart` |
| A4 | Duplikált post nem jelenik meg egy session-ben | `following_feed_test.dart` |
| A5 | Ismeretlen artifact-típus fallback-kártyát kap, nem crash-t | `following_feed_test.dart` |
| A6 | Létezik egyértelmű end-of-feed állapot | `following_feed_test.dart` |
| A7 | Pull-to-refresh megőrzi a scroll-pozíciót és jelzi az új posztokat | `following_feed_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A lista automatikusan tölt be a scroll-pozíció alapján | A3 mellett termékinvariáns-sértés (§13.6), review-lelet |
| A cache kulcsa nem tartalmazza a profil-ID-t | A2 |
| Egy videó artifact automatikusan lejátszásra indul betöltéskor | A3 |
| Egy ismeretlen artifact-típus kivételt dob és a feed összeomlik | A5 |
| A pull-to-refresh a lista tetejére ugrik minden alkalommal | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy scroll-listener alapú automatikus lapozást, futtasd a widget-tesztet a "nincs autoplay/autoload" cellára → **A3**-nak PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/following_feed_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `feed_cache.dart` — bounded, profil-ID-vel kulcsolt lokális cache.
2. `feed_controller.dart` — a teljes állapotgép.
3. `feed_card_registry.dart` — a hét artifact-típus + fallback.
4. `following_feed_screen.dart` — pull-to-refresh, explicit pagination, end-state, CTA.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az automatikus infinite-scroll kísértése.** Ez a legkönnyebben "visszacsúszó" minta — sok UI-library alapból ezt ajánlja (A3/§13.6).
- **A cache-keveredés account-váltáskor.** Egy másik user korábbi feedje átmenetileg megjelenne (A2).
- **A crash ismeretlen artifact-típuson.** Egy jövőbeli, még be nem vezetett poszt-típus a teljes feedet ledöntené fallback nélkül (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
