# ProfitCraft

A World of Warcraft: Forever addon that finds the most profitable things to buy, craft, disenchant and sell,
then walks you through them one button press at a time. It uses Auctionator's prices, TradeSkillMaster's sale
rates (if you run the TSM app), live auction house searches and your own professions. Profit is figured through
multi-step chains (ore → bars → final item), and it only offers what this character can actually do with the gold
it has.

- **Crafting**: glows and tooltips on the game's own windows (profession window, trainer, What's Training,
  AH recipes) and a **Profit** tab on the AH.
- **Plays**: a **Plays** tab on the AH ranks every money-making play open to you right now (essence
  arbitrage, buying gear to disenchant, with or without an Arcane Salvager, crafting, under-priced resales,
  vendor flips) with its numbers, risk and reasons, and a step button that does each purchase and post.
  A small **Work** button handles the mailbox, essence conversions, disenchanting and crafting.

- **Gold glow** = best, **silver** = 2nd, **bronze** = 3rd.
- Hover anything highlighted (and most things that aren't) for the full buy/craft/sell breakdown.

## Install

Needs **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** for prices and shopping lists.
Optional:
- **What's Training?** (by Sveng): its Professions tab gets glows too.
- **[TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master)** with the TSM desktop app
  logged in: region sale rates, daily sales and your auction house's market values. Without it, plays can't tell
  fast sellers from slow ones, and resale plays are off.

The addon goes in WoW Forever's AddOns folder, in a folder named exactly `ProfitCraft`:

- macOS: `/Applications/World of Warcraft/_forever_/Interface/AddOns/`
- Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\` (or wherever WoW is installed)

**With git** (easiest to update):

```
cd "/Applications/World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/Ayjrin/ProfitCraft.git
```

Update later with `git pull` inside the `ProfitCraft` folder, then `/reload` in game.

**Without git**: on GitHub, **Code → Download ZIP**, unzip it into the AddOns folder and rename the folder from
`ProfitCraft-main` to `ProfitCraft`. The game won't load it under any other name.

## First-time setup

1. **Scan the AH** with Auctionator (full scan), so there are prices.
2. **Open each profession window once.** That's how ProfitCraft learns your recipes, including the
   unlearned ones, which trainer and recipe recommendations need.
3. **Open a trade goods vendor once.** Vendor prices (thread, vials, flux) are recorded automatically.
   Until then those reagents fall back to AH prices, or show "no price".
4. **Optional: run the TSM desktop app** and log in, so plays know what sells fast.
5. **Rehearse a play with dry run on** (the default) before turning it off in Options → ProfitCraft → Buying & selling.

Re-scan the AH now and then; tooltips warn when a price is 2+ days old.

## Plays tab: buy, convert, disenchant, sell

Open the AH, click the **Plays** tab, press the step button once to scan the market (about 30 searches, one a
second). Every play open to this character is then listed, best first:

| Play | Who | What happens |
|---|---|---|
| **Split / combine essences** | everyone | Buy greater essences, split each into 3 lesser, sell the lesser (or the reverse) when the two prices drift apart. No profession needed. |
| **Disenchant** | Enchanters | Buy green/blue armor and weapons below what their mats sell for, disenchant them, post the mats. One play per disenchant bracket. |
| **Salvager disenchant** | Enchanting 140 + an Arcane Salvager | The same, counting the Salvager's bonus, done next to it. Offered only once the bonus is measured (or you set one). |
| **Craft** | your recipes | Buy the reagents, craft, sell (or disenchant, when that pays more). |
| **Resell** | with TSM data | Finished goods listed far under their materials and their usual price, bought to relist. |
| **Vendor flips** | everyone | Listings cheaper than what a merchant pays for them. |

Each play shows:
- **A certainty tier**:
  - SAFE: no luck, sells readily.
  - LIKELY: wins on average, and the batch is big enough for the luck to even out.
  - TIMING: pays if it sells at a good moment.
  - RISKY: slow sellers or small lucky batches.
  - LOCKED: not open to you, with the reason.
- **The numbers**: profit after the AH cut and deposits, the gold it needs, and minutes of your time.
- **Reasons**: two for, two against (stale prices, slow sales, unmeasured rates, the Salvager's cooldown...).

"Offering" (top right) picks which tiers show. By default only SAFE and LIKELY, with a count of what's hidden.

**Running a play.** Select it, press **Start this play**, then press the step button (or its key, or scroll down
over it) once per step:

1. Buying: one press per purchase. Gear: one listing per press, re-read at the press; skipped if it sold or changed.
   Commodities: one press for the quote, one to confirm; if the quote comes back higher than planned, it's cancelled.
2. Take the purchases from your mailbox: the **Work** button, one mail per press.
3. Convert or disenchant: the Work button, one essence or one cast per press.
4. Post: back at the AH, the step button, one auction per press, a copper under the price wall.

Right-click the step button to skip what it offers.

**Dry run is on until you turn it off** (checkbox on the tab, or Options). With it on every press says what it would
have bought or posted and spends nothing, so you can rehearse a play first.

### The Work button

A button that appears when ProfitCraft has something for you to do away from the AH window: take auction mail,
split or combine an essence, disenchant an item it bought for you, or craft a play's recipe. One press = one
action. Shift-drag to move it; `/craftprofit work` keeps it shown.

- Disenchants only items ProfitCraft bought or crafted for disenchanting. Never soulbound items, never items in an
  equipment set. Other unbound greens only if you turn that on.
- Items bought for a Salvager run wait for the Salvager's buff. Without it the button turns red: "Salvager buff
  missing: stand next to your Arcane Salvager".
- Takes auction house mail only (purchases, sales, expired auctions), never cash-on-delivery mail, and keeps a bag
  slot free.
- Does nothing in combat, or while a disenchant is casting.

### Staying within Blizzard's rules

ProfitCraft works like Auctionator, TSM and Blizzard's own AH window: **every purchase, post, cast and mail is
its own click or key press**. What that means in practice:

- **No automation.** Nothing that spends gold, posts, casts or takes mail ever runs from a timer, an event or a
  loop. Each press does at most one of those, and presses that arrive before the previous one has finished are
  ignored, not queued. The offline tests check this for every such call.
- **A press does what the button says.** If the offer changed since it was drawn (another quantity, another
  listing), the press only redraws it.
- **One press, one step, from any input.** Mouse clicks act on release. Keys and scroll-down go to a hidden twin
  of each button that acts on key-down only.
- **Polite searching.** At most one AH search a second, only when the game says its query limit is ready
  (Blizzard: "Search queries are restricted to 100 calls per minute"). No full-AH scans: Auctionator does those.
- **No outside programs.** Nothing runs outside the game and nothing writes into the AddOns folder. Prices come
  from the game, Auctionator and TSM's own addon, through their published APIs.
- **No chat or addon-channel messages, no ads, no donation asks, and every line of code is readable**, per
  Blizzard's UI Add-On Development Policy.
- **Scroll-down is off unless you turn it on.** Even then it only presses the button while your cursor is over
  it. Everywhere else the wheel zooms the camera as usual.

The rules this follows, and where they're written:

- [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534): free,
  visible code, no harm to realms, no ads, no in-game donation requests, must follow the EULA.
- [Blizzard EULA](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement),
  section 1.C: no "code and/or software, not expressly authorized by Blizzard, that allows the automated control
  of a Game".
- Blizzard support, on the forums: an addon that works within the addon API and "doesn't buy/sell for you
  automatically" doesn't violate policy; "one key press = one action is the general rule of thumb".
- The client itself: buying, posting and cancelling need a hardware event (a real key press or click), and casting
  or using items is protected. Blizzard's API docs for Forever 1.60.1 mark them so.

## What it does, window by window

| Where | What you get |
|---|---|
| **Profession window** | Gold/silver/bronze on your best known recipes in that profession. Hover any recipe for profit, return %, sale price, AH cut, reagent cost broken down by buy vs. craft, and a "don't sell below" price. Intermediate recipes say when they're a step in your best craft. |
| **Profession trainer** | Gold/silver/bronze on what to train first (recipes you can learn now). Tooltip adds training cost and how many crafts it takes to pay that back. |
| **What's Training → Professions tab** (the side tab What's Training adds to the profession window) | Gold/silver/bronze on the recipes in its **Available now** section: what to go train or buy first, from any source (trainer, vendor, drop, quest). Follows its search and filters. Hover adds the breakdown, the training cost (or the recipe item's AH price) and the payback. Needs What's Training; does nothing without it. |
| **Recipe items** (patterns, plans, formulas, anywhere: bags, AH, vendors, chat links) | What it teaches, profit per craft, what the recipe item itself sells for, and a verdict: learn it, sell it, already known, not your profession, or needs more skill. |
| **AH browse results** (e.g. the Recipes category) | Gold/silver/bronze on the best recipe items you can learn right now (your skill meets the item's "Requires X (N)" line and you don't know it yet). |
| **AH → Plays tab** | Ranked plays and the step button (see above). |
| **Work button** | Mailbox, essence conversions, disenchanting, crafting: one action per press. |
| **AH → Profit tab** | Every profitable craft you know, with sortable columns: Craft, Profession, Reagent cost, Sells for, (Disenchant, for Enchanters), AH cut, Profit, Return. Tick crafts, set "Crafts of each", press **Create Shopping List** to get an Auctionator shopping list of the reagents. |

### Disenchanting (Enchanters only)

If you have Enchanting, every craft that makes a green, blue or purple armor or weapon is also valued
**disenchanted**: what its dust, essences and shards would sell for on the AH, on average. Without Enchanting
none of this appears anywhere.

- **Profit is the better of the two**: sell the item, or disenchant it and sell the mats. So gold/silver/bronze,
  the Profit tab and `/craftprofit` already point at crafts worth making to disenchant.
- **Tooltip**: "Profit per craft (disenchanted)" when that's the better one, a one-line verdict ("Disenchant it:
  the mats beat selling by 1s 50c" or "Sell it: ..."), then the mats: chance, count and average value of each,
  and the AH cut on them. "Don't sell below" rises to the mats' value, since below that disenchanting pays more.
- **Profit tab**: a **Disenchant** column next to Sells for. Whichever of the two makes more is bright, the other
  dimmed. Sort by it to see what's worth making for mats.
- **Skill doesn't matter**: in WoW Forever any Enchanter can disenchant any item, whatever its level.
- **Blue items under item level 21** are new in Forever and nobody has published what they give yet, so they show
  "not known yet" and are valued by selling only.
- `/craftprofit why` counts the crafts that pay more disenchanted. `/craftprofit status` says whether disenchant
  values are on.

### The shopping list

- Contains the **reagents** for the ticked crafts × "Crafts of each".
- Reagents you can craft more cheaply than you can buy them are broken down, so you buy Linen Cloth, not Bolts.
- Anything already in your bags or bank is subtracted.
- Vendor items aren't added; the tab tells you what to buy from a vendor instead.
- Named "ProfitCraft" (replaced each time). After creating it, the addon switches to Auctionator's Shopping tab.

## The math

All prices are Auctionator's **last-scanned lowest price** per item.

```
Sells for      = AH price of the product × number the recipe makes
AH cut         = Sells for × 5%                 (what the auction house keeps when it sells)
Reagent cost   = sum of each reagent at its cheapest source (see below)
Profit         = Sells for − AH cut − Reagent cost
Return %       = Profit ÷ Reagent cost
Don't sell below = Reagent cost ÷ (number made × 95%)   per item, rounded up
```

**Cheapest source per reagent**: the lowest of
1. buying it on the AH,
2. buying it from a vendor (recorded when you've opened that merchant),
3. crafting it with a recipe you know, valued the same way, recursively, up to 4 steps deep.
   Cycles (e.g. lesser ↔ greater essences) are detected and skipped.

The AH **deposit** is ignored: you get it back when the item sells and lose it only if the auction expires.

**Disenchanted** (Enchanters, green/blue/purple armor and weapons):

```
Mats value     = sum over the item's mats of  chance × average count × AH price   (× number made)
AH cut         = Mats value × 5%
Profit         = Mats value − AH cut − Reagent cost
```

By item level:

- **Green armor**: 75% dust, 20% essence, 5% shard (ilvl 5–15: 80/20, no shard; 21–25: 75/15/10).
  **Green weapons** swap the dust and essence chances (mostly essences).
- **Blue**: always one shard (item level 21+). **Purple** (item level 40+): 2–4 shards, or Nexus Crystals from 56.

Where this comes from:

- **What can be disenchanted, and the skill needed**: the game's own `ItemDisenchantLoot` table for WoW Forever,
  live build 1.60.1.70959, read from [wago.tools](https://wago.tools/db2/ItemDisenchantLoot?build=1.60.1.70959).
  Armor and weapons only; green and blue from item level 5, purple from 40, up to 99. The skill column is 0 on
  every row, which matches the Forever guides: Enchanting 1 disenchants anything.
- **What each bracket gives**: that lives on the server, not in the game files. These are the Classic tables, and
  Wowhead's WoW Forever loot counts match them for greens (e.g. Heavy Linen Gloves 78% Strange Dust / 22% Lesser
  Magic Essence; Hillman's Shoulders 77% Soul Dust / 19% Greater Astral Essence / 5% Large Glimmering Shard).

### Plays: the extra math

**Live prices.** Each item is priced from the best source available, in this order:
1. A live search from the last 15 minutes: yours, Auctionator's or the AH window's. Every search the game
   answers is recorded.
2. Auctionator's last scan.
3. TSM's minimum buyout for your house.

A live search gives every price tier, not just the cheapest, so:

```
Buying N       = walk up the tiers from the cheapest, never above the play's maximum or your budget
Wall           = first price where at least 5 units and 10% of everything listed are offered at or below it
Post at        = wall − 1 copper (1 silver if the AH takes no copper); the thin cheap listings below sell first anyway
Floor          = max(vendor price ÷ 95%, 60% of TSM market value); under it the item is held, not posted
Deposit        = the game's own figure (CalculateCommodityDeposit / CalculateItemDeposit); over 20% of the sale, held
```

Your own listings are left out, so you never undercut yourself.

**Essences** (3 lesser ⇄ 1 greater, from Forever's item tables):

```
Split    profit per set = 3 × lesser post price × 95% − greater price
Combine  profit per set = greater post price × 95% − 3 × lesser price
```

Sets are bought tier by tier while the next set still makes money. Plays never plan to post more than is already
listed.

**Disenchanting gear.** One disenchant gives one kind of mat (dust *or* essence *or* shard), so each green is a
gamble with a known spread:

```
EV (per item)  = Σ chance × E[count] × mat value                   (essences valued in their better form)
σ              = √( Σ chance × E[count²] × value² − EV² )
Max buy price  = EV × 95% ÷ (1 + margin)                           (margin 10% by default)
Items needed   = ⌈ (z × σ ÷ (EV × 95% − price))² ⌉                  (z = 1.645 for a 95% chance of not losing)
```

Fewer listings than that: RISKY. Not enough gold for that many: LOCKED, with how much it needs. So small batches of
dear, lucky gear are never offered as safe.

**Arcane Salvager.** Forever's tables give the item (279985, Enchanting 140), its 15 minutes, the shared 1-hour
camping cooldown and the buff ("chance of bonus disenchanting output is increased"). They don't give the size of
the bonus, and nobody has published it. So:
- ProfitCraft counts **no bonus** until it has measured one, or you set one in Options.
- Every disenchant done with the Work button is recorded with or without the buff, kept apart.
- After 50 buffed disenchants, the measured multiplier on dust and essences replaces your setting.
- After 40 disenchants in one bracket, your measured rates replace the published table. That fills in Forever's
  new blue item level 5–20 bracket too.

**Ranking.** `score = profit × tier factor ÷ minutes of your time`. Tier factors: SAFE 0.97, LIKELY 0.9,
TIMING 0.75, RISKY 0.5. Minutes come from per-action estimates: a buy takes 3–5 s, a disenchant 3.6 s, a post 3 s,
plus a minute per play.

**Time of day.** Each live search also records the cheapest price into a weekday × 3-hour bucket, at most once an
hour per item. After a week, plays say when an item's price is unusually low or high, and when it usually sells
best.

### Profit vs. return: worked example

| | Reagents | Sells for | AH cut | Profit | Return |
|---|---|---|---|---|---|
| A | 10g | 11g | −55s | **45s** | 4.5% |
| B | 2s | 4s | −20c | **1s 80c** | 90% |

- A makes more per craft, but one 5% undercut (someone listing at 10g 45s) turns it into a loss.
- B needs 25 sales to match one A sale, but risks 50s instead of 10g and survives undercuts.
- **Limited gold → rank by return. Limited buyers → rank by profit.**
- The real limit is usually how many will sell. That's the one thing we can't see: Auctionator's public
  API gives prices and their age, not sales volume. You bring that knowledge by what you tick in the
  Profit tab.

### Which crafts glow

A craft has to clear **both** thresholds, then the top 3 by the chosen ranking glow:

- **Minimum return** (default 15%): filters thin-margin traps like A.
- **Minimum profit per craft** (default 1 silver): filters tiny wins like "buy for 1c, sell for 3c" (200%).
  It's 1s rather than 5s because early-level crafts rarely clear 5s, and nothing would glow.

Crafts below the thresholds still appear in the Profit tab (with the return % in orange) and still show
full tooltips. They just don't glow.

**Low-skill fallback**: when *nothing* in a list clears the minimum profit (normal early on, when every
craft is worth copper), the best crafts that still clear the minimum return glow anyway, and their tooltip
says so. The minimum return is never relaxed: thin margins don't glow.

## Settings

Game Menu → Options → AddOns → **ProfitCraft** (or `/craftprofit options`). Account-wide.

| Setting | Default | What it does |
|---|---|---|
| Rank glows by | **Return %** | Return % or Profit per craft. Also the Profit tab's default sort. |
| Minimum return | 15% | A craft needs at least this return to glow. |
| Minimum profit per craft | 1 silver | A craft needs at least this profit to glow. 0 turns it off. |
| Auction house cut | 5% | Change it if Forever's AH keeps a different share. |

"Reset to defaults" is on the same page.

**Buying & selling** (a page under ProfitCraft):

| Setting | Default | What it does |
|---|---|---|
| Dry run | **on** | Buttons rehearse and spend nothing. Turn off to trade for real. |
| Keep back | 15% | Share of your gold never spent (deposits, repairs, postage). |
| Spend at most | 50 gold | Per session. 0 = only the reserve limits it. |
| Plays offered | Safe | Safe / Balanced (+ timing) / Aggressive (+ risky). |
| Chance of not losing | 95% | Sets how big a disenchant batch must be (90 / 95 / 99%). |
| Margin to disenchant | 10% | Mats must beat a green's price by this much for it to be bought. |
| Most items per disenchant play | 200 | About what one Arcane Salvager lasts. |
| Salvager bonus until measured | 0% | Replaced by your own measurement after 50 buffed disenchants. |
| Auction length | longest | The AH's three durations. |
| Scroll down presses the buttons | off | Only over ProfitCraft's step buttons; zoom works everywhere else. |
| Disenchant other unbound greens | off | Also offer greens ProfitCraft didn't buy (never soulbound or equipment-set items). |

**Key bindings**: Options → Keybindings → ProfitCraft:
- "Next auction house step" presses the Plays tab's step button.
- "Work button" presses the Work button.

Any key works, and each press is one step.

## Slash commands

| Command | Does |
|---|---|
| `/craftprofit` (or `/cprofit`) | Top 5 crafts across your professions, ranked by your setting |
| `/craftprofit options` | Opens the settings page |
| `/craftprofit status` | What it has learned: Auctionator found, recipes seen, professions scanned, which windows hooked (including What's Training) |
| `/craftprofit why` | Per profession: how many known crafts make items, have prices, make money, clear the return bar, clear both, and the top 3. Says in plain words why nothing glows when nothing does. |
| `/craftprofit plays` | The top plays right now |
| `/craftprofit ledger` | Last 7 days: bought, predicted, sold, deposits, disenchant accuracy |
| `/craftprofit de` | Your disenchant measurements per bracket and the Arcane Salvager bonus |
| `/craftprofit dryrun` | Dry run on/off |
| `/craftprofit work` | Keep the Work button shown (or only when there's something to do) |
| `/craftprofit wheel` | Scroll-down over the step buttons presses them, on/off |
| `/craftprofit selling` | What plays will post (`selling clear` forgets the list) |
| `/craftprofit errors` | Errors ProfitCraft has hit (kept across reloads). `/craftprofit errors clear` forgets them. |
| `/craftprofit reset` | Forget this character's known recipes (then reopen profession windows) |
| `/craftprofit debug` | Print every error to chat as it happens (normally each kind is announced once per session) |

## Troubleshooting

Nothing glows, or hovering shows no ProfitCraft section:

1. `/craftprofit why` with the profession window open. It tells you whether it's missing prices, nothing
   being profitable, the glow bar, or a window it couldn't hook.
2. `/craftprofit errors`. Errors are never swallowed silently: the first of each kind is announced in chat.
3. Errors and the last thing each window did are also written to the saved-variables file on `/reload` or
   logout (`ProfitCraftDB.errors`, `ProfitCraftDB.diag`), so they can be read outside the game.

## How it's built

| File | Job |
|---|---|
| `ProfitCraft.toc` | Interface 16001 (WoW Forever), load order, saved variables |
| `Core.lua` | Namespace, events, settings defaults, Auctionator price calls, money/percent formatting |
| `Data.lua` | Reads recipes from the open profession window (`C_TradeSkillUI`), records vendor prices |
| `Prices.lua` | Price lookup: live search, Auctionator, TSM; sale rates |
| `Disenchant.lua` | Disenchanting tables, your Enchanting skill, what an item's mats sell for, their spread |
| `Engine.lua` | Cost/profit/return math, multi-step chains, ranking and glow thresholds |
| `Display.lua` | The pulsing glow and the shared tooltip breakdown |
| `Professions.lua` | Hooks the profession window's recipe list |
| `Trainer.lua` | Hooks the trainer list, maps trainer services to recipes |
| `WhatsTraining.lua` | Hooks What's Training's recipe list (its Professions tab) |
| `RecipeItems.lua` | Recipe-item → recipe lookup, skill requirement parsing, item tooltips |
| `Profile.lua` | Gold, reserve, budget, bag space, Arcane Salvager |
| `OrderBook.lua` | Listings at each price from live searches: depth, wall, sell price |
| `Scanner.lua` | Throttled AH searches (one a second, after the game's throttle) |
| `Telemetry.lua` | What your disenchants give, with and without the Salvager |
| `Clock.lua` | Prices by weekday and time of day |
| `Ledger.lua` | Bought, posted, disenchanted, sold |
| `Essences.lua` | Split/combine arbitrage |
| `Plays.lua` | Builds and ranks the plays |
| `Buy.lua` | Purchases, one per press |
| `Post.lua` | Posting, one auction per press |
| `Work.lua` | The Work button (mail, convert, disenchant, craft) |
| `AuctionHouse.lua` | Profit tab, shopping list, AH browse highlights |
| `PlaysTab.lua` | Plays tab and its step button |
| `Options.lua` | Options → AddOns page |
| `Slash.lua` | `/craftprofit` |
| `Bindings.xml`, `Bindings.lua` | The two key bindings |
| `Tests/harness.lua` | Offline tests (not loaded by the game) |

**Saved data** (`WTF/Account/<account>/SavedVariables/ProfitCraft.lua` and per character):
- `ProfitCraftDB.recipes`: recipe definitions seen in any profession window (account-wide; they're static)
- `ProfitCraftDB.vendor`: vendor price per item
- `ProfitCraftDB.settings`: the options above
- `ProfitCraftDB.errors` / `.diag`: the last 10 errors and what each window last painted, for troubleshooting
- `ProfitCraftDB.telemetry` / `.ledger` / `.clock`: disenchant results, trades, prices by time of day
- `ProfitCraftCharDB.known` / `.profs`: per character, which recipes you know and your skill levels
- `ProfitCraftCharDB.deQueue` / `.convert` / `.toSell` / `.craft`: per character, what plays left to do

### What we learned about the WoW Forever client

- Interface `16001`, addon load type `camelot`, build 1.60.1, product code `wowf`.
- It's a modern client: the professions window is the Dragonflight-style `ProfessionsFrame`
  (`CraftingPage.RecipeList.ScrollBox`), the trainer is the modern `ClassTrainerFrame.ScrollBox`, and the AH
  is the modern `AuctionHouseFrame` / `C_AuctionHouse`.
- `C_TradeSkillUI.GetRecipeSchematic` works for unlearned recipes. The trainer exposes
  `GetTrainerServiceItemLink` and `C_TooltipInfo.GetTrainerService`, but no reagents, so reagents come
  from the profession window scan.
- `GetMerchantItemInfo` doesn't exist; vendor prices use `C_MerchantFrame.GetItemInfo`.
- Options pages are registered with `Settings.RegisterCanvasLayoutCategory`, like other addons on this client.
- The CurseForge app updates all the addons it manages in one go, so "it broke overnight" can be another
  addon's update, not a game patch. The game build is in `.build.info` in the World of Warcraft folder.
- Game tables for this client (DB2) are on [wago.tools](https://wago.tools) under the product `wowf`.

### What's Training

What's Training (by Sveng) has no public API, so ProfitCraft reads only its frames, defensively; an update
on its side can switch this feature off but not break the rest:
- `WhatsTrainingCraftingRecipeList` (its recipe page inside `ProfessionsFrame`), `.scrollBox` (a tree
  ScrollBox), `.Filter` (runs on every search, filter and data change), and
  `.categoryNodes[1]:GetData().items` (the filtered "Available now" entries).
- Recipe rows carry `row.data = { recipe = { spell, creates, cost, teach }, category, professionID, profession }`.
  `spell` is the recipe ID; category 1 is "Available now".
- Its row `OnEnter` owns the tooltip (`SetSpellByID`); ProfitCraft appends after it.

### TradeSkillMaster

ProfitCraft only calls `TSM_API.GetCustomPriceValue` with plain price sources:
- `DBMinBuyout` and `DBMarket` (your auction house)
- `DBRegionSaleRate` and `DBRegionSoldPerDay` (the region; asked for ×1000 because TSM rounds price strings to
  whole numbers)

The data comes from the TSM desktop app, through its `TradeSkillMaster_AppHelper` addon. TSM's code and data
tables are its own (all rights reserved); none of it is copied.

### Auctionator rules

Auctionator's source asks that it not be used as a reference for other code. ProfitCraft copies none of
it and only uses what Auctionator publishes for other addons:
- `Auctionator.API.v1`: `GetAuctionPriceByItemID`, `GetAuctionAgeByItemID`, `ConvertToSearchString`, `CreateShoppingList`.
- **LibAHTab** (`LibStub("LibAHTab-1-0")`), the tab library Auctionator ships, to add the Profit tab without
  tainting the AH.

## Testing

Needs [LuaJIT](https://luajit.org) (`brew install luajit` on macOS). From the `ProfitCraft` folder:

```
luajit Tests/harness.lua .
```

The harness stubs the WoW API, loads every file in TOC order, and checks the math (including examples A and B
above), glows in each window, tooltips, the Profit tab and shopping list, and settings. It does **not** prove
the frame names and layout match the real client; that needs an in-game check.

For plays it also checks:
- prices, order-book depth and the wall;
- search throttling;
- essence and disenchant math, batch sizes, tiers and locks;
- buying, posting and the Work button, end to end.

One check runs throughout: every purchase, post, cast, craft and mail call must happen inside a simulated click
or key press, never from an event or a timer. Syntax check alone:
`for f in *.lua; do luajit -b "$f" /dev/null; done`.

## Known limits / not yet verified in game

**Check in game before turning dry run off** (the offline tests stub the game, so these can only be seen live):
- Whether Forever's AH takes copper prices (`SupportsCopperValues`). Posting rounds to whole silver if not.
- Whether dust and essences are commodities on Forever's AH (bought by quantity) or separate auctions. Both paths
  are handled; the second just takes more presses.
- The unit price passed to `StartCommoditiesPurchase`. Blizzard's own Buy window passes one; the API docs omit it.
- How long purchases take to reach your mailbox. Blizzard's hotfix notes say 60 minutes is intended.
- That the Salvager buff (aura 1283701) is readable, so the Work button's lock lifts next to the Salvager.
- That scroll-down over a step button presses it, and the camera zoom still works everywhere else.
- Layout of the Plays tab inside the AH window.

Other limits:

- The Profit and Plays tabs' spacing inside the AH window is a best guess; may need nudging.
- Crafting glows and tooltips assume you can buy and sell at the last-scanned lowest price, and ignore the AH
  deposit and the chance an item doesn't sell. Plays use live depth, walls, the game's deposits and TSM sale rates
  instead.
- The Disenchant button goes by item, not by exact copy: if you also carry an unbound copy of an item you bought to
  disenchant (say, with a better random suffix), either copy may go first. Keep such items in the bank while
  disenchanting.
- The ledger counts a sale when its mail is taken (by any addon or the mail window). Auctions that expire unsold
  only show as the deposit paid when they were posted.
- Recipes with a random yield use the average.
- A profession you've never opened can't be used for multi-step crafts. Tooltips say so when it matters.
- Recipe items are matched to recipes by name ("Pattern: X" → "X"), then by product name.
- Disenchant drop rates are the Classic ones, confirmed by Forever loot counts for greens only, until your own
  measurements replace them (40 disenchants per bracket). Blue items under item level 21 (new in Forever) aren't
  valued until then.
- The Arcane Salvager's bonus isn't counted until measured (50 buffed disenchants) or set in Options.
- Crafting tooltips value disenchant mats at their AH price; plays value essences in their better form
  (3 lesser = 1 greater). A mat with no price leaves the disenchant value as "missing prices".
- Items that can't be disenchanted despite being green gear (rare in Classic) aren't detected.

## Ideas for later

- Shopping list for the finished products, to price-check them before crafting.
- Disenchant by exact item copy (link) rather than item ID.
- Cross-character plays (buy on one character, mail to the enchanter).

## Changelog

- **2.0.0**: Plays.
  - **Plays tab** on the AH, ranking every play open to the character. Essence split/combine, buying gear to
    disenchant (and Arcane Salvager runs), crafting, under-priced resales and vendor flips, each with a certainty
    tier, profit after cut and deposits, gold needed, minutes, and two reasons for and against.
  - **Step button**: one press per search, purchase, quote confirmation or post. Right-click skips, a key binding
    is available, and scroll-down over the button is opt-in.
  - **Work button**: mailbox, essence conversions, disenchanting (locked without the Salvager buff when needed)
    and crafting, one action per press.
  - **Market data**: live search depth and price walls; TSM sale rates and market values; the batch size each
    disenchant play needs; a gold reserve and session cap.
  - **Measurements**: disenchant results recorded with and without the Salvager (measured rates replace the
    tables, and fill in the unknown blue bracket); a ledger of bought, posted and sold; prices by time of day.
  - **Dry run** on by default.

- **1.4.0**: Disenchant values for Enchanters: each green/blue/purple gear craft is valued sold and disenchanted,
  and profit (glows, Profit tab, `/craftprofit`) uses whichever pays more. Tooltip lists the mats and a sell-or-
  disenchant verdict; the Profit tab gets a Disenchant column. Nothing changes for characters without Enchanting.
  Brackets and skill (none needed) from Forever's live `ItemDisenchantLoot` table; drop rates checked against
  Wowhead's Forever loot counts.
- **1.3.0**: Gold/silver/bronze in What's Training's Professions tab, with training cost and payback on hover.
  Low-skill fallback when nothing clears the minimum profit. Errors are recorded and announced instead of
  swallowed; a failed ranking no longer takes hover tooltips down with it. Profession rows not caught by the
  scan are read on hover. `/craftprofit why`, `/craftprofit errors`.
- **1.2.0**: Return % everywhere, "Sells for" and "AH cut" shown separately, "Don't sell below" price,
  thin-margin warning, sortable Profit tab columns, glow thresholds, Options page (rank by return by default),
  this README, tests moved into `Tests/`.
- **1.1.0**: Coin icons, bronze 3rd place, AH Profit tab + Auctionator shopping lists, AH recipe highlights
  limited to what you can learn at your skill.
- **1.0.0**: Profession window and trainer glows, multi-step costing, recipe item tooltips, `/craftprofit`.
