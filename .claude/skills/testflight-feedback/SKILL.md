---
name: testflight-feedback
description: Handle a round of TestFlight tester feedback for Card Jigsaw World end to end - fetch feedback and screenshots from App Store Connect, triage, fix, QA the exact reported path on the simulator, ship a TestFlight build plus web deploy, and resolve the items on Apple. Use when the owner says "check feedback", "address feedback", "new feedback on Apple", or sends iOS screenshots with requests.
---

# TestFlight feedback round

Read the root `CLAUDE.md` first (owner rules, toolchain, code map). The store CLI needs a venv
(once: `python3 -m venv .venv && .venv/bin/pip install -r tools/content/requirements.txt`; `.venv/` is
git-ignored) and reads the App Store Connect key and issuer id from `secrets/` by itself.

## 1. Fetch

```
.venv/bin/python tools/store/asc_publish.py feedback
```

Lists every open item (id, date, tester, device, comment) and downloads each screenshot to
`store/feedback/<id>/1.png` (git-ignored: it contains tester emails). Read every screenshot with the
Read tool; the comment alone is often ambiguous. Most feedback comes from the owner (iPhone 13 Pro) and
one close tester (iPhone 15 Pro) who sometimes writes in Czech; translate before triage. Never copy
tester emails into tracked files (the repo is public).

Skip items that belong to parallel work (see "Work that may be running in parallel" in `CLAUDE.md`):
content/picture items go to the pack-making workflow, not the app.

## 2. Triage

Group items by area and by owner of files. For a handful of items, fix them yourself. For many, split
into 2 to 3 Opus subagents with disjoint file ownership (for example: game/board, UI screens/widgets,
social/profile/data), tell each which files it owns, and say that others edit the rest concurrently.
Product decisions in feedback ("Product decision: ...") are instructions, not suggestions.

Items that are questions or "help me decide" get an answer, not a code change.

## 3. Fix and QA

- Keep to the owner rules in `CLAUDE.md` (design, copy, glass alerts, cost buttons, Quests naming).
- Gates: `flutter analyze --fatal-infos --fatal-warnings`, `flutter test`.
- QA silently on the simulator and look at the screenshots yourself:
  `tools/dev/qa.sh shots` (or the store suite on the Pro Max). Extend
  `integration_test/screenshots_test.dart` so the exact path from the feedback is captured, e.g. a
  new `11d_...png`. Uninstall the app before a second same-day run.
- If a fix lives on a screen, confirm the user can reach that screen from where they reported it.
  (A past mistake: "Discard progress" was added to the difficulty screen, but players resuming a puzzle
  never see that screen; it had to move to the pause menu.)

## 4. Ship

**Builds only when the owner asks** (owner rule, 2026-10-13). After fixing and QA, commit, push and
report "ready for a build"; dispatch nothing on Apple and do not deploy the web until the owner says so.
Items stay open on Apple until the build that carries their fix exists.

1. Update `store/metadata/en-US/release_notes.txt` (the App Store "What's New" for the whole version,
   short bullets, no version bump; first line keeps the cycle's version, e.g. "Version 1.7.0") and
   REWRITE `testflight_build_notes.txt`: a TL;DR of what changed since the previous build only
   (2-4 plain bullets plus one "Please try:" line). The workflow sends it as the build's "What to Test",
   which testers see per build. Fix or backfill one build's text with
   `asc_publish.py --build N build-notes` (only when the owner asks; it is visible to testers).
2. Commit with explicit paths and push (see commit rule in `CLAUDE.md`).
3. Build for TestFlight (only on the owner's request): `tools/dev/testflight.sh` dispatches the "Release to TestFlight" workflow
   and watches it. The workflow signs, uploads, waits for processing, adds the build to the internal
   and public groups and submits Beta App Review when Apple asks for it. Build number = 100 + run
   number. The script refuses a dirty tree or unpushed main. If another agent's files keep the tree
   dirty, run `gh workflow run "Release to TestFlight" --ref main -f version=<current>` and
   `gh run watch` yourself.
4. Web: `tools/dev/deploy-web.sh` (same commit, together with the requested build). Run it after any local Flutter build finishes, not in
   parallel with one.
5. Owner's iPhone: do NOT install unless the owner asks (owner rule); TestFlight delivers the build.
   When asked: `tools/dev/device.sh` (Wi-Fi works). Bump the local build number in `pubspec.yaml`
   if the owner needs to tell builds apart.

## 5. Resolve

After the build is processed and the fix is verified:

```
.venv/bin/python tools/store/asc_publish.py feedback --resolve ID1,ID2,... --note "What was fixed, in which build"
```

This deletes the items on Apple (there is no "resolved" state) and records them with the note and
screenshot paths in `store/feedback/resolved.json`. Only resolve what is actually fixed; leave the rest
open and tell the owner why.

## 6. Report to the owner

Short: what each item became (fixed, answered, deferred with reason), build number, that TestFlight
and the web site carry it, and anything they must do (for example App Store Connect steps).

## Useful facts

- Level is derived from XP (`LevelRewards.levelForXp`); never trust the `level` column alone.
- House ad policy numbers live in `HouseAdPolicy` (`lib/features/ads/house_ads.dart`); its test
  `test/house_ads_test.dart` bounds them, update both when the owner changes the cadence.
- Economy constants: `Economy` in `lib/state/profile.dart`; quests: `Goals` in `lib/state/rewards.dart`.
- Player statistics for other users come from public profile aggregates (`PlayerStats.fromProfile`).
- Manual VIP grants (until gift codes can be minted) are a `vipExpiresAt` date on the profile row.
