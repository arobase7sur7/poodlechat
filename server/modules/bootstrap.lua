PoodleChatServer = PoodleChatServer or {}

local Server = PoodleChatServer
local bootstrapInitialized = false
local constants = nil
local nicknames = nil
local nicknameHistory = nil
local pinnedNicknames = nil
local identifierCache = nil
local typingStateBySource = nil
local citizenidCache = nil
local identitySnapshots = nil
local identityStateBySource = nil
local voiceDistanceBySource = nil
local deletedMessageRegistry = nil
local liveMessageRegistry = nil
local liveMessageRegistryOrder = nil
local messageSequence = 0

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
	["do"] = {'do'},
	staff = {'staff'},
	whisper = {'whisper', 'w', 'msg', 'dm'},
	reply = {'reply', 'r'},
	clear = {'clear'},
	clearhistory = {'clearhistory', 'clearhist'},
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
				canSend = rawEntry.canSend ~= false,
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

local function getQbCoreObject()
	local ok, qb = pcall(function()
		return exports['qb-core']:GetCoreObject()
	end)

	if not ok then
		return nil
	end

	return qb
end

local function hasAnyQbPermission(source, permissions)
	if not constants or constants.ModerationQbBridgeEnabled ~= true then
		return false
	end

	if type(permissions) ~= 'table' or #permissions == 0 then
		return false
	end

	local qb = getQbCoreObject()
	if not qb or not qb.Functions or type(qb.Functions.HasPermission) ~= 'function' then
		return false
	end

	for i = 1, #permissions do
		if qb.Functions.HasPermission(source, permissions[i]) then
			return true
		end
	end

	return false
end

local function hasModerationPermission(source, capability)
	if not constants then
		return false
	end

	local normalizedCapability = normalizeKey(capability)
	if not normalizedCapability then
		return false
	end

	if normalizedCapability == 'staff' then
		if isSet(constants.StaffChannelAce) and IsPlayerAceAllowed(source, constants.StaffChannelAce) then
			return true
		end

		return hasAnyQbPermission(source, constants.ModerationStaffQbPermissions)
	end

	if normalizedCapability == 'delete' then
		if isSet(constants.ModerationDeleteAce) and IsPlayerAceAllowed(source, constants.ModerationDeleteAce) then
			return true
		end

		return hasAnyQbPermission(source, constants.ModerationDeleteQbPermissions)
	end

	if normalizedCapability == 'viewdeleted' then
		if isSet(constants.ModerationViewDeletedAce) and IsPlayerAceAllowed(source, constants.ModerationViewDeletedAce) then
			return true
		end

		return hasModerationPermission(source, 'delete')
	end

	return false
end

local getPlayerChannelPermissions

local function getResolvedPlayerPermissions(source)
	return {
		channels = getPlayerChannelPermissions(source),
		moderation = {
			canAccessStaff = hasModerationPermission(source, 'staff'),
			canDeleteMessages = hasModerationPermission(source, 'delete'),
			canViewDeletedMessages = hasModerationPermission(source, 'viewdeleted'),
			builtInReportsEnabled = constants.BuiltInReportsEnabled == true
		}
	}
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

	if id == 'staff' and hasModerationPermission(source, 'staff') then
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

getPlayerChannelPermissions = function(source)
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

local function getDiscordWebhook(kind)
	local config = Server.config or {}
	local discordConfig = config.discord or {}
	local webhooks = type(discordConfig.webhooks) == 'table' and discordConfig.webhooks or {}
	local byKind = type(webhooks.byKind) == 'table' and webhooks.byKind or {}

	local direct = kind and byKind[kind] or nil
	if isSet(direct) then
		return tostring(direct)
	end

	if isSet(webhooks.default) then
		return tostring(webhooks.default)
	end

	if isSet(discordConfig.webhook) then
		return tostring(discordConfig.webhook)
	end

	return nil
end

local function isDiscordConfigured(kind)
	local config = Server.config or {}
	local discordConfig = config.discord or {}
	return discordConfig.enabled == true and isSet(getDiscordWebhook(kind))
end

local function isDiscordKindEnabled(kind)
	if not isDiscordConfigured(kind) then
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

	if kind == 'delete' then
		return discordConfig.sendDeletes ~= false
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
	local webhook = getDiscordWebhook(kind)
	if not webhook then
		return false
	end
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
	local normalized = tostring(value or ''):gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\n', '\\n')
	local lineBreakCount = 0

	normalized = normalized:gsub('\\n', function()
		lineBreakCount = lineBreakCount + 1
		if lineBreakCount <= 3 then
			return '\\n'
		end

		return ' '
	end)

	return normalized
end

