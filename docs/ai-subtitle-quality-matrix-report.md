# AI Subtitle Quality Matrix Report

## Method

Each source language is transcribed once per algorithm version. The resulting
semantic `transcript.json` is then reused for every target language. This keeps
speech-recognition variation out of translation comparisons. Source and target
share ordered semantic speech ranges, but each language chooses its own display cue
count and internal switch times. Exact cue-for-cue timing is an informational metric,
not a quality gate.

All measurements below use the first 600 seconds of the matching test video.
Reading-speed violations use 15 characters/second for Chinese, Japanese, and
Korean, and 20 characters/second for English.

## Group B: Chinese Source

| Direction | Target cues | Target P95 chars/s | Speed violations | Structural result |
| --- | ---: | ---: | ---: | --- |
| ZH -> EN | 179 | 21.49 | 22 | semantic anchors; 2 forced short cues; no overlap, overlong cue, line overflow, or edge punctuation |
| ZH -> JA | 179 | 11.52 | 5 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |
| ZH -> KO | 183 | 11.33 | 0 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |

Chinese recognition occasionally ends a long result with a separate one-character
tail. Rejoining that tail before translation removes incorrect isolated words.
Bounded context translation and a shared 0.35-second semantic-boundary adjustment
reduce English speed violations without changing the recognized source text. The
current independent display track has 22 violations; the strict v51 baseline had 21.
The one-cue difference is accepted because preserving two-line width and complete
content is preferable to deleting words or forcing rapid bilingual transitions.

Chinese-to-English remains the densest direction. The worst cases are not line
wrapping defects: unpunctuated multi-speaker Chinese is translated into verbose or
repetitive English whose total reading time exceeds the speech interval. Deleting
words or accelerating cue changes would hide the metric without improving meaning.
The next safe improvement is a coverage-preserving punctuation/speaker-turn hybrid.

## Group C: English, Japanese, and Korean

| Direction | Target cues | Target P95 chars/s | Speed violations | Structural result |
| --- | ---: | ---: | ---: | --- |
| EN -> JA | 239 | 12.25 | 3 | semantic anchors; 5 short replies; no other structural violation |
| EN -> KO | 240 | 11.74 | 0 | semantic anchors; 5 short replies; no other structural violation |
| JA -> EN | 185 | 17.56 | 0 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |
| JA -> KO | 181 | 7.41 | 0 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |
| KO -> EN | 127 | 14.29 | 0 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |
| KO -> JA | 122 | 8.33 | 0 | semantic anchors; no overlap, short cue, overlong cue, line overflow, or edge punctuation |

The Korean-source totals are lower than the earlier baseline because a sustained
Latin-only run recognized by the Korean speech model was an English song rendered
as gibberish. Two or more primarily Latin results spanning at least ten seconds are
now suppressed for Chinese, Japanese, and Korean source modes. Isolated Latin names
and terms remain.

## Final Matrix Gate

The `semantic-anchor-v52` run covers all 12 directed language pairs. Every pair has
zero overlaps, zero overlong cues, no more than two lines per cue, zero line-width
violations, zero edge punctuation, and no translation-context marker leakage.
Exact cue counts differ by design. Short cues remain in English-source material as
very short spoken replies, plus two forced Chinese-to-English cues where the speech
range cannot fit the complete English text at normal speed. Chinese-to-English
still exceeds the preferred English reading-speed target (P95 21.49 versus 20
characters/second, with 22 violating cues); this remains visible rather than being
hidden by deleting translated content.

## Pair Strategy

- **Target English:** allow the bilingual partitioner to use the full available
  silence and favor complete source sentences before translation. Do not use
  character deletion as a speed fix.
- **Target Japanese/Korean:** current compact-script line width and reading-speed
  allocation are effective. Preserve Korean spaces even though it shares compact
  display limits with Chinese and Japanese.
- **English source:** grammar-aware recovery is valuable because chunk boundaries
  often occur after a preposition, determiner, or adjective.
- **Japanese/Chinese source:** punctuation restoration has higher expected value
  than simply increasing the translation context window.
- **All pairs:** translate bounded semantic blocks, preserve shared outer semantic
  anchors, then segment each language's display track independently. Context markers
  are accepted only when every target boundary is safe; lowercase English
  continuations, leading Japanese/Korean particles, and
  leading punctuation trigger isolated-cue fallback. When display time cannot fit
  every translated sentence, adjacent complete sentences are merged instead of
  splitting a word or sentence. Whole-episode translation is not used because
  rewritten output cannot be mapped reliably back to speech timing or resumed
  safely.

## Next Quality Layer

The remaining high-impact work is not another line-splitting heuristic. It is a
hybrid boundary layer that retains Speech coverage while borrowing only trustworthy
punctuation or pauses from a second recognizer. It needs explicit alignment and
coverage tests before entering production, especially for rapid multi-speaker
dialogue.
