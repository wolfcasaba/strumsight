# E13-R33 review — Community profil, feed, keresés és poszt UI

- **Kör:** `E13-R33` (Chapter 13, Kör 33) — UI-53…UI-58, [ADR 0291](../adr/0291-community-is-optional-and-private-by-default.md)
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`)
- **Reviewer:** Claude (orchestrátor), 2026-08-27 — READ-ONLY, izolált klón
  (`/tmp/ss-review-e13-r33`, `HEAD = 43141e8b`)
- **Diff:** `d2c96253..43141e8b` — 41 fájl, +3417 / −468
- **Branch:** `sonnet-impl/e13-r33-community-feed-and-posts`

## 1. Mit mértem (parancsok és TÉNYLEGES kimenet)

### 1.1 Scope-audit — `ok`

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r33 \
  --brief docs/rounds/e13-r33-community-feed-and-posts.md --base 5c2ba004
→ Legacy scope audit OK (5c2ba00475d9..43141e8ba160, 41 changed path(s), 0 generated/ignored)
```

A diff EGYETLEN fájlja sem esik a §4 engedélyezett listáján kívülre. Külön
ellenőrizve: az `application/`, `data/` és `domain/` réteg **érintetlen**, és
az E13-R34-hez tartozó öt képernyő (`clubs/*`,
`community_challenges_screen.dart`, `leaderboard_screen.dart`,
`safety_relationships_screen.dart`, `community_notifications_screen.dart`)
sem szerepel a diffben — a két kör fájlhalmaza diszjunkt maradt.

### 1.2 Kötelező kapu, izolált klónban ÚJRAFUTTATVA — MINDEN ZÖLD

`tools/round-gate.sh` a brief §7 sorával, 15 lépés, csonkítatlan kimenet:

| # | Lépés | Eredmény |
|---|---|---|
| 1 | `format` | ZÖLD (2131 fájl, 0 változott) |
| 2 | `analyze` | ZÖLD |
| 3 | `community_gate_test.dart` | ZÖLD — `+8 All tests passed!` |
| 4 | `composer_audience_test.dart` | ZÖLD — `+9 All tests passed!` |
| 5 | `offline_publish_retry_test.dart` | ZÖLD — `+1 All tests passed!` |
| 6 | `block_mute_test.dart` | ZÖLD — `+2 All tests passed!` |
| 7 | `test/features/community/presentation/` | ZÖLD — `+82 All tests passed!` |
| 8 | `ui_inventory_test.dart` | ZÖLD — `+1` |
| 9 | `architecture_dependency_test.dart` | ZÖLD — `+44` |
| 10–12 | `dio_factory` / `preferences_plugin` / `route_literal` őrök | ZÖLD |
| 13 | `architecture` | ZÖLD |
| 14 | `secrets` | ZÖLD |
| 15 | `l10n` | ZÖLD |

→ `MINDEN GATE ZÖLD.`

### 1.3 Golden az x86-os (CI-vel AZONOS) architektúrán — 16/16 ZÖLD

```
tools/golden-x86.sh check test/ui/goldens/e13_r33_screens_golden_test.dart
→ 01:26 +16: All tests passed!   (GOLDEN_EXIT=0)
```

Nyolc képernyő × két keret (412×915 compact portrait és ugyanaz
`textScaleFactor: 2.0`), a PNG-k commitolva. A brief §0.0.B/B11 szerint a
golden-útvonal NEM része a lokális ARM `gate_tests`-nek — ez a futás a
kötelező x86-os pár.

### 1.4 CI, exact-SHA

| Workflow | Run | headSha | Eredmény |
|---|---|---|---|
| `router-ci.yml` | 33072012141 | `43141e8b` | **success** |
| `full-gate.yml` | 33072017326 | `43141e8b` | lásd §4 |

