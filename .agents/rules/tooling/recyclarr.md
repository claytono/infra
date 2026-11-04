---
paths: ["tools/recyclarr/**"]
---

# Recyclarr

`tools/recyclarr/data/recyclarr.yml` syncs the Sonarr and Radarr quality
profiles, named `1080p (TRaSH)` and `2160p (TRaSH)` in both apps. The profiles
deliberately depart from the TRaSH templates. Keep these behaviours when editing
the config, or the problems they fix come back.

## Sonarr prefers HEVC

Untouched HEVC WEB-DLs and tier 1 x265 encodes outscore every H.264 WEB-DL, and
`until_score: 1900` stops upgrades once a file reaches one of them. The ranking
comes from the local custom formats in `data/custom-formats/sonarr/`, which
`data/settings.yml` registers. TRaSH's x265 formats can't tell an untouched HEVC
WEB-DL from a re-encode, so they stay at an explicit score of 0; leaving them
out would let `reset_unmatched_scores` give them -10000.

The score table is in the comment above `custom_formats` in the Sonarr section.
Keep every H.264 score below `until_score`.

## Bluray shares the WEB group in Sonarr

Non-remux Bluray sits in the WEB quality group of the same resolution;
`Bluray-2160p Remux` stays a separate entry just below WEB 2160p. With TRaSH's
separate Bluray entries ranked below WEB, the 2160p profile grabbed 1080p WEB
releases as upgrades over 4K Bluray episodes. A lower-resolution release must
never rank above a higher-resolution file.

## Radarr profiles have fallbacks

The 1080p profile accepts 720p WEB and the 2160p profile accepts 1080p, so a
movie without a release at the preferred resolution still downloads instead of
dropping to SD or never downloading.

## After editing

Run `tools/recyclarr/recyclarr sync`, then check the profiles in Sonarr and
Radarr.
