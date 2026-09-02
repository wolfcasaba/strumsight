# E12-R24 — Review (Store listing, privacy és legal package)

- **Reviewer:** Claude (Opus 5), orchestrátor — read-only review, ADR 0055
- **Dátum:** 2026-09-02
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5)
- **Kör-branch:** `sonnet-impl/e12-r24-store-listing-and-legal-package`
- **Review-head:** `ff86ad57` (`[E12-R24] Store listing, privacy és legal package`)
- **Izolált klón:** friss klón a `ff86ad57` SHA-n, `prepare-flutter-generated.sh` után

## 1. menet — VERDIKT: CHANGES REQUESTED (1 MAJOR + 1 MINOR + 2 NOTE)

## Scope-audit

`tools/scope-audit.py --base 077309e9 --head ff86ad57` → **OK**, 7 changed path,
0 generated/ignored. A commitolt halmaz PONTOSAN a brief `allowed_paths` listája:

```
docs/legal/community-guidelines-draft.md
docs/legal/privacy-policy-draft.md
docs/rounds/e12-r24-store-listing-and-legal-package.md
docs/store/data-safety.yaml
docs/store/listing.md
docs/store/permissions-rationale.md
test/tooling/store_package_test.dart
```

> A wrapper első `scope_audit=VIOLATION` jelzése az orchestrátor SAJÁT,
> untracked dispatch-promptjára (`.round-prompt.md`) vonatkozott, nem az
> implementer munkájára — a fájl eltávolítása után az audit tisztán fut. Ez az
> orchestrátor dispatch-módszerének hibája volt, nem H3, és nem az implementeré.

## Alap-mérés

`flutter test test/tooling/store_package_test.dart` az izolált klónon:
**29/29 zöld**. A `data_inventory_test.dart` (A6) érintetlen — a kör a
`docs/privacy/**` fát nem módosította.

## Saját valódi-sértés próbák (nem a zöld gate-re támaszkodva)

Hét próba, mindegyik a VALÓDI forrásfájlon (a klónban), utána `git checkout`:

| # | Beavatkozás | Várt | Mért |
|---|---|---|---|
| P5 | ÚJ `ACCESS_FINE_LOCATION` a valódi `AndroidManifest.xml`-be | A1 piros | ✅ `'…ACCESS_FINE_LOCATION has no rationale entry…'` |
| P1 | a `CAMERA` rationale-blokk fejlécének eltávolítása | A1 piros | ✅ `'…CAMERA has no rationale entry…'` + `'no CAMERA rationale block found'` |
| P3 | data-safety `field:` átírása nem létező mezőnévre | A2 piros | ✅ mindkét irányban (feloldatlan hivatkozás ÉS fedezetlen mező) |
| P6 | ÚJ `leaves_device: true` mező a valódi `data-inventory.yaml`-be | A2 piros | ✅ `'…account_api/probe_injected_field … no … category references it'` |
| P2 | `audio_analysis_core` `ga_scope` `true`→`false` a valódi `device-matrix.yaml`-ben | A3 piros | ✅ a marker-cella ÉS a próza-scan is |
| P4 | kitalált `/privacy-center` route a valódi `listing.md`-be | A4 piros | ✅ `'…references app route "/privacy-center", which does not exist…'` |
| **P7** | **ÚJ, negyedik `ga_scope: false` capability + „coming soon" próza-ígéret** | **A3 piros** | ❌ **29/29 ZÖLD** → MAJOR-1 |

A P5/P6/P2 együtt bizonyítja, amit a §0.0 R1/R3/R4 megkövetelt: a teszt a
manifestet, a leltárt és a device-mátrixot ÉLŐBEN olvassa — nincs beégetett
engedély-, leltár- vagy GA-lista. Ez a kör legfontosabb minőségi állítása, és
áll.

> A brief §6.1 az A3-hoz a `device-matrix.yaml` IDEIGLENES billentését kérte az
> implementertől, de a fájl nincs az `allowed_paths`-on, és az
> `implementer_guard.py` — helyesen — megtagadta. Az implementer ezt NEM
> kerülte meg, hanem `stopped` helyett jelentette és in-memory ekvivalens
> cellákkal pótolta (§10). A tényleges fájl-billentést a reviewer végezte el
> (P2) az eldobható klónban. Az ellentmondás a briefben van, nem a
> munkában — lásd NOTE-2.

