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

	-- Optional role prefixes resolved by ACE
	-- First matching ACE wins
	-- Role color, if set, overrides default name color in chat
	roles = {
		-- {name = 'Admin', ace = 'chat.admin'},
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
		width = '38%',
		height = '22%'
	},

	-- Show overhead text messages by default for each player (use the default poodlechat system, set to false if chatbubbles is activated as it will display both otherwise)
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
