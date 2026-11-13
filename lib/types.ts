// FROZEN shared contract types. Do not edit; ask the bootstrap owner for changes.

export type Phase =
  | 'intro' | 'probePre' | 'read' | 'pipReads' | 'expression' | 'probePost' | 'report';

export type Emotion = 'scared' | 'excited' | 'sad' | 'whispering' | 'shouting' | 'happy' | 'angry';

export interface EmotionLine { text: string; speaker?: string; emotion: Emotion }
export interface BookPage {
  index: number;
  text: string;
  scene: { emoji: string; bg: string };   // fallback art
  imageUrl?: string;
  emotionLine?: EmotionLine;
}
export interface Book {
  id: string; title: string; author: string; illustrator: string;
  publisher: string; license: string; sourceUrl: string; pages: BookPage[];
}

export interface TimedWord { text: string; start: number; end: number }   // seconds
export interface Transcript { text: string; words: TimedWord[] }

export type WordStatus = 'correct' | 'substitution' | 'omission' | 'selfCorrected';
export interface AlignedWord {
  index: number; expected: string; status: WordStatus;
  said?: string; start?: number; end?: number;
  hesitationBeforeSec?: number;          // set when gap > 0.8s
}
export interface Insertion { afterIndex: number; said: string }
export interface AlignmentResult { words: AlignedWord[]; insertions: Insertion[] }
export interface ReadingMetrics {
  wcpm: number; accuracyPct: number; wordsCorrect: number; wordsTotal: number;
  durationSec: number; hesitations: number; selfCorrections: number;
}

export interface PatternFinding {
  id: string;                // must be an id from lib/patterns.ts
  kidLabel: string;          // "the 'ough' sound"
  teacherLabel: string;      // "vowel team: ough"
  evidenceWords: string[];
  confidence: number;        // 0..1
}
export interface DiagnoseResponse { patterns: PatternFinding[]; kidMessage: string }

export interface PipSentence {
  index: number;
  text: string;              // correct text
  spokenText: string;        // what Pip actually says (with misreadings, phonetic if needed)
  wordStart: number; wordEnd: number;   // page word index range, end exclusive
}
export interface PlantedMistake {
  wordIndex: number; sentenceIndex: number;
  correct: string; misread: string; speakAs: string;
  patternId: string; reaction: string;  // Pip's in-character line when caught
}
export interface PipPlan { pageIndex: number; sentences: PipSentence[]; mistakes: PlantedMistake[] }
export interface CatchResult { wordIndex: number; caught: boolean; via: 'voice' | 'tap' | 'missed' }

export interface ProsodyStats {
  pitchRangeSemitones: number; pitchSdSemitones: number;
  loudnessSdDb: number; wordsPerSec: number; voicedFrames: number;
}
export interface ProsodyFrame { t: number; semitones: number | null; rms: number }
export interface ExpressionResult {
  baseline: ProsodyStats | null; attempt: ProsodyStats;
  score: number; passed: boolean; attempts: number; tags: string[];
}

export interface ProbeItem { word: string; patternId: string }
export interface ProbeResult {
  items: { word: string; patternId: string; correct: boolean; said?: string }[];
  correctCount: number;
}

export interface TtsRequest { text: string; mode: 'flat' | 'expressive'; withTimestamps?: boolean }
export interface TtsResponse { audioUrl: string; words?: TimedWord[] }

export interface PracticeBook { title: string; pattern: PatternFinding; sentences: string[] }
