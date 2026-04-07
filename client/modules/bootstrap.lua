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
	me = {'me'},
	staff = {'staff'},
	whisper = {'whisper', 'w', 'msg', 'dm'},
	reply = {'reply', 'r'},
	clear = {'clear'},
	togglechat = {'togglechat'},
	toggleoverhead = {'toggleoverhead'},
	toggletyping = {'toggletyping'},
	togglebubbles = {'togglebubbles'},
	togglesound = {'togglesound', 'sound'},
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

local function collectVoiceIntermediateColors(raw)
	local result = {}

	local function appendColor(value)
		if value == nil then
			return
		end
		local color = tostring(value):gsub('%s+', '')
		if color ~= '' then
			result[#result + 1] = color
		end
	end

	local direct = raw.intermediate
	if type(direct) == 'table' then
		for i = 1, #direct do
			appendColor(direct[i])
		end
	elseif direct ~= nil then
		appendColor(direct)
	end

	local indexed = {}
	for key, value in pairs(raw) do
		local keyName = normalizeKey(tostring(key))
		local numericKey = keyName and keyName:match('^intermediate[_%-]?(%d+)$') or nil
		if numericKey then
			indexed[#indexed + 1] = {
				index = tonumber(numericKey) or 0,
				value = value
			}
		end
	end

	table.sort(indexed, function(a, b)
		if a.index == b.index then
			return tostring(a.value or '') < tostring(b.value or '')
		end
		return a.index < b.index
	end)

	for i = 1, #indexed do
		appendColor(indexed[i].value)
	end

	return result
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

local function buildChannelDefinitions(channelsConfig, defaultStaffAce)
	local defaults = {
		["local"] = {
			label = 'Local',
			color = {0, 153, 204},
			order = 10,
			visible = true,
			cycle = true,
			canSend = true,
			requiresAce = nil,
			maxHistory = 250,
			scope = 'proximity',
			distance = 50.0
		},
		global = {
			label = 'Global',
			color = {212, 175, 55},
			order = 20,
			visible = true,
			cycle = true,
			canSend = true,
			requiresAce = nil,
			maxHistory = 300,
			scope = 'global',
			distance = nil
		},
		staff = {
			label = 'Staff',
			color = {255, 64, 0},
			order = 30,
			visible = true,
			cycle = true,
			canSend = true,
			requiresAce = tostring(defaultStaffAce or 'chat.staffChannel'),
			maxHistory = 250,
			scope = 'permission',
			distance = nil
		},
		whispers = {
			label = 'Whispers',
			color = {254, 127, 156},
			order = 40,
			visible = true,
			cycle = true,
			canSend = true,
			requiresAce = nil,
			maxHistory = 250,
			scope = 'whisper',
			distance = nil
		}
	}

	local merged = {}

	for channelId, defaultEntry in pairs(defaults) do
		local override = type(channelsConfig[channelId]) == 'table' and channelsConfig[channelId] or {}
		local explicitPermission = override.permission
		merged[channelId] = {
			id = channelId,
			label = tostring(override.label or defaultEntry.label),
			color = normalizeRgbColor(override.color, defaultEntry.color),
			order = tonumber(override.order) or defaultEntry.order,
			visible = override.visible ~= false,
			cycle = override.cycle ~= false,
			canSend = override.canSend ~= false,
			requiresAce = type(explicitPermission) == 'string' and explicitPermission ~= '' and explicitPermission or defaultEntry.requiresAce,
			maxHistory = normalizeHistoryLimit(override.history, defaultEntry.maxHistory),
			scope = normalizeKey(override.scope) or defaultEntry.scope,
			distance = tonumber(override.distance) or defaultEntry.distance
		}
	end

	for rawId, rawEntry in pairs(channelsConfig) do
		local channelId = normalizeKey(rawId)
		if channelId and type(rawEntry) == 'table' and not merged[channelId] then
			local explicitPermission = rawEntry.permission
			merged[channelId] = {
				id = channelId,
				label = tostring(rawEntry.label or channelId),
				color = normalizeRgbColor(rawEntry.color, {255, 255, 255}),
				order = tonumber(rawEntry.order) or 100,
				visible = rawEntry.visible ~= false,
				cycle = rawEntry.cycle ~= false,
				canSend = rawEntry.canSend ~= false,
				requiresAce = type(explicitPermission) == 'string' and explicitPermission ~= '' and explicitPermission or nil,
				maxHistory = normalizeHistoryLimit(rawEntry.history, 250),
				scope = normalizeKey(rawEntry.scope) or 'global',
				distance = tonumber(rawEntry.distance)
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

local function canSendToChannel(channelId)
	local constants = Client.constants
	if not constants or not constants.channelById then
		return false
	end

	local normalized = normalizeKey(channelId)
	if not normalized then
		return false
	end

	if not canAccessChannel(normalized) then
		return false
	end

	local channel = constants.channelById[normalized]
	if not channel then
		return false
	end

	return channel.canSend ~= false
end

local function normalizeDefaultTabGrouping(rawGroups, channelList, channelById)
	local result = {}
	local seen = {}
	local nextGroupId = 1

	if type(rawGroups) == 'table' then
		for i = 1, #rawGroups do
			local rawGroup = rawGroups[i]
			if type(rawGroup) == 'table' then
				local groupMembers = {}
				for j = 1, #rawGroup do
					local channelId = normalizeKey(rawGroup[j])
					if channelId and channelById[channelId] and not seen[channelId] then
						groupMembers[#groupMembers + 1] = channelId
						seen[channelId] = true
					end
				end

				if #groupMembers > 0 then
					for j = 1, #groupMembers do
						result[groupMembers[j]] = nextGroupId
					end
					nextGroupId = nextGroupId + 1
				end
			end
		end
	end

	for i = 1, #channelList do
		local channelId = channelList[i].id
		if not result[channelId] then
			result[channelId] = nextGroupId
			nextGroupId = nextGroupId + 1
		end
	end

	return result
end

local function normalizeNotificationProfile(rawValue, fallback)
	local base = type(fallback) == 'table' and fallback or {}
	local entry = type(rawValue) == 'table' and rawValue or {}
	local soundEntry = type(entry.sound) == 'table' and entry.sound or {}
	local fallbackSoundEntry = type(entry.fallbackSound) == 'table' and entry.fallbackSound or {}
	local baseSound = type(base.sound) == 'table' and base.sound or {}
	local baseFallbackSound = type(base.fallbackSound) == 'table' and base.fallbackSound or {}

	local volume = tonumber(entry.volume)
	if volume == nil then
		volume = tonumber(base.volume)
	end
	if volume == nil then
		volume = 0.65
	end

	local enabled
	if entry.enabled == nil then
		enabled = base.enabled ~= false
	else
		enabled = entry.enabled ~= false
	end

	return {
		enabled = enabled,
		volume = clamp(volume, 0.0, 1.0),
		sound = {
			name = tostring(soundEntry.name or baseSound.name or 'SELECT'),
			set = tostring(soundEntry.set or baseSound.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
		},
		fallbackSound = {
			name = tostring(fallbackSoundEntry.name or baseFallbackSound.name or 'SELECT'),
			set = tostring(fallbackSoundEntry.set or baseFallbackSound.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
		}
	}
end

local function setupBootstrap()
	if bootstrapInitialized then
		return
	end

	local rootConfig = type(Config) == 'table' and Config or {}
	local settingsConfig = type(rootConfig.settings) == 'table' and rootConfig.settings or {}
	local uiConfig = type(rootConfig.ui) == 'table' and rootConfig.ui or {}
	local uiOverheadConfig = type(uiConfig.overhead) == 'table' and uiConfig.overhead or {}
	local emojiConfig = type(rootConfig.emoji) == 'table' and rootConfig.emoji or {}
	local featureConfig = type(rootConfig.features) == 'table' and rootConfig.features or {}
	local rawTypingConfig = type(featureConfig.typing) == 'table' and featureConfig.typing or {}
	local rawBubbleConfig = type(featureConfig.bubbles) == 'table' and featureConfig.bubbles or {}
	local voiceConfig = type(rootConfig.voice) == 'table' and rootConfig.voice or {}
	local voiceColorConfig = type(voiceConfig.colors) == 'table' and voiceConfig.colors or {}
	local runtimeConfig = type(rootConfig.runtime) == 'table' and rootConfig.runtime or {}
	local clientRuntime = type(runtimeConfig.client) == 'table' and runtimeConfig.client or {}
	local accessConfig = type(rootConfig.access) == 'table' and rootConfig.access or {}
	local channelsConfig = type(rootConfig.channels) == 'table' and rootConfig.channels or {}
	local commandsConfig = type(rootConfig.commands) == 'table' and rootConfig.commands or {}
	local routingConfig = type(rootConfig.routing) == 'table' and rootConfig.routing or {}
	local whispersConfig = type(rootConfig.whispers) == 'table' and rootConfig.whispers or {}
	local tabsConfig = type(rootConfig.tabs) == 'table' and rootConfig.tabs or {}
	local notificationsConfig = type(rootConfig.notifications) == 'table' and rootConfig.notifications or {}
	local messagesConfig = type(rootConfig.messages) == 'table' and rootConfig.messages or {}
	local actionMessageConfig = type(messagesConfig.action) == 'table' and messagesConfig.action or {}

	uiConfig.displayOverheadByDefault = uiOverheadConfig.enabledByDefault == true
	uiConfig.overheadDistance = tonumber(uiOverheadConfig.distance) or tonumber(uiConfig.overheadDistance) or 50.0
	uiConfig.overheadMinMs = tonumber(uiOverheadConfig.minMs) or tonumber(uiConfig.overheadMinMs) or 5000
	uiConfig.overheadMaxMs = tonumber(uiOverheadConfig.maxMs) or tonumber(uiConfig.overheadMaxMs) or 10000
	uiConfig.overheadPerCharMs = tonumber(uiOverheadConfig.perCharMs) or tonumber(uiConfig.overheadPerCharMs) or 200
	uiConfig.overheadUpdateMs = tonumber(uiOverheadConfig.updateMs) or tonumber(uiConfig.overheadUpdateMs) or 50

	local typingConfig = {
		enabled = rawTypingConfig.enabled == true,
		allowPlayerToggle = rawTypingConfig.allowToggle == true,
		maxDistance = tonumber(rawTypingConfig.maxDistance) or 25.0,
		updateRate = tonumber(rawTypingConfig.updateRate) or 200,
		style = tostring(rawTypingConfig.style or 'dots'),
		offset = rawTypingConfig.offset,
		headTracking = rawTypingConfig.headTracking == true,
		headLift = tonumber(rawTypingConfig.headLift),
		screenLift = tonumber(rawTypingConfig.screenLift) or 0.0
	}

	local bubbleConfig = {
		enabled = rawBubbleConfig.enabled == true,
		allowPlayerToggle = rawBubbleConfig.allowToggle == true,
		maxDistance = tonumber(rawBubbleConfig.maxDistance) or 25.0,
		fadeOutTime = tonumber(rawBubbleConfig.fadeOutMs) or 4000,
		maxLength = tonumber(rawBubbleConfig.maxLength) or 80,
		use3DText = rawBubbleConfig.use3DText ~= false,
		offset = rawBubbleConfig.offset
	}

	local channelList, channelById, channelIdByName, channelNameById = buildChannelDefinitions(channelsConfig, accessConfig.staffChannelAce)
	local keepLegacyAliases = routingConfig.keepLegacyAliases == true
	local commandByKey = buildCommandDefinitions(commandsConfig, keepLegacyAliases)
	local commandNameToKey = buildCommandNameLookup(commandByKey)

	local defaultChannelId = normalizeKey(routingConfig.defaultChannel) or 'global'
	if not channelById[defaultChannelId] then
		if channelById.global then
			defaultChannelId = 'global'
		elseif channelList[1] then
			defaultChannelId = channelList[1].id
		else
			defaultChannelId = 'global'
		end
	end

	local separateChannelTabs = true
	local singleChannelId = defaultChannelId

	local whisperTabEnabled = whispersConfig.tabEnabled ~= false
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

	for _, command in pairs(commandByKey) do
		if not channelById[command.channel] then
			command.channel = defaultChannelId
		end
	end

	local commandRoutingOverrides = buildRoutingOverrides(routingConfig.overrides, channelById)
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
	local commandResponseWindowMs = math.max(100, tonumber(routingConfig.responseWindowMs) or 1500)

	local whisperSidebar = type(whispersConfig.sidebar) == 'table' and whispersConfig.sidebar or {}
	local whisperLegacyNotification = type(whispersConfig.notification) == 'table' and whispersConfig.notification or {}

	local notificationDefaultRaw = type(notificationsConfig.default) == 'table' and notificationsConfig.default or {}
	local legacyWhisperSound = type(whisperLegacyNotification.sound) == 'table' and whisperLegacyNotification.sound or {}
	local legacyWhisperFallbackSound = type(whisperLegacyNotification.fallbackSound) == 'table' and whisperLegacyNotification.fallbackSound or {}
	local notificationDefaultProfile = normalizeNotificationProfile(notificationDefaultRaw, {
		enabled = true,
		volume = tonumber(whisperLegacyNotification.volume) or 0.65,
		sound = {
			name = tostring(legacyWhisperSound.name or 'SELECT'),
			set = tostring(legacyWhisperSound.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
		},
		fallbackSound = {
			name = tostring(legacyWhisperFallbackSound.name or 'SELECT'),
			set = tostring(legacyWhisperFallbackSound.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
		}
	})

	local notificationByChannel = {}
	local notificationTabs = type(notificationsConfig.tabs) == 'table' and notificationsConfig.tabs or {}
	for i = 1, #channelList do
		local channelId = channelList[i].id
		local profile = notificationTabs[channelId]
		if profile == nil and channelId == 'whispers' and whisperLegacyNotification.enabled ~= nil then
			profile = whisperLegacyNotification
		end
		notificationByChannel[channelId] = normalizeNotificationProfile(profile, notificationDefaultProfile)
	end

	local whisperNotificationProfile = notificationByChannel.whispers or notificationDefaultProfile

	local defaultTabGrouping = normalizeDefaultTabGrouping(tabsConfig.defaultGroups, channelList, channelById)
	local defaultTabGroupingState = {}
	for channelId, groupId in pairs(defaultTabGrouping) do
		defaultTabGroupingState[channelId] = groupId
	end

	local voiceResourceName = normalizeKey(tostring(voiceConfig.resource or 'pma-voice')) or 'pma-voice'
	local voiceFallbackLocalDistance = tonumber(voiceConfig.fallbackLocalDistance)
	if not voiceFallbackLocalDistance or voiceFallbackLocalDistance <= 0 then
		voiceFallbackLocalDistance = tonumber(((channelsConfig["local"] or {}).distance)) or 50.0
	end

	local voiceIntermediateColors = collectVoiceIntermediateColors(voiceColorConfig)

	Client.config = {
		settings = settingsConfig,
		messages = messagesConfig,
		ui = uiConfig,
		emoji = emojiConfig,
		typing = typingConfig,
		bubble = bubbleConfig,
		voice = voiceConfig,
		runtime = clientRuntime,
		access = accessConfig,
		channels = channelsConfig,
		commands = commandsConfig,
		commandRouting = routingConfig,
		whispers = whispersConfig,
		tabs = tabsConfig,
		notifications = notificationsConfig
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
		defaultTabGrouping = defaultTabGrouping,
		notificationDefaultProfile = notificationDefaultProfile,
		notificationByChannel = notificationByChannel,
		whisperNotificationDefaultEnabled = whisperNotificationProfile.enabled ~= false,
		whisperNotificationVolume = clamp(tonumber(whisperNotificationProfile.volume) or 0.65, 0.0, 1.0),
		whisperNotificationSoundName = tostring((whisperNotificationProfile.sound or {}).name or 'SELECT'),
		whisperNotificationSoundSet = tostring((whisperNotificationProfile.sound or {}).set or 'HUD_FRONTEND_DEFAULT_SOUNDSET'),
		whisperNotificationFallbackSoundName = tostring((whisperNotificationProfile.fallbackSound or {}).name or 'SELECT'),
		whisperNotificationFallbackSoundSet = tostring((whisperNotificationProfile.fallbackSound or {}).set or 'HUD_FRONTEND_DEFAULT_SOUNDSET'),
		voiceEnabled = voiceConfig.enabled == true,
		voiceResourceName = voiceResourceName,
		voiceFallbackLocalDistance = voiceFallbackLocalDistance,
		voiceColorMin = tostring(voiceColorConfig.colorMin or '#2e85cc'),
		voiceColorIntermediate = voiceIntermediateColors,
		voiceColorMax = tostring(voiceColorConfig.colorMax or '#e74c3c'),
		voicePollRate = math.max(100, tonumber(voiceConfig.pollRate) or 250),
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
		DisplayMessagesAbovePlayers = uiOverheadConfig.enabledByDefault == true,
		OverheadMessages = {},
		OverheadUpdateIntervalMs = math.max(1, tonumber(uiOverheadConfig.updateMs) or 50),
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
		whisperSoundEnabled = whisperNotificationProfile.enabled ~= false,
		autoScrollToggleAllowed = true,
		autoScrollEnabled = uiConfig.autoScrollDefault ~= false,
		TabGrouping = defaultTabGroupingState,
		TabNotificationToggles = {},
		distanceEnabled = voiceConfig.enabled == true,
		voiceAvailable = false,
		voiceModes = {},
		voiceModeLabels = {},
		voiceLevelColors = {},
		voiceErrorShown = false,
		distanceModeCount = nil,
		distanceLastPayload = nil,
		distanceState = {
			enabled = false,
			value = voiceFallbackLocalDistance,
			label = tostring(voiceFallbackLocalDistance),
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
	local localChannel = channelById["local"] or {}
	local globalChannel = channelById.global or {}
	local staffChannel = channelById.staff or {}
	local whisperChannel = channelById.whispers or {}
	state.ActionMessageColor = normalizeRgbColor(actionMessageConfig.color, {200, 0, 255})
	state.LocalMessageColor = normalizeRgbColor(localChannel.color, {0, 153, 204})
	state.GlobalMessageColor = normalizeRgbColor(globalChannel.color, {212, 175, 55})
	state.StaffMessageColor = normalizeRgbColor(staffChannel.color, {255, 64, 0})
	state.WhisperColor = normalizeRgbColor(whisperChannel.color, {254, 127, 156})
	state.WhisperEchoColor = normalizeRgbColor(messagesConfig.whisperOutgoingColor, {204, 77, 106})
	state.ActionMessageDistance = tonumber(actionMessageConfig.distance) or 50.0
	state.LocalMessageDistance = voiceFallbackLocalDistance

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
Client.canSendToChannel = canSendToChannel
