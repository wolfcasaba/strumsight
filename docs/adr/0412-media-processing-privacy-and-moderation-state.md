# ADR 0412 — Média feldolgozás, privacy és moderation state

- **Státusz:** Elfogadva (E09-R19 pre-flight, 2026-08-23)
- **Kör:** E09-R19 — Média feldolgozás, privacy és moderation state
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5,
  `--effort high`) írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 19 (a 32 kör közül a
  tizenkilencedik)
- **Kontext-ADR-ek:** [0410](0410-media-upload-contract-and-object-store.md)
  (a `CommunityMedia` tábla és az `upload_state` gép, amire ez a kör épít,
  ROUTER NÉLKÜL — ugyanaz a deferred-wiring minta itt is), [0396](0396-community-profile-schema-and-privacy-defaults.md)
  §1 (`public UUID + bigint PK`), a Kör 11 `moderation_state` / `access_policy.py`
  „egyetlen olvasási-út policy" precedens.
- **Sorszám-jegyzet:** a brief fejléce `0408`-at adott előre kiosztott
  ADR-ként, de azt közben E09-R? / bookmark-kör foglalta el
  (`0408-bookmark-and-controlled-import.md`, MÁR MERGE-ELVE) — a
  `tools/round-slots.py reserve-adr --round E09-R19` friss számot adott
  (`0412`; `0409`–`0411` már más köröké). A brief §0.0 D1 rögzíti a
  korrekciót.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban (`main @ 71b74a20`):**

1. A `CommunityMedia` modell (`backend/app/community/models/media.py`)
   `upload_state` oszlopa MA öt, kizárólag a Kör 18 upload-tranzitot fedő
   értéket hordoz (`pending`/`uploaded`/`finalized`/`cancelled`/`failed`) —
   NEM „uploaded/finalized" ahogy a brief §2 laza szövege sugallja
   (mérve: `media.py:121-135`). A modell docstringje explicit kimondja:
   „the Kör 19 media-processing round will write [a `duration_ms`
   mezőt]" és a fájl fejrésze külön szakaszt szán egy ÚJ,
   `processing_state` nevű oszlopnak (`media.py:113-117`) — ez a kör tehát
   **nem az `upload_state` gépet bővíti**, hanem egy **második, különálló**
   állapot-oszlopot vezet be ugyanazon a soron (ld. D2).
