# ADR 0249 — Analysis evaluation dataset governance

- **Státusz:** Elfogadva (E06-R29 pre-flight, 2026-08-13)
- **Kör:** E06-R29 — Evaluation harness és confidence calibration
- **Kapcsolódó szerződések:** [ADR 0216](0216-analysis-confidence-calibration-and-abstention.md), [ADR 0218](0218-analysis-metric-id-and-version-governance.md), [ADR 0237](0237-analysis-confidence-combiner-and-capability-resolver.md)

## Kontextus

Az Audio Analysis V2-nek eddig nem volt ground-truth manifestje, futtatható
evaluation harness-e vagy reprodukálható regressziós baseline-ja. A V2
`CalibrationTable` jelenleg tudatosan `identity.v1`: nincs repo-beli,
címkézett valós-audio dataset, amelyből biztonságosan kalibrált görbét lehetne
illeszteni. A nyers audio alapértelmezetten nem hagyhatja el az eszközt, és nem
kerülhet commitba sem.

## Döntés

1. A repository kizárólag sémát, dokumentációt és kis, determinisztikus,
   szintetikus CI-manifestet tart. Valós felvétel külső, hozzáférés-szabályozott
   és licencelt tárban él; a manifest és a report nem tartalmaz abszolút
   elérési utat, felhasználónevet vagy nyers audio payloadot.
2. A harness determinisztikus, verziózott reportot készít. A reportban nincs
   wall-clock érték vagy véletlen sorrend; az azonos manifest és implementáció
   bájtazonos JSON-t ad.
3. A CI-fixture csak a harness-, parser- és regressziós-szerződést méri. Nem
   állíthat valódi modellpontosságot és nem zárhat le olyan manuális-eval sort,
   amely címkézett fizikai felvételt vagy készüléket igényel.
4. Kalibrációs táblát csak binonként legalább 30, összesen legalább 300
   címkézett megfigyelés illeszthet. Mindkét határ inkluzív. Bármelyik hiánya
   esetén a rendszer `identity.v1`-et és `insufficient calibration data`
   állapotot közöl; szintetikus mintából nem keletkezhet új calibration
   verzió.
5. A regressziós kapu az rögzített baseline-hoz mér: onset F1 és chord
   accuracy legfeljebb 2 százalékponttal romolhat; timestamp MAE és BPM error
   legfeljebb 10%-kal romolhat. Javulás nem hiba. E küszöbök gyengítése emberi
   governance-döntés, nem implementer- vagy CI-módosítás.
6. A tényleges CI workflow-lépés nem része ennek a körnek: a teszt-oldali
   megfelelője készül. Workflow vagy `tool/ci` változtatás kizárólag külön,
   ember által engedélyezett governance-körben történhet.

## Következmények

**E06-R30 (2026-08-13):** megerősítve: a szintetikus harness nem zár le valós evaluation sort; a CI workflow-bekötés külön GOV-30b kör marad.

- A V2 publication út és a `CalibrationTable` szerződése változatlanul
  monoton, `[0,1]`-beli és offline marad.
- Az evaluation artefaktumok a későbbi manuális, licencelt dataset-evaluation
  bemenetét adják, de annak eredményét nem szimulálják valódi evidence-ként.
- A baseline-t és a manuális mátrixot futtatott kimenet frissíti; nem kézzel
  beírt célérték.

## Elutasított alternatívák

- **Három vagy kevesebb szintetikus esetre illesztett görbe:** a mintaszám nem
  elég, és hamis kalibráltság-állítást okozna.
- **Valós hangfájl commitolása:** adatvédelmi és licencszabályt sértene.
- **Workflow-gate hozzáadása ebben a körben:** a mérce önmódosítását jelentené.
