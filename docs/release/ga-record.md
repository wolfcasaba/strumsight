# GA record — StrumSight

**Kör:** `E12-R33` (Chapter 12, Kör 33). **Normatív forrás:** nincs ADR — a
kör három kötött szabályt hordoz a kör-briefben (`docs/rounds/e12-r33-staged-
rollout-50-to-100-and-ga.md` §5). **Ellenőrző:**
[`tool/release/verify_ga_record.py`](../../tool/release/verify_ga_record.py).

Ez a dokumentum a StrumSight GA (General Availability) állapotának
auditálható rekordja: build/verzió-azonosítók, a flag-profil pillanatképe, a
rollback-cél és egy gépi `ga_status` mező. **A 100%-os store-rollout és a
GA-jelölés maga user-művelet (§0.0 EMBERI KAPU)** — ez a kör nem publikál
semmit, nem állít rollout-százalékot, és nem írja át a
[`staged-rollout-log.md`](staged-rollout-log.md)-t. A rekord a publikálás
UTÁN kitöltendő mezőket **EXPLICIT emberi jelöléssel** viszi — lásd a §6/§7
alatti `GA UTÁN, EMBERI KITÖLTÉS` jelölést; ezek a mezők SOSEM kapnak
kitalált értéket.

A repó mért rollout-tapasztalata (ADR 0065, ADR 0197) szerint egy kiadás nem
csak verziószám — a flag-profil és a belépési pontok kérdése is; ezért ez a
rekord a verzió mellett a teljes 16 kulcsos flag-profilt is rögzíti (§3).

## 1. GA-státusz (gépi mező, §5.4 / A7)

A `ga_status` zárt értékkészletű: `not-yet` | `in-progress` | `ga`. A
`verify_ga_record.py` nem-nulla kilépéssel áll meg, ha ez a mező `ga`,
miközben a [`staged-rollout-log.md`](staged-rollout-log.md) bármely
`stage-*` döntése nem `approved`, VAGY a [`blockers.md`](blockers.md)-ben
nyitott P0/P1 sor van — MINDKÉT feltétel MA fennáll (mind a három lépcső
`pending`, plusz 1 nyitott P0 és 5 nyitott P1), tehát ez a rekord `ga_status`-
a **`not-yet`**.

<!-- ga-status:begin -->
ga_status: not-yet
<!-- ga-status:end -->

## 2. Build- és verzió-azonosítók (a manifest BEMENETEiből, A2)

A release-manifest generált Dart-artefaktum
(`tool/generate_release_manifest.dart`), statikus manifest-fájl a fán NINCS.
Az alábbi mezők ezért a manifest **deklarált bemeneteiből** származnak —
`pubspec.yaml` verzió/build, `assets/ml/model_manifest.json` és
`assets/tutor_knowledge/manifest.json` sha256-ja, séma-verziója és
elem-száma —, amelyeket a `verify_ga_record.py` minden futáskor frissen
újraszámol, sosem kézzel másolt literálból hasonlít.

<!-- ga-record-version:begin -->
| field | value |
|---|---|
| `app_version` | `1.0.0` |
| `app_build_number` | `1` |
| `ml_manifest_schema_version` | `1` |
| `ml_manifest_sha256` | `2d42d7a19dc7217e457f6140a47e484cec13d27d64a749bd0053cf101a2172ff` |
| `ml_model_count` | `4` |
| `knowledge_manifest_schema_version` | `1` |
| `knowledge_manifest_sha256` | `0d1a1294edd8a4842718cf2374c70e799fe6b88302fdab541dddc74afee3b446` |
| `knowledge_document_count` | `10` |
<!-- ga-record-version:end -->

**Build-azonosító (git SHA) — GA UTÁN, EMBERI KITÖLTÉS.** A ténylegesen
kiadott, aláírt production build git SHA-ja (`tool/generate_release_manifest
.dart --git-sha` kimenete abból a buildből) csak egy VALÓS
`release-apk.yml`-dispatch után létezik — ma nincs aláírt production APK
(`R-SIGN-01`, P0, [`blockers.md`](blockers.md)). Ez a mező ezért szándékosan
nem tartalmaz SHA-t: `<GA UTÁN, EMBERI KITÖLTÉS — a ténylegesen kiadott,
aláírt production build git SHA-ja és a `release-apk.yml` run-linkje>`.

## 3. Flag-profil pillanatkép (A3)

A [`ga-scope.md`](ga-scope.md) `<!-- ga-scope-capabilities:begin/end -->`
zárt marker-blokkjának pontos másolata — mind a 16 kulcs, a `classification`
és a `production_default` oszloppal. A `verify_ga_record.py` ezt a táblát a
`ga-scope.md`-vel élőben veti össze (nem egy befagyasztott, kézzel másolt
pillanatkép ellen) — hiányzó, többlet vagy eltérő kulcs nem-nulla kilépés.

