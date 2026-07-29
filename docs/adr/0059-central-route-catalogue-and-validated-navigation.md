# ADR 0059 — Központi route-katalógus és validált navigációs állapot

- **Státusz:** elfogadva (2026-07-29, E01-R11)
- **Kontextus:** SDD Chapter 2, Kör 11; kör-brief `docs/rounds/e01-r11-routing-and-app-shell.md`;
  review `docs/reviews/e01-r11-review.md`
- **Kapcsolódó:** [ADR 0055](0055-agent-role-protocol.md) (ágensszerepek),
  [ADR 0056](0056-exclusive-microphone-session.md) (mic-ownership),
  [ADR 0057](0057-shared-music-domain-and-feature-public-api.md) (`public.dart` contract)

## Kontextus

A router 17 route-ot definiált inline string-literálokkal, a `HomeShell` külön
tab-literállistát tartott, és további 14 hívóhely szórta szét ugyanezeket a
path-okat. A `/library/session` builder `state.extra as AnalyzedSession` castot
végzett — deep linken vagy `extra` nélküli navigáción `TypeError`. A redirect
`ref.read`-del olvasta az onboarding állapotot `refreshListenable` nélkül,
tehát nem reagált az állapotváltozásra: a működést egyedül az tartotta össze,
hogy az onboarding képernyő kézzel navigált. Router-teszt nem létezett.

## Döntés

1. **Egy katalógus.** Minden path `AppRoutes` (`lib/app/routing/app_route.dart`)
   `static const` tagja, a shell tab-sorrendjét is beleértve (`shellTabs`) — a
   router és a `HomeShell` így nem tud szétcsúszni. Path-literál a `lib/` alatt
   máshol nem szerepelhet; `test/tooling/route_literal_guard_test.dart`
   kényszeríti ki.
2. **A guardok tiszta függvények.** `onboardingRedirect({seen, location})`
   `BuildContext` és `Ref` nélkül tesztelhető, és **idempotens**: a saját
   eredményére alkalmazva `null`-t ad — ez zárja ki objektíven a
   redirect-loopot.
3. **Reaktív redirect.** A `GoRouter` `refreshListenable`-t kap, amit a
   `routerProvider` `ref.listen(onboardingSeenProvider, …)`-ból táplál; a router
   és a notifier is `ref.onDispose`-ban szabadul fel. A `redirect` továbbra is
   `ref.read`-et használ — `ref.watch` egy `Provider`-ben újraépítené a routert,
   és eldobná a navigációs stacket.
4. **Validált argumentum, kontrollált helyreállás.** A `/library/session`
   `redirect`-je `extra is! AnalyzedSession` esetén a `/library`-re küld
   (a builder védőhálóként szintén típusellenőrzött); ismeretlen path esetén az
   `onException` a `/live`-ra áll vissza. Sem saját hibaképernyő, sem új
   lokalizált szöveg nem kellett — az SDD a „biztonságos visszairányítást"
   egyenrangú megoldásként engedi.
5. **Az onboarding kilépési útjai unmount-tűrőek.** `_finish()` / `_firstWin()`
   az első `await` ELŐTT elkapja a `GoRouter`/root `Navigator` referenciát, és
   utána nem nyúl `context`-hez, `mounted`-őr nélkül navigál. Ok: a reaktív
   redirect a `complete()` optimista `state = true`-jára azonnal unmountolja a
   `/welcome`-ot, még a perzisztálás alatt — a régi `if (!mounted) return`
   elnyelte volna az aktivációs first-win leckét (r155/r156 útvonal).
6. **A mikrofon-lifecycle mechanizmusa változatlan.** A mikrofont továbbra is a
   `liveFrameProvider` `autoDispose`-a szabadítja fel a Live képernyő
   lekerülésekor; a kör ehhez shell-szintű tesztet adott. Ezért **tilos**
   `StatefulShellRoute`-ra váltani (tabonkénti state-megőrzés életben tartaná a
   Live képernyőt, és a mikrofon nyitva maradna).

## Következmények

- Path átnevezése egy helyen történik; a guard megakadályozza a visszaszivárgást.
- A navigációs viselkedés először tesztelt: első indítás, onboarding-váltás
  `context.go` nélkül, hiányzó/érvényes session-argumentum, ismeretlen path,
  login-pop, provider-dispose, Live→Settings mic-leállás, és a késleltetett
  írású first-win regresszió.
- A `complete()` optimista sorrendje szándékosan megmaradt (`onboarding_provider.dart`
  az R06 storage-contract területe): elbukó írás után a felhasználó nem ragadhat
  be az onboardingba.
- Ismert korlát: a literál-guard ma csak a `context.go|push('/…')` alakot fogja,
  a `router.go('/…')`-t nem (review MINOR-1) — follow-up az E01-R14-ben.

## Alternatívák

- **Named route-ok / `go_router_builder` típusos route-ok** — elutasítva ebben a
  körben: nagyobb felület, és a kör célja a meglévő viselkedés megszilárdítása.
- **Saját error-route képernyő** — elutasítva: új ARB-kulcsokat és UI-t kívánt
  volna, miközben a visszairányítás ugyanazt a biztonságot adja.
- **A `complete()` sorrendjének megfordítása (előbb írás, utána state)** —
  elutasítva: az UI-t egy lemezírás idejére blokkolná, és az R06 contractot
  bontaná meg; a képernyő-oldali unmount-tűrés olcsóbb és lokálisabb.
