Config = {
	settings = {
		-- Prints chat messages in server console
		printToConsole = true,
		-- Maximum characters allowed in player nickname (color codes and spaces included)
		maxNicknameLen = 150
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
			order = 20,
			-- Maximum messages kept in this tab
			history = 250,
			-- Shows this tab in UI when true
			visible = true,
			-- Includes this tab in tab key cycling when true
			cycle = true,
			-- Allows typing directly in this tab when true
			canSend = false,
			-- Channel scope type
			scope = 'proximity',
			-- Distance used by this channel when scope uses range
			distance = 0.0
		},
	
		["local"] = {
			label = 'RP',
			color = {0, 153, 204},
			order = 30,
			history = 250,
			visible = true,
			cycle = true,
			scope = 'proximity',
			distance = 50.0
		},

		global = {
			label = 'OOC',
			color = {212, 175, 55},
			order = 40,
			history = 300,
			visible = true,
			cycle = true,
			-- global scope means messages are sent to everyone
			scope = 'global'
		},

		staff = {
			label = 'Staff',
			color = {255, 64, 0},
			order = 50,
			history = 250,
			visible = true,
			cycle = true,
			-- permission scope means only players with the specified ACE permission can see and send messages in this channel
			scope = 'permission',
			-- ACE permission needed to view and use this tab
			permission = 'chat.staffChannel'
		},

		whispers = {
			label = 'Whispers',
			color = {254, 127, 156},
			order = 10,
			history = 250,
			visible = true,
			cycle = true,
			-- whisper scope is a custom type, you can also make custom scope types by checking for them in your code and applying special behavior, whisper scope is used for the built in whisper system which has extra features like saving conversations and showing a sidebar
			scope = 'whisper'
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
			-- this is the default poodlechat overhead system from forked source, ive made a bubble system that does the same things, but you can use the old system if you prefer it, just set this to true and make sure to disable the bubble system in the features section to avoid confusion from having two similar systems running at the same time
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
		togglesound = {
			enabled = true,
			command = 'togglesound',
			aliases = {'sound'},
			channel = 'global',
			label = 'SYSTEM',
			color = '#ffffff',
			handler = 'togglesound',
			help = 'Toggle global notification sound'
		},
		-- Same format as commands above
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

	-- Message routing when player types without a command
	routing = {
		-- Default channel when nothing overrides it
		defaultChannel = 'global',
		-- How long the last command context is remembered
		responseWindowMs = 1500,
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
			showid = 'local'
		}
	},

	-- Whisper system settings
	whispers = {
		tabEnabled = true,
		fallbackChannel = 'local',
		-- -1 means unlimited
		maxConversations = -1,
		-- -1 means unlimited
		maxMessagesPerConversation = 250,
		defaultConversationMode = 'active-only',
		sidebar = {
			collapsible = true,
			defaultCollapsed = false
		}
	},

	-- Default tab groups
	tabs = {
		-- Each sub table is one visual group
		defaultGroups = {
			{'local'},
			{'global'},
			{'radio'},
			{'whispers'},
			{'staff'}
		}
	},

	-- Notification sounds
	notifications = {
		-- Profile used everywhere unless overridden
		default = {
			enabled = true,
			-- 0 to 1
			volume = 0.65,
			sound = {
				name = 'Menu_Accept',
				set = 'Phone_SoundSet_Default'
			},
			fallbackSound = {
				name = 'SELECT',
				set = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
			}
		},
		-- Per-tab overrides
		tabs = {
			whispers = {
				enabled = true,
				-- 0 to 1
				volume = 0.72,
				sound = {
					name = 'Menu_Accept',
					set = 'Phone_SoundSet_Default'
				},
				fallbackSound = {
					name = 'SELECT',
					set = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
				}
			}
		}
	},

	-- pma-voice integration
	voice = {
		enabled = true,
		-- Exact voice resource name
		resource = 'pma-voice',
		-- Fallback distance if voice data is missing
		fallbackLocalDistance = 50.0,
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

	-- Chat visual settings
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
		autoScrollDefault = true,
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
			maxDistance = 25.0,
			fadeOutMs = 4000,
			maxLength = 80,
			use3DText = true,
			offset = vector3(0.0, 0.0, 1.1)
		}
	},

	-- Logs Discord
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
			report = 16613276
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
