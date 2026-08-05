# E04-R05 review — Context adapterek és TutorContextSnapshot

- **Kör:** E04-R05
- **Branch:** `codex/e04-r05-context-adapters-and-snapshot`
- **Reviewed head:** `e5361e0` (impl) a `f08d967` pre-flight fölött, main baseline `ee893da`
- **Implementer:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 (független, read-only)
- **Verdikt:** **CHANGES REQUESTED → (javító kör után) APPROVED** — 1 MAJOR (M1, lezárva), 1 NOTE
- **M1 (MAJOR, exact-SHA CI-n mérve, `run 30969874174`, head `ac54952`):** a hat
  adapter import-audit tesztje (`*_context_adapter_test.dart`, „imports only the
  … public boundary") `Process.run('rg', …)`-gal shell-el ki `ripgrep`-re, ami a
  CI-runneren NINCS telepítve → `ProcessException: No such file or directory` →
  6 teszt PIROS (`2645 passed, 6 failed`). Lokálisan zöld volt, mert ezen a boxon
  van `rg` — környezetfüggő, hordozhatatlan teszt, és épp az AC #1 (nulla
  source-internal import) bizonyítéka. **Javítás iránya:** a `rg` subprocess
  helyett tiszta Dart `File(path).readAsStringSync()` + import-sor szkennelés
  (nincs külső bináris függőség). Csak teszt-fájlok, `allowed_paths`-on belül.
  **Javító kör:** Codex, findings-listával; utána a review frissül + exact-SHA
  CI újradispatch.
- **Review mód:** izolált `/tmp/review-e04-r05` klón, saját gate-futtatás, scope-audit,
  eldobható mutáció-próbák (a klónban, a körbranchre soha nem kerültek).

## 1. Gate (izolált klón, artefaktum — nem prompt-szöveg)

A `tools/round-gate.sh test/features/ai_tutor/application/context` **mind a négy
lépésben ZÖLD** (a körbranch worktree-jében futtatva, csonkítatlan kimenettel):

```
format    zöld
analyze   zöld
test test/features/ai_tutor/application/context   zöld  (20/20 teszt)
architecture   zöld  (12 allowlisted deviation)
```

## 2. Scope-audit

`git diff --stat origin/main...HEAD`: **23 fájl**, mind a brief §4
`allowed_paths`-án belül (12 `lib` + 10 `test` + a brief maga). Listán kívüli
fájl: **nincs**. Source feature belső fájl módosítása: **nincs**.

## 3. Acceptance criteria — tételes bizonyíték

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| 1 | Adapter csak saját `public.dart` | `grep` az adapterekben: mind a hat KIZÁRÓLAG `features/<x>/public.dart`-ot importál; nulla `domain/`/`data/`/`presentation/` import. A kör tesztjei `rg`-import-audittal is mérik. | ✓ |
| 2 | Immutable + `requestId` | `@immutable`, `List.unmodifiable` a `fields`/`truncatedFields`-en, mély `_freezeMap`/`_freezeValue` (unmodifiable map/list), üres requestId → `ArgumentError`. Azonos bemenetre azonos `canonicalJson`. | ✓ |
| 3 | Redaction: audio/abs-path/secret/**teljes ÉS csonkolt** lyrics soha | Kétrétegű: (a) adapterek **explicit safe-field allowlistet** emittálnak (deny-by-default, csak aggregátum skalár/címke); (b) `ContextRedactor` blocklist másodlagos védelem. Song Trainer degradált → nincs lyrics-út egyáltalán. **Mutáció-próba** (lyrics-szabály kikapcsolva) → a redaction-próba PIROS. | ✓ |
| 4 | Provenance + hiányzó version → mező kimarad | `TutorContextField.available` dob, ha nincs version; adapterek `null`-t adnak version nélkül; assembler `missingVersion` omisszióval kihagy. Nincs hamis default. | ✓ |
| 5 | Purpose field-allowlist | `ContextPurpose.allowedFields` per-intent explicit halmaz; assembler `purposeNotAllowed` omisszióval szűr. Purpose × mező mátrix tesztelt. | ✓ |
| 6 | Song Trainer degradált (`unavailable`) | `SongTrainerContextAdapter.adapt()` → `TutorContextField.unavailable` (`songTrainer.unavailable.v1` provenance), csak `song_trainer/public.dart` (presentation) import. §0.0 D1 mérve helytálló. | ✓ |
| 7 | Lab-only inspectable, prompt NÉLKÜL | `InspectableContextView` — nincs prompt mező; `labModeProvider` kapu (`forRef`), `!enabled → null`; `toJson` csak strukturált mezők + redaction. | ✓ |

### Budget megkülönböztető mátrix (`== B` cella)

`ContextBudget.apply`: belépő őr `estimatedSizeBytes <= maxSerializedBytes`
(**inkluzív** — a pontosan határon lévő snapshot megmarad); fölötte
determinisztikus, fix `truncationPriority` const-sorrendű csonkolás +
`truncatedFields` flag. **Mutáció-próba** (`<=` → `<`) → az `== B` cella PIROS.
Független reference: a `< B` cella a legkisebb prioritású mezőt
(`settings`) ejti először — bit-stabil.

## 4. Mutáció-próbák (real-violation, a klónban, eldobva)

`test/.../review_probe_test.dart` (a körbranchre NEM került):

1. **Redaction completeness:** audio/abs-path/lyrics/secret kulcsok kiesnek,
   csak semleges `title` marad; a csonkolt lyrics szövege sehol.
   Baseline **PASS**; a lyrics-szabály kikapcsolásával **RED**.
2. **Budget `== B` inkluzív + `< B` determinisztikus:** `== B` retain,
   `B-1` csonkol, elsőként a `settings`. Baseline **PASS**; a `<=`→`<`
   mutációval **RED**.

Mindkét mutáció PIROSRA váltott (`+0 -2`), tehát az invariánsok valóban
diszkrimináló logikára mérnek, nem vakon zöldek.

## 5. NOTE (nem blokkol, follow-up R12+)

- **NOTE-1:** a `ContextRedactor._reasonForKey` **substring-blocklist**
  (value-szinten allow-by-default). A valódi deny-by-default a purpose +
  adapter allowlist; a blocklist csak defense-in-depth. Ha egy jövőbeli adapter
  olyan nyers mezőt emittálna, amelynek kulcsa nem illik a blocklist
  substringjeire (pl. `verse`, `recordingBuffer`), az átcsúszhatna a második
  rétegen. Ebben a körben nincs ilyen út (adapterek fegyelmezett allowlistje +
  degradált Song Trainer), de az R12 prompt-építésnél az adapter-allowlist
  legyen a kanonikus kapu, a blocklist ne váljon elsődleges védelemmé.

## 6. Merge-feltételek

Exact-SHA zöld `build-apk.yml` CI a kör-branch végső headjén (a review-commit
után újradispatch), §4-en belüli diff (igazolva), nulla OPEN BLOCKER/MAJOR.
Ezek teljesülésével squash-merge külön jóváhagyás nélkül (ADR 0052).
