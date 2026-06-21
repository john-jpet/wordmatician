# Wordamatician

A fast-paced mobile word game built in Godot 4. Find words on a 5×5 letter grid before the clock runs out. Longer words, power-ups, and combo streaks push your score higher.

## Gameplay

- Tap letters on the grid to spell a word, then submit it
- Each word found adds time back to the clock
- Tiles refill from above after a word is cleared
- Letters are weighted by English frequency — common letters appear more often

### Scoring

| Factor | Effect |
|---|---|
| Word length | Exponential — longer words score far more |
| Length bonus | Triggered on words over 4 letters |
| Combo streak | Each consecutive valid word multiplies the score |
| Multiplier tiles | x2 / x3 tiles in the word apply to the full word score |
| Bomb tiles | Explode in a 3×3 area; chain reactions score bonus points |

### Power-up tiles

| Tile | Effect |
|---|---|
| **x2 / x3** | Multiplies the score for any word containing it |
| **Bomb** | Destroys surrounding tiles and scores bonus points; bombs caught in blasts chain-explode |
| **Wild ★** | Matches any letter; only one can be on the board at a time |

## Game Modes

**Classic** — 60-second timer, unlimited words, score as high as possible.

**Daily Puzzle** — A fixed 5×5 grid generated from today's date. Clear all tiles to win. One attempt per day; the same puzzle is shared by all players.

## Features

- Persistent stats across sessions: high score, total words found, longest word ever, daily puzzles cleared, games played
- Loading screen with gameplay tips between scene transitions
- Home button on all screens for quick navigation

## Project Structure

```
Scenes/          .tscn scene files
Scripts/         GDScript source files
  main.gd        Classic mode logic
  daily.gd       Daily puzzle logic
  intro.gd       Home screen + stats panel
  game_over.gd   End-of-game overlay
  loading_screen.gd  Autoload — handles scene transitions
  stats_manager.gd   Autoload — persistent stat tracking
Assets/          Fonts, textures, word list
```

Save data is written to `user://` (platform-specific app storage) and never bundled into the build:
- `user://stats.json` — lifetime stats
- `user://daily_save.json` — daily puzzle completion date

## Building

Requires **Godot 4.5** with export templates installed.

### Android APK (sideload / testing)

1. Install Android Studio and ensure the SDK + NDK are available
2. In Godot: **Editor → Editor Settings → Export → Android** — set the SDK path
3. **Project → Export → Android** — configure a debug keystore
4. Export as `.apk` and sideload to your device (requires "Install unknown apps" enabled)

### Android AAB (Play Store)

Same as above but export as `.aab` using a release keystore. Upload to Google Play Console.

### Web (itch.io / browser)

**Project → Export → Web** — produces an `index.html` + supporting files. Upload the folder to [itch.io](https://itch.io) as a web game. Persistent storage works via browser IndexedDB over HTTPS (itch.io provides this automatically).

### iOS

Requires a Mac with Xcode. Export from Godot produces an Xcode project; open it on a Mac, sign with an Apple Developer certificate, and build from there. Distribute via TestFlight or the App Store.

## Tech

- **Engine:** Godot 4.5
- **Language:** GDScript
- **Target:** Mobile portrait (720×1280)
- **Word list:** Bundled at `Assets/words.txt`
