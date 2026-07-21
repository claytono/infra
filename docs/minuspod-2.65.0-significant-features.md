# MinusPod 2.40.0–2.65.0: Significant New Features

## Executive summary

The upgrade from MinusPod `2.39.0` to `2.65.0` is much larger than the version numbers suggest. It adds new audio evidence for dynamic-ad detection, centralized review tools, several per-feed processing modes, deferred processing during provider outages, richer notifications and diagnostics, runtime-adjustable settings, embedded chapters, faster media processing, endpoint connection tests, and an iTunes-backed podcast search that works without credentials.

The most consequential changes for this deployment are:

- DAI detection now combines cross-fetch comparison, splice evidence, transcript coverage, and second-pass corroboration instead of trusting one signal.
- Uncertain detections increasingly go to review rather than being cut automatically, while strongly corroborated holds can be approved and recut automatically.
- The local-CUDA media stack moves to Ubuntu 26.04, Python 3.12, ffmpeg 8, and PyTorch `2.13.0` with CUDA 12.6 wheels.
- Long-episode processing is substantially faster because ffmpeg work, audio analysis, differential fetching, fingerprint matching, and LLM windows run with less serialization.
- Operators can diagnose provider, transcriber, feed, quota, and processing failures from the UI instead of inferring them from generic errors.

This document groups releases by user-visible capability rather than repeating the changelog chronologically. Small styling fixes and dependency-only bumps are omitted unless they change operational behavior.

## Deployment context

The reviewed deployment runs one GPU-backed MinusPod replica with persistent `/app/data`, OpenRouter as its LLM provider, local Whisper on CUDA, and Authentik in front of the web UI. Version `2.65.0` was deployed successfully with the pinned image digest `sha256:da001eeeead9aa843e13429ebbc92d51fca7237026ef4dd5087d7086ef9ccd58`. The application reported a healthy database and storage, verified the OpenRouter endpoint, detected the NVIDIA RTX 2060 SUPER, refreshed both configured feeds, and remained at zero restarts during the observation window.

That live result proves basic compatibility and startup health. It does not by itself exercise every feature below, particularly DAI decisions, transcription of malformed artwork, offline deferral, SMTP delivery, or every review/recut path.

## 1. Audio evidence and cross-fetch DAI detection

**Introduced in:** `2.40.0`; expanded in `2.53.0`; safety hardened in `2.63.0`–`2.64.1`.

MinusPod can now use the audio itself as evidence rather than relying only on transcript text and learned patterns. The new splice-evidence scan looks for encoded silence, loudness transitions, and spectral transitions near likely ad boundaries. It can snap a terminal ad boundary to a strong silence transition and hold a long proposed cut when no splice evidence supports it.

Cross-fetch differential detection addresses dynamically inserted ads. MinusPod downloads an episode a second time using a different podcast-client identity, aligns the two audio files, and treats differing regions as evidence of content inserted by the publisher's ad system. In `2.40.0` this was an opt-in per-feed feature. By `2.53.0`, it gained an `Auto` mode and runs automatically when the feed or enclosure URL looks DAI-served.

The initial implementation proved that a differential is useful evidence, but later releases narrowed what it is allowed to prove:

- `2.63.0` detects wholesale re-encoding, where most of the file appears different even though the show content is the same. Such comparisons are discarded as unreliable.
- An uncorroborated differential region is held for review rather than cut or discarded. Independent fingerprint, text-pattern, cue, or sufficiently transcript-backed LLM evidence can corroborate it.
- `2.63.2` allows the second processing pass to auto-approve a held DAI span only when the new detection covers at least 90% of one pending marker, lies mostly within it, clears the normal confidence threshold, and was not explicitly rejected by the user.
- `2.64.1` fixes two edge cases where stage rewriting or a stale, barely overlapping confirmation made an apparent auto-approval do nothing.

**Why it matters:** DAI is precisely where a text-only system is weakest: the inserted segment may be quiet, omitted by voice-activity detection, or entirely different on the next download. The new pipeline can catch those ads, but its later safeguards are just as important because a bad alignment can otherwise turn real show content into an apparent ad.

**For this deployment:** automatic differential work may add a second audio download and more CPU/disk activity for feeds identified as DAI-served. Its work is partly overlapped with audio analysis as of `2.62.0`. Review the new Processing stats and Ad Review views before enabling an explicit `On` override for feeds that do not trigger `Auto`.

