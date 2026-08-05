# Review — E04-R17 Conversation repository, summary & inspectable memory

- **Verdikt:** APPROVED (javító kör #1 után — `6830e63`)
- **Branch:** `codex/e04-r17-conversation-repository-and-memory`
- **Implementer commit:** `749c081` (parent / pre-flight base `f4560ba`)
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude (Opus 4.8), független read-only review (ADR 0055)
- **Dátum:** 2026-08-05

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=749c081`, `scope_audit=ok`
(`scope_audit_changed=9`), gate zöldet jelez. A working tree tiszta
(`git status --porcelain` üres); a jelzésbeli `dirty_files=1` a
`.codex-round-status` önírása a jelzés pillanatában — nem szivárgott listán
kívüli production fájl. A brief §10 handoff kitöltve, RED→GREEN úttal.

## 2. Gate-újrafuttatás (izolált /tmp klón, saját kézzel)

`git clone` a kör-branchről → `/tmp/review-e04-r17` (HEAD `749c081`),
`tools/prepare-flutter-generated.sh`, majd `tools/round-gate.sh test/features/ai_tutor/data`:

| Lépés | Eredmény |
|---|---|
| format | ZÖLD |
| analyze | ZÖLD |
| test `test/features/ai_tutor/data` | ZÖLD |
| architecture | ZÖLD (12 allowlisted deviation) |
| secrets | ZÖLD (1715 fájl, 0 finding) |
| l10n | ZÖLD (en→hu, 720 message) |

A gate a szöveges bemondás helyett futtatott artefaktum — mind zöld.

## 3. Scope-audit

A wrapper gépi audit `scope_audit=ok`. A 9 megváltozott fájl mind a §0.0
revízió UTÁNI engedélyezett listán van; `public.dart` **nincs** módosítva
(az `ai_tutor_boundary_test.dart` üres-boundary invariáns zöld marad). Tilos
zóna nem sérült.

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték |
|---|---|
| Atomikus save | Egykulcsos envelope-írás (`_writeDocuments`/`_writeFacts` egy `writeString`); nincs részleges dokumentum. |
| Index-recovery | Teszt: `tutorConversationIndex` write hibázik → `save` `Failure`, de a dokumentum megmarad, a `list` visszaépíti az indexet a dokumentumokból. |
| Pagination | Teszt: `offset:1, limit:1` → helyes item, `offset`, `total=3`, `hasMore=true`. |
| Summary provenance | Teszt: minden üzenet `messageId`/`role`/`sequence` provenance-e, tartalommásolás nélkül. |
| Memory dedup | Teszt: normalizált fingerprint (`  prefers   slow practice. ` == `Prefers slow practice.`) → a meglévő fact tér vissza. |
| Sensitive reject | Teszt: `My password is forest-123.` → `ValidationFailure`, semmit nem perzisztál. |
| Retention (purge) | Teszt: lejárt fact `purgeExpired` után eltűnik, a friss marad. |
| Redacted export | Teszt: `content:'[redacted]'`, a nyers tartalom nincs az exportban. |
| Delete-all üríti a kulcsokat | Teszt: `StorageKeys.tutorAiData` + karantén mind törölve. |
| Corrupt-record izolált | Teszt: egy sérült rekord karanténba kerül, a jó beszélgetés olvasható marad. |
| Restart-load | Teszt: friss repository ugyanarról a store-ról betölti a mentett beszélgetést. |
| Tár-írási hiba → `AppResult.failure`, nem néma | Teszt mindkét repóban: `failingKeys` → `Failure(StorageFailure, storageWrite)`. |

## 5. Próbateszt (eldobható) — falszifikációs guard független ellenőrzése

A /tmp klón production `deleteAllAiData` ciklusát ideiglenesen
`StorageKeys.tutorAiData.take(2)`-re rontottam (a `tutorMemoryFacts` kulcsot
kihagyva), és lefuttattam a memory tesztet:

```
+4 -2: Some tests failed.
  delete all removes every declared tutor key and its quarantine key  → RED
  does not report success when a delete all removal is refused        → RED
```

A mutáció **két** cellát váltott pirosra — a delete-all a teljes kulcshalmazt
méri (nem stub-siker), a silent-no-op cella pedig a valódi hiba-utat. A klón
eldobható; a fő branch érintetlen. A guard tehát valódi.

## 6. Architektúra + termékhatárok

- A data-réteg keretfüggetlen a domain felé: a repók a `core/foundation` +
  `core/storage` + a saját domain contract/codec ellen dolgoznak; nincs
  Riverpod-provider vagy plugin-import ebben a körben (a wiring későbbi kör).
- `public.dart` érintetlen — a feature-határ zárt marad (R22 UI-ra halasztott export).
- Silent-no-op tilalom betartva: minden write-út `StorageException`-t propagál
  `StorageFailure`-ré; a `StorageException.toString` szándékosan érték-mentes,
  a repók nem logolnak nyers tartalmat.

## 7. Leletek

| # | Osztály | Fájl:sor | Megállapítás | Állapot |
|---|---|---|---|---|
| M1 | MAJOR | `local_tutor_memory_repository.dart:285–289` | **Sensitivity-filter phone-bypass.** A `\b\+?\d[\d ()-]{6,}\d\b` karakterosztály nem tartalmaz `.`-ot, ezért egy pont-tagolt telefonszám (`555.123.4567`) átcsúszik és nyersen a `ss.tutor.memory_facts`-be kerül — pedig a brief §5.3 + ADR 0134 nevesített kategóriaként (telefon/e-mail) elutasítást ír elő. Az e-mail/telefon ág **teszttel nem fedett** (`local_tutor_memory_repository_test.dart:53` csak a `password` keyword-utat méri). Irány: a szeparátor-halmaz bővítése (`.`/`/`/unicode) vagy normalizálás matching előtt, + fixture/property teszt e-mailre és több telefon-formátumra. | OPEN → javító kör |
| M2 | MAJOR | `local_tutor_conversation_repository.dart:145` | **Őrizetlen top-level `jsonDecode`.** A `_objectMap(jsonDecode(raw))` nincs try-ban. Egy sérült/csonka top-level dokumentum-blob `FormatException`-t dob → minden hívás (`get`/`list`/`save`/`delete`) tartósan `StorageFailure`-t ad, karantén/reset NÉLKÜL → a store véglegesen olvashatatlan a `deleteAllAiData`-ig. Ez ellentmond a `storage_keys.dart:74–81` „corrupt user content is isolated, never dropped" garanciájának, és **aszimmetrikus** a memory repóval, amely az azonos esetet helyesen kezeli (`local_tutor_memory_repository.dart:173–190`: try/catch → quarantine → reset). Ráadásul a `FormatException` a nyers forrásból (üzenet-tartalom) hordoz részletet a `StorageFailure.cause`-ba. **Teszttel nem fedett** (a korrupt-teszt csak érvényes envelope-on belüli rekordot ront). Irány: a 145. sor decode+`_objectMap` try/catch-be → `_quarantineDocument(raw)` + reset + üres lista; + teszt csonka top-level blobra (recovery + a cause ne hordozzon tartalmat). | OPEN → javító kör |
| N1 | NOTE | `local_tutor_memory_repository.dart:183–190` | A memory `_readFacts` **egyetlen** sérült fact-rekordnál a teljes blobot karanténba teszi és üríti az élő listát (a conversation repo rekord-szintű izolációt ad). Adat nem vész el (karanténban marad). Követő kör: rekord-szintű memory-izoláció. Nem blokkol. |
| N2 | NOTE | `local_tutor_conversation_repository.dart:146–148` | Ismeretlen/jövőbeli `schemaVersion` → üres lista **karantén nélkül**; egy rákövetkező `save` felülírná a nem-migrált blobot. A brief §5.4 „jövőbeli schemaVersion kihagyva (E02-R18 minta)" előírását követi, v2 séma ma nincs. Jövőbeli séma-emeléskor karanténba kell tenni. Nem blokkol. |
| N3 | NOTE | `local_tutor_memory_repository.dart:156–168` | `deleteAllAiData` nem atomikus: ciklus közbeni `StorageException` a korábbi kulcsokat törölve hagyja, a későbbieket bent. `remove` idempotens (retry befejezi), de a hívó retry-ja nem garantált. Megfontolandó: continue-on-error aggregált hibával. Nem blokkol. |

**OPEN: 2 MAJOR (M1, M2).** Javító kör indul ugyanazzal a motorral (Codex).
A NOTE-ok follow-up jellegűek.

### 7.1 Javító kör #1 — leletek zárása (`6830e63`, scope_audit=ok, 5 fájl)

| # | Zárás | Bizonyíték |
|---|---|---|
| **M1** | ZÁRVA | `_isSensitive` telefon-osztálya bővült: `[\d ./()\- ]{6,}` + `(?:^|[^\w])` horgony. Új cellák: `rejects an email candidate` és `rejects a dotted phone candidate` (`555.123.4567` → `Failure`/`ValidationFailure`, `list` üres). A `{6,}` hossz-küszöb megmaradt (rövid szám-tartalom nem vált téves riasztást). |
| **M2** | ZÁRVA | A top-level `jsonDecode`+`_objectMap`+schemaVersion/items ellenőrzés **try/catch**-be került → bármely hiba `_quarantineDocument(raw)` + üres lista (a memory repo mintája). Új cella: `quarantines an invalid top-level document and recovers with an empty page` (`{not json` → `Success` üres oldal + karantén). Mellékhatásként az N2 (ismeretlen schemaVersion csendes eldobás) is megszűnt: most karanténba kerül. |
| N1/N3 | follow-up | Rekord-szintű memory-izoláció és atomikus delete-all — nem blokkoló, későbbi kör. |

A javító diff kizárólag a két repo-implt, a két tesztet és a brief §10-et
érinti; `public.dart` érintetlen. A gate-et friss `/tmp` klónon
(HEAD `6830e63`) újrafuttattam.

**OPEN BLOCKER/MAJOR/MINOR: nincs.** Verdikt: **APPROVED**.

## 8. Security/privacy review

Külön `security-reviewer` ágens futott (risk=high: user-adat tárolás, törlés,
sensitivity-filter). Eredmény: lásd §8.1 lentebb.

### 8.1 security-reviewer verdikt

Nincs CRITICAL/BLOCKER. **Két MAJOR** (M1 phone-bypass, M2 top-level decode) —
a fenti §7 táblába emelve, javító kör tárgya. Külön igazolt-tiszta (bizonyítékkal):
delete-all teljesség (`tutorAiData` + minden karantén-kulcs törölve), redaktált
export (nincs content-szivárgás, karantén-kulcsokat nem olvas), silent-no-op
tilalom (minden write-út `StorageFailure`-t propagál), exception-hygiene
(`StorageException`/`AppFailure` `toString` érték-mentes, nincs nyers-content log),
nincs provider-típus/nyers audió a perzisztált adatban. NOTE-ok: keyword-only
filter nem fog bare secret-értéket (N1 az ADR 0134 keyword-modell velejárója),
karantén-blob nincs redaktálva on-device (elfogadható izoláció), deleteAllAiData
nem atomikus (§7 N3).

## 9. Merge-döntés

A zöld kapu (ADR 0052) minden eleme a kör-branch merge-SHA-ján:
- full-gate.yml (format+analyze+architecture+secret+l10n+teljes teszt+property+coverage) — a végső HEAD-en zöldnek kell lennie (orchestrátor dispatch),
- router-ci.yml — a merge-SHA-n `success` (a diff `docs/rounds/**`-t érint).

Exact-SHA szabály: a review-commit után a végső HEAD-en újra-dispatch. Zöld
kapu + nulla OPEN BLOCKER/MAJOR → squash-merge.
