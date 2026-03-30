PoodleChatClient = PoodleChatClient or {}

local Client = PoodleChatClient
local bootstrapInitialized = false

Client.netEvents = {
	'chatMessage',
	'chat:addTemplate',
	'chat:addMessage',
	'chat:addSuggestion',
	'chat:addSuggestions',
	'chat:removeSuggestion',
	'chat:clear',
	'__cfx_internal:serverPrint',
	'_chat:messageEntered',
	'poodlechat:globalMessage',
	'poodlechat:localMessage',
	'poodlechat:action',
	'poodlechat:whisperEcho',
	'poodlechat:whisper',
	'poodlechat:whisperError',
	'poodlechat:setReplyTo',
	'poodlechat:staffMessage',
	'poodlechat:setPermissions',
	'poodlechat:mute',
	'poodlechat:unmute',
	'poodlechat:showMuted',
	'poodlechat:typingState',
	'poodlechat:bubbleMessage'
}

local function decodeJson(value)
	if not value then
		return nil
	end

	local ok, result = pcall(json.decode, value)

	if ok then
		return result
	end

	return nil
end

local function encodeAndStore(key, value)
	SetResourceKvp(key, json.encode(value))
end

local function addChatMessage(color, ...)
	TriggerEvent('chat:addMessage', {
		color = color,
		args = {...}
	})
end

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function hexColorToRgb(value, fallback)
	if type(value) ~= 'string' then
		return fallback
	end

	local normalized = value:lower()
	local rHex, gHex, bHex = normalized:match('^#(%x%x)(%x%x)(%x%x)$')
	if not rHex or not gHex or not bHex then
		return fallback
	end

	local r = tonumber(rHex, 16)
	local g = tonumber(gHex, 16)
	local b = tonumber(bHex, 16)

	if not r or not g or not b then
		return fallback
	end

	return {r, g, b}
end

local function getOffset(value, fallback)
	if type(value) == 'vector3' then
		return value
	end

	if type(value) == 'table' and value.x and value.y and value.z then
		return vector3(value.x, value.y, value.z)
	end

	return fallback
end

local function sendNuiMessage(payload)
	SendNUIMessage(payload)
end

local function isInProximity(id, distance)
	local myId = PlayerId()
	local target = GetPlayerFromServerId(id)

	if target == -1 then
		return false
	end

	if target == myId then
		return true
	end

	local myPed = GetPlayerPed(myId)
	local ped = GetPlayerPed(target)

	if ped == 0 then
		return false
	end

	local myCoords = GetEntityCoords(myPed)
	local coords = GetEntityCoords(ped)

	return #(myCoords - coords) <= distance
end

