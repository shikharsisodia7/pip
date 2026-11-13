# Playtime demo script

Use mock mode (`NEXT_PUBLIC_MOCK=1` or `?mock=1`). The default mock listening fixture is `fixtures/transcripts/page1-demo.json`. Its timestamps are synthetic rehearsal timings, not a recording or measured reading results. Live speech recognition still needs a microphone rehearsal.

## Page 1: read to Pip

Read this aloud exactly. Pause silently for **two seconds after “Chhotu.”**, then finish the last sentence. Keep the rest conversational, with ordinary short breaths. Do not say the stage directions or correct the two staged errors.

> The elephant's name was Golu. He was as round as a drum. The little rabbit was named Chhotu. He looked like a ball of cotton.

The two staged errors are deliberate, common-word changes that keep the spoken sentences natural:

- Skip the first **little**, page word index **1**. Keep the second “little”.
- Say **named** instead of **called**, page word index **17**. “Called” belongs to pattern `ed`. Both words are real words; the shared `fuzzyEqual` helper does not forgive this substitution.

The long pause is before **He**, page word index **19**. The sample transcript ends “Chhotu.” at 8.75 seconds and begins “He” at 10.75 seconds. It contains 25 spoken words against 26 printed words.

## Page 2: catch Pip

The first sentence is **“They played together.”** The intended planted mistake is **“They play together.”** It carries the same `ed` pattern as “called” on page 1. Page index is **1**, sentence index **0**, sentence word range **[0, 3)**, and “played” is page word index **1**.

Wait until Pip finishes speaking and asks for help. Say exactly:

> It's played, Pip. They played together.

In mock mode, queue that exact correction in the debug transcript input before starting the catch microphone. After the catch, let Pip read the whole sentence correctly: **“They played together.”**

## Expression moment

Golu's line, stored verbatim in page 2 with emotion `excited`, is:

> Let's play a new game today.

After Pip's flat reading ends, smile and deliver the line as an eager invitation to a friend. Lift your pitch on “play” and “new game”, then finish “today” with a happy bounce. Keep the words exactly as printed. Let Pip finish the expressive replay before moving on.

The expression line occupies page word indexes **7 through 12**, range **[7, 13)**. It has six words; “Let's” is one word.

## Book selection and credit

[Playtime](https://storyweaver.org.in/stories/375-playtime), text by Sanjiv Jaiswal 'Sanjay', English translation by Manisha Chaudhry, illustrations by Ajit Narayan. Pratham Books StoryWeaver. [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

The complete story is retained, with whitespace normalized. Original source pages 1, 2, 3, and 4 remain separate; pages 5-7 and 8-10 are combined. There are no sentence cuts or rewrites. The six displayed pages contain **26, 13, 22, 24, 27, and 26 words**, counted with `tokenizeDisplay`.

Page 1 covers six taxonomy patterns using `patternsForWord`: `th` (“The”), `silent-e` (“name”, “like”), `ou` (“round”), `ed` (“called”, “looked”), `ch` (“Chhotu”), and `oo` (“looked”). The catch uses the `ed` ending, which occurs on both opening pages.

Text source: [`en/0063_playtime.md`](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0063_playtime.md). Illustration credit and license: [`metadata/0063.md`](https://github.com/global-asp/pb-imagebank/blob/7f6a3b2d0213e05c25a088413a487178a4209234/metadata/0063.md). The six image URLs use that fixed image-bank revision. Images were visually checked; their filenames do not follow the scene order listed in the metadata. Emoji scenes and soft palette backgrounds are also provided.

## Candidate scores

All **395** English story files at source revision `9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed` were screened. **394** are marked CC BY; the one marked Public Domain was excluded. These are heuristic demo-fit scores out of 100, not learner assessments or measured speech-recognition results.

The conservative screening considers every way to join adjacent source pages into four to six pages of 12-30 words, without dropping or rewriting sentences. Forty-three stories have such a layout. Stories needing cuts or sentence-level repagination receive zero in this no-trim screening; zero does not mean an adaptation is impossible. Each story keeps its highest-scoring layout.

The rubric awards 30 points for a complete layout, three points per first-page taxonomy pattern up to 15, up to 20 for an emotional second-page line (20 for quoted speech with an emotion cue, 15 for unquoted speech with a cue and an exclamation), 10 for repeating the first page's hardest pattern on page 2, 20 when that pattern occurs in a first catch sentence of eight words or fewer, and five for opening pages without joined sentence punctuation, spelled-out words, ellipses, or em dashes. Emotion cues include invitations to play, fear, crying, happiness, requests, and exclamations. A missing emotion cue or fewer than three opening patterns caps the score at 69. Ties are ordered by title. The shortlist was then read for narrative fit.

| Rank | Story | Score | Demo fit |
| --- | --- | ---: | --- |
| 1 | [Playtime](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0063_playtime.md) | 100 | Selected: complete six-page story, short `ed` catch, eager invitation. |
| 2 | [Our earth is precious](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0284_our-earth-is-precious.md) | 80 | Four pages; expressive concern, but fragment-heavy and a later catch. |
| 3 | [Rain, Rain](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0087_rain-rain.md) | 80 | Five pages; repeated requests, but a longer lead-in to the shared pattern. |
| 4 | [I Am Not Afraid!](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0114_i-am-not-afraid.md) | 75 | Six pages; clear fear and reassurance in unquoted speech. |
| 5 | [Spot and Spike](https://github.com/global-asp/pb-source/blob/9ea530dfb0011dd1cbaf42e6ffe74aa3ef5733ed/en/0137_spot-and-spike.md) | 75 | Five pages; strong emotion, but stutters and invented cries complicate rehearsal. |
