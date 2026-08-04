# ADR 0132 — AI Tutor privacy & consent

- **Státusz:** Elfogadva (E04-R01 pre-flight, 2026-08-04)
- **Kör:** E04-R01 — AI Tutor baseline, ADR-ek és feature flagek
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md)
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md),
  [0134](0134-ai-tutor-memory-policy.md)

## Kontextus

A tutor mért session-adatokból, validált tudásbázisból és explicit
felhasználói célokból dolgozik (SDD Ch5 §1). A cloud model-hívás opcionális és
adatvédelmi szempontból érzékeny: a felhasználó adatai elhagyják a készüléket.
Az on-device offline-garancia (E01-R16, `test/app/offline_network_guard_test.dart`)
0-request kijelentkezett/offline utat őriz — ezt a tutor sem törheti flag OFF
mellett.

Az SDD kimondja: nyers audio nem kerül AI requestbe (Ch5 §268, §897, §1237,
§1251, §2406); a cloud model használat, a szerveroldali tartós tárolás és az
evaluation-célú felhasználás **külön-külön** consentet igényel (Ch5 §1043–1050,
§2459).

## Döntés

1. **Cloud AI csak explicit consenttel.** Cloud model-hívás nem indulhat, amíg
   a felhasználó erre külön hozzájárulást nem adott. Consent hiányában a tutor
   a determinisztikus on-device coachingra korlátozódik.
2. **Nyers audio soha nem kerül tutor requestbe** — sem on-device, sem cloud
   úton. A tutor context kizárólag származtatott, mért aggregátumokból épül
   (akkord/ritmus/score eredmények), nem a mikrofon nyers frame-jeiből.
3. **A consent tagolt:** (a) model-use (cloud hívás egyáltalán), (b) tartós
   szerveroldali conversation-tárolás, (c) evaluation-célú felhasználás
   redakcióval — három független hozzájárulás. Az egyik megadása nem vonja
   maga után a másikat.
4. **Flag OFF ⇒ nulla hálózati kérés és nulla új route.** Az `aiTutorEnabled`
   és `aiTutorCloudEnabled` default OFF; az offline-garancia teszt változatlanul
   zöld marad.

## Következmények

- A consent-flow és a redakció külön körök (R-blokk) felelőssége; ez a kör csak
  a boundaryt és a „nyers audio nincs a contextben" kimondását rögzíti a
  baseline-dokumentumban.
- A cloud hálózati wiring (beleértve a `FeatureFlags.usesNetwork`
  részvételt és az URL-validációt) **R14-re halasztott** — ez a kör
  funkcionális változtatás nélkül, tisztán additív default-OFF flaggel zár,
  ezért `usesNetwork` ebben a körben NEM módosul.
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen.
