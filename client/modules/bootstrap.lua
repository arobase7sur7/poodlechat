PoodleChatClient = PoodleChatClient or {}

local Client = PoodleChatClient
local bootstrapInitialized = false

Client.netEvents = {
	'chatMessage',
	'chat:addTemplate',
	'chat:addMessage',
	'chat:addSuggestion',
	'chat:addSuggestions',
	'chat:removeSuggestion',
	'chat:clear',
	'__cfx_internal:serverPrint',
	'_chat:messageEntered',
	'poodlechat:channelMessage',
	'poodlechat:globalMessage',
	'poodlechat:localMessage',
	'poodlechat:action',
	'poodlechat:whisperEcho',
	'poodlechat:whisper',
	'poodlechat:whisperTargets',
	'poodlechat:whisperError',
	'poodlechat:setReplyTo',
	'poodlechat:staffMessage',
	'poodlechat:setPermissions',
	'poodlechat:mute',
	'poodlechat:unmute',
	'poodlechat:showMuted',
	'poodlechat:typingState',
	'poodlechat:bubbleMessage'
}

local legacyCommandAliases = {
	global = {'global', 'g'},
	say = {'say'},
	ooc = {'ooc', 'b'},
	me = {'me'},
	staff = {'staff'},
	whisper = {'whisper', 'w', 'msg', 'dm'},
	reply = {'reply', 'r'},
	clear = {'clear'},
	togglechat = {'togglechat'},
	toggleoverhead = {'toggleoverhead'},
	toggletyping = {'toggletyping'},
	togglebubbles = {'togglebubbles'},
	report = {'report'},
	mute = {'mute'},
	unmute = {'unmute'},
	muted = {'muted'},
	nick = {'nick'}
}

local function decodeJson(value)
	if not value then
		return nil
	end

	local ok, result = pcall(json.decode, value)

	if ok then
		return result
	end

	return nil
end

local function encodeAndStore(key, value)
	SetResourceKvp(key, json.encode(value))
end

local function normalizeKey(value)
	if type(value) ~= 'string' then
		return nil
	end

	local normalized = value:lower():gsub('^%s+', ''):gsub('%s+$', '')
	if normalized == '' then
		return nil
	end

	return normalized
end

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function clampColorChannel(value)
	local number = tonumber(value) or 0
	if number < 0 then
		return 0
	end
	if number > 255 then
		return 255
	end
	return math.floor(number)
end

local function normalizeHexColor(value)
	if type(value) ~= 'string' then
		return nil
	end

	local raw = value:gsub('%s+', ''):lower()
	local r, g, b = raw:match('^#?(%x%x)(%x%x)(%x%x)$')
	if r and g and b then
		return {
			tonumber(r, 16),
			tonumber(g, 16),
			tonumber(b, 16)
		}
	end

	local a, rr, gg, bb = raw:match('^#?(%x%x)(%x%x)(%x%x)(%x%x)$')
	if a and rr and gg and bb then
		return {
			tonumber(rr, 16),
			tonumber(gg, 16),
			tonumber(bb, 16)
		}
	end

	return nil
end

local function normalizeRgbColor(value, fallback)
	if type(value) == 'table' then
		return {
			clampColorChannel(value[1] or value.r),
			clampColorChannel(value[2] or value.g),
			clampColorChannel(value[3] or value.b)
		}
	end

	local parsed = normalizeHexColor(value)
	if parsed then
		return parsed
	end

	if type(fallback) == 'table' then
		return {
			clampColorChannel(fallback[1] or fallback.r),
			clampColorChannel(fallback[2] or fallback.g),
			clampColorChannel(fallback[3] or fallback.b)
		}
	end

	return {255, 255, 255}
end

local function addChatMessage(color, ...)
	if type(color) == 'table' and color.args then
		TriggerEvent('chat:addMessage', color)
		return
	end

	TriggerEvent('chat:addMessage', {
		color = normalizeRgbColor(color, {255, 255, 255}),
		args = {...}
	})
