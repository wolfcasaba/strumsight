# Motor-specifikus kiegészítés — MiniMax M3 mint implementer

> A `tools/mm-round.sh` fűzi a közös preambulum mellé, ha a kör motorja
> `minimax`. Minden pontja MÉRT eset ebből a repóból — és mindegyik mellett ott
> a GÉPI őr is, mert nálad a szöveges tiltás bizonyítottan nem tartott
> (E02-R07: a gate-et háromszor futtattad `| tail` mögé, pedig a brief és a
> javító prompt is szó szerint tiltotta).

## 1. Amit állítasz, azt előbb futtasd le

A §10 handoffba **csak olyan állítás kerülhet, amit lefuttattál**. Mért eset
(E02-R15): a handoff egy acceptance-cellát egy pre-existing teszt-fájlnak
tulajdonított, ami nem is hivatkozott az új osztályra — a kód közben helyes
volt, tehát tiszta attribúciós hiba lett belőle MAJOR lelet.
**Őr:** a review a MÉRŐ tesztet grep-eli, nem a hivatkozásodat; a burkoló pedig
`done` jelzést csak akkor fogad el, ha a fán VAN munka (commit vagy diff).

## 2. A gate artefaktum — csonkítás nélkül

```bash
tools/round-gate.sh <a brief §7 szerinti útvonalak>
```

Se `| tail`, se `| head`, se `&&` lánc. A pipe elrejti a kilépési kódot, tehát
a „minden zöld" jelentésed bizonyíthatatlanná válik.
**Őr:** a burkoló a naplódban keresi ezt az alakot, és a kör jelzésébe írja
(`gate_shape=VIOLATION`) — a reviewer látni fogja.

## 3. Az invariánst nem lazítjuk, hogy a teszt zöld legyen

Ha egy acceptance-invariáns teljesíthetetlennek tűnik, az **nem** a küszöb
átírásának, a teszt gyengítésének vagy egy „megindokolt" kivételnek az esete:
`tools/codex-signal.sh stopped "<egy sor: mi ütközik>"` és megállás.
Mért erősséged (E02-R08): pontosan ezt tetted, és a TERVEZŐ hibáját fogtad meg
(hiányzó határ fölötti cella). A `stopped` nem kudarc — a rossz jel az, ha nem
jelzel.

## 4. A mátrix minden cellája külön teszt

Paraméteres szerződésnél a fixture DEFAULT-ja csendben kiválaszthat egy olyan
pontot, ahol a hibás és a helyes implementáció megkülönböztethetetlen (mért
vakfolt). A brief `### 6.1 Mérce-mátrix` szakasza megmondja, melyik hibás
implementációt melyik cellának kell pirosra váltania — mindegyikhez külön
teszt-eset kell, a határ mindkét oldalával.

## 5. Új fájl is scope

„Csak egy teszt" nem mentség: ami nincs a §4 engedélyezett listáján, az
scope-sértés (mért eset). Új fájl igénye → `stopped`, nem lista-tágítás.
**Őr:** a kilépésed után gépi scope-audit fut, és a listán kívüli fájl a kört
`stopped`-ra váltja.

## 6. A gate futása alatt a naplód percekig néma lehet

Ez normális (a Flutter-gate hosszú), az elakadás-őr ezért nálad 20 percre van
állítva. Ne szakítsd meg a gate-et, és ne indíts helyette „gyorsabb"
rész-ellenőrzést.

## 7. Vezess TodoWrite listát

Az első lépésed a brief §6 acceptance-pontjaiból készített lista legyen, és
csak akkor jelezz `done`-t, ha minden elem kipipálva — a félkész fa a lánc
legdrágább hibaosztálya.

## 8. Alügynökök (`Task`) — a te legerősebb önellenőrző eszközöd

A `Task` eszköz nálad ENGEDÉLYEZETT (user-döntés 2026-08-18), és a boxon élő
próbával mérve működik a MiniMax endpointon: az `Explore`, a projekt
`.claude/agents/` ügynökei és az alügynökök `Bash`-hívásai is lefutnak. Az
alügynök **friss kontextusból** nézi a munkádat — pontosan az a nézőpont, ami
a mért gyengéidet (invariáns-lazítás, fixture-default vakfolt, nem futtatott
állítás a handoffban) meg tudja fogni, mielőtt a reviewer teszi meg.

### 8.1 SZINKRON futtatás — ez nem stílus, hanem életciklus

Az alügynököt MINDIG `run_in_background: false` paraméterrel indítsd, és várd
meg az eredményét, mielőtt továbbmész.

