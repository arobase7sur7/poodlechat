# PoodleChat

PoodleChat is a polished FiveM chat resource built for QBCore servers. It replaces the stock chat with a responsive React NUI, rich formatting, channel tabs, whispers, radio chat, reports, and a focused Personal Settings panel for each player.

The shipped interface is intentionally player-facing: chat controls, appearance, nickname management, and tab organization. Server-side configuration stays in code/configuration instead of an exposed admin console.

## Highlights

- Compact in-game chat with channel tabs, grouping, notifications, fade behavior, autoscroll control, and context menus.
- Rich rendering for FiveM colors, multiple `^#hex` colors, formatting codes, emojis, mentions, prefixes, raw copy, and message previews.
- Character-specific nicknames with per-character history and up to 5 pinned quick switches.
- Session-aware RP/OOC history that survives character selection, character switching, and `/relog` until the player fully disconnects.
- Character-specific DM and radio history.
- Player reports that can target players, yourself, system messages, or broken messages with raw and rendered context.
- Personal Settings for font, opacity, sound, bubbles, typing indicators, overhead chat, autoscroll, deleted-message visibility, and tab grouping.

## Requirements

- FiveM artifact with NUI support.
- QBCore is optional but recommended for character identity and character-specific nickname/history behavior.
- `pma-voice` is optional for voice range labels.
- Node.js is only needed when rebuilding the React NUI.

## Installation

1. Put `poodlechat` in your server `resources` folder.
2. Add the resource to `server.cfg`:

```cfg
ensure poodlechat
```

3. Disable the default chat resource if you do not want both chats running:

```cfg
# ensure chat
```

4. Review [shared/config.lua](shared/config.lua). Production servers should check channels, permissions, report settings, Discord webhooks, and command behavior.

## Building The NUI

The React UI lives in `web/` and builds into `html/`.

```powershell
npm install
npm run lint
npm run build
```

FiveM loads:

```lua
ui_page "html/index.html"
```

Run `npm run build` after frontend changes.

## Opening Settings

Players can open Personal Settings from the chat toolbar or with:

```text
/chatmanager
```

The settings panel includes profile/nickname tools, appearance controls, behavior toggles, and tab grouping. It does not expose an admin console.

## Persistence Model

PoodleChat separates player-session data from QBCore character data.

Session-based data lasts until the player fully disconnects:

- RP/OOC style channel history, including `local` and `global`.
- Join/history messages shown during the same connected session.

Character-based data changes when the active QBCore character changes:

- DM history.
- Radio history.
- Nickname.
- Nickname history.
- Pinned nicknames.

`/relog` and character switching should not wipe RP/OOC session chat, but they should switch character-specific private data.

## Formatting

Supported chat formatting includes:

- FiveM colors: `^1` through `^9`.
- Hex colors: `^#68d8a7`, including multiple hex colors in one message.
- Reset: `^r`.
- Bold, italic, underline, strike, and combined formatting.
- Emojis, mentions, prefixes, and system messages.

The input preview shows default FiveM colors and the last 10 hex colors actually used in sent messages.

## Reports

Reports can target players, yourself, system messages, or broken/bugged messages. When context is available, report payloads include:

- Reporter name, server ID, and Discord ID.
- Target name, server ID, and Discord ID.
- Raw message and rendered message.
- Reason, channel, timestamp, message ID, and metadata.

Discord report delivery can be configured in [shared/config.lua](shared/config.lua).

## Permissions

Baseline permissions still work through ACE:

```cfg
add_ace group.admin chat.manager allow
add_ace group.admin chat.staffChannel allow
add_ace group.admin chat.deleteMessage allow
add_ace group.admin chat.noMute allow
```

Those permissions are still useful for server-side checks and privileged chat behavior, even though the NUI no longer ships an admin console.

## Runtime Storage

Client preferences use client KVP for local UI settings such as opacity, font, sound volume, hidden tabs, notification toggles, and emoji usage.

Server/runtime data uses server KVP where applicable:

- `poodlechat:runtimeConfig:v1`
- `poodlechat:runtimeAcl:v1`
- `poodlechat:commandRegistry:v1`
- `poodlechat:commandBlocks:v1`
- `poodlechat:commandRoutes:v1`
- `poodlechat:customCommands:v1`
- `poodlechat:autoMessages:v1`
- `poodlechat:auditLog:v1`
- `poodlechat:reports:v1`

## External Integration

Existing compatibility events and exports are preserved:

```lua
exports['poodlechat']:SendChannelMessage(target, {
  channel = 'global',
  label = 'System',
  args = {'System', 'Hello from another resource'}
})

exports['poodlechat']:SendBubbleMessage(source, 'Overhead text')
```

Supported compatibility events include:

- `chat:addMessage`
- `chat:addSuggestion`
- `chat:addSuggestions`
- `chat:removeSuggestion`
- `chat:clear`
- `_chat:messageEntered`

## Validation

Recommended checks after changes:

```powershell
npm run lint
npm run build
```

Lua syntax should also be checked in your FiveM environment or with a local Lua/Luacheck setup if available. Node is not required at runtime after the NUI has been built.

## Notes

FiveM does not provide a reliable universal command unregister API. Disabled or renamed runtime commands may remain inert until resource restart, depending on how they were registered. PoodleChat still blocks and routes commands typed through its own NUI input before executing them.
