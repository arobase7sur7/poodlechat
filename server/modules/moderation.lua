local Server = PoodleChatServer
local constants = nil
local handlersRegistered = false
local playerSnapshotRegistry = {}

local function ensureContext()
	if constants then
		return true
	end

	constants = Server.constants
	return constants ~= nil
end

local function getModerationConfig()
	return type((Server.config or {}).moderation) == 'table' and (Server.config or {}).moderation or {}
end

local function getBuiltInReportConfig()
	local moderationConfig = getModerationConfig()
	local builtInReports = type(moderationConfig.builtInReports) == 'table' and moderationConfig.builtInReports or {}
	local discordConfig = type((Server.config or {}).discord) == 'table' and (Server.config or {}).discord or {}
	return {
		enabled = constants.BuiltInReportsEnabled == true,
		successMessage = tostring(builtInReports.successMessage or discordConfig.reportSuccessMessage or 'Your report has been submitted.'),
		failureMessage = tostring(builtInReports.failureMessage or discordConfig.reportFailureMessage or 'Sorry, something went wrong with your report.'),
		feedbackColor = builtInReports.feedbackColor or discordConfig.reportFeedbackColor or {76, 130, 255}
	}
end

local function collectStaffRecipients()
	local recipients = {}
	for _, playerId in ipairs(GetPlayers()) do
		if Server.canAccessChannel(playerId, 'staff') then
			recipients[#recipients + 1] = playerId
		end
	end
	return recipients
end

local function cloneTableShallow(value)
	if type(value) ~= 'table' then
		return nil
	end

	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = entry
	end
	return copy
end

local function sanitizeReportContext(raw)
	if type(raw) ~= 'table' then
		return nil
	end

	local function clean(value, maxLength)
		local text = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
		maxLength = tonumber(maxLength) or 300
		if #text > maxLength then
			return text:sub(1, maxLength)
		end
		return text
	end

	return {
		messageId = clean(raw.messageId, 120),
		channel = clean(raw.channel, 80),
		label = clean(raw.label, 80),
		type = clean(raw.type, 80),
		authorSource = raw.authorSource and tostring(raw.authorSource) or '',
		authorName = clean(raw.authorName, 120),
		peerId = raw.peerId and tostring(raw.peerId) or '',
		peerCharacterId = clean(raw.peerCharacterId, 120),
		conversationId = clean(raw.conversationId, 160),
		timestamp = tonumber(raw.timestamp) or os.time(),
		rawMessage = clean(raw.rawMessage or raw.raw, 1000),
		renderedMessage = clean(raw.renderedMessage or raw.rendered or raw.excerpt, 1000),
		excerpt = clean(raw.excerpt or raw.renderedMessage or raw.rawMessage, 300)
	}
end

local function buildPlayerSnapshot(source)
	local src = tonumber(source)
	if not src then
		return nil
	end

	local snapshot = {
		source = src,
		name = tostring(Server.getName(src) or GetPlayerName(src) or src),
		realName = tostring((type(Server.getRealName) == 'function' and Server.getRealName(src)) or GetPlayerName(src) or src),
		citizenid = tostring((type(Server.getCurrentCitizenId) == 'function' and Server.getCurrentCitizenId(src)) or ''),
		discord = tostring((type(Server.getIdFromSource) == 'function' and Server.getIdFromSource('discord', src)) or ''),
		license = tostring(Server.getIdFromSource(constants.IdentifierType, src) or 'unknown'),
		endpoint = tostring(GetPlayerEndpoint(src) or 'unknown'),
		lastSeenAt = os.time()
	}
	playerSnapshotRegistry[tostring(src)] = snapshot
	return snapshot
end

local function getPlayerSnapshot(source)
	local src = tonumber(source)
	if not src then
		return nil
	end

	if GetPlayerName(src) then
		return buildPlayerSnapshot(src)
	end

	return cloneTableShallow(playerSnapshotRegistry[tostring(src)])
end

local function resolveReportTarget(rawTarget)
	if rawTarget == nil or rawTarget == false then
		return nil, nil
	end

	local normalized = tostring(rawTarget):gsub('^%s+', ''):gsub('%s+$', '')
	if normalized == '' then
		return nil, nil
	end

	local liveId = Server.getPlayerId(normalized)
	if liveId then
		return tonumber(liveId) or liveId, buildPlayerSnapshot(liveId)
	end

	if normalized:match('^%d+$') then
		return nil, cloneTableShallow(playerSnapshotRegistry[normalized])
	end

	return nil, nil
end

local function buildReportDiscordBody(source, targetSnapshot, reason, reportContext, attemptedTarget)
	local reporterSnapshot = getPlayerSnapshot(source) or {
		source = tonumber(source) or source,
		name = tostring(Server.getName(source) or source),
		realName = tostring((type(Server.getRealName) == 'function' and Server.getRealName(source)) or GetPlayerName(source) or source),
		citizenid = tostring((type(Server.getCurrentCitizenId) == 'function' and Server.getCurrentCitizenId(source)) or ''),
		discord = tostring((type(Server.getIdFromSource) == 'function' and Server.getIdFromSource('discord', source)) or ''),
		license = tostring(Server.getIdFromSource(constants.IdentifierType, source) or 'unknown'),
		endpoint = tostring(GetPlayerEndpoint(source) or 'unknown')
	}
	local targetName = targetSnapshot and targetSnapshot.name
		or ((attemptedTarget and tostring(attemptedTarget) ~= '') and ('Unavailable [' .. tostring(attemptedTarget) .. ']') or 'No target provided')
	local targetLicense = targetSnapshot and targetSnapshot.license or 'n/a'
	local targetCitizenId = targetSnapshot and targetSnapshot.citizenid or 'n/a'
	local targetEndpoint = targetSnapshot and targetSnapshot.endpoint or 'n/a'
	local targetSource = targetSnapshot and tostring(targetSnapshot.source or attemptedTarget or 'n/a') or tostring(attemptedTarget or 'n/a')
	local contextLines = {}
	if reportContext then
		contextLines = {
			'',
			'Attached Message:',
			('ID: %s'):format(tostring(reportContext.messageId)),
			('Channel: %s'):format(tostring(reportContext.channel or 'unknown')),
			('Type: %s'):format(tostring(reportContext.type or 'unknown')),
			('Author: %s'):format(tostring(reportContext.authorName or 'unknown')),
			('Rendered: %s'):format(tostring(reportContext.renderedMessage or reportContext.excerpt or '')),
			('Raw: %s'):format(tostring(reportContext.rawMessage or ''))
		}
	end
	return table.concat({
		'Reporter: ' .. tostring(reporterSnapshot.name),
		'Reporter Source: ' .. tostring(reporterSnapshot.source or source),
		'Reporter Discord: ' .. tostring(reporterSnapshot.discord or 'n/a'),
		'Reporter CitizenID: ' .. tostring(reporterSnapshot.citizenid or 'n/a'),
		'Reporter License: ' .. tostring(reporterSnapshot.license),
		'Reporter IP: ' .. tostring(reporterSnapshot.endpoint),
		'',
		'Reported Player: ' .. tostring(targetName),
		'Reported Source: ' .. tostring(targetSource),
		'Reported Discord: ' .. tostring(targetSnapshot and targetSnapshot.discord or 'n/a'),
		'Reported CitizenID: ' .. tostring(targetCitizenId),
		'Reported License: ' .. tostring(targetLicense),
		'Reported IP: ' .. tostring(targetEndpoint),
		'',
		'Reason:',
		tostring(reason or '')
	}, '\n') .. (#contextLines > 0 and ('\n' .. table.concat(contextLines, '\n')) or '')
end

local function sendStaffReport(source, targetSnapshot, reason, reportContext, attemptedTarget)
	local recipients = collectStaffRecipients()
	if #recipients == 0 then
		return false
	end

	local reporterSnapshot = getPlayerSnapshot(source) or {name = tostring(Server.getName(source) or source)}
	local reporterName = reporterSnapshot.name
	local targetName = 'No target'
	local targetSource = targetSnapshot and tostring(targetSnapshot.source or attemptedTarget or '') or tostring(attemptedTarget or '')
	if targetSnapshot then
		local offlineSuffix = GetPlayerName(tonumber(targetSnapshot.source or -1)) == nil and ' (offline)' or ''
		targetName = ('[%s] %s%s'):format(tostring(targetSnapshot.source or attemptedTarget or '?'), tostring(targetSnapshot.name or 'Unknown'), offlineSuffix)
	elseif attemptedTarget and tostring(attemptedTarget) ~= '' then
		targetName = 'Unavailable [' .. tostring(attemptedTarget) .. ']'
	end
	Server.sendRawChannelMessage(recipients, 'staff', {
		label = (Server.getChannelById('staff') or {label = 'Staff'}).label,
		color = {76, 130, 255},
		args = {'REPORT', tostring(reason or '')},
		authorSource = source,
		authorName = reporterName,
		metadata = {
			type = 'report',
			reporterSource = tonumber(source) or source,
			reporterName = reporterName,
			reporter = reporterSnapshot,
			targetSource = targetSource ~= '' and tonumber(targetSource) or targetSource,
			targetName = targetName,
			target = targetSnapshot,
			reason = tostring(reason or ''),
			reportContext = sanitizeReportContext(reportContext),
			targetOffline = targetSnapshot ~= nil and GetPlayerName(tonumber(targetSnapshot.source or -1)) == nil,
			targetInput = tostring(attemptedTarget or '')
		}
	})

	return true
end

local function submitReport(source, targetInput, reason, reportContext)
	local reportConfig = getBuiltInReportConfig()
	local feedbackColor = reportConfig.feedbackColor
	local sanitizedReason = tostring(reason or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if sanitizedReason == '' then
		Server.sendSystemMessage(source, 'You must enter a reason for the report.', {255, 96, 96}, constants.DefaultChannelId)
		return false
	end

	local attemptedTarget = tostring(targetInput or ''):gsub('^%s+', ''):gsub('%s+$', '')
	local targetSource, targetSnapshot = resolveReportTarget(attemptedTarget)
	if targetSource and not targetSnapshot then
		targetSnapshot = getPlayerSnapshot(targetSource)
	end
	if attemptedTarget:match('^%d+$') and not targetSource and not targetSnapshot then
		sanitizedReason = (attemptedTarget .. ' ' .. sanitizedReason):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
		attemptedTarget = ''
	end
	local sanitizedContext = sanitizeReportContext(reportContext)

	if type(Server.recordReport) == 'function' then
		Server.recordReport(source, targetSnapshot, sanitizedReason, sanitizedContext, attemptedTarget)
	end

	sendStaffReport(source, targetSnapshot, sanitizedReason, sanitizedContext, attemptedTarget)

	if not Server.isDiscordKindEnabled('report') then
		Server.sendSystemMessage(source, reportConfig.successMessage, feedbackColor, constants.DefaultChannelId)
		return true
	end

	local reporterSnapshot = getPlayerSnapshot(source) or {name = tostring(Server.getName(source) or source)}
	local reporterName = reporterSnapshot.name
	local reportColor = Server.getDiscordColor('report', 0xfe7f9c)
	local discordBody = buildReportDiscordBody(source, targetSnapshot, sanitizedReason, sanitizedContext, attemptedTarget)
	Server.sendDiscordWebhook('report', source, reporterName, discordBody, reportColor, function(ok, statusCode, body)
		if ok then
			Server.sendSystemMessage(source, reportConfig.successMessage, feedbackColor, constants.DefaultChannelId)
			return
		end

		Server.log('error', ('Failed to send report (%s): %s'):format(tostring(statusCode), tostring(body)))
		Server.sendSystemMessage(source, reportConfig.failureMessage, feedbackColor, constants.DefaultChannelId)
	end)

	return true
end

local function sendPresenceMessage(kind, playerSource, playerName, reason)
	local args = {playerName}
	local metadata = {
		type = kind,
		playerSource = tonumber(playerSource) or playerSource,
		playerName = tostring(playerName or '')
	}

	if kind == 'join' then
		args[2] = 'joined the server'
	else
		args[2] = 'left the server'
		args[3] = tostring(reason or 'Unknown')
		metadata.reason = tostring(reason or 'Unknown')
	end

	Server.sendRawChannelMessage(nil, constants.DefaultChannelId, {
		label = 'System',
		color = {255, 255, 255},
		args = args,
		authorName = 'System',
		metadata = metadata
	})
end

local function registerModerationHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	AddEventHandler('poodlechat:report', function(player, reason, reportContext, sourceMessageId)
		local reportConfig = getBuiltInReportConfig()
		if reportConfig.enabled ~= true then
			Server.sendSystemMessage(source, 'The built-in report flow is disabled.', {255, 0, 0}, constants.DefaultChannelId)
			return
		end

		local contextPayload = sanitizeReportContext(reportContext)
		local sourceMessage = tostring(sourceMessageId or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if not contextPayload and sourceMessage ~= '' then
			contextPayload = {
				messageId = sourceMessage,
				channel = '',
				authorSource = '',
				authorName = '',
				timestamp = os.time(),
				excerpt = ''
			}
		end

		submitReport(source, player, reason, contextPayload)
	end)

	AddEventHandler('poodlechat:mute', function(player)
		local id = tonumber(Server.getPlayerId(player))

		if id then
			local license = Server.getIdFromSource(constants.IdentifierType, id)
			if license then
				TriggerClientEvent('poodlechat:mute', source, id, license)
			else
				Server.sendSystemMessage(source, 'Failed to mute player', {255, 0, 0}, constants.DefaultChannelId)
			end
		else
			Server.sendSystemMessage(source, 'No player with ID or name ' .. tostring(player) .. ' exists', {255, 0, 0}, constants.DefaultChannelId)
		end
	end)

	AddEventHandler('poodlechat:unmute', function(player)
		local id = tonumber(Server.getPlayerId(player))

		if id then
			local license = Server.getIdFromSource(constants.IdentifierType, id)
			TriggerClientEvent('poodlechat:unmute', source, id, license)
		else
			Server.sendSystemMessage(source, 'No player with ID or name ' .. tostring(player) .. ' exists', {255, 0, 0}, constants.DefaultChannelId)
		end
	end)

	AddEventHandler('poodlechat:showMuted', function(mutedPlayers)
		if type(mutedPlayers) ~= 'table' then
			mutedPlayers = {}
		end

		local mutedPlayerIds = {}
		local playersByLicense = {}

		for _, id in ipairs(GetPlayers()) do
			local license = Server.getIdFromSource(constants.IdentifierType, id)
			if license then
				playersByLicense[license] = tonumber(id)
			end
		end

		for license in pairs(mutedPlayers) do
			local id = playersByLicense[license]
			if id then
				mutedPlayerIds[#mutedPlayerIds + 1] = id
			end
		end

		TriggerClientEvent('poodlechat:showMuted', source, mutedPlayerIds)
	end)

	AddEventHandler('poodlechat:typingState', function(active)
		if Server.config.typing.enabled ~= true then
			return
		end

		local state = active and true or false
		local now = GetGameTimer()
		local updateRate = math.max(50, tonumber(Server.config.typing.updateRate) or 200)
		local current = Server.state.typingStateBySource[source]

		if current and current.state == state and (now - current.time) < updateRate then
			return
		end

		Server.state.typingStateBySource[source] = {
			state = state,
			time = now
		}

		local distance = tonumber(Server.config.typing.maxDistance) or constants.LocalMessageDistance
		local recipients = Server.getNearbyPlayers(source, distance)
		Server.triggerClientEventForTargetsNoFallback('poodlechat:typingState', recipients, source, state)
	end)

	AddEventHandler('poodlechat:bubbleMessage', function(message)
		Server.emitBubble(source, Server.Emojit(Server.normalizeMessage(message)))
	end)

	AddEventHandler('playerJoining', function()
		Server.clearIdentifierCache(source)
		Server.clearIdentityState(source)
		Server.clearSyncedVoiceDistance(source)
		buildPlayerSnapshot(source)
		local playerName = Server.getJoinName(source)
		sendPresenceMessage('join', source, playerName)

		if Server.isDiscordKindEnabled('join') then
			Server.sendDiscordWebhook('join', source, playerName, 'connected to the server.', nil)
		end
	end)

	AddEventHandler('playerDropped', function(reason)
		buildPlayerSnapshot(source)
		local leaveReason = tostring(reason or 'Unknown')
		local playerName = Server.getLeaveName(source)
		local leaveColor = Server.getDiscordColor('leave', 16711680)

		if string.find(leaveReason, 'Kicked', 1, true) or string.find(leaveReason, 'Banned', 1, true) then
			leaveColor = Server.getDiscordColor('leaveKicked', 16007897)
		end

		sendPresenceMessage('leave', source, playerName, leaveReason)
		TriggerClientEvent('poodlechat:typingState', -1, source, false)
		Server.state.typingStateBySource[source] = nil

		if Server.isDiscordKindEnabled('leave') then
			Server.sendDiscordWebhook('leave', source, playerName, 'left the server. Reason: ' .. leaveReason, leaveColor)
		end

		Server.clearIdentifierCache(source)
	end)

	handlersRegistered = true
end

Server.registerModerationHandlers = registerModerationHandlers