2. **`backend/app/community/models/media.py` a brief §5 „Tilos zóna"
   listáján szerepelt, DE nem szerepelt a §4 „Engedélyezett fájlok"
   táblában és a gépi `allowed_paths` tömbben sem** — miközben a §5 saját
   zárójeles megjegyzése („bővítés indokolt, nem átírás") kifejezetten egy
   additív módosítást ír elő ugyanarra a fájlra. Ez a brief §1
   „Erőforrás-tulajdonlás" mérési szabálya alá eső, önellentmondó
   scope-rés: egy `processing_state` oszlop nem adható hozzá a modellhez
   anélkül, hogy a fájlt módosítanánk, tehát a fájlnak SZEREPELNIE kell az
   `allowed_paths`-on, szigorúan additív korlátozással. A §0.0 D2 ezt
   javítja — ez NEM lista-tágítás, hanem egy már a brief §5 szövege által
   előírt, de a gépi listából kimaradt bejegyzés pótlása.
3. **`backend/app/community/services/media_upload_service.py` (Kör 18,
   NEM ezen kör `allowed_paths`-a) marad ÉRINTETLEN.** Semmi nem hívja ma
   automatikusan a médiafeldolgozást a finalize után — a Kör 18 saját
   orphan-cleanup függvénye is csak egy meghívatlan, közvetlenül tesztelt
   függvény (mérve: `grep -rln "cleanup_orphan_uploads\|BackgroundTasks\|celery"
   backend/app` → kizárólag saját maga). A tényleges trigger-bekötés
   (finalize → feldolgozás-indítás) egy KÉSŐBBI kör dolga — ugyanaz a
   „szolgáltatás-réteg kész, bekötés később" minta, mint a Kör 18 saját
   router-deferrálása (ADR 0410 D3) és a Kör 12 óta `UnimplementedError`-t
   dobó feed/post repository HTTP-integráció (HANDOFF §6).
4. **`backend/app/community/storage/object_store.py` (Kör 18, NEM ezen kör
   `allowed_paths`-a) `ObjectStore` ABC-je kizárólag PUT-signinget definiál**
   (`create_upload_url`, `head_object`, `delete_object` — mérve:
   `object_store.py:124-141`). Nincs GET/download signed-URL metódus, és a
   fájl módosítása ezen a körön H3 lenne. A „signed playback URL" tehát NEM
   épülhet az `ObjectStore`-ra ebben a körben (ld. D6).
5. **Nincs kép/audio/videó-feldolgozó könyvtár a `requirements.txt`-ben**
   (mérve: a fájl kizárólag `fastapi`, `uvicorn`, `SQLAlchemy`, `alembic`,
   `pydantic[-settings]`, `email-validator`, `PyJWT`, `bcrypt`,
   `python-multipart`, `httpx` — nincs Pillow/ffmpeg-python/mutagen), és a
   `requirements.txt` NINCS ezen kör `allowed_paths`-án → csomagtelepítés
   tilos (implementer-preambulum §4, ADR 0410 D2 precedens ugyanerre a
   korlátra). Ez élesen szűkíti, mit jelenthet a brief §3 „codec/duration/
   resolution/frame-rate korlátozás" és „transcoding" kitétele — ld. D8.
6. **`backend/app/community/policies/access_policy.py` MÁR tartalmaz egy
   audience-ellenőrző, tisztán funkcionális policy-t**
   (`CommunityAccessPolicy.evaluate_content_access(audience, relationship) ->
   bool`, `RelationshipContext`, `relationship_context_from_block_flag` —
   mérve: `access_policy.py:86-170`). A fájl saját docstringje kimondja:
   „Future read routers will hold one of these ... and call the matching
   method for their resource type." Ez a projekt „egyetlen olvasási-út
   policy" elve — a playback-audience-ellenőrzés ezt importálja
   (READ-ONLY import, a fájl nem módosul), nem duplikál külön blocked-user
   logikát (ld. D7).
7. `backend/app/community` egyetlen alkönyvtára sem tartalmaz
   `__init__.py`-t a top-level `community/__init__.py`-n kívül (mérve:
   `find backend/app/community -maxdepth 2 -name __init__.py`) — a projekt
   implicit namespace package-eket használ. Az ÚJ `tasks/` és
   `moderation/` alkönyvtárak tehát NEM igényelnek külön `__init__.py`-t az
   `allowed_paths`-on.
8. Nincs account-suspension/ban mechanizmus SEHOL a backendben (mérve:
   `grep -rln "suspend\|account_action\|ban_user\|is_banned" backend/app` →
   nulla találat). A brief §5.1/A7 „súlyos account action" kitétele ezért
   ebben a körben nem hivatkozhat egy létező account-szintű műveletre — ld.
   D5 a pontos hatókör-lehatárolásért.
9. `backend/alembic/versions/` legfrissebb slotja `e09_r18_0012_community_media.py`
   (`revision = "e09_r18_0012"`, nincs `down_revision`-je más fájlnak) — a
   brief `e09_r19_0013_community_media_state.py` neve és a benne írandó
   `down_revision = "e09_r18_0012"` konzisztens, nincs drift.

## Döntés

**D1 — ADR-szám korrekció.** A brief előre kiosztott `0408`-a elavult (már
merge-elt bookmark-kör foglalja); ez az ADR `0412` néven készül, a
`tools/round-slots.py reserve-adr` friss foglalása szerint.

**D2 — `processing_state` ÚJ, KÜLÖNÁLLÓ oszlop a `CommunityMedia` táblán,
NEM az `upload_state` gép bővítése.** `backend/app/community/models/media.py`
kap egy második állapot-oszlopot:

```python
PROCESSING_STATE_UPLOADED = "uploaded"
PROCESSING_STATE_SCANNING = "scanning"
PROCESSING_STATE_TRANSCODING = "transcoding"
PROCESSING_STATE_REVIEW = "review"
PROCESSING_STATE_READY = "ready"
PROCESSING_STATE_REJECTED = "rejected"
PROCESSING_STATE_DELETED = "deleted"
```

`processing_state: Mapped[str]`, `nullable=False`,
`default/server_default=PROCESSING_STATE_UPLOADED` — pontosan az
`upload_state`/`moderation_state` mintát követve (String oszlop, DB nem
kényszeríti az átmenet-halmazt, a szolgáltatás/task-réteg az egyetlen
kényszerítő). A `processing_state="uploaded"` és az `upload_state="uploaded"`
két KÜLÖNBÖZŐ dimenzió (transzport vs. tartalom-feldolgozási pipeline) —
szándékos szóegyezés, nem funkcionális ütközés; a brief §3/§8 literál
értékkészletét szó szerint követi.

Az A6 acceptance ("a moderation döntés és a provider-verzió auditált")
további, nullable audit-oszlopokat igényel UGYANAZON a soron (a Kör 18
`checksum_sha256`/`expires_at`/`finalized_at` mintáját folytatva, nem külön
audit-tábla — nincs külön migrációs fájl az `allowed_paths`-on ehhez):
`moderation_decision` (String, nullable — a `resolve_review` végeredménye),
`moderation_confidence` (Float, nullable — a triage kimenete),
`moderation_provider` (String, nullable), `moderation_provider_version`
(String, nullable), `moderated_at` (DateTime(timezone=True), nullable). Az
oszlop-KÉSZLET (pontos nevek az implementer döntése lehet, a SZEREP kötött)
együtt **additív**: az `upload_state` gép, a hozzá tartozó indexek és
tranzíciók VÁLTOZATLANOK. Ez a `backend/app/community/models/media.py`
fájlt az `allowed_paths`-ra veszi, kizárólag additív terjedelemmel (ld.
brief §0.0 D2).

**D3 — Ebben a körben NINCS automatikus trigger-bekötés a finalize és a
feldolgozás-indítás között.** `media_upload_service.py` (Kör 18) nem
módosul. `backend/app/community/tasks/media_processing.py` tiszta,
közvetlenül hívható, session+sor-paraméteres függvényeket exportál
(`start_processing`, `run_malware_scan`, `run_transcode_check`,
`submit_for_review`, `resolve_review` — a pontos névválasztás az
implementer dolga), amiket a `test_media_processing.py` közvetlenül hív, a
Kör 18 `test_media_upload.py` mintájára (FastAPI `TestClient`/router
nélkül). A finalize → `start_processing` tényleges bekötése egy KÉSŐBBI,
router-wiring kör nyitott horga — a HANDOFF §6-nak ezt rögzítenie kell.

**D4 — Malware-scan és content-moderation: ABC + mock-adapter minta, a Kör 18
`ObjectStore` precedensét követve.** `backend/app/community/moderation/media_moderation.py`
absztrakt portokat definiál (pl. `MalwareScanner.scan(key) -> ScanResult`,
`ModerationProvider.triage(content_ref) -> ModerationDecision(confidence,
recommendation)`), és MOCK/benign implementációkat ehhez a körhöz (nincs
külső SDK, nincs hálózati hívás — a `requirements.txt` nincs
`allowed_paths`-on). A valódi providerek bekötése egy jövőbeli kör dolga,
ugyanúgy, ahogy az `S3CompatibleObjectStore` bekötése is nyitott horog
maradt Kör 18 után.

**D5 — Az automatikus triage SOHA nem állíthat be súlyos/terminális
állapotot közvetlenül; a „súlyos account action" ebben a körben a média
SAJÁT súlyos állapotátmenetére (`rejected`) korlátozódik, mert a backend ma
nem rendelkezik account-szintű felfüggesztési mechanizmussal (mérve,
Kontextus/8. pont).** A `media_moderation.py` triage-függvénye kizárólag
`confidence`+`recommendation`-t ad vissza és a hívót `review` állapotba
irányítja — SOHA nem hívhatja meg közvetlenül a `rejected` átmenetet. Egy
KÜLÖN, ember által hívott döntés-függvény (`resolve_review(db, media,
decision, reviewer_id)`) az EGYETLEN út `review → ready` vagy
`review → rejected` felé. A §6.1 valódi-sértés próba ezt méri: ha a
triage-eredmény közvetlenül `rejected`-et állítana be magas confidence
esetén (a human-review-gate megkerülésével), az A7 cellának PIROSRA kell
váltania.

**D6 — A signed playback URL alkalmazás-szintű, önálló aláírt token —
NEM az `ObjectStore`-on keresztül.** `media_access_service.py` egy saját
HMAC-SHA256 aláírt tokent állít elő és ellenőriz (média `public_id` +
lejárat + audience-claim), a projekt meglévő HMAC-SHA256 signed-cursor
mintáját követve (`following_feed.py`/`profile_search_repository.py`
precedens, Kontext-ADR 0410 D4 „egységes hash-family" elve). A valódi
bucket-oldali GET-signing (`ObjectStore` bővítése) és a HTTP-útvonal, ami
ezt kiszolgálná, egy KÉSŐBBI wiring-kör dolga — ugyanaz a minta, mint a Kör
18 router-deferrálása (ADR 0410 D3). A HANDOFF §6-nak ezt nyitott horogként
kell rögzítenie.

**D7 — Az audience-ellenőrzés a MEGLÉVŐ `access_policy.py`-t importálja,
nem duplikál blocked-user logikát.** `media_access_service.py`
`CommunityAccessPolicy.evaluate_content_access` + `RelationshipContext` /
`relationship_context_from_block_flag` függvényeket használja (read-only
import — a `policies/access_policy.py` fájl NEM kerül az `allowed_paths`-ra
és nem módosul).

**D8 — A metaadat-eltávolítás és a codec/duration/resolution/frame-rate
„korlátozás" hatóköre a stdlib-only korlátra szabott (Kontextus/5. pont).**
Az EXIF/GPS-eltávolítás stdlib-only bájt-szintű implementáció a fixture
formátum(ok)ra, amit a `test_media_processing.py` ténylegesen mér (A1) — a
brief §9 már névvel nevezi a nyitott kockázatot (pl. HEIC), ez a kör nem
állít teljes formátum-lefedettséget. A codec/duration/resolution/frame-rate
„korlátozás" a KLIENS-DEKLARÁLT `content_type`/`duration_ms`/(a kör által
bevezetett) resolution/frame-rate mezők allowlist- és
határérték-ellenőrzése — a Kör 18 MIME/size deklaráció-ellenőrzés
mintájával azonos terjedelem, NEM valódi bináris dekódolás/transzkódolás.
A `transcoding` `processing_state` egy pipeline-lépés protokoll-jelölése
ebben a körben, nem tényleges bitfolyam-átkódolás.

## Következmények

- A HANDOFF §6-nak KÉT nyitott horgot kell rögzítenie a következő
  köröknek: (1) `media_upload_service.finalize_upload` → `tasks.media_processing.start_processing`
  tényleges bekötése; (2) `media_access_service` HMAC-tokenjének cseréje/
  kiegészítése valódi bucket-oldali GET-signingre (`ObjectStore` bővítés)
  + a HTTP route mountolása — ugyanaz a tartozás-osztály, mint a Kör 18
  router/`S3CompatibleObjectStore` nyitott horgai.
- Egy jövőbeli kör, ami valódi account-szintű felfüggesztést vezet be,
  KÖTELES megőrizni a D5 human-review-gate elvét (triage sosem dönt
  egyedül súlyos ügyben) — ez a §18.4 SDD-invariáns, nem csak ennek a
  körnek a szabálya.
- Ha egy jövőbeli kör a `requirements.txt`-et is `allowed_paths`-ra veszi
  és valódi kép/audio/videó-feldolgozó könyvtárat vezet be, a D8 alatt
  dokumentált „deklaráció-ellenőrzés" léphet át valódi bináris
  validációra — a jelen kör kontrollcellái (§6.1) enélkül is helytállóak
  maradnak, mert a klienstől kapott adatot ellenőrzik, nem föltételezik a
  valódi dekódolást.
