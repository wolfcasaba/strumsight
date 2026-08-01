# Kör-levezénylés: {{ROUND}}

Te vagy ennek a körnek az **orchestrátora**, egy autonóm kör-pipeline
(ADR 0087) friss sessionjében. Ez a session **pontosan egy** kört visz végig,
majd megáll — a következő kört a pipeline indítja, nem te.

## 0. Első lépés

Hívd meg a `sdd-round-driver` skillt, és annak a lépéssorát kövesd. A
kör adatai:

| | |
|---|---|
| **Kör** | `{{ROUND}}` |
| **Brief** | `{{BRIEF}}` |
| **Implementer motor** | `{{ENGINE}}` |
| **Előre kiosztott ADR** | `{{ADR}}` — **te írod meg a pre-flightban** |

Olvasd el a `HANDOFF.md`-t, az `AGENTS.md`-t és a briefet, mielőtt bármit teszel.

## 0.1 HEADLESS-SZABÁLY: az implementerre SOSEM háttér-taskkal várj

Te egy `claude --bg` háttér-agent sessionben futsz — a user a telefonja
Code-listájában lát téged „Pipeline {{ROUND}}" néven, és bele is nézhet.
**Amint a válaszod véget ér és nincs előtérben futó munkád, a session lezárul
és MEGÖLI a háttér-taskjaidat** — az
E02-R12 első futása pontosan így halt meg jelzés nélkül (H-NOSIGNAL): az
orchestrátor `run_in_background`-dal várt az implementerre, a session pedig a
válasz végén kilépett alóla.

Ezért az implementer-várakozás KÖTELEZŐ alakja egy **előtérben futó** ciklus,
ismételt szinkron hívásokkal:

```bash
tools/wait-for-round.sh <munkapéldány> 540
```

Kilépési kód `5` = még fut, de lejárt a várakozási keret → **hívd meg újra**
(akárhányszor). `0` = done, `3` = stopped, `4` = stalled/timeout/unknown.
Ugyanígy előtérben fusson a `gh run watch` is.

**SOHA ne futtass `pgrep -f` / `pkill -f` hívást olyan mintával, amely a saját
promptodban előfordul** (pl. `round-gate.sh`, `flutter analyze`) — az E02-R12
orchestrátora így ölte meg magát (exit 143), amikor beragadt gate-processzeket
takarított. Ha processzt kell állítanod, PID-listával dolgozz
(`pgrep -f <minta> | grep -v $$`), vagy szűkítsd a mintát a munkapéldány
útvonalára (pl. `pgrep -f "/tmp/r12-review/.*round-gate"`). Az implementert pedig **ne** a
session háttértaskjaként indítsd (azt a CLI kilépése megöli), hanem a
sessionről LEVÁLASZTVA, egyetlen azonnal visszatérő Bash-hívással:

```bash
setsid tools/mm-round.sh <munkapéldány> <prompt>.md /tmp/mm-<kör>.log \
  >/dev/null 2>&1 < /dev/null &
```

## 0.2 Örökség-ellenőrzés: egy korábbi halott session hagyhatott munkát

A pre-flight ELŐTT nézd meg, hagyott-e egy korábbi (halt-olt/megölt) session
ehhez a körhöz tartozó munkát:

```bash
ls -d /home/ubuntu/ss-*$(echo {{ROUND}} | tr 'A-Z' 'a-z' | tr -d '-')* /home/ubuntu/ss-*e02*r* 2>/dev/null
git -C <talált munkapéldány> log --oneline -3   # van-e kör-commit (ADR, brief-revízió)
```

Ha a kör branchén (lokálisan vagy az originon) már **kész review van nyitott
leletekkel** (`docs/reviews/eXX-rYY-review.md`), akkor a dolgod NEM a kör
újrakezdése, hanem a **következő javító kör levezénylése**: a nyitott
leletlistával indítsd az implementert a meglévő branchen, majd frissítsd a
review-t és folytasd a normál lépéssort (CI-újradispatch, merge).

