# Riddle — an enchanted diary for iPad

A native iPadOS/iOS reimagining of [rossman22590/riddle](https://github.com/rossman22590/riddle)
— *the diary of Tom Riddle*, originally for the reMarkable Paper Pro.

You write on the page with your Apple Pencil or a fingertip. After a pause, the diary
**drinks your ink** — your words soak into the paper — the page thinks for a moment, and an
answer writes itself back in a flowing hand, stroke by stroke, then fades away.

No screen glow, no keyboard, no chat UI. Just ink appearing on paper — a clean e-ink–style
page (soft paper-white, near-black ink), the diary's replies penned in **Dancing Script**.

## How it works

| Piece | Technology |
|------|------------|
| Writing surface | **PencilKit** (`PKCanvasView`, any input — Pencil, finger, trackpad) |
| "Drinking the ink" | The committed page soaks into the paper (fade + blur + downward drift) |
| Reading your words | A **vision model reads the committed page** — the ink is sent as an inline PNG, exactly like the original |
| The diary's voice | **OpenRouter only** (OpenAI-compatible chat completions, streamed) with the original Tom Riddle persona |
| The reply appearing | Custom SwiftUI **`TextRenderer`** penning each glyph with a glowing nib + wet-ink bloom, then it fades |
| The diary's hand | **Dancing Script** (bundled, OFL), registered at runtime via `CTFontManager` |
| No chrome | The guide — and Settings / the diary's memory — is summoned by a **two-finger tap** |

The API key is stored in the **Keychain**; the ink image is sent only to `openrouter.ai`.

## Requirements

- Xcode 16 or later (built/tested with Xcode 26.5)
- iOS / iPadOS 18.0+ (uses the `TextRenderer` API)

## Build & run

```sh
open Riddle.xcodeproj      # then ⌘R on an iPad simulator or device

# or from the command line:
xcodebuild -project Riddle.xcodeproj -scheme Riddle \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
```

## Giving the diary its voice

1. Get a key at <https://openrouter.ai/keys>.
2. In the app, **tap the page with two fingers** to open the guide → *The ink & the voice*.
3. Paste the key, and pick a **vision-capable** model. The default is `openai/gpt-4o-mini`
   (matching the original); the diary *reads your handwriting*, so the model must accept images.

Until a key is set the diary sleeps — writing to it opens the guide so you can wake it.

## Matching the original

| Trait | Original (reMarkable) | This app |
|---|---|---|
| Reply font | Dancing Script | Dancing Script (bundled) |
| Page / ink | e-ink white, black ink | paper-white, near-black ink |
| Reads handwriting via | vision LLM on committed PNG | vision LLM on committed PNG (OpenRouter) |
| Default model | `gpt-4o-mini` | `openai/gpt-4o-mini` |
| Persona | `riddle/src/oracle.rs` | identical prompt |
| Pause before drinking | 2.8 s | 2.8 s |
| Ink-drink / reply-fade | ~0.98 s / 0.8 s | ~0.98 s / 0.8 s |
| Reply linger | 4 s + 2 ms/char (cap 20 s) | 4 s + 2 ms/char (cap 20 s) |
| Guide gesture | draw a large "?" | two-finger tap (drawn "?" on e-ink) |

Platform-inherent differences: the original drives the reMarkable e-ink engine directly for a
takeover experience (root, no vendor UI); this is a sandboxed iOS app rendering the same
experience with SwiftUI + Core Animation.

## Project layout

```
Riddle/
  App/         RiddleApp, ContentView
  Models/      AppSettings, DiaryEntry, DiaryStore
  Services/    Keychain, Oracle (persona), OpenRouterOracle (vision)
  Views/       DiaryView, InkCanvasView (PencilKit),
               HandwritingText (TextRenderer reveal),
               GuideView, SettingsView, OnboardingView, HistoryView
  Support/     Theme, PaperBackground, FontRegistrar
  Fonts/       DancingScript.ttf, OFL.txt
```

## Credits

The diary's hand is **[Dancing Script](https://github.com/googlefonts/DancingScript)** by
Pablo Impallari (SIL Open Font License 1.1 — see `Riddle/Fonts/OFL.txt`), the same font the
original uses.
