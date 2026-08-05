# ADR 0139 — AI Tutor action proposal & confirmation mechanics

- **Státusz:** Elfogadva (E04-R11 pre-flight, 2026-08-05)
- **Kör:** E04-R11 — Action proposal, validáció és confirmation service
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 11
- **Szülő-ADR:** [0133](0133-ai-tutor-tool-confirmation.md) (kétlépcsős write/launch confirm)
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md), [0137](0137-ai-tutor-readonly-tool-contract.md)

## Kontextus

Az [ADR 0133](0133-ai-tutor-tool-confirmation.md) rögzítette a **döntést**: minden
write/launch típusú tutor-action kétlépcsős (előnézet → explicit megerősítés), és a
megerősítés nem kerülhető meg AI-oldali auto-confirm jelzéssel. Ugyanez az ADR a
**gépezet** felépítését kifejezetten az R11 körre halasztotta ("az action-proposal +
preview + confirm gépezet a R11 körben épül"). Ez az ADR az R11 konkrét
mechanizmus-döntéseit rögzíti — nem lazítja, hanem megvalósítja a 0133-at.

A route-katalógus (`lib/app/routing/app_route.dart`) ma `AppRoutes` **String-konstans**
gyűjtemény; nincs typed route-enum. Egy tévesztett vagy manipulált model-válasz, ha nyers
route-stringet adhatna át, tetszőleges képernyőre navigálhatna a felhasználó tudta nélkül.

## Döntés

1. **Nincs automatikus write/launch végrehajtási út a kódban.** A profile-update,
   plan-save és session-launch action-ök kizárólag egy `ActionConfirmationService`
   kétlépcsős folyamatán át futhatnak: `propose → (preview) → confirm`. „Biztonságosnak
   ítélt" action auto-futása nem elfogadható (ADR 0133 megerősítése).
2. **A launch-cél typed capability, soha nem nyers model-string.** A tutor-action egy
   typed capability-t hordoz; a capability → konkrét `AppRoutes`-útvonal/hatás kötés a
   modell-bemeneten **kívül** történik. A production-navigáció R19-re halasztott; itt fake
   executorok. Nyers route-string átadása validátor-elutasítás.
3. **Idempotens végrehajtás `clientActionId` alapján.** Egy megerősített action kétszeri
   végrehajtása (double-tap/retry) **egyetlen** hatást ad; a második hívás no-op a már
   ismert `clientActionId`-re.
4. **Stale-action policy — a proposal érvényességi alapot rögzít, a confirm újraellenőrzi.**
   A proposal az érvényesség alapját (pl. song-revision token, expiry, szükséges capability)
   pillanatfelvételként tárolja. Confirm-időben: revision-eltérés / lejárt expiry /
   elveszett capability / törölt session → **blokkolt**, nem hajtódik végre.
5. **Az action-domain providerfüggetlen (ADR 0131).** Nem importál más feature belső
   contractot és nem importálja az `lib/app/routing/*`-ot; a capability opaque, a revision
   opaque token.

## Következmények

- Az R11 diff a `lib/features/ai_tutor/{domain/models,application/orchestration}` alatt
  épül; a tesztek bizonyítják, hogy megerősítés nélkül nincs állapotváltozás, a stale/nem-
  idempotens/nyers-route utak pirosak.
- A production-navigáció és UI (R19) egy későbbi kör; itt a fake executorok mérik a
  szerződést.
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen — a reviewer eldobható
  mutációval (nyers route-string átengedése, auto-execute) pirosra váltja.
