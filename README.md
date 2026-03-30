# PoodleChat (Updated)

PoodleChat is a modernized FiveM chat resource focused on clean UI, strong performance, and maintainable structure.
This fork keeps behavior compatibility with the current script while cleaning architecture, removing legacy paths, and centralizing configuration.

## Modernization Highlights

- Modernized chat UI with a cleaner layout and improved usability.
- Improved overall performance through reduced redundant work and optimized update loops.
- New emoji system with categorized browsing, recent/most used usage tracking, and faster incremental rendering.
- Distance-aware voice UI with built-in PMA Voice support and generic custom integration hooks.
- Typing indicator system with player-facing toggle support (when allowed).
- Chat bubble visual system with player-facing toggle support (when allowed).
- RDR3/RedM support removed and codebase cleaned for GTA V/FiveM only.
- `discord_rest` integration removed and replaced with optional Discord webhooks.
- Fully centralized configuration in `shared/config.lua`.

## What Changed vs Older poodlechat

This fork differs from older upstream variants in several key ways:

- UI has been redesigned and modernized.
- Runtime logic is split into dedicated client/server/UI modules for maintainability.
- Emoji handling now supports category browsing and optimized panel updates.
- Distance widget and voice-range visualization support PMA Voice directly and allow custom distance getters/setters.
- Typing and bubble systems include both server-side config controls and client-side in-game toggles.
- Legacy RedM/RDR3 and legacy Discord bridge paths were removed.

## Requirements

- FiveM server (GTA V) (How you would run the script if not anyway lol)
- Optional: [pma-voice](https://github.com/AvarianKnight/pma-voice) for automatic voice range integration

## Installation

1. Place the resource in your `resources` folder.
2. Ensure it in `server.cfg`:

```cfg
ensure poodlechat
```

3. Delete this line in `server.cfg`: (if not, you will have 2 chat in game) 

```cfg
ensure chat
```

3. Configure `shared/config.lua`.
4. If using staff/role permissions, configure ACE rules in `server.cfg`.

## Configuration

All configuration is in:

- `shared/config.lua`

Main sections:

- `Config.Chat`
- `Config.Access`
- `Config.UI`
- `Config.Emoji`
- `Config.Distance`
- `Config.Discord`
- `Config.TypingIndicator`
- `Config.ChatBubbles`
- `Config.Runtime`

### Typing and Bubble Toggles

- Global enable/disable:
  - `Config.TypingIndicator.enabled`
  - `Config.ChatBubbles.enabled`
- Player in-game toggle permission:
  - `Config.TypingIndicator.allowPlayerToggle`
  - `Config.ChatBubbles.allowPlayerToggle`

When toggles are allowed, players can use:

- `/toggletyping`
- `/togglebubbles`

### Distance / Voice Integration

Distance support is controlled by `Config.Distance`:

- `getDistance`
- `getLabel`
- `setDistance`
- `ranges`
- `ui`

Default PMA Voice integration is included. You can replace these hooks with your own voice system logic.

### Discord Webhooks

Discord integration is optional and webhook-based through `Config.Discord`.

- `enabled` controls the whole integration.
- `webhook` is the full webhook URL.
- `sendLocal`, `sendGlobal`, `sendStaff`, `sendAction`, `sendJoinLeave`, `sendReports` control per-channel forwarding.


## Commands

- `/clear`
- `/global [message]`
- `/g [message]`
- `/say [message]`
- `/me [action]`
- `/staff [message]`
- `/whisper [player] [message]`
- `/w [player] [message]`
- `/reply [message]`
- `/r [message]`
- `/mute [player]`
- `/unmute [player]`
- `/muted`
- `/report [player] [reason]`
- `/nick [nickname]`
- `/togglechat`
- `/toggleoverhead`
- `/toggletyping` (if allowed)
- `/togglebubbles` (if allowed)

## Notes

- This resource is GTA V only now (`games { "gta5" }`), it will probably not work on RDR3 and will never be updated for.