#!/bin/bash
# generate_test_cases.sh
# This script uses FFmpeg to synthesize local audio files for testing MusicVideoMacApp.

set -e

# Use /opt/homebrew/bin/ffmpeg if it exists, otherwise assume ffmpeg is in PATH
FFMPEG_CMD="ffmpeg"
if [ -x "/opt/homebrew/bin/ffmpeg" ]; then
    FFMPEG_CMD="/opt/homebrew/bin/ffmpeg"
fi

echo "🎵 Starting Test Media Synthesis..."

BASE_DIR="./TestMedia"
mkdir -p "$BASE_DIR"

# ---------------------------------------------------------
# 1. Standard MP3 Album (ID3 Tags)
# ---------------------------------------------------------
echo "💿 Generating Standard MP3 Album..."
MP3_DIR="$BASE_DIR/Standard_MP3_Album"
mkdir -p "$MP3_DIR"

$FFMPEG_CMD -y -f lavfi -i "sine=frequency=440:duration=10" -metadata title="Neon Pulse" -metadata artist="Synthesizer" -metadata album="Retro Days" -c:a libmp3lame -q:a 2 "$MP3_DIR/01_Neon_Pulse.mp3" -loglevel error
$FFMPEG_CMD -y -f lavfi -i "sine=frequency=660:duration=10" -metadata title="Cyber City" -metadata artist="Synthesizer" -metadata album="Retro Days" -c:a libmp3lame -q:a 2 "$MP3_DIR/02_Cyber_City.mp3" -loglevel error
$FFMPEG_CMD -y -f lavfi -i "sine=frequency=880:duration=10" -metadata title="Sunset Drive" -metadata artist="Synthesizer" -metadata album="Retro Days" -c:a libmp3lame -q:a 2 "$MP3_DIR/03_Sunset_Drive.mp3" -loglevel error
echo "✅ MP3 Album Created."

# ---------------------------------------------------------
# 2. Cue Sheet Edition (Single WAV + .cue)
# ---------------------------------------------------------
echo "📄 Generating Cue Sheet Album..."
CUE_DIR="$BASE_DIR/Cue_Sheet_Album"
mkdir -p "$CUE_DIR"

# Generate a 30-second continuous WAV file
$FFMPEG_CMD -y -f lavfi -i "sine=frequency=550:duration=30" -c:a pcm_s16le "$CUE_DIR/Master_Audio.wav" -loglevel error

# Write the .cue file
cat << 'EOF' > "$CUE_DIR/Master_Audio.cue"
PERFORMER "The Maestro"
TITLE "Symphony of Sine Waves"
FILE "Master_Audio.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Movement I: Allegro"
    PERFORMER "The Maestro"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Movement II: Adagio"
    PERFORMER "The Maestro"
    INDEX 01 00:10:00
  TRACK 03 AUDIO
    TITLE "Movement III: Presto"
    PERFORMER "The Maestro"
    INDEX 01 00:20:00
EOF
echo "✅ Cue Sheet Album Created."

# ---------------------------------------------------------
# 3. Virtual CD (.dmg format simulating an Audio/Data CD)
# ---------------------------------------------------------
echo "💽 Generating Virtual CD Image (DMG)..."
VCD_DIR="$BASE_DIR/Virtual_CD_Source"
mkdir -p "$VCD_DIR"

$FFMPEG_CMD -y -f lavfi -i "sine=frequency=440:duration=10" -c:a pcm_s16be "$VCD_DIR/01_Track_1.aiff" -loglevel error
$FFMPEG_CMD -y -f lavfi -i "sine=frequency=660:duration=10" -c:a pcm_s16be "$VCD_DIR/02_Track_2.aiff" -loglevel error
$FFMPEG_CMD -y -f lavfi -i "sine=frequency=880:duration=10" -c:a pcm_s16be "$VCD_DIR/03_Track_3.aiff" -loglevel error

# Create a read-only DMG to simulate a CD
hdiutil create -volname "Audio CD Test" -srcfolder "$VCD_DIR" -ov -format UDRO "$BASE_DIR/Virtual_CD.dmg" > /dev/null

# Clean up the source folder as it's packaged in the dmg now
rm -rf "$VCD_DIR"

echo "✅ Virtual CD (.dmg) Created."
echo "🎉 All Test Cases Synthesized Successfully in '$BASE_DIR/'"
