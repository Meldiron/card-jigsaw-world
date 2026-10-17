# Privacy policy

Carden ("the app", formerly Card Jigsaw World, on iPhone and at play.carden.page) is made by Matej
Baco. This policy explains what the app stores, where, who can see it, and how to delete it.
Last updated 17 October 2026.

## The short version

- You can play without creating an account. The app makes an anonymous guest account for you on first launch.
- There is no advertising network, no third-party analytics and no tracking. The only "ads" are the app's own store promotions.
- The app sends usage data (which screens and features are used) to our own backend only, to make the game better. You can turn it off in Settings > Privacy > Share usage data.
- Purchases are handled by Apple. We never see your payment details.
- The app talks only to our backend (Appwrite, Frankfurt, Germany, EU) and to Apple. Every picture is served from our own storage.
- You can delete your account and everything stored for it in the app, at any time.

## What we store

All game data is stored in an [Appwrite](https://appwrite.io) project hosted in the Frankfurt region (`fra.cloud.appwrite.io`), operated under Appwrite's own [privacy policy](https://appwrite.io/privacy). The web version is served from the same project.

| Data | Why | When |
|---|---|---|
| Anonymous account id and a display name (generated, for example "Brave Otter", and changeable in Profile) | So your progress has somewhere to live and the leaderboard has a name | First launch |
| Email address and password hash | Only if you create an email account to keep your progress across devices | When you create an account |
| Apple user identifier (and, if you share them, name and email) from Sign in with Apple | Only if you choose Sign in with Apple. We never receive your Apple ID password | When you sign in with Apple |
| Profile: coins, tickets, hints, Peeks, Magic, XP, level, streak, piggy bank, unlocked packs and boards, chosen avatar, achievements, claimed quests and play statistics (puzzles solved, stars, moves, time played) | The game economy and your progress | While you play |
| Per-puzzle progress: board layout, moves, time, stars | So you can resume boards on any device and see best scores | While you play |
| Event and quest progress | Live events, daily and weekly quests | While you play |
| Coin, ticket and hint history | So your balance is the same on every device and is never counted twice | While you play |
| Friends list (the friend codes you added) | So you can open your friends' profiles | When you add a friend |
| Players you block | So they no longer show on your leaderboard | When you block someone |
| Reports you send about a player (who, the name they had and the reason) | So we can act on offensive names and cheating | When you report someone |
| Messages we send you in Social > Inbox (subject, text, an optional gift and link), and which ones you opened, claimed or deleted | So we can tell you about the game, say thank you or send a gift | When we send a message |
| Feedback you send from Settings (your message, your account id, the app version and whether it came from iPhone or the web) | So we can read your ideas and problems | When you send feedback |
| Pack codes you redeem (on the web version) | So a code opens its pack once per account | When you redeem a code |
| Purchase records: Apple transaction ids, product, date, what was granted, and Apple's per-account app identifier used for Family Sharing | To grant purchases once, restore them, share VIP with your family and handle refunds and renewals | When you buy something |
| Photos you upload in My Puzzles | To play them as puzzles | When you upload them. They are private to your account and are never shown to other players |
| Usage data: the screens you open, the app going to the background and back (with the time spent in it), and what you do in the game, such as a puzzle started or finished (mode, board size, stars, moves, time), a tool used, a pack opened or unlocked, a reward claimed, a purchase started or completed (the product), and changes to Settings > Accessibility. With each event, Appwrite records the approximate location of the connection (country, region and city, from the IP address) and the device, system or browser type | To see which parts of the game are used and where players get stuck, so we can improve it. See "Usage data" below | While you play, unless Share usage data is off |

Stored on the device only, never sent to us: settings (theme, sound, music, haptics, timer, reminder time, Share usage data), which daily reminders and event notes are planned, and the save that is waiting to sync.

## What other players can see

Your display name, avatar, level, XP, streak, achievements and play statistics are visible to other players on the leaderboard and on your player page (anyone with your friend code can open it too). Your email, Apple identity, purchases, photos, friends, blocks, reports and feedback are never shown to anyone.

Players can report a display name or unfair play, and block a player so they no longer see them on their leaderboard. Reports are read only by us; the reported player is not told who reported them.

## Usage data

The app sends usage data to [Appwrite Analytics](https://appwrite.io), part of the same Appwrite project in Frankfurt that stores your game, and to nobody else. It is listed in the table above: the screens you open, the time the app spends in the foreground, and what you do in the game.

- Event details never include your name, email, anything you type, your photos, your friend code or friends, or another player's identity. Packs, live events and achievements are named by ids that are the same for every player.
- Events are sent with your game session, like every other request the app makes, so they belong to your game account in our Appwrite project. Appwrite works out an approximate location (country, region and city) from the connection's IP address and the device or browser type from the request.
- We use usage data only to understand and improve the game. It is never used for advertising, never combined with data from other companies, never used to track you across apps or websites, and never sold or shared.
- **Turn it off**: Settings > Privacy > Share usage data. Off stops it at once, on iPhone and on the web, and it stays off until you turn it back on (the choice is stored on the device; set it again on a new device or browser).
- Usage data already sent stays in our Appwrite project's analytics after you turn it off or delete your account. Contact us (below) with any request about it.

## Pictures

Puzzle pictures come from public-domain and openly licensed sources (for example Wikimedia Commons, Openverse, Flickr, iNaturalist, Pixabay and museum open-access collections such as the Cleveland Museum of Art, the Metropolitan Museum of Art, the National Gallery of Art and the Rijksmuseum), and some are AI-generated or made by us. A copy of every picture is kept in our own Appwrite storage and loaded from there, so viewing a picture sends no request to those sources. Author and licence are shown with every picture.

## Purchases

In-app purchases and the VIP subscription are processed by Apple through the App Store. Apple sends the app a signed transaction, which our server (an Appwrite Function) verifies with Apple's certificates before adding the purchase to your account. Apple also tells our server about renewals, refunds and Family Sharing changes. We receive the transaction details listed above, never your name, address or payment details. Apple's handling of this data is described in [Apple's privacy policy](https://www.apple.com/legal/privacy/). Subscriptions renew through your Apple ID and are managed in your App Store settings. The web version sells nothing.

## Notifications

Daily reminders and notes before a new event are local notifications: they are planned on your device, and nothing about them is sent to us. Both are off until you turn them on (event notes have their own switch in Settings), and both can be turned off at any time in Settings.

## Updates

To tell you when a newer version is out, the app reads a public record of the latest build number from our backend (on the web, a small version file of the site). Nothing about you is sent with it.

## What we do not do

- No advertising SDKs and no ad network. The promotional cards inside the game only advertise the game's own store.
- No third-party analytics, crash reporters or tracking identifiers, and no tracking across apps or websites. Usage data goes only to our own Appwrite project (see "Usage data") and can be turned off.
- No selling or sharing of personal data.
- No chat or messaging between players.

## Children

The game is suitable for all ages. It contains no violent, sexual or frightening content and no links to outside social networks. It does not knowingly collect personal data from children beyond the anonymous game account described above; an email account or Sign in with Apple is optional and should be set up by a parent or guardian for younger players.

## Keeping and deleting your data

We keep your data while your account exists. Reports are kept until we have looked at them, and are deleted with the account of either player.

- **Delete your account.** In the app: Profile > Account > Delete account, for guests and signed-in players. It deletes your account, profile, progress, history, purchase records, friends, blocks, reports and uploaded photos at once, on every device; if you signed in with Apple, the game's access to your Apple ID is revoked too. You can also contact us (below) from the email on your account, or with your friend code if you play as a guest, and we will do the same within 30 days. Deleting your account does not cancel a VIP subscription: cancel it in your App Store subscriptions. Purchases are refunded through Apple, not by us.
- **Export your data.** On request we will send you a copy of the data listed above.

## Security

Every player table has row-level permissions, so only your account can read or change your progress, and nobody but us can read reports or feedback. Connections use HTTPS. Uploaded photos carry file-level permissions limited to your account.

## Changes

If this policy changes, the new version will be published at this address and the date at the top will be updated.

## Contact

contact@almostapps.eu (Settings > Contact support). The email the app prepares adds the app version and
your player id below your message, so we can find your account; you can delete them before sending.

Matej Baco, Slovakia
