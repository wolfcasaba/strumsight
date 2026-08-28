# Release history audit — StrumSight

**Mérés SHA-ja:** `main @ 92576977` (`chore(pipeline): a Chapter 12 sáv AKTIVÁLÁSA …`, 2026-08-28 01:42:55 +0200).
**Mérte:** E12-R01 implementer (Claude Sonnet 5), 2026-08-28.

A brief §7 tiltja az implementernek a `gh` hívását. A GitHub Releases-leltárt
ezért az orchestrátor pre-flightban mérte le és a kör-brief §0.0.A P2
szakaszában adta át hiteles bemenetként (`docs/rounds/e12-r01-program-baseline-and-release-history-audit.md:41-92`).
Az alábbi táblázat abból van átvéve — a forrás-parancsok szó szerint
újrafuttathatók egy `gh`-hoz hozzáférő reviewer által; az implementer csak a
helyi, `gh`-t nem igénylő tag-adatokat futtatta újra (lásd §2).

## 1. Összegzés

- **26 GitHub Release** — forrás-parancs: `gh release list --limit 100 --json
  tagName --jq 'length'` → `26` (pre-flight mérés, §0.0.A P2).
- **27 git tag** — **ezt az implementer maga is újrafuttatta**: `git tag | wc
  -l` kimenete → `27`.
- **Delta = pontosan 1 tag-only ref: `build-81`** (van tag, nincs hozzá
  Release) — forrás-parancs: `for t in $(git tag); do gh release view "$t"
  >/dev/null 2>&1 || echo "$t"; done` → `build-81` (pre-flight mérés, §0.0.A
  P2). Az implementer a helyi `git tag` kimenetében ellenőrizte, hogy
  `build-81` valóban szerepel a 27 tag között — igen (lásd §2 nyers lista).
- Legrégebbi tag: `v0.1.0` (2026-07-05T22:14:07Z) · legfrissebb (`isLatest`):
  `gov-05-shipping` (2026-08-09T18:30:53Z) — dátumok forrása: pre-flight
  mérés (§0.0.A P2); a két végpont commit-dátumát az implementer helyileg is
  ellenőrizte (`git log -1 --format='%ai' v0.1.0` → `2026-07-05 22:14:07
  +0000`, `git log -1 --format='%ai' gov-05-shipping` → `2026-08-09 18:30:53
  +0000` — egyezik).

## 2. Helyi tag-lista — az implementer saját mérése

`git tag | wc -l` kimenete → `27`. `git tag | sort` kimenete (mind a 27 tag,
ábécésorrendben):

```
build-112, build-175, build-19, build-22, build-23, build-24, build-25,
build-28, build-29, build-31, build-33, build-35, build-37, build-39,
build-41, build-43, build-45, build-48, build-58, build-64, build-66,
build-81, e01-r16, e02-r08, gov-05-shipping, v0.1.0, v0.2.0
```

Ez a 27 név **pontosan** a lenti (§3) 26 soros Release-táblázat tag-neveit
PLUSZ a `build-81`-et tartalmazza — az implementer ezzel keresztellenőrizte a
pre-flight delta-állítását (`build-81` az egyetlen tag-only ref) a saját,
`gh` nélküli mérésével.

**Fontos korlát:** a git tagek ebben a repóban lightweight tagek (nincs saját
tag-üzenetük) — `git for-each-ref --format='%(refname:short) %(objecttype)'
refs/tags` kimenete minden sorban `commit`-ot mutat, nem `tag`-et. A `git tag
-l -n1 <name>` ezért a **tagelt commit üzenetét** adja vissza, NEM a GitHub
Release címét (pl. `v0.1.0` mögötti commit üzenete `ci(apk): StrumSight
artifact name, drop supabase dart-define`, míg a Release címe — lásd §3 —
`StrumSight v0.1.0 — v1 UI (mock engine)`). A Release-címek ezért **kizárólag
GitHub-oldali metaadatok**, `gh` nélkül lokálisan nem reprodukálhatók — ez az
oka annak, hogy a §3 táblázatot a pre-flight méréséből vesszük át, nem
próbáljuk újra előállítani.

## 3. Teljes Release-leltár (pre-flight mérés, §0.0.A P2 — forrás: `gh release list --limit 100`, 2026-08-28)

