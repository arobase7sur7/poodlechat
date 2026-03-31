Config = {}

Config.Chat = {
	-- RGB color used for /me action messages (don't mind if using my QB-RPCommands script)
	actionColor = {200, 0, 255},

	-- RGB color used for local proximity chat messages
	localColor = {0, 153, 204},

	-- RGB color used for global chat messages
	globalColor = {212, 175, 55},

	-- RGB color used for staff channel messages
	staffColor = {255, 64, 0},

	-- RGB color used when receiving whispers
	whisperColor = {254, 127, 156},

	-- RGB color used when sending whispers (echo feedback)
	whisperEchoColor = {204, 77, 106},

	-- Maximum distance (meters) for /me visibility
	actionDistance = 50.0,

	-- Maximum distance (meters) for local chat visibility
	localDistance = 50.0,

	-- Maximum nickname length for /nick
	maxNicknameLen = 125,

	-- Print message traffic to server console
	printToConsole = true
}

Config.Channels = {
	["local"] = { -- channel id, used for routing and permissions
		label = 'Local', -- display label for UI
		color = {0, 153, 204}, -- RGB color for UI elements (can be hex string too, like '#0099cc')
		order = 10, -- numeric order for channel sorting in UI
		visible = true, -- whether the channel is visible/selectable in UI
		cycle = true, -- whether the channel is included when cycling with a keybind (like TAB)
		requiresAce = nil, -- optional ACE permission required to view/send in this channel, nil for no requirement
		maxHistory = 250 -- maximum number of messages to keep in history for this channel (per player)
	},
	global = {
		label = 'Global',
		color = {212, 175, 55},
		order = 20,
		visible = true,
		cycle = true,
		requiresAce = nil,
		maxHistory = 300
	},
	staff = {
		label = 'Staff',
		color = {255, 64, 0},
		order = 30,
		visible = true,
		cycle = true,
		requiresAce = 'chat.staffChannel',
		maxHistory = 250
	},
	whispers = {
		label = 'Whispers',
		color = {254, 127, 156},
		order = 40,
		visible = true,
		cycle = true,
		requiresAce = nil,
		maxHistory = 250
	}
}

Config.Commands = {
	global = { -- Command id used for routing and permissions
		enabled = true, -- master toggle for this command, can be used to disable specific commands without removing them from the config
		command = 'global', -- main command name, used for invocation (e.g. /global) and routing
		aliases = {'g'}, -- alternative command names that trigger the same handler (e.g. /g)
		channel = 'global', -- default channel id to route messages from this command, must match a key in Config.Channels
		label = 'GLOBAL', -- display label for messages from this command, can be used in UI templates
		color = '#d4af37', -- color for messages from this command, can be RGB table or hex string
		handler = 'global' -- identifier for the server-side handler function
	},
	say = {
		enabled = true,
		command = 'say',
		aliases = {},
		channel = 'local',
		label = 'LOCAL',
		color = '#0099cc',
		handler = 'local'
	},
	ooc = {
		enabled = true,
		command = 'ooc',
		aliases = {'b'},
		channel = 'global',
		label = 'OOC',
		color = '#cccccc',
		handler = 'global'
	},
	me = {
		enabled = true,
		command = 'me',
		aliases = {},
		channel = 'local',
		label = 'ME',
		color = '#ffcc00',
		handler = 'action'
	},
	staff = {
		enabled = true,
		command = 'staff',
		aliases = {},
		channel = 'staff',
		label = 'STAFF',
		color = '#ff4000',
		handler = 'staff',
		permission = 'chat.staffChannel'
	},
	whisper = {
		enabled = true,
		command = 'dm',
		aliases = {'whisper', 'w', 'msg'},
		channel = 'whispers',
		label = 'DM',
		color = '#a970ff',
		handler = 'whisper'
	},
	reply = {
		enabled = true,
		command = 'reply',
		aliases = {'r'},
		channel = 'whispers',
		label = 'REPLY',
		color = '#a970ff',
		handler = 'reply'
	},
	clear = {
		enabled = true,
		command = 'clear',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffffff',
		handler = 'clear'
	},
	togglechat = {
		enabled = true,
		command = 'togglechat',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffffff',
		handler = 'togglechat'
	},
	toggleoverhead = {
		enabled = true,
		command = 'toggleoverhead',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffffff',
		handler = 'toggleoverhead'
	},
	toggletyping = {
		enabled = true,
		command = 'toggletyping',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffffff',
		handler = 'toggletyping'
	},
	togglebubbles = {
		enabled = true,
		command = 'togglebubbles',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffffff',
		handler = 'togglebubbles'
	},
	report = {
		enabled = true,
		command = 'report',
		aliases = {},
		channel = 'global',
		label = 'REPORT',
		color = '#ffa500',
		handler = 'report'
	},
	mute = {
		enabled = true,
		command = 'mute',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffff80',
		handler = 'mute'
	},
	unmute = {
		enabled = true,
		command = 'unmute',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffff80',
		handler = 'unmute'
	},
	muted = {
		enabled = true,
		command = 'muted',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffff80',
		handler = 'muted'
	},
	nick = {
		enabled = true,
		command = 'nick',
		aliases = {},
		channel = 'global',
		label = 'SYSTEM',
		color = '#ffff80',
		handler = 'nick'
	}
}

Config.CommandRouting = {
	defaultChannel = 'global', -- default channel id for commands that don't specify one, must match a key in Config.Channels
	responseWindowMs = 1500, -- time window to route follow-up messages from the same player to the same channel after an initial command message, helps with commands that have multiple responses or require additional input, set to 0 to disable
	keepLegacyAliases = true, -- when true, command aliases that match other command names (e.g. /g for /global) will still trigger the original command handler instead of being overridden by the new one, set to false to have aliases take precedence over existing command names
	overrides = { -- route specific command names to different channels/handlers, useful for compatibility with existing scripts or custom command setups, keys are command names (without prefix), values are channel ids or handler identifiers
		me = 'local',
		["do"] = 'local', -- Work with other scripts than only poodlechat, here "do" do not exist on this script
		ooc = 'global',
		staff = 'staff',
		whisper = 'whispers',
		dm = 'whispers',
		reply = 'whispers',
		r = 'whispers'
	}
}

Config.Whispers = {
	-- Enables whisper conversation UI/tab features
	-- When false, whispers fall back to normal channel delivery and command-only behavior
	separateWhisperTab = true,

	-- Channel used to display whisper messages when separateWhisperTab is disabled
	-- Must match an existing channel id in Config.Channels
	fallbackChannel = 'local',

	-- Maximum number of whisper conversations kept in memory (-1 = unlimited)
	maxConversations = -1,

	-- Maximum number of messages kept per whisper conversation (-1 = unlimited)
	maxMessagesPerConversation = 250,
	defaultConversationMode = 'active-only',

	notifications = {
		-- Enables incoming whisper sound notifications by default
		enabled = true,

		-- 0.0 - 1.0 volume for whisper sound notifications
		volume = 0.65,

		-- GTA frontend sound name used for whisper notifications
		soundName = 'SELECT',

		-- GTA frontend soundset used for whisper notifications
		soundSet = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
	},

	sidebar = {
		-- Allow collapsed sidebar mode in whisper tab
		collapsible = true,

		-- Initial sidebar collapsed state
		defaultCollapsed = false
	}
}

Config.Access = {
	-- Identifier type used for per-player persistent data
	-- Common values: "license", "steam", "discord"
	identifier = 'license',

	-- ACE permission required to read/write the staff channel
	-- On server.cfg: add_ace group.admin chat.staffChannel allow for example
	-- Or add_ace identifier.license:1234567890abcdef chat.staffChannel allow to grant a specific player
	staffChannelAce = 'chat.staffChannel',

	-- ACE permission that bypasses local mute filtering
	noMuteAce = 'chat.noMute',

	-- Optional display-name resolver:
	-- function(source, fallbackName) -> string|nil
	-- Example with QBCore:
	-- getDisplayName = function(source, fallbackName)
	-- 	local QB = exports['qb-core']:GetCoreObject()
	-- 	local player = QB and QB.Functions and QB.Functions.GetPlayer(source)
	-- 	if player and player.PlayerData and player.PlayerData.charinfo then
	-- 		local charinfo = player.PlayerData.charinfo
	-- 		return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
	-- 	end
	-- 	return fallbackName
	-- end,
	getDisplayName = function(source, fallbackName)
		local QB = exports['qb-core']:GetCoreObject()
		local player = QB and QB.Functions and QB.Functions.GetPlayer(source)
		if player and player.PlayerData and player.PlayerData.charinfo then
			local charinfo = player.PlayerData.charinfo
			return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname and charinfo.lastname:sub(1, 1) .. '.' or '')
		end
		return fallbackName
	end,

	-- Optional role prefixes resolved by ACE
	-- First matching ACE wins
	-- Role color, if set, overrides default name color in chat
	roles = {
		 {name = 'Admin', ace = 'chat.admin'},
		-- {name = 'Moderator', color = {0, 255, 0}, ace = 'chat.moderator'}
	}
}