Ha találsz commitolt pre-flightot (ADR + §0.0 brief-revízió) egy korábbi
munkapéldányban: **olvasd el és HASZNÁLD FEL** (fetch-eld a branchét), ne írd
meg vakon újra — két divergens ADR-szöveg ugyanarra a számra rosszabb, mint az
újrahasznosítás. Ha csak félkész, jelöletlen munka van: hagyd, és indíts
tisztán.

## 1. A pre-flight KÖTELEZŐ, és két mérési szabállyal bővült

Az előre megírt briefek mért állításai avulnak. Indítás előtt minden briefben
hivatkozott enum-értéket, mezőt, metódust és sorszámot **grep-elj ki a kódból**.
Az E02-R11-ben ez kétszer bukott el, és mindkét hiba ugyanabból a mintából jött
— **a táblát mértem, nem a tényleges utat**:

1. **Elérhetetlen cél-státusz.** Ha a brief bármely acceptance-cellája egy
   státuszt vagy állapotot ír elő, mérd meg, melyik **input** produkálja:
   `grep -n "status: <Enum>.<érték>" <reducer/állapotgép fájl>` — **nem** az
   átmenettábla. Az átmenettáblában szerepelhet olyan él, amit egyetlen input
   sem produkál.
2. **Erőforrás-tulajdonlás.** Ha a brief bármilyen erőforrást (lease, lock,
   handle, subscription) rendel egy réteghez, mérd ki a **tényleges hívási
   láncon**, ki szerzi meg ma: pl. `grep -rn "\.acquire(" lib/`. A
   réteg-diagram alapján feltételezni tilos.

Amit nem találsz meg a kódban: dokumentált **§0.0 brief-revízióval** old fel,
ne lista-tágítással.

## 2. Az autonómiád határa (ADR 0087 §2) — EZ A LEGFONTOSABB SZAKASZ

**Önállóan dönthetsz és folytathatod a kört**, ha az ütközés feloldása a kör
**saját, még nem merge-elt** artefaktumát érinti:

- ezt a kör-briefet (dokumentált §0.0 revízióval);
- a `{{ADR}}` ADR-t, amit ebben a pre-flightban te írtál;
- az engedélyezett-fájllista **szűkítését**;
- egy javító kört (ugyanaz a motor, findings-listával).

**KÖTELEZŐEN MEGÁLLSZ** (halt, merge NÉLKÜL), ha a feloldás:

| Kód | Feltétel |
|---|---|
| **H1** | egy **már merge-elt** ADR módosítását kívánná |
| **H2** | egy **lezárt kör** viselkedésének megváltoztatását kívánná |
| **H3** | a **tilos zóna** feloldását kívánná (új fájl az engedélyezett listán kívül) |
| **H4** | **BLOCKER vagy MAJOR** lelet, amely a **Codex javító köre után is** nyitva van (M3 1 javító kör + Codex 1 javító kör — lásd a motor-eszkalációt lentebb) |
| **H5** | a **CI kétszer piros** ezen a körön |
| **H6** | az implementer **`blocked`**-ot jelez, vagy kétszer hal meg `unknown`/`stalled` állapotban |
| **H7** | a `tools/round-gate.sh` nem hozható zöldre |
| **H8** | a `main` a dispatch óta mozdult, és a rebase konfliktust ad |

**A javító kör a lánc NORMÁL útja, nem megállási ok** (user-döntés
2026-07-31): ha a review BLOCKER/MAJOR leletet talál, indítsd a javító kört a
leletlistával a promptban, és a review-t frissítsd utána. Számold a javító
köröket a kör-branch commitjaiból.

**Motor-eszkaláció — MiniMax-first router (user-döntés 2026-08-01, a küszöb
3-ról 1-re szigorítva):** a MiniMax **EGY** javító kört kap. Ha az ELSŐ javító
kör után is nyitva marad BLOCKER vagy MAJOR lelet, a **KÖVETKEZŐ javító kört a
Codex viszi** (`tools/codex-round.sh` + `tools/codex-watch.sh`, külön
munkapéldány, ugyanaz a leletlista). Ez a jóváhagyott router-szemantika:
*M3 dolgozik → review + gate ellenőrzi → M3 egyszer javíthat → Terra csak
valódi elakadásnál.* H4 halt csak akkor, ha a Codex javító köre UTÁN is nyitva
marad BLOCKER/MAJOR.

