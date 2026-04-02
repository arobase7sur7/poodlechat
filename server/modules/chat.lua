local Server = PoodleChatServer
local constants = nil
local handlersRegistered = false

local function ensureContext()
	if constants then
		return true
	end

	constants = Server.constants
	return constants ~= nil
end

local function getChannel(channelId)
	local id = Server.normalizeKey(channelId) or constants.DefaultChannelId
	local channel = constants.ChannelById[id]
	if channel then
		return channel
	end
	return constants.ChannelById[constants.DefaultChannelId]
end

local function canSendToChannel(source, channelId)
	local id = Server.normalizeKey(channelId)
	if not id then
		return false
	end

	local channel = constants.ChannelById[id]
	if not channel then
		return false
	end

	if not Server.canAccessChannel(source, id) then
		return false
	end

	return channel.canSend ~= false
end

local function buildEnvelope(channelId, payload)
	local channel = getChannel(channelId)
	local label = tostring(payload.label or channel.label or channel.id)
	local color = Server.normalizeRgbColor(payload.color, channel.color)
	local args = type(payload.args) == 'table' and payload.args or nil

	if not args then
		local text = tostring(payload.text or '')
		if text ~= '' then
			args = {label, text}
		else
			args = {label}
		end
	end

	return {
		channel = channel.id,
		label = label,
		color = color,
		args = args,
		template = payload.template,
		templateId = payload.templateId,
		multiline = payload.multiline ~= false,
		metadata = type(payload.metadata) == 'table' and payload.metadata or nil
	}
end

local function dispatchEnvelope(targets, envelope)
	Server.triggerClientEventForTargets('poodlechat:channelMessage', targets, envelope)
end

local function sendRawChannelMessage(targets, channelId, payload)
	local envelope = buildEnvelope(channelId, payload)
	dispatchEnvelope(targets, envelope)
	return envelope
end

local function sendSystemMessage(target, text, color, channelId)
	sendRawChannelMessage({target}, channelId or constants.DefaultChannelId, {
		label = 'System',
		color = color or {255, 255, 255},
		args = {'System', tostring(text or '')}
	})
end

local function emitBubble(source, text)
	if Server.config.bubble.enabled ~= true then
		return
	end

	local message = Server.normalizeMessage(text)
	if message == '' then
		return
	end

	local maxLen = math.max(1, tonumber(Server.config.bubble.maxLength) or 80)
	if #message > maxLen then
		message = message:sub(1, maxLen)
	end

	local distance = tonumber(Server.config.bubble.maxDistance) or constants.LocalMessageDistance
	local recipients = Server.getNearbyPlayers(source, distance)
	Server.triggerClientEventForTargetsNoFallback('poodlechat:bubbleMessage', recipients, source, message)
end

