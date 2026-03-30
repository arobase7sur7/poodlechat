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

local function sendReportToDiscord(source, target, reason)
	local message = table.concat({
		'**Reporter:** ' .. Server.getName(source),
		'**License:** ' .. tostring(Server.getIdFromSource(constants.IdentifierType, source) or 'unknown'),
		'**IP:** ' .. tostring(GetPlayerEndpoint(source) or 'unknown'),
		'',
		'**Player Reported:** ' .. Server.getName(target),
		'**License:** ' .. tostring(Server.getIdFromSource(constants.IdentifierType, target) or 'unknown'),
		'**IP:** ' .. tostring(GetPlayerEndpoint(target) or 'unknown'),
		'',
		'**Reason:** ' .. tostring(reason)
	}, '\n')

	local feedbackColor = Server.config.discord.reportFeedbackColor or {255, 165, 0}
	local successMessage = tostring(Server.config.discord.reportSuccessMessage or 'Your report has been submitted.')
	local failureMessage = tostring(Server.config.discord.reportFailureMessage or 'Sorry, something went wrong with your report.')
	local reportColor = Server.getDiscordColor('report', 0xfe7f9c)

	Server.sendDiscordWebhook('report', source, Server.getName(source), message, reportColor, function(ok, statusCode, body)
		if ok then
			TriggerClientEvent('chat:addMessage', source, {
				color = feedbackColor,
				args = {successMessage}
			})
			return
		end

		Server.log('error', ('Failed to send report (%s): %s'):format(tostring(statusCode), tostring(body)))
		TriggerClientEvent('chat:addMessage', source, {
			color = feedbackColor,
			args = {failureMessage}
		})
	end)
end

local function registerModerationHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	AddEventHandler('poodlechat:report', function(player, reason)
		if not Server.isDiscordKindEnabled('report') then
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 0, 0},
				args = {'Error', 'The report function is not enabled.'}
			})
			return
		end

		local id = Server.getPlayerId(player)
		if not id then
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 0, 0},
				args = {'Error', 'No player with ID or name ' .. tostring(player) .. ' exists'}
			})
			return
		end

		sendReportToDiscord(source, id, reason)
	end)

	AddEventHandler('poodlechat:mute', function(player)
		local id = tonumber(Server.getPlayerId(player))

		if id then
			local license = Server.getIdFromSource(constants.IdentifierType, id)
			if license then
				TriggerClientEvent('poodlechat:mute', source, id, license)
			else
				TriggerClientEvent('chat:addMessage', source, {
					color = {255, 0, 0},
					args = {'Error', 'Failed to mute player'}
				})
			end
		else
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 0, 0},
				args = {'Error', 'No player with ID or name ' .. tostring(player) .. ' exists'}
			})
		end
	end)

	AddEventHandler('poodlechat:unmute', function(player)
		local id = tonumber(Server.getPlayerId(player))

		if id then
			local license = Server.getIdFromSource(constants.IdentifierType, id)
			TriggerClientEvent('poodlechat:unmute', source, id, license)
		else
			TriggerClientEvent('chat:addMessage', source, {
				color = {255, 0, 0},
				args = {'Error', 'No player with ID or name ' .. tostring(player) .. ' exists'}
			})
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

		if Server.isDiscordKindEnabled('join') then
			Server.sendDiscordWebhook('join', source, Server.getName(source), 'connected to the server.', nil)
		end
	end)

	AddEventHandler('playerDropped', function(reason)
		local leaveReason = tostring(reason or 'Unknown')
		local playerName = Server.getName(source)
		local leaveColor = Server.getDiscordColor('leave', 16711680)

		if string.find(leaveReason, 'Kicked', 1, true) or string.find(leaveReason, 'Banned', 1, true) then
			leaveColor = Server.getDiscordColor('leaveKicked', 16007897)
		end

		TriggerClientEvent('chatMessage', -1, '', {255, 255, 255}, '^2* ' .. playerName .. '^r^2 left (' .. leaveReason .. ')')
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
