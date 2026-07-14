#!/usr/bin/env bash
# Dev-only real-audio corpus builder for StrumSight DSP tuning.
# Downloads short clips, extracts 16kHz mono WAV. NOT shipped in the app.
set -u
export PATH="$HOME/.local/bin:$PATH"
OUT_RAW="$(dirname "$0")/raw"
OUT_WAV="$(dirname "$0")/wav"
mkdir -p "$OUT_RAW" "$OUT_WAV"
dl () {  # id  label
  local id="$1" label="$2"
  echo ">>> $label ($id)"
  yt-dlp --no-warnings -f "bestaudio" -o "$OUT_RAW/${label}.%(ext)s" \
    --download-sections "*0-120" "https://www.youtube.com/watch?v=$id" 2>&1 | tail -2
  local f=$(ls "$OUT_RAW/${label}."* 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "  FAIL $label"; return; }
  ffmpeg -y -loglevel error -i "$f" -ac 1 -ar 16000 -t 120 "$OUT_WAV/${label}.wav" && echo "  wav ok: ${label}.wav"
}
# guitar-lesson clips (speech + guitar interleaved, chords named)
dl 7WQEeGkQhx8 guitar_amfcg_combo
dl tZaeiHGvZi8 guitar_beginner_cgamf
dl LAmGfokvgzA speech_kevinhart
dl W6-Rit0xHBg guitar_solo_asmr
