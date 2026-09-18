# APK smoke — a shippelt APK futtatása valódi emulátoron

A merge-kapu ma kizárólag **host-oldali** `flutter test`-et futtat: a Dart kód
viselkedését méri, a *csomagot* nem. Az APK smoke ezt a hiányzó réteget zárja
be — a `build-apk.yml` által előállított, SHIPPELT development APK-t telepíti
egy valódi Android emulátorra, és gépi evidenciát gyűjt arról, hogy elindul,
túlél egy alap-navigációt és nem omlik össze.

## Mit mér

- **Telepíthetőség**: `adb install -r -g`, majd a RECORD_AUDIO és a CAMERA
  futásidejű engedély ellenőrzése `dumpsys package`-dzsel (`pm grant` fallback).
- **Indulás**: `monkey … LAUNCHER` indítás után a `dumpsys activity activities`
  `mResumedActivity` sora tényleg a `com.wolfcasaba.strumsight/.MainActivity`-t
  mutatja-e, és él-e a process (`pidof`).
- **Valódi első frame**: az `01-launch.png` képernyőkép nem lehet üres/fekete —
  a `tools/apk-smoke/png_stats.py` (csak stdlib zlib+struct) dekódolja és
  hisztogramot számol: méret ≥ 20 KB, ≥ 16 különböző szín, a mintavett pixelek
  ≥ 2%-a nem közel-fekete.
- **Navigációs túlélés**: egy BACK az induló képernyőről (onboarding/hub nem
  halhat bele), a bottom-nav sávok végigkoppintása a képernyő ~96%-os
  magasságán, majd két további BACK — minden lépés után process-liveness
  assert + képernyőkép.
- **Crash/ANR**: a teljes `logcat -d` mentve; BUKÁS, ha `FATAL EXCEPTION`,
  `ANR in com.wolfcasaba.strumsight`, `Process … has died` vagy Flutter
  `Unhandled Exception` szerepel benne.
- **Számok**: hidegindítás (`am start -W` → `TotalTime`) és `dumpsys meminfo`
  TOTAL PSS a `report.md`-ben.

## Mit NEM mér (szándékosan)

- **Nincs mikrofon és nincs valódi gitár**: az emulátor `-noaudio`-val fut, a
  detektor tényleges pontosságáról ez a futás semmit nem mond. A végső
  elfogadási predikátum továbbra is a felhasználó valós-gitáros APK-tesztje.
- **Nincs pixel-assert**: nem golden-összehasonlítás; csak azt állítjuk, hogy a
  frame nem üres. A golden-mérce marad a `full-gate` / `build-apk` oldalán.
- **Nincs szemantikus UI-assert**: a Flutter csak bekapcsolt accessibility
  service mellett publikálja a semantics fát az `uiautomator`-nak, és a legtöbb
  AOSP emulátorképen nincs TalkBack. A koppintások ezért koordináta-alapúak és
  best-effort jellegűek: a `tab-N-alive` assert azt bizonyítja, hogy a
  koppintás nem ölte meg az appot, nem azt, hogy melyik fül nyílt meg.
- **Nincs backend**: a login/sync útvonal nem része a smoke-nak.
- **x86_64 emulátor ≠ ARM telefon**: a natív DSP/ML útvonal más ABI-n fut.

## Hogyan kell indítani

A workflow `workflow_dispatch`-es, ezért a fájlnak a **`main`-en kell élnie**,
hogy megjelenjen a dispatch-listában (ugyanaz a szabály, mint a
`record-goldens.yml`-nél — kör-branchről nem indítható).

```bash
# 1) fusson le egy zöld build-apk.yml a kör-branchen, és jegyezd fel a run id-t
gh run list --workflow build-apk.yml --limit 5

# 2) azzal a run id-vel indítsd a smoke-ot
gh workflow run apk-smoke.yml --ref main \
  -f run_id=<a build-apk futás ID-ja> \
  -f api_level=34
```

A `run_id` kötelező: a smoke NEM buildel, hanem a megnevezett futás
`strumsight-*.apk` artifactját tölti le (`actions/download-artifact@v4`,
`merge-multiple: true`), és megbukik, ha nem pontosan egy nem-üres APK jött le.

## Hogyan kell olvasni az eredményt

Az artifact neve `apk-smoke-<run_id>`, és bukott futásnál is feltöltődik
(`if: always()`) — épp az a legértékesebb. Tartalma:

| fájl | mit ad |
| --- | --- |
| `report.md` | a verdikt + assertion-tábla, hidegindítás, PSS |
| `01-launch.png` … `05-cold-start.png` | képernyőképek minden lépés után |
| `screenshots.jsonl` | képenként a méret/szín-statisztika (gépi ellenőrzés) |
| `logcat.txt`, `crash-hits.txt` | teljes logcat, illetve a találatok kivonata |
| `ui-01-launch.xml`, `ui-99-final.xml` | `uiautomator` dumpok |
| `meminfo.txt`, `am-start.txt`, `install.log` | nyers mérési kimenetek |

A job akkor és csak akkor zöld, ha egyetlen assertion sem bukott; a script a
végén kiír egy összefoglaló táblát a job-logba is.

Forrás: `tools/apk-smoke/run.sh` (a tábla logikája), `tools/apk-smoke/png_stats.py`
(a fekete-frame detektor), `.github/workflows/apk-smoke.yml` (a futtatókörnyezet).