Config.UI = {
	-- Milliseconds to keep the chat window visible after new messages
	fadeTimeout = 7000,

	-- Maximum command suggestions shown at once
	suggestionLimit = 5,

	-- Default template id
	defaultTemplateId = 'default',

	-- Alternate template id 
	defaultAltTemplateId = 'defaultAlt',

	-- HTML templates 
	templates = {
		default = '<b>{0}</b>: {1}',
		defaultAlt = '{0}',
		print = '<pre>{0}</pre>',
		['example:important'] = '<h1>^2{0}</h1>'
	},

	-- Inline CSS sizing applied to chat window
	chatStyle = {
		width = '40%',
		height = '25%'
	},

	-- Show tabs for every channel
	-- Set to false to use a single fixed tab/channel UI
	-- Note: Whisper tab is still shown separately when Config.Whispers.separateWhisperTab is true, regardless of this setting
	separateChannelTabs = true,

	-- Channel used when separateChannelTabs is false
	-- Must match an existing channel id in Config.Channels
	singleChannelId = 'local',

	-- When true, chat always scrolls to latest message
	-- Players can still toggle this in-game
	autoScrollDefault = true,

	-- Show overhead text messages by default for each player (use the original poodlechat system, set to false if chatbubbles is activated as it will display both otherwise)
	displayOverheadByDefault = false,

	-- Maximum distance (meters) to render overhead text
	overheadDistance = 50.0,

	-- Minimum display lifetime (milliseconds) for overhead text
	overheadMinMs = 5000,

	-- Maximum display lifetime (milliseconds) for overhead text
	overheadMaxMs = 10000,

	-- Added lifetime (milliseconds) per text character
	overheadPerCharMs = 200,

	-- Overhead projection update frequency (milliseconds)
	overheadUpdateMs = 50
}