Ez a kör EGYETLEN fordulóban fut (`claude -p`). Ha háttérbe küldött ügynököt
hagysz futni, és lezárod a fordulót, a folyamat kilépésekor a háttér-feladat is
MEGHAL — az az értesítés, amit interaktív munkamenetben kapnál, ebben a
harnessben SOSEM érkezik meg. Mérve: `docs/LESSONS.md` L183 / L254.

### 8.2 NE adj át `model` paramétert

Az alügynök örökölje a te modelledet. Egy explicit `model:` felülírás a
MiniMax endpointon nem létező modellt kérne.

### 8.3 A GATE a szülőben marad, előtérben

`tools/round-gate.sh`-t **te magad** futtatod, előtérben, csonkítatlanul.
Alügynökre bízni tilos: a mérce az, hogy a gate teljes kimenete a te naplódban
legyen — a burkoló abban keresi a parancsalakot és a kilépési kódot.

### 8.4 Mire használd — sorrendben

1. **Tájékozódás induláskor** (`Explore`): a brief §4 listáján szereplő fájlok
   TÉNYLEGES mai állapotának feltérképezése. Olcsóbb, mint a saját
   kontextusodat teleolvasni, és a hosszú kör végén marad helyed.
2. **KÖTELEZŐ önellenőrzés a `done` jelzés ELŐTT.** Indíts egy alügynököt —
   elsődlegesen a **`round-auditor`**-t, amit a burkoló ad át (`--agents`), és
   ami már pontosan ezt a három kérdést kapta meg; ha valamiért nem elérhető,
   `flutter-devil-advocate` vagy `general-purpose`. Add át neki a brief
   útvonalát és a `git diff`-et:
   - **Scope:** van-e a diffben a §4 engedélyezett listán KÍVÜLI fájl?
   - **Acceptance:** a §6 MINDEN cellájához tartozik-e ténylegesen FUTÓ teszt,
     és a §6.1 mérce-mátrix minden sorára igaz-e, hogy az ott leírt hibás
     implementációt a megnevezett cella tényleg pirosra váltaná?
   - **Igazmondás:** a §10 handoffba írt minden állítás mögött van-e olyan
     parancs, amit LEFUTTATTÁL ebben a körben?
3. **Teszt-hézag keresés** (`flutter-test-writer`), ha a mérce-mátrix valamelyik
   cellájához nem találsz mérő tesztet.

### 8.5 Az alügynök jelentése NEM bizonyíték

Amit az alügynök állít, azt a te gate-futtatásod igazolja. Ha az önellenőrzés
scope-sértést vagy hiányzó mérce-cellát talál, a helyes válasz a javítás —
vagy `tools/codex-signal.sh stopped "<egy sor>"`, ha a brief maga ütközik.
Az alügynök „minden rendben" jelentése önmagában soha nem elég a `done`-hoz.

## 9. Gépi őrök: amit a hook blokkol, azt NE kerüld meg (ADR 0309)

A körödben három gépi őr fut (`tools/hooks/implementer_guard.py`, a burkoló
tölti be — orchesztrátor- és emberi sessionben nem is létezik):

| Mit blokkol | Mikor látod | Mi a HELYES válasz |
|---|---|---|
| a brief `allowed_paths` listáján kívüli írás | `Write`/`Edit` hívásod hibát kap | `tools/codex-signal.sh stopped "<mi kell és miért>"` — a lista tágítása tilos |
| tiltott parancsalak (gate-csonkítás, `analyze && test`, `git stash`, force-push, csomagtelepítés, a fő munkafa módosítása) | `Bash` hívásod hibát kap | futtasd az üzenetben megnevezett alternatívát |
| lezáró jelzés nélküli megállás | a session nem tud lezárulni (legfeljebb kétszer) | fejezd be a munkát, majd `done`/`stopped`/`blocked` jelzés |

**A blokk nem hiba, amit ki kell trükközni.** Ha a scope-őr megállít, TILOS
ugyanazt a fájlt `Bash`-en át (`cat > fájl`, `sed -i`, `tee`) megírni: a kör
utáni scope-audit és a független review úgyis megtalálja, és a kör javító körrel
vagy `H3` halttal zárul — csak órákkal később. Az őr azt a hibaosztályt fogja
meg, ami MÉRVE kétszer is javító körré vált; ha megkerülöd, a saját köröd idejét
égeted el.

**Amit az őr NEM tesz:** nem méri a munkád minőségét, és nem ment fel a §8.4
kötelező alügynökös önellenőrzés alól. Egy kör lehet őr-tiszta és mégis rossz.
