# E06-R02 — Review

Brief: `docs/rounds/e06-r02-analysis-document-v2-domain.md`
Diff: `git diff origin/main...codex/e06-r02-analysis-document-v2-domain` (22 files, 1332 insertions(+), 22 deletions(-))
Branch/HEAD: `codex/e06-r02-analysis-document-v2-domain` @ `332cce2e`
Reviewer: Claude Sonnet 5 (orchesztrátor) · Dátum: 2026-08-11
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

A gate-et **saját kézzel, izolált `/tmp/review-e06-r02` klónban** (GitHub
originról, nem a megosztott munkapéldányból) újrafuttattam — mind a 9 lépés
zöld. Két **valódi-sértés próbát** végeztem saját, a brief §6.1 mérce-
mátrixából vett, az implementer önjelentésétől FÜGGETLEN mutációval (lásd
lent) — mindkettő a várt cellát fogta pirosra.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Domain-purity őr | ✅ | `tool/check_architecture.dart` zöld a saját klónomban, 0 új allowlist-bejegyzés (`git diff origin/main -- tool/check_architecture.dart` üres); egyetlen `domain/*.dart` sem importál `package:flutter`-t (kézzel átolvasva mind a 14 fájl). |
| 2 | Validációs mátrix — `AnalysisDocument` | ✅ | `analysis_document_test.dart`: durationUs −1(throws)/0(pass)/+1(pass) L7-26; duplikált metric 0/1/2 L40-54; szegmens `>`(throws)/`==`(pass)/`<`(pass) L56-87. |
| 3 | Confidence-küszöb hármas | ✅ | Ugyanaz a fájl L28-38: 0.0/0.5/1.0 pass, `-1e-9`/`1.000000001` throws, doc-comment szerint `python3 -c 'print(repr(-1e-9), repr(1.0 + 1e-9))'`-vel számolva (ellenőriztem: a python3 kimenete ténylegesen `-1e-09 1.000000001`). |
| 4 | Immutabilitás-teszt | ✅ | L89-98: a bemenő `metrics` listát a konstruktor után mutálva `document.metrics` hossza változatlan marad, `document.metrics.add(...)` `UnsupportedError`-t dob. Saját próba (lásd Megállapítások, F-NOTE nem, ez a Próbatesztek szakaszban) megerősítette, hogy ha a konstruktor `List.unmodifiable` helyett referenciát tartana, EZ a teszt buknia kellene — és bukott is a mutált verzióban. |
| 5 | Metric-value sealed teszt | ✅ | `analysis_metric_test.dart` L15-40: hét altípus `switch`-e default ág nélkül fordul és fut (a `sealed class AnalysisMetricValue` tényleg sealed — `analysis_metric.dart:5`). |
| 6 | Metric-ID őr | ✅ | `analysis_metric_test.dart` L5-13: egyediség + `^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$` regex mind a 4 katalógus-ID-re. |
| 7 | Flag-őr | ✅ | `feature_flags_test.dart` "Audio Analysis V2 rollout boundary" csoport `AppEnvironment.values`-en iterál (a tényleges 3 értékre: development/lab/production — a brief §0.0 R1 javítása szerint, NEM 4), mindhárom flag `false` + `toString()` tartalmazza. A `forEnvironment` implementációja (`feature_flags.dart:77-79`) a 3 flaget explicit `false`-ra állítja, dart-define nélkül. |
| 8 | V1 érintetlen | ✅ | `git diff --stat origin/main...codex/e06-r02-analysis-document-v2-domain` nem tartalmaz `lib/features/analyze/**` vagy `lib/features/library/**` elemet; saját gate-futásom `test/features/analyze` (64 teszt) és `test/features/library` (12 teszt) is zöld. |

