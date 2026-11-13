# Pip Reads It Wrong

Pip is a fuzzy little monster who is learning to read, and the child is his teacher. The more the child teaches him, the more Pip grows: Sprout, Glow, Star, then Crown.

Every page of a picture book goes like this:

1. Pip reads the page aloud first, so the child hears it read well. On some pages he slips on purpose, on a phonics pattern this child is practicing. The child catches the mistake by voice or by tapping the word, and Pip reads the sentence again correctly.
2. Then the child reads the page to Pip. Words light up as Pip hears them: green when read right, yellow when they took a moment, red when they were tricky. If the child stops for a few seconds, Pip shows the next word in parts.
3. After the page, Pip says what he noticed and offers a sound to practice together.

When the child is done for the day, grown-ups get a report of what was measured: words read right, accuracy, words per minute, how many of Pip's mistakes the child caught, and the sound to practice next. Pip also writes a short practice story packed with that sound.

Any book works: take a photo of a page and it becomes a new book.

Built for a one-day hackathon on multimodal AI for education (voice and audio tutors).

## How it works

- **The app:** a native SwiftUI iPhone app in `ios/`. Its pure logic (alignment, reading metrics, catch matching, stuck hints) lives in the `PipKit` Swift package, with its own tests.
- **Listening:** ElevenLabs Scribe realtime speech-to-text with word timestamps, opened with a single-use token from the server. If the server or network is unavailable, the app falls back to Apple's speech recognizer.
- **Reading analysis:** plain alignment between the page text and the transcript (no LLM in scoring), mapped onto a small phonics taxonomy.
- **Pip's voice:** ElevenLabs text-to-speech, with word timings so each word lights up as Pip reads it.
- **Judgment calls:** Claude ranks which patterns to highlight, writes how Pip misreads a word and his short in-character lines, and writes the practice stories. Code decides which words Pip misreads; Claude only words the slip. Every Claude and speech response is cached on disk so a session replays reliably.
- **Photos:** Apple's on-device text recognition turns a photo of a page into the words of a new book.
- **Server:** a small Next.js app whose only job is the API the iPhone app calls (`app/api`).

## Run it

### Server

Requires Node 22 or newer.

```bash
npm ci
cp .env.example .env.local   # add your own keys
npm run dev
```

Set `NEXT_PUBLIC_MOCK=1` in `.env.local` to answer requests from bundled fixtures with no network calls.

`npm run check` runs the type check, unit tests, and a scan that keeps secrets and audio out of the repository.

### iPhone app

It needs Xcode 26 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios && xcodegen          # generates Pip.xcodeproj (not committed)
open Pip.xcodeproj          # run the Pip scheme on an iPhone or simulator
cd PipKit && swift test     # shared logic tests, no simulator needed
```

The app talks to the server at `http://localhost:3000` by default. To point it somewhere else, or to run on a physical iPhone, create `ios/Local.xcconfig` (never committed) with:

```
DEVELOPMENT_TEAM = <your team id>
PIP_SERVER_URL = https:/$()/your-server.example.com
```

A hidden debug panel (long press the top left corner) can switch the app to mock mode, which uses bundled fixtures and needs no server.

## Credits and licenses

- "Playtime": an openly licensed picture book from [Pratham Books StoryWeaver](https://storyweaver.org.in), used under CC BY 4.0. Full attribution is shown on every reading screen.
- "The Lion and the Mouse" and "The Tortoise and the Hare": Aesop's fables, retold for Pip. Public domain.
- Pip is an original character made for this project.
- Speech recognition and synthesis by ElevenLabs. Language model calls by Anthropic Claude.
