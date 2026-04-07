local Client = PoodleChatClient
local State = nil
local config = nil
local constants = nil
local handlersRegistered = false
local tabGroupingKvpKey = 'poodlechat:tabGrouping:v1'
local tabNotificationKvpKey = 'poodlechat:tabNotifications:v1'
local notificationSoundKvpKey = 'poodlechat:notificationSound:v1'

local function ensureContext()
	if State and config and constants then
		return true
	end

	State = Client.state
	config = Client.config
	constants = Client.constants

	return State ~= nil and config ~= nil and constants ~= nil
end

local function isMutedLicense(license)
	return license and State.MutedPlayers[license] ~= nil
end

local function getChannel(channelId)
	local id = Client.normalizeKey(channelId) or constants.defaultChannelId
	return constants.channelById[id] or constants.channelById[constants.defaultChannelId]
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

local function getVoiceProximityForSource(sourceId)
	if constants.voiceEnabled ~= true or GetResourceState(tostring(constants.voiceResourceName or 'pma-voice')) ~= 'started' then
		return nil
	end

	local proximity = nil
	local sourceNumber = tonumber(sourceId)
	if sourceNumber then
		local playerId = GetPlayerFromServerId(sourceNumber)
		if playerId ~= -1 then
			local player = Player(playerId)
			if player and type(player.state) == 'table' and type(player.state.proximity) == 'table' then
				proximity = player.state.proximity
			end
		end
	end

	if type(proximity) ~= 'table' and type(LocalPlayer) == 'table' and type(LocalPlayer.state) == 'table' then
		local localProximity = LocalPlayer.state.proximity
		if type(localProximity) == 'table' then
			proximity = localProximity
		end
	end

	if type(proximity) ~= 'table' then
		return nil
	end

	return proximity
end

local function getVoiceModeLabelForSource(sourceId)
	local proximity = getVoiceProximityForSource(sourceId)
	if type(proximity) ~= 'table' then
		return nil
	end

	return formatVoiceModeLabel(proximity.mode)
end

local function getLocalChannelDisplayLabel(sourceId)
	if constants.voiceEnabled == true and GetResourceState(tostring(constants.voiceResourceName or 'pma-voice')) == 'started' then
		local modeLabel = getVoiceModeLabelForSource(sourceId)
		if modeLabel and modeLabel ~= '' then
			return modeLabel
		end
		return 'Range'
	end

	local channel = getChannel('local')
	return channel and channel.label or 'Local'
end

local function normalizeVoiceModeIndex(rawIndex, modeCount)
	local value = tonumber(rawIndex)
	if not value then
		return nil
	end

	local index = math.floor(value + 0.5)
	if index <= 0 then
		return nil
	end

	local total = tonumber(modeCount)
	if not total or total <= 0 then
		return index
	end

	total = math.max(1, math.floor(total + 0.5))
	if index > total and (index - 1) >= 1 and (index - 1) <= total then
		return index - 1
	end

	return Client.clamp(index, 1, total)
end