local function setupBootstrap()
	if bootstrapInitialized then
		return
	end

	local chatConfig = Config.Chat or {}
	local uiConfig = Config.UI or {}
	local emojiConfig = Config.Emoji or {}
	local typingConfig = Config.TypingIndicator or {}
	local bubbleConfig = Config.ChatBubbles or {}
	local distanceConfig = Config.Distance or {}
	local distanceUiConfig = type(distanceConfig.ui) == 'table' and distanceConfig.ui or {}
	local runtimeConfig = Config.Runtime or {}
	local clientRuntime = type(runtimeConfig.client) == 'table' and runtimeConfig.client or {}

	Client.config = {
		chat = chatConfig,
		ui = uiConfig,
		emoji = emojiConfig,
		typing = typingConfig,
		bubble = bubbleConfig,
		distance = distanceConfig,
		distanceUi = distanceUiConfig,
		runtime = clientRuntime
	}

	Client.constants = {
		channelIdByName = {
			Local = 'channel-local',
			Global = 'channel-global',
			Staff = 'channel-staff'
		},
		channelNameById = {
			['channel-local'] = 'Local',
			['channel-global'] = 'Global',
			['channel-staff'] = 'Staff'
		},
		chatOpenControl = tonumber(clientRuntime.chatOpenControl) or 245,
		suggestionBatchSize = math.max(1, tonumber(clientRuntime.suggestionBatchSize) or 200),
		mainLoopIdleMs = math.max(0, tonumber(clientRuntime.mainLoopIdleMs) or 0),
		overheadIdleMs = math.max(1, tonumber(clientRuntime.overheadIdleMs) or 250),
		resourceRefreshDelayMs = math.max(0, tonumber(clientRuntime.resourceRefreshDelayMs) or 500),
		pmaStartDelayMs = math.max(0, tonumber(clientRuntime.pmaStartDelayMs) or 300)
	}

	Client.state = {
		chatInputActive = false,
		chatInputActivating = false,
		chatHidden = true,
		chatLoaded = false,
		Channel = 'Local',
		HideChat = false,
		MutedPlayers = {},
		EmojiUsage = {},
		EmojiRecent = {},
		DisplayMessagesAbovePlayers = uiConfig.displayOverheadByDefault == true,
		OverheadMessages = {},
		OverheadUpdateIntervalMs = math.max(1, tonumber(uiConfig.overheadUpdateMs) or 50),
		EmojiRecentLimit = math.max(1, tonumber(emojiConfig.recentLimit) or 10),
		EmojiTopLimit = math.max(1, tonumber(emojiConfig.topLimit) or 10),
		ReplyTo = nil,
		Permissions = {
			canAccessStaffChannel = false
		},
		typingSystemEnabled = typingConfig.enabled == true,
		typingToggleAllowed = typingConfig.enabled == true and typingConfig.allowPlayerToggle == true,
		typingDisplayEnabled = typingConfig.enabled == true,
		localTypingActive = false,
		localTypingLastSent = 0,
		typingRemoteStates = {},
		bubbleSystemEnabled = bubbleConfig.enabled == true,
		bubbleToggleAllowed = bubbleConfig.enabled == true and bubbleConfig.allowPlayerToggle == true,
		bubbleDisplayEnabled = bubbleConfig.enabled == true,
		distanceEnabled = type(distanceConfig) == 'table' and distanceConfig.enabled == true,
		distanceExpressionCache = {},
		distanceObservedRanges = {},
		distanceModeCount = nil,
		distanceLastPayload = nil,
		distanceState = {
			enabled = false,
			value = tonumber(distanceConfig.default) or 10.0,
			label = tostring(tonumber(distanceConfig.default) or 10.0),
			color = '#95a5a6',
			percent = 0,
			modeIndex = nil,
			modeCount = nil,
			ranges = {}
		},
		emojiAliasesByGlyph = {},
		emojiEntries = {},
		sortedEmojiCache = nil,
		sortedEmojiDirty = true,
		emojiDataset = {
			categories = {}
		}
	}

	local state = Client.state
	state.ActionMessageColor = chatConfig.actionColor or {200, 0, 255}
	state.LocalMessageColor = chatConfig.localColor or {0, 153, 204}
	state.GlobalMessageColor = chatConfig.globalColor or {212, 175, 55}
	state.StaffMessageColor = chatConfig.staffColor or {255, 64, 0}
	state.WhisperColor = chatConfig.whisperColor or {254, 127, 156}
	state.WhisperEchoColor = chatConfig.whisperEchoColor or {204, 77, 106}
	state.ActionMessageDistance = tonumber(chatConfig.actionDistance) or 50.0
	state.LocalMessageDistance = tonumber(chatConfig.localDistance) or 50.0

	IsInProximity = isInProximity
	bootstrapInitialized = true
end

Client.setupBootstrap = setupBootstrap
Client.decodeJson = decodeJson
Client.encodeAndStore = encodeAndStore
Client.addChatMessage = addChatMessage
Client.clamp = clamp
Client.hexColorToRgb = hexColorToRgb
Client.getOffset = getOffset
Client.sendNuiMessage = sendNuiMessage
Client.isInProximity = isInProximity

