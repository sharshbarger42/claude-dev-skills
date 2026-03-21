---
name: grocery-list
description: Generate a shopping list by cross-referencing Tandoor meal plan and Grocy inventory, with smart restocking rules based on shelf life and stock targets.
disable-model-invocation: false
---

# Generate Grocery List

## Current Meal Plan
!`cat /home/selina/gitea-repos/productivity/WEEK.md`

## Instructions

### Step 1: Get recipe ingredients for the planned meals

- Read the meal plan from WEEK.md (or from Tandoor meal plans for the target week)
- Look up each planned recipe in `~/.local/share/recipe-readiness/readiness.json`
- If readiness.json is missing or stale (>2 hours), fall back to fetching recipe details from Tandoor with `get_recipe_details` and stock from Grocy with `get_stock`
- Collect all ingredients with amounts needed

### Step 2: Check inventory with restocking data

- Fetch current Grocy stock using `get_stock` (pipe through python3 in Bash)
- For each product, extract:
  - Product name, ID, current amount, location_id
  - `min_stock_amount` (built-in)
  - Userfields: `max_stock_amount`, `shelf_life_category` (in `userfields` key on each stock entry, or fetch via `/api/userfields/products/{id}`)
- Also check the Grocy shopping list in case items are already queued

### Step 3: Build the shopping list

Apply these rules **in order**:

#### Rule 1: Below minimum = must buy
For every product with `min_stock_amount > 0`: if `current_stock < min_stock_amount`, add to the list. No exceptions. Use Rule 2 to determine how much to buy.

#### Rule 2: Calculate buy quantity based on shelf life

Only applies to items already on the list (from Rule 1 or Rule 3). This determines **how much** to buy, not **whether** to buy.

**`long` shelf life** (canned, dry goods, frozen, sauces, spices):
- Target: `max_stock_amount - current_stock`
- Round UP to bulk/value package sizes when it saves money
- OK to slightly exceed max if bulk is cheaper per unit
- Examples: buy the 4-pack of canned tomatoes, the 20lb rice bag

**`medium` shelf life** (eggs, butter, onions, potatoes):
- Target: `max_stock_amount - current_stock`
- Round up to nearest standard package (dozen eggs, 1lb butter)
- Do NOT exceed max — fridge space matters
- Check product description for package-specific notes (e.g., egg sizing preferences)

**`short` shelf life** (milk, bread, bananas, fresh produce):
- Buy only what's needed for this week's recipes + small buffer
- Ignore max_stock_amount — it's always "just enough for the week"
- If it's also a staple (min > 0), buy 1 standard unit (1 gallon milk, 1 loaf bread)
- Never stockpile short-shelf items

#### Rule 3: Recipe-only items
Items NOT in Grocy or with no min_stock_amount:
- Only buy if a recipe calls for them
- Buy only the amount the recipe needs (rounded to practical purchase quantities)
- If shelf_life_category is `short` or unset, assume perishable — don't overbuy

#### Rule 4: Sale-driven restocking (Kroger)

For items that are **above minimum but below max**, do NOT auto-add them to the list. Instead, check Kroger for sales.

**Step 4a: Authenticate with Kroger**

Before searching, test Kroger API connectivity:

```bash
cd /home/selina/github-repos/kroger-mcp && python3 -c "
import sys; sys.path.insert(0, '.')
from auth import AuthManager, BASE_URL
import requests
auth = AuthManager()
headers = {'Authorization': f'Bearer {auth.get_app_token()}', 'Accept': 'application/json'}
r = requests.get(f'{BASE_URL}/locations', headers=headers, params={'filter.zipCode.near': '76028', 'filter.limit': 1})
print(f'Kroger API status: {r.status_code}')
if r.ok:
    loc = r.json()['data'][0]
    print(f'Store: {loc[\"name\"]} (ID: {loc[\"locationId\"]})')
"
```

If this returns status 200, skip to Step 4b. If it fails with 401 or any auth error:

1. Start the auth callback listener as a **background Bash task**:

```bash
cd /home/selina/github-repos/kroger-mcp && python3 << 'AUTHEOF'
import os, sys, json
mcp = json.load(open(os.path.expanduser('~/.mcp.json')))
env = mcp['mcpServers']['kroger']['env']
os.environ['KROGER_CLIENT_ID'] = env['KROGER_CLIENT_ID']
os.environ['KROGER_CLIENT_SECRET'] = env['KROGER_CLIENT_SECRET']
sys.path.insert(0, '.')
from auth import AuthManager
auth = AuthManager()
url = auth.generate_authorize_url()
print(f"\nAuth URL: {url}\n")
print("Waiting for callback on port 8080...")
auth.authorize_interactive()
AUTHEOF
```

2. From the background task output, grab the auth URL and present it to the user:

> **Kroger auth is needed before I can check for sales.**
>
> From your local machine, open an SSH tunnel:
> ```
> ssh -L 8080:localhost:8080 productivity
> ```
> Then open this URL in your browser: `<auth URL from above>`
>
> Log in with your Kroger account and approve access. Let me know when it's done.

3. **Stop and wait for the user to confirm** before continuing.
4. After confirmation, re-run the connectivity test to verify auth succeeded.

**Step 4b: Search for sales**

Once authenticated, with the store location ID from step 4a:

1. Collect all staple items where `current_stock >= min_stock_amount` but `current_stock < max_stock_amount`
2. Search each item at the store using the Kroger API:

