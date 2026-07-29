# Kör-brief (Round Brief) — sablon és szabály

A **kör-brief** a Claude tervezői kimenete és a Codex implementációs szerződése
([ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15).

**Hely:** `docs/rounds/eXX-rYY-<slug>.md`
**Commitolva a kör indítása ELŐTT.** Ha nincs brief, a kör nem Ready
(`03-definition-of-ready.md`).

A legfontosabb szekció az **engedélyezett fájlok** listája: ez teszi a
scope-tágulást objektíven ellenőrizhetővé a review-ban (`git diff --stat` a
listával összevetve), a korábbi, sessionnel elszálló prompt-megállapodás
helyett.

---

## Sablon

```markdown
# EXX-RYY — <cím>

Státusz: PLANNING | IN PROGRESS | IN REVIEW | DONE
SDD: docs/sdd/<fejezet>.md §<szakasz>
Branch: codex/eXX-rYY-<slug>
Brief szerzője: Claude · Implementáció: Codex

## 1. Cél

Egy bekezdés: mi a kör kimenete, és miért most.

## 2. Jelenlegi állapot

A ténylegesen elolvasott kód alapján — ne a dokumentációból feltételezve.
Fájlnevek és a mai viselkedés.

## 3. Scope

**Benne:**
- ...

**Kívül (ebben a körben TILOS):**
- ...

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → MEGÁLLÁS és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/...` | ... |
| `test/...` | ... |

**Tilos zóna** (a másik ágens területe vagy scope-on kívül): `...`

Közös fájlba (pl. `lib/core/foundation/app_failure.dart`) csak a kör saját
szekciójába szabad írni.

## 5. Kötött architekturális döntések

Amit a kör NEM tervezhet újra. Új ADR nélkül nem térhet el tőle.
Előre kiosztott ADR-szám: `00NN`.

## 6. Acceptance criteria

- [ ] Mérhető, ellenőrizhető állítások — nem „jól működik".

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — soha ne láncold `&&`-del):

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze lib/ test/
flutter test test/<érintett terület>
gh workflow run build-apk.yml --ref codex/eXX-rYY-<slug>
```

A teljes suite + property gate + APK a CI-ban ([ADR 0053](../adr/0053-ci-full-test-suite.md)).

## 8. Implementációs sorrend

1. ...

## 9. Kockázatok

- ...

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet (ne állíts sikert, ami nem futott).
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk.
- Follow-up issue-k.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/eXX-rYY-review.md`
```

---
