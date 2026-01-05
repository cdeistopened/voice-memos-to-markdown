# Voice Memos to Markdown

Extract and transcribe Apple Voice Memos into clean, organized markdown files with AI-powered polish.

## What This Does

1. **Extracts** voice memos directly from Apple's hidden storage location
2. **Transcribes** using Apple's embedded transcripts (free, instant) or Gemini API (for older recordings)
3. **Polishes** transcripts with AI to remove filler words, background chatter, and add structure
4. **Organizes** with frontmatter metadata (tags, project, action type) ready for Obsidian/PKM

## Requirements

- macOS Sonoma (14.0) or later
- [Gemini API key](https://aistudio.google.com/app/apikey) (free tier works)
- Terminal with Full Disk Access (see Setup)

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/cdeistopened/voice-memos-to-markdown.git
cd voice-memos-to-markdown
cp .env.example .env
```

Edit `.env` and add your Gemini API key:
```
GEMINI_API_KEY=your_key_here
```

### 2. Grant Full Disk Access

Voice Memos are stored in a protected location. Your terminal needs permission to read them.

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click **+** and add your terminal app (Terminal.app, iTerm, Warp, etc.)
3. **Restart your terminal completely**

### 3. Run it

Process your 50 most recent voice memos:
```bash
./process.sh
```

Process a specific range (e.g., recordings 50-100):
```bash
./process.sh 50 50
```

Your transcripts will appear in `./processed/` as markdown files like:
```
202501151030_meeting-notes-product-roadmap.md
```

## Output Format

Each transcript includes frontmatter for easy querying in Obsidian:

```yaml
---
source: voice-memo
date: 2025-01-15_10-30
title: Meeting Notes Product Roadmap
tags: [product, roadmap, q1-planning]
project: work
action: task
status: unprocessed
---
```

## How It Works

### Apple's Hidden Transcripts

Since late 2024, Apple embeds transcripts directly in `.qta` voice memo files. This script extracts them for free—no API calls needed for recent recordings.

Location: `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/`

### Gemini Fallback

Older `.m4a` files don't have embedded transcripts. The script automatically sends these to Gemini's audio API for transcription.

### AI Polish

Raw transcripts are messy. The script uses Gemini to:
- Remove filler words and false starts
- Filter out background conversations (family, kids, interruptions)
- Add markdown structure (headers, bullets)
- Generate title, tags, and suggested project

## Customization

### Change the project list

Edit the prompt in `process.sh` to match your projects:

```
7. Suggest PRIMARY PROJECT from: work, personal, side-project, health, or 'general'
```

### Skip the polish step

If you just want raw transcripts, set `POLISH=false` in the script.

### Adjust file size limits

Very long recordings (1hr+) may timeout. The script skips files over 50MB by default.

## Troubleshooting

### "Operation not permitted"
Your terminal doesn't have Full Disk Access. See step 2 above, and make sure to **restart the terminal** after granting access.

### "No Apple transcript found"
Older recordings (pre-late 2024) don't have embedded transcripts. The script will automatically use Gemini to transcribe the audio.

### "API key not found"
Make sure your `.env` file exists and contains a valid Gemini API key.

### Empty or garbage transcripts
Some very short recordings (<5 seconds) or background noise will be skipped automatically.

## Credits

This project was inspired by Drew Bredvick's excellent [deep-dive into Apple Voice Memos storage](https://drew.tech/posts/ios-memos-obsidian-claude) that documented the `.qta` format and embedded transcript structure.

## License

MIT
