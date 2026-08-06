# Vision camera spike — device measurement runbook (E05-R02)

- **Status:** executable device procedure; every result begins as `PENDING`
- **Applies after:** E05-R06 supplies an unsigned, local **camera-spike APK**
  with the `VISION_CAMERA_SPIKE` instrumentation described below. This E05-R02
  docs-only round does not add that APK, a plugin, a permission, or a route.
- **Record results in:** [vision device matrix](vision-device-matrix.md), section 2.8
- **Decision rule:** [ADR 0184](../adr/0184-vision-camera-capture-stack.md)

## 1. Preconditions and instrumentation contract

Use a physical Android 24+ device, USB debugging enabled, a camera-spike APK
that uses exactly one candidate (`C1`, `C2`, or `C3`) per run, and a quiet
device (no other camera app). Replace `<serial>` and `<apk>` before executing:

```bash
adb -s <serial> install -r <apk>
adb -s <serial> shell pm clear com.wolfcasaba.strumsight
adb -s <serial> shell am start -n com.wolfcasaba.strumsight/.MainActivity --es vision_candidate C1
adb -s <serial> logcat -c
```

The later spike must emit one parseable line per event, with no raw frame data:

```text
VISION_CAMERA_SPIKE candidate=<C1|C2|C3> event=<init|frame|drop|close|lifecycle|memory> elapsed_ms=<integer> frame_seq=<integer> timestamp_ns=<integer> delivered_fps=<number> processed_fps=<number> copies=<integer> open_clients=<integer> rss_kb=<integer>
```

`frame_seq`, `timestamp_ns`, `copies`, `open_clients`, and `rss_kb` are required
only for their corresponding rows below. `timestamp_ns` is the capture/analysis
timestamp forwarded to the adapter, not a wall-clock replacement. Logs must
contain metadata and aggregates only; [ADR 0178](../adr/0178-vision-privacy-by-default.md)
forbids raw-frame logging.

## 2. Measurement rows and numeric PASS rules

Run every row for C1. Run C2 only after a C1 disqualifier. Run C3 only after a
specific preview-plus-analysis need is documented. Each command is executed on
the selected physical device and each row maps one-to-one to a PENDING matrix
row (`M01`–`M12`).

| ID | Command / observation | Record | PASS condition |
| --- | --- | --- | --- |
| M01 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_START --ei iterations 20`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | 20 init `elapsed_ms`, p50, p95 | p95 first-frame init **≤ 2000 ms**; 20/20 starts produce a first frame. |
| M02 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_SOAK --ei seconds 300`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | delivered and processed FPS by 30 s window | every window has processed FPS **≥ 15.0** and delivered FPS **≥ processed FPS**. |
| M03 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_FORMAT`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | format, plane count, width, height | 20/20 frames report `YUV_420_888` or a documented adapter-converted equivalent; no unknown format. |
| M04 | Rotate portrait → landscape → portrait while running `CAMERA_SPIKE_SOAK`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | rotation degrees and frame continuity | each orientation transition is reported within **1000 ms** and no timestamp regression occurs. |
| M05 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_COPY_AUDIT --ei frames 300`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | `copies` for 300 frames | **≤ 1** full-frame copy per processed frame; no retained queue depth above **1**. |
| M06 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_STOP --ei iterations 20`; then `adb -s <serial> shell dumpsys media.camera`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | 20 close `elapsed_ms`, `open_clients` | every close completes within **2000 ms** and `open_clients=0` within **2000 ms**; no camera client remains in `dumpsys media.camera`. |
| M07 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_FRONT_MIRROR`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | preview and analysis coordinate handedness | 20/20 calibration markers have the same handedness after the documented transform; mismatch count **0**. |
| M08 | `adb -s <serial> shell settings put system accelerometer_rotation 1`; physically rotate twice during a 60-second stream; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | transition count, delivered/processed FPS | 2/2 transitions preserve a running stream or recover it within **1000 ms**; processed FPS remains **≥ 15.0**. |
| M09 | `adb -s <serial> shell input keyevent KEYCODE_HOME`; wait 5 seconds; `adb -s <serial> shell am start -n com.wolfcasaba.strumsight/.MainActivity`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | background close and foreground state | camera reaches `open_clients=0` within **2000 ms** in background; foreground does **not** restart capture without an explicit user start; an explicit start reaches first frame within **2000 ms**. |
| M10 | `adb -s <serial> shell am broadcast -a com.wolfcasaba.strumsight.CAMERA_SPIKE_TIMESTAMP --ei frames 1000`; then `adb -s <serial> logcat -d -s VisionCameraSpike:I` | 1000 `frame_seq`/`timestamp_ns` pairs and dropped count | all retained timestamps are strictly increasing (`t[n] > t[n-1]`); sequence gaps are permitted only with a matching `drop`; no retained frame older than the most recently received frame. |
| M11 | `adb -s <serial> shell getprop ro.build.version.release`; `adb -s <serial> shell dumpsys package com.wolfcasaba.strumsight`; and inspect the cited official package/licence source | Android version, APK package/version, dependency/version and licence | package/version and licence are recorded; Android is **≥ 24**; unsupported versions are `FAIL`, not silently accepted. |
| M12 | In the later dependency-adoption branch run `flutter pub deps --style=compact`; for C2/C3 also run `cd android && ./gradlew :app:dependencies --configuration debugRuntimeClasspath` | resolved `win32` major and CameraX/Gradle tree | exactly one resolved Dart `win32` major (**6.x**, matching `flutter_secure_storage`) and no Gradle resolution failure. |

## 3. Required sequences

### 3.1 20× preview start/stop

Execute M01 and M06 in the same clean-install session. A failed start, a close
over 2000 ms, or any non-zero client count is a failure even when the 20th
iteration succeeds. Save the redacted log excerpt and numeric table in the
matrix; do not attach screenshots containing the environment or raw preview.

### 3.2 Background / foreground

Execute M09 after at least one successful M02 stream. The camera must stop in
background, and audio remains outside this spike's ownership. A background
image stream is not enabled: that would conflict with [ADR 0178](../adr/0178-vision-privacy-by-default.md).

### 3.3 Memory snapshot

Before M02 and immediately after M06, collect:

```bash
adb -s <serial> shell dumpsys meminfo com.wolfcasaba.strumsight
adb -s <serial> shell dumpsys media.camera
```

Record process RSS and active camera client count. PASS requires post-close
`open_clients=0` within 2000 ms (M06) and post-close RSS no more than **20 MiB**
above the pre-start snapshot after **30 seconds**. Otherwise record `FAIL` or
`PARTIAL` with both numeric snapshots.

## 4. Decision recording

`C1` remains selected only if M01, M02, M05, M06, M09, and M10 all pass on two
different Android devices. A failure of M05 latest-frame semantics or M10
monotonic timestamps is a **C1 disqualifier**: retain the evidence, mark the
matrix `FAIL`, and evaluate C2 rather than weakening the requirement. A C3
result is accepted only if it also proves one camera client and the same M05,
M06, M09, and M10 thresholds. These measurements are technology evidence, not
permission to persist or upload raw frames.
