# StrumSight — Android permission rationale (release / `main` variant)

**Státusz:** TERVEZET — a store-feltöltés előtti forrás, MÉRT a
`android/app/src/main/AndroidManifest.xml` fájlból (E12-R24, 2026-09-02).
Nem store-szöveg — a Play Console "Data safety" / "App content" űrlapjainak
kitöltéséhez és a store-review-hoz szolgáló belső indoklás-jegyzék.

Ez a dokumentum a **`main` build variant** (a release-artefaktumba kerülő
manifest) minden `uses-permission` sorát felsorolja. Minden bejegyzés
megnevezi a FUNKCIÓT (melyik app-funkció kéri) és az ADATOT (mi történik
vele) — önmagában "a plugin kéri" típusú indoklás nem elfogadható (§5.2).

Gépileg ellenőrzött: `test/tooling/store_package_test.dart` a
`AndroidManifest.xml`-ből OLVASSA ki a kért engedélyek listáját (nincs
beégetett engedélylista a tesztben), és minden találathoz megköveteli az
alábbi `## android.permission.*` blokkok egyikét, benne egy nem üres
`- **Function:**` és `- **Data:**` sorral.

---

## android.permission.RECORD_AUDIO

- **Function:** folyamatos, on-device mikrofonbemenet a valós idejű
  akkord- és pengetésirány-detektorhoz — ez hajtja a Live tunert, a Live
  akkordfelismerést, a Practice engine-t, a Song Trainert és az Audio
  Analysis Core-t (a `live_and_tuner`, `practice_engine`,
  `song_trainer_local`, `audio_analysis_core` GA-scope capabilityk közös
  bemenete).
- **Data:** a nyers mikrofonjel kizárólag on-device kerül feldolgozásra.
  Ez az engedély önmagában NEM küld hangot a hálózatra — a
  `docs/store/data-safety.yaml` szerint egyetlen `wired: true` route sem
  szállít nyers mikrofonhangot; a `diagnostics_upload` route
  `audio_clip` mezője egy decimált, előfeldolgozott WAV-kivágat, amit a
  felhasználó a Lab-mode diagnosztikai opt-in-jén (külön, explicit
  hozzájárulás — `diagnosticsConsentProvider`) keresztül küld fel, nem
  ennek az engedélynek a következményeként.
- **Optional:** Nem — kötelező. Enélkül az app elsődleges funkciója (az
  on-device akkord/pengetésirány-detektálás) nem működik.
- **GA scope:** a fenti négy capability mind `ga_scope: true`
  (`docs/testing/device-matrix.yaml`).

## android.permission.CAMERA

- **Function:** opcionális, kamera-alapú gitártechnika-előnézet a Vision
  setup / guitar-geometry / session képernyőkhöz (`lib/features/vision/**`)
  — on-device technika-elemzés.
- **Data:** a kameraképkockák on-device kerülnek feldolgozásra a vision
  pipeline-ban; ez az engedély önmagában semmit nem tölt fel.
- **Optional:** Igen — **opcionális ÉS nem-GA**. A mögötte álló capability
  a `computer_vision`, amelynek `ga_scope: false` a
  `docs/testing/device-matrix.yaml`-ban — ez az engedély ezért NEM tartozik
  a GA release-felülethez, és a store-leírás nem reklámozhatja (§5.3). A
  kamera nélküli eszközök teljes értékű támogatást kapnak — a manifest
  `uses-feature android.hardware.camera` sora `android:required="false"`.
- **GA scope:** nincs (`computer_vision` = `false`).

## android.permission.INTERNET

- **Function:** az OPCIONÁLIS fiók-réteg — bejelentkezés/regisztráció és a
  beállítások eszközök közötti szinkronja (`lib/features/auth/**`,
  `lib/features/settings/providers/settings_sync.dart`), a Community
  profil/social-graph/challenge írás-utak (mind az `account_api`
  route-on keresztül), az opt-in Lab-mode diagnosztikai feltöltés
  (`diagnostics_upload`), és a felhasználó által kezdeményezett megosztás
  (`share_export`). A detektálás maga SOSEM használ hálózatot — kijelentkezve
  / fiók nélkül az app nulla hálózati kérést indít.
- **Data:** fiók-hitelesítő adatok (email, jelszó), szinkronizált
  beállítások, Community profil/social-graph/challenge adatok — mind az
  `account_api` route mezői —, diagnosztikai események (csak opt-in Lab
  mode-ban), és a felhasználó által indított megosztás payloadja
  (`share_export`). Részletek: `docs/store/data-safety.yaml`.
- **Optional:** Igen — a teljes fiók-réteg opcionális; az app kijelentkezve
  is teljes értékűen használható.
- **GA scope:** az `offline_operation` capability (az app offline
  használhatósága) `ga_scope: true`; a hálózat-függő fiók/Community/
  diagnosztika funkciók maguk nem szerepelnek önálló device-matrix
  capabilityként.

## android.permission.POST_NOTIFICATIONS

- **Function:** opt-in napi gyakorlás-emlékeztető (Settings-kapcsoló,
  `flutter_local_notifications`, a manifest 80. körös megjegyzése).
- **Data:** nincs — a helyi, ütemezett értesítéshez semmilyen adat nem
  kerül a hálózatra.
- **Optional:** Igen — opt-in a Settings egy kapcsolójával; az app enélkül
  is teljes értékűen működik.
- **GA scope:** a napi gyakorlási szokás-hurkot támogatja
  (`practice_engine`, `progress_goals_streak` — mindkettő `ga_scope:
  true`), önálló device-matrix capabilityként nem szerepel.

## android.permission.RECEIVE_BOOT_COMPLETED

- **Function:** az ütemezett napi gyakorlás-emlékeztető
  **újraregisztrálása újraindítás után**, a
  `ScheduledNotificationBootReceiver`-en keresztül (`flutter_local_notifications`,
  manifest 47–57. sor) — enélkül egy újraindítás előtt beütemezett
  emlékeztető csendben leállna.
- **Data:** nincs — kizárólag egy már beütemezett helyi értesítést
  regisztrál újra.
- **Optional:** Igen — csak akkor releváns, ha a felhasználó a
  `POST_NOTIFICATIONS` alatti Settings-kapcsolóval bekapcsolta a napi
  emlékeztetőt; egyébként hatástalan.
- **GA scope:** ugyanaz, mint a `POST_NOTIFICATIONS`-nál.

---

## Build variant-ok, amik NEM részei ennek az indoklásnak

A `debug` és a `profile` build variant
(`android/app/src/debug/AndroidManifest.xml`,
`android/app/src/profile/AndroidManifest.xml`) **kizárólag**
`android.permission.INTERNET`-et kér — a Flutter tooling hot-reload/
debug-bridge kapcsolatához (mindkét fájl saját megjegyzése szerint). Ez
MÉRT, nem feltételezés: egyik dev-variant sem kér `RECORD_AUDIO`-t,
`CAMERA`-t, `POST_NOTIFICATIONS`-t vagy `RECEIVE_BOOT_COMPLETED`-et. Egyik
dev-variant sem kerül a release-artefaktumba, ezért a fenti indoklás-lista
kizárólag a `main` variantra vonatkozik, és a két dev-variant tudatosan ki
van zárva belőle.
