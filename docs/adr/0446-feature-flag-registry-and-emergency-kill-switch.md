# ADR 0446 — Feature flag katalógus, aszimmetrikus vészkapcsoló és gépi teljesség-audit

- **Státusz:** Elfogadva (E12-R05 pre-flight, 2026-08-28)
- **Kör:** `E12-R05` — Feature flag registry és emergency kill switch
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Epic / fejezet:** [Chapter 12 — Release Roadmap, Sprint Planning & Final
  Integration](../sdd/12-release-roadmap-final-integration.md) Kör 5
- **Az ADR-t az orchestrátor (Claude Opus 5) írta a pre-flightban**, a
  [`docs/rounds/e12-r05-feature-flag-registry-and-kill-switch.md`](../rounds/e12-r05-feature-flag-registry-and-kill-switch.md)
  brief §5 kötött döntéseinek normatív forrásaként.
- **Kontext-ADR-ek:**
  [0395](0395-community-baseline-feature-flags-and-threat-model-scope.md) (a
  kill switch MA is operábilis: a dart-define/env mindig felülírható, a
  hardcode-false lezárás külön GOV-kör dolga),
  [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md) (a hardcode-false
  lezárás precedense),
  [0443](0443-sdd-index-machine-checkable-contract.md) (a gépi, tesztelhető
  ellenőrző-eszköz mintája: root-paraméteres függvények + vékony `main()`).

## Kontextus — a MÉRT állapot

A pre-flight mérése (`main @ 86d08ad6`, 2026-08-28):

```
lib/app/config/feature_flags.dart : 451 sor, final class FeatureFlags
                                    37 `final bool` mező
                                      = 3 kötelező (accountEnabled,
                                          diagnosticsEnabled, labModeAvailable)
                                      + 34 `= false` alapértelmezésű
                                    5 × bool.fromEnvironment a forEnvironment
                                      factoryban
                                    metaadat (owner, lejárat, kockázat): NINCS
lib/core/feature_flags/           : NEM létezik
tool/check_feature_flags.dart     : NEM létezik
test/app/config/feature_flags_test.dart : 219 sor  (regresszió-őr)
test/app/feature_flags_test.dart        : 339 sor  (regresszió-őr)
backend/app/config.py             : 5 × community_* flag, False alapértelmezés
tool/check_architecture.dart:332  : lib/core/** NEM importálhat lib/features/**
tool/gen_public_barrel.dart       : csak lib/features/<f>/public/ fragmentekből
                                    generál barrelt — lib/core/**/public.dart
                                    kézzel írt (precedens:
                                    lib/core/design_system/public.dart)
```

A mért hibaosztály, amit ez az ADR zár: **a metaadat nélküli flag-mező**. Ma 37
kapcsoló dönt arról, hogy egy build hálózatot használ-e
(`usesNetwork => accountEnabled || diagnosticsEnabled`), elérhető-e a
Lab-diagnosztika, be van-e kapcsolva a Vision kamerafelület vagy a Community
írás — és **egyikhez sincs leírva, hogy kié, meddig él, és hogyan kell
vészhelyzetben kikapcsolni**. Egy incidens alatt a kikapcsolás útja ma
kódolvasásból derül ki, a „melyik flag maradt bent lejárat után" kérdésre pedig
nincs mérés.

Ez az ADR **nem cseréli le** a meglévő compile-time mechanizmust (ADR 0395
hatálya változatlan): a katalógus a MEGLÉVŐ mezőkre hivatkozik, és
`lib/app/config/feature_flags.dart` ebben a körben nem módosul.

## Döntés

### D1 — A vészkapcsoló ASZIMMETRIKUS: kizárólag kikapcsolni tud

A prioritási lánc legerősebb forrása (`emergency`) csak `false` értéket
érvényesíthet. Az emergency forrás `true` értéke **figyelmen kívül marad** — nem
kapcsol be semmit, és nem is hiba.

**Indok:** a vészcsatorna a legkevésbé védett bemenet (incidens alatt, sietve,
gyakran külső hordozón érkezik). Ha szimmetrikus lenne, egy kompromittált vagy
elrontott vészcsatorna **capabilityt kapcsolna be** — épp azt, amit ki kellene
kapcsolnia.

