#!/usr/bin/env bash
# SoundCloud real-audio corpus for autonomous StrumSight DSP tuning (DEV-only).
# UNLIKE YouTube, SoundCloud is NOT bot-walled from the datacenter box, so this
# runs HERE and gives me real guitar + speech to test/tune on without a device.
#
# Naming convention the probe harness reads:
#   guitar_<CHORDS>_<slug>.wav   -> 'guitar'; <CHORDS> (dash-separated, e.g.
#                                   C-G-Am-F) is the approx ground-truth set.
#   speech_<slug>.wav            -> 'voice' negative (real talking).
#   lesson_<slug>.wav            -> guitar lesson (talk + play).
set -u
export PATH="$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"; RAW="$HERE/raw"; WAV="$HERE/wav"
mkdir -p "$RAW" "$WAV"
SECS="${SECS:-60}"   # seconds to keep per clip

grab () {  # label  scsearch-query  [count]
  local label="$1" query="$2" count="${3:-1}"
  echo ">>> $label  <=  scsearch$count:$query"
  local ids; ids=$(yt-dlp --no-warnings --flat-playlist --print "%(id)s" \
      "scsearch$count:$query" 2>/dev/null)
  local i=0
  while read -r id; do
    [ -z "$id" ] && continue
    i=$((i+1))
    local name="${label}_${i}"
    yt-dlp --no-warnings -f bestaudio -o "$RAW/${name}.%(ext)s" \
      "https://api.soundcloud.com/tracks/$id" >/dev/null 2>&1
    local f; f=$(ls "$RAW/${name}."* 2>/dev/null | head -1)
    [ -z "$f" ] && { echo "  fail $name"; continue; }
    ffmpeg -y -loglevel error -i "$f" -ac 1 -ar 16000 -t "$SECS" "$WAV/${name}.wav" \
      && echo "  ok $name.wav"
  done <<< "$ids"
}

# --- Guitar with NAMED chords (approx ground truth in the label) ---
grab "guitar_C-G-Am-F_backing"  "C G Am F acoustic guitar backing track" 2
grab "guitar_G-D-Em-C_backing"  "G D Em C guitar backing track" 2
grab "guitar_Em-C-G-D_progression" "Em C G D acoustic guitar progression" 1
# --- Guitar lessons (talk + play) — the real strum-on-speech negatives ---
grab "lesson_beginner"          "beginner guitar lesson open chords" 2
# --- Pure speech (real voice negatives) ---
grab "speech_podcast"           "podcast interview conversation" 2
grab "speech_story"             "spoken word storytelling voice" 1

echo; echo "WAVs:"; ls -1 "$WAV"/*.wav 2>/dev/null | wc -l
