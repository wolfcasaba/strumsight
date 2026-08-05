# ADR 0135 — Tutor knowledge governance

- **Státusz:** Elfogadva (E04-R06 pre-flight, 2026-08-05)
- **Kör:** E04-R06 — Kurált tutor tudásbázis schema és első content pack
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md)
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md) (provider-boundary),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy/consent),
  [0134](0134-ai-tutor-memory-policy.md) (memory)

## Kontextus

Az Epic 4 AI gitártanárának determinisztikus, on-device coachinghoz és
opcionális cloud-prompt-körökhöz (R12/R16) egy **felhasználói célú**, kurált
gitároktatási tudásbázisra van szüksége (SDD Ch5 §3.2, §6, §7): ritmus, akkord,
technika, gyakorlás és biztonság témákban.

A repóban már van egy `docs/rag/chunks/` korpusz, de az **fejlesztői DSP/ML
anyag** (AGENTS.md §9: „Modell assethez checksum, model card, exportverzió és
licence-adat tartozik", és a DSP-hangolás forrása) — NEM tanulói tartalom, és
NEM másolható a tutor tudásbázisba. A tutor-tartalom felhasználóknak jelenik
meg, ezért jogtisztaságot, verziózást és emberi review-t igényel, amit a
fejlesztői RAG nem garantál.

Mért kiindulás (baseline `main` @ `5180d08`, E04-R06 pre-flight):
`assets/tutor_knowledge/` **nem létezik** (greenfield); nincs approval-lifecycle
vagy manifest-hash konvenció tutor-tartalomra; a `lib/features/ai_tutor/data/`
csak a `local/` codeceket tartalmazza (`tutor_profile_codec.dart`,
`tutor_conversation_codec.dart`). A `lib/features/ai_tutor/public.dart` **üres**
boundary marad (ADR 0131 §2, a `ai_tutor_boundary_test.dart` nulla-export
invariánsa E04-R02..R05 óta).

## Döntés

1. **Szigorú elkülönítés.** A felhasználói tutor knowledge pack fizikailag és
   fogalmilag külön él a `docs/rag` fejlesztői DSP-anyagtól. A `docs/rag`
   olvasható precedensként, de **automatikus vagy kézi másolása TILOS**
   (AGENTS.md §9). A tutor-tartalom kizárólag saját szerzésű vagy bizonyítottan
   jogtiszta, license-mezővel ellátott dokumentum lehet; jogvédett tab/lyrics
   TILOS (ADR 0132 adatvédelmi vonalával összhangban).

2. **Verziózott, hash-lezárt dokumentumok.** Minden `KnowledgeDocument`
   determinisztikus mezőkészletet hordoz: `id`, `locale`, `skill`,
   `difficulty`, `license`, `version` és tartalmi **hash**. A chunkolás
   determinisztikus, így a build reprodukálható (kétszeri futtatás bit-azonos
   manifest + chunk kimenet). Óra, véletlen és lebegőpont a build-úton TILOS.

3. **Approval-lifecycle és approved-only production build.** Minden dokumentum
   pontosan egy állapotban van: `approved`, `reviewNeeded` vagy `rejected`. A
   **production manifest kizárólag `approved` dokumentumot tartalmazhat**;
   `reviewNeeded`/`rejected` dokumentum a production buildbe kerülése hiba. A
   szűrés **erős egyenlőség** (`status == approved`), nem enyhébb predikátum —
   egy `reviewNeeded` átcsúszása mutációs próbával RED.

4. **Fail-loud manifest-validáció.** A manifest-építés négy hibaosztályt
   **külön, stabil hibakóddal** utasít el: duplicate document ID, hiányzó
   license, hash mismatch (a tárolt hash ≠ az újraszámolt tartalmi hash), és
   corrupt/olvashatatlan content. Néma átugrás vagy összevont hiba nem
   elfogadható.

5. **CI-integritás.** A CI ellenőrzi a manifest + chunk hasheket és a
   reprodukálhatóságot; a `pubspec.yaml` assets-bővítése additív, és az
   asset-gate alatt fut.

## Következmények

- A tutor-tartalom bővítése **emberi review-t** igényel: új dokumentum
  `reviewNeeded` státuszban születik, és csak explicit review után válik
  `approved`-dá — így kerül be a production manifestbe.
- A retrieval/index réteg (R07) és a prompt-körök (R12/R16) erre a
  hash-lezárt, approved-only manifestre épülnek; ez a kör **csak a schema-t, a
  determinisztikus build-tool-t és az első content packet** szállítja, hívó
  nélkül (greenfield, `public.dart` üres marad → production viselkedés
  változatlan).
- A determinisztikus, hash-alapú kontraktus regressziót fog: ha egy jövőbeli
  kör megbontja a chunkolást vagy a hash-számítást, a reprodukálhatósági és a
  hash-mismatch teszt azonnal pirosra vált.
