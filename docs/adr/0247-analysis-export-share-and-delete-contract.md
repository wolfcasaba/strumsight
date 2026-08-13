# ADR 0247 — Analysis export, share és delete szerződés

- **Státusz:** Elfogadva (E06-R27 pre-flight, 2026-08-13)
- **Kör:** E06-R27 — Export, share és privacy controls
- **Kapcsolódó szerződések:** ADR 0201 (bizonytalanság), ADR 0202 (raw audio
  retention), ADR 0239 (analysis repository), SDD Ch7 §27.5 és §28.

## Kontextus

Az audio analysis V2 dokumentum exportjának helyinek, előnézettel védettnek
és adatminimalizáltnak kell lennie. A jelenlegi `ShareService` csak kártya-PNG
és szöveg megosztását támogatja, a repository pedig dokumentumot és indexet
tárol, nyers audio-byte-ot és R28 cache-t még nem.

## Döntés

1. A normál export allowlist-alapú, verziózott JSON. Nyers audio, importált
   fájlnév, device-azonosító, secret és teljes belső diagnosztika alapból nem
   része a kimenetnek.
2. Megosztás csak előnézet-megerősítés után indulhat. A `ShareService` pontosan
   egy additív publikus metódust kap: a hívó által létrehozott fájlt és feliratot
   megosztja, majd `try/finally`-ban siker és hiba esetén is törli a fájlt.
   A meglévő `shareCard`, `shareImage` és `shareText` szerződése változatlan.
3. Az `ExportAnalysisUseCase` hozza létre a random nevű app-private temp
   exportot; a megosztás utáni életciklus tulajdonosa a `ShareService`.
4. A `DeleteAnalysisUseCase` a repository dokumentum+index törlését hívja, és
   explicit cache/audio portokon át takarít. Nem bővíti az R21 repository
   szerződését és nem állítja, hogy ma nem létező cache vagy audio perzisztál.
5. Nincs hálózati út, felhőfeltöltés vagy Lab export ebben a körben.

## Következmények

- Az export és a share offline marad, nyers audio nem hagyja el az eszközt.
- A takarítás siker- és hibautas viselkedése fake share/cache/audio portokkal
  tesztelhető.
- A későbbi R28 cache-implementáció a már rögzített cache portot kötheti be
  anélkül, hogy az export-policyt lazítaná.

## Elutasított alternatívák

- Denylist-redakció: új belső mező csendben kiszivároghat.
- A hívóra hagyott temp-takarítás: hibautas fájlmaradványt enged.
- A meglévő kép/szöveg megosztók exportfájlra erőltetése: megváltoztatná a
  meglévő publikus szerződést.
