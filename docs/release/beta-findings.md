# Beta findings — StrumSight

**Kör:** `E12-R28` (Chapter 12, Kör 28). **Normatív forrás:**
[ADR 0489](../adr/0489-ga-scope-classification-and-contract-freeze.md) D8.

## 1. Mért állapot: a Closed Beta MA NEM indult el

[`docs/beta/closed-beta-launch.md:3`](../beta/closed-beta-launch.md) —
"**Status: NOT launched** — this document is a gate, not a launch
announcement". Ugyanennek a fájlnak az 5. szakasza ("Human launch field")
kipipálatlan és kitöltetlen, szándékosan — a bétaindítás emberi döntés és
emberi akció, ezen a repón kívül (`E12-R27` handoff: "**A béta NEM
indult el.**").

**Ebből következik: a fán ma nulla terepi béta-mérési adat van** — nincs
top-issue lista, nincs funnel-szám, nincs tesztelői létszám, mert ezekhez
egyetlen valódi tesztelői munkamenet sem futott le. Ez a fájl ezért **nem**
egy triage-összefoglaló (nincs mihez) — azt rögzíti, hogy a `docs/beta/`
alatt ma mi VAN: eljárás (triage-kategóriák, napi sablon, beleegyezés,
cohort-profil), nem terepi mérés.

**Kitalált top-issue lista, kitalált funnel-szám, kitalált tesztelői
létszám, vagy bármely olyan állítás, amely csak akkor lenne igaz, ha a béta
lefutott volna: ez a dokumentum szándékosan nem tartalmaz ilyet** (ADR 0489
D8). A [`tool/release/verify_ga_scope.py`](../../tool/release/verify_ga_scope.py)
D3-ellenőrzése emiatt sem hivatkozhatna nem létező béta-riportra — egy ilyen
hivatkozás nem-nulla kilépés lenne, mert a fájl nem oldható fel.

## 2. Milyen bizonyítékforrásokra épül a `ga-scope.md` besorolása helyette

A [`ga-scope.md`](ga-scope.md) capability-táblájának minden sora a fán MA
feloldható forrásra hivatkozik — béta helyett ezekre:

| Forrás | Mit ad |
|---|---|
| [`docs/beta/cohort-profiles.yaml`](../beta/cohort-profiles.yaml) | melyik flag melyik cohortban `true`/`false` — a besorolás alanyainak zárt halmaza (D1) |
| [`lib/core/feature_flags/feature_flag_registry.dart`](../../lib/core/feature_flags/feature_flag_registry.dart) | kockázati szint (`high`/`medium`/`low`), kill-switch útvonal, van-e dart-define |
| [`docs/release/blockers.md`](blockers.md) | nyitott P0/P1 release-blokkolók (R-SIGN-01, R-PRIV-01, R-SEC-01, ...) |
| [`docs/testing/device-matrix.yaml`](../testing/device-matrix.yaml) | egy MÁSIK, durvább szemcséjű, MÁR meglévő `capabilities[].ga_scope` tengely (E12-R13) — megerősítő, nem döntő forrás ehhez a körhöz |
| [`docs/sdd/epic-03-completion-report.md`](../sdd/epic-03-completion-report.md), [`docs/sdd/epic-06-completion-report.md`](../sdd/epic-06-completion-report.md) | Epic-szintű "implementation evidence recorded, release blockers remain" / "rollout stays at shadow" állapotok |
| [`docs/adr/0467-adaptive-shell-is-the-non-production-default.md`](../adr/0467-adaptive-shell-is-the-non-production-default.md) | az adaptív shell production-GA döntését kimondottan erre a körre halasztó ADR |
| [`test/e2e/first_practice_offline_test.dart`](../../test/e2e/first_practice_offline_test.dart) és a másik három `E12-R11` e2e-cella | a core tanulási út gépi leírása |

## 3. Újramérési feltételek — melyik besorolás melyik béta-mérésre vár

Egyik `ga-scope.md`-sor besorolása sem VÁRJA a bétát ahhoz, hogy MA
kimondható legyen — mindegyik a fenti, MA feloldható forrásra épül (D8: "ha
egy capability GA/preview besorolása KIZÁRÓLAG béta-adatból következne, a
besorolása `postponed`, nem becslés"). Ami valóban a béta lefutására vár, az
nem egy besorolás, hanem annak **megerősítése vagy cáfolata**:

| Ami a béta lefutásával újramérésre kerül | Miért |
|---|---|
| `labModeAvailable` (`preview`) | ma csak azt tudjuk, hogy a flag mindkét cohortban `true` — azt, hogy a tesztelők ténylegesen belebotlanak-e Lab-felületekbe, és az hordoz-e olyan hibát, ami miatt a `preview` besorolást felül kellene vizsgálni, csak triage-adat mondaná meg. |
| `migratedLearnEnabled`, `practiceDetailedHistoryEnabled` (`preview`) | a `closed_beta` cohort ma kikapcsolva tartja mindkettőt — egy jövőbeli kör csak akkor terjesztheti ki `closed_beta`-ra, ha az `internal` cohort dogfood-tapasztalata (vagy egy tényleges bővített béta) ezt alátámasztja. |
| `songTrainerV2Enabled`, `audioAnalysisV2Enabled` (`postponed`) | az Epic 3/6 completion reportban rögzített release-blokkolók lezárása az elsődleges feltétel; egy tényleges béta-kör emellett megerősítené vagy megcáfolná a rollout-tervet. |
| `aiTutorEnabled`, `aiTutorCloudEnabled`, `visionEnabled`, `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled` (`postponed`) | mindegyik a `docs/release/blockers.md` nyitott P1-jeire (`R-PRIV-01`, `R-SEC-01`) és/vagy hiányzó modell-eszközökre vár — a béta ezeknél másodlagos, a blocker-zárás az elsődleges feltétel. |
| `adaptiveShellEnabled` (`preview`) | az `internal` cohort ma éli, a `closed_beta` nem — egy tényleges bővített béta triage-adata döntené el, hogy a `closed_beta`-ra is kiterjeszthető-e. |

**Amit ez a dokumentum NEM állít:** hogy bármelyik fenti sor rosszabb vagy
jobb lenne, mint egy béta után hozott döntés — csak azt, hogy MA kevesebbet
tud, mint egy béta utáni scope (ADR 0489 "Következmények" szakasz). A
visszavonás feltétele ugyanaz, mint az ADR-é: ha a Closed Beta ténylegesen
lefut és terepi triage-adatot termel, ez a dokumentum és a `ga-scope.md`
együtt esedékes az újramérésre.
