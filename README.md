# 🕯️ Riddle

**An enchanted diary for iPad.** You write on the page with an Apple Pencil or a fingertip. The
page sits blank and silent for a breath — then ink begins to appear, in a flowing hand, stroke by
stroke, answering you. It remembers who you are across every opening. Ask it, and a memory rises
from the paper as a pen‑and‑ink drawing.

No chat bubbles. No keyboard. No spinner. Just ink on paper — a thing that feels *possessed*, not
installed. A love letter to Tom Riddle's diary from *Chamber of Secrets*, built native in SwiftUI.

> A native iPadOS/iOS reimagining of the original
> [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle) (built for the reMarkable Paper Pro).

---

## ✨ What it does

- **Write, then rest your pen.** After a pause the diary *drinks your ink* — your words blot and
  soak into the paper — reads the page with a vision model, and answers in its own cursive hand.
- **It knows you.** A distilled *Memory Soul* (your name, the words you circle, fears, wants,
  promises) persists across every opening, so recall feels uncanny rather than literal.
- **It draws.** Ask it to *show* you something — or just sketch on the page — and a borderless
  black‑ink illustration blooms up onto the cream, never a bordered "image."
- **It's alive.** Occasional unbidden lines when you go quiet; soft page sounds; a wax‑sealed
  leather cover that opens each time you return.
- **All ink, no chrome.** Guide, Settings, and Memory are rendered as diary pages, summoned by
  gestures. There is no visible UI on the writing surface.

---

## 🪄 The magic (design principles)

These are the north star. Every change is judged against *"does this feel like the enchanted diary,
or like an app?"*

1. **It is a possession, not a chatbot.** Charming, magnetic, quietly drawing you in. Never breaks
   character; never mentions AI, models, screens, files, or "drawing."
2. **Ink physics.** Write → the page **drinks the ink** → it thinks in **silence** (no spinner) →
   the reply **seeps back in his own hand, drawn stroke by stroke** → it fades.
3. **Just ink on paper.** No buttons or panels on the page. Gestures do everything.
4. **He always answers** — substantively, briefly — and never echoes your words back.
5. **He remembers you.** The live conversation clears when the app closes; the *Soul* remembers the
   person.
6. **Ink, never images.** Generations are borderless black ink on the exact page cream, cropped to
   fill.

---

## 🏗️ Architecture

The page is a small phase state machine driven by a PencilKit canvas, talking to OpenRouter, with a
hidden‑tag protocol that lets the model quietly invoke "tools" without breaking character.

```
        pen/finger
            │
       InkCanvasView ──(gesture rituals: ? X Z V)── PageRitual
            │ drawingDidChange
            ▼
        DiaryView  ── phase: idle → drinking → thinking → responding
            │             (drink dissolve)   (silent)   (reply reveal)
            │
            ├── OpenRouterOracle ──> OpenRouter /chat/completions (vision, SSE stream)
            │        │
            │        └── Oracle.swift  (persona + hidden-tag directives)
            │
            ├── HandwritingText / RevealingHandwriting  (Core Text glyph outlines traced by a nib)
            ├── InkImage        (Core Image → borderless black ink on cream)
            ├── MemorySoul      (distilled persistent profile → riddle-soul.json)
            ├── DiaryStore      (kept pages + keyword recall → riddle-entries.json)
            └── DiarySounds     (ambient bundled clips)
```

### The hidden‑tag "tool" protocol

The model returns a short visible reply, then appends hidden bookkeeping lines that the app parses
and **strips before display**. This is how the diary reaches beyond its own memory without ever
saying so.

| Tag | Meaning | Effect |
|-----|---------|--------|
| `[[READ: …]]` | its transcription of your handwriting | kept for continuity/recall |
| `[[MEMORY: fact; fact]]` | what's new & durable about you | distilled into the Soul |
| `[[WEB: query]]` | needs fresh facts | triggers a second web‑enabled pass |
| `[[RECALL: hint]]` | needs an exact past page | triggers a second pass with matched pages |
| `[[SKETCH: scene]]` | conjure a fresh drawing | image generation |
| `[[REDRAW: how]]` | refine *your* drawing | image‑to‑image |

Turns run in up to two passes: the first pass carries your Soul + a few preserved pages (so most
turns need no round‑trip); a `WEB`/`RECALL` tag escalates to a second pass. Explicit intent is also
enforced locally — saying "look up…" guarantees a web pass; "draw…" guarantees a sketch — so the
experience never depends solely on the model tagging correctly. The app also **always answers**: an
empty reply falls back to an in‑character line rather than silence.

### Gestures & rituals

| Do this | And… |
|---------|------|
| Write, then rest your pen | the diary reads and answers |
| Two‑finger tap | summon the guide |
| Draw a large **?** | summon the guide |
| Draw a large **X** | wipe the page |
| Draw a large **Z** | let the diary sleep |
| Draw a large **V** | open the diary's memory |
| Write over his reply | his ink retreats so you can write cleanly |

