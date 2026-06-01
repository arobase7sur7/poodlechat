local Server = PoodleChatServer
local constants = nil
local handlersRegistered = false
local messageHooks = {}
local registeredModes = {}
local getLocalChatDistanceForSource = nil

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

local function cloneMetadata(payload)
	if type(payload) ~= 'table' then
		return {}
	end

	local copy = {}
	for key, value in pairs(payload) do
		copy[key] = value
	end
	return copy
end

local function normalizeEnvelopeMetadata(payload, messageId, authorSource, authorName)
	local metadata = cloneMetadata(payload)
	metadata.messageId = messageId

	if metadata.authorSource == nil and authorSource ~= nil then
		metadata.authorSource = tonumber(authorSource) or authorSource
	end

	if (metadata.authorName == nil or tostring(metadata.authorName) == '') and authorName ~= nil then
		metadata.authorName = tostring(authorName)
	end

	if metadata.senderDistance == nil and metadata.distance ~= nil then
		metadata.senderDistance = metadata.distance
	end

	return metadata
end

local function buildEnvelope(channelId, payload)
	local channel = getChannel(channelId)
	local label = tostring(payload.label or channel.label or channel.id)
	local color = Server.normalizeRgbColor(payload.color, channel.color)
	local args = type(payload.args) == 'table' and payload.args or nil
	local messageId = payload.messageId or (type(Server.nextMessageId) == 'function' and Server.nextMessageId()) or tostring(os.time())

	if not args then
		local text = tostring(payload.text or '')
		if text ~= '' then
			args = {label, text}
		else
			args = {label}
		end
	end

	return {
		messageId = tostring(messageId),
		channel = channel.id,
		label = label,
		color = color,
		args = args,
		template = payload.template,
		templateId = payload.templateId,
		multiline = payload.multiline ~= false,
		metadata = normalizeEnvelopeMetadata(
			type(payload.metadata) == 'table' and payload.metadata or {},
			tostring(messageId),
			payload.authorSource,
			payload.authorName
		),
		timestamp = tonumber(payload.timestamp) or os.time()
	}
end

local function normalizeRoutingTargets(targets)
	if targets == nil or targets == -1 then
		return GetPlayers()
	end
	if type(targets) == 'table' then
		return targets
	end
	return {targets}
end

local function applyMessageHooks(source, envelope, targets)
	local canceled = false
	local routedTargets = targets
	local seObject = nil
	local message = type(envelope) == 'table' and envelope or {}

	for i = 1, #messageHooks do
		local hook = messageHooks[i]
		if type(hook) == 'function' then
			local hookRef = {
				updateMessage = function(nextMessage)
					if type(nextMessage) == 'table' then
						for key, value in pairs(nextMessage) do
							message[key] = value
						end
					end
				end,
				cancel = function()
					canceled = true
				end,
				setSeObject = function(nextSeObject)
					seObject = tostring(nextSeObject or '')
				end,
				setRouting = function(nextRouting)
					routedTargets = nextRouting
				end
			}
			pcall(hook, source or 0, message, hookRef)
			if canceled then
				break
			end
		end
	end

	return canceled, message, routedTargets, seObject
end

local function dispatchEnvelope(targets, envelope, seObject)
	local recipients = type(targets) == 'table' and targets or GetPlayers()
	for _, targetId in ipairs(recipients) do
		local resolvedTarget = tonumber(targetId) or targetId
		if not seObject or seObject == '' or IsPlayerAceAllowed(resolvedTarget, seObject) == true then
			local outbound = type(Server.buildDeletedEnvelopeForSource) == 'function'
				and Server.buildDeletedEnvelopeForSource(resolvedTarget, envelope)
				or envelope
			TriggerClientEvent('poodlechat:channelMessage', resolvedTarget, outbound)
			if Server.appendToHistoryBuffer and envelope and envelope.channel then
				Server.appendToHistoryBuffer(resolvedTarget, envelope.channel, envelope)
			end
		end
	end
end

