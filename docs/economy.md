# Economy model, pack prices and purchase amounts

Answers TestFlight feedback AEJKF0fYEmAVNisOwN27RvY ("increase pack prices, never below 1,000, up to
5,000 for nice packs") and ABNdyJTjMZXS8mv5twUXlHU ("run an economics model, understand the real value of
gold and tickets, update pack prices and what purchases give, keep the prices").

## In one paragraph

*Update 2026-10-13: finishing a puzzle now pays 1.2 coins per card (was 3.2) and replays pay 25% (was 40%), so a regular player earns about **3,500 coins per hour**; see "Lower puzzle rewards" at the end. The numbers below are the model before that change.*

A player earned about **6,000 coins per hour of play** (5,000 to 7,000 depending on how they play, and
more in the first week), and about **15 to 18 tickets per week whatever they play**, because tickets come
from logging in (daily gift, weekly quests), not from playing longer. Before this change a pack cost 300
to 900 coins, which is 3 to 9 minutes of play, and a ticket pack cost 2 to 4 tickets, about two days of
logging in. The whole paid catalogue (library and past months) cost 71,300 coins: twelve hours of play.
The new policy prices a coin pack at **24 to 50 minutes of a regular player's play (2,000 to 5,000
coins)**, a ticket pack at **half to three quarters of a week of free tickets (8, 10 or 12)**, and the
purchases are rescaled so a dollar buys what it should: **$0.99 buys a standard pack, $1.99 buys a
premium ticket pack**. Earning rates are unchanged; only prices and purchase amounts move.

## 1. Where coins, tickets and hints come from

All numbers are read from the code. Formulas use the Dart rounding (`round()` = half away from zero,
`~/` = integer division).

| Source | Coins | Tickets | Hints | Code |
|---|---|---|---|---|
| Finishing a board (first time) | `base = round(cells x 3.2)`; `round((base + (stars - 1) x (base ~/ 3)) x mode multiplier)`. 4x4 three stars = 85, 5x5 = 132, 6x6 = 192 (cards). Replays pay 40% | - | - | `Economy.completionCoins`, `ProfileNotifier.recordCompletion` |
| Mode multiplier | cards x1.0, squares x1.15, triangles x1.35, hexagons x1.5 (on coins and XP) | | | `lib/game/modes.dart` |
| XP per board | `round((round(cells x 2.5) + stars x 10) x multiplier)`; level L needs `100 + 60 x (L - 1)` XP | | | `Economy.completionXp`, `Profile.xpForLevel` |
| Level-up (each level L) | `100 + 25 x L` | 1 every 3rd level | 2 every 2nd level | `LevelRewards.forLevel` |
| Daily gift (7-day cycle) | 50, 75, 100, 125, 150, 200, 400 = **1,100 / week** | 0,0,1,0,1,1,2 = **5 / week** | 0,1,0,1,0,1,2 = **5 / week** | `Economy.dailyRewards` |
| Daily quests (3 free) | 60 + 80 + 100 = **240 / day** (VIP 4th: +120) | - | - | `Goals.daily` |
| Weekly quests (5 free) | - | 1 + 1 + 2 + 2 + 2 = **8 / week** (VIP 6th: +1) | - | `Goals.weekly` |
| Today's daily puzzle | +50 the first time | - | - | `game_screen.dart` |
| World-day event (finish all ~22 pictures of the pack in its 8-day window) | 300 | 1 | - | `events` rows (all 97: 300 + 1); 76 events in 2027 = **1.46 / week** |
| Bonus video (rewarded house ad) | 40 each, 5 a day, 10 min apart | - | - | `Economy.adRewardCoins`, `HouseAdPolicy` |
| Piggy bank | +5 per finished board (replays too), holds 500; opening costs 1 ticket | -1 to open | - | `Economy.piggyPerPuzzle`, `openPiggy` |
| Achievements (24 families, one-time) | 60 to 1,000 per step; 13,170 coins in total | 29 in total | - | `lib/state/achievements.dart` |
| Lucky Wheel (costs 1 ticket, no daily free spin) | expected 122 per spin, jackpot 500 (2.3%) | never pays tickets | 2 hints with 9% chance (0.18 per spin) | `wheel_screen.dart` |
| New profile | 500 | 3 | 3 | `Profile.guest` |
| VIP | "+500 coins every week" is promised on the store and the App Store page, **but no code grants it** (see section 9) | | | |

## 2. The play-time model

**Time per board** = 20 s outside the board (picking a picture, the win screen, a break card every third
puzzle) + `cells x (1.3 + 0.1 x cells) x pace` seconds on the board. Bigger boards take longer per card
because there are more candidates for every swap. The mode multiplier is assumed to pay exactly for the
slower tilings, so every board is counted as its cards-mode equivalent.

