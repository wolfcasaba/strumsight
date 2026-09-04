# E16-R05 review — A teljes app működésének mérése és kiadható build

- **Kör:** `E16-R05` (Chapter 16, Kör 5 — a sáv ZÁRÓ köre)
- **Ág / HEAD:** `sonnet-impl/e16-r05-full-app-verification-and-release` @ `696d0149`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5), orchesztrátor-szék, READ-ONLY
- **Bázis:** `d8ed9726` (a kör pre-flight commitja)
- **Dátum:** 2026-09-04

## 0. Mit mértem magam (nem bemondásra)

| Mérés | Eredmény |
|---|---|
| Scope-audit (`tools/scope-audit.py --base d8ed9726`) | **OK** — 6 megváltozott útvonal, mind az `allowed_paths`-on |
| Független gate izolált klónban (`/tmp/ss-review-e16-r05`, `696d0149`) | l. §1 |
| L1 lelet forrásellenőrzés (`practice_area_hub_screen.dart:55`) | **IGAZOLT** — `onPressed: () => context.go(AppRoutes.practiceSetup)`, `?id=` nélkül |
| L2 lelet forrásellenőrzés (`onboarding_screen.dart:106`) | **IGAZOLT** — `(widget.onDone ?? () => router!.go(AppRoutes.live))()` |
| P3 kivétel forrásellenőrzés (`progress_providers.dart:34`) | **IGAZOLT** — `const bool progressV2IsOffline = false;`, saját doc-commentben indokolt |
| A4 partíció számtan | 9 bejárt + 64 kimaradó = 73 = a mért elérhető halmaz |

## 1. Verdikt

**CHANGES REQUESTED** — 0 BLOCKER / **1 MAJOR** / 2 MINOR / 1 NOTE.

A kör mérnöki tartalma erős és őszinte: a mérő nem vákuum (valódi
kivétel-bejegyzés + fixture-tesztek P1/P2/P3-ra + fail-closed üres
fájlhalmazra), a bejárás a SZÁLLÍTOTT `forEnvironment(development)`
flag-készlettel fut, a bejárt halmaz a futásból származik, és a kör öt valós
bekötési hiányosságot **rögzített, nem elrejtett**. A MAJOR nem kód-, hanem
**verdikt-hiba**: a kör az A3 cellát teljesítettként jelenti, miközben a SAJÁT
mérése cáfolja.

## 2. MAJOR-1 — az A3 („a core utak végigjárhatók") teljesítettként van jelentve, miközben a kör saját mérése két helyen cáfolja

**Mit mértem.** A `full_app_walkthrough_test.dart` a bejárás gerincén KÉT
teszt-oldali navigációval hidalja át a termék saját navigációs hiányát:

| Hely | A teszt lépése | Miért kellett |
|---|---|---|
| `full_app_walkthrough_test.dart:106` | `session.router.go(AppRoutes.today)` | **L2** — az onboarding Skip-je a termékben `/live`-ra (redirect után `/practice/live`-ra) fejez be, sosem `/today`-ra (`onboarding_screen.dart:106`) |
| `full_app_walkthrough_test.dart:168–170` | `router.go(practiceHub)` + `router.go('${AppRoutes.practiceSetup}?id=…')` | **L1** — a shell EGYETLEN hirdetett belépési pontja pontozott gyakorlásba `?id=` nélkül navigál (`practice_area_hub_screen.dart:55`), a Setup a `_RouteError` ágát rendereli |

A második híd URL-alakját a kód-komment „real, supported navigation, not a
test-only shortcut"-ként indokolja, mert a **legacy** `PracticeHubScreen`
`_openSetup`-ja ilyen URI-t épít. Ez a mentség ebben a build-konfigurációban
**nem áll meg**: `adaptiveShellEnabled = true` mellett a `/practice` a
`PracticeAreaHubScreen`-t építi (`app_router.dart:541`), a legacy Hub
(`app_router.dart:394`) a `!adaptiveShellEnabled` ágon él — tehát a BE-készlet
alatt **egyetlen elérhető képernyő sem állítja elő** ezt az URI-t. A tapintható
úton a pontozott gyakorlás mérhetően nem érhető el.

