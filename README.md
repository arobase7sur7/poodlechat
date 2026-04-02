# poodlechat

Lightweight FiveM chat resource with:

- Local / global / staff / whisper channels
- Whisper conversations and sidebar
- Distance mode widget with voice range hooks
- Typing indicators and chat bubbles
- Emoji panel (recent + top usage)
- Optional Discord webhook forwarding

## Requirements

- FiveM server (GTA V)
- Optional: [pma-voice](https://github.com/AvarianKnight/pma-voice) for distance integration

## Installation

1. Put `poodlechat` in your `resources` directory.
2. Add to `server.cfg`:

```cfg
ensure poodlechat
```

3. Disable default chat if needed:

```cfg
# ensure chat
```

4. Configure `shared/config.lua`.

## Config Schema

`shared/config.lua` is new-schema-only.

Top-level keys:

- `settings`
- `channels`
- `messages`
- `commands`
- `routing`
- `whispers`
- `access`
- `ui`
- `emoji`
- `distance`
- `features`
- `discord`
- `runtime`

### Channels

Each channel entry supports:

- `label`
- `color`
- `order`
- `history`
- `visible`
- `cycle`
- `canSend` (`false` makes a read-only tab that can receive messages but not send plain chat input)
- `scope`
- `distance` (for proximity channels)
- `permission` (for restricted channels)

### Distance

Distance UI and cycling are driven by:

- `distance.enabled`
- `distance.default`
- `distance.pollRate`
- `distance.getCurrent`
- `distance.getLabel`
- `distance.setCurrent`
- `distance.modes` (`id`, `label`, `distance`, `color`)
- `distance.ui` (`useModeLabels`, `dynamic`)

### Typing / Bubbles

- `features.typing`
- `features.bubbles`

Typing includes:

- `headTracking`
- `offset`
- `screenLift`

### Whispers

- `whispers.tabEnabled`
- `whispers.fallbackChannel`
- `whispers.maxConversations`
- `whispers.maxMessagesPerConversation`
- `whispers.defaultConversationMode`
- `whispers.notification`
- `whispers.sidebar`

Whisper notification sound supports:

- `whispers.notification.sound`
- `whispers.notification.fallbackSound`

Default profile:

- Primary: `TENNIS_POINT_WON` / `HUD_AWARDS`
- Fallback: `SELECT` / `HUD_FRONTEND_DEFAULT_SOUNDSET`

### Access / Role Prefix

- `access.rolePrefixEnabled` defaults to `false`
- Staff/admin role label prefix is hidden unless this is explicitly enabled

## Commands (Default)

- `/global`, `/g`
- `/say`
- `/me`
- `/staff`
- `/dm`, `/whisper`, `/w`, `/msg`
- `/reply`, `/r`
- `/clear`
- `/togglechat`
- `/toggleoverhead`
- `/toggletyping`
- `/togglebubbles`
- `/report`
- `/mute`
- `/unmute`
- `/muted`
- `/nick`

## Notes

- OOC is not part of the default command set.
- Admin/staff prefix display is disabled by default.
- Distance mode count is derived safely from configured modes and player proximity state.

## Dev Notes (Exports)

Server exports:

- `exports['poodlechat']:SendChannelMessage(target, payload)`
  - `target`: player target(s). Accepts a single player id (`number`/`string`), a list of ids (`table`), or broadcast (`nil`/`-1`).
  - `payload`: message envelope table.
  - `payload.channel`: optional channel id (`'global'`, `'local'`, `'staff'`, etc.). Falls back automatically if invalid/inaccessible.
  - `payload.label`: optional author/header label used when `payload.args` is not provided.
  - `payload.text`: optional message text used when `payload.args` is not provided.
  - `payload.args`: optional explicit chat args array passed to chat template (example: `{ '[Staff] Admin', 'Message' }`).
  - `payload.color`: optional RGB table `{r, g, b}`.
  - `payload.template`: optional custom chat template string.
  - `payload.templateId`: optional UI template id.
  - `payload.multiline`: optional boolean; defaults to `true`.
  - `payload.metadata`: optional extra metadata table.
  - Returns `true` if at least one target received processing, otherwise `false`.
- `exports['poodlechat']:SendBubbleMessage(sourceId, text)`
  - `sourceId`: player id the bubble should appear above.
  - `text`: bubble text (normalized and length-limited by config).
  - Returns `true` on accepted input, otherwise `false`.

Client exports:

- `exports['poodlechat']:AddChannelMessage(payload)`
  - `payload.channel`: optional target channel id.
  - `payload.label`: optional fallback label.
  - `payload.text` / `payload.message`: optional fallback text when `payload.args` is not provided.
  - `payload.args`: optional explicit chat args array.
  - `payload.color`: optional RGB table `{r, g, b}`.
  - `payload.template`: optional custom chat template string.
  - `payload.templateId`: optional UI template id.
  - `payload.multiline`: optional boolean; defaults to `true`.
  - `payload.metadata`: optional extra metadata table.
  - Returns `(true, resolvedChannelId)`.
- `exports['poodlechat']:SetChannel(channelId)`
  - `channelId`: requested channel id to switch to.
  - Returns `(true, resolvedChannelId)`.

Behavior notes:

- `payload.channel` is optional. Unknown channel ids automatically fall back.
- If `target` cannot access the requested channel/tab, the message is sent to that target on the first allowed channel, then default channel as final fallback.
- If whisper tab is disabled, whisper-targeted messages are rerouted to whisper fallback/default channel.
- `AddChannelMessage` returns `(true, resolvedChannelId)`.
- `SetChannel` returns `(true, resolvedChannelId)` and always resolves to a valid accessible channel.
