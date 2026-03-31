local Client = PoodleChatClient
local handlersRegistered = false

local function ensureContext()
	local state = Client and Client.state or nil
	local constants = Client and Client.constants or nil

	if not state or not constants then
		return nil, nil
	end

	return state, constants
end

local function forwardMessageToNui(raw)
	local normalized = Client.normalizeMessagePayload(raw)
	Client.sendNuiMessage({
		type = 'ON_MESSAGE',
		message = normalized
	})
end

local function registerNuiHandlers()
	if handlersRegistered then
		return
	end

	local state, constants = ensureContext()
	if not state or not constants then
		return
	end

	AddEventHandler('chatMessage', function(author, color, text)
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

	AddEventHandler('__cfx_internal:serverPrint', function(msg)
		print(msg)

		forwardMessageToNui({
			channel = constants.defaultChannelId,
			label = 'Print',
			templateId = 'print',
			multiline = true,
			args = {msg}
		})
	end)

	AddEventHandler('chat:addMessage', function(message)
		forwardMessageToNui(message)
	end)

	AddEventHandler('chat:addSuggestion', function(name, help, params)
		Client.sendNuiMessage({
			type = 'ON_SUGGESTION_ADD',
			suggestion = {
				name = name,
				help = help,
				params = params or nil
			}
		})
	end)

	AddEventHandler('chat:addSuggestions', function(suggestions)
		if type(suggestions) ~= 'table' or #suggestions == 0 then
			return
		end

		Client.sendSuggestionBatch(suggestions)
	end)

	AddEventHandler('chat:removeSuggestion', function(name)
		Client.sendNuiMessage({
			type = 'ON_SUGGESTION_REMOVE',
			name = name
		})
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

	RegisterNUICallback('chatResult', function(data, cb)
		state.chatInputActive = false
		SetNuiFocus(false, false)
		Client.setLocalTypingState(false, true)

		if not data.canceled then
			local playerId = PlayerId()
			local r, g, b = 0, 0x99, 255

			if data.message:sub(1, 1) == '/' then
				local rawCommand = data.message:sub(2)
				local commandName = rawCommand:match('^(%S+)')
				if commandName then
					Client.setCommandContext(commandName)
				end
				ExecuteCommand(rawCommand)
			else
				TriggerServerEvent('_chat:messageEntered', GetPlayerName(playerId), {r, g, b}, data.message, state.Channel)
			end
		end

		cb('ok')
	end)

	RegisterNUICallback('typingState', function(data, cb)
		Client.setLocalTypingState(type(data) == 'table' and data.active == true, false)
		cb({})
	end)

	RegisterNUICallback('cycleDistance', function(_, cb)
		local ok = Client.cycleDistance()
		cb({ok = ok, state = state.distanceState})
	end)

	RegisterNUICallback('toggleTypingDisplay', function(_, cb)
		local current = Client.toggleTypingDisplay()
		cb({active = current})
	end)

	RegisterNUICallback('toggleBubbleDisplay', function(_, cb)
		local current = Client.toggleBubbleDisplay()
		cb({active = current})
	end)

	RegisterNUICallback('toggleWhisperSound', function(_, cb)
		local current = Client.toggleWhisperSound()
		cb({
			active = current,
			volume = tonumber(constants.whisperNotificationVolume) or 0.65
		})
	end)

	RegisterNUICallback('toggleAutoScroll', function(_, cb)
		local current = Client.toggleAutoScroll()
		cb({active = current})
	end)

	RegisterNUICallback('playWhisperSound', function(_, cb)
		Client.playWhisperSound()
		cb({})
	end)

	RegisterNUICallback('setChannel', function(data, cb)
		local requested = type(data) == 'table' and data.channelId or nil
		if requested then
			Client.SetChannel(requested)
		end
		cb({})
	end)

	RegisterNUICallback('cycleChannel', function(_, cb)
		Client.CycleChannel()
		cb({})
	end)

	RegisterNUICallback('loaded', function(_, cb)
		TriggerServerEvent('chat:init')
		TriggerServerEvent('poodlechat:getPermissions')
		Client.refreshCommands()
		Client.refreshThemes()
		state.chatLoaded = true
		Client.sendFeatureState()
		Client.refreshDistanceState(true)
		Client.refreshDistanceModeCount()
		cb('ok')
	end)

	RegisterNUICallback('onLoad', function(_, cb)
		cb(Client.buildOnLoadPayload())
	end)

	RegisterNUICallback('getEmojiPanelData', function(_, cb)
		cb(Client.getEmojiPanelData())
	end)

	RegisterNUICallback('getWhisperTargets', function(_, cb)
		TriggerServerEvent('poodlechat:getWhisperTargets')
		cb({})
	end)

	RegisterNUICallback('useEmoji', function(data, cb)
		local payload = Client.handleEmojiUse(type(data) == 'table' and data.emoji or nil)
		cb(payload)
	end)

	AddEventHandler('onClientResourceStart', function(resName)
		if resName ~= GetCurrentResourceName() then
			return
		end

		SetTextChatEnabled(false)
		SetNuiFocus(false, false)
		Wait(constants.resourceRefreshDelayMs)
		Client.refreshCommands()
		Client.refreshThemes()
	end)

	AddEventHandler('onClientResourceStart', function(resName)
		if resName ~= 'pma-voice' then
			return
		end

		if not state.distanceEnabled then
			return
		end

		Wait(constants.pmaStartDelayMs)
		Client.refreshDistanceModeCount()
		Client.refreshDistanceState(true)
	end)

	AddEventHandler('onClientResourceStop', function(resName)
		Wait(constants.resourceRefreshDelayMs)
		Client.refreshCommands()
		Client.refreshThemes()

		if resName == GetCurrentResourceName() then
			Client.setLocalTypingState(false, true)
		end
	end)

	CreateThread(function()
		SetTextChatEnabled(false)
		SetNuiFocus(false, false)
		TriggerServerEvent('poodlechat:getPermissions')

		local okLoadSaved, loadSavedError = pcall(Client.LoadSavedSettings)
		if not okLoadSaved then
			print(('[poodlechat] Failed to load saved settings: %s'):format(tostring(loadSavedError)))
		end

		local okParseEmojiDataset, parseEmojiDatasetError = pcall(Client.parseEmojiDataset)
		if not okParseEmojiDataset then
			print(('[poodlechat] Failed to parse emoji dataset: %s'):format(tostring(parseEmojiDatasetError)))
		end

		Client.registerStartupSuggestions()

		local okEmojiSuggestions, emojiSuggestionsError = pcall(Client.AddEmojiSuggestions)
		if not okEmojiSuggestions then
			print(('[poodlechat] Failed to register emoji suggestions: %s'):format(tostring(emojiSuggestionsError)))
		end

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
				SetNuiFocus(true, true)
				waitMs = 0
			end

			if state.chatInputActivating then
				if not IsControlPressed(0, constants.chatOpenControl) then
					SetNuiFocus(true, true)
					state.chatInputActivating = false
				end
				waitMs = 0
			end

			if state.chatLoaded then
				local shouldBeHidden = IsScreenFadedOut() or IsPauseMenuActive() or state.HideChat

				if (shouldBeHidden and not state.chatHidden) or (not shouldBeHidden and state.chatHidden) then
					state.chatHidden = shouldBeHidden

					Client.sendNuiMessage({
						type = 'ON_SCREEN_STATE_CHANGE',
						shouldHide = shouldBeHidden
					})
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