<!-- ga-record-flags:begin -->
| flag_key | classification | production_default |
|---|---|---|
| `accountEnabled` | `disabled` | `false` |
| `diagnosticsEnabled` | `disabled` | `false` |
| `labModeAvailable` | `preview` | `false` |
| `practiceEngineV2Enabled` | `ga` | `false` |
| `migratedLearnEnabled` | `preview` | `false` |
| `practiceDetailedHistoryEnabled` | `preview` | `false` |
| `songTrainerV2Enabled` | `postponed` | `false` |
| `aiTutorEnabled` | `postponed` | `false` |
| `aiTutorCloudEnabled` | `postponed` | `false` |
| `visionEnabled` | `postponed` | `false` |
| `visionLabCaptureEnabled` | `disabled` | `false` |
| `audioAnalysisV2Enabled` | `postponed` | `false` |
| `communityEnabled` | `postponed` | `false` |
| `communityWritesEnabled` | `postponed` | `false` |
| `communityMediaEnabled` | `postponed` | `false` |
| `adaptiveShellEnabled` | `preview` | `false` |
<!-- ga-record-flags:end -->

Az EGYETLEN `ga`-besorolású kulcs (`practiceEngineV2Enabled`) production
alapértelmezése MA `false` — a feloldó feltétel a `ga-scope.md` saját
`Production unlock:` jelölésű sorában van megnevezve (§ga-scope.md:64), ezt
a rekord nem ismétli meg.

## 4. Ismert hibák

A teljes, mért, nyitott hibalista: [`known-issues.md`](known-issues.md)
(`<!-- known-issues:begin/end -->`). Ez a rekord nem másolja be a táblát,
csak hivatkozik rá — a duplikált másolat elavulna, a hivatkozás nem.

## 5. Rollback-cél (A4, §5.3)

A GA UTÁNI rollback-készenlét a MA mért, ténylegesen lefuttatott
gyakorlatra támaszkodik ([`docs/operations/disaster-recovery-drill.md`](../operations/disaster-recovery-drill.md))
— kill-switch hatás, modellcsomag-ellenőrzés és adat-helyreállítás
végigfuttatva, gépi mércével (`test/tooling/rollback_policy_test.dart`).
**„GA után nincs visszaút" NEM elfogadható gyengítés (§5.3)** — a rollback-
cél a GA UTÁN is érvényes és elérhető marad; a kill-switch útja (build-idejű
`dart-define` vagy forráskód-módosítás) [`kill-switches.md`](kill-switches.md)
§2-ben van katalogizálva.

<!-- ga-record-rollback:begin -->
rollback_target: docs/operations/disaster-recovery-drill.md
<!-- ga-record-rollback:end -->

## 6. Támogatási linkek — GA UTÁN, EMBERI KITÖLTÉS

A fán MA nincs megerősített, store-képes support-URL: a
`privacy-support@strumsight.app` cím [`docs/legal/privacy-policy-draft.md`](../legal/privacy-policy-draft.md)
saját szavaival ELŐZETES, meg nem erősített PLACEHOLDER (`R-PRIV-01`, P1,
[`blockers.md`](blockers.md); `K-E12R24-01`, [`known-issues.md`](known-issues.md)),
és a [`04-release-checklist.md`](../governance/04-release-checklist.md):40
„support és privacy URL" sora pipálatlan. Ez a mező ezért szándékosan nem
tartalmaz linket: `<GA UTÁN, EMBERI KITÖLTÉS — a megerősített support- és
privacy-URL a store-listinghez>`.

## 7. Publikálási időbélyeg — GA UTÁN, EMBERI KITÖLTÉS

`<GA UTÁN, EMBERI KITÖLTÉS — a tényleges GA store-publikálás UTC
időbélyege>`. Ezt a mezőt a publikálást végző ember tölti ki a valós
publikálás pillanatában — nincs itt kitalált vagy előre felírt dátum.

## 8. A közzététel emberi jellege (A6)

A GA-közzététel EMBERI művelet. Sem a %-os rollout-lépcső emelése (1% → 5%
→ 20% → 50% → 100%), sem a store-oldali GA-jelölés nem automatizált — minden
lépést egy ember hajt végre, a `staged-rollout-log.md` és e rekord kitöltött,
`approved`/`ga` állapota alapján. Ez a kör kizárólag a sablont, az
ellenőrzőt és a záró release-notes-ot szállítja; a rekord és a hozzá tartozó
`verify_ga_record.py` nem indít, nem gyorsít és nem automatizál semmilyen
publikálást.