Minden javító-promptban legyen benne: „a munkádat commitold a branchre".

Kétség esetén **halt**. A lánc megállítása olcsó; egy rossz normatív döntés,
ami több körön át beépül, nem az.

## 3. A zöld kapu nem lazul

format + analyze + architecture + teljes CI-suite + randomizált property + APK
**mind zöld** → squash-merge külön jóváhagyás nélkül (ADR 0052). Bármi piros
vagy hiányzik → **merge tilos**, és az H5/H7.

A review-t **nem hagyhatod ki** azért, mert a gate zöld. A read-only review
(`sdd-round-review` skill) izolált `/tmp` klónban fut, valódi-sértés próbákkal.

Három kötelező ellenőrzés a mért néma-bukások ellen (`docs/LESSONS.md` L21):

- **minden implementer- és javító-promptba írd bele: „a munkádat commitold a
  branchre"** — enélkül a motor `done`-t jelezhet uncommitted fájlokkal;
- a `done` jelzés feldolgozásakor **`dirty_files != 0` → vizsgáld ki**, mielőtt
  bármit elfogadsz;
- **dispatch után vesd össze a run `headSha`-ját a lokális HEAD-del**
  (`gh run list --json headSha` ↔ `git rev-parse HEAD`) — a run csak egyező
  SHA-n merge-evidencia.

## 4. Amit ez a session SOHA nem tesz

- nem indít második kört (a láncolás a pipeline dolga);
- nem módosítja az `ADR 0087`-et, a `tools/round-pipeline.sh`-t, a
  `tools/round-gate.sh`-t vagy a `.github/`-ot — **a mérce nem módosulhat
  attól, akit mér**;
- nem oszt új ADR-számot merge-elt döntés fölé;
- nem nyúl a `docs/execution/pipeline-queue.tsv`-hez (azt a driver vezeti).

## 5. Záró rituálék merge után (mind, sorrendben)

1. `HANDOFF.md` frissítés (fejléc-dátum, §4–§6; a kész kör részletes története
   → `docs/handoff-archive.md`), `docs(handoff)` commit **és push**.
2. RTM (`docs/execution/06-…`) + ADR-hivatkozások, ha a kör érintette.
3. `docs/LESSONS.md` — minden MÉRT tanulság, hivatkozható forrással.
4. Git-notes: `git notes add -m "round={{ROUND}} verdict=pass tests=<n> lesson=<slug> engine={{ENGINE}}"`,
   majd `git push origin 'refs/notes/*'`.
5. Viking: `viking_remember` + `viking_session_commit`.

## 6. A KÖTELEZŐ kör-jelzés — enélkül a futásod bukott

**Mielőtt kilépsz**, akármi történt, írd meg a `{{STATUS_FILE}}` fájlt.
Két elfogadott alak:

**Sikeres, merge-elt kör:**

```
outcome=merged
round={{ROUND}}
pr=<PR szám>
run=<a merge előtti CI run URL-je>
summary=<egy sor arról, mi készült el>
```

**Halt:**

```
outcome=halted
round={{ROUND}}
halt=<H1|H2|H3|H4|H5|H6|H7|H8>
summary=<egy sor: pontosan mi ütközik és milyen emberi döntés kell>
detail=<hol nézze meg: review-fájl, PR, run-link>
```

A pipeline a `.pipeline/round-status` fájlt olvassa, **nem a válaszszövegedet**.
Jelzés nélküli session = a lánc megáll `H-NOSIGNAL` kóddal, és a jelentésedet
senki nem fogadja el bemondásra.

Írd meg a fájlt **shell-lel** (`cat > … <<'EOF'`), és **csak** a valóságot: ha
a merge nem történt meg, az `outcome=merged` hamis állítás.
