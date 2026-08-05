# ADR 0137 — AI Tutor read-only tool contract & registry

- **Státusz:** Elfogadva (E04-R10 pre-flight, 2026-08-05)
- **Kör:** E04-R10 — Tutor Tool contract és read-only registry
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 10 (§35)
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md), [0132](0132-ai-tutor-privacy-and-consent.md),
  [0133](0133-ai-tutor-tool-confirmation.md)

## Kontextus

A tutor a redaktált kontextusból (E04-R05) számol és olvas. Ahhoz, hogy a
model **eszközöket** hívhasson (számítás, lekérdezés a már összeállított
kontextus fölött), egy typed, tesztelhető tool-rendszer kell. A kockázat az,
hogy egy tévesztett vagy **manipulált** model-válasz mellékhatást vagy
adatszivárgást okozzon: fájlt írjon, hálózatot hívjon, kódot futtasson, vagy
olyan toolt hívjon, amit a jelenlegi lépés nem engedélyez.

Az [ADR 0133](0133-ai-tutor-tool-confirmation.md) a **write/launch** oldalt
szabályozza: minden állapotmódosító vagy sessiont indító action kétlépcsős
(előnézet + explicit felhasználói megerősítés, R11). Ez az ADR a **komplementer
olvasó/compute oldalt** rögzíti: milyen tool-rendszert kap a model *megerősítés
nélkül*. ADR 0133 §2 szerint tisztán olvasó/magyarázó művelet nem igényel
megerősítést — de csak akkor biztonságos, ha a tool-készlet **bizonyíthatóan**
mellékhatás-mentes.

## Döntés

1. **Szigorúan read-only + lokális compute.** A kezdeti (és minden R10-ben
   szállított) tool kizárólag a már összeállított kontextust olvassa vagy
   determinisztikusan számol fölötte. **Tilos** bármely arbitrary file-,
   network- vagy code-execution tool — „csak egy" ilyen tool sem elfogadható.
   Állapotmódosító/sessiont indító művelet az R11 kétlépcsős action-rendszeréé
   (ADR 0133), nem tool.

2. **Fail-closed, turn-specifikus allowlist.** Ismeretlen (nem regisztrált vagy
   az adott lépésre nem engedélyezett) tool hívása **fail-closed**: a registry
   nem hajtja végre, normalizált hibát ad. A model minden fordulóban csak a
   **turn-specifikus** allowlistet látja, nem a teljes registry-t.

3. **Verziózott registry + explicit input-validáció.** A registry verziót hordoz
   (kompatibilitási contract). Minden tool a bemenetét belépéskor validálja;
   invalid input **elutasítás**, nem best-effort futás.

4. **Provider-független schema.** A tool permission + schema leírás nem köt
   semmilyen konkrét LLM-szolgáltatóhoz (ADR 0131 boundary).

5. **Provenance + size-limit minden outputon.** Minden tool-kimenet forrás-
   jelölést (provenance) és méret-jelentést hordoz. A méretlimit fölötti kimenet
   **jelentse** a túllépést (a tool result modelljében), nem **csendben**
   csonkolja. Titok/redaktált mező nem szivároghat ki (no-secret-output).

6. **Hiba normalizálva `AppFailure`-ré.** A tool-futás során dobott kivétel nem
   nyers `throw`-ként terjed, hanem a Core `AppResult`/`AppFailure` contractra
   (Epic 1, `lib/core/foundation/`) képződik le a **meglévő** hibakódokkal
   (invalid/permission/unknown-tool → `ValidationFailure`; váratlan kivétel →
   `UnknownFailure`). Új `FailureCode` nem kerül ebbe a körbe — a
   `lib/core/foundation/` a kör scope-ján kívül van. A tool-specifikus kimeneti
   állapotok (oversized-report, timeout, provenance) a tool **saját** result-
   modelljében élnek, nem a globális `FailureCode`-listában.

## Következmények

- A tool-rendszer greenfield és hívó nélküli: az orchestration (R12/R16), a
  launch/action (R11) és az UI (R19) fogyasztja később. Ez a kör a
  **contractot + a read-only tool-készletet + a fake registry-t** szállítja.
- A security-allowlist **teszttel** bizonyított: reviewer egy eldobható
  mutációval (egy network/file/code tool hozzáadása) pirosra tudja váltani.
- Ez a döntés nem lazítható azért, hogy egy „hasznos" write/network tool
  beférjen, vagy hogy egy teszt zöld legyen — a kísértést az R11 kezeli.
