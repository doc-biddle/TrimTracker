# Trim Tracker changelog

Versions follow semantic versioning: MAJOR.MINOR.PATCH.
MAJOR for changes that break saved settings or commands, MINOR for new features, PATCH for fixes.

## 2.0.3 (2026-11-13)
- A quest title that wraps onto a second line under its zone header no longer overlaps the quest below it.

## 2.0.2 (2026-11-12)
- `/trimtracker` opens the options without a "tried to call the protected function" error from Blizzard's options window. Without the client call that allows that, it says where to find the options instead.

## 2.0.1 (2026-11-12)
- The description in the AddOn List now covers what the addon does since 2.0.0. No changes to the addon itself.

## 2.0.0 (2026-11-12)
- Removed: tooltips following the cursor, and its `/trimtracker tips` command. That's outside what a tracker addon should do; Leatrix Plus and similar addons cover it.
- Tracked quests are grouped under zone headers, with the zone you're in first. Click a header to collapse or expand that zone.
- Collapsing a zone untracks its quests, and expanding it tracks them again. New quests in a collapsed zone stay hidden until you expand it. Collapsed zones are remembered per character.
- Each zone header shows how many quests it holds.
- `/trimtracker font <size>` makes the tracker text smaller than Edit Mode allows (6 to 20; `reset` goes back). Edit Mode's Text Size still works on top of it.
- Tighter tracker: less space between quests (`/trimtracker spacing`, 0 to 10, default 5; Blizzard uses 10) and smaller quest map buttons lined up with each quest's title (`/trimtracker buttons`, 0.3 to 1, default 0.7).
- `/trimtracker zones` turns the headers on or off. Turning them off tracks every collapsed quest again.
- Options panel in Options > AddOns > Trim Tracker, with every setting. Its settings also turn up in the options search. `/trimtracker` on its own opens it; `/trimtracker help` lists the commands.
- The quest timer box for timed quests is now its own widget: it no longer covers the first quests or reaches up under the minimap. Move it and size it in the options, or with `/trimtracker timer` (move), `/trimtracker timer <50-200>` (size) and `/trimtracker timer reset`.
- The tracker now grows back when room frees up (a Details! window moved or closed), with no `/reload` needed.

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
