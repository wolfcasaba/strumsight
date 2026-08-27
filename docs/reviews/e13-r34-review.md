# E13-R34 — Review (Claude Opus 5, orchestrátor)

- **Kör:** `E13-R34` — Community challenges, clubs, notifications és safety UI
- **Branch:** `sonnet-impl/e13-r34-community-challenges-and-safety`
- **Review-elt HEAD:** `2ec09669`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor) + `security-reviewer` ügynök (a brief §7
  review-megjegyzése szerint KÖTELEZŐ, `risk = "high"`)
- **Dátum:** 2026-08-27

---

## 1. Amit a review MAGA futtatott (nem az implementer bemondása)

| Mérés | Hol | Eredmény |
|---|---|---|
| `tools/round-gate.sh` a §7 pontos parancssorával (10 útvonal) | izolált `/tmp/ss-review-e13-r34` klón, `2ec09669` | **15/15 lépés ZÖLD**, `GATE_EXIT=0` |
| `tools/golden-x86.sh check test/ui/goldens/e13_r34_screens_golden_test.dart` | ugyanott, x86_64 (a CI-vel azonos ISA) | **14/14 ZÖLD**, exit 0 |
| `tools/scope-audit.py --base 49d8423a` | a munkapéldány ellen | **OK** — 31 érintett útvonal, 0 listán kívüli |
| `full-gate.yml` exact-SHA CI | `headSha = 2ec09669` | **success** ([33084045920](https://github.com/wolfcasaba/strumsight/actions/runs/33084045920)) |
| `router-ci.yml` exact-SHA CI | `headSha = 2ec09669` | fut / ellenőrizve a merge előtt |

**A `dirty_files=1` kivizsgálva** (kötelező ellenőrzés, `docs/LESSONS.md` L21): a
munkapéldány `git status --short`-ja ÜRES; a számláló a jelzés írásának
pillanatában a gitignore-olt `.codex-round-status` fájlt számolta
(`git check-ignore -v` → `.gitignore:66`). Nincs elveszett munka: mind a 15
kör-commit a branchen van.

**A jelzésfájlban NEM volt `scope_audit=` kulcs**, ezért a §1.1 táblája szerint
kézzel futtattam (fenti sor) — a `skipped`/hiányzó audit nem bizonyíték.

## 2. Saját, ELDOBHATÓ valódi-sértés próbák (a reviewer méri, nem az implementer)

| Próba | Injekció | Elvárt | MÉRT |
|---|---|---|---|
| **P1 — A3** | a `club_detail_screen.dart` „küszöb alatt" ága `Text(club.name) + Text(club.description)`-re cserélve | a leakage-cella PIROS | **PIROS** — `A3 — below the threshold … the private club name and description never render for a non-member [E]`; a többi 5 cella zölden maradt (a próba pontosan a megcélzott ágat fogta) |
| **P2 — A1** | `ChallengeController.acceptInvite` elé `_repo.leaderboard(...)` hívás | az A1-cella PIROS | **PIROS** — `Actual: <1>` + a cella saját `reason` szövege („accepting a challenge invite must not enroll the viewer onto a ranking") |

Mindkét injekció visszaállítva; a klón fája utána tiszta. **A két őr tehát
valódi kapu, nem üres állítás.**

## 3. Leletek

### MAJOR-1 — A3: a privát klub NEVE kiszivárog a klub-LISTA előnézetében; a kör kliens-oldali kapuja csak a RÉSZLETnézetre került fel

**Fájl:** `lib/features/community/presentation/screens/clubs/club_list_screen.dart:230–247`
(`itemBuilder` — szűrés NÉLKÜL épít `_ClubRow`-t minden elemre) és `:273–275`
(`Semantics(label: '${club.name}. $memberCountLabel.')`) + `:288–294` (látható
`Text(club.name)`).

**Mért ellentét a kör SAJÁT kódján belül:** a `club_detail_screen.dart:203–241`
a körben ÚJ, háromágú `myRole == null && visibility == private` kaput kapott, és
a `:66–72` doc-comment kimondja az indokot — *„closing the leak channel a
repository that returns more than the SUMMARY placeholder would otherwise
open"*. **Ugyanez a fenyegetésmodell a listára is érvényes, ott mégis nyitva
maradt.** A `security-reviewer` reprodukálta:

```
PROBE list TEXTS:     [Secret Blues Club, Private · 5 members, Load more, Clubs]
PROBE list SEMANTICS: [Secret Blues Club. Private · 5 members.]
```

**Miért MAJOR és nem NOTE:** a brief §5.3 szó szerint kimondja, hogy *„a cím maga
is tartalom"*, a §6.1 A3-cellája pedig névvel nevezi a **„lista-előnézet"**
csatornát — a `private_club_leakage_test.dart` viszont KIZÁRÓLAG a
`ClubDetailScreen`-re állít (`_wrapDetail`). Mind a 17 célteszt-cella zöld,
miközben a kör saját acceptance-kritériumának egyik nevesített csatornája
méretlen és nyitva van. Ez pontosan az a „a zöld gate nem bizonyíték"
hibaosztály, amit a brief §7 review-megjegyzése miatt futtattunk
biztonsági ügynökkel.

**A javítás:** ugyanaz a predikátum a `club_list_screen.dart` sor-építőjében
(kihagyás vagy zárolt helyőrző), ÉS egy NEGYEDIK A3-cella a
`private_club_leakage_test.dart`-ba, ami a `ClubListScreen`-re állít
`findsNothing`-ot a privát klub nevére — **látható szövegre ÉS `Semantics`
labelre egyaránt** (a mellékcsatorna külön cella, mert a próba szerint a név
mindkettőben megjelenik).

---

### MAJOR-2 — A6/A8: az elutasított tiltás/némítás NÉMÁN elbukik a kör KÉT ÚJ védelmi akcióján

**Fájl:** `lib/features/community/presentation/screens/clubs/club_member_management_screen.dart:240–252`
(`_blockOrMute`) és `lib/features/community/presentation/screens/community_challenges_screen.dart:340–357`
(`_blockOrMuteAuthor`). **Mindkettő a körben ÚJ kód.**

`await repo.block(...)` / `await repo.mute(...)` **`try`/`catch` NÉLKÜL** áll egy
`PopupMenuButton.onSelected` / sheet-callback belsejében. Hálózati hibán
(`NetworkFailure(network.unavailable)`) az `AppFailure` kezeletlen aszinkron
hibaként szabadul el; **SnackBar nincs, állapotváltozás nincs**, a menü/lap
bezárul — a felület pontosan úgy néz ki, mint sikeres tiltás után. A
kihívás-lapon a `Navigator.of(sheetContext).pop()` ráadásul az `await` **ELŐTT**
fut (`:346`), tehát a lap már be is csukódott, mire a hiba megtörténik.

**Mért ellenpélda a kör SAJÁT diffjében:** `safety_relationships_screen.dart:308–320`
ugyanezt a műveletet `try { … } on AppFailure catch (failure) { … showSnackBar(_formatFailure(…)) }`
alakban végzi. A két új akció ezt a testvér-mintát nem örökölte.

**Miért MAJOR:** a tiltás **védelmi** művelet. A némán elbukó védelmi művelet
hamis biztonságérzetet ad — a felhasználó azt hiszi, elzárta magát egy
zaklatótól, közben nem történt semmi. Ez a projekt nevesített hibaosztálya
(`CLAUDE.md`: *„Cloud writes swallowed by `try/catch` → silent no-op"*), itt a
fordított alakban: **nincs is `catch`**. Az A6/A8 cellák csak a boldog utat
mérik (a `_RecordingSocialGraphRepository` sosem dob).

**A javítás:** mindkét metódus `try { … } on AppFailure catch (f) { … }`-be, a
meglévő `_formatFailure` + SnackBar mintával; a challenges-lapon a `pop()` az
`await` UTÁN, vagy a SnackBar a szülő `ScaffoldMessenger`-en (a `sheetContext`
a pop után halott). **A tesztbe DOBÓ fake-kel egy „a bukás LÁTHATÓ" cella
mindkét felületre** — enélkül a javítás mérce nélkül maradna.

---

### MINOR-1 — A10: beégetett angol `Semantics` szöveg a kör ÚJ kódjában, miközben a fájl doc-commentje teljes lokalizációt állít

**Fájl:** `community_challenges_screen.dart:413` → `semanticLabel: 'Verified'`
(**a diffben ÚJ sor**, `_MyResultSection`), és
`clubs/club_detail_screen.dart:415` → `label: 'Role: $roleLabel'` (a `'Role: '`
előtag beégetett angol; a sort a kör MOZGATTA, tehát a diff `+` oldalán áll).

A `club_detail_screen.dart:47–50` doc-commentje viszont azt állítja: *„Every
user-facing string routes through `AppLocalizations`"* — ez a kör saját
fájljáról tett, **kódban nem igaz** állítás (a brief §4 doc-comment-fegyelme:
csak bizonyított állítás). Magyar locale + képernyőolvasó mellett „**Role:**
Tulajdonos" és „**Verified**" hangzik el.

Az A10 cellapár csak látható `find.textContaining`-ot néz és a `const String
_l10nClub*` konstansok hiányát — a `Semantics`/`semanticLabel` csatornát nem
méri, ezért zölden marad.

**A javítás:** mindkét sztring ARB-kulcsba (`en` + `hu`), és az A10 terjedjen ki
a `Semantics` felületre (`bySemanticsLabel` vagy a semantics-fa olvasása).

---

## 4. NOTE-ok (nem a javító kör dolga — kifejezett átadás)

- **NOTE-1 — az értesítés ismeretlen `titleKey`-e NYERSEN renderelődik.**
  `community_notifications_screen.dart:237` (`_lookupKey(...) ?? item.titleKey`).
  **MÉRVE: KÖR ELŐTTI** — `git show origin/main:…` ugyanezt a sort mutatja
  (E09-R20). A `CommunityNotificationItem` factory-ja valódi `throw`-val
  charset-zárolja a kulcsot (`notification_item.dart:145–149`,
  `^[a-z][A-Za-z0-9_]*$`), tehát szabad szövegű injekció szerkezetileg zárt; ami
  átfér, az egyetlen camelCase token. **Nem ennek a körnek a regressziója**, és
  a fail-closed alakra váltás egy LEZÁRT kör viselkedését módosítaná (H2) —
  külön kör tárgya.
- **NOTE-2 — a `_requestJoin` szintén `try`/`catch` nélkül áll**
  (`club_detail_screen.dart:243–256`). **MÉRVE: KÖR ELŐTTI** (`origin/main`
  ugyanígy). Ugyanaz az osztály, mint a MAJOR-2, de nem védelmi művelet, és nem
  a kör vezette be — a MAJOR-2 javításával együtt olcsó lenne, de nem
  elvárás.
- **NOTE-3 — hat bájtazonos `en`/`hu` ARB-pár, MIND KÖR ELŐTTI**
  (`feedCard*` sablon-interpolációk + `feedCardAchievementUnlocked`,
  `communityNotificationLevelPush`). **A kör 59 ÚJ kulcsa közül egy sem
  bájtazonos** — a kör L519 szempontból tiszta (a saját `en`/`hu` detektorom is
  0 párt talált a diff Dart-literáljai ellen).
- **NOTE-4 — a `report` (bejelentés) akció NINCS bedrótozva.** MÉRVE:
  `showReportContentSheet` egy `ReportRepository`-t KÖVETEL (`report_content_sheet.dart:149–152`),
  és `grep -rn "showReportContentSheet" lib/` → **nulla production hívó** az
  egész fán (csak tesztek). Egy production implementáció a `data/` réteget
  kívánná, ami a kör TILOS zónája — **valódi H3**, nem mulasztás. Az A6 a
  tiltás/némítás lábán MINDKÉT felületről teljesül; a bejelentés-láb egy
  jövőbeli kör feladata (a §10 handoff ezt kimondottan rögzíti).
- **NOTE-5 — a golden-fixture valós handle-t használ**
  (`e13_r34_screens_golden_test.dart:211–212, 220–221`: `'Wolf Casaba'`,
  `'@wolfcasaba'`), és ez a commitolt PNG-kbe is bekerült. A projekt
  tulajdonosának nyilvános neve, nem titok — a `check_secrets.dart` kapu zöld —,
  de fixture-höz szintetikus név a tisztább.
- **NOTE-6 — a klub-részlet Feed/Challenges tabjainak providerei
  production módban `UnimplementedError`-t dobnak** (E09-R25 óta). A kör nem
  bővítette és nem is bővíthette (`data/` tilos zóna); csak override-olta
  tesztben és goldenben. Átadva.

## 5. Amit a review NEM mért (kimondva)

- a `backend/` oldal (a klub-láthatóság és a `verified`-only projekció
  szerver-oldali kikényszerítése) — kívül esik a diffen;
- a 12 commitolt golden PNG pixelszintű átnézése — a `golden-x86.sh check`
  nulla toleranciájú komparátora és a fixture-forrás olvasása a bizonyíték;
- a `_JoinPromptView` név-`Text`-jén nincs `maxLines`/`overflow`, de a
  `CommunityClub` 60 karakteres domain-plafonja (`community_club.dart:66`,
  valódi `throw`) miatt túlcsordulást nem sikerült előidézni — megjegyzés, nem
  lelet.

## 6. Verdikt

**CHANGES REQUESTED** — 0 BLOCKER, **2 MAJOR**, 1 MINOR, 6 NOTE.

Mindhárom javítandó lelet a kör SAJÁT, még nem merge-elt kódjában van, és
mindhárom pár soros; a javító kör a lánc normál útja (ADR 0087 §2,
user-döntés 2026-07-31). A merge a javító kör + a lelet-zárások leletenkénti
ellenőrzése + egy ÚJ exact-SHA CI-futás után lehetséges.

**Ami ÉRTÉKELENDŐ és nem hígítható a leletek mellett:** a §0.0.B pre-flight
minden mért eltérését (elérhetetlen opt-in kapcsoló, nem létező `pending`
klub-állapot, hiányzó route-mező) az implementer a MÉRT alakban implementálta,
nem a brief régi feltevése szerint; a két kötelező valódi-sértés próbát
ténylegesen lefuttatta és a MÉRT kimenetét írta le; a `textScaler 2.0` keret két
KÖR ELŐTTI `RenderFlex` túlcsordulást fogott meg (805 px a klub-részleten,
54 px az értesítés-AppBaren), és mindkettőt JAVÍTOTTA, nem bázisvonalként
rögzítette (L517); és a 46 beégetett angol klub-konstans mind eltűnt, bájtazonos
ARB↔Dart pár nélkül (L519).

---

## 7. Javító kör — a lelet-zárások ellenőrzése

> A javító kör után ez a szakasz leletenként frissül.
