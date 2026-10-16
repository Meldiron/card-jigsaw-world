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
   tap the outlined spot", then "It locked in place..." (or "They joined..."). The next move ends
   the hints, the tools fade in, and a toast says "Fewer moves earn more stars. Take your time."
   The close button ends them at once. They never come back.
3. **The finish** says "Your first picture. Home has something new." and its way out is **Home**
   (the board was opened over it).
4. **A calm Home**: today's picture, Continue, one **next step** (`nextStepProvider`: the first
   picture, then the next picture of the first pack, then "Try Squares" once Squares open, then
   "Find a pack you like"), and at the end the rest of Home **blurred** under "More opens as you
   play", which lists what opens when and has **Unlock anyway** (opens everything).
5. **Home and the tabs grow** ([`Reveal`], counted in pictures solved and levels; a 3x3 board is
   about 50 XP, so level 3 is about 5 pictures, level 4 about 8, level 5 about 12):

   | Opens | What |
   | --- | --- |
   | 1st picture | daily gift (streak card, Home dot) |
   | 2 pictures | packs on Home (all the pack rows), the Quests tab |
   | 3 pictures | Quick play |
   | level 3 | Lucky Wheel and piggy bank, the level card, the guest "Save your progress" card |
   | level 4 | the Social tab (league, friends, inbox) |
   | level 5 | achievements on Profile (and its dot), store offers (VIP banner, break offers) |

6. **Locked tabs** are drawn faded with a small lock and keep their place in the bar. A tap shows
   "Quests open after 2 pictures" with **Unlock anyway** (that tab only) or Not now. A tab that
   opened by playing carries a dot until it is visited. Profile shows achievements as one locked
   card with Unlock anyway.
7. **Tips at the moment they matter**, each once: "Just opened" on Home when something opens (with
   a button to it; closing it settles older ones), the Library's "Start with the free packs...",
   the board picker's "Pick a shape and a size...", and "Stuck? Hint shows where one card belongs"
   after six moves in a row without a lock or join. Shapes keep their own intros
   (`UnlockIntroHost`).
8. The board picker opens on **Easy** (one step up from nine cards) until the player picks a board.

Settings > Gameplay > **Guided start** (shown to guided players) turns it off (everything open)
or back on (what the player reached stays open and is not announced again).

## Tests

- `test/first_steps_test.dart`: the rules (who is guided, what opens when, Unlock anyway, tips).
- `test/guided_home_layout_test.dart`: the guided Home at SE, Pro and website sizes, both themes,
  text 100% and 200%, before and after the first picture, without layout errors.
- `integration_test/first_steps_test.dart`: the whole path on the simulator with a QA guest
  (screenshots `fs_*`). Every other suite starts past the first steps (`FirstSteps.skipFor`).

Research behind it: Unity's FTUE tips (core loop first, unlock gradually), Supersonic on teasing
features and holding offers back in the first session, and the case against forced click-through
tutorials (contextual hints instead).
