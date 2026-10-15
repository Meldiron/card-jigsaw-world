# House ads

The game runs no ad network. Every "ad" slot promotes something sold in the app (VIP, coin, ticket and hint bundles) or a free feature that leads there. Rules follow Apple guideline 2.5.18 (clearly marked, large close button) and Google Play's Better Ads policy (only at natural breaks, closable).

## Formats

| Format | Where | Timing | Reward |
|---|---|---|---|
| Rewarded offer | Store, "Free coins" card | 15 s countdown, close button always visible; closing early asks "Close and lose the reward?" | 40 coins only after the full 15 s countdown (tapping the offer never skips it); 3 per day (`Profile.adsPerDay`, stored on the profile), 10 min cooldown |
| Interstitial | After a completed puzzle, on Next puzzle / Back to pack | Skip in 5 s, then X and "No thanks" | none |
| Banner | Home, above Featured packs | dismissible per session | none |

Interstitial cadence: every 3rd completion, or right after the current one when the previous break is more than 3 minutes old, no per-session cap, never in the player's first 3 puzzles, suppressed for 10 minutes after a rewarded view, never for VIP. All numbers live in `HouseAdPolicy` in `lib/features/ads/house_ads.dart`.

## Creatives

Nine creatives rotate (never the same one twice in a row) and are targeted by state: low coins -> coin bundle, no hints -> hint pack, no tickets -> ticket bundle, 10+ puzzles and not VIP -> VIP, piggy bank over 60% -> piggy bank. Every creative uses a real pack cover behind a scrim, a kind badge, headline, one-line body, price line and a single CTA that opens the matching screen. Copy follows `docs/copy-guide.md`.

Sources for the caps and formats are listed in the research brief kept in this folder's git history (Apple App Review Guidelines, Google Play Better Ads, AdMob rewarded policies, GameAnalytics, Udonis, PocketGamer, Gamigion).
