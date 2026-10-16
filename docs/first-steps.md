# First steps (the guided start)

Owner, 2026-10-16: testers found the app "too much, too crowded" after the welcome pages, and said
they did not know what to do and that it felt like a chore. The guided start plays first and lets
the rest of the app arrive one piece at a time.

Code: `lib/state/first_steps.dart` (state, rules), `lib/features/home/guided_start.dart` (cards,
alert, tips), the coach in `lib/features/game/game_screen.dart` (`_Coach`), tabs in
`lib/features/home/home_shell.dart` and `lib/widgets/glass.dart` (`GlassTabItem.locked`).

## Who gets it

A player who finishes onboarding on this device (`SettingsNotifier.setOnboarded` calls
`FirstSteps.markNewPlayer`): the welcome pages, a first link or a sign-in. Players who started
before 2026-10-16 have no `firstSteps` record and see the whole app as before. A returning account
on a new device is guided too, but its level opens almost everything at once, and nothing is
announced to a player far past it. Deleting an account removes the record, so the fresh start is
guided again.

## The path

1. **Welcome pages, then straight into a first board.** "Start playing" goes to Home and pushes
   the first board over it: Pink Sands Beach (`firstBoardPuzzle`, free starter pack Tropical
   Beaches) on nine cards (Cards 3x3, `?first=1`). The picture loads while the welcome pages are
   open (`firstBoardPrefetchProvider`). It was chosen by scoring every picture of the six starter
   packs for how clearly its nine cards differ in colour and detail; a picture of similar cards
   (rocks, bamboo, night sky) is hard on a first board.
2. **One hint per step on the first board** (until `tutorialSeen`), where the tools will be (the
   tool bar stays laid out but hidden, so the board keeps its size): "Tap a card to pick it up",
   then the picked card's place is outlined (`GameController.guide`, free, not a Hint) with "Now
   tap the outlined spot", then "It locked in place..." (or "They joined..."). No title or step
   count, only the line (owner). The next move ends the hints, the tools fade in, and a toast says
   "Fewer moves earn more stars. Take your time." The close button ends them at once. They never
   come back.
3. **The finish**: its way out is **Home** (the board was opened over it).
4. **A calm Home**: until the daily puzzle opens, the **next step** takes the top of Home as a
   large picture (`NextStepCard(heroHeight:)`; `nextStepProvider`: the first picture, then the next
   picture of the first pack, then "Try Squares" once Squares open, then "Find a pack you like");
   afterwards today's picture is on top and the next step is a card under it. Continue shows a
   board in progress. At the end, the rest of Home is **blurred** under "More opens as you play",
   which says how many pictures the player has solved, lists what opens next and has **Unlock
   anyway** (opens everything).
5. **Everything opens by pictures solved** ([`Reveal`]; owner, 2026-10-16; levels do not count):

   | Pictures | What opens |
   | --- | --- |
   | 2 | packs on Home (all the pack rows) |
   | 3 | Quick play |
   | 5 | the daily puzzle (Home's picture of the day, the daily months on Home and in the Library, the Daily chip), the guest "Save your progress" card |
   | 10 | the daily gift (streak card, Home dot) |
   | 15 | the Lucky Wheel, the level card |
   | 20 | the Quests tab (daily and weekly quests); store offers (VIP banner, break offers) |
   | 25 | achievements on Profile (and its dot) |
   | 30 | the piggy bank |
   | 35 | live events (Home's shelf, the Quests section, event packs in the Library) |
   | 50 | the Social tab (league, friends, inbox) |

   Nothing is announced when something opens (owner: no "Just opened" card or alert).
6. **Locked places say when they open**: locked tabs are drawn faded with a small lock and keep
   their place in the bar; a tap shows "Quests open after 20 pictures" with **Unlock anyway** (that
   tab only) or Not now. A tab that opened by playing carries a dot until it is visited. Profile shows
   achievements, and Quests shows live events, as one locked card with Unlock anyway.
7. **Tips at the moment they matter**, each once: the Library's "Start with the free packs...", the
   board picker's "Pick a shape and a size...", and "Stuck? Hint shows where one card belongs" after
   six moves in a row without a lock or join. Shapes keep their own intros (`UnlockIntroHost`).
8. The board picker opens on **Easy** (one step up from nine cards) until the player picks a board.

Settings > Gameplay > **Guided start** (shown to guided players) turns it off (everything open)
or back on (what the player reached stays open).

## Tests

- `test/first_steps_test.dart`: the rules (who is guided, the schedule, Unlock anyway, tab dots).
- `test/guided_home_layout_test.dart`: the guided Home at SE, Pro and website sizes, both themes,
  text 100% and 200%, before and after the first picture, without layout errors.
- `integration_test/first_steps_test.dart`: the whole path on the simulator with a QA guest
  (screenshots `fs_*`). Every other suite starts past the first steps (`FirstSteps.skipFor`).

Research behind it: Unity's FTUE tips (core loop first, unlock gradually), Supersonic on teasing
features and holding offers back in the first session, and the case against forced click-through
tutorials (contextual hints instead).
