local function systemCommand(commandName, helpText, handler, aliases, color, label, channel)
	return {
		enabled = true,
		command = commandName,
		aliases = aliases or {},
		channel = channel or 'global',
		label = label or 'SYSTEM',
		color = color or '#ffffff',
		handler = handler or commandName,
		help = helpText
	}
end

local function soundProfile(enabled, volume, soundName, soundSet, fallbackName, fallbackSet)
	return {
		enabled = enabled ~= false,
		volume = volume,
		sound = {
			name = soundName,
			set = soundSet
		},
		fallbackSound = {
			name = fallbackName,
			set = fallbackSet
		}
	}
end

Config = {
	settings = {
		-- Prints chat messages in server console
		printToConsole = true,
		-- Maximum characters allowed in player nickname (color codes and spaces included)
		maxNicknameLen = 150,
		-- Maximum messages persisted per channel per character (KVP)
		maxPersistedMessages = 250
	},

	-- Channel tabs and message routing rules
	channels = {
		-- Radio channel settings, this is an id example for a custom channel you can add
		radio = {
			-- Tab label shown in UI
			label = 'Radio',
			-- Tab color in RGB format
			color = {255, 0, 255},
			-- Tab order in the channel list, lower numbers are shown first, you don't have to use sequential numbers, just make sure the order values are correct relative to each other
			order = 4,
			-- Maximum messages kept in this tab
			history = 250,
			-- Shows this tab in UI when true
			visible = true,
			-- Includes this tab in tab key cycling when true
			cycle = true,
			-- When false, this tab cannot host grouped channels and keeps the embedded radio behavior
			-- when it is grouped to itself. Players can still move it into another tab group.
			groupRelayTarget = false,
			-- Pinned tabs cannot be hidden from the tab list while grouped away.
			pinned = false,
			-- Allows typing directly in this tab when true
			-- canSend = false,
			-- Channel scope type
			scope = 'proximity',
			-- Distance used by this channel when scope uses range
			distance = 0.0,
			-- Persist chat history across sessions per character (KVP)
			persistHistory = true
		},
	
		["local"] = {
			label = 'RP',
		color = {0, 100, 255},
		order = 1,
		history = 250,
		visible = true,
		cycle = true,
		groupRelayTarget = true,
		pinned = true,
		scope = 'proximity',
		distance = 50.0,
		persistHistory = false
	},

	global = {
		label = 'OOC',
		color = {212, 175, 55},
		order = 2,
		history = 300,
		visible = true,
		cycle = true,
		groupRelayTarget = true,
		pinned = true,
		-- global scope means messages are sent to everyone
		scope = 'global',
		persistHistory = false
	},

	staff = {
		label = 'Staff',
		color = {255, 64, 0},
		order = 5,
		history = 250,
		visible = true,
		cycle = true,
		groupRelayTarget = true,
		pinned = false,
		-- permission scope means only players with the specified ACE permission can see and send messages in this channel
		scope = 'permission',
		-- ACE permission needed to view and use this tab
		permission = 'chat.staffChannel',
		persistHistory = true
	},

	whispers = {
		label = 'DM',
		color = {254, 127, 156},
		order = 3,
		history = 250,
		visible = true,
		cycle = true,
		-- When false, whispers use the dedicated whisper tab only while grouped to themselves.
		groupRelayTarget = false,
		pinned = false,
		-- whisper scope is a custom type, you can also make custom scope types by checking for them in your code and applying special behavior, whisper scope is used for the built in whisper system which has extra features like saving conversations and showing a sidebar
		scope = 'whisper',
		persistHistory = true
	}
	},

	-- Message style settings
	messages = {
		-- Action message style like /me, not needed if you use my QB-RPCommands script
		action = {
			-- Label shown before action messages
			label = 'ME',
			-- Action color in RGB format
			color = {200, 0, 255},
			-- Local distance for action messages
			distance = 50.0
		},
		-- Scene message style like /do, not needed if another RP command resource owns /do
		scene = {
			label = 'DO',
			color = {143, 199, 255},
			distance = 50.0
		},
		-- Color used for your own outgoing whisper line
		whisperOutgoingColor = {204, 77, 106}
	},

	-- Slash command definitions
	commands = {
		-- Global command settings
		global = {
			-- Enables this command
			enabled = true,
			-- Main command name without slash
			command = 'global',
			-- Extra aliases for this command
			aliases = {'g'},
			-- Target channel used by this command
			channel = 'global',
			-- Prefix label shown in chat
			label = 'GLOBAL',
			-- Prefix color in hex format
			color = '#d4af37',
			-- Internal handler key
			handler = 'global',
			-- Help text shown in suggestions
			help = 'Send a message in global chat'
		},

		say = {
			enabled = false,
			command = 'say',
			aliases = {},
			channel = 'local',
			label = 'LOCAL',
			color = '#0099cc',
			handler = 'local',
			help = 'Send a local proximity message'
		},

		me = {
			-- you can put that to true if you don't use my QB-RPCommands script or if you want to have the /me command handled by this script instead, just make sure to disable the /me command in my QB-RPCommands script if you do that to avoid conflicts
			enabled = false,
			command = 'me',
			aliases = {},
			channel = 'local',
			label = 'ME',
			color = '#ffcc00',
			handler = 'action',
			help = 'Send an action message'
		},

		["do"] = {
			-- Keep disabled by default so existing RP command resources can own /do without conflicts
			enabled = false,
			command = 'do',
			aliases = {},
			channel = 'local',
			label = 'DO',
			color = '#8fc7ff',
			handler = 'scene',
			help = 'Describe a local scene or outcome'
		},

		staff = {
			enabled = true,
			command = 'staff',
			aliases = {},
			channel = 'staff',
			label = 'STAFF',
			color = '#ff4000',
			handler = 'staff',
			-- ACE permission needed to use this command, also needs to be set in the channel definition for the command to show up in the staff channel
			permission = 'chat.staffChannel',
			help = 'Send a staff-only message'
		},

		whisper = {
			enabled = true,
			command = 'dm',
			aliases = {'whisper', 'w', 'msg'},
			channel = 'whispers',
			label = 'DM',
			color = '#fe7f9c',
			handler = 'whisper',
			help = 'Whisper to a player'
		},

		reply = {
			enabled = true,
			command = 'reply',
			aliases = {'r'},
			channel = 'whispers',
			label = 'REPLY',
			color = '#fe7f9c',
			handler = 'reply',
			help = 'Reply to your last whisper'
		},

		clear = systemCommand('clear', 'Clear your chat window'),
		clearhistory = systemCommand('clearhistory', 'Clear your saved chat history', 'clearhistory', {'clearhist'}, '#ffff80'),

		togglechat = systemCommand('togglechat', 'Show chat only while it is open'),

		-- this is the default poodlechat overhead system from forked source, ive made a bubble system that does the same things, but you can use the old system if you prefer it, just set this to true and make sure to disable the bubble system in the features section to avoid confusion from having two similar systems running at the same time
		toggleoverhead = {
			enabled = false,
			command = 'toggleoverhead',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'toggleoverhead',
			help = 'Toggle overhead chat text'
		},

		toggletyping = systemCommand('toggletyping', 'Toggle typing indicator visibility'),
		togglebubbles = systemCommand('togglebubbles', 'Toggle bubble visibility'),
		togglesound = systemCommand('togglesound', 'Toggle global notification sound', 'togglesound', {'sound'}),
		-- Same format as commands above
		report = {
			enabled = true,
			command = 'report',
			aliases = {},
			channel = 'global',
			label = 'REPORT',
			color = '#4c82ff',
			handler = 'report',
			help = 'Report a player to staff. Usage: /report [id] [reason]'
		},
		mute = systemCommand('mute', 'Locally mute a player', 'mute', {}, '#ffff80'),
		unmute = systemCommand('unmute', 'Remove a local mute', 'unmute', {}, '#ffff80'),
		muted = systemCommand('muted', 'Show muted players', 'muted', {}, '#ffff80'),
		nick = systemCommand('nick', 'Set your nickname', 'nick', {}, '#ffff80')
	},

	-- Message routing when player types without a command
	routing = {
		-- Default channel when nothing overrides it
		defaultChannel = 'global',
		-- How long the last command context is remembered (increased for network latency)
		responseWindowMs = 3000,
		-- Keep old aliases for compatibility
		keepLegacyAliases = false,
		-- Force specific commands to a channel
		overrides = {
			me = 'local',
			["do"] = 'local',
			staff = 'staff',
			whisper = 'whispers',
			dm = 'whispers',
			reply = 'whispers',
			r = 'whispers',
			showid = 'local',
			twt = 'local',
			news = 'local',
			dispatch = 'local',
			darkweb = 'local'
		},
		-- Fallback routing for inbound chat:addMessage payloads that do not provide a valid channel id
		-- Rules are evaluated in order and stop on the first match
		inboundMessageRules = {
			{
				channel = 'local',
				label = 'TWT',
				prefix = '[TWT]',
				templateContains = {'TWITTER | '}
			},
			{
				channel = 'local',
				label = 'NEWS',
				prefix = '[NEWS]',
				templateContains = {'NEWS | '}
			},
			{
				channel = 'local',
				label = 'DISPATCH',
				prefix = '[DISPATCH]',
				templateContains = {'Dispatch'}
			},
			{
				channel = 'local',
				label = 'DARKWEB',
				prefix = '[DARKWEB]',
				templateContains = {'Dark Web | '}
			}
		}
	},

	-- Whisper system settings
	whispers = {
		tabEnabled = true,
		tabLabel = 'DM',
		fallbackChannel = 'local',
		-- -1 means unlimited
		maxConversations = -1,
		-- -1 means unlimited
		maxMessagesPerConversation = 250,
		defaultConversationMode = 'active-only',
		-- When true, pressing + opens a live player list. When false, + asks for a player ID
		-- while still keeping conversation history and the existing DM sidebar.
		playerListEnabled = false,
		sidebar = {
			collapsible = true,
			defaultCollapsed = false,
			showPlayerMeta = false
		}
	},

	-- Default tab groups
	tabs = {
		-- Each sub table is one visual group
		defaultGroups = {
			{'local', 'global'},
			{'radio'},
			{'whispers'},
			{'staff'},
		}
	},

	-- Notification sounds
	notifications = {
		-- Profile used everywhere unless overridden
		default = soundProfile(true, 0.65, 'Menu_Accept', 'Phone_SoundSet_Default', 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET'),
		-- Per-tab overrides
		tabs = {
			whispers = soundProfile(true, 0.72, 'Menu_Accept', 'Phone_SoundSet_Default', 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET')
		}
	},

	-- pma-voice integration
	voice = {
		enabled = true,
		-- Exact voice resource name
		resource = 'pma-voice',
		-- Fallback mode list used when pma-voice settings cannot be retrieved
		-- Format: {distance, label}
		fallbackModes = {
			{5.0, 'Whisper'},
			{12.0, 'Normal'},
			{23.0, 'Shouting'}
		},
		-- How often to refresh pma-voice settings when callback retrieval is healthy
		pmaSettingsRefreshMs = 10000,
		-- Retry interval used after a failed callback retrieval
		pmaSettingsRetryMs = 30000,
		-- Fallback distance if voice data is missing
		fallbackLocalDistance = 50.0,
		-- Show a bubble marker to see your range
		showRangeBubble = true,
		-- Range level colors
		colors = {
			colorMin = 'FFDB397D',
			-- Add as many middle colors as you want in this list
			-- You can also use intermediate2 and intermediate3 keys
			-- for example intermediate = {'FF2E57DF', 'FF5033C7'},
			-- or intermediate2 = {'FF5033C7'},
			intermediate = {'FF4361C2'},
			colorMax = 'FFC43939'
		}
	},

	-- Permissions and display names
	access = {
		identifier = 'license',
		staffChannelAce = 'chat.staffChannel',
		noMuteAce = 'chat.noMute',
		rolePrefixEnabled = false,
		nicknameStorage = {
			-- "account" keeps the current behavior
			-- "qbcoreCharacter" stores nicknames per citizenid and does not fall back to account-wide keys
			-- "custom" uses the resolver below and does not fall back to the account key when no character key is returned
			mode = 'qbcoreCharacter',
			customResolver = function(source, fallbackKey)
				return fallbackKey
			end
		},
		-- Function to build the name shown in chat
		getDisplayName = function(source, fallbackName)
			if type(GetResourceState) == 'function' and GetResourceState('qb-core') ~= 'started' then
				return fallbackName
			end

			local ok, QB = pcall(function()
				return exports['qb-core']:GetCoreObject()
			end)
			if not ok or not QB then
				return fallbackName
			end

			local player = QB and QB.Functions and QB.Functions.GetPlayer(source)
			if player and player.PlayerData and player.PlayerData.charinfo then
				local charinfo = player.PlayerData.charinfo
				return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname and charinfo.lastname:sub(1, 1) .. '.' or '')
			end
			return fallbackName
		end,
		roles = {}
	},

	-- Moderation tools and report flow
	moderation = {
		builtInReports = {
			enabled = true,
			successMessage = 'Your report has been submitted.',
			failureMessage = 'Sorry, something went wrong with your report.',
			feedbackColor = {76, 130, 255}
		},
		permissions = {
			deleteAce = 'chat.deleteMessage',
			viewDeletedAce = 'chat.deleteMessage',
			qbcore = {
				enabled = true,
				staffPermissions = {'god', 'admin', 'mod'},
				deletePermissions = {'god', 'admin'}
			}
		},
		staffChannel = {
			echoReports = true,
			echoDeletes = true
		},
		deletedMessage = {
			publicLabel = 'Deleted message',
			publicText = 'This message was removed by staff.'
		}
	},

	-- Chat visual settings
	ui = {
		fadeTimeout = 7000,
		suggestionLimit = 5,
		defaultTemplateId = 'default',
		defaultAltTemplateId = 'defaultAlt',
		templates = {
			default = '{0}: {1}',
			defaultAlt = '{0}',
			print = '<pre>{0}</pre>',
			['example:important'] = '<h1>^2{0}</h1>'
		},
		chatStyle = {
			width = '40%',
			height = '25%'
		},
		theme = {
			accent = '#4c82ff'
		},
		messages = {
			showRestoredIndicator = false
		},
		autoScrollDefault = true,
		contextMenu = {
			enabled = true
		},
		colorPicker = {
			defaultColor = '#4c82ff',
			recentLimit = 8,
			autoOpenOnDecorator = false,
			openMode = 'manual'
		},
		animations = {
			enabled = true,
			profile = 'premium'
		},
		-- Text above players
		overhead = {
			enabledByDefault = false,
			distance = 50.0,
			minMs = 5000,
			maxMs = 10000,
			perCharMs = 200,
			updateMs = 50
		}
	},

	-- Emoji panel
	emoji = {
		recentLimit = 20,
		topLimit = 20
	},

	-- Optional visual effects
	features = {
		typing = {
			enabled = true,
			allowToggle = true,
			maxDistance = 25.0,
			updateRate = 200,
			style = 'dots',
			headTracking = true,
			offset = vector3(0.0, 0.0, 1.35),
			headLift = 0.26,
			screenLift = 0.03
		},
		bubbles = {
			enabled = true,
			allowToggle = true,
			-- "voice" uses the same effective range as local chat / pma-voice
			-- "fixed" keeps using maxDistance below
			rangeMode = 'voice',
			maxDistance = 25.0,
			fadeOutMs = 4000,
			maxLength = 80,
			use3DText = true,
			offset = vector3(0.0, 0.0, 1.1)
		}
	},

	integrations = {
		radio = {
			enabled = true,
			resource = '7-Radio',
			channelId = 'radio',
			-- When the embedded radio tab is hidden or unavailable, relay incoming radio text here as a plain chat line.
			fallbackChannel = 'local'
		}
	},

	manager = {
		enabled = true,
		command = 'chatmanager',
		permission = 'chat.manager',
		audit = {
			maxEntries = 500
		},
		moderation = {
			maxReports = 300
		}
	},

	runtimeAcl = {
		-- Runtime ACL entries are PoodleChat-only. They do not mutate FiveM ACE.
		-- Supported entry examples: "identifier.license:xxx", "license:xxx",
		-- "source:1", "name:Player Name", "ace:chat.staffChannel", "*" .
		allow = {},
		deny = {}
	},

	commandBuilder = {
		allowDangerousOverride = false,
		maxActions = 24,
		maxAliases = 8,
		maxTextLength = 300,
		defaultCooldownSeconds = 0,
		dangerousCommands = {
			'quit',
			'restart',
			'start',
			'stop',
			'ensure',
			'exec',
			'refresh',
			'add_ace',
			'remove_ace',
			'add_principal',
			'remove_principal'
		},
		safeEvents = {
			server = {},
			client = {}
		},
		internalActions = {
			refreshCommands = true,
			sendBubble = true
		}
	},

	autoMessages = {
		enabled = true,
		minIntervalSeconds = 120,
		maxTextLength = 240,
		defaults = {
			channel = 'global',
			label = 'Auto'
		}
	},

	-- Logs Discord
	discord = {
		enabled = false,
		-- Legacy fallback webhook. Prefer discord.webhooks.default and discord.webhooks.byKind below.
		webhook = '',
		webhooks = {
			default = '',
			byKind = {
				['local'] = '',
				global = '',
				staff = '',
				action = '',
				join = '',
				leave = '',
				report = '',
				delete = ''
			}
		},
		username = 'PoodleChat',
		footer = 'poodlechat',
		sendLocal = true,
		sendGlobal = true,
		sendStaff = true,
		sendAction = true,
		sendJoinLeave = true,
		sendReports = true,
		sendDeletes = true,
		reportSuccessMessage = 'Your report has been submitted.',
		reportFailureMessage = 'Sorry, something went wrong with your report.',
		reportFeedbackColor = {76, 130, 255},
		-- Embed colors
		colors = {
			default = 3447003,
			['local'] = 3447003,
			global = 15844367,
			staff = 15158332,
			action = 10181046,
			join = 65280,
			leave = 16711680,
			leaveKicked = 16007897,
			report = 16613276,
			delete = 15105570
		}
	},

	-- Internal performance settings
	runtime = {
		client = {
			chatOpenControl = 245,
			suggestionBatchSize = 200,
			mainLoopIdleMs = 0,
			overheadIdleMs = 250,
			resourceRefreshDelayMs = 500,
			pmaStartDelayMs = 500
		},
		server = {
			refreshCommandsDelayMs = 500
		},
		ui = {
			emojiRenderBatchSize = 260,
			emojiSearchDebounceMs = 80,
			inputFocusDelayMs = 100,
			pageScrollStep = 100
		}
	}
}