Config.Emoji = {
	-- Max entries shown in the "Recent" emoji tab
	recentLimit = 20,

	-- Max entries shown in the "Most used" emoji tab
	topLimit = 20
}

Config.Distance = {
	-- Enable distance widget and distance cycling support (Whisper, Normal etc)
	enabled = true,

	-- Expression/function returning the current voice range
	-- Supports plain expressions or full Lua return statements
	getDistance = "exports['pma-voice']:getVoiceRange()",

	-- Expression/function returning a display label for current range
	getLabel = "exports['pma-voice']:getVoiceRangeName()",

	-- Expression/function used to set the next range
	-- If this fails, fallback is ExecuteCommand('cycleproximity') when available
	setDistance = "exports['pma-voice']:setVoiceRange(range)",

	-- Fallback default range used when getters are unavailable
	default = 10.0,

	-- Ordered distance cycling list (meters), don't forget to update this if you change voice modes in pma-voice config or any custom implementation you use
	ranges = {3.0, 8.0, 15.0},

	-- Poll interval for distance refresh (milliseconds)
	pollRate = 500,

	ui = {
		-- Enable distance label/color override
		override = true,

		-- "priority" maps by configured priority/index, example: 1 = Whisper, 2 = Normal, 3 = Shout (from lowest to highest range)
		-- "range" maps by nearest configured range, example: 3.0 = Whisper, 8.0 = Normal, 15.0 = Shout (depends on getDistance implementation)
		mode = 'priority',

		-- When true, dynamically learns observed ranges from runtime state
		dynamic = true,

		-- Visual levels used for override mode
		-- color accepts #RRGGBB, RRGGBB, #AARRGGBB, or AARRGGBB
		levels = {
			{priority = 1, label = 'Whisper', color = 'FFCC2687'},
			{priority = 2, label = 'Normal', color = 'FF2E85CC'},
			{priority = 3, label = 'Shout', color = '#e74c3c'}
		}
	}
}

