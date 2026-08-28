# ADR 0472 — Az E2E folyam-mérce a `flutter test` gazdában fut, és a determinizmusát forrás-szintű őr tartja

- **Státusz:** elfogadva
- **Dátum:** 2026-08-28
- **Kör:** `E12-R11` (Chapter 12, Kör 11)
- **Kapcsolódó:** [`0053`](0053-ci-full-test-suite.md),
  [`0276`](0276-practice-presentation-owns-no-resources.md),
  [`0281`](0281-bootstrap-failure-and-in-app-recovery.md)

## Kontextus

Az SDD Chapter 12 Kör 11 „end-to-end test harness"-t ír elő, és a
[`docs/sdd/12-release-roadmap-final-integration.md` §17.1](../sdd/12-release-roadmap-final-integration.md)
`integration_test/` könyvtárat nevez meg. A pre-flightban négy tényt mértünk ki,
amelyek ezt a formát megkérdőjelezik:

1. A `pubspec.yaml` `dev_dependencies` blokkja **ma csak** `flutter_test`-et és
   `flutter_lints ^6.0.0`-t tartalmaz — `integration_test` nincs benne.
2. Ezen a boxon **nincs Android SDK**, a CI-ban pedig nincs emulátoros job: a
   `full-gate.yml` és a `build-apk.yml` egyaránt a
   `.github/actions/flutter-gates` composite-ot futtatja, amiben `flutter test`
   van, `flutter drive`/`integration_test` nincs.
3. A teljes alkalmazás-fa **már pumpolható** `flutter test` gazdában: 20+ cella
   építi a valódi `StrumSightApp`-ot valódi `routerProvider`-rel
   (`test/app/routing/onboarding_first_win_test.dart`,
   `test/app/offline_network_guard_test.dart`, a Ch13 sáv teljes készlete).
4. A `test/support/` **12 fake**-et tartalmaz (audio, auth, settings, engines,
   practice clock/recorder/tick source, preference store, synth,
   baseline-scenariók) — a determinisztikus profil ezekből építhető.

A repó mért igazsága szerint a **nem futtatott mérce rosszabb a hiányzónál**: egy
`integration_test/` csomag olyan zöldet ígérne, amit sem a fejlesztői loop, sem a
merge-kapu nem mér.

## Döntés

**D1 — Az E2E sáv a `test/e2e/` könyvtárban, a `flutter test` gazdában él.** A
cellák a VALÓDI `StrumSightApp`-ot pumpolják valódi routerrel; csak az
eszköz-határon lévő adapterek fake-ek. Az eszköz-szintű `integration_test`
útvonal egy KÉSŐBBI, capability-igazolt kör dolga (a Ch13 device-mátrixa után),
és csak akkor vezethető be, ha ugyanabban a körben CI-job is futtatja.

**NEM elfogadható gyengítés:** az `integration_test` csomag felvétele „majd
később futtatjuk" indoklással. A `pubspec` bővítése a mért win32-pin miatt
önmagában is kockázat (`flutter_secure_storage` v10 / win32 ^6).

**D2 — A hálózat-tiltás GLOBÁLIS, nem csatorna-specifikus.** A guard minden
kimenő utat zár — a Dio `HttpClientAdapter`-t, a `dart:io` `HttpClient`
felülírását (`HttpOverrides`) ÉS a platform-csatornákat
(`TestDefaultBinaryMessengerBinding.defaultBinaryMessenger.setMockMessageHandler`
minden csatornára, nem egy nevesítettre) —, és a próbálkozást **rögzíti**, hogy
a cella pirosra váltson. Az [L453](../LESSONS.md#l453) hibaosztálya (egy
csatorna-specifikus mock handler csak azt az EGY csatornát bizonyítja) normatívan
tiltott.

**D3 — Az óra egyetlen forrás.** A harness-útvonalon `DateTime.now()` és valódi
`Random()` nem maradhat; a fake óra ugyanazt a `now`-t adja a szinkron kódnak és
a stream-listenerben felfegyverzett timernek ([L122](../LESSONS.md#l122)). A
determinizmust NEM egyetlen tiszta predikátum bizonyítja, hanem a folyam
kétszeri, azonos kimenetű futtatása ([L443](../LESSONS.md#l443): a csak
predikátumot hívó „küszöb-cella" a tiltott implementáción is zöld marad).

**D4 — A guard-invariánst forrás-szintű őr is méri.** A „nincs `DateTime.now()` /
`Random()` a harness-fájlokban" állítás statikus cellája a harness FORRÁSÁT
olvassa (`File(...).readAsStringSync()`), nem a viselkedést — mert egy elrejtett
valódi idő a futásból nem feltétlenül látszik, a forrásból viszont igen
([L453](../LESSONS.md#l453) őr-mintája).

**D5 — Termékhiba felfedezése `stopped` jelzés, nem tesztátírás.** Ha egy
vertical slice a valódi fán nem járható végig, a kör kimenete a `stopped` jelzés
és a jelentés. A `lib/**` javítása ebben a körben tilos, és a folyam
„megkerülő" átírása (a UI helyett közvetlen repository-hívás) is az — az utóbbi
pontosan az [L273](../LESSONS.md#l273) hibaosztálya: a lánc egy közbenső
artefaktumot injectál, amit maga nem termel meg.

**D6 — A teardown a fake-async zóna szabályai szerint készül.** Egy broadcast
`StreamController.close()` awaitolása a `testWidgets` fake-clock zónája alatt
SOSEM tér vissza ([L513](../LESSONS.md#l513)); a harness lezárása ezért nem
awaitolhat ilyen Future-t, és a `flutter_animate` függőben maradó
teardown-timere miatt a folyam záró `pump(Duration)`-nel fejeződik be.

## Következmények

- A Kör 11 terméke **bizonyíték**, nem mechanizmus: a `lib/**` fa változatlan
  marad, a diff a `test/**` és a `docs/testing/**` alá esik.
- A `docs/testing/e2e-harness.md` kimondja a HATÁROKAT is: amit ez a sáv NEM
  fed (valódi mikrofon, valódi tárolás, platform-permission dialógus, natív
  plugin-viselkedés, több-eszközös mátrix), az az eszköz-szintű úton marad.
- A meglévő `test/app/offline_network_guard_test.dart` érintetlen és a kör
  `gate_tests` listájában marad — az új guard nem válthatja ki, csak kiegészíti.
- Amit ez az ADR NEM dönt el: hogy MIKOR jön az eszköz-szintű
  `integration_test` sáv, és milyen CI-job futtatja — az a Ch13 device-mátrix
  utáni kör dolga.