local function getChannelRecipients(source, channelId)
	local channel = getChannel(channelId)
	if not channel then
		return nil
	end

	if channel.id == 'local' then
		return Server.getNearbyPlayers(source, constants.LocalMessageDistance)
	end

	if channel.id == 'staff' then
		local recipients = {}
		for _, playerId in ipairs(GetPlayers()) do
			if Server.canAccessChannel(playerId, channel.id) then
				recipients[#recipients + 1] = playerId
			end
		end
		return recipients
	end

	if channel.requiresAce then
		local recipients = {}
		for _, playerId in ipairs(GetPlayers()) do
			if Server.canAccessChannel(playerId, channel.id) then
				recipients[#recipients + 1] = playerId
			end
		end
		return recipients
	end

	return nil
end

local function formatChatPrefix(channelLabel, name)
	return string.format('[%s] %s', tostring(channelLabel), tostring(name))
end

local function routePlayerMessageToChannel(source, channelId, message, options)
	local opts = type(options) == 'table' and options or {}
	local channel = getChannel(channelId)
	if not channel then
		return
	end

	if not Server.canAccessChannel(source, channel.id) then
		channel = getChannel(constants.DefaultChannelId)
	end

	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name, roleColor = Server.getNameWithRoleAndColor(source)
	local color = Server.normalizeRgbColor(opts.color, roleColor or channel.color)
	local label = tostring(opts.label or channel.label)
	local recipients = getChannelRecipients(source, channel.id)
	local license = Server.getMessageLicense(source)

	local envelope = sendRawChannelMessage(recipients, channel.id, {
		label = label,
		color = color,
		args = {formatChatPrefix(label, name), text},
		metadata = {
			source = tonumber(source) or source,
			license = license,
			channel = channel.id,
			type = 'chat'
		}
	})

	if opts.emitBubble ~= false then
		emitBubble(source, text)
	end

	if constants.PrintToConsole and opts.printToConsole ~= false then
		local consoleLabel = channel.label or channel.id
		print(('[%s] %s: %s'):format(consoleLabel, name, text))
	end

	if opts.discordKind then
		Server.sendDiscordWebhook(opts.discordKind, source, name, Server.sanitizeDiscordText(text), nil)
	elseif channel.id == 'local' then
		Server.sendDiscordWebhook('local', source, name, Server.sanitizeDiscordText(text), nil)
	elseif channel.id == 'global' then
		Server.sendDiscordWebhook('global', source, name, Server.sanitizeDiscordText(text), nil)
	elseif channel.id == 'staff' then
		Server.sendDiscordWebhook('staff', source, name, Server.sanitizeDiscordText(text), nil)
	end

	return envelope
end

local function localMessage(source, message)
	return routePlayerMessageToChannel(source, 'local', message, {
		label = getChannel('local').label,
		discordKind = 'local'
	})
end

local function globalMessage(source, message)
	return routePlayerMessageToChannel(source, 'global', message, {
		label = getChannel('global').label,
		discordKind = 'global'
	})
end

local function staffMessage(source, message)
	if not Server.canAccessChannel(source, 'staff') then
		sendSystemMessage(source, 'You do not have access to the Staff channel.', {255, 0, 0}, constants.DefaultChannelId)
		return
	end

	return routePlayerMessageToChannel(source, 'staff', message, {
		label = getChannel('staff').label,
		discordKind = 'staff'
	})
end

local function actionMessage(source, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name = Server.getName(source)
	local license = Server.getMessageLicense(source)
	local recipients = Server.getNearbyPlayers(source, constants.ActionMessageDistance)
	sendRawChannelMessage(recipients, 'local', {
		label = 'ME',
		color = Server.config.chat.actionColor,
		args = {'* ' .. name, text},
		metadata = {
			source = tonumber(source) or source,
			license = license,
			type = 'action'
		}
	})
	emitBubble(source, text)

	if constants.PrintToConsole then
		print(('^6%s %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('action', source, name, Server.sanitizeDiscordText(text), nil)
end

local function getPlayerId(id)
	if not id then
		return nil
	end

	local players = GetPlayers()
	local targetId = tostring(id)

	for _, playerId in ipairs(players) do
		if playerId == targetId then
			return playerId
		end
	end

	local targetName = targetId:lower()

	for _, playerId in ipairs(players) do
		if Server.getName(playerId):lower() == targetName then
			return playerId
		end
	end

	return nil
end

local function getWhisperDeliveryChannel()
	local channelId = 'whispers'
	if constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	return getChannel(channelId)
end

local function whisperMessage(source, id, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local target = getPlayerId(id)
	if not target then
		sendSystemMessage(source, 'No user with ID or name ' .. tostring(id), {255, 0, 0}, constants.DefaultChannelId)
		TriggerClientEvent('poodlechat:whisperError', source, id)
		return
	end

	local name = Server.getNameWithId(source)
	local targetName = Server.getNameWithId(target)
	local sendLicense = Server.getMessageLicense(source)
	local recvLicense = Server.getMessageLicense(target)
	local senderConversationId = tostring(recvLicense or ('id:' .. tostring(target)))
	local targetConversationId = tostring(sendLicense or ('id:' .. tostring(source)))
	local whisperChannel = getWhisperDeliveryChannel()

	sendRawChannelMessage({source}, whisperChannel.id, {
		label = whisperChannel.label,
		color = Server.config.chat.whisperEchoColor,
		args = {'[DM -> ' .. targetName .. ']', text},
		metadata = {
			type = 'whisper',
			direction = 'out',
			conversationId = senderConversationId,
			peerId = tonumber(target) or target,
			peerName = targetName,
			source = tonumber(source) or source,
			license = recvLicense
		}
	})

	sendRawChannelMessage({target}, whisperChannel.id, {
		label = whisperChannel.label,
		color = Server.config.chat.whisperColor,
		args = {'[DM] ' .. name, text},
		metadata = {
			type = 'whisper',
			direction = 'in',
			conversationId = targetConversationId,
			peerId = tonumber(source) or source,
			peerName = name,
			source = tonumber(source) or source,
			license = sendLicense
		}
	})

	TriggerClientEvent('poodlechat:setReplyTo', target, source)
	TriggerClientEvent('poodlechat:setReplyTo', source, target)

	if constants.PrintToConsole then
		print(('^9[Whisper] %s -> %s^7: %s^7'):format(Server.getRealName(source), Server.getRealName(target), text))
	end
end

local function sendWhisperTargets(source)
	local targets = {}
	for _, playerId in ipairs(GetPlayers()) do
		if tonumber(playerId) ~= tonumber(source) then
			targets[#targets + 1] = {
				id = tonumber(playerId) or playerId,
				name = Server.getName(playerId),
				label = Server.getNameWithId(playerId),
				fivemName = Server.getRealName(playerId)
			}
		end
	end

	table.sort(targets, function(a, b)
		return tonumber(a.id) < tonumber(b.id)
	end)

	TriggerClientEvent('poodlechat:whisperTargets', source, targets)
end

local function getFirstAccessibleChannelIdForSource(source)
	local list = constants.ChannelList or {}
	for i = 1, #list do
		local channel = list[i]
		if channel and channel.id and Server.canAccessChannel(source, channel.id) then
			return channel.id
		end
	end

	return constants.DefaultChannelId
end

local function resolveExportChannelForSource(source, requested)
	local channelId = Server.normalizeKey(requested) or constants.DefaultChannelId

	if channelId == 'whispers' and constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	if not Server.canAccessChannel(source, channelId) then
		channelId = getFirstAccessibleChannelIdForSource(source)
	end

	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	return channelId
end

local function normalizeExportTargets(target)
	local normalized = {}
	local seen = {}

	local function appendPlayerId(playerId)
		if playerId == nil then
			return
		end

		local key = tostring(playerId)
		if seen[key] then
			return
		end

		seen[key] = true
		normalized[#normalized + 1] = key
	end

	local function appendTarget(value)
		local playerId = getPlayerId(value)
		if not playerId then
			return
		end

		appendPlayerId(playerId)
	end

	if target == nil or tonumber(target) == -1 then
		local players = GetPlayers()
		for i = 1, #players do
			appendPlayerId(players[i])
		end
		return normalized
	end

	if type(target) == 'table' then
		for i = 1, #target do
			appendTarget(target[i])
		end
		return normalized
	end

	appendTarget(target)
	return normalized
end

local function sendChannelMessageExport(target, payload)
	if type(payload) ~= 'table' then
		return false
	end

	local targets = normalizeExportTargets(target)
	if #targets == 0 then
		return false
	end

	local requestedChannelId = Server.normalizeKey(payload.channel) or constants.DefaultChannelId

	for i = 1, #targets do
		local targetSource = targets[i]
		local resolvedChannelId = resolveExportChannelForSource(targetSource, requestedChannelId)
		sendRawChannelMessage({targetSource}, resolvedChannelId, payload)
	end

	return true
end

local function sendBubbleMessageExport(sourceId, text)
	local id = tonumber(sourceId)
	if not id then
		return false
	end

	emitBubble(id, text)
	return true
end

local function setPermissions(source)
	local channelPermissions = Server.getPlayerChannelPermissions(source)
	local canAccessStaff = channelPermissions.staff == true

	TriggerClientEvent('poodlechat:setPermissions', source, {
		canAccessStaffChannel = canAccessStaff,
		channels = channelPermissions,
		defaultChannel = constants.DefaultChannelId
	})
end

local function localCommand(source, args)
	localMessage(source, table.concat(args, ' '))
end

local function getMessageChannelForInput(source, requested)
	local channelId = Server.normalizeKey(requested) or constants.DefaultChannelId
	if channelId == 'whispers' and constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	if not Server.canAccessChannel(source, channelId) then
		channelId = getFirstAccessibleChannelIdForSource(source)
	end

	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	return channelId
end

local function routeInputMessage(source, channelId, message)
	if channelId == 'whispers' and constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	if channelId == 'whispers' then
		sendSystemMessage(source, 'Select a whisper conversation or use /w [id] [message].', {255, 128, 128}, constants.DefaultChannelId)
		return
	end

	if channelId == 'local' then
		localMessage(source, message)
		return
	end

	if channelId == 'staff' then
		staffMessage(source, message)
		return
	end

	if channelId == 'global' then
		globalMessage(source, message)
		return
	end

	routePlayerMessageToChannel(source, channelId, message)
end

local function registerChatHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	AddEventHandler('_chat:messageEntered', function(author, color, message, channel)
		if not message or not author then
			return
		end

		local channelId = getMessageChannelForInput(source, channel)
		if not canSendToChannel(source, channelId) then
			sendSystemMessage(source, 'You cannot send messages in this channel.', {255, 128, 128}, channelId)
			return
		end

		TriggerEvent('chatMessage', source, author, message, channelId)

		if WasEventCanceled() then
			return
		end

		if string.sub(message, 1, 1) == '/' then
			return
		end

		routeInputMessage(source, channelId, message)
	end)

	AddEventHandler('__cfx_internal:commandFallback', function(command)
		local name = Server.getNameWithId(source)
		local text = '/' .. tostring(command)

		TriggerEvent('chatMessage', source, name, text, constants.DefaultChannelId)

		if not WasEventCanceled() then
			sendRawChannelMessage(nil, constants.DefaultChannelId, {
				label = getChannel(constants.DefaultChannelId).label,
				color = {255, 255, 255},
				args = {name, text},
				metadata = {
					type = 'commandFallback',
					source = tonumber(source) or source
				}
			})
		end

		CancelEvent()
	end)

	AddEventHandler('chat:init', function()
		sendRawChannelMessage(nil, constants.DefaultChannelId, {
			label = getChannel(constants.DefaultChannelId).label,
			color = {255, 255, 255},
			args = {'^2* ' .. Server.getName(source) .. '^r^2 joined.'},
			metadata = {
				type = 'join'
			}
		})
		Server.refreshCommands(source)
		setPermissions(source)
	end)

	AddEventHandler('onServerResourceStart', function()
		Wait(constants.refreshCommandsDelayMs)

		for _, player in ipairs(GetPlayers()) do
			Server.refreshCommands(player)
			setPermissions(player)
		end
	end)

	AddEventHandler('poodlechat:globalMessage', function(message)
		globalMessage(source, message)
	end)

	AddEventHandler('poodlechat:actionMessage', function(message)
		actionMessage(source, message)
	end)

	AddEventHandler('poodlechat:whisperMessage', function(id, message)
		whisperMessage(source, id, message)
	end)

	AddEventHandler('poodlechat:getWhisperTargets', function()
		sendWhisperTargets(source)
	end)

	AddEventHandler('poodlechat:staffMessage', function(message)
		staffMessage(source, message)
	end)

	AddEventHandler('poodlechat:getPermissions', function()
		setPermissions(source)
	end)

	local sayCommand = constants.CommandByKey.say
	if type(sayCommand) == 'table' and sayCommand.enabled == true then
		Server.registerCommandWithAliases(sayCommand, function(sourceId, args)
			if sourceId and sourceId > 0 then
				localCommand(sourceId, args)
			else
				sendRawChannelMessage(nil, 'global', {
					label = 'Console',
					color = {255, 255, 255},
					args = {'console', table.concat(args, ' ')},
					metadata = {
						type = 'console'
					}
				})
			end
		end, true)
	end

	RegisterCommand('poodlechat_refresh_perms', function()
		for _, playerId in ipairs(GetPlayers()) do
			setPermissions(playerId)
		end
	end, true)

	exports('SendChannelMessage', sendChannelMessageExport)
	exports('SendBubbleMessage', sendBubbleMessageExport)

	GetPlayerId = getPlayerId
	LocalMessage = localMessage
	GlobalMessage = globalMessage
	StaffMessage = staffMessage

	handlersRegistered = true
end

Server.sendRawChannelMessage = sendRawChannelMessage
Server.sendSystemMessage = sendSystemMessage
Server.emitBubble = emitBubble
Server.localMessage = localMessage
Server.globalMessage = globalMessage
Server.staffMessage = staffMessage
Server.actionMessage = actionMessage
Server.whisperMessage = whisperMessage
Server.getPlayerId = getPlayerId
Server.setPermissions = setPermissions
Server.registerChatHandlers = registerChatHandlers
