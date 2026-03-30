PoodleChatServer = PoodleChatServer or {}

local Server = PoodleChatServer

RegisterServerEvent('chat:init')
RegisterServerEvent('chat:addTemplate')
RegisterServerEvent('chat:addMessage')
RegisterServerEvent('chat:addSuggestion')
RegisterServerEvent('chat:removeSuggestion')
RegisterServerEvent('_chat:messageEntered')
RegisterServerEvent('chat:clear')
RegisterServerEvent('__cfx_internal:commandFallback')
RegisterNetEvent('playerJoining')

RegisterNetEvent('poodlechat:staffMessage')
RegisterNetEvent('poodlechat:globalMessage')
RegisterNetEvent('poodlechat:actionMessage')
RegisterNetEvent('poodlechat:whisperMessage')
RegisterNetEvent('poodlechat:getPermissions')
RegisterNetEvent('poodlechat:report')
RegisterNetEvent('poodlechat:mute')
RegisterNetEvent('poodlechat:unmute')
RegisterNetEvent('poodlechat:showMuted')
RegisterNetEvent('poodlechat:typingState')
RegisterNetEvent('poodlechat:bubbleMessage')

local chatConfig = Config.Chat or {}
local accessConfig = Config.Access or {}
local typingConfig = Config.TypingIndicator or {}
local bubbleConfig = Config.ChatBubbles or {}
local discordConfig = Config.Discord or {}
local runtimeConfig = Config.Runtime or {}
local serverRuntime = type(runtimeConfig.server) == 'table' and runtimeConfig.server or {}

local IdentifierType = tostring(accessConfig.identifier or 'license')
local StaffChannelAce = tostring(accessConfig.staffChannelAce or 'chat.staffChannel')
local NoMuteAce = tostring(accessConfig.noMuteAce or 'chat.noMute')
local Roles = type(accessConfig.roles) == 'table' and accessConfig.roles or {}

local MaxNicknameLen = math.max(1, tonumber(chatConfig.maxNicknameLen) or 30)
local PrintToConsole = chatConfig.printToConsole ~= false
local LocalMessageColor = chatConfig.localColor or {0, 153, 204}
local GlobalMessageColor = chatConfig.globalColor or {212, 175, 55}
local StaffMessageColor = chatConfig.staffColor or {255, 64, 0}
local ActionMessageDistance = tonumber(chatConfig.actionDistance) or 50.0
local LocalMessageDistance = tonumber(chatConfig.localDistance) or 50.0

Server.config = {
	chat = chatConfig,
	access = accessConfig,
	typing = typingConfig,
	bubble = bubbleConfig,
	discord = discordConfig,
	runtime = serverRuntime
}

Server.constants = {
	IdentifierType = IdentifierType,
	StaffChannelAce = StaffChannelAce,
	NoMuteAce = NoMuteAce,
	Roles = Roles,
	MaxNicknameLen = MaxNicknameLen,
	PrintToConsole = PrintToConsole,
	LocalMessageColor = LocalMessageColor,
	GlobalMessageColor = GlobalMessageColor,
	StaffMessageColor = StaffMessageColor,
	ActionMessageDistance = ActionMessageDistance,
	LocalMessageDistance = LocalMessageDistance,
	refreshCommandsDelayMs = math.max(0, tonumber(serverRuntime.refreshCommandsDelayMs) or 500)
}

local logColors = {
	name = '\x1B[35m',
	default = '\x1B[0m',
	error = '\x1B[31m',
	success = '\x1B[32m',
	warning = '\x1B[33m'
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

local function getDiscordColor(kind, fallback)
	local colors = type(discordConfig.colors) == 'table' and discordConfig.colors or {}
	local base = colors[kind]
	if base == nil then
		base = colors.default
	end
	return toDiscordColor(base, fallback)
end

local function isDiscordConfigured()
	return discordConfig.enabled == true and isSet(discordConfig.webhook)
end

local function isDiscordKindEnabled(kind)
	if not isDiscordConfigured() then
		return false
	end

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

local nicknames = decodeTableOrEmpty(GetResourceKvpString('nicknames'))
local identifierCache = {}
local typingStateBySource = {}

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

function GetIDFromSource(idType, source)
	local normalizedType = idType and tostring(idType):lower()
	if not normalizedType or not source then
		return nil
	end

	local identifiers = getIdentifierMap(source)
	return identifiers[normalizedType]
end

function GetNickname(source)
	local identifier = GetIDFromSource(IdentifierType, source)
	if identifier then
		return nicknames[identifier]
	end
end

function HasNickname(source)
	local identifier = GetIDFromSource(IdentifierType, source)
	if identifier then
		return nicknames[identifier] ~= nil
	end

	return false
end

function SetNickname(source, nickname)
	local identifier = GetIDFromSource(IdentifierType, source)
	if not identifier then
		return false
	end

	nicknames[identifier] = nickname
	SetResourceKvp('nicknames', json.encode(nicknames))
	return true
end

function GetRealName(source)
	return GetPlayerName(source) or '?'
end

function GetName(source)
	if HasNickname(source) then
		return GetNickname(source)
	end

	return GetRealName(source)
end

exports('getName', GetName)

function GetNameWithId(source)
	return '[' .. source .. '] ' .. GetName(source)
end

RegisterCommand('nick', function(source, args)
	local nickname = args[1] and table.concat(args, ' ')

	if nickname and string.len(nickname) > MaxNicknameLen then
		TriggerClientEvent('chat:addMessage', source, {
			color = {255, 0, 0},
			args = {'Error', 'Nicknames cannot be more than ' .. MaxNicknameLen .. ' characters long'}
		})
		return
	end

	if SetNickname(source, nickname) then
		if nickname then
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 255, 128},
				args = {'Your nickname was set to ' .. nickname}
			})
		else
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 255, 128},
				args = {'Your nickname has been unset'}
			})
		end
	else
		TriggerClientEvent('chat:addMessage', source, {
			color = {255, 0, 0},
			args = {'Error', 'Failed to set nickname'}
		})
	end
end, true)

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
	if IsPlayerAceAllowed(source, NoMuteAce) then
		return false
	end

	return GetIDFromSource(IdentifierType, source)
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
	local name = GetName(source)
	local role = nil

	for index = 1, #Roles do
		local current = Roles[index]
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

Server.state = {
	nicknames = nicknames,
	identifierCache = identifierCache,
	typingStateBySource = typingStateBySource
}

Server.log = log
Server.decodeTableOrEmpty = decodeTableOrEmpty
Server.isSet = isSet
Server.toDiscordColor = toDiscordColor
Server.getDiscordColor = getDiscordColor
Server.isDiscordConfigured = isDiscordConfigured
Server.isDiscordKindEnabled = isDiscordKindEnabled
Server.sanitizeDiscordText = sanitizeDiscordText
Server.sendDiscordWebhook = sendDiscordWebhook
Server.clearIdentifierCache = clearIdentifierCache
Server.getIdentifierMap = getIdentifierMap
Server.normalizeMessage = normalizeMessage
Server.refreshCommands = refreshCommands
Server.getMessageLicense = getMessageLicense
Server.triggerClientEventForTargets = triggerClientEventForTargets
Server.triggerClientEventForTargetsNoFallback = triggerClientEventForTargetsNoFallback
Server.getNearbyPlayers = getNearbyPlayers
Server.getNameWithRoleAndColor = getNameWithRoleAndColor
Server.escapePattern = escapePattern

