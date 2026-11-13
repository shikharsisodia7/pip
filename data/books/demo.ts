import type { Book } from '@/lib/types';

// Placeholder story written for the app skeleton. It is replaced by an openly
// licensed StoryWeaver picture book with full attribution.
export const demoBook: Book = {
  id: 'placeholder',
  title: 'The Night Noise',
  author: 'Placeholder text',
  illustrator: 'none',
  publisher: 'Sample story for development',
  license: 'Placeholder',
  sourceUrl: '',
  pages: [
    {
      index: 0,
      text: 'Tara thought the night was too quiet. She looked out at the bright moon and smiled.',
      scene: { emoji: '🌙', bg: '#e6ebff' },
    },
    {
      index: 1,
      text: 'Then a loud boom shook the trees. Tara jumped up. "Oh no! What was that?" she cried.',
      scene: { emoji: '🌳', bg: '#fff2c9' },
      emotionLine: { text: 'Oh no! What was that?', speaker: 'Tara', emotion: 'scared' },
    },
    {
      index: 2,
      text: 'It was only her brother with a drum. They both laughed until the sun came up.',
      scene: { emoji: '🥁', bg: '#ffd9cc' },
    },
  ],
};
