PoodleChatServer = PoodleChatServer or {}

local Server = PoodleChatServer
local bootstrapInitialized = false
local constants = nil
local nicknames = nil
local identifierCache = nil
local typingStateBySource = nil

local logColors = {
	name = '\x1B[35m',
	default = '\x1B[0m',
	error = '\x1B[31m',
	success = '\x1B[32m',
	warning = '\x1B[33m'
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
	report = {'report'},
	mute = {'mute'},
	unmute = {'unmute'},
	muted = {'muted'},
	nick = {'nick'}
}

local function log(label, message)
	local color = logColors[label] or logColors.default
	print(string.format('%s[%s]%s %s', color, label, logColors.default, message))
end

local function decodeTableOrEmpty(value)
	if not value then
		return {}
	end

	local ok, decoded = pcall(json.decode, value)
	if ok and type(decoded) == 'table' then
		return decoded
	end

	return {}
end

local function isSet(value)
	return value ~= nil and tostring(value) ~= ''
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

local function toDiscordColor(value, fallback)
	if type(value) == 'number' then
		return math.floor(value)
	end

	if type(value) == 'table' then
		local r = clampColorChannel(value[1] or value.r)
		local g = clampColorChannel(value[2] or value.g)
		local b = clampColorChannel(value[3] or value.b)
		return r * 65536 + g * 256 + b
	end

	return fallback
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

