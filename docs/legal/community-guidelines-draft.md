# StrumSight — Community Guidelines (draft)

**Státusz: TERVEZET / DRAFT.** Ez a dokumentum NEM közzétehető jogi
szöveg — a store-feltöltés előtti belső forrás (E12-R24, 2026-09-02).
**Jogi felülvizsgálatért felelős:** Ralph, termék-tulajdonos
(`kcsabi176@gmail.com`) — közzététel előtt KÖTELEZŐ emberi jogi
felülvizsgálat (ideértve a moderációs ígéretek jogi/gyakorlati
fedezetének ellenőrzését is, mielőtt bármely állítás nyilvánosan
megjelenne).

## 1. Hatókör

A Community egy **opcionális, fiók-hátterű** funkció (profil, követés/
letiltás/némítás, challenge-részvétel) — a `docs/privacy/data-inventory.yaml`
`account_api` route-jának `community_profile`,
`community_social_graph` és `community_challenge_activity` mezői. Aki
NEM lép be a Community-be, arra ezek az irányelvek nem vonatkoznak — az
app fiók és Community nélkül is teljes értékűen használható.

## 2. Elvárt viselkedés

- Légy tisztelettel más gitározók felé, függetlenül a szinttől.
- Ne oszd meg más felhasználó személyes adatát az ő hozzájárulása nélkül.
- A challenge-küldés/-elfogadás/-visszautasítás (invite/accept/decline/
  cancel/submit_result) a másik fél saját döntése — a zaklatásszerű,
  ismételt felkérés nem elfogadott.

## 3. Tiltott tartalom és viselkedés

- Zaklatás, gyűlöletbeszéd, fenyegetés.
- Spam, félrevezető profiladatok, más személy megszemélyesítése.
- Illegális tartalom megosztása vagy arra való felhívás.

## 4. Eszközök, amikkel a felhasználó él a nem kívánt interakció ellen

Letiltás és némítás (`block` / `mute`) a Community social graph részeként —
ugyanaz a `account_api` írás-út, amit a 1. pont mezői leírnak.

## 5. Moderáció — ŐSZINTE állapot

**A store-feltöltés időpontjában a StrumSight-nak nincs önálló,
emberi moderátorral üzemeltetett bejelentés-feldolgozó felülete a
`backend/**` fán** — ez a dokumentum nem ígér gyorsabb vagy más
moderációs SLA-t, mint amit a store platform (Google Play) saját
bejelentési mechanizmusa nyújt. Bejelentés és panasz a támogatási
csatornán küldhető:

> `privacy-support@strumsight.app` (placeholder — lásd
> `docs/legal/privacy-policy-draft.md` 7. pont, a valódi támogatási
> postafiók a store-feltöltés előtti emberi lépés része).

## 6. Következmények

A jelen irányelvek megsértése a Community-hozzáférés korlátozásához vagy
felfüggesztéséhez vezethet — a konkrét eljárásrend (ki dönt, milyen
határidővel, milyen fellebbezési úttal) a jogi felülvizsgálat és a
store-feltöltés közötti emberi lépésben kerül kidolgozásra; ez a tervezet
csak a keretet rögzíti, eljárásrendet nem talál ki.

## 7. Kapcsolat

`privacy-support@strumsight.app` (placeholder — lásd 5. pont).
