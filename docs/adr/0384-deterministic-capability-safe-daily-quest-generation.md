# ADR 0384 — Determinisztikus, capability-safe napi quest generálás

- **Státusz:** elfogadva (E08-R17 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R17` — Napi quest generátor
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0352`](0352-qualified-day-planned-rest-and-recovery-policy.md),
  [`0382`](0382-quest-objective-and-lifecycle-contract.md)

> **Számozási megjegyzés:** az előre írt brief `0313`-at nevezett meg, de az
> már az elfogadott kör-landolási ADR száma. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R17` futás `0384`-et adott;
> a foglaló mért eredménye az irányadó, az ADR 0313 változatlan marad.

## Kontextus

A napi quest egyszerre támaszkodik a verziózott R16 quest domainre, az Epic 7
napi tervére és környezeti képességekre. Ha maga a generátor olvas órát,
permission gatewayt, accountot vagy hálózatot, a kimenet nem reprodukálható,
tesztben pedig könnyen burkolt engedélykérés vagy online függőség keletkezik.

A production terv pihenőnapját a `ScheduleDecisionReason.restDay.code` alapján
a `TodayPlanController` `TodayPlanMode.restDay` állapotként adja. A kamera
permission contract külön read-only `currentState()` és explicit user-action
`request()` műveletet tartalmaz. A generátornak egyik erőforrást sem kell és
nem is szabad birtokolnia.

## Döntés

1. **Caller-fed, immutable snapshot.** A generátor egy teljes, immutable napi
   snapshotot kap: `QuestSchedule`, stabil profile snapshot key, opcionális
   terv-objective-ek, planned-rest állapot, valamint kamera-, fiók- és
   cloud-availability. Nem olvas órát, repositoryt, permission plugint vagy
   hálózatot, és nem módosítja a tervet.

2. **Típusos katalógus-metaadat.** A verziózott katalóguselem stabil ID-t,
   típusos `QuestObjective`-et és `QuestReward`-ot hordoz, továbbá explicit
   capability-követelményeket, rövid-objective jelzőt és planned-rest
   alkalmasságot. Az ismeretlen vagy nem elérhető követelmény fail-closed
   kizárja az elemet.

3. **Stabil seed és sorrend.** A seed material a generation epoch day, a
   profile snapshot key és a catalog version egyértelmű UTF-8
   reprezentációja. A választási sorrend dokumentált 64 bites FNV-1a hashből
   származik, amely a seed material mellett a stabil katalógus-ID-t is
   tartalmazza. `Random()` mag nélkül, `DateTime.now()`, `String.hashCode` és
   iteration-orderre hagyatkozás tilos.

4. **Végrehajtható `[1, 3]` eredmény.** Availability-szűrés után a generátor
   legfeljebb három elemet választ, köztük legalább egy rövidet. Üres vagy
   alkalmatlan katalógus, hiányzó terv és új profil esetén egy tisztán lokális,
   rövid fallback lép be. A kimeneti lista és a katalógus nézete nem
   módosítható.

5. **Planned rest nem grind.** Pihenőnapon kizárólag rest-eligible reflexiós
   vagy könnyű recovery elem választható, és a generált eredmény explicit
   `isOptional = true` metaadatot hordoz. A quest nem változtatja meg a tervet,
   nem kvalifikálja át a napot és nem fogyaszt freeze-erőforrást.

6. **Instance identity.** A `QuestDefinition.id` stabil katalógus-ID marad;
   a napi példány identityjét az R16 schedule (`cadence + generationEpochDay +
   id`) adja. A generátor nem képez naponta új katalógus-ID-t, és nem mossa
   össze a definíciót a futási példánnyal.

## Következmények

Az alkalmazás composition rétege felel az aktuális terv és capabilityk
read-only snapshotjáért; az E08-R17 generator maga offline, pure Dart és
determinisztikus marad. Availability-változás csak új snapshoton változtat
kimenetet. A későbbi UI az `isOptional` metaadatot megjelenítheti, de nem
indíthat permission flow-t pusztán egy quest rendereléséből.

Az ár egy kisméretű application-level input/output contract és katalógus-entry
modell. Ez tudatosan nem bővíti az R16 persistence schemát; heti generálás és
UI-wiring külön kör marad.

## Mérce

Az E08-R17 brief A1–A8 cellái mérik a kipinnelt FNV seedet, a 100-szoros
azonos sorrendet, a 0/1/3/4 mérethatárokat, az availability mátrixot, a
permission/gateway-mentes API-t, a planned-rest optional ágat, az immutable
kimenetet és az üres katalógus fallbackjét. A reviewer valódi mutációval
`Random()`-ra cseréli a stabil seedet, majd megfordítja a kamera-szűrést;
mindkét megfelelő cellának pirosra kell váltania, restore után a teljes gate
zöld.