local function appendUnique(list, seen, value)
	local normalized = normalizeKey(value)
	if not normalized then
		return
	end

	if seen[normalized] then
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
			requiresAce = isSet(explicitPermission) and tostring(explicitPermission) or defaultEntry.requiresAce,
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
				requiresAce = isSet(explicitPermission) and tostring(explicitPermission) or nil,
				maxHistory = normalizeHistoryLimit(rawEntry.history, 250),
				scope = normalizeKey(rawEntry.scope) or 'global',
				distance = tonumber(rawEntry.distance)
			}
		end
	end

	local list = {}
	local byId = {}

	for _, channel in pairs(merged) do
		list[#list + 1] = channel
		byId[channel.id] = channel
	end

	table.sort(list, sortByOrderThenId)

	return list, byId
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
					permission = isSet(rawEntry.permission) and tostring(rawEntry.permission) or nil,
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

local function canAccessChannel(source, channelId)
	local id = normalizeKey(channelId)
	if not id then
		return false
	end

	local channel = constants and constants.ChannelById and constants.ChannelById[id] or nil
	if not channel then
		return false
	end

	local requiredAce = isSet(channel.requiresAce) and tostring(channel.requiresAce) or nil
	if not requiredAce then
		return true
	end

	return IsPlayerAceAllowed(source, requiredAce)
end

local function getChannelById(channelId)
	local id = normalizeKey(channelId)
	if not id then
		return nil
	end

	return constants and constants.ChannelById and constants.ChannelById[id] or nil
end

local function getDefaultChannelId()
	if constants and constants.DefaultChannelId then
		return constants.DefaultChannelId
	end
	return 'global'
end

local function getPlayerChannelPermissions(source)
	local result = {}
	if not constants or type(constants.ChannelList) ~= 'table' then
		return result
	end

	for i = 1, #constants.ChannelList do
		local channel = constants.ChannelList[i]
		result[channel.id] = canAccessChannel(source, channel.id)
	end

	return result
end

local function getDiscordColor(kind, fallback)
	local config = Server.config or {}
	local discordConfig = config.discord or {}
	local colors = type(discordConfig.colors) == 'table' and discordConfig.colors or {}
	local base = colors[kind]
	if base == nil then
		base = colors.default
	end
	return toDiscordColor(base, fallback)
end

local function isDiscordConfigured()
	local config = Server.config or {}
	local discordConfig = config.discord or {}
	return discordConfig.enabled == true and isSet(discordConfig.webhook)
end

local function isDiscordKindEnabled(kind)
	if not isDiscordConfigured() then
		return false
	end

	local config = Server.config or {}
	local discordConfig = config.discord or {}

	if kind == 'local' then
		return discordConfig.sendLocal == true
	end

	if kind == 'global' then
		return discordConfig.sendGlobal ~= false
	end

	if kind == 'staff' then
		return discordConfig.sendStaff == true
	end

	if kind == 'action' then
		return discordConfig.sendAction == true
	end

	if kind == 'join' or kind == 'leave' then
		return discordConfig.sendJoinLeave ~= false
	end

	if kind == 'report' then
		return discordConfig.sendReports ~= false
	end

	return false
end

local function sanitizeDiscordText(text)
	local value = tostring(text or '')
	value = value:gsub('@everyone', '`@everyone`')
	value = value:gsub('@here', '`@here`')
	return value
end

local function sendDiscordWebhook(kind, source, name, message, colorOverride, callback)
	if not isDiscordKindEnabled(kind) then
		return false
	end

	local config = Server.config or {}
	local discordConfig = config.discord or {}
	local webhook = tostring(discordConfig.webhook)
	local username = tostring(discordConfig.username or 'PoodleChat')
	local footer = tostring(discordConfig.footer or 'poodlechat')
	local displayName = tostring(name or 'Unknown')
	local authorName = displayName
	if source then
		local sourceText = tostring(source)
		if not string.find(displayName, '[' .. sourceText .. ']', 1, true) then
			authorName = displayName .. ' [' .. sourceText .. ']'
		end
	end
	local color = toDiscordColor(colorOverride, getDiscordColor(kind, 3447003))
	local payload = {
		username = username,
		embeds = {
			{
				author = {
					name = authorName
				},
				description = tostring(message or ''),
				color = color,
				footer = {
					text = footer
				},
				timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
			}
		}
	}

	PerformHttpRequest(webhook, function(statusCode, body, headers)
		local ok = statusCode and statusCode >= 200 and statusCode < 300

		if not ok then
			log('warning', ('Discord webhook failed (%s): %s'):format(tostring(statusCode), tostring(body)))
		end

		if callback then
			callback(ok, statusCode, body, headers)
		end
	end, 'POST', json.encode(payload), {
		['Content-Type'] = 'application/json'
	})

	return true
end

local function toPlayerKey(source)
	return tostring(source)
end

local function clearIdentifierCache(source)
	identifierCache[toPlayerKey(source)] = nil
end

local function getIdentifierMap(source)
	local key = toPlayerKey(source)
	local cached = identifierCache[key]

	if cached then
		return cached
	end

	local map = {}
	local identifiers = GetPlayerIdentifiers(source)

	if not identifiers or #identifiers == 0 then
		identifierCache[key] = map
		return map
	end

	for _, currentID in ipairs(identifiers) do
		local idType, idValue = currentID:match('^([^:]+):(.+)$')

		if idType and idValue then
			map[idType:lower()] = idValue:lower()
		end
	end

	identifierCache[key] = map
	return map
end

local function normalizeMessage(value)
	return tostring(value or '')
end

local function getIdFromSource(idType, source)
	local normalizedType = idType and tostring(idType):lower()
	if not normalizedType or not source then
		return nil
	end

	local identifiers = getIdentifierMap(source)
	return identifiers[normalizedType]
end

local function getNickname(source)
	if not constants then
		return nil
	end

	local identifier = getIdFromSource(constants.IdentifierType, source)
	if identifier then
		return nicknames[identifier]
	end
end

local function hasNickname(source)
	if not constants then
		return false
	end

	local identifier = getIdFromSource(constants.IdentifierType, source)
	if identifier then
		return nicknames[identifier] ~= nil
	end

	return false
end

local function setNickname(source, nickname)
	if not constants then
		return false
	end

	local identifier = getIdFromSource(constants.IdentifierType, source)
	if not identifier then
		return false
	end

	nicknames[identifier] = nickname
	SetResourceKvp('nicknames', json.encode(nicknames))
	return true
end

local function getRealName(source)
	local fallback = GetPlayerName(source) or '?'
	local resolver = constants and constants.AccessDisplayNameResolver or nil
	if type(resolver) ~= 'function' then
		return fallback
	end

	local ok, resolved = pcall(resolver, source, fallback)
	if not ok then
		log('warning', ('Display name resolver failed for %s: %s'):format(tostring(source), tostring(resolved)))
		return fallback
	end

	if type(resolved) ~= 'string' then
		return fallback
	end

	local normalized = resolved:gsub('^%s+', ''):gsub('%s+$', '')
	if normalized == '' then
		return fallback
	end

	return normalized
end

local function getName(source)
	if hasNickname(source) then
		return getNickname(source)
	end

	return getRealName(source)
end

local function getNameWithId(source)
	return '[' .. source .. '] ' .. getName(source)
end

local function registerCommandWithAliases(commandDef, callback, restricted)
	if type(commandDef) ~= 'table' or commandDef.enabled ~= true then
		return
	end

	local names = {}
	local seen = {}
	appendUnique(names, seen, commandDef.command)

	for i = 1, #commandDef.aliases do
		appendUnique(names, seen, commandDef.aliases[i])
	end

	for i = 1, #names do
		RegisterCommand(names[i], callback, restricted)
	end
end

local function registerNicknameCommand()
	local nickCommand = constants and constants.CommandByKey and constants.CommandByKey.nick or nil
	if type(nickCommand) ~= 'table' or nickCommand.enabled ~= true then
		return
	end

	registerCommandWithAliases(nickCommand, function(source, args)
		local nickname = args[1] and table.concat(args, ' ')

		if nickname and string.len(nickname) > constants.MaxNicknameLen then
			TriggerClientEvent('chat:addMessage', source, {
				channel = constants.DefaultChannelId,
				color = {255, 0, 0},
				args = {'Error', 'Nicknames cannot be more than ' .. constants.MaxNicknameLen .. ' characters long'}
			})
			return
		end

		if setNickname(source, nickname) then
			if nickname then
				TriggerClientEvent('chat:addMessage', source, {
					channel = constants.DefaultChannelId,
					color = {255, 255, 128},
					args = {'Your nickname was set to ' .. nickname}
				})
			else
				TriggerClientEvent('chat:addMessage', source, {
					channel = constants.DefaultChannelId,
					color = {255, 255, 128},
					args = {'Your nickname has been unset'}
				})
			end
		else
			TriggerClientEvent('chat:addMessage', source, {
				channel = constants.DefaultChannelId,
				color = {255, 0, 0},
				args = {'Error', 'Failed to set nickname'}
			})
		end
	end, true)
end

local function refreshCommands(player)
	if not GetRegisteredCommands then
		return
	end

	local registeredCommands = GetRegisteredCommands()
	local suggestions = {}

	for _, command in ipairs(registeredCommands) do
		if IsPlayerAceAllowed(player, ('command.%s'):format(command.name)) then
			suggestions[#suggestions + 1] = {
				name = '/' .. command.name,
				help = ''
			}
		end
	end

	TriggerClientEvent('chat:addSuggestions', player, suggestions)
end

local function getMessageLicense(source)
	if IsPlayerAceAllowed(source, constants.NoMuteAce) then
		return false
	end

	return getIdFromSource(constants.IdentifierType, source)
end

local function triggerClientEventForTargets(eventName, targets, ...)
	if not targets then
		TriggerClientEvent(eventName, -1, ...)
		return
	end

	for _, target in ipairs(targets) do
		TriggerClientEvent(eventName, tonumber(target) or target, ...)
	end
end

local function triggerClientEventForTargetsNoFallback(eventName, targets, ...)
	if not targets then
		return
	end

	for _, target in ipairs(targets) do
		TriggerClientEvent(eventName, tonumber(target) or target, ...)
	end
end

local function getNearbyPlayers(source, distance)
	if not distance then
		return nil
	end

	local sourcePed = GetPlayerPed(source)
	if sourcePed == 0 then
		return nil
	end

	local sourceCoords = GetEntityCoords(sourcePed)
	if not sourceCoords then
		return nil
	end

	local sourceId = tonumber(source)
	local sourceIdString = tostring(source)
	local maxDistance = distance * distance
	local nearby = {}

	for _, playerId in ipairs(GetPlayers()) do
		local playerIdNumber = tonumber(playerId)

		if playerId == sourceIdString or playerIdNumber == sourceId then
			nearby[#nearby + 1] = playerId
		else
			local ped = GetPlayerPed(playerId)
			if ped == 0 then
				goto continue
			end

			local coords = GetEntityCoords(ped)
			if not coords then
				goto continue
			end

			local dx = sourceCoords.x - coords.x
			local dy = sourceCoords.y - coords.y
			local dz = sourceCoords.z - coords.z
			local distanceSquared = dx * dx + dy * dy + dz * dz

			if distanceSquared <= maxDistance then
				nearby[#nearby + 1] = playerId
			end
		end

		::continue::
	end

	return nearby
end

local function getNameWithRoleAndColor(source)
	local name = getName(source)
	if constants and constants.RolePrefixEnabled ~= true then
		return '[' .. source .. '] ' .. name, nil
	end

	local role = nil
	local roles = constants.Roles

	for index = 1, #roles do
		local current = roles[index]
		if current and current.ace and IsPlayerAceAllowed(source, current.ace) then
			role = current
			break
		end
	end

	if role then
		return '[' .. source .. '] ' .. tostring(role.name or 'Role') .. ' | ' .. name, role.color
	end

	return '[' .. source .. '] ' .. name, nil
end

local function escapePattern(value)
	return value:gsub('([%(%)%.%%%+%-%*%?%[%^%$])', '%%%1')
end

local function setupBootstrap()
	if bootstrapInitialized then
		return
	end

	local rootConfig = type(Config) == 'table' and Config or {}
	local settingsConfig = type(rootConfig.settings) == 'table' and rootConfig.settings or {}
	local accessConfig = type(rootConfig.access) == 'table' and rootConfig.access or {}
	local featureConfig = type(rootConfig.features) == 'table' and rootConfig.features or {}
	local rawTypingConfig = type(featureConfig.typing) == 'table' and featureConfig.typing or {}
	local rawBubbleConfig = type(featureConfig.bubbles) == 'table' and featureConfig.bubbles or {}
	local discordConfig = type(rootConfig.discord) == 'table' and rootConfig.discord or {}
	local uiConfig = type(rootConfig.ui) == 'table' and rootConfig.ui or {}
	local channelsConfig = type(rootConfig.channels) == 'table' and rootConfig.channels or {}
	local commandsConfig = type(rootConfig.commands) == 'table' and rootConfig.commands or {}
	local routingConfig = type(rootConfig.routing) == 'table' and rootConfig.routing or {}
	local whispersConfig = type(rootConfig.whispers) == 'table' and rootConfig.whispers or {}
	local messagesConfig = type(rootConfig.messages) == 'table' and rootConfig.messages or {}
	local actionMessageConfig = type(messagesConfig.action) == 'table' and messagesConfig.action or {}
	local runtimeConfig = type(rootConfig.runtime) == 'table' and rootConfig.runtime or {}
	local serverRuntime = type(runtimeConfig.server) == 'table' and runtimeConfig.server or {}

	local typingConfig = {
		enabled = rawTypingConfig.enabled == true,
		updateRate = tonumber(rawTypingConfig.updateRate) or 200,
		maxDistance = tonumber(rawTypingConfig.maxDistance) or 25.0
	}

	local bubbleConfig = {
		enabled = rawBubbleConfig.enabled == true,
		maxDistance = tonumber(rawBubbleConfig.maxDistance) or 25.0,
		maxLength = tonumber(rawBubbleConfig.maxLength) or 80,
		fadeOutTime = tonumber(rawBubbleConfig.fadeOutMs) or 4000
	}

	local localChannelConfig = type(channelsConfig["local"]) == 'table' and channelsConfig["local"] or {}
	local globalChannelConfig = type(channelsConfig.global) == 'table' and channelsConfig.global or {}
	local staffChannelConfig = type(channelsConfig.staff) == 'table' and channelsConfig.staff or {}
	local whisperChannelConfig = type(channelsConfig.whispers) == 'table' and channelsConfig.whispers or {}

	local chatConfig = {
		maxNicknameLen = settingsConfig.maxNicknameLen,
		printToConsole = settingsConfig.printToConsole,
		localColor = localChannelConfig.color,
		globalColor = globalChannelConfig.color,
		staffColor = staffChannelConfig.color,
		whisperColor = whisperChannelConfig.color,
		whisperEchoColor = messagesConfig.whisperOutgoingColor,
		actionColor = actionMessageConfig.color,
		actionDistance = actionMessageConfig.distance,
		localDistance = localChannelConfig.distance
	}

	local identifierType = tostring(accessConfig.identifier or 'license')
	local staffChannelAce = tostring(accessConfig.staffChannelAce or 'chat.staffChannel')
	local noMuteAce = tostring(accessConfig.noMuteAce or 'chat.noMute')
	local roles = type(accessConfig.roles) == 'table' and accessConfig.roles or {}
	local rolePrefixEnabled = accessConfig.rolePrefixEnabled == true

	local maxNicknameLen = math.max(1, tonumber(chatConfig.maxNicknameLen) or 30)
	local printToConsole = chatConfig.printToConsole ~= false
	local localMessageColor = normalizeRgbColor(chatConfig.localColor, {0, 153, 204})
	local globalMessageColor = normalizeRgbColor(chatConfig.globalColor, {212, 175, 55})
	local staffMessageColor = normalizeRgbColor(chatConfig.staffColor, {255, 64, 0})
	local actionMessageDistance = tonumber(chatConfig.actionDistance) or 50.0
	local localMessageDistance = tonumber(chatConfig.localDistance) or 50.0

	local channelList, channelById = buildChannelDefinitions(channelsConfig, staffChannelAce)
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

	local separateChannelTabs = uiConfig.separateChannelTabs ~= false
	local singleChannelId = normalizeKey(uiConfig.singleChannelId) or 'local'
	if not channelById[singleChannelId] then
		singleChannelId = defaultChannelId
	end

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

	Server.config = {
		settings = settingsConfig,
		messages = messagesConfig,
		chat = chatConfig,
		access = accessConfig,
		typing = typingConfig,
		bubble = bubbleConfig,
		discord = discordConfig,
		runtime = serverRuntime,
		channels = channelsConfig,
		commands = commandsConfig,
		commandRouting = routingConfig,
		whispers = whispersConfig
	}

	Server.constants = {
		IdentifierType = identifierType,
		StaffChannelAce = staffChannelAce,
		NoMuteAce = noMuteAce,
		AccessDisplayNameResolver = type(accessConfig.getDisplayName) == 'function' and accessConfig.getDisplayName or nil,
		Roles = roles,
		RolePrefixEnabled = rolePrefixEnabled,
		MaxNicknameLen = maxNicknameLen,
		PrintToConsole = printToConsole,
		LocalMessageColor = localMessageColor,
		GlobalMessageColor = globalMessageColor,
		StaffMessageColor = staffMessageColor,
		ActionMessageDistance = actionMessageDistance,
		LocalMessageDistance = localMessageDistance,
		refreshCommandsDelayMs = math.max(0, tonumber(serverRuntime.refreshCommandsDelayMs) or 500),
		ChannelList = channelList,
		ChannelById = channelById,
		DefaultChannelId = defaultChannelId,
		CommandByKey = commandByKey,
		CommandNameToKey = commandNameToKey,
		CommandRoutingOverrides = commandRoutingOverrides,
		CommandResponseWindowMs = commandResponseWindowMs,
		WhisperTabEnabled = whisperTabEnabled,
		WhisperFallbackChannelId = whisperFallbackChannelId,
		SeparateChannelTabs = separateChannelTabs,
		SingleChannelId = singleChannelId
	}

	constants = Server.constants
	nicknames = decodeTableOrEmpty(GetResourceKvpString('nicknames'))
	identifierCache = {}
	typingStateBySource = {}

	Server.state = {
		nicknames = nicknames,
		identifierCache = identifierCache,
		typingStateBySource = typingStateBySource
	}

	Server.log = log
	Server.decodeTableOrEmpty = decodeTableOrEmpty
	Server.isSet = isSet
	Server.clampColorChannel = clampColorChannel
	Server.normalizeRgbColor = normalizeRgbColor
	Server.toDiscordColor = toDiscordColor
	Server.getDiscordColor = getDiscordColor
	Server.isDiscordConfigured = isDiscordConfigured
	Server.isDiscordKindEnabled = isDiscordKindEnabled
	Server.sanitizeDiscordText = sanitizeDiscordText
	Server.sendDiscordWebhook = sendDiscordWebhook
	Server.clearIdentifierCache = clearIdentifierCache
	Server.getIdentifierMap = getIdentifierMap
	Server.normalizeMessage = normalizeMessage
	Server.normalizeKey = normalizeKey
	Server.refreshCommands = refreshCommands
	Server.getMessageLicense = getMessageLicense
	Server.triggerClientEventForTargets = triggerClientEventForTargets
	Server.triggerClientEventForTargetsNoFallback = triggerClientEventForTargetsNoFallback
	Server.getNearbyPlayers = getNearbyPlayers
	Server.getNameWithRoleAndColor = getNameWithRoleAndColor
	Server.escapePattern = escapePattern
	Server.getIdFromSource = getIdFromSource
	Server.getNickname = getNickname
	Server.hasNickname = hasNickname
	Server.setNickname = setNickname
	Server.getRealName = getRealName
	Server.getName = getName
	Server.getNameWithId = getNameWithId
	Server.getChannelById = getChannelById
	Server.getDefaultChannelId = getDefaultChannelId
	Server.canAccessChannel = canAccessChannel
	Server.getPlayerChannelPermissions = getPlayerChannelPermissions
	Server.registerCommandWithAliases = registerCommandWithAliases
	Server.registerNicknameCommand = registerNicknameCommand

	GetIDFromSource = getIdFromSource
	GetNickname = getNickname
	HasNickname = hasNickname
	SetNickname = setNickname
	GetRealName = getRealName
	GetName = getName
	GetNameWithId = getNameWithId

	exports('getName', getName)
	bootstrapInitialized = true
end

Server.setupBootstrap = setupBootstrap