**NEM elfogadható gyengítés:** „az emergency a legerősebb forrás, tehát be is
kapcsolhat"; illetve a `true` értékre dobott kivétel (a vészcsatorna hibás
bemenetre sem állíthatja meg az alkalmazást).

### D2 — A feloldás prioritási sorrendje fail-closed

A sorrend az erősebbtől a gyengébbig:

| # | Forrás | Mit tehet |
|---|---|---|
| 1 | `emergency` | **csak kikapcsol** (D1) |
| 2 | `remote` (aláírt) | be- és kikapcsol, **kizárólag érvényes aláírással** |
| 3 | `capability` | be- és kikapcsol (eszköz-/platformképesség) |
| 4 | `local` / `define` | be- és kikapcsol (a mai `bool.fromEnvironment` út) |
| — | *nincs forrás* | a definíció `failClosedDefault` értéke |

Az egyik forrás hiánya, ismeretlen kulcsa vagy hibás értéke **nem** ad
átcsordulást az „utolsó ismert értékre": a lánc a következő gyengébb forrásra
lép, és ha egyik sem szolgáltat értéket, a definíció fail-closed alapértéke
nyer.

Az **aláírás-ellenőrzésen bukó** remote forrás értékei **figyelmen kívül
maradnak** (a lánc úgy folytatódik, mintha a forrás nem is válaszolt volna), és
a bukás **nem fatális**: nem dob, nem állítja meg az appot.

**NEM elfogadható gyengítés:** cache-elt „utolsó ismert érték" felhasználása
hiányzó forrás esetén; a bukott aláírású payload értékeinek részleges
elfogadása; a bukott aláírásra dobott kivétel.

### D3 — A remote forrás ebben a körben INTERFÉSZ, nem hálózat

A `remote(signed)` fokot a kör kizárólag interfész-szinten vezeti be: a
prioritás és a fail-closed viselkedés **fake forrásokkal** mérhető. Tényleges
hálózati csatorna vagy kriptográfiai aláírás-ellenőrzés implementációja NEM
része a körnek — az a rollout-körök (SDD Ch12 Kör 30/31) dolga, és önálló
threat-model-kiegészítést kíván.

**Indok:** hálózati flag-csatorna bevezetése új támadási felület; enélkül is
mérhető, hogy a feloldás helyes-e.

### D4 — A katalógus TELJESSÉGE gépi állítás, a kötés string-kulcsú

A `tool/check_feature_flags.dart` a `lib/app/config/feature_flags.dart`
**forrását** olvassa, kigyűjti a `final bool <név>;` mezőneveket, és minden
mezőhöz katalógus-bejegyzést követel. Katalógusból hiányzó, de a kódban létező
mező → **nem-nulla kilépési kód**.

Az eszköz a [ADR 0443](0443-sdd-index-machine-checkable-contract.md) mintáját
követi: a logika **nem** a `main()`-ben él, hanem root- és tartalom-paraméteres,
tesztből hívható függvényekben; a `main()` vékony, `exitCode`-ot állító burkoló.
A `test/tooling/feature_flag_audit_test.dart` relatív importtal
(`../../tool/check_feature_flags.dart`) hívja — ez a `test/tooling/**` mért,
egységes mintája (`check_sdd_index`, `check_secrets`, `check_assets`,
`gen_public_barrel`).

### D5 — A katalógus NEM importálja a `FeatureFlags` típust

A `lib/core/feature_flags/` réteg tisztán string-kulcsú: a bejegyzés a flag
**nevét** hordozza, nem a mezőre mutató referenciát, és a kötést a D4 gépi
audit teremti meg.

**Indok (mérve):** `lib/app/config/feature_flags.dart` importálja a
`lib/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart`-ot. Ha
a katalógus importálná a `FeatureFlags`-et, a `lib/core/` réteg tranzitívan egy
feature-domain típustól függene — a `check_architecture.dart:332`
`coreMustNotImportFeatures` szabálya a közvetlen élt nem tiltaná, de a réteg
függetlensége elveszne. A string-kulcs mellett a katalógus framework- és
feature-független marad, és a teljesség így is **gépi** (D4), nem kézi.

**NEM elfogadható gyengítés:** kézzel karbantartott, gépi teljesség-ellenőrzés
nélküli lista — az első új flag után hazudik.

### D6 — A lejárat határa INKLUZÍV, és a mért „ma" INJEKTÁLT