Calibration: the owner's own 74 finished boards in the `progress` table took 1.4 s per card on 3x3,
2.2 s on 4x4 and 4.5 s on 6x8; the formula above is about 30% slower than that, which is meant to be a
typical player rather than the developer.

| Player | Plays | Board | Pace | Stars (3 / 2 / 1) | Bonus videos | Weekly quests | Events |
|---|---|---|---|---|---|---|---|
| Casual | 20 min a day, every day | 4x4 (16, the default) | 1.25 (slower) | 60 / 35 / 5% | 1 a day | 6 tickets (skips "3 boards of 5x5") | 1 a week |
| Regular | 1 h a day | 5x5 (25) once level 3 | 1.0 | 75 / 22 / 3% | 3 a day | all 8 tickets | every one (1.46) |
| Heavy | 3 h a day | 6x6 (36) once level 7 | 0.9 (faster) | 85 / 15 / 0% | 5 a day | all 8 tickets | every one (1.46) |

Everyone claims the daily gift, finishes the three daily quests and today's puzzle, opens the piggy bank
when it is full, and plays new pictures (there are 1,106 free library pictures, 30 daily pictures a
month and about 32 event pictures a week, so nobody runs out of first-time boards in the first weeks).
Board size grows with the unlock levels (`LevelRewards.tierUnlockLevel`). Achievements are claimed as
their thresholds are reached. Not counted: the Lucky Wheel (it converts tickets into coins, it does not
create value), Night Owl / Early Bird, friends, VIP.

| | Casual | Regular | Heavy |
|---|---|---|---|
| Seconds per board | 78 | 115 | 179 |
| Boards per hour | 46 | 31 | 20 |
| Coins per board (average stars) | 77 | 125 | 185 |
| A 24-picture pack takes | 31 min | 46 min | 72 min |

## 3. Model results

The simulation runs day by day for 8 weeks. "Week 1" includes the fast early levels and most
achievements; "steady" is the average of weeks 5 to 8.

### Per hour and per week

| | Casual | Regular | Heavy |
|---|---|---|---|
| **Coins per hour, week 1** | 8,636 | 7,461 | 5,970 |
| **Coins per hour, steady** | **6,975** | **5,949** | **5,116** |
| Coins per week, week 1 / steady | 20,151 / 16,276 | 52,230 / 41,646 | 125,370 / 107,434 |
| **Tickets per week, week 1 / steady** | 24 / **14.2** | 37 / **16.8** | 48 / **17.8** |
| Tickets spent on the piggy bank per week | 1.0 | 2.2 | 4.0 |
| Hints per week, week 1 / steady | 19 / 8 | 31 / 10.5 | 47 / 13.5 |
| Level at the end of week 1 / week 8 | 15 / 38 | 26 / 64 | 42 / 104 |

Plus the starting 500 coins, 3 tickets and 3 hints.

### Where the coins come from (steady, per week)

| Source | Casual | Regular | Heavy |
|---|---|---|---|
| Finishing boards | 8,335 (51%) | 27,314 (66%) | 78,336 (73%) |
| Level-ups | 3,331 (20%) | 8,663 (21%) | 21,994 (20%) |
| Daily quests | 1,680 | 1,680 | 1,680 |
| Daily gift | 1,100 | 1,100 | 1,100 |
| Piggy bank | 500 | 1,125 | 2,000 |
| Today's puzzle | 350 | 350 | 350 |
| Bonus videos | 280 | 840 | 1,400 |
| Events | 300 | 450 | 450 |
| Achievements | 400 | 125 | 125 |
| **Total** | **16,276** | **41,646** | **107,434** |

In week 1 achievements add 3,600 to 9,800 coins and 8 to 20 tickets, and level-ups pay 4,400 to 26,700
coins: this is why a new player (and the owner, level 13 with 17,000 coins after a day) feels rich.

### Where the tickets come from (steady, per week)

| Source | Casual | Regular | Heavy |
|---|---|---|---|
| Weekly quests | 6 | 8 | 8 |
| Daily gift | 5 | 5 | 5 |
| Level-ups | 1.0 | 1.8 | 2.8 |
| Events | 1.0 | 1.5 | 1.5 |
| Achievements | 1.2 | 0.5 | 0.5 |
| **Total** | **14.2** | **16.8** | **17.8** |

Sensitivity: a player half as fast earns about a third fewer coins per hour from boards (the daily
sources do not change). Playing only 3x3 boards earns about as much per hour as 4x4, so there is no
cheap farming trick to worry about; replays pay 40% and are not worth farming.

## 4. What coins, tickets and hints are really worth

- **Coins: one hour of play is about 6,000 coins** (regular player, all sources). One minute is about
  100 coins. Gameplay alone is 3,600 to 3,900 coins an hour for every player type; level-ups add about a
  third on top for as long as anyone plays (level rewards grow by 25 per level while the XP per level
  grows by 60, so they settle at about 0.42 coins per XP).
