local Client = PoodleChatClient
local State = nil
local config = nil
local constants = nil
local chatConfig = nil
local uiConfig = nil
local runtimeUiConfig = nil
local channelIdByName = nil
local channelNameById = nil
local handlersRegistered = false

local function ensureContext()
	if State and config and constants then
		return true
	end

	State = Client.state
	config = Client.config
	constants = Client.constants

	if not State or not config or not constants then
		return false
	end

	chatConfig = config.chat or {}
	uiConfig = config.ui or {}
	runtimeUiConfig = type((Config.Runtime or {}).ui) == 'table' and (Config.Runtime or {}).ui or {}
	channelIdByName = constants.channelIdByName or {}
	channelNameById = constants.channelNameById or {}

	return true
end

local function isMutedLicense(license)
	return license and State.MutedPlayers[license] ~= nil
end

local function addTaggedMessage(tag, name, color, message)
	Client.addChatMessage(color, tag .. name, message)
end

local function addGlobalMessage(name, color, message)
	addTaggedMessage('[Global] ', name, color, message)
end

local function addLocalMessage(name, color, message)
	if State.distanceEnabled and State.distanceState and State.distanceState.enabled then
		local label = tostring(State.distanceState.label or '')
		if label ~= '' then
			local rangeColor = Client.hexColorToRgb(State.distanceState.color, color)
			addTaggedMessage('[' .. label .. '] ', name, rangeColor or color, message)
			return
		end
	end

	addTaggedMessage('[Local] ', name, color, message)
end

local function sendSuggestionBatch(suggestions)
	local batchSize = constants.suggestionBatchSize
	local count = 0
	local batch = {}

	for i = 1, #suggestions do
		count = count + 1
		batch[count] = suggestions[i]

		if count >= batchSize then
			Client.sendNuiMessage({
				type = 'ON_SUGGESTIONS_ADD',
				suggestions = batch
			})
			batch = {}
			count = 0
		end
	end

	if count > 0 then
		Client.sendNuiMessage({
			type = 'ON_SUGGESTIONS_ADD',
			suggestions = batch
		})
	end
end

local function globalCommand(_, args)
	TriggerServerEvent('poodlechat:globalMessage', table.concat(args, ' '))
end

local function whisperCommand(_, args)
	local id = args[1]
	table.remove(args, 1)
	TriggerServerEvent('poodlechat:whisperMessage', id, table.concat(args, ' '))
end

local function replyCommand(_, args)
	if State.ReplyTo then
		TriggerServerEvent('poodlechat:whisperMessage', State.ReplyTo, table.concat(args, ' '))
	else
		Client.addChatMessage({255, 0, 0}, 'Error', 'No-one to reply to')
	end
end

local function setChannel(name)
	if not ensureContext() then
		return
	end

	local channelId = channelIdByName[name]
	if not channelId then
		return
	end

	State.Channel = name

	Client.sendNuiMessage({
		type = 'setChannel',
		channelId = channelId
	})
end

local function cycleChannel()
	if not ensureContext() then
		return
	end

	local sequence
	if State.Permissions.canAccessStaffChannel then
		sequence = {'Local', 'Global', 'Staff'}
	else
		sequence = {'Local', 'Global'}
	end

	local currentIndex = nil
	for i = 1, #sequence do
		if sequence[i] == State.Channel then
			currentIndex = i
			break
		end
	end

	if not currentIndex then
		setChannel(sequence[1])
		return
	end

	local nextIndex = currentIndex + 1
	if nextIndex > #sequence then
		nextIndex = 1
	end

	setChannel(sequence[nextIndex])
end