A tervezőt futtattam, nem magamtól döntöttem:
`tools/round-ci-plan.py` → `dispatch: ["full-gate.yml"]`, `apk_required: false`
(„a diff nem érint natív/release-útvonalat"), `router_ci_expected: true`
(`docs/rounds/**` érintve).

### 1.5 Valódi-sértés próbák — HÁROM, mind ELDOBHATÓ, mind PIROSRA váltott

A zöld gate önmagában nem bizonyíték; a cellák falszifikálhatóságát külön
mértem az izolált klónban, majd minden változtatást visszaállítottam
(`git status --short` → üres).

| # | Beültetett hiba | Mit vártam | MÉRT eredmény |
|---|---|---|---|
| P1 | alapértelmezett közönség `followers` → **`public`** (composer ÉS profil) | **A2** piros | **5 cella piros**: A2 composer, A2 profil, és a §6.1 mátrix mindhárom cellája |
| P2 | a tiltás/némítás helyi eltávolítása az `await` **UTÁNRA** kerül | **A5** piros | **2 cella piros** (block + mute) |
| P3 | a szerkesztő **ÚJ** idempotencia-kulcsot mint minden mentésnél | **A6** piros | **1 cella piros** — `Expected: <2> Actual: <3>` (a duplikált függő rekord) |

A három őr tehát valódi, nem tautológia.

### 1.6 Biztonsági review (KÖTELEZŐ — `risk = "high"`, §7 review-megjegyzés)

A `security-reviewer` ügynök lefutott a diffen; a leletei közül a
döntéshordozókat SAJÁT méréssel is ellenőriztem (nem bemondásra):

| Pont | Verdikt | Az általam is MÉRT bizonyíték |
|---|---|---|
| Prompt-injection / értelmező sink | PASS | `grep -rn "Uri.parse\|launchUrl\|WebView\|Markdown\|Html"` a `presentation/`-en → 0; idegen szöveg markup-inert `Text()`-en át rendel |
| ADR 0291 §2 — alapérték nem nyilvános | PASS | `application/`+`domain/` érintetlen → a mért `followers` áll; a `public` választás megerősítés mögött |
| ADR 0291 §3 — nyers gyakorlási adat | PASS | `SharePreview` öt opt-in mezője változatlan, nyers-hang mező nincs bevezetve |
| ADR 0291 §5 — kulcs a transzportban | PASS | `grep idempotencyKey` a listás képernyőkön → csak repository-hívás argumentumaként (`followers_screen.dart:132,137,142`), `Text`/`Semantics` alatt SEHOL |
| ADR 0291 §4 — azonnali helyi tiltás | PASS | `followers_screen.dart:145` — `setState(removeWhere)` az `await` ELŐTT, a hálózati hívás `on AppFailure` best-effort ágon |
| Adatszivárgás / analytics | PASS | nincs `debugPrint`/analytics a scope-ban; a hibanézetek `AppFailure.toString()`-je csak `runtimeType + code + retryable` |
| Új hálózat/tárolás/engedély import | PASS | `git diff \| grep '^+import'` → egyetlen `dio` / `shared_preferences` / `permission_handler` / `url_launcher` sem |

Az ügynök két NOTE-ot adott (tranziens relationship-kulcs a felületi rétegben;
`AppFailure.toString()` renderelése) — egyik sem blokkol, mindkettőt lentebb
NOTE-ként rögzítem.

## 2. Leletek

### MAJOR-1 — az A2 megerősítő lap a szerkesztőben BEÉGETETT MAGYAR szöveget rendel, pedig a kör MAGA vette fel ugyanezt ARB-kulcsként

**Fájl:** `lib/features/community/presentation/screens/post_composer_screen.dart:78–84`,
használva `:349–352`.

**A mért ellentmondás.** Ez a kör négy ÚJ ARB-kulcsot vett fel
(`communityPublicConfirmTitle/Body/Cta/Cancel`) mind az `en`, mind a `hu`
fragmentumba, és a **testvér-képernyőn HELYESEN használja is** őket:

```
grep -n "communityPublicConfirm" lib/features/community/presentation/screens/edit_profile_screen.dart
345:      title: l.communityPublicConfirmTitle,
346:      consequence: l.communityPublicConfirmBody,
347:      confirmLabel: l.communityPublicConfirmCta,
348:      cancelLabel: l.communityPublicConfirmCancel,
```

A szerkesztő oldalon viszont ugyanaz a kör ÚJ, beégetett magyar konstansokat
adott hozzá — és ezek a `community_hu.arb`-ba felvett értékekkel
**bájtra azonosak**:

| `post_composer_screen.dart:78–84` | `community_hu.arb:283–292` |
|---|---|
| `'Nyilvánossá teszed?'` | `"communityPublicConfirmTitle": "Nyilvánossá teszed?"` |
| `'Ezt bárki látni fogja, nem csak a követőid. …'` | `"communityPublicConfirmBody": "Ezt bárki látni fogja, nem csak a követőid. …"` |
| `'Nyilvánossá tétel'` | `"communityPublicConfirmCta": "Nyilvánossá tétel"` |
| `'Mégse'` | `"communityPublicConfirmCancel": "Mégse"` |

**A felhasználót érintő hiba.** Egy **angol nyelvre állított** felhasználó a kör
LEGNAGYOBB következményű műveleténél — a visszavonhatatlan nyilvánossá tétel
megerősítésénél — magyar szöveget kap:

> „Nyilvánossá teszed? — Ezt bárki látni fogja, nem csak a követőid. …"

miközben a helyes angol szöveg már ott van a fán
(`community_en.arb`: *„Make this public? — Everyone will be able to see this,
not just people who follow you…"*), csak nincs bekötve. Ez a
`CLAUDE.md` kimondott konvenciójába ütközik („every user-facing string goes
through ARB → `AppLocalizations`"), és pontosan a §9 első kockázatát
(félrekattintásból visszavonhatatlan megosztás) élezi: a megerősítő lap
akkor véd, ha a felhasználó ÉRTI.

**Miért nem előzmény-hiba.** A `_ComposerLabels` osztály többi konstansa
valóban örökség (E09-R12), és a fájl doc-commentje ezt meg is indokolja:

> *„ARB entries for the composer live in a future round's scope — the Kör 12
> allowed-paths covers the screen file only; touching `lib/l10n/**` would be a
> scope violation."*

Ez az indoklás ebben a körben **már nem igaz**: a `lib/l10n/features/community_*.arb`
a §4 engedélyezett listáján VAN, a kör használta is, és a testvérfájlban a
helyes mintát alkalmazta. A négy ÚJ konstans tehát nem örökség, hanem a kör
saját, elkerülhető regressziója — a doc-comment fenti mondata pedig
félrevezetővé vált.

**Javítás (a kör saját listáján belül, 4 sor + a konstansok törlése).** A
`:349–352` hívás olvassa az `AppLocalizations`-t, ahogy az
`edit_profile_screen.dart:345–348` teszi, és a négy `publicConfirm*` konstans
kerüljön ki a `_ComposerLabels`-ből. A doc-comment idézett mondata frissüljön a
kör tényleges scope-jára. A `composer_audience_test.dart` §6.1 „fölötte"
cellája kapjon egy ÚJ állítást, amely a lapot **`AppLocalizations`-ból** vett
felirattal keresi meg (az `en` és a `hu` érték eltér, tehát a cella
falszifikálja a beégetést).

### MINOR-1 — a `_ComposerLabels` maradék örökség-konstansai és hat további beégetett angol felirat

**Fájlok:** `post_composer_screen.dart:60–76` (17 magyar konstans, örökség),
valamint a kör által ÁTÍRT, de beégetve hagyott angol feliratok:
`bookmarks_screen.dart` (`'Retry'`, `'Clear all'`), `comments_screen.dart`
(`'Retry'`), `followers_screen.dart` (`'Followers'`/`'Following'`,
`'Edit profile'`), `community_media_player.dart` (`'Play'`).

**Mérve, hogy ez NEM regresszió:** mind a hat felirat a kör ELŐTT is beégetve
állt — a diff csak a widget-típust cserélte (`const Text('Retry')` →
`SsButton(label: 'Retry')`):

```
git diff d2c96253 43141e8b -- lib/features/community/presentation/ | grep -E "^[-+].*'Retry'"
-            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
+              label: 'Retry',
```

Ezért **nem** MAJOR: a kör nem rontott. De a MAJOR-1 javításakor ezek a sorok
amúgy is a kéz alatt vannak, és a `community_*.arb` a listán van — a
migrálásuk olcsó, és megszünteti a képernyőnként vegyes nyelvű felületet.
Ha a javító kör mégis kihagyja, azt a §10-ben MONDJA KI, ne csendben.

### NOTE-1 — tranziens relationship-kulcs a felületi rétegben

`followers_screen.dart:156` — `'fw-${DateTime.now().microsecondsSinceEpoch}'`.
NEM sérti az ADR 0291 §5-öt: az a poszt/komment-outbox útra vonatkozik (a kulcs
ott a `PostComposerController`-ben él, a diff nem érintette), a block/mute
szerver-oldalon idempotens, a sor azonnal eltűnik, és a minta megegyezik a fán
már élő testvérképernyőkkel. Ha a relationship-akciók valaha offline sorba
kerülnének, a kulcsot a repository/outbox rétegbe kell emelni.

### NOTE-2 — `AppFailure.toString()` a hibanézetekben

`bookmarks_screen.dart:394` és társai. Ma ártalmatlan: az
`AppFailure.toString()` (`core/foundation/app_failure.dart:128`) csak
`runtimeType + code + retryable` — nincs benne felhasználói tartalom vagy
titok. Rögzítve arra az esetre, ha egy jövőbeli `AppFailure` altípus szabad
szöveget vinne a `code`-ba.

### NOTE-3 — mért mellékhatásként javított túlcsordulás

A golden-felvétel 412 px-en `RenderFlex overflowed by 151 pixels`-t adott a
`following_feed_screen.dart` `_EndOfFeed` sorára — a kör ELŐTT is jelen volt,
csak eddig nem futott ilyen kereten. A kör javította (`Flexible`). Ez pontosan
az **A9** mérce-mátrix „a képernyő elcsúszik, túlcsordul" sora: a cella
megfogta, amiért felvették.

## 3. Az acceptance-cellák ellenőrzése leletenként

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | a mag közösség nélkül teljes | `community_gate_test.dart` (2 cella) | ZÖLD |
| A2 | az alapértelmezett közönség nem nyilvános | `composer_audience_test.dart` (2+3 cella); **P1 próba: 5 cella pirosra vált** | ZÖLD (a felirat-nyelv a MAJOR-1) |
| A3 | a gyakorlás-megosztás tételesen mutatja, mi kerül ki | `composer_audience_test.dart` — az öt `SharePreview` mező | ZÖLD |
| A4 | a nyers hang alapból nem része a megosztásnak | ugyanott, strukturális absztinencia-cella | ZÖLD |
| A5 | a tiltás/némítás azonnal, helyben hat | `block_mute_test.dart`; **P2 próba: 2 cella pirosra vált** | ZÖLD |
| A6 | az újrapróbálkozás nem duplikál | `offline_publish_retry_test.dart`; **P3 próba: pirosra vált** | ZÖLD |
| A7 | az eltávolított tartalom helyőrzőt kap | `community_gate_test.dart` (3 cella: FeedCard ×2 + CommentsScreen) | ZÖLD |
| A8 | a felhasználónév-validáció nem enged tovább hibás bevitelt | `community_gate_test.dart` (3 cella) | ZÖLD |
| A9 | golden-felvétel mindkét kereten, commitolva | `golden-x86.sh check` → 16/16, a PNG-k a diffben | ZÖLD |

A hét MEGLÉVŐ `presentation/`-teszt (§0.0.B/B3) gyengítés nélkül fut: a
`test/features/community/presentation/` futás `+82` zöld cellát adott, és a
diffben egyetlen `skip` vagy törölt állítás sincs — csak a
`report_content_sheet_test.dart` két `FilledButton` → `SsButton` exact-cast
sora frissült, mert a `Key` magán az `SsButton`-on ül.

## 4. VÉGSŐ DÖNTÉS — 1. kör

**CHANGES REQUESTED** — egy nyitott **MAJOR** (MAJOR-1) és egy **MINOR**
(MINOR-1). A javító kör a lánc normál útja (user-döntés 2026-07-31), ugyanaz a
motor, a fenti leletlistával.

Minden más mérce zöld: scope-audit `ok`, a 15 lépéses kapu zöld, a golden
x86-on 16/16, a Router CI a merge SHA-n `success`, és a három eldobható
falszifikációs próba mind pirosra váltotta a saját celláját.

## 5. VÉGSŐ DÖNTÉS — 2. kör (a javítás után)

*(a javító kör után töltendő)*
