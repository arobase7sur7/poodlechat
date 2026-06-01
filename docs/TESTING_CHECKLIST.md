# PoodleChat Testing Guide

Use this as the manual QA checklist for the current overhaul/refactor.

## Test Setup

- [o] Start the server with `poodlechat` ensured.
- [o] If applicable, also start `qb-core`, `pma-voice`, and the radio resource used by your server.
- [o] Prepare at least:
  - [o] Player A with two QBCore characters
  - [o] Player B with one QBCore character
  - [/] Player C with staff permissions if staff-channel testing is needed 
  Player A and B are admin already, and don't have a player C available
- [o] Make sure Player A can relog, switch character, disconnect, reconnect, and restart the resource during tests.
- [o] Clear old assumptions before testing:
  - [o] Note whether existing KVP/chat history data already exists
  - [o] Note whether old nicknames already exist
  - [o] Note whether old whisper conversations already exist

## Smoke Test

- [o] `ensure poodlechat` starts without obvious console errors.
- [x] Opening chat shows the new UI without broken layout.
The layout work but, I asked for a UI rework and it look like the same as before, look at the implementation plan and the chat md file for that
Also now there is a black background, check on web as fivem have some behavior with background, not the same as classic html / css
- [o] Typing works.
It works but didn't got visual updated too
- [o] Sending a normal message works.
it work but now instead of being blue, its always pink, it don't show with the range color in chat 
- [o] Closing and reopening chat works.
- [o] No duplicated messages appear after initial load.

## UI And Layout

- [o] Main chat container renders correctly on a normal desktop resolution.
- [/] Main chat container remains readable over bright and dark in-game backgrounds.
Bc of the black background, can't test it
- [x] Tabs are visible, clickable, and styled correctly.
clickable, visible yes but styled not as what I asked
- [ ] Active tab state is visually obvious.
- [ ] Hover states look correct.
- [ ] Toolbar buttons render correctly.
- [ ] Input bar is aligned and readable.
- [ ] Scrollbars are visible and usable.
- [ ] Emoji panel opens and closes correctly.
- [ ] Whisper sidebar/thread layout is visually correct.
- [ ] No UI elements overlap or clip badly when many tabs/messages exist.

## Opacity Setting

- [ ] Open the tab/settings panel and confirm the opacity slider exists.
- [ ] Move slider to minimum allowed value and verify chat stays visible.
- [ ] Move slider to maximum allowed value and verify chat never becomes fully opaque.
- [ ] Close and reopen chat; opacity stays applied.
- [ ] Restart only `poodlechat`; opacity persists.
- [ ] Disconnect/reconnect on the same install; opacity persists.
- [ ] Switching character does not change opacity.

## Channel Basics

- [ ] `local`, `global`, `whispers`, and any enabled custom channels are visible as expected.
- [ ] Staff channel only appears for players with access.
- [ ] Messages route to the correct tab.
- [ ] If a target tab is unavailable, fallback behavior still lands messages somewhere sensible.
- [ ] Tab cycling still works with the current grouping configuration.
- [ ] Hidden/grouped tab behavior still works after reopening chat.

## Tab Grouping And Settings

- [ ] Open grouping/settings panel.
- [ ] Change a channel's group target.
- [ ] Verify grouped channel messages appear in the selected tab.
- [ ] Verify pinned tabs cannot be hidden incorrectly.
- [ ] Verify hidden tabs stay hidden after reopening chat.
- [ ] Verify tab grouping persists across reconnect.
- [ ] Verify tab grouping persists across resource restart.
- [ ] Verify grouping changes do not break whisper or radio special behavior.

## Name Resolution And `/nick`

- [ ] Set `/nick` on Player A.
- [ ] Local messages show `/nick`, not raw QBCore name.
- [ ] Global messages show `/nick`.
- [ ] Whispers sent by A show `/nick`.
- [ ] Whispers received from A show `/nick`.
- [ ] `/me` or action-style messages show `/nick`.
- [ ] Join/leave lines use the correct name behavior.
- [ ] If Discord logging is enabled on your server, webhook names match expected display name priority.
- [ ] Remove `/nick`; fallback name is correct again.

