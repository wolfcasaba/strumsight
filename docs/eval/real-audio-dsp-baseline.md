# Valós-audio DSP baseline — GOV-06 / E99-R04

## Eredmény

A változatlan, alapértelmezett `const ClipAnalyzer()` 82 valódi telefonos
gitárfelvételen 7 892 / 11 767 helyes akkordot ért el: **67,069%**.
Ez meghaladja a ground-truthból számolt G-major többségi baseline-t
(2 216 / 11 767, **18,832%**). A 222 moll eseményen a pontosság
185 / 222, **83,333%**.

Az onset-párosítás kétoldali, mohó és egész mikroszekundumos (`deltaUs <=
toleranceUs`), eredménye:

| Tűrés | Precision | Recall | F1 |
|---:|---:|---:|---:|
| 25 000 µs | 38,532% | 42,517% | 40,427% |
| 50 000 µs | 64,233% | 70,876% | 67,391% |
| 100 000 µs | 81,208% | 89,607% | 85,201% |

A BPM ground truth **származtatott**: `60 / medián pozitív ground-truth
inter-onset intervallum`. A felvételenkénti rács-szabályossági érték a pozitív
IOI-k populációs szórása / medián IOI. Nem történt automatikus szabálytalanrács-
kizárás: a kritérium „nincs kizárás; minden sikeresen elemzett, legalább két
pozitív IOI-t tartalmazó felvétel aggregálódik”, a kizártak száma **0**. Az így
származtatott BPM átlagos abszolút hibája **45,067 BPM**.

## Reprodukálhatóság és korlátok

- Futtatott mérési parancs: `~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio tool/benchmarks/real_audio_dsp_baseline.dart`.
- A briefben előírt `~/flutter/bin/dart run tool/benchmarks/real_audio_dsp_baseline.dart ml/data/klangio` ténylegesen nem indítható: a valós `ClipAnalyzer` tranzitívan `dart:ui`-t importál, ami a sima Dart VM-ben nem elérhető. A Flutter-tesztrunner ugyanazt a változatlan publikus `ClipAnalyzer`-t futtatta.
- Korpusz: 82 WAV, 82 `.strums`, 11 767 esemény; SHA-256: `4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827`.
- A korpusz nincs verziókövetve, ezért a mérés ma ezen a boxon kívül nem reprodukálható. A 423 MB-os adatforrás egyetlen, 98%-ban dúr telefonos felvételi disztribúció; az eredmények erre érvényesek, nem általános zenei állítások.
- Hibás/kihagyott felvételek: **nincs** (82/82 feldolgozva).

## Csonkítatlan mérési kimenet

