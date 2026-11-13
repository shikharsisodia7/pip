import type { Book } from '@/lib/types';

// Text: global-asp/pb-source at 9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed,
// en/0063_playtime.md. All sentences are retained verbatim, with whitespace
// normalized. Source pages 5-7 and 8-10 are combined; no text is trimmed.
// Illustrations: Ajit Narayan, CC BY 4.0. Credit and license for every image:
// https://github.com/global-asp/pb-imagebank/blob/7f6a3b2d0213e05c25a088413a487178a4209234/metadata/0063.md
// Images are matched visually because the metadata descriptions are out of order.
const imageBase = 'https://raw.githubusercontent.com/global-asp/pb-imagebank/7f6a3b2d0213e05c25a088413a487178a4209234/medium/0063';

export const demoBook: Book = {
  id: 'playtime',
  title: 'Playtime',
  author: "Sanjiv Jaiswal 'Sanjay'; translated by Manisha Chaudhry",
  illustrator: 'Ajit Narayan',
  publisher: 'Pratham Books StoryWeaver',
  license: 'CC BY 4.0',
  sourceUrl: 'https://storyweaver.org.in/stories/375-playtime',
  pages: [
    {
      index: 0,
      text: "The little elephant's name was Golu. He was as round as a drum. The little rabbit was called Chhotu. He looked like a ball of cotton.",
      scene: { emoji: '🐘 🐇', bg: '#e6ebff' },
      imageUrl: `${imageBase}/04.jpg`,
    },
    {
      index: 1,
      text: "They played together. One day, Golu said, “Let's play a new game today.”",
      scene: { emoji: '🐘 💬 🐇', bg: '#fff2c9' },
      imageUrl: `${imageBase}/05.jpg`,
      emotionLine: {
        text: "Let's play a new game today.",
        speaker: 'Golu',
        emotion: 'excited',
      },
    },
    {
      index: 2,
      text: "“You sit down. I'll land on your back in one flying leap,” said Chhotu. Golu sat down. Chhotu took a mighty leap.",
      scene: { emoji: '🐇 ☁️ 🐘', bg: '#ffd9cc' },
      imageUrl: `${imageBase}/06.jpg`,
    },
    {
      index: 3,
      text: 'Thump! He landed on Golu\'s back. “Wow!” laughed Golu and said, “My turn now. You sit down and I will leap on your back.”',
      scene: { emoji: '🐘 🐇 ✨', bg: '#e6ebff' },
      imageUrl: `${imageBase}/07.jpg`,
    },
    {
      index: 4,
      text: '“You!” “Yes, me.” “How can you do that?” asked Chhotu. "Like this!" Golu showed him. Thud... thud... thud... A shower of coconuts came down on Golu\'s head.',
      scene: { emoji: '🌴 🥥 🐘', bg: '#fff2c9' },
      imageUrl: `${imageBase}/10.jpg`,
    },
    {
      index: 5,
      text: "He ran away on fat legs, scared. One small coconut fell on Chhotu. ‘That's better,' thought Chhotu, ‘Better a coconut than an elephant on my head!'",
      scene: { emoji: '🐇 🥥 🌴', bg: '#ffd9cc' },
      imageUrl: `${imageBase}/03.jpg`,
    },
  ],
};