## Whisper System

- [ ] Start a whisper from the sidebar/player picker if enabled.
- [ ] Start a whisper manually by player ID if manual mode is used.
- [ ] Send a whisper from A to B.
- [ ] Send a whisper reply from B to A.
- [ ] Whisper thread opens/updates correctly.
- [ ] Outgoing whisper line is styled correctly.
- [ ] Incoming whisper line is styled correctly.
- [ ] Reply target updates correctly.
- [ ] Unread indicator appears when a whisper arrives in the background.
- [ ] Opening the whisper clears unread state.
- [ ] Closing/deleting a whisper conversation removes it from the UI.
- [ ] Deleted conversation does not reappear after reopening chat unless a new message arrives.

## Per-Character History

- [ ] On Character A1, send messages in all persisted channels that matter for your server.
- [ ] Create at least one whisper conversation on Character A1.
- [ ] Switch Player A to Character A2.
- [ ] Character A2 does not see A1's persisted conversations/history.
- [ ] Send new messages as A2; they stay isolated to A2.
- [ ] Switch back to Character A1.
- [ ] A1 history is restored correctly.
- [ ] Restored messages look visually distinct.
- [ ] Restored whisper threads reopen correctly and keep correct peer identity.
- [ ] Persisted history order is correct from oldest to newest.
- [ ] History limit per conversation/channel is respected once exceeded.
- [ ] Corrupted or empty history does not hard-break the UI if you simulate missing data.

## Offline Whisper Delivery

- [ ] Disconnect Player B.
- [ ] From A, send a whisper to B using the valid target identity path your server uses.
- [ ] Sender gets confirmation that the message will be delivered later.
- [ ] Reconnect Player B on the same character.
- [ ] Offline whisper is delivered automatically after character load.
- [ ] Delivered message appears in the correct conversation.
- [ ] Delivered message has offline styling/tag.
- [ ] If B reconnects on a different character, the old character's offline message is not delivered to the wrong character.
- [ ] If B later reconnects on the original character, the message delivers there.
- [ ] After delivery, reconnect again and confirm the same offline message is not delivered twice.

## Character Switching Safety

- [ ] Switch characters slowly and confirm history restores correctly.
- [ ] Switch characters quickly and confirm no crash, duplicate, or mixed history.
- [ ] While A is on Character A2, send whispers intended for A1 and confirm they do not appear live on A2.
- [ ] Switch back to A1 and confirm stored messages are present.
- [ ] UI state such as opacity and tab grouping survives character switch.

## Loading Queue And Early Routing

- [ ] Restart `poodlechat` while players are online.
- [ ] Send messages very early during client/UI load.
- [ ] Confirm early messages do not all collapse into Global incorrectly.
- [ ] Confirm early queued messages flush once UI is ready.
- [ ] Confirm restored history is not wiped by late queue flushes.
- [ ] Confirm no duplicate messages appear after load completes.

## Local Range And Distance Color

- [ ] With `pma-voice` running, test all supported voice ranges.
- [ ] At close range, local message color uses the near-range end of the configured gradient.
- [ ] At mid range, color shifts appropriately.
- [ ] Near edge of sender range, color shifts toward the far-range end.
- [ ] Two players on different personal voice modes still see color based on sender-to-receiver distance, not just receiver mode.
- [ ] Message visibility range matches actual expected local chat range.
- [ ] Bubble/typing/range visuals still work if enabled.
- [ ] If `pma-voice` is unavailable, fallback behavior still works without script breakage.

## Hex Colors And Color Picker

- [ ] Type a message containing `^#FF5733`.
- [ ] Type a message containing `^#F53`.
- [ ] Confirm the input shows the color chip/swatch helper.
- [ ] Click the swatch and confirm the custom picker opens.
- [ ] Adjust Hue slider and see the active hex update.
- [ ] Adjust Saturation slider and see the active hex update.
- [ ] Adjust Lightness slider and see the active hex update.
- [ ] Edit the hex field directly and see the message color update.
- [ ] Send the message and confirm final rendered chat color matches the chosen hex.
- [ ] Legacy `^0` to `^9` colors still work.
- [ ] Mixed legacy and hex color codes do not break rendering.

