local Client = PoodleChatClient
local State = Client.state
local constants = Client.constants

AddEventHandler('chatMessage', function(author, color, text)
	local args = {text}

	if author ~= '' then
		table.insert(args, 1, author)
	end

	Client.sendNuiMessage({
		type = 'ON_MESSAGE',
		message = {
			color = color,
			multiline = true,
			args = args
		}
	})
end)

AddEventHandler('__cfx_internal:serverPrint', function(msg)
	print(msg)

	Client.sendNuiMessage({
		type = 'ON_MESSAGE',
		message = {
			templateId = 'print',
			multiline = true,
			args = {msg}
		}
	})
end)

AddEventHandler('chat:addMessage', function(message)
	Client.sendNuiMessage({
		type = 'ON_MESSAGE',
		message = message
	})
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
	State.chatInputActive = false
	SetNuiFocus(false, false)
	Client.setLocalTypingState(false, true)

	if not data.canceled then
		local playerId = PlayerId()
		local r, g, b = 0, 0x99, 255

		if data.message:sub(1, 1) == '/' then
			ExecuteCommand(data.message:sub(2))
		else
			TriggerServerEvent('_chat:messageEntered', GetPlayerName(playerId), {r, g, b}, data.message, State.Channel)
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
	cb({ok = ok, state = State.distanceState})
end)

RegisterNUICallback('toggleTypingDisplay', function(_, cb)
	local current = Client.toggleTypingDisplay()
	cb({active = current})
end)

RegisterNUICallback('toggleBubbleDisplay', function(_, cb)
	local current = Client.toggleBubbleDisplay()
	cb({active = current})
end)

RegisterNUICallback('setChannel', function(data, cb)
	local name = type(data) == 'table' and constants.channelNameById[data.channelId] or nil
	if name then
		SetChannel(name)
	end
	cb({})
end)

RegisterNUICallback('cycleChannel', function(_, cb)
	CycleChannel()
	cb({})
end)

RegisterNUICallback('loaded', function(_, cb)
	TriggerServerEvent('chat:init')
	Client.refreshCommands()
	Client.refreshThemes()
	State.chatLoaded = true
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

	if not State.distanceEnabled then
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

	local okLoadSaved, loadSavedError = pcall(LoadSavedSettings)
	if not okLoadSaved then
		print(('[poodlechat] Failed to load saved settings: %s'):format(tostring(loadSavedError)))
	end

	local okParseEmojiDataset, parseEmojiDatasetError = pcall(Client.parseEmojiDataset)
	if not okParseEmojiDataset then
		print(('[poodlechat] Failed to parse emoji dataset: %s'):format(tostring(parseEmojiDatasetError)))
	end

	Client.registerStartupSuggestions()

	local okEmojiSuggestions, emojiSuggestionsError = pcall(AddEmojiSuggestions)
	if not okEmojiSuggestions then
		print(('[poodlechat] Failed to register emoji suggestions: %s'):format(tostring(emojiSuggestionsError)))
	end

	Client.sendFeatureState()
	Client.refreshDistanceState(true)

	while true do
		local waitMs = constants.mainLoopIdleMs

		if not State.chatInputActive then
			if IsControlPressed(0, constants.chatOpenControl) then
				State.chatInputActive = true
				State.chatInputActivating = true

				Client.sendNuiMessage({
					type = 'ON_OPEN'
				})

				waitMs = 0
			end
		elseif IsControlJustReleased(0, constants.chatOpenControl) then
			SetNuiFocus(true, true)
			waitMs = 0
		end

		if State.chatInputActivating then
			if not IsControlPressed(0, constants.chatOpenControl) then
				SetNuiFocus(true, true)
				State.chatInputActivating = false
			end
			waitMs = 0
		end

		if State.chatLoaded then
			local shouldBeHidden = IsScreenFadedOut() or IsPauseMenuActive() or State.HideChat

			if (shouldBeHidden and not State.chatHidden) or (not shouldBeHidden and State.chatHidden) then
				State.chatHidden = shouldBeHidden

				Client.sendNuiMessage({
					type = 'ON_SCREEN_STATE_CHANGE',
					shouldHide = shouldBeHidden
				})
			end
		end

		if State.typingSystemEnabled and State.localTypingActive then
			Client.setLocalTypingState(true, false)
			waitMs = 0
		end

		Wait(waitMs)
	end
end)

