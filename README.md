# Pip Reads It Wrong

Pip is a cartoon owl who is learning to read, and the child is his teacher.

1. The child reads a picture-book page aloud. Pip listens and notices which phonics patterns were tricky.
2. Pip reads the next page back, flat and a little robotic, with a deliberate mistake on one of those same patterns. The child catches it by voice, and Pip re-reads the sentence correctly.
3. Pip reads an emotional line flat and asks how it should sound. The child performs it, and Pip learns to read it with feeling.
4. Parents and teachers get a short report of what happened in the session.

Built for a one-day hackathon on multimodal AI for education (voice and audio tutors).

## How it works

- **Listening:** ElevenLabs Scribe realtime speech-to-text, with word timestamps, drives karaoke highlighting and reading metrics.
- **Reading analysis:** plain TypeScript alignment between the page text and the transcript (no LLM in scoring), mapped onto a small phonics taxonomy.
- **Pip's voice:** ElevenLabs text-to-speech. A flat voice with word timings for Pip's practice reads, and an expressive model for the line Pip learns to perform.
- **Judgment calls:** Claude ranks which patterns to highlight and writes Pip's short in-character lines. Every Claude and TTS response is cached on disk so a session replays reliably.
- **Expression:** pitch and loudness variation measured in the browser, compared with the child's own reading baseline.

## Run it

Requires Node 22 or newer.

```bash
npm ci
cp .env.example .env.local   # add your own keys
npm run dev
```

Set `NEXT_PUBLIC_MOCK=1` in `.env.local`, or open `http://localhost:3000/?mock=1`, to run with sample fixtures and no network calls.

Other scripts:

- `npm run check`: type check, unit tests, and a scan that keeps secrets and audio out of the repository.
- `npm run warm`: pre-generates the cached Claude and speech responses for the demo path (needs real keys).

### iPhone app

The native app in `ios/` is a SwiftUI client for the same server. It needs Xcode 26 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios && xcodegen          # generates Pip.xcodeproj (not committed)
open Pip.xcodeproj          # run the Pip scheme on an iPhone simulator
cd PipKit && swift test     # shared logic tests, no simulator needed
```

The app starts in mock mode with bundled fixtures, so it runs with no server. To use the live server, start `npm run dev`, then turn mock off and set the server address in the hidden debug panel (long press the top left corner). To run on a physical iPhone, put `DEVELOPMENT_TEAM = <your team id>` in `ios/Local.xcconfig`, which is never committed.

## Credits and licenses

- Story text and illustrations: an openly licensed picture book from [Pratham Books StoryWeaver](https://storyweaver.org.in), used under CC BY 4.0. Full attribution is shown on every reading screen.
- Fonts: Fredoka, Nunito and Andika, via Google Fonts under the SIL Open Font License.
- Pip the owl is an original character made for this project.
- Speech recognition and synthesis by ElevenLabs. Language model calls by Anthropic Claude.