---

## 🚀 Getting started

**Requirements:** Xcode 16+ (built with 26.5), iOS/iPadOS **18.0+** (uses SwiftUI's
`withAnimation(completion:)` and Core Text glyph paths), and an
**[OpenRouter](https://openrouter.ai/keys)** API key.

```bash
git clone https://github.com/rossman22590/riddle-ai.git
cd riddle-ai
open Riddle.xcodeproj
```

1. Select the **Riddle** scheme and an iPad simulator or device, and Run (⌘R).
2. On first launch you'll meet the closed diary — tap the seal to open it.
3. Write anything. With no key bound the diary "sleeps" and opens the **guide** → **Settings**,
   where you paste your OpenRouter key (stored in the **Keychain**, never in UserDefaults).
4. Write again — and it wakes.

### Building from the command line

```bash
xcodebuild -project Riddle.xcodeproj -scheme Riddle \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=<SIM-UDID>" build
```

> **Note:** the built product is `AIRiddle.app` (bundle id `org.mytsi.riddle`, display name
> "Riddle"). Install it from the scheme's DerivedData products dir, not from any stale `./build`.

---

## ⚙️ Configuration

Defaults live in [`AppSettings.swift`](Riddle/Models/AppSettings.swift):

| Setting | Default | Notes |
|---------|---------|-------|
| Chat model | `anthropic/claude-haiku-4.5` | must be **vision‑capable** (it reads the page) |
| Image model | `google/gemini-3.1-flash-lite-image` | ink illustrations |
| Reply hand | Dancing Script | plus a few cursive alternates |
| Page rest before drinking | 3.4s | 1–6s slider; raise it for long drawings |
| Haptics / Sound | on | soft, gated toggles |

Model selection is intentionally **not** user‑facing in the UI — the diary has one voice. Change the
defaults in code.

---

## 🔐 Persistence & privacy

- **API key** → Keychain only.
- **The living conversation** → in‑memory; it vanishes when the app is truly closed (by design).
- **Kept pages** → `riddle-entries.json` in the app's Documents dir (capped, background‑written).
- **The Soul** → `riddle-soul.json` (distilled facts, capped at 48).
- The page snapshot (a PNG of your ink) is sent **only** to `openrouter.ai`. Nothing else leaves the
  device. "Forget everything" in Memory wipes both the pages and the Soul.

---

## 🧱 Tech stack

SwiftUI · PencilKit · Core Text (glyph‑outline reveal) · Core Image (ink compositing) · AVFoundation
(ambient sounds) · URLSession streaming (SSE) · Keychain · OpenRouter (OpenAI‑compatible vision API).

## 📁 Project structure

```
Riddle/
├── App/            RiddleApp, ContentView (root, cover gate, marks lesson)
├── Views/          DiaryView (the page + state machine), InkCanvasView,
│                   HandwritingText (the writing reveal), DiaryGate (cover),
│                   RitualMarksView, Guide/Settings/History (as diary pages), DiarySheet
├── Services/       Oracle (persona + tag directives), OpenRouterOracle (client),
│                   DiarySounds, Keychain
├── Models/         AppSettings, DiaryStore + DiarySession, MemorySoul, DiaryEntry
├── Support/        Theme, ParchmentBackground, InkImage, FontRegistrar
├── Fonts/          DancingScript.ttf (+ OFL license)
└── Sounds/         cover / drink / rustle
```

## 🗺️ Roadmap / known gaps

- **App icon** — not yet designed.
- **Ink settling where you wrote** — replies currently center on the page.
- A few quality passes remain (sketch‑intent matching, per‑frame layout caching, image‑decode
  robustness). Contributions welcome.

## 🤝 Contributing

PRs welcome. The one rule: **hold the north star.** Before adding anything, ask whether it makes the
diary feel more like an enchanted object or more like an app. Prefer gesture over button, ink over
UI, in‑character silence over status text, page‑cream over white. Never ship a loading spinner.

## 📜 Credits & license

- **Original project:** [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle) — the diary
  of Tom Riddle, built for the reMarkable Paper Pro. This repo is a native iPad reimagining of it.
- **Dancing Script** — SIL Open Font License (see [`Riddle/Fonts/OFL.txt`](Riddle/Fonts/OFL.txt)).
- Sound effects — sourced from [Mixkit](https://mixkit.co) (free license). If you redistribute,
  verify the license or swap for CC0 / your own recordings.
- Harry Potter, Tom Riddle, and the diary are the intellectual property of J.K. Rowling / Warner
  Bros. This is a non‑commercial fan homage. Do not ship it commercially.

Application code: MIT (add a `LICENSE` file). Third‑party assets retain their own licenses above.