local function normalizePermissionList(value)
	local list = {}
	if type(value) ~= 'table' then
		return list
	end

	for i = 1, #value do
		local entry = normalizeKey(tostring(value[i] or ''))
		if entry then
			list[#list + 1] = entry
		end
	end

	return list
end

local function getIdFromSource(idType, source)
	local normalizedType = idType and tostring(idType):lower()
	if not normalizedType or not source then
		return nil
	end

	local identifiers = getIdentifierMap(source)
	return identifiers[normalizedType]
end

local function trimString(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function isIdentityDebugEnabled()
	return constants and constants.IdentityDebugEnabled == true
end

local function debugIdentity(message, ...)
	if not isIdentityDebugEnabled() then
		return
	end

	log('warning', string.format(tostring(message or ''), ...))
end

local function normalizeNicknameStorageKey(value)
	local key = trimString(value):lower()
	if key == '' then
		return nil
	end

	return key
end

local function getLegacyNicknameStorageKey(source)
	if not constants then
		return nil
	end

	return normalizeNicknameStorageKey(getIdFromSource(constants.IdentifierType, source))
end

local function getQbCoreCharacterNicknameKey(source, retry)
	if citizenidCache[source] and type(citizenidCache[source]) == 'string' and citizenidCache[source] ~= '' then
		return normalizeNicknameStorageKey('qbcorecharacter:' .. citizenidCache[source]), nil
	end



	local ok, QB = pcall(function()
		return exports['qb-core']:GetCoreObject()
	end)

	if not ok then
		return nil, 'qbcore_export_failed'
	end

	if not QB then
		return nil, 'qbcore_missing'
	end

	if not QB.Functions or type(QB.Functions.GetPlayer) ~= 'function' then
		return nil, 'getplayer_missing'
	end

	local player = QB.Functions.GetPlayer(source)
	if player and player.PlayerData and type(player.PlayerData.citizenid) == 'string' and player.PlayerData.citizenid ~= '' then
		citizenidCache[source] = player.PlayerData.citizenid
		return normalizeNicknameStorageKey('qbcorecharacter:' .. player.PlayerData.citizenid), nil
	end

	local players = QB.Functions.GetQBPlayers and QB.Functions.GetQBPlayers() or QB.Players
	if players and players[source] and players[source].PlayerData and type(players[source].PlayerData.citizenid) == 'string' and players[source].PlayerData.citizenid ~= '' then
		local citizenid = players[source].PlayerData.citizenid
		citizenidCache[source] = citizenid
		return normalizeNicknameStorageKey('qbcorecharacter:' .. citizenid), nil
	end

	return nil, 'player_not_found'
end


local function cacheQbCitizenId(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return nil
	end

	local ok, QB = pcall(function()
		return exports['qb-core']:GetCoreObject()
	end)

	if not ok or not QB then
		debugIdentity('cacheQbCitizenId: qbcore unavailable for src=%s', tostring(src))
		return nil
	end

	local player = nil
	if QB.Functions and type(QB.Functions.GetPlayer) == 'function' then
		player = QB.Functions.GetPlayer(src)
	end

	if not player then
		local players = QB.Functions.GetQBPlayers and QB.Functions.GetQBPlayers() or QB.Players
		player = players and players[src] or nil
	end

	if not player or not player.PlayerData or type(player.PlayerData.citizenid) ~= 'string' or player.PlayerData.citizenid == '' then
		debugIdentity(
			'cacheQbCitizenId: no citizenid for src=%s player=%s',
			tostring(src),
			tostring(player ~= nil)
		)
		return nil
	end

	citizenidCache[src] = player.PlayerData.citizenid
	debugIdentity(
		'cacheQbCitizenId: cached src=%s citizenid=%s',
		tostring(src),
		tostring(citizenidCache[src])
	)
	return citizenidCache[src]
end

local function getAccountNicknameStorageKey(source)
	if not constants then
		return nil
	end

	local identifier = getIdFromSource(constants.IdentifierType, source)
	if not identifier then
		return nil
	end

	return normalizeNicknameStorageKey(('account:%s:%s'):format(tostring(constants.IdentifierType or 'license'):lower(), identifier))
end

local function buildCharacterIdentityKey(citizenid)
	local normalizedCitizenId = trimString(citizenid)
	if normalizedCitizenId == '' then
		return nil
	end

	return normalizeNicknameStorageKey('character:qbcore:' .. normalizedCitizenId)
end

local function getIdentitySnapshotDisplayName(snapshot)
	if type(snapshot) == 'string' then
		local normalized = trimString(snapshot)
		if normalized ~= '' then
			return normalized
		end
	elseif type(snapshot) == 'table' then
		local normalized = trimString(snapshot.displayName or snapshot.name)
		if normalized ~= '' then
			return normalized
		end
	end

	return nil
end

local function persistIdentitySnapshots()
	local ok, encoded = pcall(json.encode, identitySnapshots)
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false
	end

	local stored, err = pcall(SetResourceKvp, 'identitySnapshots', encoded)
	if not stored then
		log('warning', ('Failed to store identity snapshot KVP: %s'):format(tostring(err)))
		return false
	end

	return true
end

local function setAccountDisplaySnapshot(accountKey, displayName, scope)
	local normalizedKey = normalizeNicknameStorageKey(accountKey)
	local normalizedName = trimString(displayName)
	if not normalizedKey or normalizedName == '' then
		return false
	end

	local current = identitySnapshots[normalizedKey]
	if type(current) == 'table'
		and trimString(current.displayName or current.name) == normalizedName
		and trimString(current.scope) == trimString(scope)
	then
		return true
	end

	identitySnapshots[normalizedKey] = {
		displayName = normalizedName,
		scope = trimString(scope) ~= '' and trimString(scope) or nil,
		updatedAt = os.time()
	}

	return persistIdentitySnapshots()
end

local function getAccountDisplaySnapshot(accountKey)
	local normalizedKey = normalizeNicknameStorageKey(accountKey)
	if not normalizedKey then
		return nil
	end

	local snapshot = identitySnapshots[normalizedKey]
	if type(snapshot) ~= 'table' or trimString(snapshot.scope) ~= 'nickname' then
		return nil
	end

	return getIdentitySnapshotDisplayName(snapshot)
end

local function clearAccountDisplaySnapshot(accountKey)
	local normalizedKey = normalizeNicknameStorageKey(accountKey)
	if not normalizedKey or identitySnapshots[normalizedKey] == nil then
		return false
	end

	identitySnapshots[normalizedKey] = nil
	return persistIdentitySnapshots()
end

local function getNicknameStorageKey(source, retry)
	if not constants then
		return nil, nil, 'not_ready'
	end

	local mode = normalizeKey(constants.NicknameStorageMode or 'account') or 'account'
	if mode == 'qbcorecharacter' then
		local primaryKey, reason = getQbCoreCharacterNicknameKey(source, retry == true)
		if primaryKey then
			return primaryKey, nil, reason
		end
		return nil, nil, reason
	end

	if mode == 'custom' then
		local resolver = constants.NicknameStorageResolver
		if type(resolver) ~= 'function' then
			return nil, nil, 'resolver_missing'
		end

		local fallbackKey = getAccountNicknameStorageKey(source)
		local ok, resolved = pcall(resolver, source, fallbackKey)
		if not ok then
			log('warning', ('Nickname storage resolver failed for %s: %s'):format(tostring(source), tostring(resolved)))
			return nil, nil, 'resolver_failed'
		end

		return normalizeNicknameStorageKey(resolved), nil, nil
	end

	return getAccountNicknameStorageKey(source), getLegacyNicknameStorageKey(source), nil
end

local function getNickname(source)
	if not constants then
		return nil
	end
	local primaryKey, legacyKey = getNicknameStorageKey(source)
	if primaryKey and nicknames[primaryKey] ~= nil then
		return nicknames[primaryKey]
	end

	if legacyKey and nicknames[legacyKey] ~= nil then
		return nicknames[legacyKey]
	end
end

local function hasNickname(source)
	if not constants then
		return false
	end

	local primaryKey, legacyKey = getNicknameStorageKey(source)
	if primaryKey and nicknames[primaryKey] ~= nil then
		return true
	end

	if legacyKey and nicknames[legacyKey] ~= nil then
		return true
	end

	return false
end

local function persistNicknameCompanionStores()
	local okHistory, encodedHistory = pcall(json.encode, nicknameHistory or {})
	local okPinned, encodedPinned = pcall(json.encode, pinnedNicknames or {})
	if okHistory and type(encodedHistory) == 'string' then
		SetResourceKvp('nicknameHistory', encodedHistory)
	end
	if okPinned and type(encodedPinned) == 'string' then
		SetResourceKvp('pinnedNicknames', encodedPinned)
	end
	return okHistory == true and okPinned == true
end

local function rememberNicknameHistory(storageKey, nickname)
	local key = normalizeNicknameStorageKey(storageKey)
	local value = trimString(nickname)
	if not key or value == '' then
		return
	end

	if type(nicknameHistory[key]) ~= 'table' then
		nicknameHistory[key] = {}
	end

	local history = nicknameHistory[key]
	if history[#history] == value then
		return
	end

	history[#history + 1] = value
	while #history > 20 do
		table.remove(history, 1)
	end
	persistNicknameCompanionStores()
end

local function setNickname(source, nickname)
	if not constants then
		return false, 'not_ready'
	end

	local primaryKey, legacyKey, reason = getNicknameStorageKey(source, true)
	if not primaryKey then
		debugIdentity('setNickname failed for source=%s reason=%s', tostring(source), tostring(reason))
		return false, reason or 'missing_key'
	end

	if nickname == nil then
		nicknames[primaryKey] = nil
	else
		nicknames[primaryKey] = nickname
		rememberNicknameHistory(primaryKey, nickname)
	end

	if legacyKey then
		nicknames[legacyKey] = nil
	end

	local ok, encoded = pcall(json.encode, nicknames)
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false, 'encode_failed'
	end

	local stored, err = pcall(SetResourceKvp, 'nicknames', encoded)
	if not stored then
		log('warning', ('Failed to store nickname KVP for %s: %s'):format(tostring(source), tostring(err)))
		return false, 'storage_failed'
	end

	local accountKey = getAccountNicknameStorageKey(source)
	if nickname == nil then
		clearAccountDisplaySnapshot(accountKey)
	else
		setAccountDisplaySnapshot(accountKey, nickname, 'nickname')
	end
	identityStateBySource[tostring(source)] = nil

	return true, nil
end

local function getNicknameHistory(source)
	local primaryKey = getNicknameStorageKey(source)
	if not primaryKey or type(nicknameHistory[primaryKey]) ~= 'table' then
		return {}
	end
	local history = {}
	for i = 1, #nicknameHistory[primaryKey] do
		history[i] = nicknameHistory[primaryKey][i]
	end
	return history
end

local function getPinnedNicknames(source)
	local primaryKey = getNicknameStorageKey(source)
	if not primaryKey then
		return {}
	end
	local stored = pinnedNicknames[primaryKey]
	if type(stored) == 'string' then
		return stored ~= '' and {stored} or {}
	end
	if type(stored) ~= 'table' then
		return {}
	end
	local result = {}
	for i = 1, #stored do
		local value = trimString(stored[i])
		if value ~= '' then
			result[#result + 1] = value
		end
		if #result >= 5 then
			break
		end
	end
	return result
end

local function getPinnedNickname(source)
	local pinned = getPinnedNicknames(source)
	return pinned[1]
end

local function setPinnedNickname(source, nickname)
	local primaryKey, _, reason = getNicknameStorageKey(source, true)
	if not primaryKey then
		return false, reason or 'missing_key'
	end
	local value = trimString(nickname)
	if value == '' then
		pinnedNicknames[primaryKey] = nil
	else
		pinnedNicknames[primaryKey] = {value}
		rememberNicknameHistory(primaryKey, value)
	end
	persistNicknameCompanionStores()
	return true
end

local function pinNickname(source, nickname)
	local primaryKey, _, reason = getNicknameStorageKey(source, true)
	if not primaryKey then
		return false, reason or 'missing_key'
	end
	local value = trimString(nickname)
	if value == '' then
		return false, 'invalid_nickname'
	end
	local nextPinned = {value}
	local current = getPinnedNicknames(source)
	for i = 1, #current do
		if current[i] ~= value then
			nextPinned[#nextPinned + 1] = current[i]
		end
		if #nextPinned >= 5 then
			break
		end
	end
	pinnedNicknames[primaryKey] = nextPinned
	rememberNicknameHistory(primaryKey, value)
	persistNicknameCompanionStores()
	return true
end

local function unpinNickname(source, nickname)
	local primaryKey, _, reason = getNicknameStorageKey(source, true)
	if not primaryKey then
		return false, reason or 'missing_key'
	end
	local value = trimString(nickname)
	if value == '' then
		return false, 'invalid_nickname'
	end
	local nextPinned = {}
	local current = getPinnedNicknames(source)
	for i = 1, #current do
		if current[i] ~= value then
			nextPinned[#nextPinned + 1] = current[i]
		end
	end
	pinnedNicknames[primaryKey] = #nextPinned > 0 and nextPinned or nil
	persistNicknameCompanionStores()
	return true
end

local function getCurrentCitizenId(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return nil
	end

	local cached = citizenidCache[src]
	if type(cached) == 'string' and cached ~= '' then
		return cached
	end

	return cacheQbCitizenId(src)
end

local function resolveBaseDisplayName(source, fallback)
	local fallbackName = trimString(fallback)
	if fallbackName == '' then
		fallbackName = '?'
	end

	local resolver = constants and constants.AccessDisplayNameResolver or nil
	if type(resolver) ~= 'function' then
		return fallbackName
	end

	local ok, resolved = pcall(resolver, source, fallbackName)
	if not ok then
		log('warning', ('Display name resolver failed for %s: %s'):format(tostring(source), tostring(resolved)))
		return fallbackName
	end

	local normalized = trimString(resolved)
	if normalized == '' then
		return fallbackName
	end

	return normalized
end

local function buildFallbackPlayerIdentityKey(source)
	return normalizeNicknameStorageKey('player:' .. tostring(source))
end

local function buildIdentityState(source)
	local src = tonumber(source) or source
	local fivemName = trimString(GetPlayerName(src))
	if fivemName == '' then
		fivemName = '?'
	end

	local accountKey = getAccountNicknameStorageKey(src)
	local citizenid = getCurrentCitizenId(src)
	local characterKey = buildCharacterIdentityKey(citizenid)
	local baseDisplayName = resolveBaseDisplayName(src, fivemName)
	local characterDisplayName = characterKey and baseDisplayName or fivemName
	local nickname = getNickname(src)
	local activeDisplayName = trimString(nickname or characterDisplayName or fivemName)
	if activeDisplayName == '' then
		activeDisplayName = fivemName
	end

	local joinFallbackDisplayName = getAccountDisplaySnapshot(accountKey) or fivemName
	local conversationScope = characterKey and 'character' or 'account'
	local conversationKey = characterKey or accountKey or buildFallbackPlayerIdentityKey(src)

	return {
		source = src,
		accountKey = accountKey,
		citizenid = citizenid,
		characterKey = characterKey,
		fivemName = fivemName,
		baseDisplayName = characterDisplayName,
		nickname = nickname,
		activeDisplayName = activeDisplayName,
		joinFallbackDisplayName = joinFallbackDisplayName,
		conversationScope = conversationScope,
		conversationKey = conversationKey
	}
end

local function getIdentityState(source, refresh)
	local key = tostring(source)
	if refresh ~= true then
		local cached = identityStateBySource[key]
		if type(cached) == 'table' then
			return cached
		end
	end

	local state = buildIdentityState(source)
	identityStateBySource[key] = state
	return state
end

local function refreshIdentityState(source, persistSnapshot)
	local state = getIdentityState(source, true)
	local nickname = trimString(state.nickname)
	if persistSnapshot == true and state.accountKey and nickname ~= '' then
		setAccountDisplaySnapshot(
			state.accountKey,
			nickname,
			'nickname'
		)
		state.joinFallbackDisplayName = getAccountDisplaySnapshot(state.accountKey) or state.fivemName
		identityStateBySource[tostring(source)] = state
	end

	return state
end

local function clearIdentityState(source)
	identityStateBySource[tostring(source)] = nil
end

local function getRealName(source)
	return getIdentityState(source).baseDisplayName
end

local function getName(source)
	return getIdentityState(source).activeDisplayName
end

local function getJoinName(source)
	return getIdentityState(source).joinFallbackDisplayName
end

local function getLeaveName(source)
	local state = getIdentityState(source)
	if state.characterKey then
		return state.activeDisplayName
	end

	return state.joinFallbackDisplayName
end

local function getConversationIdentity(source)
	local state = getIdentityState(source)
	return state.conversationKey, state.conversationScope, state.activeDisplayName
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
		local function sendFeedback(text, color)
			if Server.sendSystemMessage then
				Server.sendSystemMessage(source, text, color, constants.DefaultChannelId)
				return
			end
			TriggerClientEvent('chat:addMessage', source, {
				channel = constants.DefaultChannelId,
				color = color or {255, 255, 255},
				args = {'System', tostring(text or '')},
				metadata = {type = 'system'}
			})
		end

		local nickname = args[1] and table.concat(args, ' ')
		if nickname then
			nickname = trimString(nickname)
			if nickname == '' then
				nickname = nil
			end
		end

		if nickname and string.len(nickname) > constants.MaxNicknameLen then
			sendFeedback('Nicknames cannot be more than ' .. constants.MaxNicknameLen .. ' characters long', {255, 0, 0})
			return
		end

		local ok, reason = setNickname(source, nickname)
		if ok then
			refreshIdentityState(source, true)
			if Server.updateCharacterDirectoryEntry then
				Server.updateCharacterDirectoryEntry(source)
			end
			if nickname then
				sendFeedback('Your nickname was set to ' .. nickname, {104, 216, 167})
			else
				sendFeedback('Your nickname has been unset', {246, 211, 101})
			end
		else
			local message = 'Failed to set nickname'

			if reason == 'player_not_found' then
				message = 'Your QBCore player object could not be found'
			elseif reason == 'qbcore_export_failed' or reason == 'qbcore_missing' then
				message = 'QBCore is not available'
			elseif reason == 'getplayer_missing' then
				message = 'QBCore GetPlayer is unavailable'
			elseif reason == 'not_ready' then
				message = 'Character data is still loading, try setting your nickname again in a moment'
			end

			sendFeedback(message, {255, 0, 0})
		end
	end, false)
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

local function getMaxAllowedVoiceDistance()
	local maxDistance = math.max(
		tonumber(constants and constants.VoiceFallbackLocalDistance) or 0.0,
		tonumber(constants and constants.LocalMessageDistance) or 0.0
	)

	local voiceConfig = Server and Server.config and Server.config.voice or {}
	local configuredModes = nil

	if type(voiceConfig.fallbackModes) == 'table' then
		configuredModes = voiceConfig.fallbackModes
	elseif type(voiceConfig.modes) == 'table' then
		configuredModes = voiceConfig.modes
	elseif type(voiceConfig.voiceModes) == 'table' then
		configuredModes = voiceConfig.voiceModes
	end

	if type(configuredModes) == 'table' then
		for i = 1, #configuredModes do
			local rawEntry = configuredModes[i]
			local range = nil
			if type(rawEntry) == 'table' then
				range = tonumber(rawEntry[1] or rawEntry.range or rawEntry.distance or rawEntry.value)
			else
				range = tonumber(rawEntry)
			end

			if range and range > maxDistance then
				maxDistance = range
			end
		end
	end

	if maxDistance <= 0 then
		maxDistance = 50.0
	end

	return maxDistance
end

local function setSyncedVoiceDistance(source, distance)
	local src = tonumber(source)
	local resolvedDistance = tonumber(distance)
	if not src or src <= 0 then
		return false
	end

	if not resolvedDistance or resolvedDistance <= 0 then
		voiceDistanceBySource[tostring(src)] = nil
		return false
	end

	resolvedDistance = math.min(resolvedDistance, getMaxAllowedVoiceDistance())
	voiceDistanceBySource[tostring(src)] = resolvedDistance
	return true
end

local function getSyncedVoiceDistance(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return nil
	end

	local cached = tonumber(voiceDistanceBySource[tostring(src)])
	if not cached or cached <= 0 then
		return nil
	end

	return cached
end

local function clearSyncedVoiceDistance(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return
	end

	voiceDistanceBySource[tostring(src)] = nil
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
	local voiceConfig = type(rootConfig.voice) == 'table' and rootConfig.voice or {}
	local uiConfig = type(rootConfig.ui) == 'table' and rootConfig.ui or {}
	local baseChannelsConfig = type(rootConfig.channels) == 'table' and rootConfig.channels or {}
	local channelsConfig = {}
	for channelId, channelConfig in pairs(baseChannelsConfig) do
		channelsConfig[channelId] = channelConfig
	end
	if type(Server.getRuntimeStore) == 'function' then
		local storedRuntimeConfig = Server.getRuntimeStore('runtimeConfig')
		local runtimeChannels = type(storedRuntimeConfig) == 'table' and type(storedRuntimeConfig.channels) == 'table' and storedRuntimeConfig.channels or nil
		if runtimeChannels then
			for channelId, channelConfig in pairs(runtimeChannels) do
				if type(channelConfig) == 'table' then
					channelsConfig[channelId] = channelConfig
				end
			end
		end
	end
	local commandsConfig = type(rootConfig.commands) == 'table' and rootConfig.commands or {}
	local routingConfig = type(rootConfig.routing) == 'table' and rootConfig.routing or {}
	local whispersConfig = type(rootConfig.whispers) == 'table' and rootConfig.whispers or {}
	local messagesConfig = type(rootConfig.messages) == 'table' and rootConfig.messages or {}
	local moderationConfig = type(rootConfig.moderation) == 'table' and rootConfig.moderation or {}
	local moderationPermissionsConfig = type(moderationConfig.permissions) == 'table' and moderationConfig.permissions or {}
	local moderationQbConfig = type(moderationPermissionsConfig.qbcore) == 'table' and moderationPermissionsConfig.qbcore or {}
	local builtInReportsConfig = type(moderationConfig.builtInReports) == 'table' and moderationConfig.builtInReports or {}
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
		rangeMode = normalizeKey(rawBubbleConfig.rangeMode) or 'fixed',
		maxDistance = tonumber(rawBubbleConfig.maxDistance) or 25.0,
		maxLength = tonumber(rawBubbleConfig.maxLength) or 80,
		fadeOutTime = tonumber(rawBubbleConfig.fadeOutMs) or 4000
	}

	local localChannelConfig = type(channelsConfig["local"]) == 'table' and channelsConfig["local"] or {}
	local globalChannelConfig = type(channelsConfig.global) == 'table' and channelsConfig.global or {}
	local staffChannelConfig = type(channelsConfig.staff) == 'table' and channelsConfig.staff or {}
	local whisperChannelConfig = type(channelsConfig.whispers) == 'table' and channelsConfig.whispers or {}
	local sceneMessageConfig = type(messagesConfig.scene) == 'table' and messagesConfig.scene or {}

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
		sceneLabel = sceneMessageConfig.label,
		sceneColor = sceneMessageConfig.color,
		sceneDistance = sceneMessageConfig.distance,
		localDistance = voiceConfig.fallbackLocalDistance or localChannelConfig.distance
	}

	local identifierType = tostring(accessConfig.identifier or 'license')
	local staffChannelAce = tostring(accessConfig.staffChannelAce or 'chat.staffChannel')
	local noMuteAce = tostring(accessConfig.noMuteAce or 'chat.noMute')
	local moderationDeleteAce = tostring(moderationPermissionsConfig.deleteAce or 'chat.deleteMessage')
	local moderationViewDeletedAce = tostring(moderationPermissionsConfig.viewDeletedAce or moderationDeleteAce)
	local moderationQbBridgeEnabled = moderationQbConfig.enabled ~= false
	local moderationStaffQbPermissions = normalizePermissionList(moderationQbConfig.staffPermissions or {'god', 'admin', 'mod'})
	local moderationDeleteQbPermissions = normalizePermissionList(moderationQbConfig.deletePermissions or {'god', 'admin'})
	local nicknameStorageConfig = type(accessConfig.nicknameStorage) == 'table' and accessConfig.nicknameStorage or {}
	local nicknameStorageMode = normalizeKey(tostring(nicknameStorageConfig.mode or 'account')) or 'account'
	if nicknameStorageMode ~= 'account' and nicknameStorageMode ~= 'qbcorecharacter' and nicknameStorageMode ~= 'custom' then
		nicknameStorageMode = 'account'
	end
	local nicknameStorageResolver = type(nicknameStorageConfig.customResolver) == 'function' and nicknameStorageConfig.customResolver or nil
	local roles = type(accessConfig.roles) == 'table' and accessConfig.roles or {}
	local rolePrefixEnabled = accessConfig.rolePrefixEnabled == true

	local maxNicknameLen = math.max(1, tonumber(chatConfig.maxNicknameLen) or 30)
	local printToConsole = chatConfig.printToConsole ~= false
	local localMessageColor = normalizeRgbColor(chatConfig.localColor, {0, 153, 204})
	local globalMessageColor = normalizeRgbColor(chatConfig.globalColor, {212, 175, 55})
	local staffMessageColor = normalizeRgbColor(chatConfig.staffColor, {255, 64, 0})
	local sceneMessageColor = normalizeRgbColor(chatConfig.sceneColor, {143, 199, 255})
	local actionMessageDistance = tonumber(chatConfig.actionDistance) or 50.0
	local sceneMessageDistance = tonumber(chatConfig.sceneDistance) or actionMessageDistance
	local localMessageDistance = tonumber(chatConfig.localDistance) or 50.0
	local voiceEnabled = voiceConfig.enabled == true
	local voiceResourceName = normalizeKey(tostring(voiceConfig.resource or 'pma-voice')) or 'pma-voice'

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

	local whisperTabLabel = type(whispersConfig.tabLabel) == 'string' and whispersConfig.tabLabel:gsub('^%s+', ''):gsub('%s+$', '') or ''
	if whisperTabLabel ~= '' and channelById.whispers then
		channelById.whispers.label = whisperTabLabel
		for i = 1, #channelList do
			if channelList[i].id == 'whispers' then
				channelList[i].label = whisperTabLabel
				break
			end
		end
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
		moderation = moderationConfig,
		chat = chatConfig,
		access = accessConfig,
		typing = typingConfig,
		bubble = bubbleConfig,
		voice = voiceConfig,
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
		ModerationDeleteAce = moderationDeleteAce,
		ModerationViewDeletedAce = moderationViewDeletedAce,
		ModerationQbBridgeEnabled = moderationQbBridgeEnabled,
		ModerationStaffQbPermissions = moderationStaffQbPermissions,
		ModerationDeleteQbPermissions = moderationDeleteQbPermissions,
		BuiltInReportsEnabled = builtInReportsConfig.enabled ~= false,
		IdentityDebugEnabled = serverRuntime.identityDebug == true,
		NicknameStorageMode = nicknameStorageMode,
		NicknameStorageResolver = nicknameStorageResolver,
		AccessDisplayNameResolver = type(accessConfig.getDisplayName) == 'function' and accessConfig.getDisplayName or nil,
		Roles = roles,
		RolePrefixEnabled = rolePrefixEnabled,
		MaxNicknameLen = maxNicknameLen,
		PrintToConsole = printToConsole,
		LocalMessageColor = localMessageColor,
		GlobalMessageColor = globalMessageColor,
		StaffMessageColor = staffMessageColor,
		SceneMessageColor = sceneMessageColor,
		ActionMessageDistance = actionMessageDistance,
		SceneMessageDistance = sceneMessageDistance,
		LocalMessageDistance = localMessageDistance,
		VoiceEnabled = voiceEnabled,
		VoiceResourceName = voiceResourceName,
		VoiceFallbackLocalDistance = localMessageDistance,
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
	Server.applyRuntimeChannelConfig = function()
		local nextChannelsConfig = {}
		for channelId, channelConfig in pairs(baseChannelsConfig) do
			nextChannelsConfig[channelId] = channelConfig
		end
		if type(Server.getRuntimeStore) == 'function' then
			local storedRuntimeConfig = Server.getRuntimeStore('runtimeConfig')
			local runtimeChannels = type(storedRuntimeConfig) == 'table' and type(storedRuntimeConfig.channels) == 'table' and storedRuntimeConfig.channels or nil
			if runtimeChannels then
				for channelId, channelConfig in pairs(runtimeChannels) do
					if type(channelConfig) == 'table' then
						nextChannelsConfig[channelId] = channelConfig
					end
				end
			end
		end

		local nextChannelList, nextChannelById = buildChannelDefinitions(nextChannelsConfig, staffChannelAce)
		local nextDefaultChannelId = normalizeKey(routingConfig.defaultChannel) or constants.DefaultChannelId or 'global'
		if not nextChannelById[nextDefaultChannelId] then
			nextDefaultChannelId = nextChannelById.global and 'global' or (nextChannelList[1] and nextChannelList[1].id or 'global')
		end

		local nextWhisperFallbackChannelId = normalizeKey(whispersConfig.fallbackChannel) or nextDefaultChannelId
		if nextWhisperFallbackChannelId == 'whispers' or not nextChannelById[nextWhisperFallbackChannelId] then
			nextWhisperFallbackChannelId = nextDefaultChannelId
		end

		local nextWhisperTabLabel = type(whispersConfig.tabLabel) == 'string' and whispersConfig.tabLabel:gsub('^%s+', ''):gsub('%s+$', '') or ''
		if nextWhisperTabLabel ~= '' and nextChannelById.whispers then
			nextChannelById.whispers.label = nextWhisperTabLabel
			for i = 1, #nextChannelList do
				if nextChannelList[i].id == 'whispers' then
					nextChannelList[i].label = nextWhisperTabLabel
					break
				end
			end
		end

		if whispersConfig.tabEnabled == false and nextChannelById.whispers then
			nextChannelById.whispers.visible = false
			nextChannelById.whispers.cycle = false
		end

		Server.config.channels = nextChannelsConfig
		constants.ChannelList = nextChannelList
		constants.ChannelById = nextChannelById
		constants.DefaultChannelId = nextDefaultChannelId
		constants.WhisperFallbackChannelId = nextWhisperFallbackChannelId
		return true
	end
	nicknames = decodeTableOrEmpty(GetResourceKvpString('nicknames'))
	nicknameHistory = decodeTableOrEmpty(GetResourceKvpString('nicknameHistory'))
	pinnedNicknames = decodeTableOrEmpty(GetResourceKvpString('pinnedNicknames'))
	identitySnapshots = decodeTableOrEmpty(GetResourceKvpString('identitySnapshots'))
	Server.characterDirectory = decodeTableOrEmpty(GetResourceKvpString('characterDirectory'))
	identifierCache = {}
	typingStateBySource = {}
	citizenidCache = {}
	identityStateBySource = {}
	voiceDistanceBySource = {}
	deletedMessageRegistry = decodeTableOrEmpty(GetResourceKvpString('deletedMessageRegistry'))
	liveMessageRegistry = {}
	liveMessageRegistryOrder = {}
	messageSequence = 0

	Server.state = {
		nicknames = nicknames,
		nicknameHistory = nicknameHistory,
		pinnedNicknames = pinnedNicknames,
		identitySnapshots = identitySnapshots,
		characterDirectory = Server.characterDirectory,
		identifierCache = identifierCache,
		typingStateBySource = typingStateBySource,
		identityStateBySource = identityStateBySource,
		voiceDistanceBySource = voiceDistanceBySource,
		deletedMessageRegistry = deletedMessageRegistry,
		liveMessageRegistry = liveMessageRegistry
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
	Server.getCurrentCitizenId = getCurrentCitizenId
	Server.setSyncedVoiceDistance = setSyncedVoiceDistance
	Server.getSyncedVoiceDistance = getSyncedVoiceDistance
	Server.clearSyncedVoiceDistance = clearSyncedVoiceDistance
	Server.triggerClientEventForTargets = triggerClientEventForTargets
	Server.triggerClientEventForTargetsNoFallback = triggerClientEventForTargetsNoFallback
	Server.getNearbyPlayers = getNearbyPlayers
	Server.getNameWithRoleAndColor = getNameWithRoleAndColor
	Server.escapePattern = escapePattern
	Server.getIdFromSource = getIdFromSource
	Server.getNickname = getNickname
	Server.hasNickname = hasNickname
	Server.setNickname = setNickname
	Server.getNicknameHistory = getNicknameHistory
	Server.getPinnedNicknames = getPinnedNicknames
	Server.getPinnedNickname = getPinnedNickname
	Server.setPinnedNickname = setPinnedNickname
	Server.pinNickname = pinNickname
	Server.unpinNickname = unpinNickname
	Server.getRealName = getRealName
	Server.getName = getName
	Server.getJoinName = getJoinName
	Server.getLeaveName = getLeaveName
	Server.getConversationIdentity = getConversationIdentity
	Server.refreshIdentityState = refreshIdentityState
	Server.clearIdentityState = clearIdentityState
	Server.getNameWithId = getNameWithId
	Server.getChannelById = getChannelById
	Server.getDefaultChannelId = getDefaultChannelId
	Server.canAccessChannel = canAccessChannel
	Server.getPlayerChannelPermissions = getPlayerChannelPermissions
	Server.getResolvedPlayerPermissions = getResolvedPlayerPermissions
	Server.hasModerationPermission = hasModerationPermission
	Server.registerCommandWithAliases = registerCommandWithAliases
	Server.registerNicknameCommand = registerNicknameCommand

	GetIDFromSource = getIdFromSource
	GetNickname = getNickname
	HasNickname = hasNickname
	SetNickname = setNickname
	GetRealName = getRealName
	GetName = getName
	GetJoinName = getJoinName
	GetLeaveName = getLeaveName
	GetNameWithId = getNameWithId

	-- Prime the citizenid cache when the resource starts or restarts while players are online.
	for _, playerId in ipairs(GetPlayers()) do
		cacheQbCitizenId(playerId)
		refreshIdentityState(playerId, true)
		if Server.updateCharacterDirectoryEntry then
			Server.updateCharacterDirectoryEntry(playerId)
		end
		if Server.loadAndDeliverHistory then
			Server.loadAndDeliverHistory(playerId, false)
		end
	end

	-- Register for QB Core events
	local function onQbPlayerLoaded(payload)
		local src = nil

		if type(payload) == 'number' then
			src = payload
		elseif type(payload) == 'string' then
			src = tonumber(payload)
		elseif type(payload) == 'table' then
			if payload.PlayerData and payload.PlayerData.source then
				src = tonumber(payload.PlayerData.source)
			elseif payload.source then
				src = tonumber(payload.source)
			end
		end

		if not src and source then
			src = tonumber(source)
		end

		if src then
			cacheQbCitizenId(src)
			refreshIdentityState(src, true)
			if Server.updateCharacterDirectoryEntry then
				Server.updateCharacterDirectoryEntry(src)
			end
			debugIdentity(
				'QBCore player loaded -> cached citizenid for src=%s value=%s',
				tostring(src),
				tostring(citizenidCache[src])
			)
			-- Load and deliver persisted chat history for this character
			Server.loadAndDeliverHistory(src, true)
		else
			debugIdentity('QBCore player loaded but could not resolve source from payload')
		end
	end

	AddEventHandler('QBCore:Server:OnPlayerLoaded', onQbPlayerLoaded)
	AddEventHandler('QBCore:Server:PlayerLoaded', onQbPlayerLoaded)
	AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerSource)
		local src = tonumber(playerSource or source)
		if src then
			Server.savePlayerHistory(src)
			TriggerClientEvent('poodlechat:characterSwitch', src, {})
			Server.clearCharacterHistoryBuffer(src)
			refreshIdentityState(src, true)
			citizenidCache[src] = nil
			refreshIdentityState(src, false)
		end
	end)
	AddEventHandler('playerDropped', function(reason)
		local src = tonumber(source)
		if not src then
			return
		end

		Server.savePlayerHistory(src)
		refreshIdentityState(src, true)
		CreateThread(function()
			Wait(0)
			citizenidCache[src] = nil
			clearSyncedVoiceDistance(src)
			clearIdentityState(src)
			Server.clearPlayerHistoryBuffer(src)
		end)
	end)

	exports('getName', getName)
	bootstrapInitialized = true
end

Server.setupBootstrap = setupBootstrap

-- ══════════════════════════════════════════════════════════════════
-- Split chat history system:
-- session buffers live until playerDropped; character buffers are KVP-backed per QBCore character.
-- ══════════════════════════════════════════════════════════════════

local playerHistoryBuffers = {}
local sessionHistoryBuffers = {}
local historyDirtyBySource = {}
local historyAutosaveThreadStarted = false

local function getCharacterDirectory()
	if type(Server.characterDirectory) ~= 'table' then
		Server.characterDirectory = {}
	end

	return Server.characterDirectory
end

local function getMaxPersistedMessages()
	local config = Config or {}
	local settings = config.settings or {}
	return math.max(1, tonumber(settings.maxPersistedMessages) or 250)
end

local function normalizeStoredTimestamp(value)
	local timestamp = tonumber(value)
	if not timestamp or timestamp <= 0 then
		return os.time()
	end

	return math.floor(timestamp)
end

local function normalizeStoredMessageId(value)
	local normalized = trimString(value)
	if normalized == '' then
		return nil
	end

	return normalized
end

local function hashString(value)
	local hash = 2166136261
	local text = tostring(value or '')
	for i = 1, #text do
		hash = (hash ~ string.byte(text, i)) & 0xffffffff
		hash = (hash * 16777619) & 0xffffffff
	end
	return string.format('%08x', hash & 0xffffffff)
end

local function nextMessageId()
	messageSequence = (tonumber(messageSequence) or 0) + 1
	return string.format('msg:%d:%d', os.time(), messageSequence)
end

local function deriveStoredMessageId(channelId, message)
	local entry = type(message) == 'table' and message or {}
	local metadata = type(entry.metadata) == 'table' and entry.metadata or {}
	local args = type(entry.args) == 'table' and entry.args or {}
	local basis = table.concat({
		tostring(channelId or entry.channel or ''),
		tostring(entry.label or ''),
		tostring(args[1] or ''),
		tostring(args[2] or entry.text or entry.message or ''),
		tostring(metadata.type or ''),
		tostring(metadata.authorSource or metadata.source or ''),
		tostring(metadata.authorName or metadata.peerName or ''),
		tostring(normalizeStoredTimestamp(entry.timestamp))
	}, '|')

	return 'hist:' .. hashString(basis)
end

local function shallowCopyArray(list)
	if type(list) ~= 'table' then
		return list
	end

	local copy = {}
	for i = 1, #list do
		copy[i] = list[i]
	end
	return copy
end

local function shallowCopyTable(value)
	if type(value) ~= 'table' then
		return value
	end

	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = entry
	end
	return copy
end

local function cloneEnvelope(message)
	if type(message) ~= 'table' then
		return nil
	end

	local copy = shallowCopyTable(message)
	copy.args = shallowCopyArray(message.args)
	copy.color = shallowCopyArray(message.color)
	copy.metadata = shallowCopyTable(message.metadata)
	return copy
end

local function getDeletedMessageRegistry()
	if type(deletedMessageRegistry) ~= 'table' then
		deletedMessageRegistry = {}
	end

	return deletedMessageRegistry
end

local function persistDeletedMessageRegistry()
	local registry = getDeletedMessageRegistry()
	if next(registry) == nil then
		DeleteResourceKvp('deletedMessageRegistry')
		return true
	end

	local ok, encoded = pcall(json.encode, registry)
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false
	end

	SetResourceKvp('deletedMessageRegistry', encoded)
	return true
end

local function getDeletedMessageEntry(messageId)
	local normalizedMessageId = normalizeStoredMessageId(messageId)
	if not normalizedMessageId then
		return nil
	end

	return getDeletedMessageRegistry()[normalizedMessageId]
end

local function rememberLiveMessage(targets, envelope)
	local entry = cloneEnvelope(envelope)
	local messageId = entry and normalizeStoredMessageId(entry.messageId)
	if not messageId then
		return
	end

	liveMessageRegistry[messageId] = {
		targets = type(targets) == 'table' and shallowCopyArray(targets) or nil,
		envelope = entry,
		channel = entry.channel,
		createdAt = os.time()
	}

	liveMessageRegistryOrder[#liveMessageRegistryOrder + 1] = messageId
	if #liveMessageRegistryOrder > 600 then
		local oldest = table.remove(liveMessageRegistryOrder, 1)
		if oldest then
			liveMessageRegistry[oldest] = nil
		end
	end
end

local function findLoadedMessageById(messageId)
	local normalizedMessageId = normalizeStoredMessageId(messageId)
	if not normalizedMessageId then
		return nil, nil, nil
	end

	if type(liveMessageRegistry) == 'table' and type(liveMessageRegistry[normalizedMessageId]) == 'table' then
		local record = liveMessageRegistry[normalizedMessageId]
		return cloneEnvelope(record.envelope), type(record.targets) == 'table' and shallowCopyArray(record.targets) or nil, record.channel
	end

	local bufferSets = {playerHistoryBuffers, sessionHistoryBuffers}
	for setIndex = 1, #bufferSets do
		for sourceId, channelBuffers in pairs(bufferSets[setIndex]) do
			if type(channelBuffers) == 'table' then
				for channelId, messages in pairs(channelBuffers) do
					if type(messages) == 'table' then
						for i = 1, #messages do
							local entry = messages[i]
							if type(entry) == 'table' and normalizeStoredMessageId(entry.messageId) == normalizedMessageId then
								local targets = {tonumber(sourceId) or sourceId}
								return cloneEnvelope(entry), targets, channelId
							end
						end
					end
				end
			end
		end
	end

	return nil, nil, nil
end

local function collectLoadedRecipientsForMessage(messageId)
	local normalizedMessageId = normalizeStoredMessageId(messageId)
	if not normalizedMessageId then
		return {}
	end

	if type(liveMessageRegistry) == 'table' and type(liveMessageRegistry[normalizedMessageId]) == 'table' then
		local record = liveMessageRegistry[normalizedMessageId]
		if type(record.targets) == 'table' then
			return shallowCopyArray(record.targets)
		end
		return GetPlayers()
	end

	local recipients = {}
	local seen = {}
	local bufferSets = {playerHistoryBuffers, sessionHistoryBuffers}
	for setIndex = 1, #bufferSets do
		for sourceId, channelBuffers in pairs(bufferSets[setIndex]) do
			if type(channelBuffers) == 'table' then
				for _, messages in pairs(channelBuffers) do
					if type(messages) == 'table' then
						for i = 1, #messages do
							local entry = messages[i]
							if type(entry) == 'table' and normalizeStoredMessageId(entry.messageId) == normalizedMessageId then
								local target = tonumber(sourceId) or sourceId
								local key = tostring(target)
								if not seen[key] then
									seen[key] = true
									recipients[#recipients + 1] = target
								end
								goto next_recipient
							end
						end
					end
				end
			end

			::next_recipient::
		end
	end

	return recipients
end

local function buildDeletedEnvelopeForSource(source, message)
	local entry = type(message) == 'table' and cloneEnvelope(message) or nil
	local deletedEntry = entry and getDeletedMessageEntry(entry.messageId) or nil
	if not entry or not deletedEntry then
		return entry
	end

	entry.metadata = type(entry.metadata) == 'table' and shallowCopyTable(entry.metadata) or {}
	entry.metadata.originalType = entry.metadata.type or 'chat'
	entry.metadata.deleted = true
	entry.metadata.deletedAt = deletedEntry.deletedAt
	entry.metadata.deletedBySource = deletedEntry.deletedBySource
	entry.metadata.deletedByName = deletedEntry.deletedByName
	entry.metadata.deletedReason = deletedEntry.publicText

	if hasModerationPermission(source, 'viewdeleted') then
		entry.metadata.deletedVisibleOriginal = true
		return entry
	end

	entry.label = tostring(deletedEntry.publicLabel or 'Deleted message')
	entry.color = {145, 150, 158}
	entry.args = {
		tostring(deletedEntry.publicLabel or 'Deleted message'),
		tostring(deletedEntry.publicText or 'This message was removed by staff.')
	}
	entry.metadata.deletedVisibleOriginal = false
	return entry
end

local function registerDeletedMessage(messageId, deleterSource, message)
	local normalizedMessageId = normalizeStoredMessageId(messageId)
	if not normalizedMessageId then
		return false
	end

	local registry = getDeletedMessageRegistry()
	if type(registry[normalizedMessageId]) == 'table' then
		return true
	end

	local moderationConfig = type((Server.config or {}).moderation) == 'table' and (Server.config or {}).moderation or {}
	local deletedMessageConfig = type(moderationConfig.deletedMessage) == 'table' and moderationConfig.deletedMessage or {}
	registry[normalizedMessageId] = {
		messageId = normalizedMessageId,
		channel = trimString(type(message) == 'table' and message.channel or ''),
		deletedAt = os.time(),
		deletedBySource = tonumber(deleterSource) or deleterSource,
		deletedByName = Server.getName(deleterSource),
		publicLabel = tostring(deletedMessageConfig.publicLabel or 'Deleted message'),
		publicText = tostring(deletedMessageConfig.publicText or 'This message was removed by staff.')
	}

	persistDeletedMessageRegistry()
	return true
end

local function getHistoryKvpKey(citizenid, channelId)
	return 'chatHistory:' .. tostring(citizenid) .. ':' .. tostring(channelId)
end

local function getOfflineWhisperKvpKey(citizenid)
	return 'offlineWhispers:' .. tostring(citizenid)
end

local function persistCharacterDirectory()
	local ok, encoded = pcall(json.encode, getCharacterDirectory())
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false
	end

	local stored, err = pcall(SetResourceKvp, 'characterDirectory', encoded)
	if not stored then
		log('warning', ('Failed to store character directory KVP: %s'):format(tostring(err)))
		return false
	end

	return true
end

local function getSourceByCitizenId(citizenid)
	local normalizedCitizenId = trimString(citizenid):lower()
	if normalizedCitizenId == '' then
		return nil
	end

	for _, playerId in ipairs(GetPlayers()) do
		local currentCitizenId = trimString(getCurrentCitizenId(playerId)):lower()
		if currentCitizenId ~= '' and currentCitizenId == normalizedCitizenId then
			return playerId
		end
	end

	return nil
end

function Server.updateCharacterDirectoryEntry(source)
	local src = tonumber(source)
	if not src then
		return false
	end

	local state = refreshIdentityState(src, true)
	local citizenid = trimString(state and state.citizenid or '')
	if citizenid == '' then
		return false
	end

	local directory = getCharacterDirectory()
	local key = citizenid:lower()
	local displayName = trimString(state.activeDisplayName or state.baseDisplayName or state.fivemName or citizenid)
	local baseDisplayName = trimString(state.baseDisplayName or displayName)
	local accountKey = trimString(state.accountKey or '')
	local current = type(directory[key]) == 'table' and directory[key] or {}

	if trimString(current.displayName or '') == displayName
		and trimString(current.baseDisplayName or '') == baseDisplayName
		and trimString(current.accountKey or '') == accountKey
	then
		current.lastSource = src
		current.updatedAt = os.time()
		directory[key] = current
		return persistCharacterDirectory()
	end

	directory[key] = {
		citizenid = citizenid,
		displayName = displayName,
		baseDisplayName = baseDisplayName,
		accountKey = accountKey ~= '' and accountKey or nil,
		lastSource = src,
		updatedAt = os.time()
	}

	return persistCharacterDirectory()
end

local function findCharacterDirectoryMatch(query)
	local normalizedQuery = trimString(query)
	if normalizedQuery == '' then
		return nil
	end

	local directory = getCharacterDirectory()
	local direct = directory[normalizedQuery:lower()]
	if type(direct) == 'table' then
		return direct
	end

	local loweredQuery = normalizedQuery:lower()
	local bestMatch = nil
	for _, entry in pairs(directory) do
		if type(entry) == 'table' then
			local displayName = trimString(entry.displayName or ''):lower()
			local baseDisplayName = trimString(entry.baseDisplayName or ''):lower()
			if displayName == loweredQuery or baseDisplayName == loweredQuery then
				if not bestMatch or normalizeStoredTimestamp(entry.updatedAt) > normalizeStoredTimestamp(bestMatch.updatedAt) then
					bestMatch = entry
				end
			end
		end
	end

	return bestMatch
end

function Server.resolveStoredCharacterTarget(query)
	local entry = findCharacterDirectoryMatch(query)
	if type(entry) ~= 'table' then
		return nil
	end

	local citizenid = trimString(entry.citizenid or '')
	if citizenid == '' then
		return nil
	end

	return {
		citizenid = citizenid,
		displayName = trimString(entry.displayName or entry.baseDisplayName or citizenid),
		conversationId = buildCharacterIdentityKey(citizenid),
		onlineSource = getSourceByCitizenId(citizenid)
	}
end

local function normalizeHistoryEntry(channelId, message)
	if type(message) ~= 'table' then
		return nil
	end

	local resolvedChannelId = trimString(message.channel or channelId)
	if resolvedChannelId == '' then
		resolvedChannelId = trimString(channelId)
	end

	local args = type(message.args) == 'table' and message.args or nil
	if not args then
		local text = tostring(message.text or message.message or '')
		local label = tostring(message.label or resolvedChannelId or 'Chat')
		if text ~= '' then
			args = {label, text}
		else
			args = {label}
		end
	end

	return {
		messageId = normalizeStoredMessageId(message.messageId or (type(message.metadata) == 'table' and message.metadata.messageId or nil)) or deriveStoredMessageId(resolvedChannelId, message),
		channel = resolvedChannelId,
		label = tostring(message.label or resolvedChannelId or 'Chat'),
		color = type(message.color) == 'table' and message.color or nil,
		args = args,
		template = message.template,
		templateId = message.templateId,
		multiline = message.multiline ~= false,
		metadata = type(message.metadata) == 'table' and message.metadata or nil,
		timestamp = normalizeStoredTimestamp(message.timestamp)
	}
end

local function markPlayerHistoryDirty(source)
	local src = tonumber(source)
	if not src then
		return
	end

	historyDirtyBySource[tostring(src)] = true
end

local function ensureHistoryAutosaveThread()
	if historyAutosaveThreadStarted then
		return
	end

	historyAutosaveThreadStarted = true
	CreateThread(function()
		while true do
			Wait(30000)
			for sourceKey in pairs(historyDirtyBySource) do
				Server.savePlayerHistory(sourceKey)
			end
		end
	end)
end

local function isChannelPersisted(channelId)
	local config = Server.config or Config or {}
	local channels = config.channels or {}
	local channel = channels[channelId]
	if type(channel) ~= 'table' then
		return false
	end
	return channel.persistHistory == true
end

local function isSessionHistoryChannel(channelId)
	local normalized = normalizeKey(channelId)
	return normalized == 'local' or normalized == 'global'
end

local function getHistoryScope(channelId)
	if isChannelPersisted(channelId) then
		return 'character'
	end
	if isSessionHistoryChannel(channelId) then
		return 'session'
	end
	return nil
end

local function getHistoryLimitForChannel(channelId)
	local config = Server.config or Config or {}
	local channels = config.channels or {}
	local channel = type(channels[channelId]) == 'table' and channels[channelId] or {}
	return normalizeHistoryLimit(channel.history, getMaxPersistedMessages())
end

local function getPersistedChannelIds()
	local config = Server.config or Config or {}
	local channels = config.channels or {}
	local ids = {}
	for id, channel in pairs(channels) do
		if type(channel) == 'table' and channel.persistHistory == true then
			ids[#ids + 1] = id
		end
	end
	return ids
end

function Server.appendToHistoryBuffer(source, channelId, message)
	local src = tonumber(source)
	if not src then return end
	local scope = getHistoryScope(channelId)
	if not scope then return end

	local root = scope == 'session' and sessionHistoryBuffers or playerHistoryBuffers

	if not root[src] then
		root[src] = {}
	end
	if not root[src][channelId] then
		root[src][channelId] = {}
	end

	local buffer = root[src][channelId]
	local maxMessages = getHistoryLimitForChannel(channelId)
	local entry = normalizeHistoryEntry(channelId, message)
	if not entry then
		return
	end

	local messageId = normalizeStoredMessageId(entry.messageId)
	if messageId then
		for i = 1, #buffer do
			if type(buffer[i]) == 'table' and normalizeStoredMessageId(buffer[i].messageId) == messageId then
				buffer[i] = entry
				if scope == 'character' then
					markPlayerHistoryDirty(src)
				end
				return
			end
		end
	end

	buffer[#buffer + 1] = entry
	if maxMessages > 0 and #buffer > maxMessages then
		table.remove(buffer, 1)
	end

	if scope == 'character' then
		markPlayerHistoryDirty(src)
	end
end

function Server.saveCharacterHistory(citizenid, channelId, messages)
	local normalizedCitizenId = trimString(citizenid)
	local normalizedChannelId = trimString(channelId)
	if normalizedCitizenId == '' or normalizedChannelId == '' then
		return false
	end

	local list = type(messages) == 'table' and messages or {}
	if #list == 0 then
		DeleteResourceKvp(getHistoryKvpKey(normalizedCitizenId, normalizedChannelId))
		return true
	end

	local ok, encoded = pcall(json.encode, list)
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false
	end

	SetResourceKvp(getHistoryKvpKey(normalizedCitizenId, normalizedChannelId), encoded)
	return true
end

function Server.clearCharacterHistory(citizenid, channelId)
	local normalizedCitizenId = trimString(citizenid)
	local normalizedChannelId = trimString(channelId)
	if normalizedCitizenId == '' or normalizedChannelId == '' then
		return false
	end

	DeleteResourceKvp(getHistoryKvpKey(normalizedCitizenId, normalizedChannelId))
	return true
end

function Server.savePlayerHistory(source)
	local src = tonumber(source)
	if not src then return end

	local citizenid = citizenidCache[src]
	if not citizenid or citizenid == '' then return end

	local buffers = playerHistoryBuffers[src]
	if not buffers then return end

	for channelId, messages in pairs(buffers) do
		if #messages > 0 then
			Server.saveCharacterHistory(citizenid, channelId, messages)
		else
			Server.clearCharacterHistory(citizenid, channelId)
		end
	end

	historyDirtyBySource[tostring(src)] = nil
end

function Server.loadCharacterHistory(citizenid)
	if not citizenid or citizenid == '' then return {} end

	local channelIds = getPersistedChannelIds()
	local history = {}
	local maxMessages = getMaxPersistedMessages()

	for _, channelId in ipairs(channelIds) do
		local raw = GetResourceKvpString(getHistoryKvpKey(citizenid, channelId))
		if raw and raw ~= '' then
			local ok, messages = pcall(json.decode, raw)
			if ok and type(messages) == 'table' then
				local sanitized = {}
				for i = 1, #messages do
					local entry = normalizeHistoryEntry(channelId, messages[i])
					if entry then
						sanitized[#sanitized + 1] = entry
					end
				end
				messages = sanitized
				if #messages > maxMessages then
					local trimmed = {}
					for i = #messages - maxMessages + 1, #messages do
						trimmed[#trimmed + 1] = messages[i]
					end
					messages = trimmed
				end
				history[channelId] = messages
			end
		end
	end

	return history
end

local function loadOfflineWhispers(citizenid)
	local raw = GetResourceKvpString(getOfflineWhisperKvpKey(citizenid))
	if not raw or raw == '' then
		return {}
	end

	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= 'table' then
		return {}
	end

	return decoded
end

local function saveOfflineWhispers(citizenid, messages)
	local normalizedCitizenId = trimString(citizenid)
	if normalizedCitizenId == '' then
		return false
	end

	local list = type(messages) == 'table' and messages or {}
	if #list == 0 then
		DeleteResourceKvp(getOfflineWhisperKvpKey(normalizedCitizenId))
		return true
	end

	local ok, encoded = pcall(json.encode, list)
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false
	end

	SetResourceKvp(getOfflineWhisperKvpKey(normalizedCitizenId), encoded)
	return true
end

function Server.storeOfflineWhisper(targetCitizenId, payload)
	local normalizedCitizenId = trimString(targetCitizenId)
	local entry = type(payload) == 'table' and payload or nil
	if normalizedCitizenId == '' or not entry then
		return false
	end

	local queue = loadOfflineWhispers(normalizedCitizenId)
	queue[#queue + 1] = {
		senderSource = tonumber(entry.senderSource) or nil,
		senderCitizenId = trimString(entry.senderCitizenId or ''),
		senderConversationId = trimString(entry.senderConversationId or ''),
		senderConversationScope = trimString(entry.senderConversationScope or ''),
		senderName = trimString(entry.senderName or ''),
		senderLicense = entry.senderLicense,
		replyTo = type(entry.replyTo) == 'table' and entry.replyTo or nil,
		text = tostring(entry.text or ''),
		timestamp = normalizeStoredTimestamp(entry.timestamp)
	}

	local maxMessages = getMaxPersistedMessages()
	if #queue > maxMessages then
		local trimmed = {}
		for i = #queue - maxMessages + 1, #queue do
			trimmed[#trimmed + 1] = queue[i]
		end
		queue = trimmed
	end

	return saveOfflineWhispers(normalizedCitizenId, queue)
end

function Server.deliverOfflineWhispers(source)
	local src = tonumber(source)
	if not src then
		return false
	end

	local citizenid = trimString(citizenidCache[src] or '')
	if citizenid == '' then
		return false
	end

	local queue = loadOfflineWhispers(citizenid)
	if #queue == 0 then
		return false
	end

	local whisperConfig = type(Server.config.whispers) == 'table' and Server.config.whispers or {}
	local whisperChannelId = constants.WhisperTabEnabled == true and 'whispers' or (Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId)
	if not (constants.ChannelById and constants.ChannelById[whisperChannelId]) then
		whisperChannelId = constants.DefaultChannelId
	end

	local whisperChannel = constants.ChannelById[whisperChannelId] or {id = whisperChannelId, label = 'Whispers'}
	local incomingColor = Server and Server.config and Server.config.chat and Server.config.chat.whisperColor or {254, 127, 156}

	for i = 1, #queue do
		local entry = type(queue[i]) == 'table' and queue[i] or {}
		local senderCitizenId = trimString(entry.senderCitizenId or '')
		local senderConversationId = trimString(entry.senderConversationId or '')
		if senderConversationId == '' and senderCitizenId ~= '' then
			senderConversationId = buildCharacterIdentityKey(senderCitizenId) or senderCitizenId
		end

		local senderName = trimString(entry.senderName or '')
		if senderName == '' then
			senderName = senderCitizenId ~= '' and senderCitizenId or 'Unknown'
		end

		Server.sendRawChannelMessage({src}, whisperChannel.id, {
			label = whisperChannel.label,
			color = incomingColor,
			args = {'[DM] ' .. senderName, tostring(entry.text or '')},
			timestamp = normalizeStoredTimestamp(entry.timestamp),
			metadata = {
				type = 'whisper',
				direction = 'in',
				offline = true,
				conversationId = senderConversationId ~= '' and senderConversationId or tostring(senderCitizenId ~= '' and senderCitizenId or ('id:' .. tostring(entry.senderSource or senderName))),
				conversationScope = trimString(entry.senderConversationScope or '') ~= '' and trimString(entry.senderConversationScope or '') or 'character',
				peerId = tonumber(entry.senderSource) or nil,
				peerName = senderName,
				peerCharacterId = senderCitizenId ~= '' and senderCitizenId or nil,
				license = entry.senderLicense,
				source = tonumber(entry.senderSource) or nil,
				replyTo = type(entry.replyTo) == 'table' and entry.replyTo or nil
			}
		})
	end

	saveOfflineWhispers(citizenid, {})
	return true
end

function Server.loadAndDeliverHistory(source, replaceExisting)
	local src = tonumber(source)
	if not src then return end

	local citizenid = citizenidCache[src]
	if not citizenid or citizenid == '' then return end

	local history = Server.loadCharacterHistory(citizenid)

	playerHistoryBuffers[src] = {}
	for channelId, messages in pairs(history) do
		playerHistoryBuffers[src][channelId] = messages
	end

	CreateThread(function()
		Wait(2000)
		if not playerHistoryBuffers[src] then return end

		local payload = {}
		for channelId, messages in pairs(history) do
			for _, msg in ipairs(messages) do
				local restoredMessage = {
					messageId = msg.messageId,
					channel = msg.channel or channelId,
					label = msg.label,
					color = msg.color,
					args = msg.args,
					template = msg.template,
					templateId = msg.templateId,
					multiline = msg.multiline,
					metadata = msg.metadata,
					timestamp = msg.timestamp,
					restored = true
				}
				payload[#payload + 1] = buildDeletedEnvelopeForSource(src, restoredMessage) or restoredMessage
			end
		end

		table.sort(payload, function(a, b)
			return normalizeStoredTimestamp(a.timestamp) < normalizeStoredTimestamp(b.timestamp)
		end)

		TriggerClientEvent(replaceExisting == true and 'poodlechat:characterSwitch' or 'poodlechat:restoreHistory', src, payload)
		Server.deliverOfflineWhispers(src)
	end)
end

function Server.clearPlayerHistoryBuffer(source)
	local src = tonumber(source)
	if src then
		playerHistoryBuffers[src] = nil
		sessionHistoryBuffers[src] = nil
		historyDirtyBySource[tostring(src)] = nil
	end
end

function Server.clearCharacterHistoryBuffer(source)
	local src = tonumber(source)
	if src then
		playerHistoryBuffers[src] = nil
		historyDirtyBySource[tostring(src)] = nil
	end
end

function Server.clearPlayerChatHistory(source)
	local src = tonumber(source)
	if not src then
		return false
	end

	local citizenid = citizenidCache[src]
	if citizenid and citizenid ~= '' then
		local channelIds = getPersistedChannelIds()
		for i = 1, #channelIds do
			Server.clearCharacterHistory(citizenid, channelIds[i])
		end
	end

	playerHistoryBuffers[src] = {}
	sessionHistoryBuffers[src] = {}
	historyDirtyBySource[tostring(src)] = nil
	return true
end

function Server.deleteConversationHistory(source, channelId, conversationId)
	local src = tonumber(source)
	local normalizedChannelId = trimString(channelId)
	local normalizedConversationId = trimString(conversationId)
	if not src or normalizedChannelId == '' or normalizedConversationId == '' then
		return false
	end

	local channelBuffers = playerHistoryBuffers[src]
	if type(channelBuffers) ~= 'table' or type(channelBuffers[normalizedChannelId]) ~= 'table' then
		return false
	end

	local filtered = {}
	local changed = false
	for i = 1, #channelBuffers[normalizedChannelId] do
		local entry = channelBuffers[normalizedChannelId][i]
		local metadata = type(entry) == 'table' and type(entry.metadata) == 'table' and entry.metadata or nil
		if metadata and trimString(metadata.conversationId or '') == normalizedConversationId then
			changed = true
		else
			filtered[#filtered + 1] = entry
		end
	end

	if not changed then
		return false
	end

	channelBuffers[normalizedChannelId] = filtered
	Server.savePlayerHistory(src)
	return true
end

Server.getDeletedMessageEntry = getDeletedMessageEntry
Server.buildDeletedEnvelopeForSource = buildDeletedEnvelopeForSource
Server.registerDeletedMessage = registerDeletedMessage
Server.findLoadedMessageById = findLoadedMessageById
Server.collectLoadedRecipientsForMessage = collectLoadedRecipientsForMessage
Server.rememberLiveMessage = rememberLiveMessage
Server.nextMessageId = nextMessageId

AddEventHandler('onResourceStop', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then
		return
	end

	for sourceId in pairs(playerHistoryBuffers) do
		Server.savePlayerHistory(sourceId)
	end
end)

ensureHistoryAutosaveThread()
