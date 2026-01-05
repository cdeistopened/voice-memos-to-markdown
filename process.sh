#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
DB_PATH="$SOURCE_DIR/CloudRecordings.db"
PROCESSED_DIR="$SCRIPT_DIR/processed"
LOG_FILE="$SCRIPT_DIR/.processed.log"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY not set. Create a .env file with your key."
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Voice Memos folder not found."
    echo "Make sure you've granted Full Disk Access to your terminal."
    exit 1
fi

OFFSET=${1:-0}
LIMIT=${2:-50}
MAX_FILE_SIZE=52428800  # 50MB

mkdir -p "$PROCESSED_DIR"
touch "$LOG_FILE"

echo "Voice Memos to Markdown"
echo "======================="
echo "Processing recordings $OFFSET to $((OFFSET + LIMIT))..."
echo ""

sqlite3 "$DB_PATH" "
SELECT ZPATH, ZDATE, ZDURATION
FROM ZCLOUDRECORDING 
ORDER BY ZDATE DESC 
LIMIT $LIMIT OFFSET $OFFSET;
" | while IFS='|' read -r filename coredata_ts duration; do
    
    if grep -q "^$filename$" "$LOG_FILE" 2>/dev/null; then
        continue
    fi
    
    SOURCE_FILE="$SOURCE_DIR/$filename"
    if [[ ! -f "$SOURCE_FILE" ]]; then
        echo "$filename" >> "$LOG_FILE"
        continue
    fi
    
    FILE_SIZE=$(stat -f%z "$SOURCE_FILE" 2>/dev/null || echo "0")
    if [[ "$FILE_SIZE" -gt "$MAX_FILE_SIZE" ]]; then
        echo "SKIP (too large): $filename"
        echo "$filename" >> "$LOG_FILE"
        continue
    fi
    
    if (( $(echo "$duration < 5" | bc -l) )); then
        echo "$filename" >> "$LOG_FILE"
        continue
    fi
    
    unix_ts=$(echo "$coredata_ts + 978307200" | bc)
    unix_ts_int=${unix_ts%.*}
    DATE_STAMP=$(date -r "$unix_ts_int" +"%Y%m%d%H%M")
    DATE_READABLE=$(date -r "$unix_ts_int" +"%Y-%m-%d_%H-%M")
    
    RAW_TRANSCRIPT=""
    
    if [[ "$filename" == *.qta ]]; then
        RAW_TRANSCRIPT=$(strings "$SOURCE_FILE" | grep -o '{"attributedString".*' | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    runs = data['attributedString']['runs']
    print(' '.join(runs[::2]).replace('  ', ' '))
except:
    pass
" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$RAW_TRANSCRIPT" ]]; then
        echo "Transcribing: $filename ($DATE_READABLE)"
        
        TEMP_FILE=$(mktemp).m4a
        if [[ "$filename" == *.qta ]]; then
            afconvert -f m4af -d aac "$SOURCE_FILE" "$TEMP_FILE" 2>/dev/null
        else
            cp "$SOURCE_FILE" "$TEMP_FILE"
        fi
        
        AUDIO_BASE64=$(base64 -i "$TEMP_FILE")
        rm "$TEMP_FILE"
        
        RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
            -H 'Content-Type: application/json' \
            -d @- << EOF
{
  "contents": [{
    "parts": [
      {
        "inline_data": {
          "mime_type": "audio/mp4",
          "data": "$AUDIO_BASE64"
        }
      },
      {
        "text": "Transcribe this audio. Return ONLY the transcription, no labels or commentary."
      }
    ]
  }],
  "generationConfig": { "temperature": 0.1 }
}
EOF
)
        
        RAW_TRANSCRIPT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty')
        
        if [[ -z "$RAW_TRANSCRIPT" || "$RAW_TRANSCRIPT" == "[no speech]" ]]; then
            echo "  (no speech detected)"
            echo "$filename" >> "$LOG_FILE"
            continue
        fi
    else
        echo "Processing: $filename ($DATE_READABLE)"
    fi
    
    ESCAPED_TRANSCRIPT=$(echo "$RAW_TRANSCRIPT" | jq -Rs .)
    
    RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d @- << EOF
{
  "contents": [{
    "parts": [
      {
        "text": "Process this voice memo transcript.\n\n1. PRESERVE all substantive ideas and details\n2. REMOVE filler words, false starts, background conversations\n3. POLISH for clarity while keeping the speaker's voice\n4. STRUCTURE with markdown headers/bullets where helpful\n5. Generate a SHORT TITLE (3-6 words)\n6. Identify TAGS (lowercase, comma-separated)\n7. Suggest PROJECT from: work, personal, health, creative, or 'general'\n8. Identify ACTION: task, idea, reflection, or archive\n\nIf content is just noise/chatter, respond: SKIP\n\nFormat:\nTITLE: <title>\nTAGS: <tags>\nPROJECT: <project>\nACTION: <action>\n\n---\n\n<polished content>\n\nRAW:"
      },
      {
        "text": $ESCAPED_TRANSCRIPT
      }
    ]
  }],
  "generationConfig": { "temperature": 0.3 }
}
EOF
)
    
    RESULT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty')
    
    if [[ -z "$RESULT" || "$RESULT" == "SKIP" ]]; then
        echo "  (no substantive content)"
        echo "$filename" >> "$LOG_FILE"
        continue
    fi
    
    TITLE=$(echo "$RESULT" | grep -E "^TITLE:" | sed 's/^TITLE: *//' | head -1)
    TAGS=$(echo "$RESULT" | grep -E "^TAGS:" | sed 's/^TAGS: *//' | head -1)
    PROJECT=$(echo "$RESULT" | grep -E "^PROJECT:" | sed 's/^PROJECT: *//' | head -1)
    ACTION=$(echo "$RESULT" | grep -E "^ACTION:" | sed 's/^ACTION: *//' | head -1)
    CONTENT=$(echo "$RESULT" | sed -n '/^---$/,$ p' | tail -n +2)
    
    [[ -z "$TITLE" ]] && TITLE="untitled"
    
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | head -c 40)
    OUTPUT_FILE="$PROCESSED_DIR/${DATE_STAMP}_${SLUG}.md"
    
    cat > "$OUTPUT_FILE" << EOF
---
source: voice-memo
date: $DATE_READABLE
title: $TITLE
tags: [$TAGS]
project: $PROJECT
action: $ACTION
status: unprocessed
---

$CONTENT
EOF
    
    echo "  → $(basename "$OUTPUT_FILE")"
    echo "$filename" >> "$LOG_FILE"
    
done

echo ""
echo "Done! Transcripts in: $PROCESSED_DIR"
ls "$PROCESSED_DIR"/*.md 2>/dev/null | wc -l | xargs echo "Total files:"
