local Client = PoodleChatClient
local handlersRegistered = false
local asyncResponse = {}
local managerRequestCounter = 0
local managerRequests = {}

local function ensureContext()
	local state = Client and Client.state or nil
	local constants = Client and Client.constants or nil

	if not state or not constants then
		return nil, nil
	end

	return state, constants
end

local function isRuntimeConsoleErrorLine(value)
	local line = tostring(value or ''):upper()
	if line == '' then
		return false
	end

	local hasLuaTrace = string.find(line, '.LUA:', 1, true) ~= nil and line:sub(1, 1) == '@'

	return string.find(line, 'SCRIPT ERROR', 1, true) ~= nil
		or string.find(line, 'STACK TRACEBACK', 1, true) ~= nil
		or string.find(line, 'CITIZEN:/SCRIPTING/', 1, true) ~= nil
		or hasLuaTrace
end

local function ensurePendingUiMessages(state)
	if type(state.PendingUiMessages) ~= 'table' then
		state.PendingUiMessages = {}
	end

	return state.PendingUiMessages
end

local function flushPendingUiMessages(state)
	if not state or state.chatLoaded ~= true then
		return
	end

	local pending = ensurePendingUiMessages(state)
	if #pending == 0 then
		return
	end

	state.PendingUiMessages = {}
	for i = 1, #pending do
		Client.sendNuiMessage({
			type = 'ON_MESSAGE',
			message = pending[i]
		})
	end
end

local function queueOrSendHistoryPayload(payloadType, messages)
	local state = Client and Client.state or nil
	local payload = {
		type = payloadType,
		messages = type(messages) == 'table' and messages or {}
	}

	if state and state.chatLoaded ~= true then
		state.PendingHistoryPayload = payload
		return
	end

	Client.sendNuiMessage(payload)
end

local function flushPendingHistoryPayload(state)
	if not state or state.chatLoaded ~= true then
		return
	end

	local payload = type(state.PendingHistoryPayload) == 'table' and state.PendingHistoryPayload or nil
	if not payload then
		return
	end

	state.PendingHistoryPayload = nil
	Client.sendNuiMessage(payload)
end

