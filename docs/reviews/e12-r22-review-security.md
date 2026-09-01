# E12-R22 — Security review (kötelező, risk = high)

- **Kör:** `E12-R22` — Beta distribution, tester enrollment és feedback
- **Munkapéldány:** `/tmp/review-e12-r22`, branch `sonnet-impl/e12-r22-beta-distribution-and-feedback`,
  HEAD `958df30c` (base `b2b37735`, 8 fájl). A klón a review végén **érintetlen**
  (`git status --short` üres, `git diff --stat` üres).
- **Szerződés:** ADR 0486 D1–D7 + brief §0.0.A R1–R9, §5, §6.
- **Reviewer:** security-reviewer (READ-ONLY, production kódot nem írtam).
- **Minden lelet MÉRT** — a próbák a `/tmp/claude-1001/.../scratchpad/probe`
  könyvtárban futottak, `python3 3.12.3`, a klón fájljait hívva.

## Összefoglaló

| Súlyosság | Db |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 1 |
| MAJOR | 3 |
| MINOR | 4 |
| NOTE | 5 |

A D1 (rétegzett consent), D4 (determinizmus), D5 (fail-closed jegyzet) és D6
(leltár-kereszt-ellenőrzés) **mérve tartják magukat**. A D2 (redakció) és a D3
(méret-korlát / „soha nem néma csonkolás") **nem**: a csomagoló hibaága a négy
redaktálandó osztályt szó szerint kiírja a stderr-re, a valósághű base64 hang
pedig csendben megsemmisül a kimenetben — a szállított A3 cella csak azért zöld,
mert a fixture csupa nulla bájt.

---

## BLOCKER

### B1 — A hibaüzenet a NEM redaktált session-részletet írja ki: token, e-mail, abszolút útvonal és eszköz-azonosító egy sorban

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:171`
  (`raise BundleError(f"malformed audio clip: {clip!r}")`), kiírás
  `tool/release/build_diagnostics_bundle.py:235`.
- **Sértett szabály:** nem tárgyalható termékhatár **#3** (secret/token/PII nem
  kerülhet logba, jelzésfájlba, **hibaüzenetbe**); ADR 0486 D2 szelleme
  („a redakció az EGYETLEN hely, ahol a titok eltűnik") és
  `docs/beta/tester-consent.md:97-100` állítása („a report-építés az egyetlen
  hely, ahol a maszkolás garantáltan megtörtént, mielőtt a reportot bárki
  elolvassa").
- **Failure scenario:** a szerver bájtra verbatim tárol (ADR 0486 Kontextus), a
  csomagoló bemenete tehát tetszőleges kliens-JSON. Ha egy `audioClips` elem
  bármi okból nem tartalmaz `wavBase64`-t (régi/idegen kliens-alak, kézzel
  szerkesztett session, csonka feltöltés), a `_raw_audio_byte_count` a **teljes
  klip-dictet `repr`-rel** beteszi a hibaüzenetbe, ami a triage-operátor
  termináljára / CI-logjába kerül. A redakció ekkor még **le sem futott**
  (`main:224` a nyers `session`-t adja át, a `redact()` csak `main:232`-ben fut).
- **Repró:**

```bash
cd <scratch>
python3 -c "
import json
json.dump({'sessionId':'s','audioClips':[{'tSec':0,'diagToken':'tok-REAL-123',
  'contact':'tester.person@example.com','file':'/home/tester/Music/take.wav',
  'deviceId':'AAAA-BBBB'}]}, open('clip.json','w'))"
python3 /tmp/review-e12-r22/tool/release/build_diagnostics_bundle.py \
  --session-file clip.json --output clip_out.json \
  --consent-diagnostics --consent-raw-audio; echo "exit=$?"
```

- **Tényleges kimenet (stderr):**

```
build_diagnostics_bundle: malformed audio clip: {'tSec': 0, 'diagToken': 'tok-REAL-123',
'contact': 'tester.person@example.com', 'file': '/home/tester/Music/take.wav',
'deviceId': 'AAAA-BBBB'}
exit=1
(no output file)
```

  Mind a négy D2-osztály (token, e-mail, abszolút útvonal, device-id) szó
  szerint. (A kimeneti fájl helyesen nem jött létre — a szivárgás kizárólag a
  hibacsatornán történik, de az is csatorna.)
- **Javasolt irány:** a hibaüzenet ne hordozzon bemeneti tartalmat — index/kulcs
  szintű azonosítás elég (`malformed audio clip at audioClips[3]: missing
  "wavBase64"`); ha a tartalom mégis kell, a `redact()`-en átvezetve. Ugyanezt
  a mintát érdemes a `_raw_audio_byte_count` base64-hibaágára is alkalmazni
  (`:175`, ott a `binascii.Error` üzenete ma nem hordoz adatot, de a jövőben
  igen). Mérés-oldal: egy backend pytest cella, ami a stderr-t vizsgálja a fenti
  bemenettel (ma **egyetlen** teszt sem nézi a stderr tartalmát).

---

## MAJOR

### M1 — A valósághű nyers hang CSENDBEN megsemmisül a csomagban (D3 „soha nem néma csonkolás" megsértése); az A3 cella csak a csupa-nulla fixture miatt zöld

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:95`
  (`_POSIX_PATH_PATTERN`) → alkalmazva `:111` (`_redact_string`), a méret-mérés
  a redakció ELŐTTI adaton `:224`. A hamis zöld forrása:
  `test/tooling/beta_release_notes_test.dart:56`
  (`'wavBase64': base64Encode(Uint8List(rawByteCount))`) és az erre épülő
  állítások `:401-402`, `:423-424`.
- **Sértett szabály:** ADR 0486 **D3** („NEM elfogadható gyengítés: csendes
  csonkolás; …"), és a `docs/beta/feedback-triage.md:58-60` állítása
  („there is no partial clip; the tool wrote nothing").
- **Failure scenario:** a base64 ábécé tartalmazza a `/` karaktert. Egy valódi
  16-bit WAV base64-je néhány ezer `/`-t tartalmaz, és két `/` közti szakasz
  kielégíti a „legalább két szegmens" POSIX-útvonal mintát → a minta a
  hangadatba harap, és `[REDACTED:path]`-ra cseréli. A csomagoló **exit 0**-val,
  figyelmeztetés nélkül ír ki egy fájlt, amiben a klip 0,1–3 %-a maradt, és ami
  már nem is dekódolható base64-ként. A triager a `feedback-triage.md` alapján
  azt hiszi, ép klipet kapott. A méret-korlát ellenőrzése a redakció ELŐTTI
  bájtszámon fut, tehát a „5 242 880 bájton elfogadva" üzenet mögött a lemezen
  ~194 000 base64-karakternyi szemét van.
- **Repró (a szállított A3 cella szemantikája, de valósághű klippel — 1 kHz
  szinusz, 44,1 kHz, 2 s, ahogy a `clipFromPcm` előállítja):**

```bash
python3 - <<'EOF'
import base64, json, math, struct, subprocess, sys
sr=44100; n=sr*2
pcm=b''.join(struct.pack('<h', int(20000*math.sin(2*math.pi*1000*i/sr))) for i in range(n))
hdr=(b'RIFF'+struct.pack('<I',36+len(pcm))+b'WAVEfmt '+struct.pack('<IHHIIHH',16,1,1,sr,sr*2,2,16)
     +b'data'+struct.pack('<I',len(pcm)))
wav=hdr+pcm; b64=base64.b64encode(wav).decode()
print('raw wav bytes', len(wav), '| slashes in base64:', b64.count('/'))
json.dump({'sessionId':'fixture-session','events':[],
  'audioClips':[{'tSec':0,'wavBase64':b64}]}, open('sine.json','w'))
p=subprocess.run([sys.executable,'/tmp/review-e12-r22/tool/release/build_diagnostics_bundle.py',
  '--session-file','sine.json','--output','sine_out.json',
  '--consent-diagnostics','--consent-raw-audio'],capture_output=True,text=True)
print('exit', p.returncode, p.stderr[:200])
out=json.load(open('sine_out.json'))['session']['audioClips'][0]['wavBase64']
print('a szállított A3 állítás: base64Decode(clip).length == %d' % len(wav))
try: print('valóság:', len(base64.b64decode(out, validate=True)))
except Exception as e: print('valóság: base64Decode DOB ->', type(e).__name__, e)
print('megmaradt a consentelt klipből: %.1f%%' % (100*len(out)/len(b64)))
EOF
```

- **Tényleges kimenet:**

```
raw wav bytes 176444 | slashes in base64: 2800
exit 0
a szállított A3 állítás: base64Decode(clip).length == 176444
valóság: base64Decode DOB -> Error Only base64 data is allowed
megmaradt a consentelt klipből: 0.1%
```

  Ugyanez pontosan a küszöbön (5 242 880 véletlen bájt, `os.urandom`):
  `input b64 chars 6990508 -> output b64 chars 194052 (2.8% kept)`, exit 0,
  a kimenet nem dekódolható.
- **Miért zöld mégis a gate:** `audioClip(n)` a `Uint8List(n)`-t kódolja, ami
  csupa nulla bájt → a base64 csupa `A` (+`=`), **egyetlen `/` sincs benne**,
  tehát a POSIX-minta nem talál. A `Uint8List(n)` fixture nem „egyszerűsítés",
  hanem pontosan az az egyetlen bemenet, amelyen a hiba nem látszik. Valódi
  mikrofon-felvétel soha nem csupa nulla.
- **Javasolt irány:** (a) a `wavBase64` (általánosabban: base64/opaque bináris)
  mezőket ne érje sztring-redakció — vagy a bejárás zárja ki őket explicit,
  nevesített allowlisttel, vagy a redakció fusson a base64 DEKÓDOLT tartalmán
  („nincs sztring-redakció bináris payloadon"); (b) a szigorítás után a
  csomagoló ellenőrizze, hogy a kimeneti klip még dekódolható és a
  bájthossza változatlan — ha nem, az legyen HIBA (nem-nulla kilépés), mert
  éppen ez a D3 lényege; (c) a fixture legyen nem-degenerált (véletlen vagy
  szinusz PCM), különben a cella nem tud pirosra váltani.

### M2 — A `--consent-raw-audio` réteg és a D3 méret-korlát EGYETLEN legfelső szintű kulcsnéven áll: máshol elhelyezett hang consent nélkül és korlát nélkül átmegy

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:190`
  (`redacted_session.pop("audioClips", None)`) és `:164-176`
  (`_raw_audio_byte_count` szintén csak `session["audioClips"]`-et nézi).
- **Sértett szabály:** ADR 0486 **D1** (a nyers hang külön, alapból kikapcsolt
  réteg) és **D3** (méret-korlát); nem tárgyalható termékhatár **#1**
  (nyers audio nem hagyhatja el az eszközt alapértelmezetten — a csomag az az
  artefaktum, amivel a hang ténylegesen távozik a tesztelőtől).
- **Failure scenario:** a csomagoló bemenete a szerveren **verbatim** tárolt,
  tetszőleges kliens-JSON. Ha a klip nem a legfelső szintű `audioClips` listában
  van (beágyazott `events[i].wavBase64`, `capture.audioClips`, régebbi vagy
  jövőbeli payload-alak, kézzel szerkesztett session), a `pop` nem találja meg,
  és a hang **csak `--consent-diagnostics`-szal is** bekerül a csomagba — ráadásul
  a méret-korlát sem fut rá, tehát tetszőlegesen nagy klip mehet.
- **Repró:**

```bash
python3 - <<'EOF'
import base64, json
clip = base64.b64encode(bytes(20*1024*1024)).decode()   # 20 MB = a D3 korlát 4x-e
json.dump({'sessionId':'s','surface':'analyze',
  'events':[{'tSec':0.0,'wavBase64':clip}],
  'capture':{'audioClips':[{'tSec':1.0,'wavBase64':clip}]}}, open('nested.json','w'))
EOF
python3 /tmp/review-e12-r22/tool/release/build_diagnostics_bundle.py \
  --session-file nested.json --output nested_out.json --consent-diagnostics
echo "exit=$?  (CSAK --consent-diagnostics)"
python3 -c "
import json; d=json.load(open('nested_out.json'))['session']
print('events[0].wavBase64 :', len(d['events'][0]['wavBase64']), 'b64 chars')
print('capture.audioClips  :', len(d['capture']['audioClips'][0]['wavBase64']), 'b64 chars')"
```

- **Tényleges kimenet:**

```
exit=0  (CSAK --consent-diagnostics)
events[0].wavBase64 : 27962028 b64 chars
capture.audioClips  : 27962028 b64 chars
```

  20 MB dekódolt hang egy olyan csomagban, amihez a tesztelő a hang-réteget nem
  engedélyezte, és amire a 5 242 880 bájtos korlát rá sem futott.
- **Mai elérhetőség:** a SZÁLLÍTOTT kliens-alak
  (`lib/features/diagnostics/model/diagnostics_session.dart:100-108`) fix
  kulcsokkal, legfelső szinten teszi be az `audioClips`-et, tehát a normál úton
  ma nem áll elő ilyen session — a lelet **latens**, de a bemenet nem megbízható,
  és egyetlen payload-alak-változás (vagy egy idegen feltöltés) élessé teszi,
  miközben minden szállított teszt zöld marad.
- **Javasolt irány:** a hang-réteg gate-je legyen TARTALOM-alapú, ne kulcsnév-
  alapú: rekurzív bejárás, ami minden `wavBase64` (vagy általában base64-audio)
  mezőt megtalál, `--consent-raw-audio` nélkül **mindet** eltávolítja, a
  korlátot pedig az ÖSSZES megtalált klip összegére alkalmazza. Fail-closed
  alternatíva: ismeretlen session-alakra (nem várt top-level kulcs) nem-nulla
  kilépés. Mérés: cella beágyazott `wavBase64`-gyel, `--consent-diagnostics`-
  szal → a kimenetben nem szerepelhet a `wavBase64` kulcs.

### M3 — Korlátlan gzip-kicsomagolás nem megbízható bemeneten (dekompressziós bomba)

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:148-152`
  (`gzip.decompress(raw)`, méret-korlát nélkül).
- **Sértett szabály:** brief „Importált tartalom" (zip bomb / méretkorlát);
  ADR 0486 D3 szellemével is szemben álló hiány (a kör központi témája a
  méret-korlát, de csak a base64 hangra van).
- **Failure scenario:** a `/diagnostics` végpontot csak az `X-Diag-Token`
  „eldobható spam-gate" védi (ADR 0486 Kontextus, `lab-apk.yml:8-10`), a router
  a bájtokat verbatim tárolja. Egy 2 MB-os feltöltés, ami 2 GB-ra bomlik ki,
  a triage-gépen memória-kimerülést okoz, mikor az operátor csomagot épít
  belőle; a hiba nem a `BundleError` ágon jön, hanem nyers traceback.
- **Repró:**

```bash
python3 - <<'EOF'
import gzip
payload = b'{"pad":"' + b'A'*(2*1024*1024*1024) + b'"}'
with gzip.open('bomb.json.gz','wb',compresslevel=9) as f: f.write(payload)
EOF
ls -l bomb.json.gz          # 2 087 305 bájt
( ulimit -v 3000000; python3 /tmp/review-e12-r22/tool/release/build_diagnostics_bundle.py \
  --session-file bomb.json.gz --output bomb_out.json --consent-diagnostics ) 2>&1 | tail -5
```

- **Tényleges kimenet:**

```
-rw-rw-r-- 1 ubuntu ubuntu 2087305 ... bomb.json.gz
  File "/tmp/review-e12-r22/tool/release/build_diagnostics_bundle.py", line 150, in _load_session
    raw = gzip.decompress(raw)
MemoryError: Unable to allocate output buffer.
maxRSS child MB= 2063.9   wall=4.3s      (ulimit nélkül a 24 GB RAM-ig menne)
```

- **Javasolt irány:** `gzip.GzipFile` inkrementális olvasás explicit
  felső korláttal (`read(limit + 1)` → ha többet ad, `BundleError`), plusz egy
  korlát a bemeneti fájl és a dekódolt JSON méretére is. A korlát legyen MÉRT
  konstans (a kliens ~8 MB-os upload-budgetjéből levezetve), ne kitalált.

---

## MINOR

### N1 — A JSON objektum-KULCSOK maguk soha nem redaktálódnak (e-mail / abszolút útvonal kulcsnévben átmegy)

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:119-128` — a kulcs csak
  osztály-KIVÁLASZTÁSRA szolgál (`_TOKEN_KEY_PATTERN.search(key)`,
  `key in _DEVICE_ID_KEYS`), maga a kulcs sztring változatlanul kerül a
  `result`-ba; a `_redact_string` csak értékekre fut (`:131-132`).
- **Sértett szabály:** ADR 0486 **D2** („a redakció … kulcs- és sztringérték-
  szinten egyaránt"); `docs/beta/tester-consent.md:88-90` („anywhere in any text
  field").
- **Failure scenario:** egy útvonal- vagy e-mail-kulcsú map (pl. jövőbeli
  „per-file" vagy „per-tester" bontás) esetén a PII a kulcsnévben, szó szerint
  kerül a csomagba; minden szállított teszt zöld marad, mert egyik sem tesz
  PII-t kulcsnévbe.
- **Repró / tényleges kimenet** (a `p1_session.json` `byKey` szakasza,
  `--consent-diagnostics --consent-raw-audio`):

```json
"byKey": {
  "/home/tester/Music/secret.wav": "value-under-path-key",
  "authToken": "[REDACTED:token]",
  "tester.person@example.com": "value-under-email-key"
}
```

- **Ma elérhető?** A szállított kliens-alak fix kulcsokat használ → latens.
- **Javasolt irány:** a `redact()` a kulcsra is futtassa a `_redact_string`-et
  (a token/device-id kiválasztás UTÁN, hogy az osztályozás ne sérüljön), és
  kezelje a kulcs-ütközést determinisztikusan (két különböző e-mail-kulcs
  ugyanarra a `[REDACTED:email]`-re képződne — ez a D4 miatt nem hash-elhető,
  tehát ütközésre inkább `BundleError`).

### N2 — A kimeneti fájl világ-olvasható (0664), és a `--output` szimlinken keresztül ír

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:238`
  (`Path(args.output).write_bytes(output_bytes)`), ill.
  `tool/release/generate_beta_notes.py:197`.
- **Failure scenario:** a csomag TESZTELŐI adatot hordoz (consentelt
  diagnosztika, `--consent-raw-audio` mellett nyers hang). Alapértelmezett
  umask 0002 mellett a fájl `-rw-rw-r--` — a triage-gép minden felhasználója
  olvassa. Ha a `--output` egy szimlink, a tool követi és a célfájlba ír.
- **Repró / tényleges kimenet:**

```
$ umask; stat -c '%a %n' d1.json
0002
664 d1.json
$ ln -sf "$PWD/victim.txt" link.json && python3 ...--output link.json --consent-diagnostics; echo $?
0
$ head -c 60 victim.txt
{"schemaVersion":1,"session":{"events":[{"a":1}],"sessionId"
```

- **Javasolt irány:** `os.open(..., O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0o600)`
  (vagy `write_bytes` + `os.chmod(0o600)` a létrehozás közvetlen közelében),
  szimlink-célra fail-closed.

### N3 — Az e-mail-osztály nem fogja meg a nem-ASCII (IDN) alakot, sem a base64-be csomagolt címet

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:81-83` (`_EMAIL_PATTERN`
  ASCII-only karakterosztályok).
- **Failure scenario:** HU-lokalizált app, HU tesztelő: `tesztelő@példa.hu`
  változatlanul kerül a csomagba, miközben a doksi szerint „an e-mail address
  appearing anywhere in any text field" maszkolva van. A base64-be csomagolt
  cím (`dGVzdGVyLnBlcnNvbkBleGFtcGxlLmNvbQ==`) szintén átmegy.
- **Tényleges kimenet (p1 próba):**
  `"emailUnicode": "tesztelő@példa.hu"`, `"emailB64": "dGVzdGVyLnBlcnNvbkBleGFtcGxlLmNvbQ=="`
  (a `"emailUpperTLD": "[REDACTED:email]"` viszont helyesen maszkolt → a
  kis/nagybetű nem probléma).
- **Javasolt irány:** unicode-tűrő local-part/domain karakterosztály (a
  korlátos kvantorokat megtartva, a ReDoS-érv miatt jogosan); a base64-alak
  fedése nem kötelező, de nevesített hiányként a doksiba való.

### N4 — A titok-osztályt egyedül a `token` kulcs-részsztring definiálja: `Authorization: Bearer …`, `apiKey`, `password` értéke szó szerint átmegy

- **Fájl:sor:** `tool/release/build_diagnostics_bundle.py:67`, `:122`.
- **Failure scenario:** ha bármikor bekerül a session-payloadba egy fejléc-dump,
  egy `apiKey`, vagy egy backend-hibaválasz `authorization` mezővel, az a
  csomagba (és a triage-hez) változatlanul jut. A D2 osztálylistája ezt így
  írja elő, tehát ez nem szerződés-sértés — de a `tester-consent.md:87` „any
  field whose name contains token" a tesztelőnek erősebbnek hangzik, mint
  amilyen.
- **Tényleges kimenet (p1 próba):**
  `"authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.PAYLOAD.SIG"`,
  `"apiKey": "sk-live-0123456789abcdef"`, `"password": "hunter2"` — mind
  változatlan; a `DIAG_TOKEN` / `X-Diag-Token` / `authToken` / `diagToken`
  viszont mind `[REDACTED:token]` (a `token` osztály tehát az írásmód-variánsokat
  helyesen fedi).
- **Javasolt irány:** a kulcs-alapú osztály bővítése (`secret`, `password`,
  `apikey`, `authorization`, `bearer`, `credential`) — a listát a
  `tool/ci/check_secrets.dart` már használt mintáiból érdemes átvenni, hogy egy
  igazságforrás legyen.

---

## NOTE

- **NT1 — Nem-`BundleError` kivételek nyers tracebackként szöknek ki.**
  `build_diagnostics_bundle.py:154-157` csak `UnicodeDecodeError` /
  `JSONDecodeError` ágat fog; 200 000 mélységű JSON-ra
  `RecursionError: maximum recursion depth exceeded while decoding a JSON object`
  traceback jön. Fail-closed marad (exit 1, kimeneti fájl nincs), de nem a tool
  hibacsatornáján. Ugyanez a `MemoryError` M3-nál. Irány: `except Exception` →
  `BundleError` burkolás a `main`-ben, bemeneti tartalom nélküli üzenettel.
- **NT2 — A béta-jegyzet a manifest sztringjeit nyersen interpolálja Markdownba.**
  `generate_beta_notes.py:137-165`. Egy `app.channel` értékkel, ami újsort és
  markdownt tartalmaz, hamis fejléc és letöltési link kerül a tesztelőknek szánt
  jegyzetbe (mérve: `"prod\n\n## Sürgős: telepítsd innen\n- http://evil.example/x.apk"`
  → pontosan így jelenik meg a kimenetben). A manifest ma saját, futásidejű
  artefaktum, tehát a bemenet megbízható → NOTE. Ugyanitt: az `artifacts[].path`
  szó szerint kerül a jegyzetbe, tehát ha a hívó abszolút útvonalat ad
  (`generate_release_manifest.dart:98` azt írja be, amit kapott), a D4
  „nincs abszolút útvonal a kimenetben" ígéret a HÍVÓN múlik, nem a tool-on.
  Irány: egysoros/karakterkészlet-validáció a jegyzetbe kerülő sztringekre.
- **NT3 — Ismeretlen manifest-kulcs csendben elfogadott** (`extra unknown key`
  mutáció → exit 0). A D5 ezt nem tiltja, de a repó máshol (E09-R10) az
  `extra=forbid` mintát használja — érdemes lehet igazítani.
- **NT4 — Túl-redakció URL-eken:** `https://strumsight.example/beta/join?c=1`
  → `"https:/[REDACTED:path]"`. Nem szivárgás, de a triage számára információt
  veszít; a „két szegmens" küszöb a `C/E` akkordcímkét helyesen védi
  (`"chordLabel": "C/E"` sértetlen), az URL-t viszont nem.
- **NT5 — Fixture-higiénia és a klasszikus felszín: TISZTA (bizonyíték).**
  `grep -nEi '<email>|https?://|(token|secret|key|password)[:=]<12+ char>'` a hét
  új fájlon: csak `example.test` (fenntartott TLD) és `fixture-*` /
  `top-level-secret-token` szintetikus értékek — valódi tesztelői adat, valódi
  token, valódi e-mail sehol (brief §3 megtartva). A két Python eszközben nincs
  `eval` / `exec` / `pickle` / `yaml.load` / `subprocess` / `shell=True` /
  hálózati hívás (`grep` mind a hatra: 0 találat). Egy előre létező kimeneti
  fájlt a hibás futás **nem csonkít** (mérve: `keep.json` tartalma
  `PRE-EXISTING` maradt a méret-korlát-hiba után), mert az írás minden
  ellenőrzés után, egyetlen ponton történik.

---

## Amit végignéztem és MÉRTEM zöldnek (az üres lelet is bizonyíték)

| Szerződés | Mérés | Eredmény |
|---|---|---|
| **D1** rétegzett consent, 4 bemenet/kimenet pár (R5) | mind a négy kombináció futtatva `p3.json`-nal | `''→exit 1, fájl nincs` · `--consent-diagnostics→exit 0, audioClips NINCS` · `--consent-raw-audio→exit 1, fájl nincs` · `mindkettő→exit 0, audioClips VAN`. Részleges/félkész fájl egyik hibaágon sem keletkezett (a `write_bytes` az utolsó művelet). **PONTOSAN a táblázat szerint** |
| **D2** token-osztály írásmód-variánsai | `diagToken`, `X-Diag-Token`, `authToken`, `DIAG_TOKEN` | mind `[REDACTED:token]` |
| **D2** e-mail bármely sztringértékben, tetszőleges mélységben | top-level, listaelem, listán belüli dict, nem-`email` nevű kulcs (`contactNote`, `note`, `reporter.contactEmail`) | mind `[REDACTED:email]` |
| **D2** abszolút útvonal POSIX + Windows | `/data/user/0/…`, `/Users/…`, `C:\Users\…`, `C:\diag.json` | mind `[REDACTED:path]`; `C/E` akkordcímke sértetlen |
| **D2** device-id zárt lista | `deviceId`, `device_id`, `androidId`, `installId`, `udid` | mind `[REDACTED:device-id]`; a listán kívüliek (`deviceID`, `device_uuid`, `advertisingId`) szándék szerint átmennek — D2 zárt listát ír elő |
| **D2** nem-string skalárok | int / float / bool / null | változatlanul átmennek, hiba nélkül |
| **D3** küszöb-hármas | 5 242 879 / 5 242 880 / 5 242 881 dekódolt bájt | `exit 0` / `exit 0` / `exit 1 + „rejected, not truncated" + kimeneti fájl NINCS`. Az inkluzív határ tartja magát (a klip-integritásra lásd M1) |
| **D4** determinizmus | két futás `PYTHONHASHSEED=0/LC_ALL=C` vs `PYTHONHASHSEED=random/LC_ALL=hu_HU.UTF-8/TZ=Asia/Tokyo` | `cmp` bájtazonos, sha256 egyezik; a jegyzetnél ugyanez. Időbélyeg, gépnév, saját abszolút útvonal a kimenetekben nincs |
| **D5** fail-closed jegyzet | 8 mutáció: hiányzó `app.shortSha`, `null`, `"42"` string buildNumber, `true` buildNumber, üres `app.version`, hiányzó `artifacts`, hiányzó `artifacts[0].sha256`, hiányzó `knowledgePackage` | **mind exit 1**, a hiányzó kulcsot NEVESÍTVE, stdout üres — `unknown`/üres mező sehol |
| **D6** leltár-kereszt-ellenőrzés | független újraparszolás (`yaml.safe_load`) → 12 `leaves_device: true` mező 3 útvonalon; a `tester-consent.md` blokk 12 sora **szó szerint** ugyanaz; `grep -c "leaves_device: true"` = 12 | teljes fedés; a teszt (`beta_release_notes_test.dart:787-900`) valóban kétirányú és a SZÁLLÍTOTT `DataInventory.parseFile`-t importálja (nincs második parszer) |
| **D7** felület-tilalom | `git diff --stat b2b37735..HEAD` | 8 fájl, `lib/**`, `.github/**`, `lab_build.json`, `docs/adr/**`, `tools/**` érintetlen |
| Ellátási lánc | új dependency: **nincs** (csak stdlib: argparse, base64, binascii, gzip, json, re, sys, pathlib); új asset: nincs | rendben |
| Path traversal | `--session-file` / `--output` / `--manifest` operátor-megadott útvonalak, nincs archívum-kicsomagolás fájlnevekkel → klasszikus `../` traversal-felület **nincs** | rendben (a szimlink/jogosultság kérdés N2) |

---

## Mit kérek a merge előtt

1. **B1** — a hibaüzenet ne hordozzon bemeneti tartalmat (blokkoló: §5.3).
2. **M1** — a nyers hang ne essen sztring-redakció alá, és a fixture legyen
   nem-degenerált, hogy az A3 cella pirosra tudjon váltani.
3. **M2** — a hang-réteg és a méret-korlát tartalom-alapú legyen, ne egyetlen
   legfelső szintű kulcsnéven álljon.
4. **M3** — korlát a gzip-kicsomagolásra.

A MINOR/NOTE tételek follow-upban is rendezhetők, de N1 és N2 olcsó és a
kör saját témájába vág.

VERDIKT: CHANGES REQUESTED
