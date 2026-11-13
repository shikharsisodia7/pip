import { highlightPattern } from './highlight-pattern';

export function PatternText({ text, patternId }: { text: string; patternId: string }) {
  return text.split(/(\s+)/).map((word, index) => /^\s+$/.test(word) ? word : (
    <span key={index} className="whitespace-nowrap">
      {highlightPattern(word, patternId).map((part, partIndex) => part.bold
        ? <strong key={partIndex}>{part.text}</strong>
        : part.text)}
    </span>
  ));
}