Egy flag a `expiresOn` napján **még érvényes**; a rákövetkező naptól lejárt.
A lejárat-vizsgáló függvény a „mai napot" **paraméterként** kapja
(`DateTime now`), nem `DateTime.now()`-ot hív.

**Indok:** a küszöb-cellahármas (tegnap → PIROS, ma → ZÖLD, holnap → ZÖLD)
csak injektált idővel determinisztikus; valós órával a cellák naptárfüggők és
éjfél körül flakyk lennének.

Az `expiresOn` **opcionális**: `null` = tartós capability-kapcsoló (pl.
`accountEnabled`, `diagnosticsEnabled`, `labModeAvailable`), ami nem jár le.
Lejárat csak ott áll, ahol az SDD a rollout végét ténylegesen dátumozza.

**A valós katalógusnak zöldnek kell lennie:** `dart run
tool/check_feature_flags.dart` a szállított fán **0** kóddal lép ki. Az A5
piros esetét **kézzel épített fixture** katalógus adja, nem a valós bejegyzés
lejáratra állítása.

### D7 — A kill switch NEM töröl adatot

Egy capability kikapcsolása **elrejti** a felületet; a felhasználó adatai
(felvételek, gyakorlás-előzmény, community tartalom) érintetlenek maradnak, és
visszakapcsoláskor ismét elérhetők.

**Indok:** a vészkapcsoló incidens-eszköz, nem adatkezelési döntés. Ha
takarítana, egy téves kikapcsolás visszafordíthatatlan adatvesztés lenne — és a
kikapcsolás gyakran épp azért történik, hogy az adat SÉRTETLEN maradjon a
vizsgálatig.

**NEM elfogadható gyengítés:** „takarítás" vagy cache-ürítés a kikapcsoláskor.

## Következmények

- Minden kockázatos capability egyetlen, típusos katalógusban van leírva —
  owner, kockázati szint, fail-closed alapérték, kill-switch-út, hivatkozott
  ADR, opcionális lejárat.
- Egy új flag felvétele a `FeatureFlags`-be **gépi hibává** válik, amíg a
  katalógus-bejegyzés hiányzik (D4).
- Az incidens-válasz útja dokumentált: `docs/release/kill-switches.md`.
- A `tools/round-gate.sh` **nem** bővül a `check_feature_flags.dart`-tal ebben
  a körben (a gate a mérce, és a mércét nem az módosítja, akit mér — a
  bekötése külön, governance-jellegű kör dolga).
- A `lib/app/config/feature_flags.dart` és a két meglévő regresszió-teszt
  (558 sor együtt) **változatlan** marad.

## Elutasított alternatívák

1. **A `FeatureFlags` mezőinek átírása metaadatot hordozó típusra.** Ez 37
   mező minden hívóhelyét érintené, és a két meglévő regresszió-tesztet
   átírásra kényszerítené — az [L478](../LESSONS.md) mért hibaosztálya. A
   katalógus emiatt a mezők MELLÉ kerül, nem helyettük.
2. **Szimmetrikus emergency forrás.** Lásd D1: a legkevésbé védett bemenet nem
   kaphat bekapcsoló jogot.
3. **Valódi hálózati remote flag csatorna ebben a körben.** Új támadási felület
   aláírás-ellenőrzési tervezet nélkül (D3).
4. **Reflexió-alapú teljesség-ellenőrzés.** A Dart AOT/Flutter környezetben nincs
   használható futásidejű mezőlista; a forrás-parse (D4) determinisztikus és
   tesztelhető, a `check_sdd_index.dart` bevált mintáján.
5. **A hardcode-false kill switch bevezetése.** Az [ADR 0395](0395-community-baseline-feature-flags-and-threat-model-scope.md)
   szerint ez dedikált GOV-kör dolga, nem egy építő-köré.

## A visszavonás feltétele

Felülvizsgálandó, ha (a) a rollout-körök valódi remote flag csatornát
vezetnek be — ekkor a D3 interfész-szintű kikötése lejár, és az aláírás-
ellenőrzés normatív leírása külön ADR-t kap; vagy (b) mérten kiderül, hogy a
string-kulcsú kötés (D5) drift-et enged a mezőnevek átnevezésekor — ekkor a
gépi audit kiegészítendő az átnevezés-detektálással, nem a katalógus
típus-kötésével.