```python
# Search pattern for each item — use limit=10 to find both sale and cheapest
resp = requests.get(f"{BASE_URL}/products", headers=headers, params={
    "filter.term": "<item name>",
    "filter.locationId": "<store location ID>",
    "filter.limit": 10,
})
# For each product: items[0].price.promo, items[0].price.regular, items[0].size
```

3. Look for promo prices — the API returns both `regular` and `promo` price fields on each item
4. **Only suggest restocking to max if the item has a promo price** — present these as "Sale Opportunities"
5. **For each sale item, also find the cheapest non-sale item** of similar size/type from the same search results. This lets the user compare the sale brand against the everyday cheapest option:
   - From the search results, find the product with the lowest `regular` price in a similar size
   - Prefer store brand (Kroger) as the cheap comparison when available
   - If the sale price is still higher than the cheapest option's regular price, flag it — the "sale" may not actually be the best value
6. For each sale item, show:
   - Sale item: brand, size, sale price, regular price, % off
   - Cheapest comparable: brand, size, regular price
   - Verdict: which is actually cheaper per unit
   - Current stock → max and how much to buy
7. If no items are on sale, skip this section entirely — don't suggest restocking at full price

**Kroger search tips:**
- Search by generic product name (e.g., "crushed tomatoes" not "Hunt's crushed tomatoes")
- Use `limit=10` to get enough results to find both sale items and cheap comparisons
- Batch searches efficiently — group similar items, search the most impactful ones first (biggest gap from max, or most expensive items)
- When comparing sizes, normalize to per-unit or per-oz price when sizes differ significantly

#### Rule 5: Fridge pressure check
After building the full list:
- Count items going **directly** into the fridge (location_id = 2)
- **Exclude pantry-backup items** (see below) — their sealed backup lives in the pantry, not the fridge
- If more than ~8-10 new fridge items on one list, flag it
- Suggest spreading purchases or swapping a recipe for one using more pantry/frozen ingredients

### Pantry-Backup Items

Some items are shelf-stable when sealed but need refrigeration once opened. For these:
- **Max = 2** means: 1 open in the fridge + 1 sealed backup in the pantry
- The sealed backup does NOT count toward fridge pressure
- When the open one runs out, move the backup to the fridge and buy a new backup
- These items follow `medium` shelf life buy rules but don't stress fridge space

**Pantry-backup items:** Ketchup, Ranch, Honey mustard, Mayo, Soy sauce, Light soy sauce, Gochujang, Hoisin sauce, BBQ sauce, Hot sauce, Worcestershire sauce, and similar condiments/sauces that are shelf-stable when sealed.

**How to identify:** Product group 2 (Sauces & Condiments) items are almost always pantry-backup. When in doubt, if a condiment has max=2 and medium shelf life, treat it as pantry-backup.

### Step 4: Compile and categorize

Group the shopping list by store section:
- **Produce** — fresh fruits, vegetables
- **Meat/Protein** — fresh or frozen meats
- **Dairy/Fridge** — eggs, butter, milk, cheese
- **Canned/Dry Goods** — canned goods, pasta, rice, beans
- **Pantry/Baking** — flour, sugar, spices
- **Frozen** — frozen proteins, vegetables
- **Other** — anything else

For each item show:
- Item name
- Quantity to buy (with package size if relevant)
- Reason: "recipe: Yakisoba" or "staple restock" or "below minimum"
- Current stock vs target

### Step 5: Present for review

Show the list in a clean table. Highlight:
- Items below minimum (urgent)
- Good bulk-buy opportunities (long shelf, better per-unit at larger size)
- Fridge pressure warnings if applicable
- Any items the user might want to substitute or skip

Ask for changes before finalizing. User likes to make things from scratch (tortillas, bread) — may skip store-bought versions.

### Step 6: Finalize

- Update WEEK.md grocery list section with the final version
- Optionally add items to Grocy shopping list

## Restocking Reference

### Staples (always keep stocked)
Bread, Milk, Eggs, Butter, Flour, Sugar, Baking soda, Baking powder, Salt, Pepper, Coffee, Ketchup, Ranch, Honey mustard, Mayo, Rice, Onions, Olive oil, Vegetable oil

### Shelf Life Guidelines
| Category | Examples | Buy strategy |
|----------|----------|-------------|
| `long` | Canned goods, rice, pasta, flour, sugar, spices, frozen, sauces | Stock up to max, buy bulk when cheaper |
| `medium` | Eggs, butter, onions, potatoes, cheese | Stock to max, respect fridge space |
| `medium` + pantry-backup | Ketchup, ranch, mayo, soy sauce, gochujang, hot sauce | Max=2 (1 open in fridge + 1 sealed in pantry). No fridge pressure. |
| `short` | Milk, bread, bananas, carrots, fresh produce | This week's needs only |

### Product-Specific Notes
- **Eggs**: Come in 12 or 18 count. Prefer 18 when very low (< 6), 12 otherwise. Max 24.
- **No almond milk** — always substitute soy milk or coconut milk.
- **Water**: 5-gallon jug — refill if empty, don't track in Grocy.
- **Condiments** (ketchup, ranch, mayo, etc.): Shelf-stable when sealed. Keep 1 open + 1 backup. Backup goes in pantry, not fridge.
- **Rotel, egg noodles**: Not staples. Only buy when a recipe calls for them.

## Notes
- User cooks for 3-4 people
- User may substitute items (e.g., make tortillas instead of buying, use sandwich bread instead of buns)
- Always present the list for review — never finalize without confirmation
- Grocy quantities for many items are still "1 = we have it" rather than real counts. Flag uncertain quantities and ask.
