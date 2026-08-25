# Miért halad lassan a Ch13 (UI) sáv — mért diagnózis

**Mérve:** 2026-08-25, `main @ b28bb1bf`. Forrás: `.pipeline/chain.log`,
`.pipeline/session-*.log`, `tools/round-metrics.py`, `tools/halt-ledger.py`,
`docs/execution/pipeline-queue.tsv`, `gh run list`.

A vizsgálat kérdése: a lánc a Ch13 sávra szűkítve miért produkál napi 1 kört a
korábbi 4-5 helyett, és kell-e Flutter/Dart verziót emelni.

---

## 1. A számok

`tools/round-metrics.py` (226 mért kör): **medián kör-idő 90 perc.**
Az utolsó UI-körök viszont:

| kör | kör-idő | önjavító | mi történt |
| --- | ---: | ---: | --- |
| E13-R13 | 171p | 0 | normál |
| E13-R14 | 132p | 1 | normál |
| E13-R16 | **1121p** | 3 | lásd §2 |
| E13-R17 | (folyamatban) | 1 (H3) | sáv-szintű brief-defekt, §3 |

Az E13-R16 (18 óra 41 perc) idővonala percre bontva:

| ablak | hossz | mi történt |
| --- | ---: | --- |
| 22:50–02:40 | 3h50m | 4 session (2 orchestrátor + 2 önjavító) indult és halt meg AZONNAL a Claude heti kereten; mind H-NOSIGNAL-nak minősítve |
| 02:40–14:05 | **11h25m** | a lánc HALT-on ÁLLT, kézi `tools/pipeline-status.sh --resume`-ra várva — a keret közben 08:00-kor megnyílt |
| 14:05–17:30 | 3h25m | a tényleges fejlesztés: kör + H3 halt + heal + 4 javító kör + merge |

**A 18,7 órából ~15,2 óra (81%) nem fejlesztés volt, hanem kvóta-félreosztályozás
és kézi feloldásra várakozás.**

---

## 2. Első gyökérok — a heti Claude-keret, félreosztályozva (JAVÍTVA)

A CLI a heti keret kimerülésekor ezt írja a panelre:

```
You've hit your weekly limit · resets 8am (UTC)    /upgrade to increase your usage limit.
```

A `tools/round-pipeline.sh` `CLAUDE_LIMIT_PATTERN` mintája `(usage|session)
limit` alakra illeszkedett — a `weekly` szóra **nem**. Ellenőrizve:

```
NO-MATCH:: You've hit your weekly limit · resets 8am (UTC)
MATCH   :: You've hit your usage limit
```

Következmény-lánc: kvótahalál → H-NOSIGNAL → önjavító kör (ami maga is
Claude-keretet kér, tehát ugyanabba a falba fut) → a keret elfogy → lánc-HALT →
kézi `--resume`. **Az utolsó 60 pipeline-session közül 18 pontosan ezen a
mondaton halt meg.**

A driver ugyanezt a hibaosztályt kétszer már megoldotta más motorra (Terra
napi-budget: E03-R08 H6; Codex CLI usage-limit: E05-R15 H6) — csak a
Claude-rétegre nem. A javítás ezt a mintát húzza rá a harmadik rétegre:
`claude_quota_hold_if_detected` / `claude_quota_hold_active_for`, és a kvótán
elhalt session **nem ír HALT-fájlt**. Mérce:
`tools/tests/test_claude_weekly_quota_hold.py` (a javítás előtt 4 failed,
utána 4 passed).

