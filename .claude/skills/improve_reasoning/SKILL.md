---
name: ReAct Chain-of-Thought Agent Pattern
description: Komplex autonóm feladatokhoz — Thought/Action/Observation lépések interleaved végrehajtása. LLM-re épül, külső tool-okat használ. RecipeWiser social media, recipe elemzés, felhasználó interakció kezelésére ideális.
trigger_keywords: ["react", "chain-of-thought", "agent", "autonomous", "komplex feladat", "több lépés", "reasoning"]
category: reasoning
tags: ["prompting", "agent", "reasoning", "tool-use"]
origin: improve_reasoning v1
change_summary: "Első verzió — ReAct pattern dokumentálva promptingguide.ai/alapján"
---

# ReAct Chain-of-Thought Agent Pattern

## Mikor használd

Komplex, több-lépéses feladatokhoz ahol:
- LLM-nek külső információra van szüksége (web search, file olvasás, API hívás)
- Egyszerű CoT nem elég, mert a modell "hallucinálhat" fakta hibákat
- Tool-okat kell sorrendben hívni, eredményt feldolgozni, majd döntést hozni

Példa RecipeWiser használat:
1. Recipe-ről készíts Instagram posztot → Thought: elemezd a receptét, Action: mcp_recipewiser_get_recipes, Observation: kinyert adatok
2. Felhasználónak üzenetet válaszolsz → Thought: mi a kérdés lényege, Action: memory/search, Observation: kontextus

## Hogyan működik (Thought → Action → Observation)

```
Thought 1: Elemzem a kérdést — mit kell tudnom ahhoz, hogy válaszoljak?
Action 1: [Tool neve][tool input]
Observation 1: [Tool visszatérési értéke]
Thought 2: A kapott információ alapján mit kell tennem?
Action 2: [Következő tool vagy Finish]
Observation 2: ...
...
Thought N: Most már van elegendő információm — megválaszolom.
Finish[final answer]
```

## Prompt template

Külső forrásból (pl. web search) információt igénylő feladatokhoz:

```
Következő feladatot hajtsd végre ReAct (Reasoning + Acting) mintával.
Minden lépésnél: Thought → Action → Observation formátumot kövess.

Feladat: [USER QUERY]

Kezdj a Thought 1-gyel!
```

## ReAct + CoT kombináció (legjobb gyakorlat)

A Yao et al. 2022 paper eredményei alapján:
- **ReAct önmagában**: interleaved reasoning + acting, de nem elég a belső tudatra
- **CoT önmagában**: erős reasoning, de hallucinálhat fakta hibákat
- **ReAct + CoT együtt**: a legjobb — belső tudás + külső információ kombinációja

RecipeWiser contextben: 
→ CoT: "A felhasználó egy mediterrán vacsorareceptet keres,忌澱粉"
→ ReAct: search_recipes(mediterranean, no-gluten) → observation → refine

## Pitfall-ok

1. **Non-informative search results**: Ha a keresés nem ad vissza releváns eredményt, a modell "eltéved" — mindig legyen fallback
2. **Thought-ok túl rövidek**: A gondolatmenetnek elég részletesnek kell lennie, különben rossz action-t választ
3. **Túl sok lépés**: Max 5-7 thought-action-observation — utána "Finish"-elni kell

## Referencia

- Paper: Yao et al. 2022 — "ReAct: Synergizing Reasoning and Acting in Language Models" (arXiv:2210.03629)
- Gyakorlati útmutató: https://www.promptingguide.ai/techniques/react
- LangChain implementáció: `initialize_agent(tools, llm, agent="zero-shot-react-description")`