local function getClosestVoiceModeIndexByDistance(distance)
	if type(State.voiceModes) ~= 'table' or #State.voiceModes == 0 then
		return nil
	end

	local bestIndex = nil
	local bestDiff = math.huge

	for i = 1, #State.voiceModes do
		local mode = State.voiceModes[i]
		local modeRange = tonumber(mode and mode.range)
		local modeIndex = normalizeVoiceModeIndex(mode and mode.index, #State.voiceModes)
		if modeRange and modeIndex then
			local diff = math.abs(distance - modeRange)
			if diff < bestDiff then
				bestDiff = diff
				bestIndex = modeIndex
			end
		end
	end

	return bestIndex
end

local function getVoiceColorForSource(sourceId)
	if constants.voiceEnabled ~= true or GetResourceState(tostring(constants.voiceResourceName or 'pma-voice')) ~= 'started' then
		return nil
	end

	local proximity = getVoiceProximityForSource(sourceId)
	if type(proximity) ~= 'table' then
		return nil
	end

	local colorLevels = type(State.voiceLevelColors) == 'table' and State.voiceLevelColors or {}
	local modeCount = tonumber(State.distanceModeCount)
	if not modeCount or modeCount <= 0 then
		modeCount = #colorLevels
	end
	if modeCount <= 0 then
		return nil
	end

	local modeIndex = normalizeVoiceModeIndex(proximity.index, modeCount)
	if not modeIndex then
		local distance = tonumber(proximity.distance)
		if distance then
			modeIndex = getClosestVoiceModeIndexByDistance(distance)
		end
	end
	if not modeIndex then
		return nil
	end

	local colorHex = tostring(colorLevels[modeIndex] or '')
	if colorHex == '' then
		return nil
	end

	local parsed = Client.hexColorToRgb(colorHex, nil)
	if type(parsed) ~= 'table' then
		return nil
	end

	return {
		tonumber(parsed[1]) or 255,
		tonumber(parsed[2]) or 255,
		tonumber(parsed[3]) or 255
	}
end

local function getFirstAccessibleChannelId()
	for i = 1, #constants.channelList do
		local channel = constants.channelList[i]
		if channel and channel.id and Client.canAccessChannel(channel.id) then
			return channel.id
		end
	end

	return constants.defaultChannelId
end

local function resolveChannelWithFallback(channelId)
	local normalized = Client.normalizeKey(channelId)

	if constants.separateChannelTabs ~= true then
		normalized = constants.singleChannelId or constants.defaultChannelId
	end

	if not normalized or not constants.channelById[normalized] or not Client.canAccessChannel(normalized) then
		normalized = constants.defaultChannelId
	end

	if not normalized or not constants.channelById[normalized] or not Client.canAccessChannel(normalized) then
		normalized = getFirstAccessibleChannelId()
	end

	return normalized
end

local function normalizeLimit(value, fallback)
	local number = tonumber(value)
	if number == nil then
		number = tonumber(fallback)
	end

	if number == nil then
		return 1
	end

	number = math.floor(number)
	if number < 0 then
		return -1
	end
	if number == 0 then
		return math.max(1, math.floor(tonumber(fallback) or 1))
	end

	return number
end

local function buildDefaultTabGrouping()
	local defaults = {}
	local maxGroup = 0
	local configured = type(constants.defaultTabGrouping) == 'table' and constants.defaultTabGrouping or {}

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local groupId = tonumber(configured[channelId])
		if groupId and groupId > 0 then
			groupId = math.floor(groupId)
			defaults[channelId] = groupId
			if groupId > maxGroup then
				maxGroup = groupId
			end
		end
	end

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		if not defaults[channelId] then
			maxGroup = maxGroup + 1
			defaults[channelId] = maxGroup
		end
	end

	return defaults
end

local function normalizeTabGrouping(rawGrouping)
	local normalized = {}
	local highestGroup = 0

	if type(rawGrouping) == 'table' then
		for i = 1, #constants.channelList do
			local channelId = constants.channelList[i].id
			local groupId = tonumber(rawGrouping[channelId])
			if groupId and groupId > 0 then
				groupId = math.floor(groupId)
				normalized[channelId] = groupId
				if groupId > highestGroup then
					highestGroup = groupId
				end
			end
		end
	end

	local defaults = buildDefaultTabGrouping()
	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		if not normalized[channelId] then
			local fallbackGroup = tonumber(defaults[channelId])
			if fallbackGroup and fallbackGroup > 0 then
				fallbackGroup = math.floor(fallbackGroup)
				normalized[channelId] = fallbackGroup
				if fallbackGroup > highestGroup then
					highestGroup = fallbackGroup
				end
			else
				highestGroup = highestGroup + 1
				normalized[channelId] = highestGroup
			end
		end
	end

	return normalized
end

local function normalizeTabNotificationToggles(rawToggles)
	local normalized = {}
	if type(rawToggles) ~= 'table' then
		return normalized
	end

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local value = rawToggles[channelId]
		if value ~= nil then
			normalized[channelId] = value == true or value == 'true'
		end
	end

	return normalized
end

local function normalizeMessagePayload(message)
	local raw = type(message) == 'table' and message or {text = tostring(message or '')}
	local channelId = Client.normalizeKey(raw.channel)

	if not channelId or not constants.channelById[channelId] then
		channelId = Client.getActiveCommandContextChannel() or constants.defaultChannelId
	end

	channelId = resolveChannelWithFallback(channelId)

	local channel = getChannel(channelId)
	local color = Client.normalizeRgbColor(raw.color, channel and channel.color or {255, 255, 255})
	local label = tostring(raw.label or (channel and channel.label or 'Chat'))
	local args = type(raw.args) == 'table' and raw.args or nil

	if not args then
		local text = tostring(raw.text or raw.message or '')
		if text ~= '' then
			args = {label, text}
		else
			args = {label}
		end
	end

	return {
		channel = channelId,
		label = label,
		color = color,
		args = args,
		template = raw.template,
		templateId = raw.templateId,
		multiline = raw.multiline ~= false,
		metadata = type(raw.metadata) == 'table' and raw.metadata or nil
	}
end

local function sendChannelMessage(message)
	TriggerEvent('chat:addMessage', normalizeMessagePayload(message))
end

local function setChannel(channelId)
	if not ensureContext() then
		return
	end

	local normalized = Client.normalizeKey(channelId)
	normalized = resolveChannelWithFallback(normalized)

	State.Channel = normalized

	Client.sendNuiMessage({
		type = 'setChannel',
		channelId = normalized
	})
end

local function cycleChannel()
	if not ensureContext() then
		return
	end

	if constants.separateChannelTabs ~= true then
		setChannel(constants.singleChannelId or constants.defaultChannelId)
		return
	end

	local available = {}
	for i = 1, #constants.channelList do
		local channel = constants.channelList[i]
		if channel.visible ~= false and channel.cycle ~= false and Client.canAccessChannel(channel.id) then
			available[#available + 1] = channel.id
		end
	end

	if #available == 0 then
		return
	end

	local currentIndex = 1
	for i = 1, #available do
		if available[i] == State.Channel then
			currentIndex = i
			break
		end
	end

	local nextIndex = currentIndex + 1
	if nextIndex > #available then
		nextIndex = 1
	end

	setChannel(available[nextIndex])
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

	if State.whisperSoundToggleAllowed then
		local whisperSoundSaved = GetResourceKvpString(notificationSoundKvpKey)
		if whisperSoundSaved ~= 'true' and whisperSoundSaved ~= 'false' then
			whisperSoundSaved = GetResourceKvpString('whisperSoundEnabled')
		end
		if whisperSoundSaved == 'true' then
			State.whisperSoundEnabled = true
		elseif whisperSoundSaved == 'false' then
			State.whisperSoundEnabled = false
		end
	end

	if State.autoScrollToggleAllowed then
		local autoScrollSaved = GetResourceKvpString('chatAutoScrollEnabled')
		if autoScrollSaved == 'true' then
			State.autoScrollEnabled = true
		elseif autoScrollSaved == 'false' then
			State.autoScrollEnabled = false
		end
	end

	local tabGroupingSaved = Client.decodeJson(GetResourceKvpString(tabGroupingKvpKey))
	State.TabGrouping = normalizeTabGrouping(tabGroupingSaved)

	local tabNotificationSaved = Client.decodeJson(GetResourceKvpString(tabNotificationKvpKey))
	State.TabNotificationToggles = normalizeTabNotificationToggles(tabNotificationSaved)

	Client.markEmojiDirty()
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

local function buildSuggestionListFromCommands()
	local suggestions = {}
	for _, command in pairs(constants.commandByKey) do
		if command.enabled == true then
			suggestions[#suggestions + 1] = {
				'/' .. command.command,
				command.help ~= '' and command.help or ('Send a message in ' .. tostring(command.label)),
				nil
			}
			for i = 1, #command.aliases do
				suggestions[#suggestions + 1] = {
					'/' .. command.aliases[i],
					command.help ~= '' and command.help or ('Alias for /' .. command.command),
					nil
				}
			end
		end
	end

	return suggestions
end

local function registerStartupSuggestions()
	if not ensureContext() then
		return
	end

	local suggestions = buildSuggestionListFromCommands()
	for i = 1, #suggestions do
		local suggestion = suggestions[i]
		TriggerEvent('chat:addSuggestion', suggestion[1], suggestion[2], suggestion[3])
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

local function getAllowedChannelsPayload()
	local channels = {}
	for i = 1, #constants.channelList do
		local entry = constants.channelList[i]
		channels[#channels + 1] = {
			id = entry.id,
			label = entry.label,
			color = entry.color,
			order = entry.order,
			visible = entry.visible,
			cycle = entry.cycle,
			canSend = entry.canSend,
			maxHistory = entry.maxHistory,
			allowed = Client.canAccessChannel(entry.id)
		}
	end
	return channels
end

local function getNotificationProfilesPayload()
	local defaultProfile = type(constants.notificationDefaultProfile) == 'table' and constants.notificationDefaultProfile or {}
	local byChannel = type(constants.notificationByChannel) == 'table' and constants.notificationByChannel or {}
	local channels = {}

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local profile = byChannel[channelId]
		if type(profile) == 'table' then
			channels[channelId] = profile
		end
	end

	return defaultProfile, channels
end

local function setTabGrouping(rawGrouping)
	if not ensureContext() then
		return {}
	end

	State.TabGrouping = normalizeTabGrouping(rawGrouping)
	Client.encodeAndStore(tabGroupingKvpKey, State.TabGrouping)
	return State.TabGrouping
end

local function setTabNotificationToggle(channelId, enabled)
	if not ensureContext() then
		return nil
	end

	local normalizedChannelId = Client.normalizeKey(channelId)
	if not normalizedChannelId or not constants.channelById[normalizedChannelId] then
		return nil
	end

	if type(State.TabNotificationToggles) ~= 'table' then
		State.TabNotificationToggles = {}
	end

	State.TabNotificationToggles[normalizedChannelId] = enabled == true
	Client.encodeAndStore(tabNotificationKvpKey, State.TabNotificationToggles)
	Client.sendFeatureState()
	return State.TabNotificationToggles[normalizedChannelId]
end

local function getTabNotificationToggles()
	if not ensureContext() then
		return {}
	end
	if type(State.TabNotificationToggles) ~= 'table' then
		State.TabNotificationToggles = {}
	end
	return State.TabNotificationToggles
end

local function buildOnLoadPayload()
	if not ensureContext() then
		return {}
	end

	if not constants.channelById[State.Channel] then
		State.Channel = constants.defaultChannelId
	end

	setChannel(State.Channel)
	Client.refreshDistanceState(true)
	Client.sendFeatureState()

	local notificationDefaultProfile, notificationChannels = getNotificationProfilesPayload()

	return {
		playerServerId = GetPlayerServerId(PlayerId()),
		channels = getAllowedChannelsPayload(),
		activeChannel = State.Channel,
		tabs = {
			grouping = State.TabGrouping,
			defaultGrouping = buildDefaultTabGrouping()
		},
		notifications = {
			default = notificationDefaultProfile,
			channels = notificationChannels,
			toggles = getTabNotificationToggles()
		},
		whispers = {
			maxConversations = normalizeLimit(config.whispers.maxConversations, 30),
			maxMessagesPerConversation = normalizeLimit(config.whispers.maxMessagesPerConversation, 80),
			defaultConversationMode = tostring(config.whispers.defaultConversationMode or 'active-only'),
			separateWhisperTab = constants.whisperTabEnabled == true,
			fallbackChannel = constants.whisperFallbackChannelId or constants.defaultChannelId,
			notifications = {
				enabled = State.whisperSoundEnabled == true,
				allowToggle = State.whisperSoundToggleAllowed == true,
				volume = tonumber(constants.whisperNotificationVolume) or 0.65
			},
			sidebar = {
				collapsible = constants.whisperSidebarCollapsible == true,
				defaultCollapsed = constants.whisperSidebarDefaultCollapsed == true
			}
		},
		emoji = {},
		emojiPanel = Client.getEmojiPanelData(),
		distance = State.distanceState,
		features = Client.getFeatureStatePayload(),
		ui = {
			fadeTimeout = tonumber(config.ui.fadeTimeout) or 7000,
			suggestionLimit = math.max(1, tonumber(config.ui.suggestionLimit) or 5),
			style = config.ui.chatStyle or {},
			separateChannelTabs = constants.separateChannelTabs ~= false,
			singleChannelId = constants.singleChannelId or constants.defaultChannelId,
			autoScrollDefault = State.autoScrollEnabled == true,
			templates = config.ui.templates or {},
			defaultTemplateId = tostring(config.ui.defaultTemplateId or 'default'),
			defaultAltTemplateId = tostring(config.ui.defaultAltTemplateId or 'defaultAlt'),
			runtime = {
				emojiRenderBatchSize = tonumber(((config.runtime or {}).ui or {}).emojiRenderBatchSize) or 260,
				emojiSearchDebounceMs = tonumber(((config.runtime or {}).ui or {}).emojiSearchDebounceMs) or 80,
				inputFocusDelayMs = tonumber(((config.runtime or {}).ui or {}).inputFocusDelayMs) or 100,
				pageScrollStep = tonumber(((config.runtime or {}).ui or {}).pageScrollStep) or 100
			}
		}
	}
end

local function sendMutedError(name)
	sendChannelMessage({
		channel = constants.defaultChannelId,
		label = 'Error',
		color = {255, 0, 0},
		args = {'Error', tostring(name) .. ' is muted'}
	})
end

local function sendSimpleError(text)
	sendChannelMessage({
		channel = constants.defaultChannelId,
		label = 'Error',
		color = {255, 0, 0},
		args = {'Error', tostring(text)}
	})
end

local function addEnvelopeToChat(message)
	local normalized = normalizeMessagePayload(message)
	local metadata = normalized.metadata or {}
	local license = metadata.license or message.license
	if isMutedLicense(license) then
		return
	end

	if normalized.channel == 'local' and metadata.type == 'chat' then
		local rangeColor = getVoiceColorForSource(metadata.source)
		if rangeColor then
			normalized.color = rangeColor
		end
	end

	if metadata.source and State.DisplayMessagesAbovePlayers then
		local text = normalized.args[#normalized.args]
		if type(text) == 'string' and text ~= '' then
			Client.displayTextAbovePlayer(metadata.source, normalized.color, text)
		end
	end

	TriggerEvent('chat:addMessage', normalized)
end

local function executeClientCommand(commandKey, commandName, args)
	local command = constants.commandByKey[commandKey]
	if not command or command.enabled ~= true then
		return
	end

	Client.setCommandContext(commandName)

	local message = table.concat(args, ' ')
	local handler = command.handler

	if handler == 'global' then
		TriggerServerEvent('poodlechat:globalMessage', message)
		return
	end

	if handler == 'action' then
		TriggerServerEvent('poodlechat:actionMessage', message)
		return
	end

	if handler == 'whisper' then
		local id = args[1]
		if not id then
			sendSimpleError('You must specify a player and a message')
			return
		end

		table.remove(args, 1)
		TriggerServerEvent('poodlechat:whisperMessage', id, table.concat(args, ' '))

		if constants.whisperTabEnabled == true then
			Client.SetChannel('whispers')
			Client.sendNuiMessage({
				type = 'setChannel',
				channelId = 'whispers'
			})
		end
		return
	end

	if handler == 'reply' then
		if State.ReplyTo then
			TriggerServerEvent('poodlechat:whisperMessage', State.ReplyTo, message)
			if constants.whisperTabEnabled == true then
				Client.SetChannel('whispers')
				Client.sendNuiMessage({
					type = 'setChannel',
					channelId = 'whispers'
				})
			end
		else
			sendSimpleError('No-one to reply to')
		end
		return
	end

	if handler == 'clear' then
		TriggerEvent('chat:clear')
		return
	end

	if handler == 'toggleoverhead' then
		State.DisplayMessagesAbovePlayers = not State.DisplayMessagesAbovePlayers
		sendChannelMessage({
			channel = command.channel,
			label = command.label,
			color = command.color,
			args = {'Overhead messages', State.DisplayMessagesAbovePlayers and 'on' or 'off'}
		})
		SetResourceKvp('displayMessagesAbovePlayers', State.DisplayMessagesAbovePlayers and 'true' or 'false')
		return
	end

	if handler == 'toggletyping' then
		Client.toggleTypingDisplay()
		return
	end

	if handler == 'togglebubbles' then
		Client.toggleBubbleDisplay()
		return
	end

	if handler == 'togglesound' then
		Client.toggleWhisperSound()
		return
	end

	if handler == 'togglechat' then
		State.HideChat = not State.HideChat
		return
	end

	if handler == 'staff' then
		if message ~= '' then
			TriggerServerEvent('poodlechat:staffMessage', message)
		end
		return
	end

	if handler == 'report' then
		if #args < 2 then
			sendSimpleError('You must specify a player and a reason')
			return
		end
		local player = table.remove(args, 1)
		local reason = table.concat(args, ' ')
		TriggerServerEvent('poodlechat:report', player, reason)
		return
	end

	if handler == 'mute' then
		if #args < 1 then
			sendSimpleError('You must specify a player to mute')
			return
		end
		TriggerServerEvent('poodlechat:mute', args[1])
		return
	end

	if handler == 'unmute' then
		if #args < 1 then
			sendSimpleError('You must specify a player to unmute')
			return
		end
		TriggerServerEvent('poodlechat:unmute', args[1])
		return
	end

	if handler == 'muted' then
		TriggerServerEvent('poodlechat:showMuted', State.MutedPlayers)
		return
	end
end

local function registerConfiguredCommands()
	local supportedHandlers = {
		global = true,
		action = true,
		whisper = true,
		reply = true,
		clear = true,
		toggleoverhead = true,
		toggletyping = true,
		togglebubbles = true,
		togglesound = true,
		togglechat = true,
		staff = true,
		report = true,
		mute = true,
		unmute = true,
		muted = true
	}

	for key, command in pairs(constants.commandByKey) do
		if command.enabled == true and supportedHandlers[command.handler] then
			local names = {command.command}
			for i = 1, #command.aliases do
				names[#names + 1] = command.aliases[i]
			end

			for i = 1, #names do
				local name = names[i]
				local lower = Client.normalizeKey(name)
				if lower then
					RegisterCommand(lower, function(_, args)
						executeClientCommand(key, lower, args)
					end, false)
				end
			end
		end
	end
end

local function registerChatHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
	end

	registerConfiguredCommands()

	AddEventHandler('poodlechat:channelMessage', function(message)
		addEnvelopeToChat(message)
	end)

	AddEventHandler('poodlechat:globalMessage', function(id, license, name, color, message)
		if isMutedLicense(license) then
			return
		end

		addEnvelopeToChat({
			channel = 'global',
			label = getChannel('global').label,
			color = color,
			args = {'[' .. getChannel('global').label .. '] ' .. name, message},
			metadata = {
				type = 'chat',
				source = id,
				license = license
			}
		})
	end)

	AddEventHandler('poodlechat:localMessage', function(id, license, name, color, message)
		if isMutedLicense(license) then
			return
		end

		if Client.isInProximity(id, State.LocalMessageDistance) then
			local localLabel = getLocalChannelDisplayLabel(id)
			addEnvelopeToChat({
				channel = 'local',
				label = localLabel,
				color = color,
				args = {'[' .. localLabel .. '] ' .. name, message},
				metadata = {
					type = 'chat',
					source = id,
					license = license
				}
			})
		end
	end)

	AddEventHandler('poodlechat:action', function(id, license, name, message)
		if isMutedLicense(license) then
			return
		end

		if Client.isInProximity(id, State.ActionMessageDistance) then
			addEnvelopeToChat({
				channel = 'local',
				label = 'ME',
				color = State.ActionMessageColor,
				args = {'* ' .. name, message},
				metadata = {
					type = 'action',
					source = id,
					license = license
				}
			})
		end
	end)

	AddEventHandler('poodlechat:whisperEcho', function(id, license, name, message)
		if isMutedLicense(license) then
			sendMutedError(name)
			return
		end

		addEnvelopeToChat({
			channel = 'whispers',
			label = getChannel('whispers') and getChannel('whispers').label or 'Whispers',
			color = State.WhisperEchoColor,
			args = {'[DM -> ' .. name .. ']', message},
			metadata = {
				type = 'whisper',
				direction = 'out',
				conversationId = tostring(license or ('id:' .. tostring(id))),
				peerId = id,
				peerName = name,
				license = license,
				source = GetPlayerServerId(PlayerId())
			}
		})
	end)

	AddEventHandler('poodlechat:whisper', function(id, license, name, message)
		if isMutedLicense(license) then
			return
		end

		addEnvelopeToChat({
			channel = 'whispers',
			label = getChannel('whispers') and getChannel('whispers').label or 'Whispers',
			color = State.WhisperColor,
			args = {'[DM] ' .. name, message},
			metadata = {
				type = 'whisper',
				direction = 'in',
				conversationId = tostring(license or ('id:' .. tostring(id))),
				peerId = id,
				peerName = name,
				license = license,
				source = id
			}
		})
	end)

	AddEventHandler('poodlechat:whisperError', function(id)
		sendSimpleError('No user with ID or name ' .. tostring(id))
	end)

	AddEventHandler('poodlechat:whisperTargets', function(targets)
		Client.sendNuiMessage({
			type = 'setWhisperTargets',
			targets = type(targets) == 'table' and targets or {}
		})
	end)

	AddEventHandler('poodlechat:setReplyTo', function(id)
		State.ReplyTo = tostring(id)
	end)

	AddEventHandler('poodlechat:staffMessage', function(id, name, color, message)
		addEnvelopeToChat({
			channel = 'staff',
			label = getChannel('staff') and getChannel('staff').label or 'Staff',
			color = color,
			args = {'[' .. (getChannel('staff') and getChannel('staff').label or 'Staff') .. '] ' .. name, message},
			metadata = {
				type = 'chat',
				source = id
			}
		})
	end)

	AddEventHandler('poodlechat:setPermissions', function(permissions)
		if type(permissions) ~= 'table' then
			permissions = {}
		end

		if type(permissions.channels) ~= 'table' then
			permissions.channels = {}
		end

		State.Permissions = permissions
		if not Client.canAccessChannel(State.Channel) then
			State.Channel = constants.defaultChannelId
			setChannel(State.Channel)
		end
		Client.sendFeatureState()

		Client.sendNuiMessage({
			type = 'setPermissions',
			permissions = permissions,
			channels = getAllowedChannelsPayload(),
			activeChannel = State.Channel
		})
	end)

	AddEventHandler('poodlechat:mute', function(id, license)
		local player = GetPlayerFromServerId(id)
		local name = player ~= -1 and GetPlayerName(player) or tostring(id)

		State.MutedPlayers[license] = name
		sendChannelMessage({
			channel = constants.defaultChannelId,
			label = 'System',
			color = {255, 255, 128},
			args = {'System', name .. ' was muted'}
		})
		Client.encodeAndStore('mutedPlayers', State.MutedPlayers)
	end)

	AddEventHandler('poodlechat:unmute', function(id, license)
		local player = GetPlayerFromServerId(id)
		local name = player ~= -1 and GetPlayerName(player) or tostring(id)

		State.MutedPlayers[license] = nil
		sendChannelMessage({
			channel = constants.defaultChannelId,
			label = 'System',
			color = {255, 255, 128},
			args = {'System', name .. ' was unmuted'}
		})
		Client.encodeAndStore('mutedPlayers', State.MutedPlayers)
	end)

	AddEventHandler('poodlechat:showMuted', function(mutedPlayerIds)
		local muted = {}
		if type(mutedPlayerIds) ~= 'table' then
			mutedPlayerIds = {}
		end

		table.sort(mutedPlayerIds)

		for _, id in ipairs(mutedPlayerIds) do
			local player = GetPlayerFromServerId(id)
			local name = player ~= -1 and GetPlayerName(player) or tostring(id)
			muted[#muted + 1] = string.format('%s [%d]', name, id)
		end

		if #muted == 0 then
			sendChannelMessage({
				channel = constants.defaultChannelId,
				label = 'System',
				color = {255, 255, 128},
				args = {'System', 'No players are muted'}
			})
		else
			sendChannelMessage({
				channel = constants.defaultChannelId,
				label = 'Muted',
				color = {255, 255, 128},
				args = {'Muted', table.concat(muted, ', ')}
			})
		end
	end)

	exports('AddChannelMessage', function(payload)
		local normalized = normalizeMessagePayload(payload or {})
		addEnvelopeToChat(normalized)
		return true, normalized.channel
	end)

	exports('SetChannel', function(channelId)
		local resolved = resolveChannelWithFallback(channelId)
		setChannel(resolved)
		return true, resolved
	end)

	handlersRegistered = true
end

Client.isMutedLicense = isMutedLicense
Client.normalizeMessagePayload = normalizeMessagePayload
Client.sendChannelMessage = sendChannelMessage
Client.sendSuggestionBatch = sendSuggestionBatch
Client.SetChannel = setChannel
Client.CycleChannel = cycleChannel
Client.LoadSavedSettings = loadSavedSettings
Client.registerStartupSuggestions = registerStartupSuggestions
Client.refreshCommands = refreshCommands
Client.refreshThemes = refreshThemes
Client.buildOnLoadPayload = buildOnLoadPayload
Client.setTabGrouping = setTabGrouping
Client.setTabNotificationToggle = setTabNotificationToggle
Client.getTabNotificationToggles = getTabNotificationToggles
Client.registerChatHandlers = registerChatHandlers
