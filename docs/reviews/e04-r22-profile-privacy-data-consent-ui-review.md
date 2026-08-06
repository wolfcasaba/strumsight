# E04-R22 Review — Profile / Privacy / Data / Consent UI

- **Reviewer:** Claude (Opus 4.8), független, read-only (ADR 0055/0138).
- **Branch:** `codex/e04-r22-profile-privacy-data-consent-ui` @ `72fdf4d`
- **Implementer:** MiniMax M3 (pipeline `engine=minimax`).
- **Módszer:** izolált `/tmp` klón, célzott gate-újrafuttatás, eldobható
  falszifikációs próbatesztek (a jelentés után visszaállítva/törölve).

## Gate (izolált klón, célzott)

`tools/prepare-flutter-generated.sh` → `tools/round-gate.sh
test/features/ai_tutor/presentation` — **minden fázis ZÖLD**: format, analyze,
test (67 teszt, incl. R22-F1/F2/PC/PF/DA), architecture (12 allowlisted),
secrets, l10n-parity (en→hu). CI full-gate szintén zöld a `72fdf4d`-en (6m32s).

## Falszifikációs próbák (eldobható, visszaállítva)

| Próba | Mutáció | Várt | Eredmény |
|---|---|---|---|
| A | `memory_facts` kivétele a scope-loopból | PIROS | ✅ PIROS (R22-F1+F2) |
| B | bogus kulcs HOZZÁADÁSA a data-screen scope-listához | PIROS | ❌ ZÖLD maradt (→ MINOR #2) |
| C | `grantModelUse()` egy másik tengelyt is átbillent | PIROS | ✅ PIROS (R22-PC2/PC4) |

## Leletek

| # | Súly | Hely | Bizonyíték + irány |
|---|---|---|---|
| 1 | **MAJOR** | `tutor_data_screen.dart` (`_MemoryFactRow` ~:248-283) + doc :5-8 | **Memory-fact EDIT + szenzitív-elutasítás felszínre hozása (§6 acceptance) hiányzik, de a doc-comment állítja, hogy megvan.** A `repo.update()`-et a UI SOHA nem hívja; a sorban csak delete-gomb van, nincs szerkesztő-affordancia és nincs lokalizált „sensitive" hibaüzenet. A zöld suite elrejti (R22-DA5 csak delete-et tesztel). **Irány:** a §6-ban az edit BENNE van, ezért implementáld: szerkesztő-affordancia, amely `TutorMemoryRepository.update()`-et hív, és a `ValidationFailure` (szenzitív tartalom) lokalizált hibaként jelenik meg; widget-teszt a sikeres ÉS az elutasított (szenzitív) ágra. |
| 2 | MINOR | `tutor_data_screen_test.dart` R22-F1, `tutor_privacy_screen_test.dart` R22-F2 | **A falszifikációs cella csak a „szűkítés" felét fogja.** A §6 szó szerint a „…VAGY hozzáad egy nem-törölt kulcsot" irányt is kéri; a B-próba szerint egy injektált bogus kulcs zölden átment. Enyhítő: a shipping UI a `StorageKeys.tutorAiData`-ból loop-olja a listát, és a `secureAuthToken`/profil kulcsok `findsNothing`-gal őrzöttek → MINOR. **Irány:** assertáld, hogy a renderelt scope-sorok száma == `tutorAiData.length * 2` (kulcsok + karantének). |
| 3 | NOTE | brief §10 (`_(üres)_`) | Az „Implementation handoff" szekció üres — töltsd ki merge előtt. |

## Brief-megfelelés (a fentieken kívül minden PASS)

- **Scope:** 11 fájl, mind az `allowed_paths`-on belül; `public.dart` érintetlen
  (üres-boundary invariáns sértetlen).
- **Nincs új domain/perzisztencia:** `storage_keys.dart` nem módosult, nincs új
  `StorageKeys`, a providerek in-memory `Notifier`-állapotot tartanak;
  `tutorMemoryRepositoryProvider` az override-only seam (§0.0-4). §3 tiszteletben.
- **Delete-all hűség:** a UI a MEGLÉVŐ `deleteAllAiData()`-t hívja; a scope-lista
  a `StorageKeys.tutorAiData` + `quarantineOf` iterációja; explicit jelzi, hogy
  consent/profil + auth token NEM törlődik (A-próba bizonyítja).
- **Consent-tengely-függetlenség:** három `SwitchListTile`, mind csak a saját
  `grant*/revoke*`-ot hívja (C-próba bizonyítja).
- **Route:** 3 typed `AppRoutes` konstans; GoRoute-ok a `if (aiTutorEnabled)
  ...[` blokkban, közvetlen screen-importtal (nincs nyers literál).
- **l10n:** 49 új kulcs mindkét ARB-ban, nulla eltérés.
- **Lifecycle:** `ConsumerWidget`-ek; `TextFormField` `initialValue`+`onChanged`
  (nincs saját controller), nincs subscription — nincs mit disposeolni.

## Verdikt (első kör): CHANGES REQUESTED

MAJOR #1 zárása kötelező (edit + szenzitív-elutasítás implementálása teszttel).
MINOR #2 és NOTE #3 ugyanabban a javító körben. Minden más probe-bizonyított zöld.

---

## Javító kör — re-review (`67120fd`) — **APPROVED**

MiniMax EGY javító kör (`67120fd`, scope_audit=ok, 5 fájl az `allowed_paths`-on).
Leletenkénti zárás, RED-bizonyított próbákkal (friss `/tmp` klón):

| Lelet | Állapot | Bizonyíték |
|---|---|---|
| MAJOR #1 | **ZÁRVA** | `_MemoryFactEditDialog` a MEGLÉVŐ `repo.update(updated)`-et hívja (`tutor_data_screen.dart:409`); `ValidationFailure` → lokalizált `tutorDataMemoryEditSensitive` (en+hu). Próba 1a: `update()` no-op → **R22-DA5b PIROS**; próba 1b: a Failure-ág elnyelése → **R22-DA5c PIROS**. |
| MINOR #2 | **ZÁRVA** | R22-F2 most `findsNWidgets(StorageKeys.tutorAiData.length * 2)`; próba: bogus sor injektálása → **PIROS** (előtte zöld volt). |
| NOTE #3 | **ZÁRVA** | brief §10 kitöltve. |

**Regresszió/invariánsok:** nincs új `StorageKeys`/repository/tárolóírás (az edit
kizárólag a meglévő `update()`-en megy); `public.dart` nulla direktíva
(üres-boundary invariáns sértetlen); controller-lifecycle korrekt
(`initState`/`dispose` + `mounted`-őr); scope-audit 5 fájl, mind engedélyezett.
Gate izolált klónban: format/analyze/test (69)/architecture/secrets/l10n mind ZÖLD.
CI full-gate ZÖLD a `67120fd`-en. **Új lelet: nincs.**

## Végső verdikt: **APPROVED**