local function loadSavedSettings()
	if not ensureContext() then
		return
	end

	local mutedJson = GetResourceKvpString('mutedPlayers')
	local muted = Client.decodeJson(mutedJson)

	if type(muted) == 'table' then
		State.MutedPlayers = muted
	end

	local emojiUsageJson = GetResourceKvpString('emojiUsage')
	local usage = Client.decodeJson(emojiUsageJson)

	if type(usage) == 'table' then
		local normalized = {}
		for glyph, count in pairs(usage) do
			local number = tonumber(count)
			if type(glyph) == 'string' and number and number > 0 then
				normalized[glyph] = math.floor(number)
			end
		end
		State.EmojiUsage = normalized
	end

	local emojiRecentJson = GetResourceKvpString('emojiRecent')
	local recent = Client.decodeJson(emojiRecentJson)

	if type(recent) == 'table' then
		local normalizedRecent = {}
		for i = 1, #recent do
			local glyph = recent[i]
			if type(glyph) == 'string' and glyph ~= '' then
				normalizedRecent[#normalizedRecent + 1] = glyph
			end
			if #normalizedRecent >= State.EmojiRecentLimit then
				break
			end
		end
		State.EmojiRecent = normalizedRecent
	end

	local displayMessagesAbovePlayers = GetResourceKvpString('displayMessagesAbovePlayers')

	if displayMessagesAbovePlayers == 'true' then
		State.DisplayMessagesAbovePlayers = true
	elseif displayMessagesAbovePlayers == 'false' then
		State.DisplayMessagesAbovePlayers = false
	end

	if State.typingSystemEnabled and State.typingToggleAllowed then
		local typingSaved = GetResourceKvpString('typingIndicatorEnabled')
		if typingSaved == 'true' then
			State.typingDisplayEnabled = true
		elseif typingSaved == 'false' then
			State.typingDisplayEnabled = false
		end
	end

	if State.bubbleSystemEnabled and State.bubbleToggleAllowed then
		local bubbleSaved = GetResourceKvpString('chatBubblesEnabled')
		if bubbleSaved == 'true' then
			State.bubbleDisplayEnabled = true
		elseif bubbleSaved == 'false' then
			State.bubbleDisplayEnabled = false
		end
	end

	Client.markEmojiDirty()
end

local startupSuggestions = {
	{ '/clear', 'Clear chat window' },
	{
		'/global',
		'Send a message to all players',
		{
			{name = 'message', help = 'The message to send'}
		}
	},
	{
		'/g',
		'Send a message to all players',
		{
			{name = 'message', help = 'The message to send'}
		}
	},
	{
		'/me',
		'Perform an action',
		{
			{name = 'action', help = 'The action to perform'}
		}
	},
	{
		'/mute',
		'Mute a player, hiding their messages in text chat',
		{
			{name = 'player', help = 'ID or name of the player to mute'}
		}
	},
	{ '/muted', 'Show a list of muted players' },
	{
		'/nick',
		'Set a nickname used for chat messages',
		{
			{name = 'nickname', help = 'The new nickname to use. Omit to unset your current nickname.'}
		}
	},
	{
		'/reply',
		'Reply to the last whisper',
		{
			{name = 'message', help = 'The message to send'}
		}
	},
	{
		'/r',
		'Reply to the last whisper',
		{
			{name = 'message', help = 'The message to send'}
		}
	},
	{
		'/report',
		'Report another player for abuse',
		{
			{name = 'player', help = 'ID or name of the player to report'},
			{name = 'reason', help = 'Reason you are reporting this player'}
		}
	},
	{
		'/say',
		'Send a message to nearby players',
		{
			{name = 'message', help = 'The message to send'}
		}
	},
	{ '/togglechat', 'Toggle the chat on/off' },
	{ '/toggleoverhead', 'Toggle overhead messages on/off' },
	{
		'/unmute',
		'Unmute a player, allowing you to see their messages in text chat again',
		{
			{name = 'player', help = 'ID or name of the player to unmute'}
		}
	},
	{
		'/whisper',
		'Send a private message',
		{
			{name = 'player', help = 'ID or name of the player to message'},
			{name = 'message', help = 'The message to send'}
		}
	},
	{
		'/w',
		'Send a private message',
		{
			{name = 'player', help = 'ID or name of the player to message'},
			{name = 'message', help = 'The message to send'}
		}
	}
}

local function registerStartupSuggestions()
	if not ensureContext() then
		return
	end

	for i = 1, #startupSuggestions do
		local suggestion = startupSuggestions[i]
		TriggerEvent('chat:addSuggestion', suggestion[1], suggestion[2], suggestion[3])
	end

	if State.typingSystemEnabled and State.typingToggleAllowed then
		TriggerEvent('chat:addSuggestion', '/toggletyping', 'Toggle typing indicator on/off')
	end

	if State.bubbleSystemEnabled and State.bubbleToggleAllowed then
		TriggerEvent('chat:addSuggestion', '/togglebubbles', 'Toggle chat bubbles on/off')
	end
end

local function refreshCommands()
	if not ensureContext() then
		return
	end

	if not GetRegisteredCommands then
		return
	end

	local registeredCommands = GetRegisteredCommands()
	local suggestions = {}

	for _, command in ipairs(registeredCommands) do
		if IsAceAllowed(('command.%s'):format(command.name)) then
			suggestions[#suggestions + 1] = {
				name = '/' .. command.name,
				help = ''
			}
		end
	end

	TriggerEvent('chat:addSuggestions', suggestions)
end

local function refreshThemes()
	if not ensureContext() then
		return
	end

	local themes = {}

	for resourceIndex = 0, GetNumResources() - 1 do
		local resource = GetResourceByFindIndex(resourceIndex)

		if GetResourceState(resource) == 'started' then
			local numThemes = GetNumResourceMetadata(resource, 'chat_theme')

			if numThemes > 0 then
				local themeName = GetResourceMetadata(resource, 'chat_theme')
				local themeData = Client.decodeJson(GetResourceMetadata(resource, 'chat_theme_extra') or 'null')

				if themeName and themeData then
					themeData.baseUrl = 'nui://' .. resource .. '/'
					themes[themeName] = themeData
				end
			end
		end
	end

	Client.sendNuiMessage({
		type = 'ON_UPDATE_THEMES',
		themes = themes
	})
end

local function buildOnLoadPayload()
	if not ensureContext() then
		return {}
	end

	setChannel(State.Channel)
	Client.refreshDistanceState(true)
	Client.sendFeatureState()

	return {
		localColor = State.LocalMessageColor,
		globalColor = State.GlobalMessageColor,
		staffColor = State.StaffMessageColor,
		emoji = {},
		emojiPanel = Client.getEmojiPanelData(),
		distance = State.distanceState,
		features = Client.getFeatureStatePayload(),
		ui = {
			fadeTimeout = tonumber(uiConfig.fadeTimeout) or 7000,
			suggestionLimit = math.max(1, tonumber(uiConfig.suggestionLimit) or 5),
			style = uiConfig.chatStyle or {},
			templates = uiConfig.templates or {},
			defaultTemplateId = tostring(uiConfig.defaultTemplateId or 'default'),
			defaultAltTemplateId = tostring(uiConfig.defaultAltTemplateId or 'defaultAlt'),
			runtime = {
				emojiRenderBatchSize = tonumber(runtimeUiConfig.emojiRenderBatchSize) or 260,
				emojiSearchDebounceMs = tonumber(runtimeUiConfig.emojiSearchDebounceMs) or 80,
				inputFocusDelayMs = tonumber(runtimeUiConfig.inputFocusDelayMs) or 100,
				pageScrollStep = tonumber(runtimeUiConfig.pageScrollStep) or 100
			}
		}
	}
end

local function registerChatHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	RegisterCommand('global', globalCommand, false)
	RegisterCommand('g', globalCommand, false)

	RegisterCommand('me', function(_, args)
		TriggerServerEvent('poodlechat:actionMessage', table.concat(args, ' '))
	end, false)

	RegisterCommand('whisper', whisperCommand, false)
	RegisterCommand('w', whisperCommand, false)

	RegisterCommand('clear', function()
		TriggerEvent('chat:clear')
	end, false)

	RegisterCommand('toggleoverhead', function()
		State.DisplayMessagesAbovePlayers = not State.DisplayMessagesAbovePlayers
		Client.addChatMessage({255, 255, 128}, 'Overhead messages', State.DisplayMessagesAbovePlayers and 'on' or 'off')
		SetResourceKvp('displayMessagesAbovePlayers', State.DisplayMessagesAbovePlayers and 'true' or 'false')
	end, false)

	RegisterCommand('toggletyping', function()
		Client.toggleTypingDisplay()
	end, false)

	RegisterCommand('togglebubbles', function()
		Client.toggleBubbleDisplay()
	end, false)

	AddEventHandler('poodlechat:globalMessage', function(id, license, name, color, message)
		if isMutedLicense(license) then
			return
		end

		addGlobalMessage(name, color, message)

		if State.DisplayMessagesAbovePlayers then
			Client.displayTextAbovePlayer(id, color, message)
		end
	end)

	AddEventHandler('poodlechat:localMessage', function(id, license, name, color, message)
		if isMutedLicense(license) then
			return
		end

		if Client.isInProximity(id, State.LocalMessageDistance) then
			addLocalMessage(name, color, message)

			if State.DisplayMessagesAbovePlayers then
				Client.displayTextAbovePlayer(id, color, message)
			end
		end
	end)

	AddEventHandler('poodlechat:action', function(id, license, name, message)
		if isMutedLicense(license) then
			return
		end

		if Client.isInProximity(id, State.ActionMessageDistance) then
			Client.addChatMessage(State.ActionMessageColor, '^*' .. name .. '^r^* ' .. message)

			if State.DisplayMessagesAbovePlayers then
				Client.displayTextAbovePlayer(id, State.ActionMessageColor, '*' .. message .. '*')
			end
		end
	end)

	AddEventHandler('poodlechat:whisperEcho', function(_, license, name, message)
		if isMutedLicense(license) then
			Client.addChatMessage({255, 0, 0}, 'Error', name .. ' is muted')
			return
		end

		Client.addChatMessage(State.WhisperEchoColor, '[Whisper@' .. name .. ']', message)

		if State.DisplayMessagesAbovePlayers then
			Client.displayTextAbovePlayer(GetPlayerServerId(PlayerId()), State.WhisperColor, message)
		end
	end)

	AddEventHandler('poodlechat:whisper', function(id, license, name, message)
		if isMutedLicense(license) then
			return
		end

		Client.addChatMessage(State.WhisperColor, '[Whisper] ' .. name, message)

		if State.DisplayMessagesAbovePlayers then
			Client.displayTextAbovePlayer(id, State.WhisperColor, message)
		end
	end)

	AddEventHandler('poodlechat:whisperError', function(id)
		Client.addChatMessage({255, 0, 0}, 'Error', 'No user with ID or name ' .. tostring(id))
	end)

	RegisterCommand('reply', replyCommand, false)
	RegisterCommand('r', replyCommand, false)

	AddEventHandler('poodlechat:setReplyTo', function(id)
		State.ReplyTo = tostring(id)
	end)

	RegisterCommand('togglechat', function()
		State.HideChat = not State.HideChat
	end)

	RegisterCommand('staff', function(_, args)
		local message = table.concat(args, ' ')

		if message == '' then
			return
		end

		TriggerServerEvent('poodlechat:staffMessage', message)
	end)

	AddEventHandler('poodlechat:staffMessage', function(id, name, color, message)
		Client.addChatMessage(color, '[Staff] ' .. name, message)

		if State.DisplayMessagesAbovePlayers then
			Client.displayTextAbovePlayer(id, color, message)
		end
	end)

	AddEventHandler('poodlechat:setPermissions', function(permissions)
		State.Permissions = permissions

		Client.sendNuiMessage({
			type = 'setPermissions',
			permissions = json.encode(permissions)
		})
	end)

	RegisterCommand('report', function(_, args)
		if #args < 2 then
			Client.addChatMessage({255, 0, 0}, 'Error', 'You must specify a player and a reason')
			return
		end

		local player = table.remove(args, 1)
		local reason = table.concat(args, ' ')

		TriggerServerEvent('poodlechat:report', player, reason)
	end, false)

	RegisterCommand('mute', function(_, args)
		if #args < 1 then
			Client.addChatMessage({255, 0, 0}, 'Error', 'You must specify a player to mute')
			return
		end

		TriggerServerEvent('poodlechat:mute', args[1])
	end, false)

	AddEventHandler('poodlechat:mute', function(id, license)
		local player = GetPlayerFromServerId(id)
		local name = player ~= -1 and GetPlayerName(player) or tostring(id)

		State.MutedPlayers[license] = name

		Client.addChatMessage({255, 255, 128}, name .. ' was muted')
		Client.encodeAndStore('mutedPlayers', State.MutedPlayers)
	end)

	RegisterCommand('unmute', function(_, args)
		if #args < 1 then
			Client.addChatMessage({255, 0, 0}, 'Error', 'You must specify a player to unmute')
			return
		end

		TriggerServerEvent('poodlechat:unmute', args[1])
	end)

	AddEventHandler('poodlechat:unmute', function(id, license)
		local player = GetPlayerFromServerId(id)
		local name = player ~= -1 and GetPlayerName(player) or tostring(id)

		State.MutedPlayers[license] = nil

		Client.addChatMessage({255, 255, 128}, name .. ' was unmuted')
		Client.encodeAndStore('mutedPlayers', State.MutedPlayers)
	end)

	RegisterCommand('muted', function()
		TriggerServerEvent('poodlechat:showMuted', State.MutedPlayers)
	end)

	AddEventHandler('poodlechat:showMuted', function(mutedPlayerIds)
		local muted = {}

		table.sort(mutedPlayerIds)

		for _, id in ipairs(mutedPlayerIds) do
			local player = GetPlayerFromServerId(id)
			local name = player ~= -1 and GetPlayerName(player) or tostring(id)
			muted[#muted + 1] = string.format('%s [%d]', name, id)
		end

		if #muted == 0 then
			Client.addChatMessage({255, 255, 128}, 'No players are muted')
		else
			Client.addChatMessage({255, 255, 128}, 'Muted', table.concat(muted, ', '))
		end
	end)

	handlersRegistered = true
end

Client.isMutedLicense = isMutedLicense
Client.sendSuggestionBatch = sendSuggestionBatch
Client.SetChannel = setChannel
Client.CycleChannel = cycleChannel
Client.LoadSavedSettings = loadSavedSettings
Client.registerStartupSuggestions = registerStartupSuggestions
Client.refreshCommands = refreshCommands
Client.refreshThemes = refreshThemes
Client.buildOnLoadPayload = buildOnLoadPayload
Client.registerChatHandlers = registerChatHandlers
