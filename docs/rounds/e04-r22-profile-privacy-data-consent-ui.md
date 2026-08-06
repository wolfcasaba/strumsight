# E04-R22 — Profile, privacy, data és consent UI

- **Státusz:** PLANNING (pre-flight mérve 2026-08-06, kód olvasva: main @ `b973461`; §0.0 revízió)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 22; §35
- **Branch:** `codex/e04-r22-profile-privacy-data-consent-ui`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R03, R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (pipeline `engine=minimax`)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/presentation/tutor_profile_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "docs/rounds/e04-r22-profile-privacy-data-consent-ui.md",
]
gate_tests = [
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R03/R17 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 **0132** privacy +
> **0134** memory bővítése). `rg`: az R03 consent-tengelyek + R17 memory/delete-all
> repo public felülete; a flag mögötti route-minta. **ARB gen** a gate előtt.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió (mérve 2026-08-06, main @ `b973461`)

**Nincs ÚJ ADR.** Az [ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)
(privacy + granular consent) és az [ADR 0134](../adr/0134-ai-tutor-memory-policy.md)
(memory + retention/delete-all) hatálya alá esik; mindkettő létezik és merge-elt.
Ez a kör **kizárólag prezentációs UI + Riverpod-wiring** a MÁR meglévő domain
modellek és bekötött repók fölé — **új domain-/data-/perzisztencia-réteget NEM
épít** (§3 TILOS-a él).

### Mért tények (grep/olvasás, nem tábla)

1. **A teljes `ai_tutor` feature ma flag-mögötti/preview:** `FeatureFlags.aiTutorEnabled`
   default `false` minden környezetben (`lib/app/config/feature_flags.dart:19,53,86`);
   a repo-providerek override-only (`tutorConversationRepositoryProvider`,
   `tutorOrchestratorProvider` „must be overridden in tests"-et dobnak,
   `presentation/providers/tutor_providers.dart:337,345`); a chat Fake controllert
   használ; **nincs valós-app bootstrap wiring** a tutor repókra (main/app grep: 0 találat).
   → A három új képernyő ugyanígy flag-mögötti, **widget-teszttel** (override/fake
   providerrel) bizonyítva, az R18–R21 mintát követve. Ez a mérce, nem élő-app manuál.