---

## MAJOR-1 — Az A3 próza-scan NÉMÁN kihagyja a signature nélküli non-GA capabilityket (fail-open)

**Hely:** `test/tooling/store_package_test.dart:1036` (`capabilityMarketingSignaturePatterns`),
`:1053-1054` (`final pattern = signaturePatterns[capability.id]; if (pattern == null) continue;`)

**A hiba.** A `checkListingProseAgainstCapabilitySignatures` végigmegy a
device-mátrix `ga_scope: false` capabilityjein, de amelyikhez nincs bejegyzés a
kézzel karbantartott `capabilityMarketingSignaturePatterns` térképben, azt egy
`continue` **csendben átugorja**. Egyetlen cella sem méri, hogy a térkép lefedi-e
az összes non-GA capabilityt. A hiányzó lefedettség tehát ZÖLDKÉNT jelenik meg.

**Reprodukció (P7, ténylegesen lefuttatva az izolált klónon):**

```bash
# 1) negyedik non-GA capability a valódi mátrixba
#    (docs/testing/device-matrix.yaml, az ai_tutor blokk után)
  - id: band_jam_mode
    ga_scope: false
    devices: []
# 2) a listing PRÓZÁJÁBA (a markert NEM bővítve):
**Band Jam Mode.** Play along with a full backing band, coming soon.

flutter test test/tooling/store_package_test.dart
→ 00:00 +29: All tests passed!      # exit 0
```