Sources: [2.40.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L905-L953), [2.53.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L435-L463), [2.63.0 safety changes](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L149-L180), [cross-fetch documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/how-it-works.md#cross-fetch-differential), [upstream PR #485](https://github.com/ttlequals0/MinusPod/pull/485), [upstream PR #542](https://github.com/ttlequals0/MinusPod/pull/542).

## 2. Safer review boundaries and recuts

**Introduced in:** `2.60.0`; expanded in `2.62.1`–`2.64.1`.

Held detections are no longer strictly all-or-nothing. When the reviewer believes a detected span contains an ad plus real show content, it can preserve a proposed trim. The episode page offers a **Confirm trimmed** action, and that correction survives future reprocessing so a wider rediscovery does not restore the content the user chose to keep.

Subsequent releases make the boundary logic more defensible:

- The reviewer is asked to provide adjusted boundaries when its own reasoning identifies non-ad content.
- A duplicated-speech check prevents VAD-gap extension from crossing a DAI splice into real content.
- The reviewer receives timestamped transcript segments instead of timestamp-free text, allowing its numerical trim to target the sentence it describes.
- Contradictory second-pass verdicts are held for review instead of being cut silently.
- Large, unanchored trims do not rewrite cross-episode patterns and affect future episodes.
- Chapter timestamps and applied cuts are persisted together, closing a partial-write window before recut.

**Why it matters:** the system now treats “this is an ad” and “these are the exact safe cut boundaries” as separate judgments. This reduces the chance that a correct ad classification removes adjacent show dialogue.

**For this deployment:** `/app/data` holds the corrections, retained originals, cut history, and chapter metadata needed for recut. Keep the original audio long enough to audition and recut held detections; automatic approval cannot recut when the retained original or saved segments are absent.

Sources: [2.60.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L318-L336), [2.62.1 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L181-L204), [2.63.1–2.63.2 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L103-L148), [2.64.1 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L38-L59).

## 3. Centralized Ad Review workflow

**Introduced in:** `2.48.0`; refined through `2.51.3`.

The Patterns page now includes an **Ad Review** tab that aggregates detections across every podcast. It defaults to unresolved items and supports status and podcast filters, search, sorting, pagination, audio preview, waveform editing, confirmation, and rejection. Later updates add detection totals, responsive mobile cards, and clearer language: **Confirm ad** and **Not an ad** replace the ambiguous Approve/Dismiss terms.

Reviewing multiple held ads in one episode also becomes cheaper. Confirmations can be collected first, then applied in one recut rather than rendering the full episode after every decision. The final remaining confirmation can still use the one-tap confirm-and-recut path.

**Why it matters:** review changes from an episode-by-episode scavenger hunt into an operational queue. That makes the increasingly conservative hold behavior practical; safety would otherwise create unresolved work that is difficult to discover.

**For this deployment:** the two configured feeds can be reviewed from one queue. Audio preview depends on the retained original, so the original-audio retention window controls how long the review interface remains fully actionable.

Sources: [2.48.0–2.48.4 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L695-L744), [2.51.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L523-L580), [Ad Review documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/web-interface.md#ad-review-tab), [upstream PR #497](https://github.com/ttlequals0/MinusPod/pull/497).

## 4. Per-feed processing modes

**Introduced in:** `2.54.0` and `2.61.0`; consolidated in `2.62.0`.

Feeds can now choose between materially different processing paths:

- **Standard:** transcribe, detect ads, verify, and cut.
- **Keep content only:** invert detection toward preserving selected content, with a per-episode fallback to normal removal when safety gates fail.
- **Skip ad detection:** still transcribe and generate chapters, but skip first-pass detection, verification, audio cues, and the second differential download. Nothing is cut.
- **Pass-through:** download and host the episode exactly as published, with no transcription, detection, or cutting.

The precedence is deliberate: pass-through wins over skip detection, and skip detection wins over the selected detection mode. `2.62.0` centralizes this decision so each pipeline stage sees the same effective mode.

**Why it matters:** MinusPod is no longer a single mandatory ad-removal pipeline. It can act as an archive/proxy, a transcript-and-chapter generator for ad-free shows, or a normal remover on a feed-by-feed basis without changing the feed URL in the podcast client.

**For this deployment:** use Skip ad detection for truly ad-free feeds when transcripts and chapters remain useful; use Pass-through when even transcription and its GPU/LLM cost are unnecessary. Existing processed episodes are not retroactively changed merely by flipping a mode.

Sources: [2.54.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L407-L419), [2.61.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L301-L317), [keep-content and skip-detection documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/how-it-works.md#keep-content-only), [pass-through configuration](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/configuration.md#pass-through-mode), [upstream PR #539](https://github.com/ttlequals0/MinusPod/pull/539).

## 5. Offline queue and provider-outage recovery

**Introduced in:** `2.41.0`.

The optional offline queue distinguishes an unreachable dependency from a bad episode. When the LLM provider or remote Whisper endpoint is unavailable because of DNS failure, connection refusal, timeout, repeated server errors, or an open circuit breaker, the episode enters a new `deferred` state. A background probe checks the service approximately every five minutes and automatically requeues deferred episodes when it recovers. A configurable TTL limits how long an episode may remain deferred.

Authentication errors, rate limits, and malformed responses are intentionally not treated as outages. They continue through their normal failure paths, and deferral does not consume processing retry attempts.

**Why it matters:** intermittent OpenRouter or self-hosted transcriber downtime no longer requires manually finding and reprocessing every affected episode.

**For this deployment:** this is directly relevant to OpenRouter availability, although it is off by default. Local Whisper runs in the same pod, so remote-transcriber deferral does not apply to the current local-CUDA path. Enabling the feature adds a data-preserving SQLite table rebuild for the new status and deferred metadata.

Sources: [2.41.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L862-L904), [offline queue documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/configuration.md#offline-queue), [upstream PR #486](https://github.com/ttlequals0/MinusPod/pull/486).

## 6. Processing observability and actionable failures

**Introduced in:** `2.45.0`, `2.52.0`, and `2.53.0`; expanded in `2.64.0`–`2.65.0`.

Several releases turn previously opaque failures into operator-facing state:

- Failed episodes show their stored error reason on the detail page and episode list.
- Quota and billing failures become a distinct **Limit Exceeded** event, are marked non-retryable, and no longer masquerade as bad credentials.
- Feed refresh failures alert only after three spaced failures, show the start time of the outage, suppress alert storms, and clear on recovery.
- Per-run Processing stats show the input duration, transcript size, detection-window count, hits by detection stage, cut/held/kept counts, verification result, and seconds removed.
- A low-ad-yield badge compares the current removal with the feed's recent norm.
- The original RSS duration is compared with the downloaded copy, exposing DAI variance.
- `2.65.0` improves ffmpeg diagnostics by logging actual error lines and distinguishes chunk-extraction failures from transcriber failures.

**Why it matters:** operators can tell the difference between “the episode had fewer ads,” “the publisher served a different copy,” “the provider rejected billing,” “ffmpeg could not extract audio,” and “the detection pipeline missed something.” Those require different responses.

**For this deployment:** OpenRouter quota failures will permanently fail the episode until the account or key limit is fixed; reprocess afterward. Processing stats are the best first check when the two configured feeds produce unexpectedly different results.

Sources: [2.45.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L785-L810), [2.52.0–2.53.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L435-L492), [2.65.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L9-L37), [notification event documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/api-and-webhooks.md#events).

## 7. Native email notifications

**Introduced in:** `2.47.0`.

MinusPod can send notifications directly through an operator-controlled SMTP server. Email supports the same event set as webhooks, provides HTML and plain-text bodies, encrypts the SMTP password, and includes a real send-test action. Alert deduplication is shared with webhooks so one outage does not produce parallel storms.

**Why it matters:** installations no longer need a webhook-to-email sidecar to receive human-readable alerts.

**For this deployment:** this is opt-in and requires SMTP settings. Saving an SMTP password depends on the existing master passphrase, already present in this deployment through the ExternalSecret-backed environment.

Sources: [2.47.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L745-L758), [email notification documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/api-and-webhooks.md#email-notifications), [upstream PR #496](https://github.com/ttlequals0/MinusPod/pull/496).

## 8. Runtime settings and predictable configuration precedence

**Introduced in:** `2.50.0`.

All settings that can originate from both environment variables and the database now follow one rule: the environment value seeds the default, but a value explicitly saved in the UI wins afterward. Previously some stage tunables worked in the opposite direction, leaving controls read-only or allowing an environment value to mask a stored choice.

The episode download, artwork, and RSS body size caps also become runtime settings with UI and API controls. Their environment variables still seed defaults, but raising a cap no longer requires a pod restart. Bootstrap variables were added for auto-processing, feed authentication, and artwork watermarking; setting feed authentication through the environment can mint the initial feed key.

A corrective migration preserves the effective pre-upgrade values and prevents previously customized rows from being overwritten.

**Why it matters:** configuration is easier to reason about. Deployment manifests establish defaults while operators can make intentional runtime changes without fighting environment precedence.

**For this deployment:** the startup logs for `2.65.0` showed the env-backed settings audit, including OpenRouter, auto-processing, media caps, and local processing concurrency. The settings database on persistent storage remains authoritative after an explicit UI edit.

Sources: [2.50.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L581-L617), [environment-variable documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/environment-variables.md), [upstream PR #511](https://github.com/ttlequals0/MinusPod/pull/511).

## 9. Correct chapters and post-cut timelines

**Introduced in:** `2.49.0` and `2.55.0`; recut handling expanded in `2.62.1`.

MinusPod now remaps embedded ID3 chapters onto the post-cut timeline rather than copying stale timestamps from the original. It accounts for the short replacement beep inserted for each cut, drops chapters that existed wholly inside removed spans, and preserves a recoverable fallback when ffprobe cannot read the source chapters.

Generated chapters are also embedded into the processed MP3 as ID3 frames in addition to being exposed through Podcasting 2.0 chapter JSON. Players such as Castro that rely on embedded chapters can therefore use MinusPod-generated chapters directly. Regenerating chapters updates both representations.

The same beep-aware timeline correction applies to VTT, plain-text transcripts, final segments, second-pass detection mapping, and recut chapter remapping.

**Why it matters:** after multiple cuts, a seemingly small one-second-per-cut accounting error can make every later transcript cue and chapter noticeably early. Correct chapter mapping is also essential when a held detection is approved and the episode is rendered again.

**For this deployment:** chapter generation uses the configured LLM path, so it depends on OpenRouter. Episodes processed before the applied-cut history existed may require **Regenerate Chapters** after a recut; the software deliberately avoids guessing for those older records.

Sources: [2.49.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L618-L694), [2.55.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L390-L406), [chapter documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/how-it-works.md#chapter-generation), [upstream PR #510](https://github.com/ttlequals0/MinusPod/pull/510), [upstream PR #524](https://github.com/ttlequals0/MinusPod/pull/524).

## 10. Faster processing and lower I/O

**Introduced in:** `2.62.0`.

The processing pipeline removes several large serial bottlenecks:

- preprocessing filters and FLAC encoding are folded into chunk extraction, avoiding extra ffmpeg passes and intermediate WAV traffic;
- volume, cue, and silence analysis run concurrently;
- the second DAI download overlaps with audio analysis;
- keep-content LLM windows use the parallel window runner;
- fingerprint comparisons use batched NumPy and are reported as four to seven times faster;
- TF-IDF text-pattern matching batches sliding-window transforms;
- cached RSS is served immediately while a bounded refresh runs in the background;
- redundant startup feed refreshes and repeated filesystem walks are removed or cached.

**Why it matters:** long episodes can save minutes before LLM latency is considered, while the pod writes less temporary audio to persistent or ephemeral storage.

**For this deployment:** local CUDA transcription remains the dominant specialized compute path, but ffmpeg, analysis, differential alignment, and pattern matching still consume CPU and disk. Increased concurrency can create sharper short-term resource demand even when total wall time falls.

**Important regression:** folding FLAC encoding into chunk extraction caused ffmpeg to process malformed embedded artwork as a video stream. A mislabeled APIC frame could make every chunk fail. `2.65.0` fixes this with `-vn`, so `2.64.1` should not be used for the local-Whisper path.

Sources: [2.62.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L205-L300), [malformed-artwork issue #556](https://github.com/ttlequals0/MinusPod/issues/556), [2.65.0 fix PR #557](https://github.com/ttlequals0/MinusPod/pull/557), [upstream PR #540](https://github.com/ttlequals0/MinusPod/pull/540).

## 11. Endpoint connection tests

**Introduced in:** `2.64.0`.

Settings now include connection tests for the LLM provider, remote transcription server, and PodcastIndex. The UI distinguishes an unreachable server, a reachable endpoint that rejects the request, and a working configuration.

The tests follow the real application path rather than sending generic pings:

- LLM tests use the provider's model-discovery endpoint and Ollama's `/v1` normalization.
- PodcastIndex sends a signed search request.
- Remote transcription uploads a generated one-second audio sample in the configured FLAC or WAV format, revealing wrong paths, model names, keys, codecs, and cold-load timeouts.

Unsaved server values can be tested, but a saved API key is only sent when the tested URL matches the saved server, preventing the UI from forwarding credentials to an arbitrary host.

**Why it matters:** configuration problems can be isolated before an episode spends time downloading and entering the processing pipeline.

**For this deployment:** the OpenRouter test targets its fixed endpoint and checks the saved key. The live `2.65.0` startup independently verified the OpenRouter endpoint and discovered 338 models. The remote-transcriber test is not relevant while Whisper remains local, but becomes useful if the backend changes later.

Sources: [2.64.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L60-L102), [upstream PR #554](https://github.com/ttlequals0/MinusPod/pull/554).

## 12. Credential-free podcast search

**Introduced in:** `2.65.0`.

Podcast search can use either Apple's iTunes directory or PodcastIndex.org. iTunes requires no account or API key and is the default for installations that never configured PodcastIndex. Existing PodcastIndex users keep their current provider until they explicitly choose another. Both providers return the same internal result shape, and iTunes entries without a usable RSS URL are filtered out.

**Why it matters:** adding a feed by name now works on a new installation without obtaining third-party credentials. PodcastIndex remains available for operators who prefer it.

**For this deployment:** this does not alter existing feeds. It changes only future Add Feed searches and can be selected under **Settings > Podcast Search**.

Sources: [2.65.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L9-L37), [feed search documentation](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/docs/feeds-and-usage.md#podcast-search), [upstream PR #557](https://github.com/ttlequals0/MinusPod/pull/557).

## Runtime-platform change

Although it is not a user-facing feature, `2.43.0` materially changes the deployment envelope:

- Ubuntu 24.04 becomes Ubuntu 26.04.
- Python 3.11 becomes Python 3.12.
- ffmpeg 6 becomes ffmpeg 8.
- PyTorch `2.6.0` with CUDA 12.4 becomes PyTorch `2.13.0` with CUDA 12.6.
- The GPU image stops inheriting from `nvidia/cuda`; CUDA runtime libraries come from the statically linked CTranslate2 runtime and pip-installed NVIDIA wheels.
- The declared host-driver floor remains 525 rather than taking the 580 floor associated with CUDA 13 Ubuntu 26.04 base images.

The live deployment demonstrated that the current node can start this image and expose the RTX 2060 SUPER inside the container. A real transcription is still the stronger proof that Whisper, CTranslate2, CUDA, ffmpeg, storage, and an actual source file work together.

Sources: [2.43.0 changelog](https://github.com/ttlequals0/MinusPod/blob/a834fb3be5f48e51b61a1364100a6ce8ca27ae65/CHANGELOG.md#L835-L844), [upstream PR #488](https://github.com/ttlequals0/MinusPod/pull/488).

## Version-to-feature index

| Versions | Significant capability |
|---|---|
| `2.40.0` | Splice evidence, cross-fetch DAI comparison, tail re-transcription |
| `2.41.0` | Offline queue, editable feed source, per-feed status visibility |
| `2.42.0`–`2.44.0` | Auditioning held/rejected detections and feedback-driven cue tuning |
| `2.43.0` | Ubuntu/Python/ffmpeg/PyTorch/CUDA runtime transition |
| `2.45.0`–`2.47.0` | Actionable failures, quota classification, download cap, native email |
| `2.48.0`–`2.51.3` | Central Ad Review, batch review/recut, unified setting precedence |
| `2.49.0`, `2.55.0` | Correct post-cut timelines and embedded generated chapters |
| `2.52.0`–`2.53.0` | Feed-outage alerts, processing statistics, automatic DAI comparison |
| `2.54.0`, `2.61.0` | Pass-through and skip-ad-detection feed modes |
| `2.58.0` | Compatibility with newer Anthropic models through Anthropic or OpenRouter |
| `2.60.0`–`2.64.1` | Trim-aware review and safer DAI hold/corroboration behavior |
| `2.62.0` | Major processing and I/O performance work |
| `2.64.0` | Real-path endpoint connection tests |
| `2.65.0` | iTunes podcast search and malformed-artwork transcription fix |

## Recommended follow-up validation

The current rollout establishes startup and health, but the highest-value application test is one real local-CUDA episode processing run on `2.65.0`. It should verify:

1. download and ffmpeg preprocessing complete;
2. local Whisper loads on CUDA and produces segments;
3. OpenRouter detection and optional chapter generation succeed;
4. the output duration, transcript, chapters, and Processing stats agree;
5. no new held or rejected detection removes real content;
6. the final pod remains Ready with no restart or error-log burst.

For the specific `2.62.0` regression fixed in `2.65.0`, the strongest targeted test would process an MP3 containing malformed embedded artwork similar to issue #556. Routine processing of a clean episode does not prove that particular fix.
