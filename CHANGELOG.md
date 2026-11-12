# Trim Tracker changelog

Versions follow semantic versioning: MAJOR.MINOR.PATCH.
MAJOR for changes that break saved settings or commands, MINOR for new features, PATCH for fixes.

## 1.0.3 (2026-11-12)
- First release on CurseForge, uploaded automatically by the release pipeline. No changes to the addon itself.
- New logo, also used as the project icon on GitLab, GitHub, Wago and CurseForge.

## 1.0.2 (2026-11-12)
- First release on Wago (addons.wago.io), imported automatically from the GitHub release. No changes to the addon itself.
- The toc now has `X-Wago-ID`, so WowUp and Wago can match an installed copy to its Wago project.

## 1.0.1 (2026-11-12)
- No changes to the addon itself: this release moves it to the BigWigs packager.
- Releases are now published on GitLab (gitlab.com/docbiddle/TrimTracker) and GitHub (github.com/doc-biddle/TrimTracker), each with a `-forever.zip` and `release.json` for WowUp. Wago is next.
- The version shown in the AddOn List now comes from the release tag.
- Licensed under GPL-3.0.

## 1.0.0 (2026-11-12)
- First release, renamed from Tracker Trim. `/trackertrim` still works as well as `/trimtracker`.
- Hides the "All Objectives" header, caps the tracker's height above the Details! windows, and makes skill and interface tooltips follow the cursor.
- Commands: `/trimtracker gap`, `header`, `tips`, `debug`.
- Icon and version number in the game's AddOn List.
