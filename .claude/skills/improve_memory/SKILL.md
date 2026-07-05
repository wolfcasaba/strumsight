---
name: Háromrétegű Agent Memory Architektúra
description: Autonóm LLM agent memóriakezelése — semantic, episodic, contextual. RecipeWiser felhasználói preferenciák, recipe történetek, aktuális session kontextus tárolására.
trigger_keywords: ["memory", "context", "felhasználó", "preferencia", "remember", "history", "session"]
category: memory
tags: ["agent", "memory", "architecture", "context", "user-preference"]
origin: improve_memory v1
change_summary: "Első verzió — agent memory architecture a Medium/OpenClaw útmutató alapján"
---

# Háromrétegű Agent Memory Architektúra

## Mikor használd

Autonóm agent-nél, ahol:
- Felhasználóval hosszabb interakció van (pl. RecipeWiser támogatás)
- Agent-nek emlékeznie kell korábbi döntésekre, felhasználói preferenciákra
- Több session közötti continuitás szükséges

## A három réteg

### 1. Semantic Memory (hosszú távú — facts)
**Mi:** Állandó tudás, megtanult tények, felhasználói profil adatok
**RecipeWiser példa:** 
- "A felhasználó X allergénlistája: glutén, tej"
- "Y felhasználóPreference: alacsony szénhidrát"
**Archív:** user profile DB, preferenciák tárolása

### 2. Episodic Memory (közép távú — tapasztalatok)
**Mi:** Korábbi interakciók, befejezett feladatok, események sora
**RecipeWiser példa:**
- "Felhasználó Z legutóbb 3Qs csirkereceptet nézett"
- "Előzőleg lekért receptlisták időponttal"
**Archív:** session log, history, completed tasks

### 3. Contextual Memory (rövid távú — aktuális)
**Mi:** Jelenlegi conversation/session állapota
**RecipeWiser példa:**
- "Jelenlegi prompt: 'készíts heti menüt'"
- "Aktuális filter: vegetarian, max 30 perc"
**Archív:** agent kontextus buffer, jelenlegi session

## Implementáció RecipeWiser-nél

```python
# Semantic (állandó — DB-ban)
user_preferences = {
    "allergens": ["gluten", "dairy"],
    "diet": "low-carb",
    "cuisine_preference": "mediterranean"
}

# Episodic (history — session log)
recent_recipes_viewed = [
    {"recipe_id": "X", "viewed_at": "2026-04-19T10:00"},
    {"recipe_id": "Y", "viewed_at": "2026-04-19T10:15"}
]

# Contextual (current — session)
current_task = {
    "intent": "weekly_menu_plan",
    "filters": {"vegetarian": True, "max_time": 30}
}
```

## Memory retrieval stratégia

Amikor agent-nek kell válaszolni:

1. **Contextual check**: Mit csinál user épp? → aktuális session
2. **Episodic check**: Volt-e korábbi hasonló kérés? → history
3. **Semantic check**: Mik a felhasználó állandó preferenciái? → profile

## Pitfall-ok

1. **Memory overflow**: Túl sok információ a context-ben → token limit
   - Megoldás: prioritás alapú szűrés, legutóbbi 5 interakció csak
2. **Elavult adat**: Régi preferenciák visszaélése
   - Megoldás: timestamp + validity check
3. **Nincs episodic**: Agent minden session-t nulláról kezd
   - Megoldás: session_search() hívása minden új interakció előtt

## Referencia

- OpenClaw Agents.MD, Memory.MD konvenciók
- Medium: "The Architecture of Memory: How AI Agents Remember, Forget, and Learn"
- AccelData: "How Memory-Augmented Agents Enhance Large-Scale Data Environments"
- Usama Amjid: "Building Autonomous AI Agents: Memory Systems Guide"