end

local function hexColorToRgb(value, fallback)
	if type(value) ~= 'string' then
		return fallback
	end

	local normalized = value:lower()
	local rHex, gHex, bHex = normalized:match('^#(%x%x)(%x%x)(%x%x)$')
	if not rHex or not gHex or not bHex then
		return fallback
	end

	local r = tonumber(rHex, 16)
	local g = tonumber(gHex, 16)
	local b = tonumber(bHex, 16)

	if not r or not g or not b then
		return fallback
	end

	return {r, g, b}
end

local function getOffset(value, fallback)
	if type(value) == 'vector3' then
		return value
	end

	if type(value) == 'table' and value.x and value.y and value.z then
		return vector3(value.x, value.y, value.z)
	end

	return fallback
end

local function sendNuiMessage(payload)
	SendNUIMessage(payload)
end

local function isInProximity(id, distance)
	local myId = PlayerId()
	local target = GetPlayerFromServerId(id)

	if target == -1 then
		return false
	end

	if target == myId then
		return true
	end

	local myPed = GetPlayerPed(myId)
	local ped = GetPlayerPed(target)

	if ped == 0 then
		return false
	end

	local myCoords = GetEntityCoords(myPed)
	local coords = GetEntityCoords(ped)

	return #(myCoords - coords) <= distance
end

