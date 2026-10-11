# Privacy policy

Card Jigsaw World ("the app") is made by Matej Baco. This policy explains what the app stores, where, and why. Last updated 11 October 2026.

## The short version

- You can play without creating an account. The app makes an anonymous guest account for you on first launch.
- There is no advertising network, no third-party analytics and no tracking. The only "ads" are the app's own store promotions.
- Purchases are handled by Apple. We never see your payment details.
- Your data lives on an Appwrite backend in Frankfurt, Germany (EU).
- You can ask us to delete everything at any time.

## What we store

All game data is stored in an [Appwrite](https://appwrite.io) project hosted in the Frankfurt region (`fra.cloud.appwrite.io`), operated under Appwrite's own [privacy policy](https://appwrite.io/privacy).

| Data | Why | When |
|---|---|---|
| Anonymous account id and a generated display name (for example "Brave Otter") | So your progress has somewhere to live | First launch |
| Email address and password hash | Only if you create an email account to keep your progress across devices | When you create an account |
| Apple user identifier (and, if you share it, name and email) from Sign in with Apple | Only if you choose Sign in with Apple. We do not receive your Apple ID password | When you sign in with Apple |
| Profile: coins, tickets, hints, XP, level, streak, piggy bank, unlocked packs, chosen avatar, achievements, statistics | The game economy and your progress | While you play |
| Per-puzzle progress: board layout, moves, time, stars | So you can resume boards and see best scores | While you play |
| Event and goal progress | Live events, daily and weekly goals | While you play |
| Friend code and friends list | So players you invite can see each other on the league board | When you add a friend |
| Purchase records: Apple transaction ids, product id, date, what was granted | To grant purchases once, restore them and handle refunds and renewals | When you buy something |
| Photos you upload in My Puzzles | To play them as puzzles | When you upload them. They are private to your account and are not shown to other players |
| Settings (theme, sound, haptics, timer, reminders) | Stored on the device only | Always |

Your display name, avatar, level and XP are visible to other players on the league leaderboard and to friends who have your friend code. Nothing else is public.

## Purchases

In-app purchases and the VIP subscription are processed by Apple through the App Store. Apple sends the app a signed transaction, which our server (an Appwrite Function) verifies with Apple's certificates before adding the purchase to your profile. We receive the transaction id, the product and the date. We do not receive your name, address or payment details. Apple's handling of this data is described in [Apple's privacy policy](https://www.apple.com/legal/privacy/). Subscriptions renew through your Apple ID and are managed in your App Store settings.

## Images

Puzzle pictures are loaded directly from their sources: Openverse, the Cleveland Museum of Art, the NASA Image and Video Library and Lorem Picsum. Loading a picture sends an ordinary image request (your IP address and the picture URL) to that source, as any browser would. Author and licence are shown with every finished puzzle.

## What we do not do

- No advertising SDKs and no ad network. The promotional cards inside the game only advertise the game's own store.
- No third-party analytics, crash reporters or tracking identifiers.
- No selling or sharing of personal data.
- No chat or messaging between players.

## Children

The game is suitable for all ages. It contains no violent, sexual or frightening content and no links to outside social networks. It does not knowingly collect personal data from children beyond the anonymous game account described above; an email account or Sign in with Apple is optional and should be set up by a parent or guardian for younger players.

## Your choices

- **Play as a guest.** No email, no name, no password.
- **Delete your data.** Contact us (below) from the email on your account, or with your friend code if you play as a guest, and we will delete your account, profile, progress, purchase records and uploaded photos within 30 days. Purchases are refunded through Apple, not by us.
- **Export your data.** On request we will send you a copy of the data listed above.
- **Reminders.** Daily reminders are an opt-in setting and can be turned off at any time.

## Security

Every user table has row-level permissions, so only your account can read or change your progress. Connections use HTTPS. Uploaded photos carry file-level permissions limited to your account.

## Changes

If this policy changes, the new version will be published at this address and the date at the top will be updated.

## Contact

[support email]

Matej Baco, Slovakia
