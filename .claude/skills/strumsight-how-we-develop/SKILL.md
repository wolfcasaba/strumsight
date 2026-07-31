---
name: strumsight-how-we-develop
description: StrumSight fejlesztési modell — kötelező onboarding minden olyan session elején, ahol a modell (pl. Claude Opus 5 vagy bármely új motor) még nem ismeri a projektet. Átadja az SDD-váltóbot lánc lényegét (Claude tervez → Codex/M3 implementál → Claude review-z → merge zöld kapuval), a doksi-elsőbbségi láncot, a box mért igazságait (OOM-csapda, nincs lokális Android SDK, CI = evidencia) és a memóriarendszereket. Használd session-kezdéskor, "hogyan fejlesztünk", "mi a workflow", "onboarding" kérdésekre, vagy mielőtt bármilyen StrumSight-feladatba kezdesz.
---

# StrumSight — hogyan fejlesztünk itt

**Mi ez:** offline, on-device gitár akkord- + pengetésirány-detektor (Flutter,
Dart ^3.12.2, Material 3, Riverpod 3 kézi providerek, opcionális FastAPI+SQLite
backend a `backend/`-ben). A detektálás SOHA nem megy hálózatra; az app
kijelentkezve teljes értékű.

## Session-kezdő olvasási sorrend (kötelező, ebben a sorrendben)

1. `HANDOFF.md` — az élő állapot: mi kész, mi a pontos következő feladat (§6).
2. `AGENTS.md` — a kötelező ágens-szabálykönyv (scope, gate-ek, git, szerepek §15).
3. `docs/sdd/00-index.md` + a kijelölt kör SDD-fejezete.
4. Az érintett TÉNYLEGES kód és tesztek — soha ne a dokumentációból feltételezz.

**Doksi-elsőbbség ütközésnél** (AGENTS.md §2): user-utasítás → kijelölt SDD-kör
→ SDD-fejezet → Chapter 1 + AGENTS.md → ADR → HANDOFF → README/CLAUDE.md.
Elavult doksit nem követünk némán — az eltérést dokumentáljuk.

## A fejlesztési modell: SDD-váltóbot (ADR 0055)

Egy fejlesztési egység = **egy kör** (E<epic>-R<kör>, pl. E02-R06). Egy session
= egy kör; a kör lezárása után a session MEGÁLL, a következő kör ÚJ sessionben
indul (ADR 0052). A körön belül a lánc:

```
Claude tervez (kör-brief, engedélyezett-fájllistával)
  → implementer motor dolgozik (Codex VAGY MiniMax M3, ADR 0069)
  → Claude független review-t ír (READ-ONLY, docs/reviews/)
  → a motor javít
  → Claude CI-t dispatchel és zöld kapuval squash-merge-el
```

Egyszerre EGY ágens ír. Részletek: `sdd-round-driver` skill (levezénylés),
`round-brief-prep` skill (brief-írás), `sdd-round-review` skill (review).

## A box mért igazságai (megsérteni = órák elvesztése)

- **`flutter analyze` és `flutter test` KÜLÖN hívás — láncolva (`&&`) OOM.**
  A mérce egyetlen futtatható artefaktum, lásd lent.
- **Nincs lokális Android SDK** — `flutter build apk`-t ne is próbálj; APK és
  teljes suite MINDIG CI-ből: `gh workflow run build-apk.yml --ref <branch>`.
  A teljes suite lokálisan ~15 perc, CI-ban ~4–5 → **a regresszió-evidencia a
  CI-run link, nem lokális kimenet** (ADR 0053).
- EGY win32 major a fán (`flutter_secure_storage` v10-re pinnelve) — új plugin
  előtt win32-ellenőrzés.
- Riverpod 3.3.2: `AsyncValue.value` (nullable), NINCS `.valueOrNull`.
- `lucide_icons_flutter` ikonnevek csak compile-kor buknak — nevet ellenőrizz.
- Backend-írás `try/catch`-ben némán elveszhet — synced állapot CSAK
  szerver-megerősítés után; hibás push retry-t kap.

## Verify gate (mielőtt bármit „kész"-nek mondasz)

A mérce egyetlen futtatható artefaktum, nem prompt-szöveg — a csővezeték
(`| tail`, `| head`, `&&`) elrejti a kilépési kódot, így a „minden gate zöld"
jelentés bizonyíthatatlanná válik ([`docs/LESSONS.md` L09](docs/LESSONS.md);
mért eset: E02-R07). A normatív forrás: `AGENTS.md` §12.

```bash
tools/round-gate.sh test/<a kör területe> [további teszt-útvonal ...]
```

A script a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket egymás után, KÜLÖN processzként futtatja; az első piros lépésnél a
helyes kilépési kóddal megáll. A teljes suite + randomizált property gate +
APK a CI-ből jön (lásd fenn). Backend-érintésnél a `cd backend && .venv/bin/python
-m pytest` a kiegészítő lépés — NEM a gate része.

Új DSP-viselkedés ⇒ randomizált property `test/property/`-be (`PROPERTY_SEED`).
DSP-paraméter változás ⇒ `docs/rag/chunks/` frissítés UGYANABBAN a commitban.
A VÉGSŐ elfogadás a user valódi-gitáros APK-tesztje — synthetic green ≠ done.

## Git-szabályok (ezen a boxon több autonóm ágens is dolgozhat!)

- **Explicit staging** — `git add .` / `git add -A` TILOS (behúzza a másik
  ágens munkáját). Destruktív parancs (`reset --hard`, `clean -fd`,
  `checkout -- .`) user-engedély nélkül TILOS. Zavaros working tree → állj
  meg és jelents.
- Branch: `codex/eXX-rYY-rovid-leiras` (vagy `mm/...` M3-körnél); main-re
  közvetlen kör-push nincs; Conventional Commit előtag.
- **Zöld-kapus auto-merge** (ADR 0052): MINDEN gate zöld (CI-s teljes suite is)
  → squash-merge külön jóváhagyás NÉLKÜL. Bármi piros/hiányzik → merge tilos.
- Merge/dispatch előtt `gh pr list` + `gh run list` — egy párhuzamos autonóm
  driver nyithatott már PR-t ugyanarra a körre.

## Nem tárgyalható termékhatárok (AGENTS.md §5 — röviden)

Nyers audio nem hagyja el az eszközt · kijelentkezve+diagnostics-off nincs
rejtett hálózati kérés (rendszerteszt őrzi) · egy mic-owner egyszerre · gyenge
confidence nem állítható biztosnak · secret/nyers audio nem kerül logba/commitba.

## Memóriarendszerek (a kör végén MIND frissül)

| Rendszer | Mikor | Hogyan |
|---|---|---|
| `HANDOFF.md` | minden kör után | a fájl végi „How to update" szerint; történet → `docs/handoff-archive.md` |
| Git-notes buffer | minden kör-commit után | `git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug> engine=<motor>"` + `git push origin 'refs/notes/*'` |
| Viking (közös agy, MCP) | kör végén | `viking_remember` a tanulságokra + KÖTELEZŐ `viking_session_commit` |
| Auto-memory | nem-triviális tanulságnál | fájl + MEMORY.md index-sor |

Kereshető korpuszok: `node tools/rag.mjs --corpus plan "..."` (tervek),
`tools/flutter-rag.mjs` (Dart kód), `tools/dsp-rag.mjs` + `docs/rag/chunks/`
(DSP-igazság).