local function appendUnique(list, seen, value)
	local normalized = normalizeKey(value)
	if not normalized or seen[normalized] then
		return
	end

	seen[normalized] = true
	list[#list + 1] = normalized
end

local function sortByOrderThenId(a, b)
	if a.order == b.order then
		return a.id < b.id
	end
	return a.order < b.order
end

local function normalizeHistoryLimit(value, fallback)
	local number = tonumber(value)
	if number == nil then
		number = tonumber(fallback)
	end

	if number == nil then
		return 250
	end

	number = math.floor(number)
	if number < 0 then
		return -1
	end
	if number == 0 then
		return math.max(1, math.floor(tonumber(fallback) or 250))
	end

	return number
end

local function buildChannelDefinitions(channelsConfig, chatConfig, accessConfig)
	local defaults = {
		["local"] = {
			label = 'Local',
			color = chatConfig.localColor or {0, 153, 204},
			order = 10,
			visible = true,
			cycle = true,
			requiresAce = nil,
			maxHistory = 250
		},
		global = {
			label = 'Global',
			color = chatConfig.globalColor or {212, 175, 55},
			order = 20,
			visible = true,
			cycle = true,
			requiresAce = nil,
			maxHistory = 300
		},
		staff = {
			label = 'Staff',
			color = chatConfig.staffColor or {255, 64, 0},
			order = 30,
			visible = true,
			cycle = true,
			requiresAce = tostring(accessConfig.staffChannelAce or 'chat.staffChannel'),
			maxHistory = 250
		},
		whispers = {
			label = 'Whispers',
			color = chatConfig.whisperColor or {254, 127, 156},
			order = 40,
			visible = true,
			cycle = true,
			requiresAce = nil,
			maxHistory = 250
		}
	}

	local merged = {}

	for channelId, defaultEntry in pairs(defaults) do
		local override = type(channelsConfig[channelId]) == 'table' and channelsConfig[channelId] or {}
		merged[channelId] = {
			id = channelId,
			label = tostring(override.label or defaultEntry.label),
			color = normalizeRgbColor(override.color, defaultEntry.color),
			order = tonumber(override.order) or defaultEntry.order,
			visible = override.visible ~= false,
			cycle = override.cycle ~= false,
			requiresAce = type(override.requiresAce) == 'string' and override.requiresAce ~= '' and override.requiresAce or defaultEntry.requiresAce,
			maxHistory = normalizeHistoryLimit(override.maxHistory, defaultEntry.maxHistory)
		}
	end

	for rawId, rawEntry in pairs(channelsConfig) do
		local channelId = normalizeKey(rawId)
		if channelId and type(rawEntry) == 'table' and not merged[channelId] then
			merged[channelId] = {
				id = channelId,
				label = tostring(rawEntry.label or channelId),
				color = normalizeRgbColor(rawEntry.color, {255, 255, 255}),
				order = tonumber(rawEntry.order) or 100,
				visible = rawEntry.visible ~= false,
				cycle = rawEntry.cycle ~= false,
				requiresAce = type(rawEntry.requiresAce) == 'string' and rawEntry.requiresAce ~= '' and rawEntry.requiresAce or nil,
				maxHistory = normalizeHistoryLimit(rawEntry.maxHistory, 250)
			}
		end
	end

	local list = {}
	local byId = {}
	local idByName = {}
	local nameById = {}

	for _, channel in pairs(merged) do
		list[#list + 1] = channel
		byId[channel.id] = channel
		idByName[channel.label] = channel.id
		nameById[channel.id] = channel.label
	end

	table.sort(list, sortByOrderThenId)

	for i = 1, #list do
		local channel = list[i]
		idByName[channel.label] = channel.id
		nameById[channel.id] = channel.label
	end

	return list, byId, idByName, nameById
end

local function buildCommandDefinitions(commandsConfig, keepLegacyAliases)
	local commandByKey = {}

	for rawKey, rawEntry in pairs(commandsConfig) do
		if type(rawEntry) == 'table' and rawEntry.enabled ~= false then
			local key = normalizeKey(rawKey)
			if key then
				local commandName = normalizeKey(rawEntry.command) or key
				local aliases = {}
				local seenNames = {}
				seenNames[commandName] = true

				if type(rawEntry.aliases) == 'table' then
					for i = 1, #rawEntry.aliases do
						appendUnique(aliases, seenNames, rawEntry.aliases[i])
					end
				end

				if keepLegacyAliases then
					local legacy = legacyCommandAliases[key]
					if type(legacy) == 'table' then
						for i = 1, #legacy do
							local legacyName = legacy[i]
							if normalizeKey(legacyName) ~= commandName then
								appendUnique(aliases, seenNames, legacyName)
							end
						end
					end
				end

				commandByKey[key] = {
					key = key,
					enabled = true,
					command = commandName,
					aliases = aliases,
					channel = normalizeKey(rawEntry.channel) or 'global',
					label = tostring(rawEntry.label or key:upper()),
					color = normalizeRgbColor(rawEntry.color, {255, 255, 255}),
					handler = normalizeKey(rawEntry.handler) or key,
					permission = type(rawEntry.permission) == 'string' and rawEntry.permission ~= '' and rawEntry.permission or nil,
					help = tostring(rawEntry.help or '')
				}
			end
		end
	end

	return commandByKey
end

local function buildCommandNameLookup(commandByKey)
	local lookup = {}

	for key, command in pairs(commandByKey) do
		lookup[command.command] = key
		for i = 1, #command.aliases do
			local alias = command.aliases[i]
			if lookup[alias] == nil then
				lookup[alias] = key
			end
		end
	end

	return lookup
end

local function buildRoutingOverrides(overrides, channelById)
	local normalized = {}
	if type(overrides) ~= 'table' then
		return normalized
	end

	for rawKey, rawChannel in pairs(overrides) do
		local key = normalizeKey(rawKey)
		local channelId = normalizeKey(rawChannel)
		if key and channelId and channelById[channelId] then
			normalized[key] = channelId
		end
	end

	return normalized
end

local function resolveCommandChannel(commandName)
	local state = Client.state
	local constants = Client.constants
	if not state or not constants then
		return 'global'
	end

	local normalized = normalizeKey(commandName)
	if not normalized then
		return constants.defaultChannelId or 'global'
	end

	local commandKey = constants.commandNameToKey[normalized]
	if commandKey then
		local mapped = constants.commandRoutingOverrides[commandKey]
		if mapped and constants.channelById[mapped] then
			return mapped
		end

		local command = constants.commandByKey[commandKey]
		if command and constants.channelById[command.channel] then
			return command.channel
		end
	end

	local explicit = constants.commandRoutingOverrides[normalized]
	if explicit and constants.channelById[explicit] then
		return explicit
	end

	return constants.defaultChannelId or 'global'
end

local function setCommandContext(commandName)
	local state = Client.state
	local constants = Client.constants
	if not state or not constants then
		return
	end

	local normalized = normalizeKey(commandName)
	if not normalized then
		return
	end

	state.LastCommandContext = {
		command = normalized,
		channel = resolveCommandChannel(normalized),
		expiresAt = GetGameTimer() + (constants.commandResponseWindowMs or 1500)
	}
end

local function getActiveCommandContextChannel()
	local state = Client.state
	if not state or type(state.LastCommandContext) ~= 'table' then
		return nil
	end

	if GetGameTimer() > (state.LastCommandContext.expiresAt or 0) then
		state.LastCommandContext = nil
		return nil
	end

	return state.LastCommandContext.channel
end

local function canAccessChannel(channelId)
	local state = Client.state
	local constants = Client.constants
	if not state or not constants then
		return false
	end

	local normalized = normalizeKey(channelId)
	if not normalized then
		return false
	end

	local channel = constants.channelById[normalized]
	if not channel then
		return false
	end

	local allowed = state.Permissions.channels and state.Permissions.channels[normalized]
	if allowed == nil then
		if channel.requiresAce then
			return false
		end
		return true
	end

	return allowed == true
end

local function setupBootstrap()
	if bootstrapInitialized then
		return
	end

	local chatConfig = Config.Chat or {}
	local uiConfig = Config.UI or {}
	local emojiConfig = Config.Emoji or {}
	local typingConfig = Config.TypingIndicator or {}
	local bubbleConfig = Config.ChatBubbles or {}
	local distanceConfig = Config.Distance or {}
	local distanceUiConfig = type(distanceConfig.ui) == 'table' and distanceConfig.ui or {}
	local runtimeConfig = Config.Runtime or {}
	local clientRuntime = type(runtimeConfig.client) == 'table' and runtimeConfig.client or {}
	local accessConfig = Config.Access or {}
	local channelsConfig = type(Config.Channels) == 'table' and Config.Channels or {}
	local commandsConfig = type(Config.Commands) == 'table' and Config.Commands or {}
	local commandRoutingConfig = type(Config.CommandRouting) == 'table' and Config.CommandRouting or {}
	local whispersConfig = type(Config.Whispers) == 'table' and Config.Whispers or {}

	local channelList, channelById, channelIdByName, channelNameById = buildChannelDefinitions(channelsConfig, chatConfig, accessConfig)
	local keepLegacyAliases = commandRoutingConfig.keepLegacyAliases ~= false
	local commandByKey = buildCommandDefinitions(commandsConfig, keepLegacyAliases)
	local commandNameToKey = buildCommandNameLookup(commandByKey)

	local defaultChannelId = normalizeKey(commandRoutingConfig.defaultChannel) or 'global'
	if not channelById[defaultChannelId] then
		if channelById.global then
			defaultChannelId = 'global'
		elseif channelList[1] then
			defaultChannelId = channelList[1].id
		else
			defaultChannelId = 'global'
		end
	end

	local separateChannelTabs = uiConfig.separateChannelTabs ~= false
	local singleChannelId = normalizeKey(uiConfig.singleChannelId) or 'local'
	if not channelById[singleChannelId] then
		singleChannelId = defaultChannelId
	end

	local whisperTabEnabled = whispersConfig.separateWhisperTab ~= false
	local whisperFallbackChannelId = normalizeKey(whispersConfig.fallbackChannel) or defaultChannelId
	if whisperFallbackChannelId == 'whispers' or not channelById[whisperFallbackChannelId] then
		whisperFallbackChannelId = defaultChannelId
	end

	if not whisperTabEnabled then
		local whispersChannel = channelById.whispers
		if whispersChannel then
			whispersChannel.visible = false
			whispersChannel.cycle = false
		end
	end

	if not whisperTabEnabled and defaultChannelId == 'whispers' then
		defaultChannelId = whisperFallbackChannelId
	end

	if not separateChannelTabs then
		if singleChannelId == 'whispers' and not whisperTabEnabled then
			singleChannelId = whisperFallbackChannelId
		end
		if not channelById[singleChannelId] then
			singleChannelId = defaultChannelId
		end
		defaultChannelId = singleChannelId
	end

	for _, command in pairs(commandByKey) do
		if not channelById[command.channel] then
			command.channel = defaultChannelId
		end
	end

	local commandRoutingOverrides = buildRoutingOverrides(commandRoutingConfig.overrides, channelById)
	if not whisperTabEnabled then
		local whisperRoutingKeys = {'whisper', 'dm', 'msg', 'reply', 'r'}
		for i = 1, #whisperRoutingKeys do
			commandRoutingOverrides[whisperRoutingKeys[i]] = whisperFallbackChannelId
		end

		if commandByKey.whisper then
			commandByKey.whisper.channel = whisperFallbackChannelId
		end
		if commandByKey.reply then
			commandByKey.reply.channel = whisperFallbackChannelId
		end
	end
	local commandResponseWindowMs = math.max(100, tonumber(commandRoutingConfig.responseWindowMs) or 1500)

	local whisperNotifications = type(whispersConfig.notifications) == 'table' and whispersConfig.notifications or {}
	local whisperSidebar = type(whispersConfig.sidebar) == 'table' and whispersConfig.sidebar or {}

	Client.config = {
		chat = chatConfig,
		ui = uiConfig,
		emoji = emojiConfig,
		typing = typingConfig,
		bubble = bubbleConfig,
		distance = distanceConfig,
		distanceUi = distanceUiConfig,
		runtime = clientRuntime,
		channels = channelsConfig,
		commands = commandsConfig,
		commandRouting = commandRoutingConfig,
		whispers = whispersConfig
	}

	Client.constants = {
		channelList = channelList,
		channelById = channelById,
		channelIdByName = channelIdByName,
		channelNameById = channelNameById,
		defaultChannelId = defaultChannelId,
		commandByKey = commandByKey,
		commandNameToKey = commandNameToKey,
		commandRoutingOverrides = commandRoutingOverrides,
		commandResponseWindowMs = commandResponseWindowMs,
		whisperTabEnabled = whisperTabEnabled,
		whisperFallbackChannelId = whisperFallbackChannelId,
		separateChannelTabs = separateChannelTabs,
		singleChannelId = singleChannelId,
		autoScrollDefault = uiConfig.autoScrollDefault ~= false,
		whisperNotificationDefaultEnabled = whisperNotifications.enabled ~= false,
		whisperNotificationVolume = clamp(tonumber(whisperNotifications.volume) or 0.65, 0.0, 1.0),
		whisperNotificationSoundName = tostring(whisperNotifications.soundName or 'SELECT'),
		whisperNotificationSoundSet = tostring(whisperNotifications.soundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET'),
		whisperSidebarCollapsible = whisperSidebar.collapsible ~= false,
		whisperSidebarDefaultCollapsed = whisperSidebar.defaultCollapsed == true,
		chatOpenControl = tonumber(clientRuntime.chatOpenControl) or 245,
		suggestionBatchSize = math.max(1, tonumber(clientRuntime.suggestionBatchSize) or 200),
		mainLoopIdleMs = math.max(0, tonumber(clientRuntime.mainLoopIdleMs) or 0),
		overheadIdleMs = math.max(1, tonumber(clientRuntime.overheadIdleMs) or 250),
		resourceRefreshDelayMs = math.max(0, tonumber(clientRuntime.resourceRefreshDelayMs) or 500),
		pmaStartDelayMs = math.max(0, tonumber(clientRuntime.pmaStartDelayMs) or 300)
	}

	Client.state = {
		chatInputActive = false,
		chatInputActivating = false,
		chatHidden = true,
		chatLoaded = false,
		Channel = defaultChannelId,
		HideChat = false,
		MutedPlayers = {},
		EmojiUsage = {},
		EmojiRecent = {},
		DisplayMessagesAbovePlayers = uiConfig.displayOverheadByDefault == true,
		OverheadMessages = {},
		OverheadUpdateIntervalMs = math.max(1, tonumber(uiConfig.overheadUpdateMs) or 50),
		EmojiRecentLimit = math.max(1, tonumber(emojiConfig.recentLimit) or 10),
		EmojiTopLimit = math.max(1, tonumber(emojiConfig.topLimit) or 10),
		ReplyTo = nil,
		LastCommandContext = nil,
		Permissions = {
			canAccessStaffChannel = false,
			channels = {}
		},
		typingSystemEnabled = typingConfig.enabled == true,
		typingToggleAllowed = typingConfig.enabled == true and typingConfig.allowPlayerToggle == true,
		typingDisplayEnabled = typingConfig.enabled == true,
		localTypingActive = false,
		localTypingLastSent = 0,
		typingRemoteStates = {},
		bubbleSystemEnabled = bubbleConfig.enabled == true,
		bubbleToggleAllowed = bubbleConfig.enabled == true and bubbleConfig.allowPlayerToggle == true,
		bubbleDisplayEnabled = bubbleConfig.enabled == true,
		whisperSoundToggleAllowed = true,
		whisperSoundEnabled = whisperNotifications.enabled ~= false,
		autoScrollToggleAllowed = true,
		autoScrollEnabled = uiConfig.autoScrollDefault ~= false,
		distanceEnabled = type(distanceConfig) == 'table' and distanceConfig.enabled == true,
		distanceExpressionCache = {},
		distanceObservedRanges = {},
		distanceModeCount = nil,
		distanceLastPayload = nil,
		distanceState = {
			enabled = false,
			value = tonumber(distanceConfig.default) or 10.0,
			label = tostring(tonumber(distanceConfig.default) or 10.0),
			color = '#95a5a6',
			percent = 0,
			modeIndex = nil,
			modeCount = nil,
			ranges = {}
		},
		emojiAliasesByGlyph = {},
		emojiEntries = {},
		sortedEmojiCache = nil,
		sortedEmojiDirty = true,
		emojiDataset = {
			categories = {}
		}
	}

	local state = Client.state
	state.ActionMessageColor = normalizeRgbColor(chatConfig.actionColor, {200, 0, 255})
	state.LocalMessageColor = normalizeRgbColor(chatConfig.localColor, {0, 153, 204})
	state.GlobalMessageColor = normalizeRgbColor(chatConfig.globalColor, {212, 175, 55})
	state.StaffMessageColor = normalizeRgbColor(chatConfig.staffColor, {255, 64, 0})
	state.WhisperColor = normalizeRgbColor(chatConfig.whisperColor, {254, 127, 156})
	state.WhisperEchoColor = normalizeRgbColor(chatConfig.whisperEchoColor, {204, 77, 106})
	state.ActionMessageDistance = tonumber(chatConfig.actionDistance) or 50.0
	state.LocalMessageDistance = tonumber(chatConfig.localDistance) or 50.0

	IsInProximity = isInProximity
	bootstrapInitialized = true
end

Client.setupBootstrap = setupBootstrap
Client.decodeJson = decodeJson
Client.encodeAndStore = encodeAndStore
Client.normalizeKey = normalizeKey
Client.normalizeRgbColor = normalizeRgbColor
Client.addChatMessage = addChatMessage
Client.clamp = clamp
Client.hexColorToRgb = hexColorToRgb
Client.getOffset = getOffset
Client.sendNuiMessage = sendNuiMessage
Client.isInProximity = isInProximity
Client.resolveCommandChannel = resolveCommandChannel
Client.setCommandContext = setCommandContext
Client.getActiveCommandContextChannel = getActiveCommandContextChannel
Client.canAccessChannel = canAccessChannel