local function forwardMessageToNui(raw)
	local normalized = Client.normalizeMessagePayload(raw)
	local state = Client and Client.state or nil
	if state and state.chatLoaded ~= true then
		local pending = ensurePendingUiMessages(state)
		pending[#pending + 1] = normalized
		return
	end

	Client.sendNuiMessage({
		type = 'ON_MESSAGE',
		message = normalized
	})
end

local function addSuggestionToNui(name, help, params)
	Client.sendNuiMessage({
		type = 'ON_SUGGESTION_ADD',
		suggestion = {
			name = name,
			help = help,
			params = params or nil
		}
	})
end

local function addSuggestionsToNui(suggestions)
	if type(suggestions) ~= 'table' or #suggestions == 0 then
		return
	end

	Client.sendSuggestionBatch(suggestions)
end

local function removeSuggestionFromNui(name)
	Client.sendNuiMessage({
		type = 'ON_SUGGESTION_REMOVE',
		name = name
	})
end

local function registerNuiCallbackSafe(name, fallbackResponse, handler)
	RegisterNUICallback(name, function(data, cb)
		local responded = false

		local function safeRespond(payload)
			if responded then
				return
			end
			responded = true
			pcall(cb, payload)
		end

		local ok, result = pcall(handler, data, safeRespond)
		if not ok then
			safeRespond(fallbackResponse)
			return
		end

		if responded then
			return
		end

		if result == asyncResponse then
			return
		end

		if result == nil then
			safeRespond(fallbackResponse)
			return
		end

		safeRespond(result)
	end)
end

local function requestManager(action, payload, safeRespond)
	managerRequestCounter = managerRequestCounter + 1
	local requestId = ('mgr:%d:%d'):format(GetGameTimer(), managerRequestCounter)
	managerRequests[requestId] = safeRespond
	TriggerServerEvent('poodlechat:manager:request', requestId, action, payload or {})
	Citizen.SetTimeout(8000, function()
		local responder = managerRequests[requestId]
		if responder then
			managerRequests[requestId] = nil
			responder({ok = false, reason = 'timeout'})
		end
	end)
	return asyncResponse
end

local function getLocalPlayerSettings(state)
	return {
		opacity = tonumber(GetResourceKvpString('poodlechat:uiOpacity')) or 88,
		soundEnabled = state.whisperSoundEnabled == true,
		soundVolume = tonumber(GetResourceKvpString('poodlechat:soundVolume:v1')) or 0.65,
		bubbles = state.bubbleDisplayEnabled == true,
		typing = state.typingDisplayEnabled == true,
		overhead = state.DisplayMessagesAbovePlayers == true,
		autoScroll = state.autoScrollEnabled == true,
		fontFamily = tostring(GetResourceKvpString('poodlechat:fontFamily:v1') or 'inter'),
		fontScale = tonumber(GetResourceKvpString('poodlechat:fontScale:v1')) or 1.0,
		tabGrouping = state.TabGrouping,
		tabOrder = state.TabGroupOrder,
		groupNames = state.TabGroupNames or {},
		groupDisplayMode = state.TabGroupDisplayMode or {},
		hiddenTabs = state.HiddenTabButtons,
		hideDeletedMessages = GetResourceKvpString('poodlechat:hideDeletedMessages:v1') == 'true',
		tabNotifications = state.TabNotificationToggles
	}
end

local function getCommandPolicyDecision(state, commandName)
	local policy = type(state.CommandPolicy) == 'table' and state.CommandPolicy or {}
	local blocks = type(policy.blocks) == 'table' and policy.blocks or {}
	local normalized = Client.normalizeKey(commandName)
	if not normalized then
		return nil
	end

	local entry = type(blocks[normalized]) == 'table' and blocks[normalized] or nil
	if not entry or entry.enabled == false then
		return nil
	end

	local mode = Client.normalizeKey(entry.mode) or 'block'
	if mode == 'hide' or mode == 'hide_suggestion' or mode == 'hidefromsuggestions' then
		return nil
	end
	if mode == 'staff' or mode == 'staffonly' then
		local permissions = type(state.Permissions) == 'table' and state.Permissions or {}
		local moderation = type(permissions.moderation) == 'table' and permissions.moderation or {}
		if permissions.staff == true or permissions.manager == true or permissions.canManagePoodleChat == true or moderation.canAccessStaff == true then
			return nil
		end
	end
	if mode == 'permission' or mode == 'permissionrequired' then
		local permissions = type(state.Permissions) == 'table' and state.Permissions or {}
		local capabilities = type(permissions.capabilities) == 'table' and permissions.capabilities or {}
		local permission = tostring(entry.permission or '')
		if permission ~= '' and capabilities[permission] == true then
			return nil
		end
	end

	return entry
end

local function registerNuiHandlers()
	if handlersRegistered then
		return
	end

	local state, constants = ensureContext()
	if not state or not constants then
		return
	end

	local function releaseChatNuiFocus(resetState)
		if resetState ~= false then
			state.chatInputActive = false
			state.chatInputActivating = false
		end

		SetNuiFocus(false, false)
		SetNuiFocusKeepInput(false)
		if SetCursorLocation then
			SetCursorLocation(0.5, 0.5)
		end

		Citizen.SetTimeout(100, function()
			SetNuiFocus(false, false)
			SetNuiFocusKeepInput(false)
		end)

		Client.setLocalTypingState(false, true)
	end

	local function acquireChatNuiFocus()
		SetNuiFocus(true, true)
		SetNuiFocusKeepInput(false)
	end

	local function openManagerNui()
		state.managerOpen = true
		SetNuiFocus(true, true)
		SetNuiFocusKeepInput(false)
		Client.sendNuiMessage({
			type = 'openManager'
		})
	end

	AddEventHandler('chatMessage', function(author, color, text)
		if isRuntimeConsoleErrorLine(author) or isRuntimeConsoleErrorLine(text) then
			return
		end

		local args = {text}

		if author ~= '' then
			table.insert(args, 1, author)
		end

		forwardMessageToNui({
			channel = constants.defaultChannelId,
			label = (constants.channelById[constants.defaultChannelId] and constants.channelById[constants.defaultChannelId].label) or 'Global',
			color = color,
			multiline = true,
			args = args
		})
	end)

	AddEventHandler('chat:addMessage', function(message)
		forwardMessageToNui(message)
	end)

	RegisterNetEvent('poodlechat:restoreHistory')
	AddEventHandler('poodlechat:restoreHistory', function(messages)
		if type(messages) ~= 'table' or #messages == 0 then
			return
		end
		queueOrSendHistoryPayload('restoreHistory', messages)
	end)

	RegisterNetEvent('poodlechat:characterSwitch')
	AddEventHandler('poodlechat:characterSwitch', function(messages)
		queueOrSendHistoryPayload('characterSwitch', messages)
	end)

	AddEventHandler('chat:addSuggestion', function(name, help, params)
		addSuggestionToNui(name, help, params)
	end)

	AddEventHandler('chat:addSuggestions', function(suggestions)
		addSuggestionsToNui(suggestions)
	end)

	AddEventHandler('chat:removeSuggestion', function(name)
		removeSuggestionFromNui(name)
	end)

	AddEventHandler('chat:addTemplate', function(id, html)
		Client.sendNuiMessage({
			type = 'ON_TEMPLATE_ADD',
			template = {
				id = id,
				html = html
			}
		})
	end)

	AddEventHandler('chat:clear', function()
		Client.sendNuiMessage({
			type = 'ON_CLEAR'
		})
	end)

	exports('addMessage', function(message)
		forwardMessageToNui(message)
		return true
	end)

	exports('addSuggestion', function(name, help, params)
		addSuggestionToNui(name, help, params)
		return true
	end)

	exports('addSuggestions', function(suggestions)
		addSuggestionsToNui(suggestions)
		return true
	end)

	exports('removeSuggestion', function(name)
		removeSuggestionFromNui(name)
		return true
	end)

	exports('clear', function()
		Client.sendNuiMessage({
			type = 'ON_CLEAR'
		})
		return true
	end)

	AddEventHandler('poodlechat:manager:response', function(requestId, payload)
		local id = tostring(requestId or '')
		local responder = managerRequests[id]
		if not responder then
			return
		end

		managerRequests[id] = nil
		local response = type(payload) == 'table' and payload or {ok = false, reason = 'invalid_response'}
		if type(response.commandPolicy) == 'table' then
			state.CommandPolicy = response.commandPolicy
		end
		if type(response.commandBlocks) == 'table' or type(response.commandRoutes) == 'table' or type(response.customCommands) == 'table' then
			state.CommandPolicy = state.CommandPolicy or {}
			if type(response.commandBlocks) == 'table' then
				state.CommandPolicy.blocks = response.commandBlocks.entries or response.commandBlocks
			end
			if type(response.commandRoutes) == 'table' then
				state.CommandPolicy.routes = response.commandRoutes.overrides or response.commandRoutes
			end
			if type(response.customCommands) == 'table' then
				state.CommandPolicy.customCommands = response.customCommands.entries or response.customCommands
			end
		end
		responder(response)
	end)

	registerNuiCallbackSafe('chatResult', 'ok', function(data)
		local payload = type(data) == 'table' and data or {}
		releaseChatNuiFocus(true)

		if not payload.canceled then
			local playerId = PlayerId()
			local r, g, b = 0, 0x99, 255
			local message = tostring(payload.message or '')
			local sourceChannelId = Client.normalizeKey(payload.channel) or state.Channel or constants.defaultChannelId

			if message == '' then
				return 'ok'
			end

			local replyTo = type(payload.replyTo) == 'table' and payload.replyTo or nil
			local whisperTarget = type(payload.whisperTarget) == 'table' and payload.whisperTarget or nil
			if whisperTarget and message:sub(1, 1) ~= '/' then
				local target = whisperTarget.peerCharacterId or whisperTarget.peerId
				if target then
					TriggerServerEvent('poodlechat:whisperMessage', target, message, {
						replyTo = replyTo
					})
					return 'ok'
				end
			end

			if message:sub(1, 1) == '/' then
				local rawCommand = message:sub(2)
				local commandName = rawCommand:match('^(%S+)')
				if commandName then
					local block = getCommandPolicyDecision(state, commandName)
					if block then
						local mode = Client.normalizeKey(block.mode) or 'block'
						if mode == 'redirect' and block.redirect then
							local redirectName = tostring(block.redirect):gsub('^/', '')
							rawCommand = redirectName .. rawCommand:gsub('^%S+', '')
							commandName = redirectName
						else
							forwardMessageToNui({
								channel = sourceChannelId,
								label = 'System',
								color = {255, 128, 128},
								args = {'System', tostring(block.message or 'That command is blocked in PoodleChat input.')},
								metadata = {
									type = 'system',
									subtype = 'commandBlock',
									command = commandName
								}
							})
							return 'ok'
						end
					end
					Client.setCommandContext(commandName)
				end
				ExecuteCommand(rawCommand)
			else
				if Client.canSendToChannel and not Client.canSendToChannel(sourceChannelId) then
					forwardMessageToNui({
						channel = sourceChannelId,
						label = 'System',
						color = {255, 128, 128},
						args = {'System', 'You cannot send messages in this channel.'}
					})
					return 'ok'
				end

				TriggerServerEvent('_chat:messageEntered', GetPlayerName(playerId), {r, g, b}, message, sourceChannelId, {
					replyTo = replyTo
				})
			end
		end

		return 'ok'
	end)

	registerNuiCallbackSafe('closeInput', 'ok', function()
		releaseChatNuiFocus(true)
		return 'ok'
	end)

	registerNuiCallbackSafe('typingState', {}, function(data)
		Client.setLocalTypingState(type(data) == 'table' and data.active == true, false)
		return {}
	end)

	registerNuiCallbackSafe('cycleDistance', {ok = false, state = state.distanceState}, function()
		local ok = Client.cycleDistance()
		return {ok = ok, state = state.distanceState}
	end)

	registerNuiCallbackSafe('toggleTypingDisplay', {active = state.typingDisplayEnabled}, function()
		local current = Client.toggleTypingDisplay()
		return {active = current}
	end)

	registerNuiCallbackSafe('toggleBubbleDisplay', {active = state.bubbleDisplayEnabled}, function()
		local current = Client.toggleBubbleDisplay()
		return {active = current}
	end)

	registerNuiCallbackSafe('toggleWhisperSound', {
		active = state.whisperSoundEnabled,
		allowToggle = state.whisperSoundToggleAllowed == true,
		mode = state.whisperSoundEnabled and 'on' or 'off',
		volume = tonumber(constants.whisperNotificationVolume) or 0.65
	}, function()
		Client.toggleWhisperSound()
		local feature = (Client.getFeatureStatePayload() or {}).whisperSound or {}
		return {
			active = feature.active == true,
			allowToggle = feature.allowToggle == true,
			mode = tostring(feature.mode or 'off'),
			volume = tonumber(constants.whisperNotificationVolume) or 0.65
		}
	end)

	registerNuiCallbackSafe('toggleAutoScroll', {active = state.autoScrollEnabled}, function()
		local current = Client.toggleAutoScroll()
		return {active = current}
	end)

	registerNuiCallbackSafe('playWhisperSound', {}, function(data)
		local payload = type(data) == 'table' and data or {}
		local channelId = payload.channelId
		if Client.playTabNotificationSound then
			Client.playTabNotificationSound(channelId)
		else
			Client.playWhisperSound()
		end
		return {}
	end)

	registerNuiCallbackSafe('setWaypoint', {ok = false}, function(data)
		local payload = type(data) == 'table' and data or {}
		local x = tonumber(payload.x)
		local y = tonumber(payload.y)
		if not x or not y then
			return {ok = false}
		end

		SetNewWaypoint(x + 0.0, y + 0.0)
		return {ok = true}
	end)

	registerNuiCallbackSafe('setTabGrouping', {grouping = {}}, function(data)
		local grouping = type(data) == 'table' and data.grouping or {}
		local order = type(data) == 'table' and data.order or {}
		local groupNames = type(data) == 'table' and data.groupNames or {}
		local groupDisplayMode = type(data) == 'table' and data.groupDisplayMode or {}
		local resolved = Client.setTabGrouping(grouping, order)
		if Client.setTabGroupSettings and type(data) == 'table' and (data.groupNames ~= nil or data.groupDisplayMode ~= nil) then
			local groupSettings = Client.setTabGroupSettings(groupNames, groupDisplayMode)
			resolved = {
				grouping = resolved.grouping or {},
				order = resolved.order or {},
				groupNames = groupSettings.groupNames or {},
				groupDisplayMode = groupSettings.groupDisplayMode or {}
			}
		end
		return {
			grouping = resolved.grouping or {},
			order = resolved.order or {},
			groupNames = resolved.groupNames or {},
			groupDisplayMode = resolved.groupDisplayMode or {},
			hidden = Client.getHiddenTabButtons(),
			activeChannel = Client.state and Client.state.Channel or nil
		}
	end)

	registerNuiCallbackSafe('setTabHidden', {channelId = '', hidden = false, hiddenTabs = {}}, function(data)
		local payload = type(data) == 'table' and data or {}
		local hidden = Client.setHiddenTabButton(payload.channelId, payload.hidden == true)
		return {
			channelId = payload.channelId,
			hiddenTabs = hidden,
			activeChannel = Client.state and Client.state.Channel or nil
		}
	end)

	registerNuiCallbackSafe('setTabNotificationToggle', {channelId = '', enabled = true, toggles = {}, feature = {}}, function(data)
		local payload = type(data) == 'table' and data or {}
		local channelId = payload.channelId
		local enabled = payload.enabled == true
		Client.setTabNotificationToggle(channelId, enabled)
		return {
			channelId = channelId,
			enabled = enabled,
			toggles = Client.getTabNotificationToggles(),
			feature = Client.getFeatureStatePayload()
		}
	end)

	registerNuiCallbackSafe('setOpacity', {ok = true}, function(data)
		local payload = type(data) == 'table' and data or {}
		local opacity = tonumber(payload.opacity)
		if opacity and opacity >= 70 and opacity <= 100 then
			SetResourceKvp('poodlechat:uiOpacity', tostring(math.floor(opacity)))
		end
		return {ok = true}
	end)

	registerNuiCallbackSafe('closeManager', {ok = true}, function(data)
		local payload = type(data) == 'table' and data or {}
		state.managerOpen = false
		if payload.returnToChat == true then
			state.chatInputActive = true
			state.chatInputActivating = false
			acquireChatNuiFocus()
			Client.setLocalTypingState(true, false)
		else
			releaseChatNuiFocus(false)
		end
		return {ok = true}
	end)

	registerNuiCallbackSafe('managerGetBootstrap', {ok = false}, function(data, safeRespond)
		return requestManager('managerGetBootstrap', data, function(response)
			if type(response) == 'table' and type(response.commandPolicy) == 'table' then
				state.CommandPolicy = response.commandPolicy
			end
			response.playerSettings = getLocalPlayerSettings(state)
			safeRespond(response)
		end)
	end)

	registerNuiCallbackSafe('managerUpdatePlayerSettings', {ok = true}, function(data)
		local payload = type(data) == 'table' and data or {}
		local settings = type(payload.settings) == 'table' and payload.settings or payload
		local opacity = tonumber(settings.opacity)
		if opacity and opacity >= 70 and opacity <= 100 then
			SetResourceKvp('poodlechat:uiOpacity', tostring(math.floor(opacity)))
		end
		if settings.soundEnabled ~= nil and Client.setWhisperSoundEnabled then
			Client.setWhisperSoundEnabled(settings.soundEnabled == true)
		end
		if settings.bubbles ~= nil and Client.setBubbleDisplayEnabled then
			Client.setBubbleDisplayEnabled(settings.bubbles == true)
		end
		if settings.typing ~= nil and Client.setTypingDisplayEnabled then
			Client.setTypingDisplayEnabled(settings.typing == true)
		end
		if settings.autoScroll ~= nil and Client.setAutoScrollEnabled then
			Client.setAutoScrollEnabled(settings.autoScroll == true)
		end
		if settings.overhead ~= nil then
			state.DisplayMessagesAbovePlayers = settings.overhead == true
			SetResourceKvp('displayMessagesAbovePlayers', state.DisplayMessagesAbovePlayers and 'true' or 'false')
		end
		if settings.hideDeletedMessages ~= nil then
			SetResourceKvp('poodlechat:hideDeletedMessages:v1', settings.hideDeletedMessages == true and 'true' or 'false')
		end
		if settings.fontFamily ~= nil then
			local fontFamily = tostring(settings.fontFamily or ''):gsub('[^%w_%-]', '')
			if fontFamily ~= '' then
				SetResourceKvp('poodlechat:fontFamily:v1', fontFamily)
			end
		end
		local fontScale = tonumber(settings.fontScale)
		if fontScale then
			SetResourceKvp('poodlechat:fontScale:v1', tostring(Client.clamp(fontScale, 0.5, 1.5)))
		end
		if type(settings.tabGrouping) == 'table' then
			Client.setTabGrouping(settings.tabGrouping, settings.tabOrder)
		end
		if Client.setTabGroupSettings and (type(settings.groupNames) == 'table' or type(settings.groupDisplayMode) == 'table') then
			Client.setTabGroupSettings(settings.groupNames, settings.groupDisplayMode)
		end
		local soundVolume = tonumber(settings.soundVolume)
		if soundVolume then
			SetResourceKvp('poodlechat:soundVolume:v1', tostring(Client.clamp(soundVolume, 0.0, 1.0)))
		end
		return {ok = true, playerSettings = getLocalPlayerSettings(state), feature = Client.getFeatureStatePayload()}
	end)

	local managerCallbacks = {
		'managerGetNicknameState',
		'managerSetNickname',
		'managerPinNickname'
	}
	for i = 1, #managerCallbacks do
		local callbackName = managerCallbacks[i]
		registerNuiCallbackSafe(callbackName, {ok = false}, function(data, safeRespond)
			return requestManager(callbackName, data, safeRespond)
		end)
	end

	registerNuiCallbackSafe('messageContextAction', {ok = true}, function(data)
		local payload = type(data) == 'table' and data or {}
		return {
			ok = true,
			action = tostring(payload.action or '')
		}
	end)

	registerNuiCallbackSafe('submitReport', {ok = false, reason = 'disabled'}, function(data)
		local payload = type(data) == 'table' and data or {}
		local permissions = type(state.Permissions) == 'table' and state.Permissions or {}
		local moderation = type(permissions.moderation) == 'table' and permissions.moderation or {}
		if moderation.builtInReportsEnabled ~= true then
			return {ok = false, reason = 'disabled'}
		end

		local targetId = tostring(payload.targetId or ''):gsub('^%s+', ''):gsub('%s+$', '')
		local reason = tostring(payload.reason or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if reason == '' then
			return {ok = false, reason = 'invalid'}
		end

		TriggerServerEvent(
			'poodlechat:report',
			targetId ~= '' and targetId or false,
			reason,
			type(payload.reportContext) == 'table' and payload.reportContext or nil,
			tostring(payload.sourceMessageId or '')
		)
		return {ok = true}
	end)

	registerNuiCallbackSafe('deleteConversation', {ok = true}, function(data)
		local payload = type(data) == 'table' and data or {}
		TriggerServerEvent('poodlechat:deleteConversation', payload.channelId, payload.conversationId)
		return {ok = true}
	end)

	registerNuiCallbackSafe('deleteMessage', {ok = false}, function(data)
		local payload = type(data) == 'table' and data or {}
		local messageId = tostring(payload.messageId or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if messageId == '' then
			return {ok = false}
		end

		TriggerServerEvent('poodlechat:deleteMessage', messageId)
		return {ok = true}
	end)

	registerNuiCallbackSafe('setChannel', {}, function(data)
		local requested = type(data) == 'table' and data.channelId or nil
		if requested then
			Client.SetChannel(requested)
		end
		return {}
	end)

	registerNuiCallbackSafe('radioSendMessage', {ok = false, reason = 'disabled', state = {}}, function(data)
		local payload = type(data) == 'table' and data or {}
		return Client.sendEmbeddedRadioMessage(payload.slot, payload.message, payload.frequency)
	end)

	registerNuiCallbackSafe('cycleChannel', {}, function()
		Client.CycleChannel()
		return {}
	end)

	registerNuiCallbackSafe('loaded', 'ok', function()
		state.chatLoaded = true
		TriggerServerEvent('chat:init')
		TriggerServerEvent('poodlechat:getPermissions')
		Client.refreshCommands()
		Client.refreshThemes()
		if Client.refreshEmbeddedRadioState and Client.getEmbeddedRadioPayload then
			Client.refreshEmbeddedRadioState()
			Client.sendNuiMessage({
				type = 'setRadioState',
				state = Client.getEmbeddedRadioPayload()
			})
			if Client.ensureEmbeddedRadioStateSynced then
				Client.ensureEmbeddedRadioStateSynced()
			end
		end
		if Client.refreshVoiceAvailability then
			Client.refreshVoiceAvailability(true)
		end
		Client.sendFeatureState()
		Client.refreshDistanceModeCount()
		flushPendingHistoryPayload(state)
		flushPendingUiMessages(state)
		return 'ok'
	end)

	registerNuiCallbackSafe('onLoad', {}, function()
		return Client.buildOnLoadPayload() or {}
	end)

	registerNuiCallbackSafe('getEmojiPanelData', {recent = {}, top = {}}, function()
		return Client.getEmojiPanelData() or {recent = {}, top = {}}
	end)

	registerNuiCallbackSafe('getWhisperTargets', {}, function()
		TriggerServerEvent('poodlechat:getWhisperTargets')
		return {}
	end)

	registerNuiCallbackSafe('resyncState', {ok = true}, function()
		TriggerServerEvent('poodlechat:getPermissions')
		Client.refreshCommands()
		Client.refreshThemes()
		Client.sendFeatureState()
		Client.refreshDistanceModeCount()
		if Client.refreshEmbeddedRadioState and Client.getEmbeddedRadioPayload then
			Client.refreshEmbeddedRadioState()
			Client.sendNuiMessage({
				type = 'setRadioState',
				state = Client.getEmbeddedRadioPayload()
			})
		end
		flushPendingHistoryPayload(state)
		flushPendingUiMessages(state)
		return {ok = true}
	end)

	registerNuiCallbackSafe('useEmoji', {panel = {recent = {}, top = {}}}, function(data)
		local payload = Client.handleEmojiUse(type(data) == 'table' and data.emoji or nil)
		if type(payload) ~= 'table' then
			return {panel = {recent = {}, top = {}}}
		end
		return payload
	end)

	AddEventHandler('onClientResourceStart', function(resName)
		if resName ~= GetCurrentResourceName() then
			return
		end

		SetTextChatEnabled(false)
		state.chatLoaded = false
		releaseChatNuiFocus(true)
		Wait(constants.resourceRefreshDelayMs)
		TriggerServerEvent('poodlechat:getPermissions')
		Client.refreshCommands()
		Client.refreshThemes()
	end)

	RegisterCommand('chatmanager', function()
		openManagerNui()
	end, false)

	AddEventHandler('onClientResourceStop', function(resName)
		Wait(constants.resourceRefreshDelayMs)
		Client.refreshCommands()
		Client.refreshThemes()

		if resName == GetCurrentResourceName() then
			releaseChatNuiFocus(true)
		end
	end)

	CreateThread(function()
		SetTextChatEnabled(false)
		releaseChatNuiFocus(true)
		TriggerServerEvent('poodlechat:getPermissions')

		pcall(Client.LoadSavedSettings)
		pcall(Client.parseEmojiDataset)

		Client.registerStartupSuggestions()

		pcall(Client.AddEmojiSuggestions)

		Client.sendFeatureState()
		Client.refreshDistanceState(true)

		while true do
			local waitMs = constants.mainLoopIdleMs

			if not state.chatInputActive then
				if IsControlPressed(0, constants.chatOpenControl) then
					state.chatInputActive = true
					state.chatInputActivating = true
					TriggerServerEvent('poodlechat:getPermissions')

					Client.sendNuiMessage({
						type = 'ON_OPEN'
					})

					waitMs = 0
				end
			elseif IsControlJustReleased(0, constants.chatOpenControl) then
				acquireChatNuiFocus()
				waitMs = 0
			end

			if state.chatInputActivating then
				if not IsControlPressed(0, constants.chatOpenControl) then
					acquireChatNuiFocus()
					state.chatInputActivating = false
				end
				waitMs = 0
			end

			if state.chatLoaded then
				local shouldBeHidden = IsScreenFadedOut()
					or IsPauseMenuActive()
					or (state.HideChat and not state.chatInputActive and not state.chatInputActivating)

				if (shouldBeHidden and not state.chatHidden) or (not shouldBeHidden and state.chatHidden) then
					state.chatHidden = shouldBeHidden

					Client.sendNuiMessage({
						type = 'ON_SCREEN_STATE_CHANGE',
						shouldHide = shouldBeHidden
					})

					if shouldBeHidden and (state.chatInputActive or state.chatInputActivating) then
						releaseChatNuiFocus(true)
					end
				end
			end

			if state.typingSystemEnabled and state.localTypingActive then
				Client.setLocalTypingState(true, false)
				waitMs = 0
			end

			Wait(waitMs)
		end
	end)

	handlersRegistered = true
end

Client.registerNuiHandlers = registerNuiHandlers