local function sendRawChannelMessage(targets, channelId, payload)
	local envelope = buildEnvelope(channelId, payload)
	local source = payload and payload.authorSource or nil
	local canceled, hookedEnvelope, routedTargets, seObject = applyMessageHooks(source, envelope, targets)
	if canceled then
		return hookedEnvelope
	end
	targets = routedTargets
	envelope = hookedEnvelope
	if type(Server.rememberLiveMessage) == 'function' then
		Server.rememberLiveMessage(targets, envelope)
	end
	dispatchEnvelope(normalizeRoutingTargets(targets), envelope, seObject)
	return envelope
end

local function sendSystemMessage(target, text, color, channelId)
	sendRawChannelMessage({target}, channelId or constants.DefaultChannelId, {
		label = 'System',
		color = color or {255, 255, 255},
		args = {'System', tostring(text or '')},
		authorName = 'System',
		metadata = {
			type = 'system',
			authorName = 'System'
		}
	})
end

local function getBubbleDistanceForSource(source)
	local bubbleConfig = Server.config.bubble or {}
	if bubbleConfig.rangeMode == 'voice' then
		return getLocalChatDistanceForSource(source)
	end

	return tonumber(bubbleConfig.maxDistance) or constants.LocalMessageDistance
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

	local distance = tonumber(getBubbleDistanceForSource(source)) or constants.LocalMessageDistance
	local recipients = Server.getNearbyPlayers(source, distance)
	Server.triggerClientEventForTargetsNoFallback('poodlechat:bubbleMessage', recipients, source, message, distance)
end

local function isVoiceIntegrationAvailable()
	if constants.VoiceEnabled ~= true then
		return false
	end

	if GetResourceState(tostring(constants.VoiceResourceName or 'pma-voice')) ~= 'started' then
		return false
	end

	return true
end

local function getVoiceProximityStateForSource(source)
	if not isVoiceIntegrationAvailable() then
		return nil
	end

	local player = Player(source)
	if not player or type(player.state) ~= 'table' then
		return nil
	end

	local proximity = player.state.proximity
	if type(proximity) ~= 'table' then
		return nil
	end

	return proximity
end

local function formatVoiceModeLabel(rawMode)
	if type(rawMode) ~= 'string' then
		return nil
	end

	local cleaned = rawMode:gsub('^%s+', ''):gsub('%s+$', '')
	if cleaned == '' then
		return nil
	end

	cleaned = cleaned:gsub('[_%-]+', ' '):gsub('%s+', ' '):lower()
	cleaned = cleaned:gsub('(%a)([%w\']*)', function(first, rest)
		return string.upper(first) .. rest
	end)

	return cleaned
end

local function getVoiceRangeForSource(source)
	local syncedDistance = Server.getSyncedVoiceDistance and Server.getSyncedVoiceDistance(source) or nil
	if syncedDistance and syncedDistance > 0 then
		return syncedDistance
	end

	local proximity = getVoiceProximityStateForSource(source)
	if type(proximity) ~= 'table' then
		return nil
	end

	local distance = tonumber(proximity.distance)
	if not distance or distance <= 0 then
		return nil
	end

	return distance
end

local function getVoiceModeLabelForSource(source)
	local proximity = getVoiceProximityStateForSource(source)
	if type(proximity) ~= 'table' then
		return nil
	end

	local modeLabel = formatVoiceModeLabel(proximity.mode)
	if modeLabel and modeLabel ~= '' then
		return modeLabel
	end

	return nil
end

local function getLocalChannelDisplayLabel(source)
	if isVoiceIntegrationAvailable() then
		local voiceLabel = getVoiceModeLabelForSource(source)
		if voiceLabel and voiceLabel ~= '' then
			return voiceLabel
		end
		return 'Range'
	end

	return getChannel('local').label
end

getLocalChatDistanceForSource = function(source)
	return getVoiceRangeForSource(source) or tonumber(constants.VoiceFallbackLocalDistance) or constants.LocalMessageDistance
end

