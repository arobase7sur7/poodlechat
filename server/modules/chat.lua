local Server = PoodleChatServer
local constants = Server.constants

AddEventHandler('_chat:messageEntered', function(author, color, message, channel)
	if not message or not author then
		return
	end

	TriggerEvent('chatMessage', source, author, message, channel)

	if not WasEventCanceled() then
		TriggerClientEvent('chatMessage', -1, author, {255, 255, 255}, message)
	end
end)

AddEventHandler('__cfx_internal:commandFallback', function(command)
	local name = GetNameWithId(source)

	TriggerEvent('chatMessage', source, name, '/' .. command)

	if not WasEventCanceled() then
		TriggerClientEvent('chatMessage', -1, name, {255, 255, 255}, '/' .. command)
	end

	CancelEvent()
end)

AddEventHandler('chat:init', function()
	TriggerClientEvent('chatMessage', -1, '', {255, 255, 255}, '^2* ' .. GetName(source) .. '^r^2 joined.')
	Server.refreshCommands(source)
end)

AddEventHandler('onServerResourceStart', function()
	Wait(constants.refreshCommandsDelayMs)

	for _, player in ipairs(GetPlayers()) do
		Server.refreshCommands(player)
	end
end)

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
	local license = Server.getMessageLicense(source)
	Server.triggerClientEventForTargetsNoFallback('poodlechat:bubbleMessage', recipients, source, message, license)
end

function LocalMessage(source, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name, color = Server.getNameWithRoleAndColor(source)
	if not color then
		color = constants.LocalMessageColor
	end

	local license = Server.getMessageLicense(source)
	local recipients = Server.getNearbyPlayers(source, constants.LocalMessageDistance)
	Server.triggerClientEventForTargets('poodlechat:localMessage', recipients, source, license, name, color, text)
	emitBubble(source, text)

	if constants.PrintToConsole then
		print(('^5[Local] %s^7: %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('local', source, name, Server.sanitizeDiscordText(text), nil)
end

function GlobalMessage(source, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name, color = Server.getNameWithRoleAndColor(source)
	if not color then
		color = constants.GlobalMessageColor
	end

	local license = Server.getMessageLicense(source)
	TriggerClientEvent('poodlechat:globalMessage', -1, source, license, name, color, text)
	emitBubble(source, text)

	if constants.PrintToConsole then
		print(('^3[Global] %s^7: %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('global', source, name, Server.sanitizeDiscordText(text), nil)
end

AddEventHandler('poodlechat:globalMessage', function(message)
	GlobalMessage(source, message)
end)

local function LocalCommand(source, args)
	LocalMessage(source, table.concat(args, ' '))
end

RegisterCommand('say', function(source, args)
	if source and source > 0 then
		LocalCommand(source, args)
	else
		TriggerClientEvent('chat:addMessage', -1, {color = {255, 255, 255}, args = {'console', table.concat(args, ' ')}})
	end
end, true)

AddEventHandler('chatMessage', function(source, name, message, channel)
	if string.sub(message, 1, 1) ~= '/' then
		if channel == 'Global' then
			GlobalMessage(source, message)
		elseif channel == 'Local' then
			LocalMessage(source, message)
		elseif channel == 'Staff' then
			StaffMessage(source, message)
		end
	end

	CancelEvent()
end)

AddEventHandler('poodlechat:actionMessage', function(message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name = GetName(source)
	local license = Server.getMessageLicense(source)
	local recipients = Server.getNearbyPlayers(source, constants.ActionMessageDistance)
	Server.triggerClientEventForTargets('poodlechat:action', recipients, source, license, name, text)
	emitBubble(source, text)

	if constants.PrintToConsole then
		print(('^6%s %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('action', source, name, Server.sanitizeDiscordText(text), nil)
end)

function GetPlayerId(id)
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
		if GetName(playerId):lower() == targetName then
			return playerId
		end
	end

	return nil
end

AddEventHandler('poodlechat:whisperMessage', function(id, message)
	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local target = GetPlayerId(id)
	if not target then
		TriggerClientEvent('poodlechat:whisperError', source, id)
		return
	end

	local name = Server.getNameWithRoleAndColor(source)
	local sendLicense = Server.getMessageLicense(source)
	local recvLicense = Server.getMessageLicense(target)

	TriggerClientEvent('poodlechat:whisperEcho', source, target, recvLicense, GetNameWithId(target), text)
	TriggerClientEvent('poodlechat:whisper', target, source, sendLicense, name, text)
	TriggerClientEvent('poodlechat:setReplyTo', target, source)
	TriggerClientEvent('poodlechat:setReplyTo', source, target)

	if constants.PrintToConsole then
		print(('^9[Whisper] %s -> %s^7: %s^7'):format(GetRealName(source), GetRealName(target), text))
	end
end)

function StaffMessage(source, message)
	if not IsPlayerAceAllowed(source, constants.StaffChannelAce) then
		TriggerClientEvent('chat:addMessage', source, {
			color = {255, 0, 0},
			args = {'Error', 'You do not have access to the Staff channel.'}
		})
		return
	end

	local text = Server.normalizeMessage(message)
	if text == '' then
		return
	end

	text = Server.Emojit(text)

	local name, color = Server.getNameWithRoleAndColor(source)
	if not color then
		color = constants.StaffMessageColor
	end

	for _, playerId in ipairs(GetPlayers()) do
		if IsPlayerAceAllowed(playerId, constants.StaffChannelAce) then
			TriggerClientEvent('poodlechat:staffMessage', playerId, source, name, color, text)
		end
	end

	emitBubble(source, text)

	if constants.PrintToConsole then
		print(('^1[Staff] %s^7: %s^7'):format(name, text))
	end

	Server.sendDiscordWebhook('staff', source, name, Server.sanitizeDiscordText(text), nil)
end

AddEventHandler('poodlechat:staffMessage', function(message)
	StaffMessage(source, message)
end)

local function SetPermissions(source)
	TriggerClientEvent('poodlechat:setPermissions', source, {
		canAccessStaffChannel = IsPlayerAceAllowed(source, constants.StaffChannelAce)
	})
end

AddEventHandler('poodlechat:getPermissions', function()
	SetPermissions(source)
end)

RegisterCommand('poodlechat_refresh_perms', function()
	for _, playerId in ipairs(GetPlayers()) do
		SetPermissions(playerId)
	end
end, true)

Server.emitBubble = emitBubble
Server.SetPermissions = SetPermissions

