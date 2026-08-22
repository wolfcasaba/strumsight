# Community access matrix — viewer × profile × content

> **E09-R04** (ADR 0398). A dokumentum a `CommunityAccessPolicy` által
> visszaadott szintek MÁTRIXÁT rögzíti — a kód-oldali forrás
> (`backend/app/community/policies/access_policy.py`) és a teszt-oldali
> mérce (`backend/tests/community/test_access_policy.py`) egyeztetésének
> kiindulópontja. A Kör 11/13 read-routerjei ezt a mátrixot valósítják
> meg a feed/post útvonalakon.

## Kiértékelési sorrend (az ordrings a biztonsági szerződés)

A `CommunityAccessPolicy.evaluate_profile_access` minden híváskor
PONTOSAN ebben a sorrendben fut le, és az ELSŐ egyezés visszatér:

1. **`viewer_is_owner == True`** → `FULL` (a tulajdonos mindent lát).
2. **`blocked == True`** → `SUMMARY` (a blokkolt fél számára a profil
   MINDIG úgy viselkedik, mintha `private` lenne — függetlenül a
   tényleges `visibility`-től; ADR 0398 §3, brief §5.2, A2).
3. **`visibility == PUBLIC`** → `FULL`.
4. **`visibility == FOLLOWERS`** → `FULL` ha `is_follower`, egyébként
   `SUMMARY`.
5. **`visibility == PRIVATE`** (maradék) → `SUMMARY`.

Az 1–2. lépést NEM szabad a 3–4. LÉPÉS UTÁNRA tenni — ez a §6.1
valódi-sértés próba (a sorrend felcserélése → A2 cella pirosra vált).

A `evaluate_content_access` (post/komment audience) ugyanezt a sorrendet
követi, kivéve a SUMMARY-szintet — ott a tartalom vagy látszik, vagy nem
(bool visszatérés).

## Mátrix — profil-read (`ProfileAccessLevel`)

| Viewer-típus | `visibility = PUBLIC` | `visibility = FOLLOWERS` | `visibility = PRIVATE` |
|---|:---:|:---:|:---:|
| **Owner** | `FULL` (1. ág) | `FULL` (1. ág) | `FULL` (1. ág) |
| **Follower** | `FULL` (3.) | `FULL` (4a.) | `SUMMARY` (5.) |
| **Nem-follower** | `FULL` (3.) | `SUMMARY` (4b.) | `SUMMARY` (5.) |
| **Blocked follower** | `SUMMARY` (2.) | `SUMMARY` (2.) | `SUMMARY` (2.) |
| **Club-member**† | `FULL` (3.) | `SUMMARY` (4b.) ‡ | `SUMMARY` (5.) |
| **Self-blocked owner** | (nem értelmezett; Kör 8) | — | — |

† A `RelationshipContext.is_club_member` ebben a körben MINDIG `False`
(az élő club-adatmodell a Kör 24 scope). A mező a kontraktus RÉSZE — a
Kör 24 a `RelationshipContext.is_club_member=True`-val hívja majd a
policyt. A mátrix-sor itt csak a jövőre vonatkozó referencia; a Kör 4
tesztjei `False`-szal dolgoznak, és nem hamisítanak klubtagságot.

‡ A Kör 24 jövőbeli scope — a jelenlegi `evaluate_profile_access` a
klubtagságot NEM olvassa (nincs rá ág, mert a `FOLLOWERS` ág kizárólag
az `is_follower` flaget nézi). A klub-tagság KÖVETKEZMÉNYE a Kör 24
döntése, nem a Kör 4-é.

## Mátrix — content-read (`evaluate_content_access` → bool)

| Viewer-típus | `audience = PUBLIC` | `audience = FOLLOWERS` | `audience = PRIVATE` |
|---|:---:|:---:|:---:|
| **Owner** | ✅ (1.) | ✅ (1.) | ✅ (1.) |
| **Follower** | ✅ (3.) | ✅ (4a.) | ❌ (5.) |
| **Nem-follower** | ✅ (3.) | ❌ (4b.) | ❌ (5.) |
| **Blocked follower** | ❌ (2.) | ❌ (2.) | ❌ (2.) |

## Default értékek — A5 invariáns

| Mező | Alapértelmezett | Forrás |
|---|---|---|
| `community_privacy_settings.visibility` | `"followers"` | ADR 0398 §5 + migráció `server_default` |
| `community_privacy_settings.audience_default` | `"followers"` | ADR 0398 §5 + migráció `server_default` |

Az alapérték SOHA nem `"public"` — ez az A5/§5.3 SDD-invariáns
(ADR 0291: a közösség nem nyilvános alapból).

## Optimistic concurrency — A6

A `community_privacy_settings.updated_at` oszlop a resource-version —
nincs külön `version`/`etag` oszlop (ADR 0398 §6 "Elutasított
alternatívák"). A `PUT /community/privacy/{public_id}` az
`PrivacySettingsUpdate.resource_version` mezőt összehasonlítja a sor
`updated_at`-jével:

* **Egyezés** → a sor frissül (`visibility`, `audience_default`,
  `updated_at = now`); a kliens megkapja az új `resource_version`-t.
* **Eltérés** → `StalePrivacyUpdateError` → HTTP **409** a részletes
  `current_resource_version` payload-dal.

## Hivatkozott szerződés — `RelationshipContext`

A Kör 8 brief name szerint hivatkozza a `RelationshipContext.blocked`
mezőt — ez a kontraktus MOSTANTÓL stabil:

| Mező | Típus | Jelentés |
|---|---|---|
| `viewer_is_owner` | `bool` | A néző a profil tulajdonosa |
| `blocked` | `bool` | A nézőt a tulajdonos blokkolta (A2) |
| `is_follower` | `bool` | Kizárólag ELFOGADOTT follow (A4) |
| `is_club_member` | `bool` | Kör 24 klubtagság (most `False`) |

A `blocked` mező NEVE nem változtatható (Kör 8 hivatkozás); bővíteni
lehet új mezőkkel, de a meglévőkön átnevezni a downstream briefek
egyidejű felülvizsgálatát igényli.

## Hivatkozások

- ADR 0398 — `docs/adr/0398-profile-privacy-audience-policy-and-access-control.md`
- E09-R04 brief — `docs/rounds/e09-r04-profile-privacy-and-audience-policy.md`
- Kör 8 (előre megírt, nem indított) —
  `docs/rounds/e09-r08-block-mute-and-safety-relationships.md` §2