## Line Break Support

- [ ] Send a message containing one `\n`.
- [ ] Confirm one line break renders.
- [ ] Send a message containing three `\n`.
- [ ] Confirm exactly three line breaks render.
- [ ] Send a message containing more than three `\n`.
- [ ] Confirm extra line breaks are ignored silently.
- [ ] Confirm line breaks do not break whisper threads or other channels.

## Emoji Panel

- [ ] Open emoji panel.
- [ ] Search for an emoji.
- [ ] Insert an emoji into the input.
- [ ] Recently used emojis update correctly.
- [ ] Top/recent sections load correctly.
- [ ] Emoji panel styling is intact.
- [ ] Emoji insertion does not break color codes or line-break text.

## Notifications And Sounds

- [ ] Whisper notification sound plays when enabled.
- [ ] Whisper notification sound does not play when muted/disabled.
- [ ] Per-tab sound toggles still behave correctly.
- [ ] Background unread dots update correctly.
- [ ] No sound plays for the wrong channel.

## Action / Bubble / Typing Features

- [ ] `/me` or action message still displays correctly.
- [ ] Typing indicator appears when expected.
- [ ] Typing indicator stops when input closes.
- [ ] Bubble display still appears over players if enabled.
- [ ] Bubble range still behaves correctly.
- [ ] Toggling bubbles/typing/autoscroll still works.

## Radio Integration

Only run this section if your radio integration is enabled.

- [ ] Radio panel appears only when expected.
- [ ] Primary slot state loads correctly.
- [ ] Secondary slot state loads correctly if supported.
- [ ] Incoming radio messages render correctly.
- [ ] Outgoing radio messages send correctly.
- [ ] Radio fallback routing behaves correctly if embedded view is unavailable.
- [ ] Restarting the radio resource does not permanently desync chat UI.

## Resource Restart / Reconnect / Robustness

- [ ] `ensure poodlechat` while players are online does not leave chat unusable.
- [ ] Client reconnect after network drop restores chat functionality.
- [ ] Reopening chat after reconnect still works.
- [ ] No permanent stuck focus after resource restart.
- [ ] Permissions/channels re-sync after restart.
- [ ] History re-sync after restart is correct.
- [ ] Whisper conversations still work after restart.

## Regression Checks

- [ ] Existing exports used by other resources still work on a smoke-test level.
- [ ] README-documented channel usage still works.
- [ ] Global chat still reaches everyone.
- [ ] Staff chat is still permission-gated.
- [ ] Commands still register and show suggestions.
- [ ] No major console spam appears during normal use.

## Suggested Test Sessions

### Session 1: Single-Player

- [ ] UI smoke
- [ ] Opacity
- [ ] Tabs/grouping
- [ ] Emoji panel
- [ ] Hex colors
- [ ] Line breaks
- [ ] Resource restart

### Session 2: Two-Player

- [ ] Local/global chat
- [ ] Range color
- [ ] Whispers
- [ ] Notification/unread behavior
- [ ] Typing/bubbles

### Session 3: Character Persistence

- [ ] Character A1 history
- [ ] Switch to A2
- [ ] Isolation check
- [ ] Switch back to A1
- [ ] Restore check
- [ ] Delete conversation check

### Session 4: Offline / Failure Paths

- [ ] Offline whisper queue
- [ ] Reconnect delivery
- [ ] Wrong-character reconnect guard
- [ ] Hot restart while players are online
- [ ] Late-load queue behavior

## Issue Log Template

Use this when something fails:

```md
- Area:
- Scenario:
- Players involved:
- Steps to reproduce:
- Expected result:
- Actual result:
- Console errors:
- Video/screenshot:
```


o = test passed / valided / positif
/ = can't be tested
x = failed / don't work