- **Tickets: about 500 coins each.** Tickets are a login currency: 14 to 18 a week for everyone, no
  matter how long they play. What a ticket buys: a full piggy bank (500 coins, at most one per 100
  boards), a Lucky Wheel spin (122 coins + 0.18 hints, about 133 coins of value) or a share of a ticket
  pack. 500 coins is the anchor: a 10-ticket pack is then worth 5,000 coins, just above the best coin
  packs, which is where premium packs belong. The wheel returns about a quarter of a ticket's value: it
  is a fun way to spend spare tickets, never an investment (it never pays tickets).
- **Hints: 150 coins each**, because the game sells one for 150 coins whenever a player has none left
  (`useHint`). That is about 90 seconds of play.
- **Money**: after this change one dollar buys 2,500 to 3,000 coins, so an hour of regular play is worth
  about $2, a standard pack $0.95 and a showcase pack $1.98.

## 5. Everything players can spend on

| Sink | Price | Where |
|---|---|---|
| Coin packs (92) | **2,000 to 5,000** coins (was 300 to 900) | `packs.priceCoins` |
| Past monthly albums (46) | **2,800 to 3,100** coins (was 400); the current month is free | `packs.priceCoins`, category Daily |
| Ticket packs (15) | **8, 10 or 12** tickets (was 2 to 4) | `packs.priceTickets` |
| Hint when none are left | 150 coins (was 60) | `Economy.hintCostCoins` |
| Magic Lock | 300 coins (was 120) | `Economy.magicLockCostCoins` |
| Peek | 75 coins (was 30) | `Economy.peekCostCoins` |
| Early board tier (before its level) | `600 + 300 x tier`: 1,500 / 1,800 / 2,100 / 2,400 / 2,700 for tiers 3 to 7 (levels 2, 3, 5, 7, 10) | `Economy.tierUnlockCoins` |
| Avatars (28 for coins) | 900 coins each, 25,200 for all | `Economy.avatarCoins` |
| Lucky Wheel spin | 1 ticket | `Economy.wheelSpinTickets` |
| Opening the piggy bank | 1 ticket | `Economy.piggyOpenTickets` |
| Restoring a lost streak | `3 + longest ~/ 7` tickets, 3 to 10 | `Economy.streakRestoreTickets` |
| VIP (real money) | $2.99 a month or $14.99 a year: every pack and every past month | App Store |

Free and unchanged: 48 free library packs (1,106 pictures, about 35 hours for a regular player), every
world-day event pack while it is live, the current month's daily album, undo.

## 6. Pack prices

### Policy

Prices are set by hours of play of the **regular player** (about 6,000 coins an hour, 16 free tickets a
week) and applied by `tools/store/apply_pack_prices.py`.

**Coin packs**: `price = pictures x coins per picture of the tier`, rounded to 100, never below 1,000,
never above 5,000. A 24-picture pack costs:

| Tier | Old price (content tool scale) | Hours of regular play | Coins per picture | 24 pictures | 20 pictures |
|---|---|---|---|---|---|
| Standard | 300 to 400 (new packs: 400) | 0.40 h (24 min) | 100 | 2,400 | 2,000 |
| Plus | 500 to 600 | 0.55 h (33 min) | 137.5 | 3,300 | 2,800 |
| Special | 700 to 800 | 0.70 h (42 min) | 175 | 4,200 | 3,500 |
| Showcase ("nice packs") | 900, or a premium pack sold for coins | 0.85 h (50 min) | 212.5 | 5,000 (cap) | 4,300 |

The tier keeps the ranking the packs were created with: what was the most expensive pack stays the most
expensive. The price follows the number of pictures, so a 17-picture pack costs less than a full one.

| Price | Casual (20 min a day) | Regular (1 h a day) | Heavy (3 h a day) |
|---|---|---|---|
| 1,000 (floor) | 9 min of play, 0.4 days | 10 min, 0.2 days | 12 min |
| 2,400 standard | 21 min, 1 day | 24 min, 0.4 days | 28 min |
| 3,300 plus | 28 min, 1.4 days | 33 min, 0.55 days | 39 min |
| 4,200 special | 36 min, 1.8 days | 42 min, 0.7 days | 49 min |
| 5,000 showcase | 43 min, 2.2 days | 50 min, 0.85 days | 59 min |