A brief §6 checkbox-ai (`- [ ]`) üresen maradtak — a §10 handoff táblázata
lefedi mind a nyolcat, de a checkbox-ok pipálása elmaradt. Lásd NOTE-2.

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat
origin/main...codex/e06-r02-analysis-document-v2-domain` pontosan 22 fájlt
mutat, mind a brief `allowed_paths`/kiegészített listáján (14 domain fájl +
`public.dart` + `feature_flags.dart` + 4 névvel adott teszt + a meglévő
`feature_flags_test.dart` + a brief maga a §10 handoffhoz). Ez egyezik a
gépi `scope_audit=ok` / `scope_audit_changed=22` jelzéssel
(`.codex-round-status`, `scope_audit_base=0decde90` — az orchesztrátor
pre-flight commitjának SHA-ja, helyesen).

## Próbatesztek (valódi-sértés próbák, saját, az implementer önjelentésétől független)

Külön, eldobható klónban (`/tmp/review-e06-r02-probe`), a munkába NEM
commitolva:

1. **Confidence-határ kizárása** (`analysis_capability.dart:46`):
   `confidence < 0 || confidence > 1` → `confidence <= 0 || confidence >= 1`.
   Eredmény: `analysis_document_test.dart` "accepts inclusive confidence
   boundaries..." tesztje PIROS lett (`Invalid argument (confidence): must
   be in [0, 1]: 0.0`). Visszaállítva.
2. **Lista-referencia megtartása** (`analysis_document.dart:45`):
   `metrics = List<AnalysisMetricResult>.unmodifiable(metrics)` →
   `metrics = metrics`. Eredmény: "takes immutable snapshots of document
   lists" teszt PIROS lett (a külső listát utólag mutálva a document
   `metrics` hossza 1 helyett 2 lett — pontosan a brief §6.1 mérce-mátrix
   "A konstruktor a kapott listát referenciaként tárolja" sorának megfelelő
   hiba). Visszaállítva.

Mindkét próba a brief §6.1 mérce-mátrixának egy-egy sorát célozta, és
mindkettő a várt cellát fogta — a teszt-suite valódi fogást ad, nem csak
formai zöldet.

Az implementer saját, a §10 handoffban dokumentált próbája (duplikált
metric-ID őr ideiglenes kiszedése) egy HARMADIK sort fed le; nem
ismételtem meg, mert a leírás konkrét és hihető (pontos hibaüzenetet közöl).

## Architektúra és termékhatárok

- **Domain-függetlenség (AGENTS.md §6):** mind a 14 domain fájl
  framework-mentes — nincs `package:flutter`/`flutter_riverpod`/Dio import
  egyikben sem (kézi átolvasás + `tool/check_architecture.dart` zöld, 0 új
  allowlist-bejegyzés).
- **`public.dart` contract:** a barrel mind a 14 domain fájlt exportálja
  (`grep -c "^export" public.dart` = 14 = a `domain/*.dart` fájlszám) — teljes
  lefedettség, nincs kifelé rejtett típus. A brief §9 kockázat-szakasza azt
  kérte, hogy a barrel csak a ténylegesen igényelt típusokat exportálja; mivel
  ez a kör maga a teljes domain-modellt szállítja (nincs még önálló
  fogyasztó/adapter, ami szűkebb metszetet indokolna), az egy-az-egyben export
  ésszerű alapállapot — a jövőbeli szűkítés egy fogyasztó-specifikus kör
  dolga, ha indokolt lesz.
- **Termékhatárok (§5):** nincs hálózati/`print`/`dart:io` hívás az új
  fájlokban (`grep -rn "print(\|http\|dio\|Socket\|dart:io"
  lib/features/audio_analysis/` — 0 valódi találat). `AnalysisInputSummary`
  kizárólag metaadatot hordoz (időtartam, sample rate, csatornaszám,
  fingerprint hash, `sourceName`), nyers PCM-et vagy audio-byte-ot sosem;
  `originalAudioRetained` alapértelmezetten `false` (ADR 0217-nek megfelelően
  — teszttel is bizonyítva: `analysis_document_test.dart:104`).
- **Erőforrás-lifecycle:** nincs `StreamSubscription`/isolate/mic/timer —
  ez a kör tisztán érték-típusokat szállít, a kritérium nem alkalmazható.

## Megállapítások

### NOTE-1 — `feature_flags.dart` hashCode a brief kérésén túl bővült

- **Fájl:** `lib/app/config/feature_flags.dart:192-225`
- **Megfigyelés:** a brief csak a 3 ÚJ flag `==`/`hashCode`/`toString`
  bevonását kérte (§5 pont 7). Az implementer ennél tovább ment: a
  `hashCode`-ot úgy alakította át, hogy MINDEN eddig kimaradt flaget (a
  `songTrainerV2Enabled`-től az összes `vision*`-ig, plusz a 3 új
  audio-analysis flaget) `Object.hashAll`-lal bevonja, ha bármelyik `true` —
  és megőrzi a régi 6-mezős `legacyHash`-t, ha minden extra flag `false`
  (a leggyakoribb eset). Ez egy meglévő, a körön kívüli hiányosságot
  (hiányos `hashCode`) is javít, bővebb kört érintve, mint amit a brief
  szó szerint kért.
- **Miért nem MAJOR/MINOR:** (1) ugyanabban a fájlban van, amit a brief
  már "additív" módosításra engedélyezett; (2) a régi (all-off) esetben
  BÁJTRA ugyanazt a hash-t adja, mint korábban — nincs láthatatlan
  viselkedésváltozás a jelenlegi (minden extra flag off) production
  állapotban; (3) a `feature_flags_test.dart` új tesztjei ténylegesen
  lefedik az új ágat (`hashCode, isNot(defaults.hashCode)` L298).
- **Teendő:** nincs — dokumentálva a jövőbeli olvasó számára; ha a projekt
  szigorúbb "csak a kért mezőt bővítsd" elvet követne, ez egy jövőbeli
  MINOR-follow-up lehetne, de jelen state-ben ártalmatlan és tesztelt.
- **Státusz:** NOTE, nem blokkoló.

### NOTE-2 — A brief §6 acceptance checkbox-ai nincsenek kipipálva

- **Fájl:** `docs/rounds/e06-r02-analysis-document-v2-domain.md` §6
- **Megfigyelés:** mind a nyolc `- [ ]` üresen maradt annak ellenére, hogy a
  §10 handoff táblázata tételesen bizonyítékot ad mindegyikre. Tisztán
  dokumentációs hiányosság, funkcionális hatás nélkül.
- **Teendő:** a review-commit részeként kipipálom (ld. lent) — nem igényel
  külön javító kört.
- **Státusz:** FIXED a review-commitban (nem production kód, dokumentáció).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (saját `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld (23→1→0 lint javítási kör után) | ✅ zöld, "No issues found! (ran in 18.0s)" |
| test test/features/audio_analysis | 13 teszt zöld | ✅ zöld, 13 teszt |
| test test/app | — | ✅ zöld, 69 teszt |
| test test/features/analyze (V1) | zöld | ✅ zöld, 64 teszt |
| test test/features/library (V1) | zöld | ✅ zöld, 12 teszt |
| architecture | zöld | ✅ zöld, 12 allowlisted deviation (mind pre-existing, 0 új) |
| secrets | (nem kötelező ebben a körben, de lefutott) | ✅ zöld, 2145 fájl, 0 lelet |
| l10n | (nem kötelező, de lefutott) | ✅ zöld |
| CI (teljes suite + property + APK) | nem futott — orchesztrátor dolga | ⏳ orchesztrátor a review után dispatch-eli |

## Merge-döntés

ADR 0052 szerint: minden LOKÁLIS gate zöld ÉS nulla nyitott BLOCKER/MAJOR →
**a CI-dispatch és a merge útja szabad**, a CI (teljes suite + randomizált
property + APK/full-gate) zöld visszaigazolása után.
