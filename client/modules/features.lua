local Client = PoodleChatClient
local State = Client.state
local config = Client.config
local constants = Client.constants

local uiConfig = config.ui
local typingConfig = config.typing
local bubbleConfig = config.bubble
local distanceConfig = config.distance
local distanceUiConfig = config.distanceUi

local function getTypingUpdateRate()
	return math.max(50, tonumber(typingConfig.updateRate) or 200)
end

local function getLocalProximityState()
	if type(LocalPlayer) ~= 'table' then
		return nil
	end

	local playerState = LocalPlayer.state
	if type(playerState) ~= 'table' then
		return nil
	end

	local proximity = playerState.proximity
	if type(proximity) ~= 'table' then
		return nil
	end

	return proximity
end

local function normalizeHexColor(value, fallback)
	if type(value) ~= 'string' then
		return fallback
	end

	local normalized = value:gsub('%s+', '')

	if normalized:match('^#%x%x%x%x%x%x$') then
		return normalized:lower()
	end

	if normalized:match('^%x%x%x%x%x%x$') then
		return ('#' .. normalized):lower()
	end

	if normalized:match('^#%x%x%x%x%x%x%x%x$') then
		return ('#' .. normalized:sub(4, 9)):lower()
	end

	if normalized:match('^%x%x%x%x%x%x%x%x$') then
		return ('#' .. normalized:sub(3, 8)):lower()
	end

	return fallback
end

