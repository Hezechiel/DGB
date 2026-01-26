## 4. ARCHITECTURE (architecture.md)

### High‑Level Architecture
**Offline‑first, single‑player focused, no dedicated server**

```
[ Player Input ]
      ↓
[ Game Logic Layer ]
      ↓
[ Local Save (JSON) ] ←→ [ Cloud Sync (optional) ]
      ↓
[ Presentation (UI / Effects) ]
```

### Core Systems
- World Simulation System
- Gesture Recognition System
- Resource System (Faith)
- Upgrade & Progression System
- Babylon Endgame System

### Data Storage
- Local JSON save file
- Deterministic simulation where possible
- Optional cloud save (Google Play Services)

### Seasons & Leaderboards (No Dedicated Server)
- Season parameters delivered via:
  - Firebase Remote Config (or equivalent)
- Leaderboards:
  - Google Play Games Services

### Technology Stack
- Engine: Godot 4.x
- Language: GDScript
- Platform Export: Android
- Version Control: Git + GitHub
