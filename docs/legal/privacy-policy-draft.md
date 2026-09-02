# StrumSight — Privacy Policy (draft)

**Státusz: TERVEZET / DRAFT.** Ez a dokumentum NEM közzétehető jogi
szöveg — a store-feltöltés előtti belső forrás, a MÉRT adatkezelésből
származtatva (E12-R24, 2026-09-02). **Jogi felülvizsgálatért felelős:**
Ralph, termék-tulajdonos (`kcsabi176@gmail.com`) — közzététel előtt
KÖTELEZŐ emberi jogi felülvizsgálat, ideértve a helyi
adatvédelmi/fogyasztóvédelmi jog szerinti végső szöveg jóváhagyását is.
Ez a kör (§0.0) kizárólag a dokumentum-csomagot állítja elő; a store-fiók,
a feltöltés és a jogi jóváhagyás emberi lépés marad.

Ez a tervezet a `docs/privacy/data-inventory.yaml` (E12-R17, ADR 0479)
gépileg ellenőrzött adatleltárából és az ADR 0247 export/share/delete
szerződéséből származik — nem önállóan megfogalmazott állítás. A
`docs/store/data-safety.yaml` ugyanennek a leltárnak a store-formára
leképezett, gépileg összevethető alakja.

## 1. Kire vonatkozik

StrumSight (`com.wolfcasaba.strumsight`), egy offline, on-device
gitárakkord- és pengetésirány-detektor. Az app kijelentkezve / fiók nélkül
is teljes értékűen használható; az alábbi adatkategóriák egy része
kizárólag akkor keletkezik, ha a felhasználó explicit módon bekapcsol egy
opcionális funkciót (fiók, Lab-mode diagnosztika, megosztás).

## 2. Amit az eszközön belül dolgozunk fel, és SOSEM hagyja el

A mikrofonjel és a kamerakép (ha a felhasználó engedélyezi) kizárólag
on-device kerül feldolgozásra a detektálási és elemzési pipeline-ban. A
StrumSight detektáló motorja hálózati kérést nem indít — kijelentkezve,
fiók nélkül az app mérten nulla hálózati kérést küld.

## 3. Amit gyűjtünk, ha a felhasználó bekapcsolja az opcionális
   fiók-réteget

Az opcionális fiók-réteg (bejelentkezés + beállítás-szinkron) az alábbi
adatokat küldi a backend felé (részletek, jogalap és megőrzési idő:
`docs/store/data-safety.yaml`):

- fiók-hitelesítő adatok (email, jelszó) — jogalap: szerződés;
- szinkronizált beállítások (téma, nyelv, érzékenységi küszöb, hangolási
  referencia) — jogalap: szerződés;
- Community profil (felhasználónév, megjelenített név, láthatóság) — csak
  ha a felhasználó explicit belép a Community funkcióba;
- Community social graph (követés/letiltás/némítás) és challenge-aktivitás
  — csak Community-használat esetén.

## 4. Opt-in diagnosztika (Lab mode)

Ha a felhasználó explicit bekapcsolja a Lab-mode diagnosztikai opt-int
(alapértelmezetten KIKAPCSOLVA, fail-closed), StrumSight ML-vs-DSP
összehasonlító eseményeket, egy decimált hangkivágatot és
eszköz/verzió-metaadatot küld fel modell-hibakereséshez. Ez a felfelé
irányuló küldés Lab mode nélkül SOHA nem történik meg.

## 5. Felhasználó által kezdeményezett megosztás

Amikor a felhasználó explicit megoszt egy gyakorlás-kártyát, feliratot
vagy egy előnézettel megerősített elemzés-exportot (ADR 0247), az adott
tartalom az operációs rendszer megosztási felületén keresztül a
felhasználó által VÁLASZTOTT célalkalmazáshoz kerül — ez a felhasználó
saját döntése, nem a StrumSight által vezérelt adattovábbítás. Az
exportált JSON egy allowlist-alapú, redaktált nézet — nem a teljes belső
dokumentum.

## 6. Amit MA NEM gyűjtünk, bár a kód útja létezik

A Tutor cloud-stream (`POST /tutor/stream`) és a Community-média feltöltés
útja a kódban létezik, de MA nincs production konstrukciós helye a
`lib/**` fában — ezek az utak ma egyetlen byte-ot sem küldenek a
hálózatra. Ha ez egy jövőbeli körben megváltozik, ez a dokumentum
felülvizsgálatra szorul.

## 7. Az adatokhoz való hozzáférés és törlés

**On-device adatok:** a Settings képernyőről (`/settings`) elérhető
Privacy Center exportálja vagy törli az on-device Vision-munkameneteket
(`PrivacyCenterScreen`, `lib/features/settings/screens/privacy_center_screen.dart`).
A Tutor consent és a helyi tutor-memória kezelése a `/tutor/privacy`
(hozzájárulás visszavonása) és a `/tutor/data` (tutor-memória kezelése)
képernyőn érhető el.

**Fiók-szintű törlés — ŐSZINTE állapot (§0.0 R2, MÉRVE 2026-09-02):**
StrumSight **does not have a client-triggered account-deletion endpoint**
ma a `backend/**` fán — a `backend/app/routers/auth.py` három végpontot ad
(`POST /register`, `POST /login`, `GET /me`), törlési végpont nincs
köztük. A fiók és a hozzá tartozó backend-oldali adatok
(email, jelszó, szinkronizált beállítások, Community profil/social-graph/
challenge-adatok) törlését ezért MA egy támogatási csatornán, e-mailben
kell kérni:

> **`privacy-support@strumsight.app`** (ELŐZETES, meg nem erősített
> placeholder cím — a valódi támogatási postafiók a store-feltöltés előtti
> emberi lépés része).

Ez a bekezdés a `test/tooling/store_package_test.dart` A4 cellája által
gépileg ellenőrzött, szó szerinti állítás — ha ez a mondat eltűnik, vagy
egy nem létező törlési végpont/route kerül a helyére, a cella pirosra
vált.

## 8. Megőrzés

A backend-oldali megőrzés a fiók élettartamára szól (`docs/privacy/data-inventory.yaml`
`account_api` route, `retention` mezők) — a fenti 7. pont korlátja mellett.
A diagnosztikai feltöltés egy-lövéses, kliens-oldalról mért törlési útja
nincs. A megosztott fájlok on-device temp-életciklusát a `ShareService`
`try/finally` blokkja garantáltan takarítja, sikertől függetlenül.

## 9. Kapcsolat

Adatvédelmi kérdés, export- vagy törlési kérés: `privacy-support@strumsight.app`
(placeholder — lásd 7. pont).
