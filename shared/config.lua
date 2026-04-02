Config = {
	settings = {
		printToConsole = true,
		maxNicknameLen = 125
	},
	channels = {
		radio = {
			label = 'Radio',
			color = {255, 0, 255},
			history = 250,
			visible = true,
			cycle = true,
			scope = 'proximity',
			distance = 0.0
		},
		["local"] = {
			label = 'RP',
			color = {0, 153, 204},
			history = 250,
			visible = true,
			cycle = true,
			scope = 'proximity',
			distance = 50.0
		},
		global = {
			label = 'OOC',
			color = {212, 175, 55},
			history = 300,
			visible = true,
			cycle = true,
			scope = 'global'
		},
		staff = {
			label = 'Staff',
			color = {255, 64, 0},
			history = 250,
			visible = true,
			cycle = true,
			scope = 'permission',
			permission = 'chat.staffChannel'
		},
		whispers = {
			label = 'Whispers',
			color = {254, 127, 156},
			history = 250,
			visible = true,
			cycle = true,
			scope = 'whisper'
		}
	},
	messages = {
		action = {
			label = 'ME',
			color = {200, 0, 255},
			distance = 50.0
		},
		whisperOutgoingColor = {204, 77, 106}
	},
	commands = {
		global = {
			enabled = true,
			command = 'global',
			aliases = {'g'},
			channel = 'global',
			label = 'GLOBAL',
			color = '#d4af37',
			handler = 'global',
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
			enabled = true,
			command = 'me',
			aliases = {},
			channel = 'local',
			label = 'ME',
			color = '#ffcc00',
			handler = 'action',
			help = 'Send an action message'
		},
		staff = {
			enabled = true,
			command = 'staff',
			aliases = {},
			channel = 'staff',
			label = 'STAFF',
			color = '#ff4000',
			handler = 'staff',
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
		clear = {
			enabled = true,
			command = 'clear',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'clear',
			help = 'Clear your chat window'
		},
		togglechat = {
			enabled = true,
			command = 'togglechat',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'togglechat',
			help = 'Toggle chat visibility'
		},
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
		toggletyping = {
			enabled = true,
			command = 'toggletyping',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'toggletyping',
			help = 'Toggle typing indicator visibility'
		},
		togglebubbles = {
			enabled = true,
			command = 'togglebubbles',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'togglebubbles',
			help = 'Toggle bubble visibility'
		},
		report = {
			enabled = true,
			command = 'report',
			aliases = {},
			channel = 'global',
			label = 'REPORT',
			color = '#ffa500',
			handler = 'report',
			help = 'Report a player to staff'
		},
		mute = {
			enabled = true,
			command = 'mute',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffff80',
			handler = 'mute',
			help = 'Locally mute a player'
		},
		unmute = {
			enabled = true,
			command = 'unmute',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffff80',
			handler = 'unmute',
			help = 'Remove a local mute'
		},
		muted = {
			enabled = true,
			command = 'muted',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffff80',
			handler = 'muted',
			help = 'Show muted players'
		},
		nick = {
			enabled = true,
			command = 'nick',
			aliases = {},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffff80',
			handler = 'nick',
			help = 'Set your nickname'
		}
	},
	routing = {
		defaultChannel = 'global',
		responseWindowMs = 1500,
		keepLegacyAliases = false,
		overrides = {
			me = 'local',
			["do"] = 'local',
			staff = 'staff',
			whisper = 'whispers',
			dm = 'whispers',
			reply = 'whispers',
			r = 'whispers',
			showid = 'local'
		}
	},
	whispers = {
		tabEnabled = true,
		fallbackChannel = 'local',
		maxConversations = -1,
		maxMessagesPerConversation = 250,
		defaultConversationMode = 'active-only',
		notification = {
			enabled = true,
			volume = 0.72,
			sound = {
				name = 'TENNIS_POINT_WON',
				set = 'HUD_AWARDS'
			},
			fallbackSound = {
				name = 'SELECT',
				set = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
			}
		},
		sidebar = {
			collapsible = true,
			defaultCollapsed = false
		}
	},
	access = {
		identifier = 'license',
		staffChannelAce = 'chat.staffChannel',
		noMuteAce = 'chat.noMute',
		rolePrefixEnabled = false,
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
		roles = {
			-- {name = 'Admin', ace = 'chat.admin'} 
		}
	},
	ui = {
		fadeTimeout = 7000,
		suggestionLimit = 5,
		defaultTemplateId = 'default',
		defaultAltTemplateId = 'defaultAlt',
		templates = {
			default = '<b>{0}</b>: {1}',
			defaultAlt = '{0}',
			print = '<pre>{0}</pre>',
			['example:important'] = '<h1>^2{0}</h1>'
		},
		chatStyle = {
			width = '40%',
			height = '25%'
		},
		separateChannelTabs = true,
		singleChannelId = 'local',
		autoScrollDefault = true,
		overhead = {
			enabledByDefault = false,
			distance = 50.0,
			minMs = 5000,
			maxMs = 10000,
			perCharMs = 200,
			updateMs = 50
		}
	},
	emoji = {
		recentLimit = 20,
		topLimit = 20
	},
	distance = {
		enabled = true,
		default = 8.0,
		pollRate = 500,
		getCurrent = "exports['pma-voice']:getVoiceRange()",
		getLabel = "exports['pma-voice']:getVoiceRangeName()",
		setCurrent = "exports['pma-voice']:setVoiceRange(range)",
		modes = {
			{id = 'whisper', label = 'Whisper', distance = 3.0, color = '#cc2687'},
			{id = 'normal', label = 'Normal', distance = 8.0, color = '#2e85cc'},
			{id = 'shout', label = 'Shout', distance = 15.0, color = '#e74c3c'}
		},
		ui = {
			useModeLabels = true,
			dynamic = true
		}
	},
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
			maxDistance = 25.0,
			fadeOutMs = 4000,
			maxLength = 80,
			use3DText = true,
			offset = vector3(0.0, 0.0, 1.1)
		}
	},
	discord = {
		enabled = false,
		webhook = '',
		username = 'PoodleChat',
		footer = 'poodlechat',
		sendLocal = true,
		sendGlobal = true,
		sendStaff = true,
		sendAction = true,
		sendJoinLeave = true,
		sendReports = true,
		reportSuccessMessage = 'Your report has been submitted.',
		reportFailureMessage = 'Sorry, something went wrong with your report.',
		reportFeedbackColor = {255, 165, 0},
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
	},
	runtime = {
		client = {
			chatOpenControl = 245,
			suggestionBatchSize = 200,
			mainLoopIdleMs = 0,
			overheadIdleMs = 250,
			resourceRefreshDelayMs = 500,
			pmaStartDelayMs = 300
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