2. **Consent = provider-mentes value object** (R03 „domain, provider-free", PR #126):
   `TutorConsent` (`domain/models/tutor_consent.dart:2`) három `bool` tengellyel —
   `modelUseGranted` (9), `persistentStorageGranted` (10),
   `evaluationWithRedactionGranted` (11); grant/revoke **immutable copy-metódusok
   magán a modellen**: `grantModelUse()`/`revokeModelUse()` (13/19),
   `grantPersistentStorage()`/`revokePersistentStorage()` (25/31),
   `grantEvaluationWithRedaction()`/`revokeEvaluationWithRedaction()` (37/43).
   **Nincs** consent-repository/-store/-provider és **nincs** perzisztens consent-key.
   → A consent-képernyő egy `tutor_privacy_providers.dart`-ban tartott
   `TutorConsent` állapotot szerkeszt a MEGLÉVŐ copy-metódusokkal (prezentációs
   wiring, nem új domain-logika). Perzisztálást NEM ad hozzá.

3. **Profil = provider-mentes modellek + codec** (R03): `StudentProfile`
   (`domain/models/student_profile.dart`), `GuitarProfile` (`guitar_profile.dart`),
   `LearningGoal` (`learning_goal.dart`), `TutorProfileCodec`
   (`data/local/tutor_profile_codec.dart`) — a codec-et **csak a unit-tesztje**
   használja, **nincs** profil-repository/-provider/-StorageKey.
   → A profil-editor `copyWith` + a modellek meglévő validációja fölé épül,
   `tutor_privacy_providers.dart`-ban tartott állapottal. Perzisztálást NEM ad hozzá.

4. **Memory repo (R17) — bekötött:** `TutorMemoryRepository`
   (`domain/repositories/tutor_memory_repository.dart`), impl
   `LocalTutorMemoryRepository` (`data/repositories/local_tutor_memory_repository.dart:12`,
   ctor `KeyValueStore`-t vár). Metódusok: `list()` (if.6/impl.23, newest-first),
   `update(TutorMemoryFact)` (12/69), `delete(String factId)` (14/96),
   `exportRedacted()` (18/128, minden `content`→`'[redacted]'`),
   `deleteAllAiData()` (21/156), `saveCandidate`/`purgeExpired`.
   **Nincs** `tutorMemoryRepositoryProvider` — ezt e kör hozza létre
   `tutor_privacy_providers.dart`-ban (widget-tesztben override-olva egy
   fake/in-memory repóval), a meglévő `tutorConversationRepositoryProvider`
   minta szerint.

5. **Delete-all EXACT scope** (`core/storage/storage_keys.dart:62`,
   `StorageKeys.tutorAiData`): `ss.tutor.conversation_documents`,
   `ss.tutor.conversation_index`, `ss.tutor.memory_facts` — **plusz mindegyik
   `.corrupt` karantén-kulcsa** (`quarantineOf`, :81). A `deleteAllAiData()` ezt a
   listát járja be (`local_tutor_memory_repository.dart:156-168`). **NEM** törli a
   consent/profil blobot és a secure auth tokent. A UI scope-listája **pontosan**
   ez a három store legyen; a falszifikációs cella ezt méri (§6).

6. **Route: a brief útvonala DRIFT-elt** — `lib/app/router/app_route.dart` nem
   létezik; a valós fájlok a `lib/app/routing/` alatt vannak. A `AppRoutes`
   path-konstansok: `app_route.dart` (tutorHome=`/tutor/home` :31, tutorChat :32);
   a flag-mögötti GoRoute-**regisztráció** `app_router.dart`-ban van:
   `final aiTutorEnabled = ...flags.aiTutorEnabled;` (:64) →
   `if (aiTutorEnabled) ...[ GoRoute(...) ]` (:197), a screeneket **közvetlenül**
   importálva (:34-35), NEM public.dart-on át. A `practiceEnabled`/`songTrainerEnabled`
   spread-minta (:138/:156) a precedens. → Az `allowed_paths`-t korrigáltam:
   `lib/app/routing/app_route.dart` (3 új path-konstans) + `lib/app/routing/app_router.dart`
   (3 új GoRoute a flag-blokkban + import). Ez a brief eredeti §4 „flag mögötti
   route (additív)" szándékának pontosítása, nem scope-tágítás.

7. **`public.dart` ÜRES-BOUNDARY invariáns:** `test/features/ai_tutor/ai_tutor_boundary_test.dart`
   megköveteli, hogy a `public.dart` **nulla** import/export direktívát tartalmazzon,
   amíg cross-feature fogyasztó nem érkezik (R20/R21 scope-narrowing). A route az
   app-rétegben KÖZVETLEN importtal éri el a screeneket, ezért e kör **NEM ad
   exportot** a `public.dart`-hoz — hagyd érintetlenül (különben a gate pirosra vált).

### Törölt/halasztott acceptance (nincs domain-háttér; §3 tiltja az építését)

Az alábbi brief-elemek MÖGÖTT nincs meglévő domain-réteg, és a hozzáépítés
tiltott (§3) / a tilos zónába esne (H3). Ezek **e körből kiesnek**, prerekvizit
körbe halasztva (mérve: nem található a kódban → §0.0 revízió, nem lista-tágítás):

- **Retention-beállítás:** nincs konfigurálható retention-mező; csak per-fact
  `expiresAt` + `purgeExpired(now)` létezik. → KIESIK (opcionálisan a fact-lista
  csak-olvasható `expiresAt` kijelzése megengedett, új mező nélkül).
- **Conversation export:** nincs ilyen metódus; a `TutorConversationRepository`
  csak `save/get/list/summary/delete`. Az EGYETLEN export a memory-fact
  `exportRedacted()`. → az export-akció a **redaktált memory-export**, nem
  „conversation export".
- **Cloud-sync local vs remote-pending külön jelzés:** nincs cloud-sync és nincs
  remote-pending állapot (minden repo local-only). → KIESIK.
- **Consent-revoke → pending-request-cancel policy:** a `consentRevoked` egy
  per-turn reducer-effekt (`tutor_orchestrator.dart:47-56,292-298`), nincs a UI
  által lemondható perzisztens „pending request". → a consent-képernyő a
  tengely-értéket kapcsolja; a pending-cancel KIESIK.

A megmaradó, ténylegesen buildelhető scope-ot a §6 sorolja (frissítve).

## 1. Cél

A felhasználó számára **teljesen átlátható** profil-, memória-, consent-, retention-,
export- és törlésvezérlés — a delete-all scope egyértelmű.

## 2. Jelenlegi állapot

- Nincs privacy/profile UI. R03 granular consent + R17 memory/delete-all repo kész —
  a UI ezek fölé épül.
- A három consent-tengely (model-use/storage/evaluation) külön kapcsolható (R03).

## 3. Scope

**Benne:** student+guitar profile editor, aktív célok, cloud-AI consent képernyő
(plain-language), **külön** model-use/storage/evaluation consent, memory-fact lista +
edit, retention-beállítás, conversation export + törlés, **delete-all-AI-data** exact
scope-listával, consent-revoke → pending-request policy, cloud-sync-hiba local vs
remote-pending külön jelzés.

**Kívül — TILOS:** új consent/memory domain-logika (R03/R17), provider-SDK, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/screens/tutor_profile_screen.dart` | ÚJ | profil editor |
| `.../presentation/screens/tutor_privacy_screen.dart` | ÚJ | consent képernyő |
| `.../presentation/screens/tutor_data_screen.dart` | ÚJ | export + delete-all |
| `.../presentation/providers/tutor_privacy_providers.dart` | ÚJ | Riverpod wiring (consent/profil állapot + memory-repo provider) |
| `lib/app/routing/app_route.dart` | meglévő | 3 új `AppRoutes` path-konstans (§0.0-6) |
| `lib/app/routing/app_router.dart` | meglévő | 3 új GoRoute a `if (aiTutorEnabled) ...[` blokkban + import (§0.0-6) |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | privacy szövegek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/presentation/*` | ÚJ | consent/delete widget-tesztek |
| `docs/rounds/e04-r22-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **consent granular** (három tengely külön, R03/ADR 0132); a **delete-all scope
   egyértelmű** és tényleges (R17). **NEM elfogadható:** összevont consent vagy
   „részleges" delete-all félrevezető szöveggel.
2. Consent-revoke **törli/leállítja** a pending requestet policy szerint.
3. Cloud-sync-hiba → **local vs remote-pending külön** jelzés (nem néma).
4. A privacy-szöveg **lokalizált** (hu+en).

## 6. Acceptance criteria (§0.0 szerint mérve/szűkítve)

**Benne (buildelhető a meglévő domain + bekötött repók fölött):**

- [ ] **Profil-editor**: `StudentProfile` + `GuitarProfile` + `LearningGoal` mezők
      szerkesztése a modellek meglévő `copyWith` + validációja fölött, provider-tartott
      állapottal; érvénytelen bemenet lokalizált hibát ad. Widget-teszt.
- [ ] **Consent-képernyő**: a **három tengely külön** kapcsolható
      (`modelUseGranted` / `persistentStorageGranted` / `evaluationWithRedactionGranted`)
      a MEGLÉVŐ grant/revoke copy-metódusokkal; a tengelyek függetlenek (egyik
      állítása a másikat nem mozdítja). Widget-teszt tengelyenként + a
      falszifikációs cella (l. lent).
- [ ] **Memory-fact lista + edit + delete**: `list()` / `update()` / `delete()` a
      `tutorMemoryRepositoryProvider`-en (widget-tesztben fake repóval override-olva);
      szenzitív-tartalom elutasítást a UI felszínre hozza. Widget-teszt.
- [ ] **Redaktált memory-export**: az export-akció `exportRedacted()`-et hív; a
      teszt igazolja, hogy a kimenet minden `content`-je `'[redacted]'`.
- [ ] **Delete-all confirmation** a MEGLÉVŐ `deleteAllAiData()`-t hívja, és a
      megerősítő UI **pontos scope-listát** mutat: `conversation_documents`,
      `conversation_index`, `memory_facts` (+ mindegyik `.corrupt` karanténja),
      ÉS explicit jelzi, hogy a consent/profil és az auth token **NEM** törlődik.
- [ ] **Conversation lista + delete**: a meglévő `tutorConversationRepositoryProvider`
      `list()`/`delete()`-jén. Widget-teszt.
- [ ] Minden szöveg **lokalizált** (hu+en), semantics-label a fő akciókon.

**Falszifikációs cella (KÖTELEZŐ gépi mérce):**

- [ ] A **delete-all scope-lista** teszt: egy eldobható mutáció, amely a UI
      scope-listáját szűkíti/tágítja a tényleges `StorageKeys.tutorAiData`-hoz
      képest (pl. kihagyja a `memory_facts`-et vagy hozzáad egy nem-törölt kulcsot),
      **pirosra** váltja a tesztet — a scope-lista a tényleges törléssel egyezzen.
- [ ] A **consent-tengely-függetlenség** teszt: egy mutáció, amely egy tengely
      kapcsolásakor egy másikat is átbillent, **pirosra** váltja (ADR 0132
      granular-consent szerződés).

**Kiesett** (§0.0 „Törölt/halasztott": retention-config, conversation-export,
cloud remote-pending, consent-revoke pending-cancel — nincs domain-háttér).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED: delete-all-scope falszifikáció + consent-tengely-függetlenség +
   memory list/edit/delete + redaktált-export + conversation list/delete tesztek.
2. `tutor_privacy_providers.dart` (consent/profil állapot + `tutorMemoryRepositoryProvider`)
   + profile/privacy/data screenek.
3. flag mögötti route: `AppRoutes` konstansok (`app_route.dart`) + GoRoute-ok a
   `if (aiTutorEnabled) ...[` blokkban (`app_router.dart`, közvetlen screen-import) + ARB (hu+en).
4. `flutter gen-l10n`; gate. **`public.dart`-hoz NEM nyúlsz** (üres-boundary invariáns).

## 9. Kockázatok

- Félrevezető delete-all szöveg (scope ≠ tényleges) — a scope-lista mérve egyezzen.
- Consent-tengely összemosás a UI-kényelemért — TILOS (R03 domain-szerződés).

**STOP:** összevont consent, félrevezető delete-all vagy néma cloud-hiba helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Kör:** E04-R22 (javító kör, MAJOR/MINOR/NOTE) — MiniMax M3.

**Mérce:** `tools/round-gate.sh test/features/ai_tutor/presentation` →
`format`/`analyze`/`test`/`architecture`/`secrets`/`l10n` mind ZÖLD lokálisan
(67 teszt, 12 allowlist-deviation, 913 l10n message, 0 secret finding). A teljes
suite + property + APK a CI-ból jön (orchestrátor dispatch).

**Mit szállítottam (csak az `allowed_paths` körein belül):**

- **`tutor_data_screen.dart`** — `_MemoryFactRow` kapott egy edit-affordanciát
  (edit + delete gombok, `tutorDataMemoryEdit:<id>` Key), a `_MemoryFactEditDialog`
  egy saját `StatefulWidget` (`TextEditingController` a saját
  `initState`/`dispose` lifecycle-ében, így nincs controller-leak), a `submit`
  `repo.update(fact.copyWith(content, updatedAt: DateTime.now().toUtc()))`-et
  hív; a `ValidationFailure`-t lokalizált `tutorDataMemoryEditSensitive`
  üzenettel jeleníti meg (saját `tutorDataMemoryEditErrorDialog:<id>` dialogban),
  egyéb `AppFailure` ágra a `tutorDataMemoryEditFailed`. Siker esetén
  `ref.invalidate(tutorMemoryFactsProvider)`. A delete-all scope-lista
  `Key('tutorDataDeleteAllScopeList')`-be van csomagolva (a pontos sor-számot
  a R22-F2 most `find.descendant(... Padding)`-szel méri; R22-F2-ben a
  `findsNWidgets(StorageKeys.tutorAiData.length * 2)` assert zárja a „bővítés"
  irányt — a B-próba innentől pirosra vált, ha bogus kulcs kerülne a
  scope-listába).
- **`tutor_data_screen_test.dart`** — két új cella:
  `R22-DA5b: editing a memory fact updates the repository with new content`
  (sikerág: `repo.update()` a módosított `TutorMemoryFact`-tal, `updatedFacts`
  lista a fake repóban), `R22-DA5c: sensitive memory edit surfaces a localized
  validation error` (szenzitív-elutasítás: a fake `rejectSensitiveUpdates=true`
  flagjével a `password`-tartalmú edit `ValidationFailure`-t ad vissza, az UI
  a `tutorDataMemoryEditSensitive` lokalizált szöveget mutatja); a `R22-F2`
  a `tutorDataDeleteAllScopeList` kulccsal scope-olt `Padding`-szám-assertet +
  a `secureAuthToken` / `tutorConsent.profile` `findsNothing` őrét tartja.
  Mindkét edit-teszt a meglévő `_FakeMemoryRepository` override-on fut.
- **`app_en.arb` / `app_hu.arb`** — 7-7 új kulcs (mindkét nyelven): 
  `tutorDataMemoryEdit`, `tutorDataMemoryEditTitle`, `tutorDataMemoryEditSave`,
  `tutorDataMemoryEditCancel`, `tutorDataMemoryEditEmpty`,
  `tutorDataMemoryEditSensitive`, `tutorDataMemoryEditFailed`. ARB-generálás
  (`flutter gen-l10n`) a gate előtt lefutott; l10n-parity zöld
  (913 message, en→hu nulla eltérés).
- **Dokumentáció** — ez a §10 handoff szakasz kitöltve (a NOTE #3 zárása).

**Providerek / route-ok:** nem nyúltam (a R22-es payload
`public.dart` + `app_route.dart` + `app_router.dart` változatlanok; az
`allowed_paths`-listán belül a memory-edit nem igényel új providert — a
meglévő `tutorMemoryRepositoryProvider` + `tutorMemoryFactsProvider` fölé
épül).

**Kiesett (korábban, §0.0 + §3 tilalma):** retention-mező, conversation-export,
cloud remote-pending, consent-revoke pending-cancel — a R22 brief-állapot
szerint nincs mögöttük domain-háttér; a javító kör sem épített új
domain-/perzisztencia-réteget.

**Következő lépés (orchestrátornak):** review-zás → CI-dispatch
(`gh workflow run build-apk.yml --ref <branch>`) → a §6 összes elfogadási
kritériumára kiterjedő APPROVED → squash-merge zöld kapuval.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r22-profile-privacy-data-consent-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
