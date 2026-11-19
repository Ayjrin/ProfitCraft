# ProfitCraft

A World of Warcraft: Forever addon that tells you what's most profitable to craft, using Auctionator's
auction house prices and your own profession data. Profit is figured through multi-step chains
(ore → bars → final item), and it recommends only crafts you can actually make. It stays out of the way:
no new windows, just glows and tooltips on the game's existing menus, plus one AH tab.

- **Gold glow** = best, **silver** = 2nd, **bronze** = 3rd.
- Hover anything highlighted (and most things that aren't) for the full buy/craft/sell breakdown.

## Install

Needs **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** for prices and shopping lists.
**What's Training?** (by Sveng) is optional: with it, its Professions tab gets glows too.

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

Re-scan the AH now and then; tooltips warn when a price is 2+ days old.

## What it does, window by window

| Where | What you get |
|---|---|
| **Profession window** | Gold/silver/bronze on your best known recipes in that profession. Hover any recipe for profit, return %, sale price, AH cut, reagent cost broken down by buy vs. craft, and a "don't sell below" price. Intermediate recipes say when they're a step in your best craft. |
| **Profession trainer** | Gold/silver/bronze on what to train first (recipes you can learn now). Tooltip adds training cost and how many crafts it takes to pay that back. |
| **What's Training → Professions tab** (the side tab What's Training adds to the profession window) | Gold/silver/bronze on the recipes in its **Available now** section: what to go train or buy first, from any source (trainer, vendor, drop, quest). Follows its search and filters. Hover adds the breakdown, the training cost (or the recipe item's AH price) and the payback. Needs What's Training; does nothing without it. |
| **Recipe items** (patterns, plans, formulas, anywhere: bags, AH, vendors, chat links) | What it teaches, profit per craft, what the recipe item itself sells for, and a verdict: learn it, sell it, already known, not your profession, or needs more skill. |
| **AH browse results** (e.g. the Recipes category) | Gold/silver/bronze on the best recipe items you can learn right now (your skill meets the item's "Requires X (N)" line and you don't know it yet). |
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

## Slash commands

| Command | Does |
|---|---|
| `/craftprofit` (or `/cprofit`) | Top 5 crafts across your professions, ranked by your setting |
| `/craftprofit options` | Opens the settings page |
| `/craftprofit status` | What it has learned: Auctionator found, recipes seen, professions scanned, which windows hooked (including What's Training) |
| `/craftprofit why` | Per profession: how many known crafts make items, have prices, make money, clear the return bar, clear both, and the top 3. Says in plain words why nothing glows when nothing does. |
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
| `Disenchant.lua` | Disenchanting tables, your Enchanting skill, what an item's mats sell for |
| `Engine.lua` | Cost/profit/return math, multi-step chains, ranking and glow thresholds |
| `Display.lua` | The pulsing glow and the shared tooltip breakdown |
| `Professions.lua` | Hooks the profession window's recipe list |
| `Trainer.lua` | Hooks the trainer list, maps trainer services to recipes |
| `WhatsTraining.lua` | Hooks What's Training's recipe list (its Professions tab) |
| `RecipeItems.lua` | Recipe-item → recipe lookup, skill requirement parsing, item tooltips |
| `AuctionHouse.lua` | Profit tab, shopping list, AH browse highlights |
| `Options.lua` | Options → AddOns page |
| `Slash.lua` | `/craftprofit` |
| `Tests/harness.lua` | Offline tests (not loaded by the game) |

**Saved data** (`WTF/Account/<account>/SavedVariables/ProfitCraft.lua` and per character):
- `ProfitCraftDB.recipes`: recipe definitions seen in any profession window (account-wide; they're static)
- `ProfitCraftDB.vendor`: vendor price per item
- `ProfitCraftDB.settings`: the options above
- `ProfitCraftDB.errors` / `.diag`: the last 10 errors and what each window last painted, for troubleshooting
- `ProfitCraftCharDB.known` / `.profs`: per character, which recipes you know and your skill levels

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
the frame names and layout match the real client; that needs an in-game check. Syntax check alone:
`for f in *.lua; do luajit -b "$f" /dev/null; done`.

## Known limits / not yet verified in game

- The Profit tab's spacing inside the AH window is a best guess; may need nudging.
- Assumes you can buy at, and sell at, the last-scanned lowest price (no undercut, no market depth).
- Ignores the AH deposit, and the chance an item doesn't sell.
- Recipes with a random yield use the average.
- A profession you've never opened can't be used for multi-step crafts. Tooltips say so when it matters.
- Recipe items are matched to recipes by name ("Pattern: X" → "X"), then by product name.
- Disenchant drop rates are the Classic ones, confirmed by Forever loot counts for greens only. Blues and purples
  haven't been checked against Forever data. Blue items under item level 21 (new in Forever) aren't valued.
- The Forever-only **Arcane Salvager** (Enchanting 140) "improves disenchanting" by an amount nobody has published,
  so it isn't counted. If you use it, your real yields are higher than shown.
- Disenchant mats are valued at the AH price only (3 lesser essences = 1 greater isn't used), and a mat with no
  price leaves the whole disenchant value as "missing prices", same as reagents.
- Items that can't be disenchanted despite being green gear (rare in Classic) aren't detected.

## Ideas for later

- Count the deposit (and its risk) using posting duration.
- A rough "competition" hint from how many are listed when you search an item.
- Shopping list for the finished products, to price-check them before crafting.

## Changelog

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