**Miért MAJOR.** Ez pontosan az [ADR 0470](../adr/0470-practice-setup-navigates-to-the-session-route.md)
/ [L273](../LESSONS.md#l273) hibaosztálya, amivel az `E12-R11` review **H2**-vel
állította meg a láncot: *„a vertical slice a szállított appban nem volt
végigjárható, ezért az implementer a hiányzó lánc-lépést a TESZTBEN pótolta."*
A különbség — és ezért nem BLOCKER — hogy ez a kör a hiányt **kimérte és
dokumentálta** (L1, L2), nem elrejtette. A hiba tehát nem a mérésben, hanem a
**jelentett verdiktben** van: a §6 A3 cellája és a `full-app-verification.md`
összegzése úgy olvasható, mintha a core út végigjárható lenne.

**Amit a kör tényleg bizonyított** (és amit a dokumentumnak ki kell mondania):
a core út állomásai a szállított BE-flagkészlettel **oda navigálva** valós
adatot vagy explicit állapotot mutatnak (A2 ✅), és a mért elérhető halmaz
partíciója teljes (A4 ✅) — de a **termék saját navigációja** a gerincen két
ponton megszakad, tehát **A3 = NEM TELJESÜL**.

**A javítás doc-only, az `allowed_paths`-on belül** (a `lib/**` tiltott zóna
marad, §5.2 — a bekötést NEM javítjuk itt):

1. `docs/release/full-app-verification.md`: a §2 bevezetője mondja ki, hogy a
   bejárás a gerincen két teszt-oldali navigációt használ, és sorolja fel,
   melyik lelet miatt; a dokumentum kapjon egy kimondott
   **„A3 — NEM teljesül"** sort a mért indokkal.
2. `docs/rounds/e16-r05-…md` §6: az A3 sor kapjon `**NEM teljesül**`
   megjelölést az L1/L2 hivatkozással (a cellát nem töröljük és nem írjuk át —
   a mérce marad, a mért eredmény negatív).
3. A §10 handoff és a §4 nyitott tételek tükrözzék ugyanezt.

## 3. MINOR-1 — a §4 „Nyitott tételek" tábla `Kör` oszlopa csupasz `nincs`, indoklás nélkül

A §3.2 kimaradó tábláját az A5 gépi őre a `nincs — <indok>` alakra kényszeríti
(`placeholder_wiring_test.dart:72–74`), a §4 összefoglaló tábla öt sora viszont
csak `nincs`-et ír, miközben az L1–L5 szakaszok törzse tartalmazza az indokot.
Ugyanaz a dokumentum két mércét használ ugyanarra a mezőre. **Javítás:** a §4
`Kör` cellái vegyék át a szakaszok `nincs — <indok>` alakját.

## 4. MINOR-2 — a Profile Hub „sessions" cellája bármelyik `0`-ra illeszkedik

`full_app_walkthrough_test.dart:336–345` a `find.descendant(of:
ProfileHubScreen, matching: find.text('$v1SessionCount'))` alakot használja.
A mért érték ezen a bejáráson `0`, és a képernyőn a **streak** csempe is `0`-t
renderel (`profile_hub_screen.dart:48–58`: két `_Metric`, `streak.current` és
`stats.totalSessions`) — a cella tehát akkor is zöld, ha a sessions-metrika
egyáltalán nem renderelődik. Ez a §5.1 („a cella az ADATOT állítja") gyengébb
olvasata.

**Javítás (a teszt az `allowed_paths`-on van):** kösd a cellát a metrika
feliratához — pl. a `l10n.progressSessions` szövegtől felfelé a közös
`Column`-ig, majd abban keresd az értéket —, hogy a streak csempéje ne
elégíthesse ki. Ha a widget-fa ezt nem engedi pontosan, a teszt-komment
mondja ki a korlátot.

## 5. NOTE-1 — az L3 harness-eredetű, és ezt a §2 bevezetője elmossa

Az L3 (`UnifiedLibraryScreen` → `libraryV2LoadFailed`) **nem** termékhiba: a
három repository-t a production bootstrap köti be, a `bootE2eApp` pedig
szándékosan nem futtat bootstrapot (E12-R11, ADR 0472). Az L3 szakasz ezt
korrektül leírja és a gazdát „Library V2 feature / **E12-R11 harness**"-ként
nevezi meg — a §2 bevezetője viszont mind az öt leletet egy kalap alatt
„bekötési hiányosság"-ként vezeti fel. Egy kiadás-igazoló dokumentumban érdemes
kimondani, hogy a Library-állomás a szállított kompozícióról **semmit nem
bizonyít**, mert a mérés a harness határán akadt el. (Nem blokkoló: a
részletező szakasz pontos.)

## 6. Amit ellenőriztem és RENDBEN találtam

- **A mérő nem vákuum.** `placeholder_wiring_test.dart` négy fixture-cellája
  külön-külön bizonyítja, hogy a P1/P2/P3 szabály tényleg jelez, és hogy egy
  lokális változó NEM lelet; az A8 üres-fixture cellája a fail-closed ágat
  méri. Ez pontosan az [L606](../LESSONS.md#l606) hibaosztálya ellen szól.
- **A7 valódi kivétel-listát mér.** A lista egyetlen eleme
  (`progressV2IsOffline`) forrásból igazolt, az indoka a forrás saját
  doc-commentje — nem a mérce puhítása.
- **A4 a futásból jön.** A `runCoreWalkthrough` a `walked` halmazt csak azután
  bővíti, hogy a megfelelő `expect(find.byType(...))` lefutott, és a
  `placeholder_wiring_test.dart` A4 cellája ÚJRA lefuttatja a bejárást, majd
  a mért `ScreenReachability` eredménnyel veti össze — nincs kézzel másolt
  lista.
- **A5 saját piros-próbával jön.** A „blanking one real row's Gazda" cella a
  `screen_reachability_test.dart` bevett mintáját alkalmazza.
- **A9 igazolt.** A négy örökölt harness-hívó fájlja érintetlen
  (`git diff --stat`: csak a hat engedélyezett útvonal), és mind a négy zölden
  fut a független gate-emben.
- **A partíció számtana stimmel:** 9 + 64 = 73 = mért elérhető halmaz; a
  bejárt és kimaradó halmaz diszjunkt (gépileg állítva).
- **Az §6.1 KÖTELEZŐ valódi-sértés próba** mindkét lépése dokumentálva van,
  szó szerinti PIROS kimenettel (§10.4), és a fa a próba után tiszta volt.

## 7. A független gate (izolált klón, `696d0149`)

`/tmp/ss-review-e16-r05`, friss `prepare-flutter-generated.sh` után, a brief §7
nyolc útvonalával. **`GATE_EXIT=0`, 13/13 lépés zöld** — az implementer §10.5
jelentése reprodukálva, nem bemondásra elfogadva:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/e2e/full_app_walkthrough_test.dart               zöld
    test test/tooling/placeholder_wiring_test.dart             zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/e2e/first_practice_offline_test.dart             zöld
    test test/e2e/returning_user_restart_test.dart             zöld
    test test/accessibility/release_flow_semantics_test.dart   zöld
    test test/accessibility/release_flow_text_scale_test.dart  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A zöld gate azonban **nem** oldja fel a MAJOR-1-et: az A3 cellát egyetlen
gépi mérce sem állítja — a bejárás a két teszt-oldali hidat használva zöld,
tehát a „végigjárható" állítás a dokumentumban él, nem a kódban.

## 8. Zárás

A MAJOR-1 javítása után (mind a három MINOR/NOTE ponttal együtt, doc- és
teszt-oldalon, `lib/**` érintése NÉLKÜL) a kör merge-elhető, feltéve, hogy a
teljes CI-kapu (`build-apk.yml` + `router-ci.yml`) a merge SHA-n zöld.
