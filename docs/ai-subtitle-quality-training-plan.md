# AI Subtitle Quality Tuning Plan

## Objective

Use the test media in `../materials/test-media` as a stable regression corpus for
Rawya's local Apple speech and translation pipeline. The goal is not to retrain
Apple's models, which are system-managed, but to improve every controllable stage:

1. audio extraction and speech recognition stability;
2. recovery of fragmented or revised recognition results;
3. translation context and language-pair-specific normalization;
4. readable cue segmentation and display duration;
5. semantic-range alignment with language-specific display timing.

## Corpus

| ID | Source language | Media | Reference |
| --- | --- | --- | --- |
| EN-1 | English | Modern Family S01E01 | visual/manual comparison |
| EN-2 | English | Friends S05E14 | embedded English SRT reference |
| JA-1 | Japanese | Rebooting S01E01 | visual/manual comparison |
| KO-1 | Korean | Lovestruck in the City S01E01 | visual/manual comparison |
| ZH-1 | Simplified Chinese | A Little Reunion S01E01 | visual/manual comparison |

The media is evaluation data, not code-test fixtures. Generated audio chunks and
subtitles stay under `materials/subtitle-evaluation` and are not shipped in Rawya.

## Tuning Matrix

### Group A: Chinese as target

- English -> Simplified Chinese (EN-1 and EN-2)
- Japanese -> Simplified Chinese
- Korean -> Simplified Chinese

### Group B: Chinese as source

- Simplified Chinese -> English
- Simplified Chinese -> Japanese
- Simplified Chinese -> Korean

### Group C: English, Japanese, and Korean cross-translation

- English <-> Japanese
- English <-> Korean
- Japanese <-> Korean

Each source transcript is generated once per algorithm version and reused for
target-language experiments. This prevents translation tuning from being polluted
by a different recognition run.

## Iteration Loop

1. Generate an untranslated source transcript.
2. Compare against an embedded reference where available and inspect representative
   opening, dialogue-heavy, multi-speaker, quiet, and music-heavy intervals.
3. Translate the same semantic transcript to every target language in the group.
4. Run structural metrics and inspect the worst-scoring cues in context.
5. Change one class of rules at a time, add a focused self-test, and regenerate.
6. Accept the change only when it improves the target pair without regressing the
   rest of the completed matrix.
7. Run full-episode generation after sample metrics and manual review stabilize.

## Quality Gates

All generated subtitle pairs must satisfy these structural gates:

- original and translated files stay inside the same ordered semantic speech
  ranges, while each language may use a different cue count and switch time;
- no overlapping cues or pipeline-created duplicate cues; repeated spoken lines
  are retained and reviewed rather than deleted automatically;
- at most two display lines per cue;
- no leading or trailing sentence punctuation;
- no cue shorter than 0.8 seconds unless it is a standalone response or the
  complete text cannot otherwise fit the two-line limit inside its speech range;
- no cue longer than 6 seconds;
- compact scripts normally stay at or below 22 characters per line;
- Latin scripts normally stay at or below 42 characters per line;
- reading-speed P95 targets 15 chars/s for compact scripts and 20 chars/s for Latin
  scripts; unavoidable overflow is recorded instead of hiding it by deleting text;
- one cue contains one readable thought, not a paragraph of unrelated dialogue.

Recognition and translation accuracy are evaluated separately. For EN-2, normalized
word error rate against the embedded English subtitle is tracked. For other sources,
manual review records missing dialogue, false speech, names, numbers, repeated text,
and language mismatch.

## Translation Strategy Experiments

The default experiment uses semantic blocks of one to three sentences and preserves
stable cue identifiers. It will be compared with:

- isolated cue translation;
- bounded context windows containing adjacent dialogue;
- language-pair-specific context sizes;
- post-translation resegmentation with shared semantic anchors and independent
  language-specific display timing.

Whole-episode translation is not the default: it has useful context but weak timing
alignment, high failure blast radius, and no reliable way to map a rewritten result
back to individual cues. Bounded context plus bilingual resegmentation provides the
better balance and remains resumable.

## Acceptance Record

Every completed direction records the algorithm version, source/target language,
media interval, metrics, representative defects, implemented change, and before/after
result under `materials/subtitle-evaluation/reports`.

The first accepted result and its remaining model limitations are recorded in
`docs/ai-subtitle-quality-group-a-report.md`.
The fixed-transcript Group B and Group C comparison is recorded in
`docs/ai-subtitle-quality-matrix-report.md`.

## Final Coverage

The `final-matrix-v51` regression completed all directed pairs among English,
Simplified Chinese, Japanese, and Korean:

| Source | Targets | Status |
| --- | --- | --- |
| English | Simplified Chinese, Japanese, Korean | complete |
| Simplified Chinese | English, Japanese, Korean | complete |
| Japanese | Simplified Chinese, English, Korean | complete |
| Korean | Simplified Chinese, English, Japanese | complete |

The strict-timeline `final-matrix-v51` run is retained as a historical baseline.
All 12 pairs passed its timing, overlap, duration, line-count, line-width, and
edge-punctuation gates. Later runs use semantic-anchor alignment instead of exact
cue-for-cue timing. Chinese-to-English remains above the preferred English
reading-speed target, while remaining accuracy defects are tracked as source
recognition or Apple Translation model limits and are not hidden with
sample-specific substitutions.