Ez PONTOSAN az a §5.3-sértés („NEM elfogadható gyengítés: »hamarosan«
megfogalmazású funkció-ígéret"), amelynek megfogása ennek a körnek a célja, és
a kétrétegű A3 második rétege pont azért létezik, hogy a markerbe fel nem vett
prózát elkapja — ez a réteg némán elveszik.

**Miért MAJOR, nem MINOR.** Ez gépi mércében fail-open, és a fán MÁR MÉRT
hibaosztály: [ADR 0477](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md)
**D2** kimondja, hogy hiányzó bizonyíték BLOKKOL és a „nincs adat → nincs
regresszió" TILOS; az E12-R16 MAJOR-1 ([L555](../LESSONS.md#l555)) ugyanezt a
mintát („a kapu követelmény-listája némán csökkenthető") már egyszer megfogta
ezen a fán, TELJESEN ZÖLD gate mellett.

**Javasolt javítás (kicsi, additív).** Fail-closed cella + fail-closed kód:
minden `ga_scope: false` capabilityhez KÖTELEZŐ signature-bejegyzés. Vagy a
`continue` helyett a hiányzó minta maga legyen violation, vagy egy külön cella
mérje `capabilities.where((c) => !c.gaScope).map((c) => c.id)` ⊆
`signaturePatterns.keys`. A P7 reprodukciónak utána PIROSNAK kell lennie.

---

## MINOR-1 — Az A4 route-scan nem nézi a `docs/store/data-safety.yaml`-t

**Hely:** `test/tooling/store_package_test.dart` — az A4 `docFiles` listája négy
fájlt sorol (`listing.md`, `permissions-rationale.md`, `privacy-policy-draft.md`,
`community-guidelines-draft.md`); a csomag ötödik szállított fájlja,
a `docs/store/data-safety.yaml`, kimarad.

**Hatás.** Ma nincs benne route-alakú szöveg, tehát élő hiba nincs — de a
`purpose:` mezők szabad szövegűek, és egy jövőbeli „törölhető a `/privacy-center`
képernyőn" mondat az A4-en észrevétlenül átmenne. A csomag öt dokumentumából
négy van lefedve; a lefedettség legyen teljes, ne majdnem teljes.

**Javasolt javítás:** vedd fel a `docs/store/data-safety.yaml`-t a `docFiles`
listába (a fájl a többivel azonos módon olvasható szövegként).

---

## NOTE-1 — A támogatási e-mail kitalált placeholder

A `privacy-support@strumsight.app` cím nem mért, létező postafiók. Az
implementer ezt a §10-ben KIMONDTA, és mindkét jogi tervezet, valamint a teszt
is „placeholder"-ként jelöli — ez helyes, őszinte kezelés, nem lelet. A
tényleges cím megerősítése az emberi jogi felülvizsgálat része (§0.0), és a
store-feltöltés előfeltétele. Rögzítve, hogy a merge után se felejtődjön el.

## NOTE-2 — Az ORCHESTRÁTOR dispatch-promptja kért `allowed_paths`-on kívüli próbát

Pontosítás a hiba helyéről: a brief §6.1 sora („A3 önvédő cella … billentve a
cellának meg kell FORDULNIA") in-memory önvédő cellaként is teljesíthető, és a
brief kötelező valódi-sértés próbája csak az A1-et írja elő. A
`docs/testing/device-matrix.yaml` TÉNYLEGES, fájl-szintű billentését az
**orchestrátor dispatch-promptja** (`.pipeline/prompt-e12-r24-impl.md` §5)
kérte — egy olyan fájlra, amely nincs az `allowed_paths`-on. Az
`implementer_guard.py` ezért megtagadta: a védelem helyesen működött, és a hibás
utasítás az enyém volt, nem a briefé és nem az implementeré.

Az implementer eljárása helyes: nem kerülte meg az őrt, hanem a §10-ben
kimondottan jelentette, és ekvivalens in-memory cellákkal pótolta —
scope-sértés nélkül. A fájl-szintű próbát a reviewer végezte el az eldobható
klónban (P2), és pont ez a próba-készlet (P7) hozta ki a MAJOR-1-et. **Átvihető
tanulság:** forrásfájlt ténylegesen billentő falszifikációs próba a REVIEW
hatásköre (eldobható klón), nem az implementeré — a dispatch-prompt ne kérjen
az implementertől `allowed_paths`-on kívüli írást.

---

## Amit külön megnéztem, és rendben van

- **A1 tartalmi mérce (§5.2).** Mind az 5 mért engedélyhez van FUNKCIÓ + ADAT
  megnevezés; „a plugin kéri" alakú indoklás sehol. A `RECEIVE_BOOT_COMPLETED`
  a `ScheduledNotificationBootReceiver`-re és az emlékeztető-újraregisztrálásra
  hivatkozik, nem a pluginra. A `debug`/`profile` variant kizárása kimondott és
  mért.
- **A CAMERA / non-GA feszültség (§0.0 R3).** A rationale kimondottan
  „opcionális ÉS nem-GA"-ként minősíti, a `computer_vision` `ga_scope: false`
  hivatkozásával, a `listing.md` pedig sem a markerben, sem a prózában nem
  reklámozza. A STOP-protokoll helyesen NEM állt fenn (van mérhető funkció).
- **A2 kétirányúság és a `rides:` kezelés (§0.0 R4).** A `rides` route-ok nem
  követelnek külön kategóriát (külön cella méri), a `wired: false` /
  `leaves_device: false` mezők sem — a 12 `leaves_device: true` mező mind
  fedett. A leltár olvasása a KÉSZ `tool/check_data_inventory.dart`-tal megy,
  `package:yaml` import nincs, a `tool/**` érintetlen.
- **A4 őszinteség (§0.0 R2).** A `privacy-policy-draft.md` szó szerint kimondja,
  hogy nincs kliens által indítható fiók-törlési végpont, és külön cella méri
  a valódi `backend/app/routers/auth.py` három végpontját. Kitalált route és
  kitalált `DELETE /auth/me` alakra is van fixture-cella.
- **A5.** Mindkét jogi tervezet `TERVEZET / DRAFT` fejlécet és nevesített
  felülvizsgálót visel; a hiányzó marker fixture-cellája piros.

## Teendő

**MAJOR-1 és MINOR-1 javító körben zárandó** (ugyanaz a motor, ugyanaz a
branch). A javítás után a P7 reprodukciónak PIROSNAK kell lennie, és a
29 meglévő cellának zöldnek maradnia.