local function getChannelRecipients(source, channelId)
	local channel = getChannel(channelId)
	if not channel then
		return nil
	end

	if channel.id == 'local' then
		return Server.getNearbyPlayers(source, getLocalChatDistanceForSource(source))
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
	local extraMetadata = type(opts.metadata) == 'table' and cloneMetadata(opts.metadata) or {}
	local envelopeMetadata = {
		source = tonumber(source) or source,
		authorSource = tonumber(source) or source,
		authorName = name,
		license = license,
		channel = channel.id,
		type = 'chat',
		distance = opts.distance,
		senderDistance = opts.distance
	}

	for key, value in pairs(extraMetadata) do
		envelopeMetadata[key] = value
	end

	if type(envelopeMetadata.replyTo) == 'table' then
		envelopeMetadata.replyTo = cloneMetadata(envelopeMetadata.replyTo)
	end

	local envelope = sendRawChannelMessage(recipients, channel.id, {
		label = label,
		color = color,
		args = {formatChatPrefix(label, name), text},
		authorSource = source,
		authorName = name,
		metadata = envelopeMetadata
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

local function localMessage(source, message, options)
	local opts = type(options) == 'table' and options or {}
	return routePlayerMessageToChannel(source, 'local', message, {
		label = getLocalChannelDisplayLabel(source),
		discordKind = 'local',
		distance = getLocalChatDistanceForSource(source),
		metadata = opts.metadata
	})
end

local function globalMessage(source, message, options)
	local opts = type(options) == 'table' and options or {}
	return routePlayerMessageToChannel(source, 'global', message, {
		label = getChannel('global').label,
		discordKind = 'global',
		metadata = opts.metadata
	})
end

local function staffMessage(source, message, options)
	if not Server.canAccessChannel(source, 'staff') then
		sendSystemMessage(source, 'You do not have access to the Staff channel.', {255, 0, 0}, constants.DefaultChannelId)
		return
	end

	local opts = type(options) == 'table' and options or {}
	return routePlayerMessageToChannel(source, 'staff', message, {
		label = getChannel('staff').label,
		discordKind = 'staff',
		metadata = opts.metadata
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
		authorSource = source,
		authorName = name,
		metadata = {
			source = tonumber(source) or source,
			authorSource = tonumber(source) or source,
			authorName = name,
			license = license,
			type = 'action'
		}
	})
	emitBubble(source, ('* %s %s'):format(name, text))

	if constants.PrintToConsole then
		print(('^6%s %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('action', source, name, Server.sanitizeDiscordText(text), nil)
end

local function sceneMessage(source, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name = Server.getName(source)
	local license = Server.getMessageLicense(source)
	local sceneConfig = type(Server.config.messages) == 'table' and type(Server.config.messages.scene) == 'table' and Server.config.messages.scene or {}
	local label = tostring(sceneConfig.label or (Server.config.chat and Server.config.chat.sceneLabel) or 'DO')
	local color = Server.config.chat and Server.config.chat.sceneColor or constants.SceneMessageColor or {143, 199, 255}
	local distance = tonumber(Server.config.chat and Server.config.chat.sceneDistance) or tonumber(constants.SceneMessageDistance) or constants.ActionMessageDistance
	local recipients = Server.getNearbyPlayers(source, distance)

	sendRawChannelMessage(recipients, 'local', {
		label = label,
		color = color,
		args = {label, text},
		authorSource = source,
		authorName = name,
		metadata = {
			source = tonumber(source) or source,
			authorSource = tonumber(source) or source,
			authorName = name,
			license = license,
			type = 'scene'
		}
	})
	emitBubble(source, ('Scene: %s'):format(text))

	if constants.PrintToConsole then
		print(('^5[DO] %s: %s^7'):format(name, text))
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

local function getWhisperDisplayName(playerId)
	local id = tonumber(playerId) or playerId
	local displayName = Server.getName(playerId)

	if not displayName or displayName == '' then
		displayName = Server.getRealName(playerId)
	end

	if not displayName or displayName == '' then
		displayName = tostring(playerId)
	end

	return string.format('[%s] %s', tostring(id), tostring(displayName))
end

local function whisperMessage(source, id, message, options)
	local opts = type(options) == 'table' and options or {}
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local target = getPlayerId(id)
	local storedTarget = nil
	if not target and type(Server.resolveStoredCharacterTarget) == 'function' then
		storedTarget = Server.resolveStoredCharacterTarget(id)
		if storedTarget and storedTarget.onlineSource then
			target = storedTarget.onlineSource
		end
	end

	if not target and not storedTarget then
		sendSystemMessage(source, 'No user with ID or name ' .. tostring(id), {255, 0, 0}, constants.DefaultChannelId)
		TriggerClientEvent('poodlechat:whisperError', source, id)
		return
	end

	local name = getWhisperDisplayName(source)
	local targetCitizenId = nil
	local targetConversationId = nil
	local targetConversationScope = nil
	local targetName = nil
	if target then
		targetCitizenId = type(Server.getCurrentCitizenId) == 'function' and Server.getCurrentCitizenId(target) or nil
		targetConversationId, targetConversationScope = Server.getConversationIdentity(target)
		targetName = getWhisperDisplayName(target)
	else
		targetCitizenId = storedTarget and storedTarget.citizenid or nil
		targetConversationId = storedTarget and storedTarget.conversationId or nil
		targetConversationScope = 'character'
		targetName = tostring(storedTarget and storedTarget.displayName or id)
	end

	local sendLicense = Server.getMessageLicense(source)
	local sourceCitizenId = type(Server.getCurrentCitizenId) == 'function' and Server.getCurrentCitizenId(source) or nil
	local sourceConversationId, sourceConversationScope = Server.getConversationIdentity(source)
	local whisperChannel = getWhisperDeliveryChannel()
	sendRawChannelMessage({source}, whisperChannel.id, {
		label = whisperChannel.label,
		color = Server.config.chat.whisperEchoColor,
		args = {'[DM -> ' .. targetName .. ']', text},
		authorSource = source,
		authorName = name,
		metadata = {
			type = 'whisper',
			direction = 'out',
			conversationId = tostring(targetConversationId or ('id:' .. tostring(target))),
			conversationScope = tostring(targetConversationScope or 'account'),
			peerId = tonumber(target) or nil,
			peerName = targetName,
			peerCharacterId = targetCitizenId,
			source = tonumber(source) or source,
			authorSource = tonumber(source) or source,
			authorName = name,
			license = sendLicense,
			replyTo = type(opts.replyTo) == 'table' and cloneMetadata(opts.replyTo) or nil
		}
	})

	if target then
		sendRawChannelMessage({target}, whisperChannel.id, {
			label = whisperChannel.label,
			color = Server.config.chat.whisperColor,
			args = {'[DM] ' .. name, text},
			authorSource = source,
			authorName = name,
			metadata = {
				type = 'whisper',
				direction = 'in',
				conversationId = tostring(sourceConversationId or ('id:' .. tostring(source))),
				conversationScope = tostring(sourceConversationScope or 'account'),
				peerId = tonumber(source) or source,
				peerName = name,
				peerCharacterId = sourceCitizenId,
				source = tonumber(source) or source,
				authorSource = tonumber(source) or source,
				authorName = name,
				license = sendLicense,
				replyTo = type(opts.replyTo) == 'table' and cloneMetadata(opts.replyTo) or nil
			}
		})

		TriggerClientEvent('poodlechat:setReplyTo', target, source)
		TriggerClientEvent('poodlechat:setReplyTo', source, target)
	else
		Server.storeOfflineWhisper(targetCitizenId, {
			senderSource = source,
			senderCitizenId = sourceCitizenId,
			senderConversationId = sourceConversationId,
			senderConversationScope = sourceConversationScope,
			senderName = name,
			senderLicense = sendLicense,
			replyTo = type(opts.replyTo) == 'table' and cloneMetadata(opts.replyTo) or nil,
			text = text,
			timestamp = os.time()
		})
		sendSystemMessage(
			source,
			('Message will be delivered when %s comes online.'):format(tostring(targetName)),
			{255, 214, 102},
			whisperChannel.id
		)
	end

	if constants.PrintToConsole then
		print(('^9[Whisper] %s -> %s^7: %s^7'):format(name, targetName, text))
	end
end

local function sendWhisperTargets(source)
	local targets = {}
	for _, playerId in ipairs(GetPlayers()) do
		if tonumber(playerId) ~= tonumber(source) then
			targets[#targets + 1] = {
				id = tonumber(playerId) or playerId,
				name = Server.getName(playerId),
				label = getWhisperDisplayName(playerId),
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

local function resolveExportChannelFromCommand(source, commandName)
	local normalizedCommand = Server.normalizeKey(commandName)
	if not normalizedCommand then
		return nil
	end

	local runtimeMapped = type(Server.resolveRuntimeCommandRoute) == 'function'
		and Server.resolveRuntimeCommandRoute(normalizedCommand)
		or nil
	if runtimeMapped and constants.ChannelById[runtimeMapped] then
		return resolveExportChannelForSource(source, runtimeMapped)
	end

	local commandKey = constants.CommandNameToKey and constants.CommandNameToKey[normalizedCommand] or nil
	if commandKey then
		local mapped = constants.CommandRoutingOverrides and constants.CommandRoutingOverrides[commandKey] or nil
		if mapped and constants.ChannelById[mapped] then
			return resolveExportChannelForSource(source, mapped)
		end

		local command = constants.CommandByKey and constants.CommandByKey[commandKey] or nil
		if type(command) == 'table' and constants.ChannelById[command.channel] then
			return resolveExportChannelForSource(source, command.channel)
		end
	end

	local explicit = constants.CommandRoutingOverrides and constants.CommandRoutingOverrides[normalizedCommand] or nil
	if explicit and constants.ChannelById[explicit] then
		return resolveExportChannelForSource(source, explicit)
	end

	return nil
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

	local requestedChannelId = Server.normalizeKey(payload.channel)
	local requestedCommand = payload.routeCommand or payload.command

	for i = 1, #targets do
		local targetSource = targets[i]
		local resolvedChannelId = nil
		if requestedChannelId then
			resolvedChannelId = resolveExportChannelForSource(targetSource, requestedChannelId)
		end
		if not resolvedChannelId and requestedCommand ~= nil then
			resolvedChannelId = resolveExportChannelFromCommand(targetSource, requestedCommand)
		end
		if not resolvedChannelId then
			resolvedChannelId = resolveExportChannelForSource(targetSource, constants.DefaultChannelId)
		end
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

local function addMessageExport(target, message)
	local resolvedTarget = tonumber(target)
	local resolvedMessage = message
	if resolvedMessage == nil then
		resolvedTarget = -1
		resolvedMessage = target
	end
	if not resolvedTarget then
		resolvedTarget = -1
	end
	TriggerClientEvent('chat:addMessage', resolvedTarget, resolvedMessage)
	return true
end

local function registerMessageHookExport(hook)
	if type(hook) ~= 'function' then
		return false
	end
	messageHooks[#messageHooks + 1] = hook
	return true
end

local function registerModeExport(modeData)
	if type(modeData) ~= 'table' then
		return false
	end
	local name = tostring(modeData.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if name == '' then
		return false
	end
	registeredModes[name] = modeData
	return true
end

local function getEnvelopeBodyText(envelope)
	if type(envelope) ~= 'table' then
		return ''
	end

	local args = type(envelope.args) == 'table' and envelope.args or {}
	if args[2] ~= nil then
		return tostring(args[2])
	end

	return tostring(args[1] or envelope.text or '')
end

local function getEnvelopeAuthorName(envelope)
	local metadata = type(envelope) == 'table' and type(envelope.metadata) == 'table' and envelope.metadata or {}
	if Server.isSet and Server.isSet(metadata.authorName) then
		return tostring(metadata.authorName)
	end

	local args = type(envelope) == 'table' and type(envelope.args) == 'table' and envelope.args or {}
	return tostring(args[1] or envelope.label or 'Unknown')
end

local function deleteMessageById(source, messageId)
	if type(Server.hasModerationPermission) == 'function' and not Server.hasModerationPermission(source, 'delete') then
		sendSystemMessage(source, 'You do not have permission to delete messages.', {255, 96, 96}, constants.DefaultChannelId)
		return false
	end

	local originalEnvelope = nil
	local channelId = nil
	if type(Server.findLoadedMessageById) == 'function' then
		local resolvedEnvelope, _, resolvedChannelId = Server.findLoadedMessageById(messageId)
		originalEnvelope = resolvedEnvelope
		channelId = resolvedChannelId
	end
	if type(originalEnvelope) ~= 'table' then
		sendSystemMessage(source, 'That message could not be found.', {255, 96, 96}, constants.DefaultChannelId)
		return false
	end

	if type(Server.registerDeletedMessage) == 'function' then
		Server.registerDeletedMessage(messageId, source, originalEnvelope)
	end

	if type(Server.appendAuditLog) == 'function' then
		Server.appendAuditLog(source, 'message.delete', {
			messageId = tostring(messageId),
			channel = channelId or originalEnvelope.channel,
			author = getEnvelopeAuthorName(originalEnvelope)
		})
	end

	local recipients = type(Server.collectLoadedRecipientsForMessage) == 'function'
		and Server.collectLoadedRecipientsForMessage(messageId)
		or {}
	for i = 1, #recipients do
		local recipient = tonumber(recipients[i]) or recipients[i]
		local outbound = type(Server.buildDeletedEnvelopeForSource) == 'function'
			and Server.buildDeletedEnvelopeForSource(recipient, originalEnvelope)
			or originalEnvelope
		TriggerClientEvent('poodlechat:channelMessage', recipient, outbound)
	end

	local moderationConfig = type(Server.config.moderation) == 'table' and Server.config.moderation or {}
	local staffChannelConfig = type(moderationConfig.staffChannel) == 'table' and moderationConfig.staffChannel or {}
	local deletedByName = Server.getName(source)
	local authorName = getEnvelopeAuthorName(originalEnvelope)
	local bodyText = getEnvelopeBodyText(originalEnvelope)
	local resolvedChannelId = Server.normalizeKey(channelId or originalEnvelope.channel) or constants.DefaultChannelId

	if staffChannelConfig.echoDeletes ~= false then
		sendRawChannelMessage(getChannelRecipients(source, 'staff'), 'staff', {
			label = getChannel('staff').label,
			color = {245, 158, 11},
			args = {'STAFF DELETE', string.format('%s removed %s in %s: %s', deletedByName, authorName, resolvedChannelId, bodyText)},
			authorSource = source,
			authorName = deletedByName,
			metadata = {
				type = 'system',
				subtype = 'delete',
				authorSource = tonumber(source) or source,
				authorName = deletedByName
			}
		})
	end

	local deleteWebhookBody = table.concat({
		'Deleted by: ' .. tostring(deletedByName),
		'Author: ' .. tostring(authorName),
		'Channel: ' .. tostring(resolvedChannelId),
		'Message ID: ' .. tostring(messageId),
		'',
		tostring(bodyText)
	}, '\n')
	Server.sendDiscordWebhook('delete', source, deletedByName, deleteWebhookBody, Server.getDiscordColor('delete', 15105570))

	-- No per-player system message; staff channel echo (above) is the sole confirmation.
	return true
end

local function setPermissions(source)
	local resolved = type(Server.getResolvedPlayerPermissions) == 'function'
		and Server.getResolvedPlayerPermissions(source)
		or {channels = Server.getPlayerChannelPermissions(source), moderation = {}}
	local channelPermissions = type(resolved.channels) == 'table' and resolved.channels or {}
	local moderationPermissions = type(resolved.moderation) == 'table' and resolved.moderation or {}
	local canAccessStaff = channelPermissions.staff == true
	local channelDefinitions = {}
	local channelList = type(constants.ChannelList) == 'table' and constants.ChannelList or {}
	for i = 1, #channelList do
		local channel = channelList[i]
		if channel and channel.id and Server.canAccessChannel(source, channel.id) then
			channelDefinitions[#channelDefinitions + 1] = {
				id = channel.id,
				label = channel.label,
				color = channel.color,
				order = channel.order,
				visible = channel.visible ~= false,
				cycle = channel.cycle ~= false,
				canSend = channel.canSend ~= false,
				allowed = true,
				maxHistory = channel.maxHistory
			}
		end
	end

	TriggerClientEvent('poodlechat:setPermissions', source, {
		canAccessStaffChannel = canAccessStaff,
		channels = channelPermissions,
		channelDefinitions = channelDefinitions,
		moderation = moderationPermissions,
		defaultChannel = constants.DefaultChannelId
	})
end

local function syncAllPermissions()
	for _, playerId in ipairs(GetPlayers()) do
		setPermissions(playerId)
	end
end

local function localCommand(source, args)
	localMessage(source, table.concat(args, ' '))
end

local function getMessageChannelForInput(source, requested)
	local channelId = nil
	
	-- First, normalize and validate the requested channel
	if requested and type(requested) == 'string' then
		channelId = Server.normalizeKey(requested)
	end
	
	-- If no valid channel was requested, use default
	if not channelId then
		channelId = constants.DefaultChannelId
	end
	
	-- Handle whisper fallback
	if channelId == 'whispers' and constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	-- Validate channel exists
	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	-- Check player permissions
	if not Server.canAccessChannel(source, channelId) then
		channelId = getFirstAccessibleChannelIdForSource(source)
	end

	-- Final validation
	if not constants.ChannelById[channelId] then
		channelId = constants.DefaultChannelId
	end

	return channelId
end

local function routeInputMessage(source, channelId, message, options)
	if channelId == 'whispers' and constants.WhisperTabEnabled ~= true then
		channelId = Server.normalizeKey(constants.WhisperFallbackChannelId) or constants.DefaultChannelId
	end

	if channelId == 'whispers' then
		sendSystemMessage(source, 'Select a whisper conversation or use /w [id] [message].', {255, 128, 128}, constants.DefaultChannelId)
		return
	end

	if channelId == 'local' then
		localMessage(source, message, options)
		return
	end

	if channelId == 'staff' then
		staffMessage(source, message, options)
		return
	end

	if channelId == 'global' then
		globalMessage(source, message, options)
		return
	end

	routePlayerMessageToChannel(source, channelId, message, options)
end

local function registerChatHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	AddEventHandler('_chat:messageEntered', function(author, color, message, channel, options)
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

		routeInputMessage(source, channelId, message, type(options) == 'table' and options or nil)
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
				authorSource = source,
				authorName = name,
				metadata = {
					type = 'commandFallback',
					source = tonumber(source) or source,
					authorSource = tonumber(source) or source,
					authorName = name
				}
			})
		end

		CancelEvent()
	end)

	AddEventHandler('chat:init', function()
		Server.refreshCommands(source)
		setPermissions(source)
	end)

	AddEventHandler('onServerResourceStart', function(resName)
		if resName ~= GetCurrentResourceName() then
			return
		end

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

	AddEventHandler('poodlechat:sceneMessage', function(message)
		sceneMessage(source, message)
	end)

	AddEventHandler('poodlechat:clearHistory', function()
		local ok = type(Server.clearPlayerChatHistory) == 'function' and Server.clearPlayerChatHistory(source)
		if ok then
			TriggerClientEvent('chat:clear', source)
			sendSystemMessage(source, 'Your saved chat history has been cleared.', {104, 216, 167}, constants.DefaultChannelId)
		else
			sendSystemMessage(source, 'Your chat history could not be cleared yet.', {255, 128, 128}, constants.DefaultChannelId)
		end
	end)

	AddEventHandler('poodlechat:whisperMessage', function(id, message, options)
		whisperMessage(source, id, message, options)
	end)

	AddEventHandler('poodlechat:getWhisperTargets', function()
		sendWhisperTargets(source)
	end)

	AddEventHandler('poodlechat:deleteConversation', function(channelId, conversationId)
		Server.deleteConversationHistory(source, channelId, conversationId)
	end)

	AddEventHandler('poodlechat:deleteMessage', function(messageId)
		deleteMessageById(source, messageId)
	end)

	AddEventHandler('poodlechat:staffMessage', function(message)
		staffMessage(source, message)
	end)

	AddEventHandler('poodlechat:getPermissions', function()
		setPermissions(source)
	end)

	RegisterNetEvent('poodlechat:voiceDistanceState')
	AddEventHandler('poodlechat:voiceDistanceState', function(payload)
		local rawPayload = type(payload) == 'table' and payload or {}
		local distance = tonumber(rawPayload.distance or payload)
		if distance and distance > 0 then
			Server.setSyncedVoiceDistance(source, distance)
			return
		end

		Server.clearSyncedVoiceDistance(source)
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

	RegisterCommand('poodlechat_refresh_perms', syncAllPermissions, true)

	exports('SendChannelMessage', sendChannelMessageExport)
	exports('SendBubbleMessage', sendBubbleMessageExport)
	exports('addMessage', addMessageExport)
	exports('registerMessageHook', registerMessageHookExport)
	exports('registerMode', registerModeExport)

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
Server.sceneMessage = sceneMessage
Server.whisperMessage = whisperMessage
Server.getPlayerId = getPlayerId
Server.deleteMessageById = deleteMessageById
Server.setPermissions = setPermissions
Server.syncAllPermissions = syncAllPermissions
Server.registerChatHandlers = registerChatHandlers