Reading it: playing a 24-picture pack earns a regular player about 4,000 coins with level-ups, so one
pack pays for roughly the next standard or plus pack, and a showcase pack needs a bit of the daily
income on top. A casual player opens a new pack every one to two days. Nobody can buy the whole catalogue
at once any more: it now costs 438,200 coins (10.5 weeks of a regular player's income, 73 hours of play)
instead of 71,300 (12 hours).

**Past monthly albums** (category Daily, one picture per day) use the standard rate: 2,800 coins for
February, 3,000 for 30-day months, 3,100 for 31-day months. The daily mechanics stay as they are: the
current month is free, today's puzzle pays +50, VIP includes every past month.

**Ticket packs** cost a share of a week of free tickets (16 for the regular player): standard
(old 2) **8 tickets** = half a week, plus (old 3) **10** = 0.6 weeks, special (old 4) **12** = 0.75
weeks; two fewer for packs under 18 pictures. Since every player type earns 14 to 18 tickets a week,
that is about one premium pack a week for anyone who saves their tickets, a clear step up from the old
2 to 4 (one every two days).

**Unchanged by the model**: free packs stay free (they are the starter catalogue), event packs stay
free while live and keep their 300 coins + 1 ticket reward, VIP keeps unlocking everything.

### Re-applying (new packs)

The content tool still creates packs at 400 coins or 3 tickets (or the 300 to 900 price in their spec).
Those are on the old scale, and the script reprices every row below 1,000 coins or 5 tickets. Rows
already on the new scale are left alone, so a price set by hand in the console survives a re-run; use
`--all` to re-derive them as well (the tier is then read back from the price per picture, which is only
reliable while the picture count stays close to the one it was priced with). So: after a content run,
run the script again.

```
python3 tools/store/apply_pack_prices.py            # dry run: what would change
python3 tools/store/apply_pack_prices.py --apply    # write it
```

If earnings change (new rewards, different level curve), `test/economy_test.dart` fails: re-run the
model (appendix), update `REGULAR_COINS_PER_HOUR` / `REGULAR_TICKETS_PER_WEEK` in the script and
`PackPricePolicy` in `lib/data/purchases.dart`, then `--all --apply`.

### Dry run (12 October 2026, 298 packs read, nothing written)

```
packs read: 298  (coins 92, daily 46, event 97, free 48, tickets 15)
coins    coin packs:  92  before 300-900 (total 52,900, mean 575)  after 2,000-5,000 (total 298,200, mean 3,241)
  tiers: standard 25, plus 35, special 27, showcase 5
  new prices: 2,000 x4, 2,100 x1, 2,300 x3, 2,400 x18, 2,800 x6, 2,900 x2, 3,000 x4, 3,200 x2, 3,300 x21, 3,500 x7, 3,900 x4, 4,000 x2, 4,200 x13, 5,000 x5
daily    coin packs:  46  before 400-400 (total 18,400, mean 400)  after 2,800-3,100 (total 140,000, mean 3,043)
  tiers: standard 46
  new prices: 2,800 x3, 2,900 x1, 3,000 x15, 3,100 x27
tickets  ticket packs:  15  before 2-4 (total 43, mean 3)  after 8-12 (total 146, mean 10)
  tiers: standard 6, plus 5, special 4
  new prices: 8 x6, 10 x5, 12 x4
changes: 153
dry run: nothing written. Re-run with --apply to write these prices.
```

Sample rows: Kittens, Parrots, Libraries, Barcelona, Antique Glass & Crystal 900 -> 5,000; Big Cats 800 ->
4,000; Foxes 300 -> 2,400; Sushi (17 pictures) 600 -> 2,300; Land of Fire & Ice 3 -> 10 tickets;
Caves 4 -> 12 tickets; Northern Lights 2 -> 8 tickets; past months 400 -> 2,800 to 3,100. A pack the
content session created while this was written (`abstract-neon`, 600 on the old scale, pictures still
being added) was picked up as plus, 3,300: the rule works for packs that arrive later.

## 7. What purchases give

Prices stay as they are; the amounts change. Every bundle is worth about the same per dollar, counting
a ticket as 500 coins and a hint as 150 coins, and the bigger bundles add up to about a fifth more.

| Product id (fixed on Apple) | Price | Before | **After** | Coin value per dollar | Reads as |
|---|---|---|---|---|---|
| `coins_1000` | $0.99 | 1,000 coins | **2,500 coins** | 2,525 | a standard pack |
| `coins_3000` | $2.99 | 3,000 coins | **8,000 coins** | 2,676 (+6%) | up to three packs |
| `coins_5500` | $4.99 | 5,500 coins | **14,000 coins** | 2,806 (+11%) | five standard or three special packs |
| `coins_12000` | $9.99 | 12,000 coins | **30,000 coins** | 3,003 (+18%) | about nine packs, five hours of play |
| `tickets_5` | $1.99 | 5 tickets | **10 tickets** | 2,513 | most premium packs, or ten spins |
| `tickets_15` | $4.99 | 15 tickets | **30 tickets** | 3,006 (+19%) | two to three premium packs |
| `hints_5` | $0.99 | 5 hints | **16 hints** | 2,424 | |
| `hints_15` | $2.49 | 15 hints | **48 hints** | 2,892 (+15%) | |
| `vip_monthly` / `vip_yearly` | $2.99 / $14.99 | VIP | unchanged | | every pack |

Why hint bundles grow: the game sells a hint for 150 coins whenever a player has none (60 before the
owner approved the booster prices on 2026-10-12), so 5 hints for $0.99 was worth far less than the same
dollar spent on coins. A hint bundle that is worse than buying coins and letting the game spend them is
not worth offering, so the bundles are sized to the same value per dollar as coins.

The three places that hold the amounts now agree and are checked by `test/economy_test.dart`:
`StoreProducts.grants` in `lib/data/purchases.dart` (store screen, house ads, the debug sandbox),
`GRANTS` in `functions/verify-purchase/src/main.js` (what the server credits) and
`store/metadata/subscriptions/consumables.json` (App Store names, descriptions, review notes). All eight
consumables are `READY_TO_SUBMIT` on Apple (never reviewed), so changing their names costs no review.

The house ads now build every amount and price from the same table: the VIP card says "7 days free, then
$2.99/month" (it said $4.99), the coin, ticket and hint cards name the new amounts, and the piggy-bank
card says 5 coins per puzzle (it said 25).

## 8. Release (together with the next build)

Order matters: the server must credit the new amounts before a build shows them. The old build reading
the new server only gets more than it shows, which is harmless.

1. **Deploy the function** (`verify-purchase`, Node 22, entrypoint `src/main.js`, build `npm install`).
   The repo's API keys have no function scope, so deploy through the Appwrite MCP or the console:
   ```
   COPYFILE_DISABLE=1 tar --exclude node_modules -czf /tmp/verify-purchase.tar.gz -C functions/verify-purchase .
   ```
   then `appwrite_call_tool` with `project_id: "6acb4de5003e38d5ebd9"`, `tool_name:
   "functions_create_deployment"`, `confirm_write: true`, arguments `{function_id: "verify-purchase",
   code: {filename: "code.tar.gz", content: <base64 of the tarball>, encoding: "base64", mime_type:
   "application/gzip"}, activate: true, entrypoint: "src/main.js", commands: "npm install"}` (or upload
   the tarball in Console > Functions > verify-purchase > Deployments). Check
   `curl -s https://cjw-verify-purchase.fra.appwrite.run/health` returns `{"ok":true}`.
2. **App Store names and descriptions**:
   `.venv/bin/python tools/store/asc_publish.py iap --dry-run`, then
   `.venv/bin/python tools/store/asc_publish.py iap`. It updates the reference names, review notes and
   en-GB localisations of the eight consumables; prices, availability and review screenshots already
   exist and are left alone.
3. **Pack prices**: `python3 tools/store/apply_pack_prices.py` (check the table), then
   `python3 tools/store/apply_pack_prices.py --apply`. Re-run it after every content session.
4. **Build**: TestFlight build and web deploy as in the apple-release skill (store screen and house ads
   show the new amounts).

## 9. Findings outside this change

- **VIP "+500 coins every week" is not granted anywhere.** It is on the store's VIP card, in
  `docs/purchases.md` and in the App Store description, but no code adds it. Either implement it (a
  weekly claim for VIP on the Quests tab) or remove the line from all three. At 6,000 coins an hour it is
  worth five minutes of play; 2,500 to 5,000 a week would match the new scale.
- **Level-ups pay about a fifth of all coins forever** (100 + 25 x level, while the XP per level grows by
  60). That is the main reason earnings feel generous; the owner asked for price changes only, so it is
  untouched.
- **Boosters were raised x2.5** (owner approved, 2026-10-12): hint 150, Magic Lock 300, Peek 75. Avatars
  (9 minutes of play) and early board tiers (24 minutes for an early 6x6 tier) are still cheap next to
  packs; raising them is a separate decision.
- **Event rewards (300 coins + 1 ticket) are small**: three minutes of play for finishing about 22
  pictures in a week. Left as is (earnings).
- **The Lucky Wheel returns about a quarter of a ticket's value** (122 coins + 0.18 hints for a ticket
  worth 500). Fine for a sink; the comment in `wheel_screen.dart` still assumes a ticket is worth 150.