Config.Discord = {
	-- Master toggle for outbound Discord webhook integration
	enabled = false,

	-- Full Discord webhook URL
	webhook = '',

	-- Display name used by webhook posts
	username = 'PoodleChat',

	-- Footer text displayed in webhook embeds
	footer = 'poodlechat',

	-- Send local chat to Discord
	sendLocal = true,

	-- Send global chat to Discord
	sendGlobal = true,

	-- Send staff chat to Discord
	sendStaff = true,

	-- Send action chat (/me) to Discord (only supports the default template)
	sendAction = true,

	-- Send player join/leave events to Discord
	sendJoinLeave = true,

	-- Enable /report webhook delivery
	sendReports = true,

	-- Feedback shown to reporter on successful submission
	reportSuccessMessage = 'Your report has been submitted.',

	-- Feedback shown to reporter when submission fails
	reportFailureMessage = 'Sorry, something went wrong with your report.',

	-- RGB feedback color for /report responses in chat
	reportFeedbackColor = {255, 165, 0},

	-- Embed colors per message kind (decimal or hex)
	colors = {
		default = 3447003,
		['local'] = 3447003,
		global = 15844367,
		staff = 15158332,
		action = 10181046,
		join = 65280,
		leave = 16711680,
		leaveKicked = 16007897,
		report = 16613276
	}
}

Config.TypingIndicator = {
	-- Enable typing indicator system
	enabled = true,

	-- Allow players to toggle indicator visibility in-game
	allowPlayerToggle = true,

	-- Max distance (meters) for receiving remote typing indicators
	maxDistance = 25.0,

	-- Minimum interval (milliseconds) between repeated typing state updates
	updateRate = 200,

	-- Visual style for overhead typing indicator
	-- Supported: "dots", "typing"
	style = 'dots',

	-- Base world-space offset applied to typing indicator projection.
	offset = vector3(0.0, 0.0, 1.1)
}

Config.ChatBubbles = {
	-- Enable chat bubble display system
	enabled = true,

	-- Allow players to toggle bubble visibility in-game
	allowPlayerToggle = true,

	-- Max distance (meters) for receiving bubble messages
	maxDistance = 25.0,

	-- Bubble fade-out lifetime (milliseconds)
	fadeOutTime = 4000,

	-- Maximum bubble text length after clipping
	maxLength = 80,

	-- Render bubbles using 3D projected UI elements, if false, falls back to DrawText based rendering (not recommended)
	use3DText = true,

	-- Base world-space bubble offset for 3D rendering
	offset = vector3(0.0, 0.0, 1.1)
}

Config.Runtime = {
	client = {
		-- Control id used to open chat input (default: T key)
		chatOpenControl = 245,

		-- NUI suggestion batch size for large command/emoji lists
		suggestionBatchSize = 200,

		-- Main input/state loop sleep in milliseconds when idle
		-- Keep 0 for original per-frame behavior
		mainLoopIdleMs = 0,

		-- Overhead update loop sleep in milliseconds when no entries exist
		overheadIdleMs = 250,

		-- Delay before command/theme refresh on start/stop events
		resourceRefreshDelayMs = 500,

		-- Delay after pma-voice start before querying voice modes
		pmaStartDelayMs = 300
	},

	server = {
		-- Delay before refreshing command suggestions at server start
		refreshCommandsDelayMs = 500
	},

	ui = {
		-- Emoji render chunk size when virtualizing panel list
		emojiRenderBatchSize = 260,

		-- Emoji search input debounce in milliseconds
		emojiSearchDebounceMs = 80,

		-- Delay before focusing chat input after open
		inputFocusDelayMs = 100,

		-- Scroll step for PageUp/PageDown inside chat history
		pageScrollStep = 100
	}
}