```text
Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+4 available)
  camera_avfoundation 0.9.23+2 (0.10.2 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  go_router 17.3.0 (17.4.0 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
45 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e99-r04/tool/benchmarks/real_audio_dsp_baseline.dart
Shell: [1/82] recording_1001_phone.wav
Shell: [2/82] recording_1002_phone.wav
Shell: [3/82] recording_1003_phone.wav
Shell: [4/82] recording_1004_phone.wav
Shell: [5/82] recording_1005_phone.wav
Shell: [6/82] recording_1006_phone.wav
Shell: [7/82] recording_1007_phone.wav
Shell: [8/82] recording_1008_phone.wav
Shell: [9/82] recording_1009_phone.wav
Shell: [10/82] recording_1010_phone.wav
Shell: [11/82] recording_1011_phone.wav
Shell: [12/82] recording_1012_phone.wav
Shell: [13/82] recording_1013_phone.wav
Shell: [14/82] recording_1014_phone.wav
Shell: [15/82] recording_1015_phone.wav
Shell: [16/82] recording_1016_phone.wav
Shell: [17/82] recording_1017_phone.wav
Shell: [18/82] recording_1018_phone.wav
Shell: [19/82] recording_1019_phone.wav
Shell: [20/82] recording_1020_phone.wav
Shell: [21/82] recording_1021_phone.wav
Shell: [22/82] recording_1023_phone.wav
Shell: [23/82] recording_1024_phone.wav
Shell: [24/82] recording_1025_phone.wav
Shell: [25/82] recording_1026_phone.wav
Shell: [26/82] recording_1027_phone.wav
Shell: [27/82] recording_1028_phone.wav
Shell: [28/82] recording_2001_phone.wav
Shell: [29/82] recording_2002_phone.wav
Shell: [30/82] recording_2003_phone.wav
Shell: [31/82] recording_2004_phone.wav
Shell: [32/82] recording_2005_phone.wav
Shell: [33/82] recording_2006_phone.wav
Shell: [34/82] recording_2007_phone.wav
Shell: [35/82] recording_2008_phone.wav
Shell: [36/82] recording_2009_phone.wav
Shell: [37/82] recording_2010_phone.wav
Shell: [38/82] recording_2011_phone.wav
Shell: [39/82] recording_2012_phone.wav
Shell: [40/82] recording_2013_phone.wav
Shell: [41/82] recording_2014_phone.wav
Shell: [42/82] recording_2015_phone.wav
Shell: [43/82] recording_2016_phone.wav
Shell: [44/82] recording_2017_phone.wav
Shell: [45/82] recording_2018_phone.wav
Shell: [46/82] recording_2019_phone.wav
Shell: [47/82] recording_2020_phone.wav
Shell: [48/82] recording_2021_phone.wav
Shell: [49/82] recording_2022_phone.wav
Shell: [50/82] recording_2023_phone.wav
Shell: [51/82] recording_2024_phone.wav
Shell: [52/82] recording_2025_phone.wav
Shell: [53/82] recording_2026_phone.wav
Shell: [54/82] recording_2027_phone.wav
Shell: [55/82] recording_2028_phone.wav
Shell: [56/82] recording_4001_phone.wav
Shell: [57/82] recording_4002_phone.wav
Shell: [58/82] recording_4003_phone.wav
Shell: [59/82] recording_4004_phone.wav
Shell: [60/82] recording_4005_phone.wav
Shell: [61/82] recording_4006_phone.wav
Shell: [62/82] recording_4007_phone.wav
Shell: [63/82] recording_4008_phone.wav
Shell: [64/82] recording_4009_phone.wav
Shell: [65/82] recording_4010_phone.wav
Shell: [66/82] recording_4011_phone.wav
Shell: [67/82] recording_4012_phone.wav
Shell: [68/82] recording_4013_phone.wav
Shell: [69/82] recording_4014_phone.wav
Shell: [70/82] recording_4015_phone.wav
Shell: [71/82] recording_4016_phone.wav
Shell: [72/82] recording_4017_phone.wav
Shell: [73/82] recording_4018_phone.wav
Shell: [74/82] recording_4019_phone.wav
Shell: [75/82] recording_4020_phone.wav
Shell: [76/82] recording_4021_phone.wav
Shell: [77/82] recording_4022_phone.wav
Shell: [78/82] recording_4023_phone.wav
Shell: [79/82] recording_4024_phone.wav
Shell: [80/82] recording_4025_phone.wav
Shell: [81/82] recording_4027_phone.wav
Shell: [82/82] recording_4028_phone.wav
Shell: {
Shell:   "corpus": {
Shell:     "path": "ml/data/klangio",
Shell:     "wavCount": 82,
Shell:     "strumsCount": 82,
Shell:     "eventCount": 11767,
Shell:     "sha256": "4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827",
Shell:     "versionControlled": false
Shell:   },
Shell:   "processedRecordings": 82,
Shell:   "skippedRecordings": [],
Shell:   "chords": {
Shell:     "correct": 7892,
Shell:     "total": 11767,
Shell:     "accuracy": 0.6706892156029575,
Shell:     "majorityClassBaseline": {
Shell:       "label": "G-major",
Shell:       "correct": 2216,
Shell:       "total": 11767,
Shell:       "accuracy": 0.1883232769609926
Shell:     },
Shell:     "minorSubset": {
Shell:       "correct": 185,
Shell:       "total": 222,
Shell:       "accuracy": 0.8333333333333334
Shell:     },
Shell:     "perLabel": {
Shell:       "A-major": {
Shell:         "support": 1546,
Shell:         "precision": 0.8832288401253918,
Shell:         "recall": 0.7289780077619664
Shell:       },
Shell:       "A-minor": {
Shell:         "support": 98,
Shell:         "precision": 0.6722689075630253,
Shell:         "recall": 0.8163265306122449
Shell:       },
Shell:       "B-major": {
Shell:         "support": 860,
Shell:         "precision": 0.9394703656998739,
Shell:         "recall": 0.8662790697674418
Shell:       },
Shell:       "B-minor": {
Shell:         "support": 124,
Shell:         "precision": 0.8823529411764706,
Shell:         "recall": 0.8467741935483871
Shell:       },
Shell:       "Bb-major": {
Shell:         "support": 284,
Shell:         "precision": 0.9520958083832335,
Shell:         "recall": 0.5598591549295775
Shell:       },
Shell:       "C#-major": {
Shell:         "support": 138,
Shell:         "precision": 0.0,
Shell:         "recall": 0.0
Shell:       },
Shell:       "C-major": {
Shell:         "support": 1982,
Shell:         "precision": 0.8497772119669,
Shell:         "recall": 0.6735620585267407
Shell:       },
Shell:       "D-major": {
Shell:         "support": 1804,
Shell:         "precision": 0.8984468339307049,
Shell:         "recall": 0.41685144124168516
Shell:       },
Shell:       "E-major": {
Shell:         "support": 1283,
Shell:         "precision": 0.8276119402985075,
Shell:         "recall": 0.8643803585346843
Shell:       },
Shell:       "F#-major": {
Shell:         "support": 408,
Shell:         "precision": 0.9525222551928784,
Shell:         "recall": 0.7867647058823529
Shell:       },
Shell:       "F-major": {
Shell:         "support": 1024,
Shell:         "precision": 0.7767624020887729,
Shell:         "recall": 0.5810546875
Shell:       },
Shell:       "G-major": {
Shell:         "support": 2216,
Shell:         "precision": 0.88712422007941,
Shell:         "recall": 0.7057761732851986
Shell:       }
Shell:     }
Shell:   },
Shell:   "onsets": {
Shell:     "25000": {
Shell:       "matched": 5003,
Shell:       "falsePositives": 7981,
Shell:       "falseNegatives": 6764,
Shell:       "precision": 0.3853203943314849,
Shell:       "recall": 0.4251720914421688,
Shell:       "f1": 0.4042664942830592
Shell:     },
Shell:     "50000": {
Shell:       "matched": 8340,
Shell:       "falsePositives": 4644,
Shell:       "falseNegatives": 3427,
Shell:       "precision": 0.6423290203327172,
Shell:       "recall": 0.7087617914506671,
Shell:       "f1": 0.6739121651650438
Shell:     },
Shell:     "100000": {
Shell:       "matched": 10544,
Shell:       "falsePositives": 2440,
Shell:       "falseNegatives": 1223,
Shell:       "precision": 0.8120764017252002,
Shell:       "recall": 0.8960652672728818,
Shell:       "f1": 0.8520059795563816
Shell:     }
Shell:   },
Shell:   "bpm": {
Shell:     "groundTruthMethod": "60 / median positive ground-truth inter-onset interval",
Shell:     "regularityMethod": "population standard deviation of positive IOIs / median IOI",
Shell:     "exclusionCriterion": "none; all successfully analyzed recordings with at least two positive IOIs are aggregated",
Shell:     "excludedForIrregularGrid": 0,
Shell:     "meanAbsoluteErrorBpm": 45.06716069579421,
Shell:     "recordings": [
Shell:       {
Shell:         "recording": "recording_1001",
Shell:         "groundTruthBpm": 49.692033621629946,
Shell:         "predictedBpm": 82.68749999999977,
Shell:         "absoluteErrorBpm": 32.99546637836983,
Shell:         "ioiStddevOverMedian": 0.034557378826369084
Shell:       },
Shell:       {
Shell:         "recording": "recording_1002",
Shell:         "groundTruthBpm": 99.38398493338788,
Shell:         "predictedBpm": 101.3327205882361,
Shell:         "absoluteErrorBpm": 1.948735654848221,
Shell:         "ioiStddevOverMedian": 0.035422577796431584
Shell:       },
Shell:       {
Shell:         "recording": "recording_1003",
Shell:         "groundTruthBpm": 95.70309073131517,
Shell:         "predictedBpm": 100.34890776699055,
Shell:         "absoluteErrorBpm": 4.645817035675378,
Shell:         "ioiStddevOverMedian": 1.2965264147217497
Shell:       },
Shell:       {
Shell:         "recording": "recording_1004",
Shell:         "groundTruthBpm": 129.19924461508316,
Shell:         "predictedBpm": 141.58818493150648,
Shell:         "absoluteErrorBpm": 12.388940316423316,
Shell:         "ioiStddevOverMedian": 0.944990383580662
Shell:       },
Shell:       {
Shell:         "recording": "recording_1005",
Shell:         "groundTruthBpm": 184.5699520118125,
Shell:         "predictedBpm": 102.3360148514853,
Shell:         "absoluteErrorBpm": 82.23393716032719,
Shell:         "ioiStddevOverMedian": 0.9171662995975662
Shell:       },
Shell:       {
Shell:         "recording": "recording_1006",
Shell:         "groundTruthBpm": 258.39904564619144,
Shell:         "predictedBpm": 191.4062499999999,
Shell:         "absoluteErrorBpm": 66.99279564619155,
Shell:         "ioiStddevOverMedian": 0.8437012329966382
Shell:       },
Shell:       {
Shell:         "recording": "recording_1007",
Shell:         "groundTruthBpm": 258.39904564619144,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 96.90002220869167,
Shell:         "ioiStddevOverMedian": 0.9476264484134093
Shell:       },
Shell:       {
Shell:         "recording": "recording_1008",
Shell:         "groundTruthBpm": 369.139904023625,
Shell:         "predictedBpm": 300.0,
Shell:         "absoluteErrorBpm": 69.13990402362498,
Shell:         "ioiStddevOverMedian": 0.49843670712799965
Shell:       },
Shell:       {
Shell:         "recording": "recording_1009",
Shell:         "groundTruthBpm": 198.76764062810574,
Shell:         "predictedBpm": 102.3360148514853,
Shell:         "absoluteErrorBpm": 96.43162577662044,
Shell:         "ioiStddevOverMedian": 0.4882146816338328
Shell:       },
Shell:       {
Shell:         "recording": "recording_1010",
Shell:         "groundTruthBpm": 172.2652885443583,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 10.766265106858526,
Shell:         "ioiStddevOverMedian": 0.29333362371282373
Shell:       },
Shell:       {
Shell:         "recording": "recording_1011",
Shell:         "groundTruthBpm": 215.33199707866257,
Shell:         "predictedBpm": 164.06250000000122,
Shell:         "absoluteErrorBpm": 51.269497078661345,
Shell:         "ioiStddevOverMedian": 0.4506552847699843
Shell:       },
Shell:       {
Shell:         "recording": "recording_1012",
Shell:         "groundTruthBpm": 198.7682991065365,
Shell:         "predictedBpm": 107.66601562499916,
Shell:         "absoluteErrorBpm": 91.10228348153733,
Shell:         "ioiStddevOverMedian": 0.0853385304049231
Shell:       },
Shell:       {
Shell:         "recording": "recording_1013",
Shell:         "groundTruthBpm": 95.70309073131517,
Shell:         "predictedBpm": 95.70312499999994,
Shell:         "absoluteErrorBpm": 0.00003426868477163225,
Shell:         "ioiStddevOverMedian": 0.5310073557402203
Shell:       },
Shell:       {
Shell:         "recording": "recording_1014",
Shell:         "groundTruthBpm": 151.99916907120908,
Shell:         "predictedBpm": 154.2677238805972,
Shell:         "absoluteErrorBpm": 2.268554809388121,
Shell:         "ioiStddevOverMedian": 0.500807345039918
Shell:       },
Shell:       {
Shell:         "recording": "recording_1015",
Shell:         "groundTruthBpm": 184.57051978134547,
Shell:         "predictedBpm": 187.92613636363643,
Shell:         "absoluteErrorBpm": 3.3556165822909634,
Shell:         "ioiStddevOverMedian": 0.48004503294593964
Shell:       },
Shell:       {
Shell:         "recording": "recording_1016",
Shell:         "groundTruthBpm": 52.20171613141782,
Shell:         "predictedBpm": 99.38401442307723,
Shell:         "absoluteErrorBpm": 47.182298291659414,
Shell:         "ioiStddevOverMedian": 0.29387977438339014
Shell:       },
Shell:       {
Shell:         "recording": "recording_1017",
Shell:         "groundTruthBpm": 184.57051978134547,
Shell:         "predictedBpm": 184.57031250000227,
Shell:         "absoluteErrorBpm": 0.00020728134319369929,
Shell:         "ioiStddevOverMedian": 0.4739648170222402
Shell:       },
Shell:       {
Shell:         "recording": "recording_1018",
Shell:         "groundTruthBpm": 161.49870801033592,
Shell:         "predictedBpm": 151.99908088235324,
Shell:         "absoluteErrorBpm": 9.499627127982677,
Shell:         "ioiStddevOverMedian": 0.3926983627051008
Shell:       },
Shell:       {
Shell:         "recording": "recording_1019",
Shell:         "groundTruthBpm": 103.35935117889953,
Shell:         "predictedBpm": 172.26562499999912,
Shell:         "absoluteErrorBpm": 68.90627382109959,
Shell:         "ioiStddevOverMedian": 0.2920731424692689
Shell:       },
Shell:       {
Shell:         "recording": "recording_1020",
Shell:         "groundTruthBpm": 151.99878400972793,
Shell:         "predictedBpm": 118.8038793103448,
Shell:         "absoluteErrorBpm": 33.19490469938313,
Shell:         "ioiStddevOverMedian": 0.9131116180252276
Shell:       },
Shell:       {
Shell:         "recording": "recording_1021",
Shell:         "groundTruthBpm": 258.3984892301663,
Shell:         "predictedBpm": 198.76802884615327,
Shell:         "absoluteErrorBpm": 59.63046038401305,
Shell:         "ioiStddevOverMedian": 0.8484668683497539
Shell:       },
Shell:       {
Shell:         "recording": "recording_1023",
Shell:         "groundTruthBpm": 123.04676084529024,
Shell:         "predictedBpm": 97.50884433962247,
Shell:         "absoluteErrorBpm": 25.537916505667766,
Shell:         "ioiStddevOverMedian": 0.7566775769379448
Shell:       },
Shell:       {
Shell:         "recording": "recording_1024",
Shell:         "groundTruthBpm": 172.26553583912695,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 10.766512401627182,
Shell:         "ioiStddevOverMedian": 0.30786002087659237
Shell:       },
Shell:       {
Shell:         "recording": "recording_1025",
Shell:         "groundTruthBpm": 198.7682991065365,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 37.269275669036716,
Shell:         "ioiStddevOverMedian": 0.6013462754217499
Shell:       },
Shell:       {
Shell:         "recording": "recording_1026",
Shell:         "groundTruthBpm": 52.7343647003194,
Shell:         "predictedBpm": 102.3360148514853,
Shell:         "absoluteErrorBpm": 49.601650151165906,
Shell:         "ioiStddevOverMedian": 0.422125131427463
Shell:       },
Shell:       {
Shell:         "recording": "recording_1027",
Shell:         "groundTruthBpm": 322.99741602067184,
Shell:         "predictedBpm": 219.91356382978523,
Shell:         "absoluteErrorBpm": 103.0838521908866,
Shell:         "ioiStddevOverMedian": 0.4508236452654108
Shell:       },
Shell:       {
Shell:         "recording": "recording_1028",
Shell:         "groundTruthBpm": 215.33238347826398,
Shell:         "predictedBpm": 198.76802884615563,
Shell:         "absoluteErrorBpm": 16.564354632108348,
Shell:         "ioiStddevOverMedian": 0.31189738036137177
Shell:       },
Shell:       {
Shell:         "recording": "recording_2001",
Shell:         "groundTruthBpm": 99.38398493338788,
Shell:         "predictedBpm": 107.66601562500054,
Shell:         "absoluteErrorBpm": 8.282030691612661,
Shell:         "ioiStddevOverMedian": 0.043820581889706244
Shell:       },
Shell:       {
Shell:         "recording": "recording_2002",
Shell:         "groundTruthBpm": 99.38398493338788,
Shell:         "predictedBpm": 118.8038793103448,
Shell:         "absoluteErrorBpm": 19.41989437695692,
Shell:         "ioiStddevOverMedian": 0.04024218183532168
Shell:       },
Shell:       {
Shell:         "recording": "recording_2003",
Shell:         "groundTruthBpm": 161.49914270871744,
Shell:         "predictedBpm": 164.06250000000003,
Shell:         "absoluteErrorBpm": 2.5633572912825855,
Shell:         "ioiStddevOverMedian": 1.0275414298840533
Shell:       },
Shell:       {
Shell:         "recording": "recording_2004",
Shell:         "groundTruthBpm": 95.70309073131517,
Shell:         "predictedBpm": 106.55605670103219,
Shell:         "absoluteErrorBpm": 10.852965969717019,
Shell:         "ioiStddevOverMedian": 1.338848624388184
Shell:       },
Shell:       {
Shell:         "recording": "recording_2005",
Shell:         "groundTruthBpm": 184.57051978134547,
Shell:         "predictedBpm": 191.4062499999999,
Shell:         "absoluteErrorBpm": 6.835730218654419,
Shell:         "ioiStddevOverMedian": 1.029828896707495
Shell:       },
Shell:       {
Shell:         "recording": "recording_2006",
Shell:         "groundTruthBpm": 206.71870235779906,
Shell:         "predictedBpm": 271.99835526316434,
Shell:         "absoluteErrorBpm": 65.27965290536528,
Shell:         "ioiStddevOverMedian": 0.840571041822228
Shell:       },
Shell:       {
Shell:         "recording": "recording_2007",
Shell:         "groundTruthBpm": 258.3979328165375,
Shell:         "predictedBpm": 184.57031250000227,
Shell:         "absoluteErrorBpm": 73.82762031653522,
Shell:         "ioiStddevOverMedian": 0.9225240132870023
Shell:       },
Shell:       {
Shell:         "recording": "recording_2008",
Shell:         "groundTruthBpm": 322.9991548188782,
Shell:         "predictedBpm": 215.33203125000108,
Shell:         "absoluteErrorBpm": 107.66712356887712,
Shell:         "ioiStddevOverMedian": 0.4067859409978997
Shell:       },
Shell:       {
Shell:         "recording": "recording_2009",
Shell:         "groundTruthBpm": 198.76764062810574,
Shell:         "predictedBpm": 202.66544117647464,
Shell:         "absoluteErrorBpm": 3.897800548368906,
Shell:         "ioiStddevOverMedian": 0.5008288941646035
Shell:       },
Shell:       {
Shell:         "recording": "recording_2010",
Shell:         "groundTruthBpm": 172.2657831346056,
Shell:         "predictedBpm": 166.70866935483818,
Shell:         "absoluteErrorBpm": 5.557113779767434,
Shell:         "ioiStddevOverMedian": 0.30068786334800685
Shell:       },
Shell:       {
Shell:         "recording": "recording_2011",
Shell:         "groundTruthBpm": 135.99906613974585,
Shell:         "predictedBpm": 184.57031250000227,
Shell:         "absoluteErrorBpm": 48.571246360256424,
Shell:         "ioiStddevOverMedian": 0.47931016708429364
Shell:       },
Shell:       {
Shell:         "recording": "recording_2012",
Shell:         "groundTruthBpm": 198.7682991065365,
Shell:         "predictedBpm": 202.66544117646978,
Shell:         "absoluteErrorBpm": 3.8971420699332953,
Shell:         "ioiStddevOverMedian": 0.07468706898320819
Shell:       },
Shell:       {
Shell:         "recording": "recording_2013",
Shell:         "groundTruthBpm": 151.99916907120908,
Shell:         "predictedBpm": 161.49902343750287,
Shell:         "absoluteErrorBpm": 9.499854366293789,
Shell:         "ioiStddevOverMedian": 0.5632953927068789
Shell:       },
Shell:       {
Shell:         "recording": "recording_2014",
Shell:         "groundTruthBpm": 95.70309073131517,
Shell:         "predictedBpm": 300.0,
Shell:         "absoluteErrorBpm": 204.29690926868483,
Shell:         "ioiStddevOverMedian": 0.5491915312984428
Shell:       },
Shell:       {
Shell:         "recording": "recording_2015",
Shell:         "groundTruthBpm": 156.60501214341366,
Shell:         "predictedBpm": 178.20581896551593,
Shell:         "absoluteErrorBpm": 21.60080682210227,
Shell:         "ioiStddevOverMedian": 0.5899363344180751
Shell:       },
Shell:       {
Shell:         "recording": "recording_2016",
Shell:         "groundTruthBpm": 103.35935117889953,
Shell:         "predictedBpm": 191.4062499999999,
Shell:         "absoluteErrorBpm": 88.04689882110036,
Shell:         "ioiStddevOverMedian": 0.3095804641151923
Shell:       },
Shell:       {
Shell:         "recording": "recording_2017",
Shell:         "groundTruthBpm": 95.70316705705584,
Shell:         "predictedBpm": 229.68750000000037,
Shell:         "absoluteErrorBpm": 133.98433294294455,
Shell:         "ioiStddevOverMedian": 0.5459216655988789
Shell:       },
Shell:       {
Shell:         "recording": "recording_2018",
Shell:         "groundTruthBpm": 198.76796986677576,
Shell:         "predictedBpm": 198.76802884615327,
Shell:         "absoluteErrorBpm": 0.00005897937751342397,
Shell:         "ioiStddevOverMedian": 0.3982030045898827
Shell:       },
Shell:       {
Shell:         "recording": "recording_2019",
Shell:         "groundTruthBpm": 50.17446078134179,
Shell:         "predictedBpm": 169.44159836065674,
Shell:         "absoluteErrorBpm": 119.26713757931495,
Shell:         "ioiStddevOverMedian": 0.33741178197104943
Shell:       },
Shell:       {
Shell:         "recording": "recording_2020",
Shell:         "groundTruthBpm": 151.99916907120908,
Shell:         "predictedBpm": 159.014423076923,
Shell:         "absoluteErrorBpm": 7.015254005713928,
Shell:         "ioiStddevOverMedian": 0.9300433862828307
Shell:       },
Shell:       {
Shell:         "recording": "recording_2021",
Shell:         "groundTruthBpm": 234.9072116513977,
Shell:         "predictedBpm": 258.3984375000066,
Shell:         "absoluteErrorBpm": 23.491225848608906,
Shell:         "ioiStddevOverMedian": 1.0095415144915127
Shell:       },
Shell:       {
Shell:         "recording": "recording_2022",
Shell:         "groundTruthBpm": 184.57051978134547,
Shell:         "predictedBpm": 187.92613636363643,
Shell:         "absoluteErrorBpm": 3.3556165822909634,
Shell:         "ioiStddevOverMedian": 0.5191224449407352
Shell:       },
Shell:       {
Shell:         "recording": "recording_2023",
Shell:         "groundTruthBpm": 191.40618146263034,
Shell:         "predictedBpm": 159.014423076923,
Shell:         "absoluteErrorBpm": 32.391758385707334,
Shell:         "ioiStddevOverMedian": 0.7171710017197096
Shell:       },
Shell:       {
Shell:         "recording": "recording_2024",
Shell:         "groundTruthBpm": 103.35935117889953,
Shell:         "predictedBpm": 191.4062499999999,
Shell:         "absoluteErrorBpm": 88.04689882110036,
Shell:         "ioiStddevOverMedian": 0.3230892854529361
Shell:       },
Shell:       {
Shell:         "recording": "recording_2025",
Shell:         "groundTruthBpm": 161.49892535923416,
Shell:         "predictedBpm": 172.26562499999997,
Shell:         "absoluteErrorBpm": 10.766699640765808,
Shell:         "ioiStddevOverMedian": 0.5982903510877592
Shell:       },
Shell:       {
Shell:         "recording": "recording_2026",
Shell:         "groundTruthBpm": 80.74946267961708,
Shell:         "predictedBpm": 149.796195652173,
Shell:         "absoluteErrorBpm": 69.04673297255592,
Shell:         "ioiStddevOverMedian": 0.4162757574287587
Shell:       },
Shell:       {
Shell:         "recording": "recording_2027",
Shell:         "groundTruthBpm": 322.99741602067184,
Shell:         "predictedBpm": 219.91356382978523,
Shell:         "absoluteErrorBpm": 103.0838521908866,
Shell:         "ioiStddevOverMedian": 0.4488499513163549
Shell:       },
Shell:       {
Shell:         "recording": "recording_2028",
Shell:         "groundTruthBpm": 215.33238347826398,
Shell:         "predictedBpm": 210.93749999999864,
Shell:         "absoluteErrorBpm": 4.394883478265342,
Shell:         "ioiStddevOverMedian": 0.31823422617437574
Shell:       },
Shell:       {
Shell:         "recording": "recording_4001",
Shell:         "groundTruthBpm": 80.74946267961708,
Shell:         "predictedBpm": 295.312500000001,
Shell:         "absoluteErrorBpm": 214.56303732038396,
Shell:         "ioiStddevOverMedian": 0.058091972516607
Shell:       },
Shell:       {
Shell:         "recording": "recording_4002",
Shell:         "groundTruthBpm": 80.74946267961708,
Shell:         "predictedBpm": 86.13281249999999,
Shell:         "absoluteErrorBpm": 5.383349820382904,
Shell:         "ioiStddevOverMedian": 0.04311599831446333
Shell:       },
Shell:       {
Shell:         "recording": "recording_4003",
Shell:         "groundTruthBpm": 135.99922027113712,
Shell:         "predictedBpm": 154.2677238805972,
Shell:         "absoluteErrorBpm": 18.268503609460083,
Shell:         "ioiStddevOverMedian": 1.079650456982293
Shell:       },
Shell:       {
Shell:         "recording": "recording_4004",
Shell:         "groundTruthBpm": 117.45383574864096,
Shell:         "predictedBpm": 149.796195652173,
Shell:         "absoluteErrorBpm": 32.34235990353204,
Shell:         "ioiStddevOverMedian": 0.8524758051831485
Shell:       },
Shell:       {
Shell:         "recording": "recording_4005",
Shell:         "groundTruthBpm": 258.3979328165375,
Shell:         "predictedBpm": 252.0960365853687,
Shell:         "absoluteErrorBpm": 6.301896231168797,
Shell:         "ioiStddevOverMedian": 0.9619192827389249
Shell:       },
Shell:       {
Shell:         "recording": "recording_4006",
Shell:         "groundTruthBpm": 206.71870235779906,
Shell:         "predictedBpm": 265.0240384615385,
Shell:         "absoluteErrorBpm": 58.30533610373945,
Shell:         "ioiStddevOverMedian": 0.7983313049291909
Shell:       },
Shell:       {
Shell:         "recording": "recording_4007",
Shell:         "groundTruthBpm": 258.3979328165375,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 96.89890937903772,
Shell:         "ioiStddevOverMedian": 0.9061149895441531
Shell:       },
Shell:       {
Shell:         "recording": "recording_4008",
Shell:         "groundTruthBpm": 172.26553583912695,
Shell:         "predictedBpm": 161.49902343749977,
Shell:         "absoluteErrorBpm": 10.766512401627182,
Shell:         "ioiStddevOverMedian": 0.4154793845616581
Shell:       },
Shell:       {
Shell:         "recording": "recording_4009",
Shell:         "groundTruthBpm": 322.99741602067184,
Shell:         "predictedBpm": 287.1093750000014,
Shell:         "absoluteErrorBpm": 35.888041020670414,
Shell:         "ioiStddevOverMedian": 0.5051398736190652
Shell:       },
Shell:       {
Shell:         "recording": "recording_4010",
Shell:         "groundTruthBpm": 172.2657831346056,
Shell:         "predictedBpm": 172.26562499999912,
Shell:         "absoluteErrorBpm": 0.0001581346064938316,
Shell:         "ioiStddevOverMedian": 0.2770076324672288
Shell:       },
Shell:       {
Shell:         "recording": "recording_4011",
Shell:         "groundTruthBpm": 271.99844054227424,
Shell:         "predictedBpm": 215.33203125000108,
Shell:         "absoluteErrorBpm": 56.66640929227316,
Shell:         "ioiStddevOverMedian": 0.4679972361141489
Shell:       },
Shell:       {
Shell:         "recording": "recording_4012",
Shell:         "groundTruthBpm": 161.49914270871744,
Shell:         "predictedBpm": 181.3322368421057,
Shell:         "absoluteErrorBpm": 19.833094133388244,
Shell:         "ioiStddevOverMedian": 0.0909597733255421
Shell:       },
Shell:       {
Shell:         "recording": "recording_4013",
Shell:         "groundTruthBpm": 184.57023589614232,
Shell:         "predictedBpm": 172.26562499999912,
Shell:         "absoluteErrorBpm": 12.304610896143203,
Shell:         "ioiStddevOverMedian": 0.49953875616057464
Shell:       },
Shell:       {
Shell:         "recording": "recording_4014",
Shell:         "groundTruthBpm": 151.99916907120908,
Shell:         "predictedBpm": 175.185381355932,
Shell:         "absoluteErrorBpm": 23.186212284722927,
Shell:         "ioiStddevOverMedian": 0.523876375661359
Shell:       },
Shell:       {
Shell:         "recording": "recording_4015",
Shell:         "groundTruthBpm": 151.99897654022462,
Shell:         "predictedBpm": 202.66544117647038,
Shell:         "absoluteErrorBpm": 50.66646463624576,
Shell:         "ioiStddevOverMedian": 0.5342567444414847
Shell:       },
Shell:       {
Shell:         "recording": "recording_4016",
Shell:         "groundTruthBpm": 107.66599853933128,
Shell:         "predictedBpm": 191.40625000000205,
Shell:         "absoluteErrorBpm": 83.74025146067076,
Shell:         "ioiStddevOverMedian": 0.30171197189561577
Shell:       },
Shell:       {
Shell:         "recording": "recording_4017",
Shell:         "groundTruthBpm": 143.55475058558375,
Shell:         "predictedBpm": 154.26772388059578,
Shell:         "absoluteErrorBpm": 10.712973295012034,
Shell:         "ioiStddevOverMedian": 0.4948022412166023
Shell:       },
Shell:       {
Shell:         "recording": "recording_4018",
Shell:         "groundTruthBpm": 99.38398493338788,
Shell:         "predictedBpm": 123.04687499999972,
Shell:         "absoluteErrorBpm": 23.662890066611837,
Shell:         "ioiStddevOverMedian": 0.36613071260563124
Shell:       },
Shell:       {
Shell:         "recording": "recording_4019",
Shell:         "groundTruthBpm": 52.7343647003194,
Shell:         "predictedBpm": 108.79934210526294,
Shell:         "absoluteErrorBpm": 56.06497740494354,
Shell:         "ioiStddevOverMedian": 0.31992959716828273
Shell:       },
Shell:       {
Shell:         "recording": "recording_4020",
Shell:         "groundTruthBpm": 139.67488342967022,
Shell:         "predictedBpm": 178.2058189655178,
Shell:         "absoluteErrorBpm": 38.53093553584759,
Shell:         "ioiStddevOverMedian": 0.836325772190036
Shell:       },
Shell:       {
Shell:         "recording": "recording_4021",
Shell:         "groundTruthBpm": 132.51205307549432,
Shell:         "predictedBpm": 219.9135638297881,
Shell:         "absoluteErrorBpm": 87.40151075429378,
Shell:         "ioiStddevOverMedian": 0.8736471421637002
Shell:       },
Shell:       {
Shell:         "recording": "recording_4022",
Shell:         "groundTruthBpm": 369.139904023625,
Shell:         "predictedBpm": 206.7187500000002,
Shell:         "absoluteErrorBpm": 162.42115402362478,
Shell:         "ioiStddevOverMedian": 0.49935991259726065
Shell:       },
Shell:       {
Shell:         "recording": "recording_4023",
Shell:         "groundTruthBpm": 271.99844054227424,
Shell:         "predictedBpm": 206.71874999999892,
Shell:         "absoluteErrorBpm": 65.27969054227532,
Shell:         "ioiStddevOverMedian": 0.8891082535902987
Shell:       },
Shell:       {
Shell:         "recording": "recording_4024",
Shell:         "groundTruthBpm": 103.35935117889953,
Shell:         "predictedBpm": 191.4062499999977,
Shell:         "absoluteErrorBpm": 88.04689882109817,
Shell:         "ioiStddevOverMedian": 0.31226062923320796
Shell:       },
Shell:       {
Shell:         "recording": "recording_4025",
Shell:         "groundTruthBpm": 161.49914270871744,
Shell:         "predictedBpm": 169.44159836065504,
Shell:         "absoluteErrorBpm": 7.942455651937593,
Shell:         "ioiStddevOverMedian": 0.5972413630039823
Shell:       },
Shell:       {
Shell:         "recording": "recording_4027",
Shell:         "groundTruthBpm": 161.49892535923416,
Shell:         "predictedBpm": 184.57031249999974,
Shell:         "absoluteErrorBpm": 23.07138714076558,
Shell:         "ioiStddevOverMedian": 0.4228467197341364
Shell:       },
Shell:       {
Shell:         "recording": "recording_4028",
Shell:         "groundTruthBpm": 103.35935117889953,
Shell:         "predictedBpm": 151.99908088235324,
Shell:         "absoluteErrorBpm": 48.63972970345371,
Shell:         "ioiStddevOverMedian": 0.3093650543607509
Shell:       }
Shell:     ]
Shell:   }
Shell: }
No tests ran.
No tests were found.
```