| Tag | Létrehozva (UTC) | Cím |
|---|---|---|
| `gov-05-shipping` | 2026-08-09T18:30:53Z | GOV-05 shipping rollout — Practice V2 + Song Trainer V2 + Learn V2 (development APK) |
| `e02-r08` | 2026-07-31T07:57:09Z | E02-R08 — Observation gateway (development APK) |
| `e01-r16` | 2026-07-30T07:31:10Z | E01-R16 — Epic 1 zárókör (development APK) |
| `build-175` | 2026-07-14T00:38:31Z | StrumSight — no-strum reject live (r175) |
| `build-112` | 2026-07-11T11:41:17Z | StrumSight build-112 — round 112 (15-lesson curriculum, metre-aware count-in) |
| `build-66` | 2026-07-10T12:10:41Z | StrumSight build-66 — moat + game-feel + glowing highway |
| `build-64` | 2026-07-10T08:58:32Z | StrumSight build-64 — moat hardened + game-feel |
| `build-58` | 2026-07-10T04:49:51Z | StrumSight build-58 — Songwriting suite: build songs, setlists, metronome & progress |
| `build-48` | 2026-07-09T14:00:40Z | StrumSight build-48 — Strum Reel, Jam mode, more lessons |
| `build-45` | 2026-07-09T13:30:37Z | StrumSight build-45 — more chords, a barre lesson, left-handed mode |
| `build-43` | 2026-07-09T13:07:36Z | StrumSight build-43 — Chord diagrams everywhere + chord library |
| `build-41` | 2026-07-09T12:11:35Z | StrumSight build-41 — Learn: chord diagrams + slow-down practice |
| `build-39` | 2026-07-09T10:58:15Z | StrumSight build-39 — Learn: chord grading + quality-of-life |
| `build-37` | 2026-07-09T10:20:36Z | StrumSight build-37 — Learn: metronome + practice your own recordings |
| `build-35` | 2026-07-09T09:26:22Z | StrumSight build-35 — Learn: full curriculum + shareable scores |
| `build-33` | 2026-07-09T07:33:44Z | StrumSight build-33 — Learn mode: play-along + scoring |
| `build-31` | 2026-07-09T06:48:25Z | StrumSight build-31 — Growth pack: Share, Streaks, Onboarding |
| `build-29` | 2026-07-09T05:11:30Z | StrumSight build-29 — Share your Strum Card (growth) |
| `build-28` | 2026-07-08T14:39:11Z | StrumSight build-28 — Chord dictionary + Viterbi (extended chords, 7ths) |
| `build-25` | 2026-07-07T08:03:12Z | StrumSight build-25 — Chordino-class chord engine (NNLS) |
| `build-24` | 2026-07-07T06:27:36Z | StrumSight build-24 — tuner & Live reject voice/noise |
| `build-23` | 2026-07-07T05:57:00Z | StrumSight build-23 — Analyze + Library work; clean UI |
| `build-22` | 2026-07-07T05:45:56Z | StrumSight build-22 — Analyze + Library now work |
| `build-19` | 2026-07-06T11:50:52Z | StrumSight build-19 — tuning A4 + account sync |
| `v0.2.0` | 2026-07-05T22:57:41Z | StrumSight v0.2.0 — real on-device detection |
| `v0.1.0` | 2026-07-05T22:14:07Z | StrumSight v0.1.0 — v1 UI (mock engine) |

`build-81` (2026-07-10T19:09:39Z helyi commit-dátum, `git log -1
--format='%ai' build-81` kimenete) **nincs a fenti táblázatban** — ez a
pre-flight méréssel azonosított egyetlen tag-only ref (van git tag, nincs
hozzá GitHub Release).

## 4. `build-NN` tagnév vs. pubspec build number

**A `build-NN` tag NEM a pubspec build numbere.** A tagnevek a projekt
SDD előtti belső kör-számozását hordozzák (`build-175` = a projekt 175.
belső fejlesztési köre), miközben a `pubspec.yaml:5` a mérés pillanatában is
`1.0.0+1` — lásd `program-baseline.md` §1. A 26 GitHub Release és a
változatlan `+1` build number csak együtt értelmezhető: a projekt eddig soha
nem emelte a pubspec build számát egyetlen kiadáshoz sem, a `build-NN`
tagelés egy párhuzamos, SDD előtti névkonvenció.

## 5. Publikus store-jelenlét

**NINCS publikus store-jelenlét** (Google Play / Apple App Store) a mérés
pillanatában. Bizonyíték:

- A Chapter 12 tervben a store-belépő kör (`E12-R24 —
  store-listing-and-legal-package`) **`pending`** státuszú, azaz még nem
  futott: `grep -n "^E12-R24" docs/execution/pipeline-queue.tsv` kimenete →
  `E12-R24	docs/rounds/e12-r24-store-listing-and-legal-package.md
  sonnet-impl	nincs	pending`.
- Nincs Fastlane- vagy store-metaadat fájl a repóban: `find . -iname
  "*fastlane*" -not -path "./.git/*"` kimenete üres; `find . -iname
  "*app-store*" -o -iname "*play-console*"` (a `.git/`-et kiszűrve) kimenete
  üres.
- Nincs commitolt `.aab` (Android App Bundle, a Play Store kötelező
  formátuma): `find . -iname "*.aab" -not -path "./.git/*"` kimenete üres.
- A `docs/governance/04-release-checklist.md` „Store" szakaszának mind az 5
  sora pipálatlan (`[ ]`) — `sed -n '35,41p' docs/governance/04-release-checklist.md`
  kimenete a `## Store` fejléc alatt 5 db `[ ]` sort mutat.

A 26 cím közül 3 kifejezetten megnevezi magát „(development APK)"-ként
(`gov-05-shipping`, `e02-r08`, `e01-r16` — lásd a §3 táblázat „Cím" oszlopát);
a többi 23 cím `StrumSight build-NN — …` alakú, artifact-típust a címben nem
nevesítve. Az egyes Release-ekhez tartozó tényleges asset-lista (`gh release
view <tag> --json assets`) ellenőrzése `gh`-t igényelne, amit ez a kör nem hív
(brief §7) — ezért az implementer **nem állítja**, hogy mind a 26 Release
APK-t tartalmaz, csak azt, hogy egyik sem store-disztribúció (Play Store /
App Store nem képes GitHub Release-ből telepíteni).

## 6. Kapcsolódó dokumentum

[program-baseline.md](program-baseline.md) §1 (alkalmazás-azonosság,
`build-NN` vs. pubspec) és §3 (`release-apk.yml` production signing) a jelen
audit előfeltétele — a két dokumentum együtt olvasandó. A jelen auditból
következő release-blokkolók a [blockers.md](blockers.md)-ben.
