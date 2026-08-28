# AI Subtitle Quality Report: Group A

## Scope

The first tuning group covers English, Japanese, and Korean speech translated to
Simplified Chinese. Results below use the first 600 seconds of each test video.
The generated evaluation artifacts remain in
`../materials/subtitle-evaluation/runs` and are not included in Rawya builds.

## Accepted Changes

1. Preserve Korean spaces while joining recognition fragments and translation
   context. Korean is compact for reading-speed limits, but it is not a
   space-less writing system.
2. Recover English phrases split at incomplete grammatical boundaries such as
   prepositions, determiners, conjunctions, and adjectives.
3. Limit translation blocks to the number that can receive at least one second
   of display time.
4. Keep both tracks inside shared semantic speech ranges, then allocate cue count
   and display time independently for each language's reading needs.
5. Remove sentence punctuation from both edges of every rendered line.
6. Use Apple's word-level audio ranges to split recognition results at meaningful
   pauses: 0.3 seconds for Chinese/Japanese and 0.45 seconds for English/Korean.
7. Translate up to three adjacent semantic segments with stable numeric markers,
   while falling back to isolated translation whenever a marker boundary moves a
   grammatical continuation.
8. Suppress sustained Latin-only noise produced by a mismatched East Asian speech
   model while retaining isolated foreign names and terms.

## Results

| Sample | Before | Current | Accuracy / timing |
| --- | --- | --- | --- |
| Friends EN -> ZH | 252 cues; 14 source speed violations; 10 short cues | 229 source / 221 target cues; 2 source and 0 target speed violations; 5 short replies | WER unchanged at 18.55%; both tracks remain in ordered semantic ranges |
| Rebooting JA -> ZH | 195 cues; no structural violations | 179 source / 159 target cues; no structural violations | Chinese changes at its own reading boundaries inside each Japanese semantic range |
| Lovestruck KO -> ZH | Korean words were joined incorrectly; 122 cues after spacing fix | 105 source / 98 target cues; sustained song noise removed; 0 overlaps, speed violations, short cues, long cues, or line-edge punctuation | Both tracks remain in ordered semantic ranges |

All current outputs use no more than two lines and have no cue overlap, semantic
range crossing, overlong cue, line-width violation, or line-edge punctuation.

## Findings

### English

The main controllable defect was recognition-result boundaries splitting an
unfinished phrase. Grammar-aware recovery reduces fragments without changing the
recognized word stream, as confirmed by the unchanged reference WER.

### Japanese

Apple Speech provides broad dialogue coverage but often returns long runs without
sentence punctuation. Translating a wider unpunctuated block did not improve the
tested examples. Manually restored Japanese sentence boundaries produced visibly
better Chinese, showing that punctuation restoration is more valuable than simply
adding context.

Apple Dictation was evaluated because its preset provides punctuation and timing.
Its punctuation and narration quality were better, but it returned only 99 display
cues where Speech returned 191 and omitted substantial quick dialogue. It therefore
must not replace Speech. A future hybrid may use Speech for coverage and transfer
only trustworthy Dictation boundaries.

### Korean

Treating Korean as space-less caused avoidable word joins. Keeping its spaces
improves both the source subtitle and the context sent to Apple Translation. Some
repeated syllables and false English fragments originate in Apple's recognition
result and need confidence/language-mismatch handling rather than text deletion.

## Remaining Limits

- Apple model recognition errors, names, and literal translations cannot be fixed
  reliably by display rules alone.
- Speaker changes are not exposed as speaker identities by the current Apple
  Speech result. Meaningful acoustic pauses can split turns, but speaker
  diarization requires a separate model or service.
- Punctuation restoration must be conservative. Inventing punctuation before
  translation can improve fluency while also changing meaning.

## Decision

The accepted changes improve readability without changing English recognition
accuracy. Bilingual synchronization is intentionally soft: semantic ranges stay
ordered, but source and target cue transitions may differ. All 12 directed language
pairs now pass the final structural matrix. Further gains require better recognition
or translation models rather than broader text-deletion rules.
