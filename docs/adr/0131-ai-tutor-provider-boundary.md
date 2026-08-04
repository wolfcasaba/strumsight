# ADR 0131 — AI Tutor provider-boundary

- **Státusz:** Elfogadva (E04-R01 pre-flight, 2026-08-04)
- **Kör:** E04-R01 — AI Tutor baseline, ADR-ek és feature flagek
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md)
- **Kontext-ADR-ek:** [0132](0132-ai-tutor-privacy-and-consent.md),
  [0133](0133-ai-tutor-tool-confirmation.md),
  [0134](0134-ai-tutor-memory-policy.md)

## Kontextus

Az Epic 4 egy beszélgetéses AI gitártanárt vezet be, amely determinisztikus
on-device coachingból és opcionális cloud model-hívásból dolgozik (SDD Ch5 §1,
§20). A cloud-oldal a StrumSight backenden (R14) keresztül fut, nem a kliensből
közvetlenül. A kockázat, hogy egy konkrét model-provider SDK típusai
(kérés/válasz DTO-k, hibaosztályok, token-fogalmak) beszivárognak a tutor
domainbe vagy a kliensbe, provider-lock-int és tesztelhetetlen határt hoznak
létre.

Mért kiindulás (baseline `main` @ `8d70232`, E04-R01 pre-flight):
`lib/features/ai_tutor/` **nem létezik** (greenfield). Ez a kör kizárólag üres
publikus boundaryt (`lib/features/ai_tutor/public.dart`) és a rollout-flageket
hozza létre; provider-integráció még nincs.

## Döntés

1. Az AI Tutor **providerfüggetlen**. A tutor domain és a Flutter kliens soha
   nem hivatkozhat egy konkrét model-provider SDK típusra. A model-hívás a
   StrumSight backenden át történik (R14); a kliens csak a backend saját,
   provider-semleges contractját ismeri.
2. A `lib/features/ai_tutor/public.dart` a feature egyetlen publikus felülete.
   Nem importálhat más feature belső rétegét (`/domain/`, `/data/`,
   `/application/`, `/presentation/`), és nem exportálhat provider-specifikus
   típust.
3. A provider kiválasztása, kvótája és hibakezelése backend-oldali,
   konfigurációval cserélhető döntés — nem szivárog a domain modellbe.

## Következmények

- A későbbi körök (R02+) a tutor domain modelljét provider-semleges
  típusokkal építik; a cloud gateway (R14) a backend contract mögé rejti a
  provider SDK-t.
- A boundary-tesztet (`test/features/ai_tutor/ai_tutor_boundary_test.dart`)
  ez a kör vezeti be: bizonyítja, hogy a `public.dart` nem húz be idegen belső
  fájlt. Ez az invariáns nem gyengíthető „csak egy belső import" kivétellel.
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen.
