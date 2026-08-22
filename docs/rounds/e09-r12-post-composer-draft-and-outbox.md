# E09-R12 — Flutter post composer, draft és outbox

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 12
- **Kör-azonosító:** `E09-R12`
- **Branch:** `<motor>/e09-r12-post-composer-draft-and-outbox`
- **Előfeltétel:** `E09-R11` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a gamifikáció E08-R04 activity-outbox mintáját (`lib/features/gamification/data/activity_outbox_repository.dart`) — a Community outbox ugyanazt a stabil-ID + retry-állapot mintát követi. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/application/controllers/post_composer_controller.dart",
  "lib/features/community/data/local/community_draft_store.dart",
  "lib/features/community/application/outbox/community_outbox.dart",
  "lib/features/community/presentation/screens/post_composer_screen.dart",
  "test/features/community/application/post_composer_test.dart",
  "test/features/community/application/community_outbox_test.dart",
  "docs/rounds/e09-r12-post-composer-draft-and-outbox.md",
]
gate_tests = [
  "test/features/community/application/post_composer_test.dart",
  "test/features/community/application/community_outbox_test.dart"
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

Megbízható, adatvédelmi előnézetet biztosító posztkészítés online és offline állapotban — a közzététel előtt pontos preview, offline queue hamis siker NÉLKÜL.

## 2. Jelenlegi állapot — mért tények

- A Kör 11 post-endpoint MA idempotency-key-t vár — ez a kör adja a kliensoldali generátort és a lokális draft/outbox tárolást
- A gamifikáció `ActivityOutboxRepository` (E08-R04) MÁR bizonyított mintát ad a stabil-ID + retry-állapot outboxra — ez a kör erre a mintára épít, nem talál ki újat

## 3. Scope

**Benne van:** composer state machine: source, body, fields, audience, media, preview, sending, success, failure · field-level share kapcsolók + végső preview · lokális, verziózott draft repository user scope-pal · Community outbox mutáció stabil mutation/idempotency ID-val · offline publish: pending állapot, sosem hamis siker · app kill/restart utáni draft és pending-post helyreállítás · logout: dokumentált policy a ki nem küldött draftra.

**NINCS benne (tilos):**

- Média feltöltés — Kör 18 (a composer csak jelzi, hogy médiát csatolna).
- Feed megjelenítés — Kör 14.
- `docs/adr/**`, `tools/**`, `.github/**`, `backend/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/application/controllers/post_composer_controller.dart` | ÚJ |
| `lib/features/community/data/local/community_draft_store.dart` | ÚJ |
| `lib/features/community/application/outbox/community_outbox.dart` | ÚJ |
| `lib/features/community/presentation/screens/post_composer_screen.dart` | ÚJ |
| `test/features/community/application/post_composer_test.dart` | ÚJ — a §6 cellái |
| `test/features/community/application/community_outbox_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/gamification/**` (csak a mintát követi, nem importálja) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 Offline publish PENDING állapotot mutat, SOHA nem hamis sikert

A composer nem zárja le "sikeresként" a küldést, amíg a szerver nem erősítette vissza — az offline állapot explicit, látható UI-jelzés.

**NEM elfogadható gyengítés:** egy optimista "Közzétéve!" üzenet megjelenítése a tényleges szerver-válasz előtt — a felhasználó azt hinné, a poszt élesben van.

### 5.2 Az outbox mutation-ID stabil és a kliensben generált idempotency key

App-restart után ugyanaz a mutation folytatódik, nem generálódik új ID — így egy megszakadt küldés nem duplikálhat.

### 5.3 Hiba esetén a felhasználó szövege SOSEM vész el

A draft minden karakterleütés után (debounce-olva) lokálisan perzisztál — egy hálózati hiba vagy app-crash nem viszi el a beírt szöveget.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Közzététel előtt pontos preview látható (audience, mezők, média-jelzés) | `post_composer_test.dart` |
| A2 | Offline retry nem hoz létre dupla posztot | `community_outbox_test.dart` |
| A3 | Dupla tap a küldés gombon nem indít két mutációt | `post_composer_test.dart` |
| A4 | App kill és restart után a draft és a pending post helyreáll | `community_outbox_test.dart` |
| A5 | A felhasználó szövege hiba esetén megmarad | `post_composer_test.dart` |
| A6 | Logout kezeli a ki nem küldött draftot a dokumentált policy szerint | `post_composer_test.dart` |
| A7 | Az érzékeny mezők (audio-csatolás) alapból KI vannak kapcsolva a preview-ban | `post_composer_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A composer 'Közzétéve' állapotra vált a szerver válasza előtt | A1 |
| Az outbox retry új mutation-ID-t generál minden próbálkozáskor | A2 |
| A küldés gomb nincs disable-elve a hívás alatt | A3 |
| App-restart után a pending mutation elvész | A4 |
| Egy hálózati hiba törli a composer szövegmezőjét | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az outbox retry-logikáját úgy, hogy minden próbálkozáskor ÚJ mutation-ID-t generáljon, futtasd offline szimulációval → az **A2** cellának PIROSNAK kell lennie (duplikált poszt) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/post_composer_test.dart test/features/community/application/community_outbox_test.dart
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

1. `community_draft_store.dart` — lokális, verziózott, user-scope-olt draft tárolás.
2. `community_outbox.dart` — stabil mutation-ID (a gamifikáció E08-R04 mintája alapján), retry-állapot.
3. `post_composer_controller.dart` — a teljes state machine.
4. `post_composer_screen.dart` — preview, field-toggle, audience-választás.
5. App-kill/restart helyreállítási teszt.
6. Logout draft-policy.
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A hamis "sikeres" visszajelzés.** A legkínosabb felhasználói élmény ebben a körben — egy poszt, amit a user sikeresnek hisz, sosem jut el a szerverre (A1).
- **A mutation-ID újragenerálása retry-nál.** Ez pontosan az a hiba, amit az E08-R04 outbox-minta már megoldott máshol — itt is ugyanaz a hibaosztály fenyeget (A2).
- **Az elveszett draft.** Egy órákig írt komplex poszt egyetlen crash-től elveszne enélkül (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
