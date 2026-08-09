# E99-R05 (GOV-06b) — Review

Brief: `docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md`
ADR: `docs/adr/0212-bpm-baseline-metric-invalidation-and-independent-tempo-reference.md`
Diff: `git diff origin/main...codex/e99-r05-gov-06b-bpm-metric-fix` (commit `a3f54bc7`, javítva `cd7d7ca9`-ig)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-09
Verdikt: **APPROVED** (1 javító kör után)

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott (1 javítva) · MINOR: 0 · NOTE: 2

**Frissítés (javító kör #1 után, commit `cd7d7ca9`):** F1 **FIXED**. A
`docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md` §10-je most a két mérési
parancs teljes, csonkítatlan stdout-ját tartalmazza (a `tempo_reference.py`
teljes kimenete + a `flutter test` teljes JSON-je, a `bpm` szakasz mind a 82
rekordjával). Tételesen ellenőrizve: `"strictTempoMatch": {"matched": 11,
"eligible": 82}`, `"metricLevelTempoMatch": {"matched": 32, "eligible": 82}`,
`"missingReferenceRecordings": []` — mind szó szerint jelen van; a
beillesztett kimenetben összesen 164 `"recording":` bejegyzés (82 a `bpm.records`-ban
+ 82 a megőrzött `strumDensityAgreement.records`-ban). A javító kör **kizárólag**
a `docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md`-t módosította (`git diff --stat
58521ec3..cd7d7ca9` → 1 fájl); a Dart/Python kód és a teszt bitre változatlan
maradt, ahogy a fix-prompt kérte. Gate **saját kézzel újrafuttatva, friss
`/tmp` klónban a fix után is**: 7/7 zöld. `scope_audit=ok` a jelzésfájlban
(`scope_audit_changed=1`).

Minden gate zöld egy saját, izolált `/tmp/review-e99-r05` klónban
(független újrafuttatás, nem a implementer állítása). A kör mind a 10
acceptance criteria-ját (A1–A10) **saját kézzel, függetlenül reprodukálva**
igazoltnak találtam — a mért számok bitre egyeznek a handoffban állítottakkal
ÉS a GOV-06 eredeti riportjával. A `§6.1` valódi-sértés próbát is
függetlenül megismételtem (nem fogadtam el a implementer állítását
bemondásra): a mutáció pontosan az elvárt cellát váltja pirosra. Egyetlen
nyitott MAJOR lelet van: a brief §10 sablonja szó szerint előírja a **két
mérési parancs TÉNYLEGES, csonkítatlan kimenetét** a handoffban, ez viszont
csak összefoglaló mondatokkal szerepel.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `lib/` nulla változás | ✅ | Saját `git diff --name-only origin/main...HEAD \| grep '^lib/'` → üres, a klónban |
| A2 | Tűrés-hármas (39/40/41 ezrelék, `<=`) | ✅ | `test/tooling/real_audio_dsp_baseline_test.dart:84-99` — saját futtatás zöld; saját mutációs próba (lásd lent) a 40-es cellát pontosan pirosra váltja |
| A3 | Metrikai-szint tolerancia 5-soros mátrixa (+ 1/3, 2/3, 3× extra fedés) | ✅ | `test/tooling/real_audio_dsp_baseline_test.dart:101-117` — saját futtatás zöld, a 137 BPM cella (a „minden szorzót elfogad" hibaosztály csapdája) explicit tesztelve |
| A4 | Pengetés-sűrűség szám NEM tempóként címkézve | ✅ | `grep -in "pengetés-sűrűség\|tempó-hiba\|BPM-pontosság" docs/eval/real-audio-dsp-baseline.md` → csak „Pengetés-sűrűség egyezés" címke, „tempó-hiba"/„BPM-pontosság" sehol |
| A5 | 45,067 visszavontként megmarad | ✅ | `docs/eval/real-audio-dsp-baseline.md:22,36` — „visszavonva" + ok; a legacy nyers blokk is megőrizve |
| A6 | Hiányzó referencia → `notRun`, nincs csendes visszaesés | ✅ | `test/tooling/real_audio_dsp_baseline_test.dart:119-123` zöld; `buildTempoSummary()` (`tool/benchmarks/real_audio_dsp_baseline.dart:128-134`) a `null` referenciát ELSŐ ágon `notRun`-ra zárja, mielőtt bármi mást számolna |
| A7 | Akkord/onset számok bitre változatlanok | ✅ | **Saját, teljes 82 felvételes újramérés**: `accuracy: 0.6706892156029575` (67,069%), `minorSubset: 185/222 = 0.8333333333333334`, onset F1 `0.4042664942830592 / 0.6739121651650438 / 0.8520059795563816` — mind bitre egyezik a GOV-06 riporttal és a handoff állításával |
| A8 | Reprodukálhatósági korlát kimondva (audio-venv, librosa verzió, parancs) | ✅ | `docs/eval/real-audio-dsp-baseline.md:46,50` — librosa 0.11.0, `~/audio-venv` nem verziókövetett, pontos parancs |
| A9 | Kimaradt felvételek nevesítve, darabszámmal | ✅ | Saját futtatás: `recordings without tempo (0): []`; `missingReferenceRecordings: []` a JSON-ban; doc + handoff egyaránt „kimaradt: 0" |
| A10 | Gate zöld a §7 artefaktummal | ✅ | Saját `tools/round-gate.sh test/tooling test/features/analyze` izolált klónban: 7/7 lépés zöld (format, analyze, 2×test, architecture, secrets, l10n) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --name-only origin/main...HEAD`
pontosan az 5 engedélyezett fájlt adja (`ml/chords/tempo_reference.py` ÚJ,
`tool/benchmarks/real_audio_dsp_baseline.dart`,
`test/tooling/real_audio_dsp_baseline_test.dart`,
`docs/eval/real-audio-dsp-baseline.md`,
`docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md`). A `.codex-round-status`
gépi scope-audit is `scope_audit=ok`, `scope_audit_changed=5` — egyezik.
`ml/chords/eval_real_sessions.py`, `eval_guitarset.py` és `ml/data/`
érintetlenek.

## Saját próbatesztek (a review mérése, nem a implementer állítása)

1. **Teljes független mérés-reprodukció** izolált `/tmp/review-e99-r05`
   klónban: `~/audio-venv/bin/python ml/chords/tempo_reference.py
   ml/data/klangio --out /tmp/review-tempo-reference.json` (82/82, 0 hiány,
   42 s), majd a Flutter-mérés
   (`--dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=...`, 4 m 34 s). Eredmény:
   szigorú egyezés **11/82**, metrikai-szint **32/82**, pengetés-sűrűség
   MAE **45,06716069579421** — mindhárom szám bitre egyezik a handoff
   állításával.
2. **§6.1 valódi-sértés próba, saját kézzel megismételve** (nem a
   implementer log-jából idézve): `temposMatch` `<=`→`<` mutáció →
   `flutter test test/tooling/real_audio_dsp_baseline_test.dart` → **1
   teszt PIROS** (`tempo tolerance uses inclusive integer-per-mille
   boundary cells`, `Expected: <true> Actual: <false> predicted=104.0`,
   pontosan a brief §6.1 által megjósolt cella) — a többi 7 zöld marad.
   Visszaállítás után **8/8 zöld**. A `git diff --stat` a visszaállítás
   után üres — a próba nem hagyott nyomot.

## Megállapítások

### F1 — MAJOR — A §10 handoff nem tartalmazza a két mérési parancs tényleges, csonkítatlan kimenetét

- **Fájl:** `docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md:393-401` (§10,
  „Futtatott parancsok" bekezdés)
- **Probléma:** a brief §10 sablonja szó szerint előírja: „Futtatott
  parancsok + **TÉNYLEGES, csonkítatlan** kimenet (mindkét mérési
  parancs)." A committolt handoff ehelyett csak egysoros összefoglalókat ad
  (pl. „szigorú egyezés 11/82, metrikai-szint egyezés 32/82, pengetés-
  sűrűség átlagos abszolút különbség 45.06716069579421 BPM"), és a `flutter
  test` teljes JSON-kimenetét (82 rekord a `records` tömbben,
  `strictTempoMatch`/`metricLevelTempoMatch`/`missingReferenceRecordings`
  mezőkkel) sehol nem idézi — sem a handoffban, sem a
  `docs/eval/real-audio-dsp-baseline.md`-ben (ott is csak egy összefoglaló
  táblázat van, a GOV-06 RÉGI nyers blokkja van megőrizve, de az ÚJ futás
  nyers kimenete nincs hozzáadva).
- **Hatás:** a projekt kifejezett, ismételt elve — „Szám, amit nem
  futtattál, hazugság" (a brief záró sora), és `docs/LESSONS.md` L09 — hogy
  az összefoglaló ÁLLÍTÁS önmagában nem bizonyíték, a TÉNYLEGES kimenet az.
  A GOV-06 (E99-R04) saját precedense pontosan ezt tette (a teljes nyers
  JSON-t idézte, ami ebben a fájlban most is látható, megőrzött formában) —
  ez a kör a SAJÁT új adatára nem alkalmazta ugyanazt a mércét. Egy jövőbeli
  olvasó (aki nem futtatja újra a mérést) a handoffból NEM tudja
  ellenőrizni a 11/82 és 32/82 számokat felvételenkénti bontásban, csak a
  végösszeget.
- **Kötelező javítás:** a `~/flutter/bin/flutter test
  --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio
  --dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=<json> ...` parancs teljes,
  csonkítatlan stdout-ját (a `bpm` szakasz mind a 82 rekordjával együtt) és
  a `tempo_reference.py` teljes stdout-ját illeszd be a brief §10-be,
  ahogy a sablon előírja. Javasolt (nem kötelező, de a GOV-06 precedenssel
  konzisztens): a `docs/eval/real-audio-dsp-baseline.md`-be is kerüljön be
  egy „E99-R05 csonkítatlan mérési kimenet" szakasz a jelenlegi „GOV-06
  eredeti, visszavont..." szakasz mellé, hogy a fájl önmagában
  reprodukció nélkül is auditálható maradjon.
- **Ellenőrzés:** a javított handoffban a beillesztett kimenet
  `"strictTempoMatch": {"matched": 11, "eligible": 82}` és
  `"metricLevelTempoMatch": {"matched": 32, "eligible": 82}` mezőket
  tartalmazza szó szerint, és `grep -c '"recording":' <handoff-szakasz>` 82
  körüli találatot ad (a `records` tömb mérete).
- **Státusz:** FIXED (`cd7d7ca9`) — tételesen ellenőrizve, lásd az
  Összegzés-frissítést fent.

### N1 — NOTE — A brief §6 checkbox-lista nincs kipipálva

- **Fájl:** `docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md:265-317` (a
  `- [ ] A1` … `- [ ] A10` sorok)
- **Megfigyelés:** a handoff tartalmilag minden A1–A10-et teljesíti (lásd az
  Acceptance criteria táblát fent), de a brief saját `- [ ]` jelölői
  változatlanul üresek maradtak. Kozmetikai — a gate és a review nem ezen
  a jelölésen múlik —, de a következő olvasó számára megtévesztő lehet.
  Nem blokkoló, javítható a fix körben a §10-módosítással egy menetben.

### N2 — NOTE — `_recording_stem` szigorú `_phone.wav` feltevése dokumentálatlan él-eset

- **Fájl:** `ml/chords/tempo_reference.py:28-32`
- **Megfigyelés:** a `_recording_stem()` `ValueError`-t dob minden `.wav`
  fájlra, ami nem `_phone.wav`-ra végződik — ez helyes fail-loud viselkedés
  a jelenlegi korpuszra (minden fájl ezt a mintát követi), de a
  `main()`-ben nincs elkapva, tehát egy jövőbeli, vegyes-elnevezésű
  korpuszon a script a FÉLIG kész JSON-t nem írja ki, hanem elszáll. Ez ma
  helyes (fail-loud jobb, mint néma torzítás), csak dokumentálatlan — nem
  igényel kódváltoztatást ebben a körben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, saját `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld (0 issue) |
| test test/tooling | zöld | ✅ zöld (55/55, benne a 8 új BPM-cella) |
| test test/features/analyze | zöld | ✅ zöld (64/64) |
| architecture | zöld | ✅ zöld (12 allowlistelt eltérés, változatlan) |
| secrets | (nem jelentett, gate-ben benne van) | ✅ zöld (2103 fájl, 0 lelet) |
| l10n | (nem jelentett, gate-ben benne van) | ✅ zöld (1019 üzenet, en↔hu) |
| CI (teljes suite + property + APK) | — | még nem dispatch-elve (a review után következik) |

## Biztonsági review

`risk = "high"` (a brief `ai-router` blokkja) → dedikált `security-reviewer`
review kötelező. Folyamatban, külön jelentés:
`docs/reviews/e99-r05-gov-06b-bpm-metric-fix-security.md`.

## Merge-döntés

Nincs nyitott BLOCKER/MAJOR, minden gate zöld (helyi + a CI-dispatch még
hátra van) → **ADR 0052 szerint mehet a squash-merge**, amint a CI-dispatch
(teljes suite + property + build) is zöldet ad a merge SHA-n.
