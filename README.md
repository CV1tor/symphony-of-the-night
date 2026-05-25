# Symphony of the Fight

Symphony of the Fight is a local 1v1 rhythm combat prototype made in Godot 4.6.3. Two players take turns creating and defending short rhythmic phrases in a medieval chiptune duel.

## Current Prototype

- Local two-player battle on one keyboard.
- Static characters with placeholder UI and colors.
- Turn-based call-and-response rhythm loop.
- Mathematical hit detection; no physics or collision areas.
- Health bars, damage feedback, screen shake, and game over state.

## Gameplay Loop

1. The active player waits through a short ready countdown.
2. The attacker records up to 6 directional notes in 3 seconds.
3. The defender repeats the phrase as notes reach the hit line.
4. Perfect and good hits prevent damage.
5. Misses, omissions, and wrong valid inputs damage the defender.
6. Turns alternate until one player reaches 0 health.

## Controls

| Player | Keys |
| --- | --- |
| Player 1 | `W`, `A`, `S`, `D` |
| Player 2 | Arrow keys |
| Restart | `Enter` after game over |

Inputs from the inactive player are ignored, so pressing the other player's controls during their turn does not cause damage.

## Running Locally

Install Godot 4.6.3, then run:

```sh
godot --path .
```

For a quick headless validation:

```sh
godot --headless --path . --quit
```

## Project Structure

```text
project.godot          Godot project configuration
scenes/Battle.tscn     Main battle scene
scripts/               GDScript gameplay code
icon.svg               Temporary project icon
AGENTS.md              Project context and contributor notes
```

## Development Notes

The MVP intentionally avoids character movement, online multiplayer, items, enemy AI, and complex menus. The current focus is timing feel, turn flow, and clear feedback before adding final art, audio, and polish.