**Ami ettől NEM oldódik meg:** a keret maga. Egy UI-kör MINDKÉT oldala ugyanazt
az előfizetést fogyasztja — az orchestrátor/reviewer `claude-opus-5
--effort max` (a `sonnet-impl` sorok bedrótozott alapértéke,
`round-pipeline.sh:153,159`; az általános default `high`), az implementer
`claude-sonnet-5 --effort high` ugyanabban a `~/.claude` config-dirben. A
`minimax` motor (MiniMax-M3, saját API-kulcs, saját számla) eközben mérve
**92% heti / 99% intervallum szabad kerettel** elérhető, és nincs használatban.
A `docs/execution/pipeline-queue.tsv` saját, 2026-08-21-i döntés-blokkja
egyébként `minimax`-ot ír elő minden nyitott sorra — az E13 sorok ezzel szemben
`sonnet-impl`-en állnak. Ez motor-döntés, nem hiba: a `minimax` mért gyengéje
(„invariánst lazít") az UI-minőség rovására mehet, ezért user-döntés.

---

## 3. Második gyökérok — sáv-szintű brief-defekt a migrációs körökben

Az R16-tal a sáv átfordult *komponens-építésből* **képernyő-migrációba**. Egy
migrációs kör lecserél egy örökség-képernyőt, amit a fa MÁS pontjain élő tesztek
importálnak/pinnelnek — ezek a kör `allowed_paths`-án kívül vannak, a felvételük
tágítás → **H3**, az orchestrátor nem oldhatja fel. Ez állította meg az R16-ot
(F9, képernyő-leltár) és az R17-et (navigációs őrök) is.

A hátralévő sávon ez **nem egyedi eset, hanem szerkezet**. Mérve (a kör
`allowed_paths`-ában szereplő `*_screen.dart` fájlok ↔ az őket importáló, de a
briefen kívüli tesztek):

| kör | kívül maradt teszt |
| --- | ---: |
| E13-R18 (Live) | 7 |
| E13-R19 (Tuner/Metronóm) | 6 |
| E13-R20 (Chords/Learn) | 5 |
| E13-R21 (Practice session) | 3 |
| E13-R32 (Gamification) | 1 |
| E13-R35 (Account/Share) | 5 |

**Összesen 28 (kör, teszt) pár 6 körben.** Köztük olyanok, amik a mérce
gerincét adják: `test/ui/ui_baseline_screenshot_test.dart` (az R19 lecseréli a
`tuner_screen.dart`-ot, amit ez a teszt IMPORTÁL — fordítási hiba, nem
assert-hiba), `test/app/navigation/adaptive_scaffold_test.dart` (R18/R19/R20/
R21/R35 — ugyanaz az őr, ami az R17-et megállította),
`test/app/routing/app_router_test.dart`, `test/core/screen_size_guard_test.dart`.

Emellett **0/20** hátralévő brief nevezi meg a teljes `lib/` fát pásztázó
őröket (`test/tooling/route_literal_guard_test.dart`,
`test/core/architecture_dependency_test.dart`,
`test/features/practice/domain/domain_purity_test.dart`) — ezek a célzott
kör-gate-en NEM futnak, csak az exact-SHA Full Gate-en, tehát a lelet MINDIG
későn, javító körben érkezik (ez volt az R16 F8/F9 mintája).

A `tools/brief-lint.py` `S9`/`S10` szabályai ennek a hibaosztálynak eddig két
konkrét esetét fedték le (képernyő-leltár, router-őr), mindkettőt **utólag**,
HEAL-körben. A javasolt lépés ugyanaz a minta, egy szinttel általánosabban: egy
`S11` szabály, ami a kör `allowed_paths`-ában lecserélt képernyők ELLEN méri a
fát, és követeli a pinnelő tesztek felvételét — plusz a 6 érintett brief
egyszeri, sáv-szintű eltakarítása. Így 6 halt marad el a 19 hátralévő körben,
a mai HEAL-per-halt ütem helyett.

---

## 4. Amit MÉRVE nem érdemes bántani

**Flutter/Dart verzió: NE emelj.** A box `Flutter 3.44.2 / Dart 3.12.2`, és
mind a **hat** workflow (`build-apk`, `full-gate`, `router-ci`, `dsp-probe`,
`lab-apk`, `release-apk`) EXAKT ugyanerre a `flutter-version: '3.44.2'`-re van
pinelve — nincs lokál/CI divergencia, ezért működik a golden-kapu. Van újabb
stabil (`3.44.9` patch, `3.47.1` minor), de az emelés (a) egyetlen mért
szűk keresztmetszetet sem old fel, (b) a motor szövegrenderelését elmozdítva a
10 golden PNG + 7 baseline képernyőkép mércéjét — pont az UI-minőség kapuját —
tömegesen pirosra váltaná, (c) hat workflow lépészáras bumpját kérné. Ha
egyszer mégis: önálló GOV-kör, a Ch13 lezárása UTÁN.

**A box és a CI nem szűk keresztmetszet.** Full Gate CI: 14–17 perc
(`gh run list`). A 4 magos ARM box lassú, de a teljes suite mérve CI-ben fut
(ADR 0053), a kör-gate célzott. Higiénia: 5 elárvult `flutter_tester` process
(aug. 22–24-i klónokból) és ~30 régi `~/ss-*` munkapéldány takarítható, de
ezek nem okozói a lassulásnak.

**A Codex-oldal (Sol/Terra) INERT, nem zavaró — és nem is szabad kivágni.**
User-kérdés 2026-08-25: „kodex nincs, töröld le ha zavar". Mérve, hol lehetne
még útban: a nyitott sorok motorja **0 codex/terra** (58 `minimax` + 20
`sonnet-impl`), a `fallback_engine` alapértéke már a scriptben `none`, és az
`orchestrator_preference=claude`. Az EGYETLEN pont, ahol a lemezen maradt
`~/.codex*/auth.json` még számít, az utolsó önjavító kísérlet motorváltása —
a kizárása viszont MÉRVE elbukik: a `test_selfheal_escalation.py` szerint a
harmadik kísérletnek MÁS modellre kell váltania, és a kizárás után nem marad
jelölt, azaz a próba elmarad. Az eszkaláció elvesztése rosszabb, mint egy
esetleg kimerült kereten elköltött utolsó kísérlet, ezért a Codex-sorok
MARADNAK. (A javítási kísérlet és a mérés: a `9ed537b5` commit és a
visszavonása ezen az ágon.)

**A pipeline-mechanika és a review-fegyelem működik.** Az R17 (kvóta-mentes
ablakban): implementer `status=done` 34 perc alatt, review APPROVED
0 BLOCKER / 0 MAJOR. A lánc nem lassú — a lánc ÁLL.