local function dedupeAndSortRanges(ranges)
	local set = {}
	local list = {}

	for _, value in ipairs(ranges) do
		local num = tonumber(value)
		if num and num > 0 then
			num = tonumber(string.format('%.3f', num))
			if not set[num] then
				set[num] = true
				list[#list + 1] = num
			end
		end
	end

	table.sort(list)

	return list
end

local function createDistanceExpressionExecutor(cacheKey, sourceCode, withRange)
	if type(sourceCode) ~= 'string' or sourceCode == '' then
		return nil
	end

	local key = cacheKey .. '\0' .. sourceCode
	local cached = State.distanceExpressionCache[key]

	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached
	end

	local wrapper

	if withRange then
		wrapper = 'return function(range) ' .. sourceCode .. ' end'
	else
		if sourceCode:match('^%s*return%s+') then
			wrapper = 'return function() ' .. sourceCode .. ' end'
		else
			wrapper = 'return function() return ' .. sourceCode .. ' end'
		end
	end

	local chunk, loadErr = load(wrapper, '=' .. cacheKey, 't', setmetatable({}, {__index = _G}))

	if not chunk then
		State.distanceExpressionCache[key] = false
		print(('[poodlechat] Invalid distance expression (%s): %s'):format(cacheKey, tostring(loadErr)))
		return nil
	end

	local ok, fn = pcall(chunk)

	if not ok or type(fn) ~= 'function' then
		State.distanceExpressionCache[key] = false
		return nil
	end

	State.distanceExpressionCache[key] = fn

	return fn
end

local function invokeDistanceGetter(fieldName)
	if not State.distanceEnabled then
		return nil
	end

	local value = distanceConfig[fieldName]

	if type(value) == 'function' then
		local ok, result = pcall(value)
		if ok then
			return result
		end
		return nil
	end

	if type(value) == 'string' then
		local fn = createDistanceExpressionExecutor('distance_get_' .. fieldName, value, false)
		if fn then
			local ok, result = pcall(fn)
			if ok then
				return result
			end
		end
	end

	return nil
end

local function invokeDistanceSetter(range)
	if not State.distanceEnabled then
		return false
	end

	local value = distanceConfig.setDistance

	if type(value) == 'function' then
		local ok = pcall(value, range)
		return ok
	end

	if type(value) == 'string' then
		local fn = createDistanceExpressionExecutor('distance_set', value, true)
		if fn then
			local ok = pcall(fn, range)
			return ok
		end
	end

	return false
end

local function getDistanceRangesList()
	local ranges = {}
	local configuredRanges = distanceConfig.ranges

	if type(configuredRanges) == 'table' then
		for _, value in ipairs(configuredRanges) do
			ranges[#ranges + 1] = value
		end
	end

	ranges[#ranges + 1] = distanceConfig.default

	if distanceUiConfig.dynamic == true then
		for value in pairs(State.distanceObservedRanges) do
			ranges[#ranges + 1] = value
		end
	end

	local list = dedupeAndSortRanges(ranges)

	if #list == 0 then
		list[1] = tonumber(distanceConfig.default) or 10.0
	end

	return list
end

local function getClosestRangeIndex(distance, ranges)
	local index = 1
	local bestDiff = math.huge

	for i = 1, #ranges do
		local diff = math.abs(distance - ranges[i])
		if diff < bestDiff or (diff == bestDiff and ranges[i] > ranges[index]) then
			bestDiff = diff
			index = i
		end
	end

	return index
end

local function selectOverrideLevelByRange(distance, levels)
	local selected = nil
	local selectedDiff = math.huge
	local selectedRange = -math.huge

	for i = 1, #levels do
		local level = levels[i]
		local levelRange = tonumber(level.range)
		if levelRange then
			local diff = math.abs(distance - levelRange)
			if diff < selectedDiff or (diff == selectedDiff and levelRange > selectedRange) then
				selected = level
				selectedDiff = diff
				selectedRange = levelRange
			end
		end
	end

	return selected
end

local function selectOverrideLevelByPriority(distance, levels, ranges, modeIndex)
	local prioritized = {}

	for i = 1, #levels do
		local level = levels[i]
		prioritized[#prioritized + 1] = {
			level = level,
			priority = tonumber(level.priority) or i
		}
	end

	table.sort(prioritized, function(a, b)
		if a.priority == b.priority then
			return tostring(a.level.label or '') < tostring(b.level.label or '')
		end
		return a.priority < b.priority
	end)

	local explicitIndex = tonumber(modeIndex)
	if explicitIndex then
		explicitIndex = math.floor(explicitIndex + 0.5)

		for i = 1, #prioritized do
			if prioritized[i].priority == explicitIndex then
				return prioritized[i].level
			end
		end

		return nil
	end

	local closestRangeIndex = getClosestRangeIndex(distance, ranges)
	local mappedIndex

	if #ranges <= 1 or #prioritized <= 1 then
		mappedIndex = 1
	else
		mappedIndex = math.floor(((closestRangeIndex - 1) * (#prioritized - 1)) / (#ranges - 1) + 1 + 0.5)
	end

	mappedIndex = Client.clamp(mappedIndex, 1, #prioritized)

	return prioritized[mappedIndex].level
end

local function getDistanceOverride(distance, fallbackLabel, modeIndex)
	if type(distanceUiConfig) ~= 'table' or distanceUiConfig.override ~= true then
		return fallbackLabel, '#95a5a6'
	end

	local levels = distanceUiConfig.levels

	if type(levels) ~= 'table' or #levels == 0 then
		return fallbackLabel, '#95a5a6'
	end

	local ranges = getDistanceRangesList()
	local mode = tostring(distanceUiConfig.mode or 'priority'):lower()
	local selected = nil
	local explicitModeIndex = tonumber(modeIndex)

	if mode == 'range' then
		selected = selectOverrideLevelByRange(distance, levels)
		if not selected then
			selected = selectOverrideLevelByPriority(distance, levels, ranges, modeIndex)
		end
	else
		selected = selectOverrideLevelByPriority(distance, levels, ranges, modeIndex)
		if not selected and explicitModeIndex then
			return fallbackLabel, '#95a5a6'
		end
		if not selected then
			selected = selectOverrideLevelByRange(distance, levels)
		end
	end

	if not selected then
		return fallbackLabel, '#95a5a6'
	end

	local label = tostring(selected.label or fallbackLabel)
	local color = normalizeHexColor(selected.color, '#95a5a6')

	return label, color
end

local function observeDistance(value)
	if distanceUiConfig.dynamic ~= true then
		return
	end

	local rounded = tonumber(string.format('%.3f', value))
	if rounded then
		State.distanceObservedRanges[rounded] = true
	end
end

local function createDistancePayload()
	if not State.distanceEnabled then
		return {
			enabled = false
		}
	end

	local proximityState = getLocalProximityState()
	local proximityDistance = proximityState and tonumber(proximityState.distance) or nil
	local proximityMode = proximityState and proximityState.mode or nil
	local proximityIndex = proximityState and proximityState.index or nil

	local defaultDistance = tonumber(distanceConfig.default) or 10.0
	local rawDistance = invokeDistanceGetter('getDistance')
	local distance = tonumber(rawDistance) or proximityDistance or defaultDistance

	observeDistance(distance)

	local rawLabel = invokeDistanceGetter('getLabel')
	local fallbackLabel

	if type(rawLabel) == 'string' and rawLabel ~= '' then
		fallbackLabel = rawLabel
	elseif tonumber(rawLabel) then
		fallbackLabel = tostring(rawLabel)
	elseif type(proximityMode) == 'string' and proximityMode ~= '' then
		fallbackLabel = proximityMode
	else
		fallbackLabel = string.format('%.1f m', distance)
	end

	local label, color = getDistanceOverride(distance, fallbackLabel, proximityIndex)
	local ranges = getDistanceRangesList()

	local percent = 0
	local modeCount = tonumber(State.distanceModeCount)
	local modeIndex = proximityIndex and tonumber(proximityIndex) or nil

	if not modeCount or modeCount <= 1 then
		if type(distanceUiConfig.levels) == 'table' and #distanceUiConfig.levels > 1 then
			modeCount = #distanceUiConfig.levels
		elseif #ranges > 1 then
			modeCount = #ranges
		end
	end

	if modeIndex and modeCount and modeCount > 1 then
		percent = math.floor(Client.clamp((modeIndex - 1) / (modeCount - 1), 0.0, 1.0) * 100 + 0.5)
	elseif #ranges == 1 then
		percent = 100
	else
		local minRange = ranges[1]
		local maxRange = ranges[#ranges]

		if maxRange > minRange then
			percent = math.floor(Client.clamp((distance - minRange) / (maxRange - minRange), 0.0, 1.0) * 100 + 0.5)
		end
	end

	return {
		enabled = true,
		value = distance,
		label = label,
		color = color,
		percent = percent,
		modeIndex = modeIndex,
		modeCount = modeCount,
		ranges = ranges
	}
end

local function isSameDistancePayload(a, b)
	if not a or not b then
		return false
	end

	if a.enabled ~= b.enabled then
		return false
	end

	if not a.enabled then
		return true
	end

	if a.label ~= b.label or a.color ~= b.color or a.percent ~= b.percent then
		return false
	end

	if (tonumber(a.modeIndex) or -1) ~= (tonumber(b.modeIndex) or -1) then
		return false
	end

	if (tonumber(a.modeCount) or -1) ~= (tonumber(b.modeCount) or -1) then
		return false
	end

	if math.abs((tonumber(a.value) or 0.0) - (tonumber(b.value) or 0.0)) > 0.001 then
		return false
	end

	local aRanges = a.ranges or {}
	local bRanges = b.ranges or {}

	if #aRanges ~= #bRanges then
		return false
	end

	for i = 1, #aRanges do
		if math.abs((tonumber(aRanges[i]) or 0.0) - (tonumber(bRanges[i]) or 0.0)) > 0.001 then
			return false
		end
	end

	return true
end

local function refreshDistanceState(force)
	local payload = createDistancePayload()

	State.distanceState = payload

	if force or not isSameDistancePayload(payload, State.distanceLastPayload) then
		State.distanceLastPayload = payload
		Client.sendNuiMessage({
			type = 'setDistanceState',
			state = payload
		})
	end
end

local function refreshDistanceModeCount()
	if not State.distanceEnabled then
		return
	end

	if GetResourceState('pma-voice') ~= 'started' then
		return
	end

	pcall(function()
		TriggerEvent('pma-voice:settingsCallback', function(voiceSettings)
			local modes = type(voiceSettings) == 'table' and voiceSettings.voiceModes or nil
			if type(modes) ~= 'table' then
				return
			end

			local count = #modes
			if count > 0 then
				State.distanceModeCount = count
				refreshDistanceState(true)
			end
		end)
	end)
end

local function invokeDistanceCycleFallback()
	if GetResourceState('pma-voice') ~= 'started' then
		return false
	end

	local ok = pcall(ExecuteCommand, 'cycleproximity')
	return ok
end

local function cycleDistance()
	if not State.distanceEnabled then
		return false
	end

	local ranges = getDistanceRangesList()
	local currentDistance = tonumber(State.distanceState.value) or tonumber(distanceConfig.default) or ranges[1]
	local nextRange = ranges[1]

	for i = 1, #ranges do
		if ranges[i] > currentDistance + 0.01 then
			nextRange = ranges[i]
			break
		end
	end

	local ok = invokeDistanceSetter(nextRange)
	local usedFallback = false

	if not ok then
		ok = invokeDistanceCycleFallback()
		usedFallback = ok
	end

	if ok and not usedFallback then
		observeDistance(nextRange)
	end

	refreshDistanceState(true)

	return ok
end

local function getFeatureStatePayload()
	return {
		typing = {
			enabled = State.typingSystemEnabled,
			allowToggle = State.typingToggleAllowed,
			active = State.typingDisplayEnabled
		},
		bubbles = {
			enabled = State.bubbleSystemEnabled,
			allowToggle = State.bubbleToggleAllowed,
			active = State.bubbleDisplayEnabled
		},
		distance = {
			enabled = State.distanceEnabled
		}
	}
end

local function sendFeatureState()
	Client.sendNuiMessage({
		type = 'setFeatureState',
		state = getFeatureStatePayload()
	})
end

local function getPlayerPedFromServerId(serverId)
	local player = GetPlayerFromServerId(serverId)

	if player == -1 then
		return nil
	end

	local ped = GetPlayerPed(player)

	if ped == 0 or not DoesEntityExist(ped) then
		return nil
	end

	return ped
end

local function getPedScreenCoord(serverId, offset, maxDistance, myCoords)
	local ped = getPlayerPedFromServerId(serverId)

	if not ped then
		return nil
	end

	local pedCoords = GetEntityCoords(ped)
	local sourceCoords = myCoords
	if not sourceCoords then
		local myPed = PlayerPedId()
		sourceCoords = GetEntityCoords(myPed)
	end

	if #(sourceCoords - pedCoords) > maxDistance then
		return false, 0.0, 0.0
	end

	local finalOffset = offset

	if not finalOffset then
		local minBounds, maxBounds = GetModelDimensions(GetEntityModel(ped))
		finalOffset = vector3(0.0, 0.0, (maxBounds.z - minBounds.z) / 2)
	end

	return GetScreenCoordFromWorldCoord(
		pedCoords.x + finalOffset.x,
		pedCoords.y + finalOffset.y,
		pedCoords.z + finalOffset.z
	)
end

local function removeOverheadMessage(id)
	local entry = State.OverheadMessages[id]

	if not entry then
		return
	end

	State.OverheadMessages[id] = nil

	Client.sendNuiMessage({
		type = 'remove3dMessage',
		id = id
	})
end

local function upsertOverheadMessage(params)
	local entryId = tostring(params.id)
	local timeout = math.max(0, tonumber(params.timeout) or 0)
	local persistent = params.persistent == true
	local now = GetGameTimer()
	local expiresAt = persistent and nil or (now + timeout)
	local color = params.color or {255, 255, 255}

	State.OverheadMessages[entryId] = {
		id = entryId,
		serverId = tonumber(params.serverId) or params.serverId,
		color = color,
		text = tostring(params.text or ''),
		expiresAt = expiresAt,
		persistent = persistent,
		maxDistance = tonumber(params.maxDistance) or uiConfig.overheadDistance,
		offset = params.offset,
		style = tostring(params.style or 'overhead'),
		floatUp = params.floatUp == true
	}

	Client.sendNuiMessage({
		type = 'create3dMessage',
		id = entryId,
		color = color,
		text = tostring(params.text or ''),
		timeout = timeout,
		persistent = persistent,
		style = tostring(params.style or 'overhead'),
		floatUp = params.floatUp == true
	})
end

local function displayTextAbovePlayer(serverId, color, text)
	local message = tostring(text or '')
	if message == '' then
		return
	end

	local timeout = Client.clamp(
		#message * (tonumber(uiConfig.overheadPerCharMs) or 200),
		tonumber(uiConfig.overheadMinMs) or 5000,
		tonumber(uiConfig.overheadMaxMs) or 10000
	)

	upsertOverheadMessage({
		id = 'msg-' .. tostring(serverId),
		serverId = serverId,
		color = color,
		text = message,
		timeout = timeout,
		persistent = false,
		maxDistance = tonumber(uiConfig.overheadDistance) or 50.0,
		style = 'overhead',
		floatUp = false
	})
end

local function setTypingOverhead(serverId, active)
	local entryId = 'typing-' .. tostring(serverId)

	if not active then
		removeOverheadMessage(entryId)
		return
	end

	local style = tostring(typingConfig.style or 'dots')
	local text = style == 'dots' and '...' or 'typing'
	local configuredOffset = Client.getOffset(typingConfig.offset, vector3(0.0, 0.0, 1.1))
	local offset = vector3(configuredOffset.x, configuredOffset.y, math.max(0.75, configuredOffset.z - 0.2))
	local maxDistance = tonumber(typingConfig.maxDistance) or State.LocalMessageDistance
	local existing = State.OverheadMessages[entryId]

	if existing and existing.style == 'typingBubble' and existing.serverId == (tonumber(serverId) or serverId) then
		existing.offset = offset
		existing.maxDistance = maxDistance
		existing.text = text
		existing.color = {255, 255, 255}
		existing.persistent = true
		existing.expiresAt = nil
		return
	end

	upsertOverheadMessage({
		id = entryId,
		serverId = serverId,
		color = {255, 255, 255},
		text = text,
		timeout = 600000,
		persistent = true,
		maxDistance = maxDistance,
		offset = offset,
		style = 'typingBubble',
		floatUp = false
	})
end

local function displayBubbleMessage(serverId, text)
	if not State.bubbleSystemEnabled or not State.bubbleDisplayEnabled then
		return
	end

	if not bubbleConfig.use3DText then
		return
	end

	local maxLength = math.max(1, tonumber(bubbleConfig.maxLength) or 80)
	local fadeOutTime = math.max(100, tonumber(bubbleConfig.fadeOutTime) or 4000)
	local maxDistance = tonumber(bubbleConfig.maxDistance) or State.LocalMessageDistance
	local clipped = tostring(text or '')
	local sourceKey = tostring(tonumber(serverId) or serverId)
	local baseOffset = Client.getOffset(bubbleConfig.offset, vector3(0.0, 0.0, 1.1))

	if clipped == '' then
		return
	end

	if #clipped > maxLength then
		clipped = clipped:sub(1, maxLength)
	end

	local bubbleId = 'bubble-' .. sourceKey

	removeOverheadMessage('typing-' .. tostring(serverId))
	State.typingRemoteStates[tostring(serverId)] = false

	upsertOverheadMessage({
		id = bubbleId,
		serverId = serverId,
		color = State.LocalMessageColor,
		text = clipped,
		timeout = fadeOutTime,
		persistent = false,
		maxDistance = maxDistance,
		offset = baseOffset,
		style = 'bubble',
		floatUp = true
	})
end

local function setLocalTypingState(active, force)
	if not State.typingSystemEnabled then
		return
	end

	if not State.typingDisplayEnabled then
		active = false
	end

	local now = GetGameTimer()
	local rate = getTypingUpdateRate()
	local nextState = active == true
	local changed = nextState ~= State.localTypingActive

	State.localTypingActive = nextState
	local myServerId = GetPlayerServerId(PlayerId())

	if changed or force or nextState then
		setTypingOverhead(myServerId, nextState)
	end

	State.typingRemoteStates[tostring(myServerId)] = nextState

	if changed or force or (now - State.localTypingLastSent) >= rate then
		State.localTypingLastSent = now
		TriggerServerEvent('poodlechat:typingState', nextState)
	end
end

local function reapplyRemoteTypingEntries()
	for sourceId, active in pairs(State.typingRemoteStates) do
		local numericSource = tonumber(sourceId)
		if numericSource then
			setTypingOverhead(numericSource, State.typingDisplayEnabled and active == true)
		end
	end
end

local function setTypingDisplayEnabled(nextState)
	if not State.typingSystemEnabled then
		return false
	end

	if State.typingToggleAllowed ~= true then
		return State.typingDisplayEnabled
	end

	State.typingDisplayEnabled = nextState == true
	SetResourceKvp('typingIndicatorEnabled', State.typingDisplayEnabled and 'true' or 'false')
	sendFeatureState()

	if not State.typingDisplayEnabled then
		setLocalTypingState(false, true)
		for key in pairs(State.OverheadMessages) do
			if key:sub(1, 7) == 'typing-' then
				removeOverheadMessage(key)
			end
		end
	else
		reapplyRemoteTypingEntries()
	end

	return State.typingDisplayEnabled
end

local function toggleTypingDisplay()
	if not State.typingSystemEnabled then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Typing indicator is not enabled')
		return false
	end

	if State.typingToggleAllowed ~= true then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Typing indicator cannot be toggled')
		return State.typingDisplayEnabled
	end

	local value = setTypingDisplayEnabled(not State.typingDisplayEnabled)
	Client.addChatMessage({255, 255, 128}, 'Typing indicator', value and 'on' or 'off')
	return value
end

local function setBubbleDisplayEnabled(nextState)
	if not State.bubbleSystemEnabled then
		return false
	end

	if State.bubbleToggleAllowed ~= true then
		return State.bubbleDisplayEnabled
	end

	State.bubbleDisplayEnabled = nextState == true
	SetResourceKvp('chatBubblesEnabled', State.bubbleDisplayEnabled and 'true' or 'false')
	sendFeatureState()

	if not State.bubbleDisplayEnabled then
		for key in pairs(State.OverheadMessages) do
			if key:sub(1, 7) == 'bubble-' then
				removeOverheadMessage(key)
			end
		end
	end

	return State.bubbleDisplayEnabled
end

local function toggleBubbleDisplay()
	if not State.bubbleSystemEnabled then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Chat bubbles are not enabled')
		return false
	end

	if State.bubbleToggleAllowed ~= true then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Chat bubbles cannot be toggled')
		return State.bubbleDisplayEnabled
	end

	local value = setBubbleDisplayEnabled(not State.bubbleDisplayEnabled)
	Client.addChatMessage({255, 255, 128}, 'Chat bubbles', value and 'on' or 'off')
	return value
end

AddEventHandler('poodlechat:typingState', function(sourceId, active)
	if not State.typingSystemEnabled then
		return
	end

	local myServerId = GetPlayerServerId(PlayerId())
	local key = tostring(sourceId)
	local enabled = active == true
	State.typingRemoteStates[key] = enabled

	if not State.typingDisplayEnabled then
		setTypingOverhead(sourceId, false)
		return
	end

	if tonumber(sourceId) ~= tonumber(myServerId) and enabled and not Client.isInProximity(sourceId, tonumber(typingConfig.maxDistance) or State.LocalMessageDistance) then
		setTypingOverhead(sourceId, false)
		return
	end

	setTypingOverhead(sourceId, enabled)
end)

AddEventHandler('poodlechat:bubbleMessage', function(sourceId, message)
	removeOverheadMessage('typing-' .. tostring(sourceId))
	State.typingRemoteStates[tostring(sourceId)] = false

	if not State.bubbleSystemEnabled or not State.bubbleDisplayEnabled then
		return
	end

	if not Client.isInProximity(sourceId, tonumber(bubbleConfig.maxDistance) or State.LocalMessageDistance) then
		return
	end

	displayBubbleMessage(sourceId, message)
end)

CreateThread(function()
	while true do
		local hasEntries = next(State.OverheadMessages) ~= nil
		Wait(hasEntries and State.OverheadUpdateIntervalMs or constants.overheadIdleMs)

		if hasEntries then
			local now = GetGameTimer()
			local myCoords = GetEntityCoords(PlayerPedId())

			for id, entry in pairs(State.OverheadMessages) do
				if entry.expiresAt and now >= entry.expiresAt then
					removeOverheadMessage(id)
				else
					local onScreen, screenX, screenY = getPedScreenCoord(entry.serverId, entry.offset, entry.maxDistance, myCoords)

					if onScreen == nil then
						removeOverheadMessage(id)
					else
						Client.sendNuiMessage({
							type = 'update3dMessage',
							id = id,
							onScreen = onScreen,
							screenX = screenX,
							screenY = screenY
						})
					end
				end
			end
		end
	end
end)

if State.distanceEnabled then
	CreateThread(function()
		local pollRate = math.max(100, tonumber(distanceConfig.pollRate) or 500)

		while true do
			Wait(pollRate)
			refreshDistanceState(false)
		end
	end)
end

AddEventHandler('pma-voice:setTalkingMode', function()
	if State.distanceEnabled then
		refreshDistanceModeCount()
		refreshDistanceState(true)
	end
end)

if State.distanceEnabled and type(AddStateBagChangeHandler) == 'function' then
	AddStateBagChangeHandler('proximity', nil, function(bagName)
		local localBag = 'player:' .. tostring(GetPlayerServerId(PlayerId()))
		if bagName ~= localBag then
			return
		end

		refreshDistanceState(true)
	end)
end

Client.getFeatureStatePayload = getFeatureStatePayload
Client.sendFeatureState = sendFeatureState
Client.refreshDistanceState = refreshDistanceState
Client.refreshDistanceModeCount = refreshDistanceModeCount
Client.cycleDistance = cycleDistance
Client.displayTextAbovePlayer = displayTextAbovePlayer
Client.displayBubbleMessage = displayBubbleMessage
Client.removeOverheadMessage = removeOverheadMessage
Client.setLocalTypingState = setLocalTypingState
Client.toggleTypingDisplay = toggleTypingDisplay
Client.toggleBubbleDisplay = toggleBubbleDisplay
Client.setTypingDisplayEnabled = setTypingDisplayEnabled
Client.setBubbleDisplayEnabled = setBubbleDisplayEnabled

