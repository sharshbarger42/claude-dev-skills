---
name: meal-plan
description: Plan meals for the week using Tandoor recipes and Grocy inventory, accounting for ingredients already committed to the current week.
disable-model-invocation: false
argument-hint: "[number of dinners] [any preferences]"
---

# Meal Planning

## Current State
!`cat /home/selina/gitea-repos/productivity/WEEK.md`

## Instructions

### Step 1: Load recipe readiness data

1. Read `~/.local/share/recipe-readiness/readiness.json`
2. If the file is missing or `generated_at` is more than 2 hours old, fall back to direct API calls (fetch recipes from Tandoor with `get_recipes`/`get_recipe_details` and stock from Grocy with `get_stock`)
3. Note the pre-computed readiness scores — recipes are ranked by what percentage of ingredients are in stock

### Step 2: Get this week's committed meals

1. Determine the current week's date range (Monday–Sunday)
2. Fetch this week's Tandoor meal plan using `get_meal_plans` with `from_date` and `to_date`
3. For each already-planned meal, note its ingredients as "committed" (subtract consumable proteins, produce, canned goods, eggs/dairy, and noodles from available stock; do NOT subtract pantry staples like sauces, spices, oils, flour, sugar, salt, pepper)

### Step 3: Suggest meals

- Suggest $0 dinners (default: 3-4 if not specified)
- Prefer recipes already in Tandoor
- Pick from the top of the readiness list (highest `readiness_pct` first)
- Prioritize recipes with `expiring_soon` ingredients (use them before they go bad)
- Consider variety (don't repeat cuisines or proteins back-to-back)
- All meals should be <45 min active cook time
- Apply any preferences from arguments: $ARGUMENTS

### Step 4: Present the plan with verification

Show:
1. **Committed ingredients summary** — "This week's meals will use: 2 ground beef, 4 onions, 1 can crushed tomatoes..."
2. **Suggested meals** — with readiness scores and which days they'd work best
3. **Missing ingredients** — pre-computed from readiness.json `missing` field for each recipe
4. **Expiring soon** — ingredients that should be used first

Ask the user to:
- Confirm or correct the "what's left" estimates for flagged items
- Approve/swap meals
- Note any substitutions

### Step 5: Finalize

- Update WEEK.md with the confirmed meal plan
- Add meals to Tandoor meal plan using `create_tandoor_meal_plan`
- Offer to run /grocery-list to generate the full shopping list

## Notes
- Cooking for 3-4 people
- If the user mentions a recipe URL, offer to import it to Tandoor using `create_tandoor_recipe`
- User likes to make things from scratch when possible (e.g., tortillas, bread)
- Grocy quantities are imprecise for many items (tracked as "1 = we have it"). When in doubt, ask rather than assume.
- Over time, key consumables should be updated to real counts in Grocy. The voice input system (planned) will help maintain this.