- Copy that names old amounts outside the files changed here: `store/metadata/en-US/review_notes.txt`
  ("choose 1,000 coins", now "2,500 coins"), `ios/Runner/Products.storekit` (local StoreKit test
  names), `docs/house-ads.md` ("or when the offer is tapped": the reward needs the full countdown),
  `docs/copy-guide.md` ("Unlock for 400"), `README.md` (economy and house-ad rows), and `CLAUDE.md`
  ("Pack prices": the policy is now this document and the script).

## Appendix: the simulation

`test/economy_test.dart` holds a compact copy of the regular player's steady state (it gives 5,928 coins
an hour and 16.2 tickets a week, against 5,949 and 16.8 here) and fails when the earnings drift from the
constants the price script uses. The full day-by-day model behind the tables above:

<details>
<summary>model.py (Python 3, no dependencies): `python3 model.py`</summary>

```python
"""Card Jigsaw World economy model. Mirrors the Dart constants (lib/state/profile.dart,
rewards.dart, achievements.dart, wheel_screen.dart, models.dart). Day-by-day simulation."""
import math, json, sys, collections

# ---- game constants (copied from the Dart code) ----
DAILY_GIFT = [(50,0,0),(75,0,1),(100,1,0),(125,0,1),(150,1,0),(200,1,1),(400,2,2)]
DAILY_QUEST_COINS = [60, 80, 100]          # Goals.daily free; VIP 4th = 120
DAILY_PUZZLE_BONUS = 50
AD_COINS = 40
WEEKLY_TICKETS = [1, 1, 2, 2, 2]           # Goals.weekly free; VIP 6th = 1
EVENT_COINS, EVENT_TICKETS = 300, 1
EVENTS_PER_WEEK = 76 / 52                  # 76 world-day events in 2027 (events table)
PIGGY_PER, PIGGY_CAP = 5, 500
TIER_LEVEL = [1, 1, 1, 2, 3, 5, 7, 10]
CARD_CELLS = [9, 12, 16, 20, 25, 30, 36, 48]
WHEEL = [(60,0,5),(90,0,4),(120,0,4),(0,2,2),(150,0,3),(200,0,2),(300,0,1.5),(500,0,0.5)]

def r(x):  # Dart round(): half away from zero
    return int(math.floor(x + 0.5))

def completion_coins(cells, stars, mult=1.0):
    base = r(cells * 3.2)
    return r((base + (stars - 1) * (base // 3)) * mult)

def completion_xp(cells, stars, mult=1.0):
    return r((r(cells * 2.5) + stars * 10) * mult)

def xp_for_level(l): return 100 + (l - 1) * 60
def level_for_xp(xp):
    l = 1
    while xp >= xp_for_level(l):
        xp -= xp_for_level(l); l += 1
    return l
def level_reward(l): return (100 + 25 * l, 1 if l % 3 == 0 else 0, 2 if l % 2 == 0 else 0)
def max_tier(level): return max(i for i, L in enumerate(TIER_LEVEL) if level >= L)

def wheel_ev():
    w = sum(s[2] for s in WHEEL)
    return sum(s[0]*s[2] for s in WHEEL)/w, sum(s[1]*s[2] for s in WHEEL)/w

# ---- play-time model ----
OVERHEAD = 20.0                      # s per puzzle outside the board (menus, win screen, breaks)
def board_seconds(cells, pace):     # s on the board
    return cells * (1.3 + 0.1 * cells) * pace
def puzzle_seconds(cells, pace): return OVERHEAD + board_seconds(cells, pace)

TYPES = {
    'casual':  dict(minutes=20,  tier=2, pace=1.25, stars={3: .60, 2: .35, 1: .05}, ads=1, weekly=6, events=1.0, speed=.3),
    'regular': dict(minutes=60,  tier=4, pace=1.00, stars={3: .75, 2: .22, 1: .03}, ads=3, weekly=8, events=EVENTS_PER_WEEK, speed=.3),
    'heavy':   dict(minutes=180, tier=6, pace=0.90, stars={3: .85, 2: .15},           ads=5, weekly=8, events=EVENTS_PER_WEEK, speed=.1),
}
# Achievement families (threshold lists, coins step, tickets param) from achievements.dart
def tiered(th, coins, tickets=0): return [(t, coins*(i+1), tickets+1 if i >= 2 else tickets) for i, t in enumerate(th)]
ACH = {
    'solver': tiered([1,10,50,200,500], 60), 'perfect': tiered([5,25,100], 120),
    'streak': tiered([7,30,100], 150, 1), 'level': tiered([5,10,20,35,50], 200, 1),
    'cards': tiered([10,50], 100), 'squares': tiered([10,50], 110), 'triangles': tiered([10,50], 130), 'hexagons': tiered([10,50], 150),
    'big': tiered([5,25], 150), 'master': tiered([1,10], 250, 1), 'nohints': tiered([10,50], 120),
    'collector': tiered([3,10,30], 100), 'daily': tiered([7,30,100], 100, 1), 'events': tiered([5,25], 120, 1),
    'speed': tiered([10,50], 120), 'marathon': tiered([10,25], 200), 'allmodes': [(4, 200, 1)],
    'starhoarder': tiered([50,250,1000], 150), 'rich': [(5000, 0, 2)], 'piggy': [(500, 100, 0)],
}
# Share of a tier's boards (mode mix 25% each) that count for big (>=36) / master (>=48) cells
LADDERS = {'cards': [(3,3),(3,4),(4,4),(4,5),(5,5),(5,6),(6,6),(6,8)], 'squares': [(3,4),(4,5),(4,6),(5,6),(5,7),(6,8),(7,9),(8,10)],
           'triangles': [(4,3),(4,4),(6,4),(6,6),(8,6),(8,8),(10,8),(10,10)], 'hexagons': [(3,4),(4,5),(4,6),(5,6),(5,7),(6,8),(6,9),(7,10)]}
def share(tier, pred): return sum(1 for m in LADDERS.values() if pred(m[tier][0]*m[tier][1])) / 4

def simulate(kind, days=56, vip=False):
    T = TYPES[kind]
    st = collections.Counter()
    xp, level = 0, 1
    piggy = 0
    acc = collections.Counter()   # cumulative counters for achievements
    claimed = collections.defaultdict(int)
    weeks = []
    wk = collections.Counter()
    puzzles_frac = 0.0
    ev_frac = 0.0
    for day in range(days):
        # board size: preferred tier capped by level
        tier = min(T['tier'], max_tier(level))
        cells = CARD_CELLS[tier]
        n = T['minutes'] * 60 / puzzle_seconds(cells, T['pace'])
        puzzles_frac += n
        k = int(puzzles_frac); puzzles_frac -= k
        avg_coins = sum(p * completion_coins(cells, s) for s, p in T['stars'].items())
        avg_xp = sum(p * completion_xp(cells, s) for s, p in T['stars'].items())
        avg_stars = sum(p * s for s, p in T['stars'].items())
        p3 = T['stars'].get(3, 0)
        # gameplay
        wk['coins:gameplay'] += k * avg_coins
        xp += k * avg_xp
        newl = level_for_xp(int(xp))
        for l in range(level + 1, newl + 1):
            c, t, h = level_reward(l)
            wk['coins:level-ups'] += c; wk['tickets:level-ups'] += t; wk['hints:level-ups'] += h
        level = newl
        # piggy (+5 per completion, open with 1 ticket when full)
        piggy += k * PIGGY_PER
        while piggy >= PIGGY_CAP:
            piggy -= PIGGY_CAP
            wk['coins:piggy'] += PIGGY_CAP; wk['tickets:piggy (spent)'] -= 1
            acc['piggyfull'] = 500
        # daily gift, quests, daily puzzle, ads
        c, t, h = DAILY_GIFT[day % 7]
        wk['coins:daily gift'] += c; wk['tickets:daily gift'] += t; wk['hints:daily gift'] += h
        wk['coins:daily quests'] += sum(DAILY_QUEST_COINS) + (120 if vip and cells >= 25 else 0)
        wk['coins:daily puzzle'] += DAILY_PUZZLE_BONUS
        if not vip: wk['coins:bonus videos'] += T['ads'] * AD_COINS
        # events
        ev_frac += T['events'] / 7
        if ev_frac >= 1:
            ev_frac -= 1
            wk['coins:events'] += EVENT_COINS; wk['tickets:events'] += EVENT_TICKETS
            acc['eventpuzzles'] += 24
        # achievement counters
        acc['solver'] += k; acc['perfect'] += k * p3; acc['streak'] = day + 1; acc['level'] = level
        for m in ('cards', 'squares', 'triangles', 'hexagons'): acc[m] += k / 4
        acc['big'] += k * share(tier, lambda c: c >= 36); acc['master'] += k * share(tier, lambda c: c >= 48)
        acc['nohints'] += k * 0.8; acc['collector'] = 2 + acc['solver'] / 15; acc['daily'] += 1
        acc['events'] = acc['eventpuzzles']; acc['speed'] += k * T['speed']; acc['marathon'] = max(acc['marathon'], k)
        acc['allmodes'] = 4 if acc['solver'] >= 4 else acc['solver']; acc['starhoarder'] += k * avg_stars
        acc['rich'] = 5000 if day >= 3 else 0   # 'Well Off': holds 5,000 coins by day 4
        acc['piggy'] = acc['piggyfull']
        for fam, steps in ACH.items():
            while claimed[fam] < len(steps) and acc[fam] >= steps[claimed[fam]][0]:
                th, c, t = steps[claimed[fam]]
                wk['coins:achievements'] += c; wk['tickets:achievements'] += t
                claimed[fam] += 1
        wk['puzzles'] += k
        wk['minutes'] += T['minutes']
        if day % 7 == 6:
            wk['tickets:weekly quests'] += T['weekly']   # 8 = all five free weekly quests
            if vip: wk['tickets:weekly quests'] += 1
            wk['level_end'] = level; wk['cells'] = cells
            weeks.append(wk); wk = collections.Counter()
    return weeks

def totals(w):
    coins = sum(v for k, v in w.items() if k.startswith('coins:'))
    tickets = sum(v for k, v in w.items() if k.startswith('tickets:') and 'spent' not in k)
    hints = sum(v for k, v in w.items() if k.startswith('hints:'))
    return coins, tickets, hints

if __name__ == '__main__':
    ev = wheel_ev()
    print('wheel EV per ticket: %.1f coins + %.3f hints' % ev)
    out = {}
    for kind in TYPES:
        weeks = simulate(kind)
        T = TYPES[kind]
        hours = T['minutes'] * 7 / 60
        w1 = weeks[0]
        steady = collections.Counter()
        for w in weeks[4:8]:
            for k2, v in w.items(): steady[k2] += v / 4
        print(f"\n=== {kind}: {T['minutes']} min/day, {hours:.1f} h/week")
        for label, w in (('week 1', w1), ('steady (weeks 5-8 avg)', steady)):
            c, t, h = totals(w)
            print(f"  {label}: puzzles {w['puzzles']:.0f}, level at end {w['level_end']:.0f}, board {w['cells']:.0f} cells")
            print(f"    coins {c:,.0f}/week = {c/hours:,.0f}/hour of play; tickets {t:.1f}/week; hints {h:.1f}/week; piggy tickets spent {w['tickets:piggy (spent)']:.1f}")
            for k2 in sorted(w):
                if ':' in k2: print(f"      {k2:28} {w[k2]:>9,.1f}")
        out[kind] = dict(weeks=[dict(w) for w in weeks])
    json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else '/dev/null', 'w'), indent=1)
```

