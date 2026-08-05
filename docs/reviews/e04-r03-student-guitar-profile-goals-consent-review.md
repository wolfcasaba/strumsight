# Review — E04-R03 — Student/Guitar profile, goals & granular consent

- **Reviewer:** Claude (orchestrátor, read-only review — ADR 0055)
- **Kör-branch:** `codex/e04-r03-student-guitar-profile-goals-consent`
- **Implementer:** Codex (Terra) · commit `2e4766e`
- **Dátum:** 2026-08-05
- **Verdikt:** ✅ **APPROVED** — nincs nyitott BLOCKER/MAJOR.

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=2e4766e`, gate zöld. A brief §10
handoff kitöltve. A `dirty_files=1` a signal-időpontban a gitignore-olt
`.codex-round-status` fájl volt; a working tree a commit után tiszta.

## 2. Gate — reviewer által ÚJRAFUTTATVA (izolált klón)

`git clone --branch <branch> … /tmp/review-e04-r03`; a repo-szintű `analyze`
először PIROS volt, **kizárólag a gitignore-olt generált l10n hiánya miatt**
(`test/features/tuner/*` → `AppLocalizations` undefined) — nem a kör hibája.
`tools/prepare-flutter-generated.sh` után újrafuttatva:

```
format                                     zöld
analyze                                    zöld
test test/features/ai_tutor/domain         zöld
test test/features/ai_tutor/data           zöld
architecture                               zöld
MINDEN GATE ZÖLD.
```

## 3. Scope-audit (a §0.0-val szűkített engedélyezett-lista ellen)

`git diff --name-only 52bf072..2e4766e` — mind a 9 fájl a listán belül:
4 domain modell + codec + 3 teszt + a brief (§10 handoff). **NINCS `public.dart`
módosítás** (§0.0 Rev.1 betartva), **NINCS új tesztfájl** — Guitar/Learning
tesztek a `student_profile_test.dart`-ban csoportosítva (§0.0 Rev.2 betartva).
Listán kívüli fájl: 0.

## 4. Acceptance criteria — tételes bizonyíték

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| 1 | `TutorConsent` 3 független tengely, round-trip, per-tengely grant/revoke | `tutor_consent.dart`: minden grant/revoke csak a saját tengelyt írja; teszt minden él ellenőrzi a másik 2 tengely változatlanságát | ✅ |
| 2 | Student/Guitar/Learning validáció + value-equality + immutabilitás literálisan | `student_profile_test.dart`: provenance, explicit>inferred merge, defenzív lista-másolás, stabil hibakód-készlet, ==/hashCode | ✅ |
| 3 | Codec round-trip bit-stabil; unknown/missing policy dokumentált+tesztelt | `tutor_profile_codec_test.dart`: byte-identical re-encode; unknown-mező ignorálva; missing→`fieldMissing`; unknown schema→`schemaVersionUnknown` | ✅ |
| 4 | Domain purity zöld; ≥90% coverage | purity-guard (R02 `tutor_conversation_test.dart` a teljes `ai_tutor` domaint scanneli) zöld; **coverage 90.6%** aggregát | ✅ |

## 5. Próbatesztek (eldobható, review után törölve)

**Consent-függetlenség valódi-sértés próba (az acceptance headline-je).**
Az izolált klónban a `grantModelUse()`-t úgy rontottam, hogy a
`persistentStorage` tengelyt is állítsa (`persistentStorageGranted: true`).
Eredmény: `tutor_consent_test.dart` → **PIROS**
(„grants and revokes model use without changing other axes" bukott).
A guard tehát bizonyítottan fog. Mutáció visszaállítva (`git diff` tiszta).

**Coverage-mérés** (`flutter test --coverage`, `lcov.info`):

```
student_profile      96.4%   guitar_profile   89.8%   learning_goal   88.6%
tutor_consent       100.0%   tutor_profile_codec 87.2%
TOTAL new domain+data 357/394 = 90.6%  (≥90% ✔)
```

## 6. Architektúra + termékhatárok

- Domain Flutter-/provider-SDK-mentes: a purity-guard zöld (AGENTS.md §6). ✅
- Nyers audio/PII nincs a modellekben (ADR 0132 §4). ✅
- `public.dart` contract érintetlen (üres-boundary invariáns megőrizve). ✅
- Nincs hálózat/mic/secret a diffben (AGENTS.md §5). ✅

## 7. Leletek

| Osztály | Lelet | Fájl:sor |
|---|---|---|
| NOTE | A per-fájl coverage 3 fájlon 87–90% között (védekező hibaágak fedetlenek); az aggregát 90.6% teljesíti a kritériumot. Nem blokkol. | `guitar_profile.dart`, `learning_goal.dart`, `tutor_profile_codec.dart` |
| NOTE | `StudentProfile` a briefnél gazdagabb (per-mező provenance + explicit>inferred merge); összhangban a provenance-tanulsággal, tesztelt. Nem blokkol. | `student_profile.dart` |

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2**

## 8. Merge-döntés

Zöld kapu minden eleme reviewer által látott; scope tiszta; acceptance
bizonyítva; consent-függetlenség mutációval igazolva. **APPROVED** —
merge exact-SHA zöld CI után.
