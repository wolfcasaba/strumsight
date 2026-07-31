# E02-R12 review — Practice Hub + Setup (ADR 0078)

- **Kör:** [`docs/rounds/e02-r12-practice-hub-and-setup.md`](../rounds/e02-r12-practice-hub-and-setup.md)
- **Branch:** `mm/e02-r12-practice-hub-setup` · **HEAD:** `de930b5`
- **Implementer motor:** **MiniMax M3** (pipeline-vezérelt kör)
- **Reviewer:** Claude (Opus 5), read-only, izolált klón (`/tmp/r12-review`)
- **Dátum:** 2026-07-31
- **Verdikt:** **APPROVED — 0 BLOCKER · 0 MAJOR · 0 MINOR**

## 1. Kontextus: félbeszakadt pipeline-review

Ezt a kört az autonóm pipeline (ADR 0087) első teljes futása vitte. A
pipeline-orchestrátor a review közepén **megölte saját magát** (exit 143): egy
beragadt gate-processz-takarító `pgrep -f "tools/round-gate.sh"` a saját
argv-jában lévő teljes promptra illeszkedett (L12 argv-változata; a driver
azóta fájl-hivatkozással indít, a sablon tiltja az ön-illeszkedő pgrep-et).
A review-t az interaktív orchestrátor fejezte be — ez a jelentés.

Az implementer-oldal a megszakadástól **független és sértetlen**: a kör-commit
(`de930b5`) 20:38-kor, a `done` jelzés előtt elkészült.

## 2. Scope-audit

`git show --stat de930b5` ↔ a brief §4 táblája: **16/16 fájl, egyezés
tételesen**, listán kívüli fájl nincs. `docs/adr/`, `HANDOFF.md`, `lib/core/`,
`lib/features/learn/` érintetlen.

## 3. Gate — függetlenül újrafuttatva az izolált klónban

```
format zöld · analyze zöld · test test/features/practice/presentation/ zöld ·
test test/core/screen_size_guard_test.dart zöld · architecture zöld (12 allowlisted, változatlan)
```

(A klónban előbb `flutter gen-l10n` kellett — a generált l10n gitignore-olt,
ez nem kör-hiba; a halott orchestrátor ugyanezt találta meg.)

## 4. Valódi-sértés próba

| Mutáció | Eredmény |
|---|---|
| a flag-őr kiiktatása a routerben (`if (true)`) | **PIROS** — mindkét A7-cella (`flag OFF → /practice` és `/practice/setup` Live-fallback) |

A `practiceEngineV2Enabled` alapértéke mérve **`false`**
(`feature_flags.dart:15`), tehát a production viselkedés változatlan; a
flag-gating mércéje bizonyítottan fog.

## 5. Kód-megfigyelések (nem lelet)

- A Setup **nem** hivatkozik a session controllerre: a `PracticePrepareSink`
  injektálható boundary mögé küldi a `PreparePractice` commandot, a production
  default naplózó nyelő — a Kör 13 cseréli valódira. Ez összhangban van az
  R11 review §11.4/4 follow-upjával (a controller-provider ma szándékosan nem
  áll össze production oldalon).
- Ismeretlen/hiányzó `id` a Setup route-on: lokalizált hibaállapot, tesztelve
  (`unknown id shows the localized error state`).
- 41 új `practice*` ARB-kulcs en+hu, a parity-gate-tel őrizve.

## 6. Merge-döntés

**A merge nincs blokkolva.** CI zöld pontosan a `de930b5` HEAD-en
([30663683642](https://github.com/wolfcasaba/strumsight/actions/runs/30663683642)),
headSha ↔ HEAD egyeztetve (L21).
