# E09-R19 — Biztonsági / privacy / moderation review

- **Kör:** E09-R19 — Média feldolgozás, privacy és moderation state
- **Reviewer:** Claude (dedikált biztonsági review, READ-ONLY, `security-reviewer` agent)
- **Branch:** `minimax/e09-r19-media-processing-privacy-and-moderation-state`
- **Review HEAD:** `52cbeb33` (kör-commit `d278c31b`, alap `6d1216bf`)
- **ADR:** 0412 · **Risk:** high
- **Verdikt:** **PASS** — 0 BLOCKER, 0 MAJOR. Minden lelet MINOR/NOTE, mind
  latens az UNWIRED határ mögött, névvel nevezett seam-ekkel.

> Ez a review a §-os általános review-tól (`e09-r19-review.md`) FÜGGETLENÜL
> készült — külön izolált klón, egyeztetés nélkül (L214 minta).

## Ellenőrzés-összegző

- **Flutter gate-teszt** (`community_media_player_test.dart`): 8/8 zöld.
- **Backend media pytest** (`test_media_processing.py`): 30 zöld.
- **Regressziós részhalmaz** (migration-contract + access-policy + media +
  Kör 18 upload): 103 zöld, 1 xfailed, 0 piros — az additív modell+migráció
  nem regresszált.
- **A7 valódi-sértés próba (saját kézzel lefuttatva):** a `triage()`-be
  injektált gate-megkerülés (magas-confidence `reject` → közvetlen
  `_set_processing_state(..., REJECTED)`) hatására a
  `test_a7_real_violation_probe` PIROSRA váltott; `git checkout --` után
  4/4 zöld. A human-review-gate strukturálisan az egyetlen út `rejected`-be.
- **Token tamper/replay próba (saját kézzel):** mind a 6 tengely (lejárat-
  hosszabbítás, sor-keresztes replay, rossz secret, audience-bukás, lejárt
  token) elutasítva — a HMAC az expiry-t ÉS a `public_id`-t is köti,
  `hmac.compare_digest` konstans idejű, TTL 30 percre clamp-elve.
- **EXIF próba (saját kézzel):** realisztikus, több-szegmenses JPEG
  (JFIF + EXIF/GPS + SOS + entropy-adat) → az APP1 és a GPS-bájtok
  eltávolítva, a JFIF/scan-data megmarad. Valódi bájt-szintű strip.
- **Scope-határ:** a kör-commit diffje a 4 tiltott fájlra (`media_upload_service.py`,
  `object_store.py`, `access_policy.py`, `requirements.txt`) + `docs/adr/**`
  ellen **üres** — nincs jogosulatlan S3-signing-felület bővítés.

Az egész kör **BEKÖTETLEN** (mérve: `grep` a `backend/app/`-ban — nulla
fogyasztó, nincs router-mount), ami minden latens leletet a jövőbeli
wiring-kör mögé told.

## 1. Bizonyítottan rendben lévő biztonsági kontrollok

- **HMAC-SHA256 token** (`media_processing.py:482-556`,
  `media_access_service.py:154-303`): konstans-idejű `hmac.compare_digest`
  (`media_processing.py:524`, `media_access_service.py:298`); az expiry a
  payloadba kötve ÉS verify-időben ellenőrizve (`expires_at <= now`,
  `media_processing.py:526`); TTL cap `MAX_PLAYBACK_TTL = 30 min`
  clamp-elve (`media_access_service.py:191-193`); a `secret` kötelező
  paraméter, default nélkül → fail-closed.
- **Blocked-user kényszer** (`access_policy.py:193-196`): a `blocked` az
  audience-ellenőrzés ELŐTT fut, ezért a `_resolve_audience` PUBLIC-default
  ellenére is denied; a verify újrafuttatja (`media_access_service.py:238-242`).
- **EXIF/GPS strip valódi** (`media_processing.py:206-280`).
- **Nem-ready expozíció zárt**: `is_playable` csak `ready` (`media_processing.py:458-467`);
  issue/verify `MediaNotPlayable` nem-ready sorra; a Flutter widget nem-ready
  állapotban semmilyen URL/kulcs/lejátszó nélkül (`community_media_player.dart:94-104`).
- **Scope-boundary**: a kör-commit diffje a 4 tiltott fájlra üres.
- **Migráció** (`e09_r19_0013`): additív-only, helyes `down_revision`,
  szimmetrikus downgrade.
- **Model** (`models/media.py`): additív; az `upload_state` gép + indexei
  érintetlenek.

## 2. Leletek

**MINOR-1 — `_resolve_audience` hardcode PUBLIC → az A4 followers-tengelye
nem kényszerített/tesztelt.** `media_access_service.py:130-146`; tesztek
`test_media_processing.py:499-568` (csak `blocked`). Latens hiba: egy
jövőbeli FOLLOWERS-only médiánál egy nem-blokkolt, nem-követő néző
`evaluate_content_access(PUBLIC, non_follower)` → `True` → tokent kap. Az A4
audit túlállítja a lefedettséget (§5.5). Ma NEM MAJOR: bekötetlen, nincs
audience-oszlop, nincs hívó → nem reprodukálható. Sértett szabály: A4/§5.5.
Javasolt: a wiring-kör kösse be a valódi audience-t + adjon
„non-follower + FOLLOWERS → denied" tesztet — a wiring-kör BLOKKOLÓ
előfeltétele legyen.

**NOTE-1 — az EXIF-strip nincs bekötve pipeline-átmenetbe.**
`media_processing.py:206`, nulla hívó. Az A1 a függvényt izoláltan méri;
egy jövőbeli wiring, ami elfelejti hívni a stripet `ready` előtt, attól még
zöld A1-et látna. Javasolt: a wiring-kör ténylegesen hívja a stripet +
bővítse az A1-et a meghívás assertálására.

**NOTE-2 — elutasított/lejárt token a kivétel-üzenetben.**
`media_access_service.py:261,285,291,297,299,301`
(`MediaTokenInvalid(token)`/`MediaTokenExpired(token)`). Csak
már-elutasított token jut ide, így az érték használhatatlan; alacsony súly.
Javasolt: fix ok-string a nyers token helyett.

**NOTE-3 — `moderated_at` minden átmenetnél felülíródik.**
`media_processing.py:354` (`_set_processing_state` mindig stampeli) —
a `start_processing`/`run_malware_scan` is írja, holott „utolsó moderációs
írás" bélyege. A6 audit-fidelity kérdés, nem rés. Javasolt: csak
`triage`/`resolve_review` írja.

**NOTE-4 — `deleted` terminál állapot elérhetetlen az állapotgépből.**
`media_processing.py:319-335` (`_PROCESSING_TRANSITIONS`-ben nincs
`(*, deleted)` él, a komment ellenére). Fail-safe (nem lehet véletlen
átmenet), nem rés. Javasolt: explicit `tombstone()` vagy a komment javítása.

**NOTE-5 — secret-provenance halasztva.** `media_access_service.py:159,211`
(`secret: str` default nélkül → fail-closed); production forrás még nincs
bekötve. Javasolt: a wiring-kör `Settings`-ből olvasott magas-entrópiájú
secretet adjon, sose üreset/hardcode-ot.

## 3. Verdikt

**PASS.** 0 BLOCKER, 0 MAJOR. Minden lelet (1 MINOR + 5 NOTE) latens az
UNWIRED határ mögött, névvel nevezett seam-ekkel; a MINOR-1 a jövőbeli
poszt-attachment/wiring-kör explicit előfeltételeként blokkoló ott, nem itt.