</details>


## Lower puzzle rewards (owner request, 2026-10-13)

`Economy.coinsPerCard` 3.2 -> 1.2 and `Economy.replayCoinShare` 0.4 -> 0.25; stars still add a third per
star above one and modes still multiply. Pack prices stay as set on 2026-10-12, so a pack now costs more
play time (`tools/store/apply_pack_prices.py` keeps `TIER_PACK_COINS` and records
`REGULAR_COINS_PER_HOUR = 3500`).

| Board (3 stars, first time) | Before | After |
|---|---|---|
| Cards 4x4 (16) | 85 | 31 |
| Cards 6x6 (36) | 191 | 71 |
| Squares 4x5 (20) | 122 | 46 |
| Triangles Easy (28) | 202 | 76 |
| Hexagons Easy (38) | 303 | 114 |
| Hexagons largest (112) | 894 | 333 |

Regular player: boards 27,300 -> 10,200 coins a week; all sources 41,400 -> 24,300 a week (about 5,900 ->
3,500 coins per hour); a standard 2,400-coin pack goes from about 25 to about 40 minutes of play.

## Quest pool and unlocks (2026-10-14)

Rewards per slot are unchanged (daily 60 + 80 + 100 coins, VIP 120; weekly 1 + 1 + 2 + 2 + 2 tickets,
VIP 1), so the totals above still hold. What changed is which quest fills a slot (`Goals.daily`,
`Goals.weekly`):

| Slot | Reward | Quest (rotates by day or week) |
|---|---|---|
| Daily 1 | 60 | Solve 3 puzzles |
| Daily 2 | 80 | Earn 3 stars twice / Solve 2 pictures without Peek / Finish a board at par |
| Daily 3 | 100 | Finish a <shape> board / Lock 5 cards in one move / Solve a Painting board |
| Daily VIP | 120 | Finish a 5x5 (4x4 below level 3) or bigger board |
| Weekly 1 | 1 | Solve 10 puzzles this week |
| Weekly 2 | 1 | Collect 15 stars / Solve 5 pictures without Peek / Finish 3 boards at par |
| Weekly 3 | 2 | Play on 4 different days |
| Weekly 4 | 2 | Finish 3 boards of 5x5 or bigger / Lock 5 cards in one move on 3 pictures / Solve 3 Painting boards |
| Weekly 5 | 2 | Play every mode once (only the modes the player has; "Earn 3 stars 5 times" with Cards only) |
| Weekly VIP | 1 | Finish 2 boards of the trickiest open shape (hexagons once open; "Solve 15 puzzles" with Cards only) |

Shapes and options open as levels rise (`Unlocks.levels` in `lib/state/rewards.dart`): Squares at
level 2, Triangles 4, Hexagons 6, Painting 8, giant boards 10. A player who plays about 20 minutes a day
earns roughly 1,000 XP a day, so the first comes after the second picture and the rest about a day apart.
Anything a player already used (a board finished or in progress) stays open whatever the level. A
quest never asks for something locked: the shape or Painting quest falls back to "Lock 5 cards in one
move", and a slot keeps the quest already claimed in it, so a level-up that changes the pick never pays
twice.
