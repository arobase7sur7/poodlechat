local Client = PoodleChatClient
local State = nil
local config = nil
local constants = nil
local uiConfig = nil
local typingConfig = nil
local bubbleConfig = nil
local voiceConfig = nil
local handlersRegistered = false
local refreshDistanceState = nil
local isTabSoundEnabled = nil
local hasAnyUnmutedNotificationTab = nil
local getNotificationToggleState = nil

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

	uiConfig = config.ui or {}
	typingConfig = config.typing or {}
	bubbleConfig = config.bubble or {}
	voiceConfig = config.voice or {}

	return true
end

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

local function normalizeModeText(value)
	if type(value) ~= 'string' then
		return nil
	end

	local normalized = value:lower():gsub('^%s+', ''):gsub('%s+$', '')
	if normalized == '' then
		return nil
	end

	return normalized
end

local function normalizeModeIndex(rawIndex, modeCount)
	local value = tonumber(rawIndex)
	if not value then
		return nil
	end

	local index = math.floor(value + 0.5)
	if index < 0 then
		return nil
	end

	local total = tonumber(modeCount)
	if not total or total <= 0 then
		if index == 0 then
			return 1
		end
		return index
	end

	total = math.max(1, math.floor(total + 0.5))

	if index == 0 then
		return 1
	end

	if index > total and (index - 1) >= 1 and (index - 1) <= total then
		return index - 1
	end

	return Client.clamp(index, 1, total)
end

local function hexColorToRgb(value)
	if type(value) ~= 'string' then
		return nil
	end

	local normalized = value:gsub('%s+', '')
	local rHex, gHex, bHex = normalized:match('^#?(%x%x)(%x%x)(%x%x)$')
	if not rHex or not gHex or not bHex then
		return nil
	end

	local r = tonumber(rHex, 16)
	local g = tonumber(gHex, 16)
	local b = tonumber(bHex, 16)
	if not r or not g or not b then
		return nil
	end

	return {r, g, b}
end

local function rgbToHex(color)
	local r = Client.clamp(math.floor(tonumber(color[1]) or 0), 0, 255)
	local g = Client.clamp(math.floor(tonumber(color[2]) or 0), 0, 255)
	local b = Client.clamp(math.floor(tonumber(color[3]) or 0), 0, 255)
	return string.format('#%02x%02x%02x', r, g, b)
end

local function interpolateColor(colorA, colorB, factor)
	local t = Client.clamp(tonumber(factor) or 0.0, 0.0, 1.0)
	local r = (colorA[1] or 0) + ((colorB[1] or 0) - (colorA[1] or 0)) * t
	local g = (colorA[2] or 0) + ((colorB[2] or 0) - (colorA[2] or 0)) * t
	local b = (colorA[3] or 0) + ((colorB[3] or 0) - (colorA[3] or 0)) * t
	return {
		math.floor(r + 0.5),
		math.floor(g + 0.5),
		math.floor(b + 0.5)
	}
end

local function isVoiceResourceStarted()
	local resourceName = tostring(constants.voiceResourceName or 'pma-voice')
	return GetResourceState(resourceName) == 'started'
end

local function parseVoiceModeEntry(rawEntry, fallbackIndex)
	if type(rawEntry) ~= 'table' then
		return nil
	end

	local range = tonumber(rawEntry[1] or rawEntry.range or rawEntry.distance or rawEntry.value)
	if not range or range <= 0 then
		return nil
	end

	local label = rawEntry[2] or rawEntry.name or rawEntry.label or rawEntry.id
	if type(label) ~= 'string' or label == '' then
		label = string.format('%.1f m', range)
	end

	local index = normalizeModeIndex(rawEntry[3] or rawEntry.index or rawEntry.priority, nil)
	if not index then
		index = fallbackIndex
	end

	return {
		index = index,
		label = label,
		range = range
	}
end

local function refreshVoiceModesFromPma()
	local modes = {}

	if not State.distanceEnabled or not isVoiceResourceStarted() then
		State.voiceModes = modes
		State.voiceModeLabels = {}
		return
	end

	local captured = nil
	TriggerEvent('pma-voice:settingsCallback', function(settings)
		captured = settings
	end)

	local rawModes = captured and captured.voiceModes
	if type(rawModes) == 'table' then
		for i = 1, #rawModes do
			local parsed = parseVoiceModeEntry(rawModes[i], i)
			if parsed then
				modes[#modes + 1] = parsed
			end
		end
	end

	if #modes == 0 then
		local proximity = getLocalProximityState()
		local distance = proximity and tonumber(proximity.distance) or nil
		if distance and distance > 0 then
			local label = tostring(proximity.mode or string.format('%.1f m', distance))
			modes[1] = {
				index = 1,
				label = label,
				range = distance
			}
		end
	end

	table.sort(modes, function(a, b)
		return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
	end)

	State.voiceModes = modes
	State.voiceModeLabels = {}
	for i = 1, #modes do
		State.voiceModeLabels[i] = tostring(modes[i].label or ('Mode ' .. i))
	end
end

local function buildVoiceColorAnchors()
	local anchors = {}
	local minColor = normalizeHexColor(tostring(constants.voiceColorMin or '#2e85cc'), '#2e85cc')
	local maxColor = normalizeHexColor(tostring(constants.voiceColorMax or '#e74c3c'), '#e74c3c')
	anchors[#anchors + 1] = hexColorToRgb(minColor) or {46, 133, 204}

	local intermediate = type(constants.voiceColorIntermediate) == 'table' and constants.voiceColorIntermediate or {}
	for i = 1, #intermediate do
		local parsed = hexColorToRgb(normalizeHexColor(tostring(intermediate[i]), '#ffffff'))
		if parsed then
			anchors[#anchors + 1] = parsed
		end
	end

	anchors[#anchors + 1] = hexColorToRgb(maxColor) or {231, 76, 60}
	return anchors
end

local function buildVoiceLevelColors(levelCount)
	local total = math.max(1, math.floor(tonumber(levelCount) or 1))
	local anchors = buildVoiceColorAnchors()
	local colors = {}
	local anchorCount = #anchors

	if anchorCount == 1 then
		for i = 1, total do
			colors[i] = rgbToHex(anchors[1])
		end
		return colors
	end

	if total <= anchorCount then
		for i = 1, total do
			local anchorIndex = 1
			if total > 1 then
				local target = ((i - 1) / (total - 1)) * (anchorCount - 1)
				anchorIndex = math.floor(target + 0.5) + 1
			end
			anchorIndex = Client.clamp(anchorIndex, 1, anchorCount)
			colors[i] = rgbToHex(anchors[anchorIndex])
		end
	else
		for i = 1, total do
			local t
			if total == 1 then
				t = 0.0
			else
				t = (i - 1) / (total - 1)
			end

			local scaled = t * (anchorCount - 1)
			local leftIndex = math.floor(scaled) + 1
			local rightIndex = math.min(anchorCount, leftIndex + 1)
			local localT = scaled - math.floor(scaled)
			colors[i] = rgbToHex(interpolateColor(anchors[leftIndex], anchors[rightIndex], localT))
		end
	end

	if anchorCount == 3 and total % 2 == 1 then
		local middleIndex = math.floor((total + 1) / 2)
		colors[middleIndex] = rgbToHex(anchors[2])
	end

	return colors
end

local function getDistanceRangesList()
	local ranges = {}
	for i = 1, #State.voiceModes do
		local modeRange = tonumber(State.voiceModes[i].range)
		if modeRange and modeRange > 0 then
			ranges[#ranges + 1] = modeRange
		end
	end

	local sorted = dedupeAndSortRanges(ranges)
	if #sorted == 0 then
		local fallback = tonumber(constants.voiceFallbackLocalDistance) or tonumber(State.LocalMessageDistance) or 10.0
		sorted[1] = fallback
	end
	return sorted
end

local function refreshVoiceAvailability(announceMissing)
	if not State.distanceEnabled then
		State.voiceAvailable = false
		State.voiceModes = {}
		State.voiceModeLabels = {}
		State.voiceLevelColors = {}
		State.distanceModeCount = nil
		refreshDistanceState(true)
		return
	end

	State.voiceAvailable = isVoiceResourceStarted()
	if not State.voiceAvailable then
		State.voiceModes = {}
		State.voiceModeLabels = {}
		State.voiceLevelColors = {}
		State.distanceModeCount = nil
		if announceMissing and not State.voiceErrorShown then
			State.voiceErrorShown = true
			Client.addChatMessage({255, 128, 128}, 'System', ('Voice resource "%s" is not running'):format(tostring(constants.voiceResourceName or 'pma-voice')))
		end
		refreshDistanceState(true)
		return
	end

	State.voiceErrorShown = false
	refreshVoiceModesFromPma()
	State.distanceModeCount = math.max(1, #State.voiceModes)
	State.voiceLevelColors = buildVoiceLevelColors(State.distanceModeCount)
	refreshDistanceState(true)
end

local function createDistancePayload()
	if not State.distanceEnabled or State.voiceAvailable ~= true then
		return {
			enabled = false
		}
	end

	local proximityState = getLocalProximityState()
	local proximityDistance = proximityState and tonumber(proximityState.distance) or nil
	local proximityMode = tostring(proximityState and proximityState.mode or '')
	local modeCount = tonumber(State.distanceModeCount) or 1
	local modeIndex = normalizeModeIndex(proximityState and proximityState.index or nil, modeCount)
	if not modeIndex then
		modeIndex = 1
	end

	local fallbackDistance = tonumber(constants.voiceFallbackLocalDistance) or tonumber(State.LocalMessageDistance) or 10.0
	local distance = proximityDistance or fallbackDistance
	local label = proximityMode ~= '' and proximityMode or tostring(State.voiceModeLabels[modeIndex] or string.format('%.1f m', distance))
	local color = normalizeHexColor(State.voiceLevelColors[modeIndex], '#95a5a6')
	local ranges = getDistanceRangesList()

	local percent
	if modeCount > 1 then
		percent = math.floor(Client.clamp((modeIndex - 1) / (modeCount - 1), 0.0, 1.0) * 100 + 0.5)
	elseif #ranges > 1 then
		local minRange = ranges[1]
		local maxRange = ranges[#ranges]
		if maxRange > minRange then
			percent = math.floor(Client.clamp((distance - minRange) / (maxRange - minRange), 0.0, 1.0) * 100 + 0.5)
		else
			percent = 100
		end
	else
		percent = 100
	end

	percent = percent or 0
	if percent >= 99 then
		percent = 100
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

refreshDistanceState = function(force)
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
	if not State.distanceEnabled or State.voiceAvailable ~= true then
		return
	end

	refreshVoiceModesFromPma()
	State.distanceModeCount = math.max(1, #State.voiceModes)
	State.voiceLevelColors = buildVoiceLevelColors(State.distanceModeCount)
	refreshDistanceState(true)
end

local function cycleDistance()
	if not State.distanceEnabled or State.voiceAvailable ~= true then
		return false
	end

	local ok = pcall(ExecuteCommand, 'cycleproximity')
	if ok then
		Wait(0)
		refreshDistanceModeCount()
		refreshDistanceState(true)
	end

	return ok
end

hasAnyUnmutedNotificationTab = function()
	if type(constants.channelList) ~= 'table' then
		return false
	end

	for i = 1, #constants.channelList do
		local channel = constants.channelList[i]
		local channelId = channel and channel.id
		if channelId and Client.canAccessChannel(channelId) and channel.visible ~= false and isTabSoundEnabled(channelId) then
			return true
		end
	end

	return false
end

getNotificationToggleState = function()
	local hasUnmutedTabs = hasAnyUnmutedNotificationTab()
	return {
		allowToggle = State.whisperSoundToggleAllowed == true and hasUnmutedTabs,
		active = State.whisperSoundEnabled == true and hasUnmutedTabs,
		mode = hasUnmutedTabs and (State.whisperSoundEnabled == true and 'on' or 'off') or 'allMuted'
	}
end

local function getFeatureStatePayload()
	local notificationState = getNotificationToggleState()
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
		autoScroll = {
			enabled = true,
			allowToggle = State.autoScrollToggleAllowed == true,
			active = State.autoScrollEnabled == true
		},
		whisperSound = {
			enabled = true,
			allowToggle = notificationState.allowToggle,
			active = notificationState.active,
			mode = notificationState.mode,
			volume = tonumber(constants.whisperNotificationVolume) or 0.65
		},
		distance = {
			enabled = State.distanceEnabled and State.voiceAvailable == true
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

local function getPedScreenCoord(serverId, offset, maxDistance, myCoords, style)
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

	if style == 'typingBubble' and typingConfig.headTracking == true and type(GetPedBoneCoords) == 'function' then
		local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
		if headCoords then
			local headOffset = offset or vector3(0.0, 0.0, 0.0)
			return GetScreenCoordFromWorldCoord(
				headCoords.x + headOffset.x,
				headCoords.y + headOffset.y,
				headCoords.z + headOffset.z
			)
		end
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
	local configuredOffset = Client.getOffset(typingConfig.offset, vector3(0.0, 0.0, 1.35))
	local offset = nil
	if typingConfig.headTracking == true then
		local configuredHeadLift = tonumber(typingConfig.headLift)
		local fallbackHeadLift = tonumber(configuredOffset.z) or 1.35
		if not configuredHeadLift then
			if fallbackHeadLift > 0.8 then
				configuredHeadLift = 0.26
			else
				configuredHeadLift = math.max(0.05, fallbackHeadLift)
			end
		end

		local totalHeadLift = math.max(0.05, configuredHeadLift + (tonumber(typingConfig.screenLift) or 0.0))
		offset = vector3(configuredOffset.x, configuredOffset.y, totalHeadLift)
	else
		offset = vector3(configuredOffset.x, configuredOffset.y, math.max(1.05, configuredOffset.z))
	end
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

	local now = GetGameTimer()
	local rate = getTypingUpdateRate()
	local nextState = active == true
	local changed = nextState ~= State.localTypingActive

	State.localTypingActive = nextState
	local myServerId = GetPlayerServerId(PlayerId())
	local shouldRenderLocal = State.typingDisplayEnabled and nextState

	if changed or force or nextState then
		setTypingOverhead(myServerId, shouldRenderLocal)
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
		for key in pairs(State.OverheadMessages) do
			if key:sub(1, 7) == 'typing-' then
				removeOverheadMessage(key)
			end
		end
	else
		reapplyRemoteTypingEntries()
		setTypingOverhead(GetPlayerServerId(PlayerId()), State.localTypingActive == true)
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

local function setWhisperSoundEnabled(nextState)
	if State.whisperSoundToggleAllowed ~= true then
		return State.whisperSoundEnabled
	end

	State.whisperSoundEnabled = nextState == true
	SetResourceKvp('poodlechat:notificationSound:v1', State.whisperSoundEnabled and 'true' or 'false')
	SetResourceKvp('whisperSoundEnabled', State.whisperSoundEnabled and 'true' or 'false')
	sendFeatureState()

	return State.whisperSoundEnabled
end

local function toggleWhisperSound()
	if State.whisperSoundToggleAllowed ~= true then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Notification sound cannot be toggled')
		return State.whisperSoundEnabled
	end

	if not hasAnyUnmutedNotificationTab() then
		Client.addChatMessage({255, 165, 0}, 'Notification sound', 'all tabs are muted')
		sendFeatureState()
		return State.whisperSoundEnabled
	end

	local value = setWhisperSoundEnabled(not State.whisperSoundEnabled)
	Client.addChatMessage({255, 255, 128}, 'Notification sound', value and 'on' or 'off')
	return value
end

local function setAutoScrollEnabled(nextState)
	if State.autoScrollToggleAllowed ~= true then
		return State.autoScrollEnabled
	end

	State.autoScrollEnabled = nextState == true
	SetResourceKvp('chatAutoScrollEnabled', State.autoScrollEnabled and 'true' or 'false')
	sendFeatureState()

	return State.autoScrollEnabled
end

local function toggleAutoScroll()
	if State.autoScrollToggleAllowed ~= true then
		Client.addChatMessage({255, 0, 0}, 'Error', 'Auto-scroll cannot be toggled')
		return State.autoScrollEnabled
	end

	local value = setAutoScrollEnabled(not State.autoScrollEnabled)
	Client.addChatMessage({255, 255, 128}, 'Auto-scroll', value and 'on' or 'off')
	return value
end

local function resolveNotificationProfile(channelId)
	local normalized = Client.normalizeKey(channelId) or ''
	local byChannel = type(constants.notificationByChannel) == 'table' and constants.notificationByChannel or {}
	local profile = byChannel[normalized]
	if type(profile) == 'table' then
		return profile
	end
	return type(constants.notificationDefaultProfile) == 'table' and constants.notificationDefaultProfile or {}
end

isTabSoundEnabled = function(channelId)
	local normalized = Client.normalizeKey(channelId) or ''
	if normalized == '' then
		return true
	end

	local toggles = State.TabNotificationToggles
	if type(toggles) == 'table' and toggles[normalized] ~= nil then
		return toggles[normalized] == true
	end

	local profile = resolveNotificationProfile(normalized)
	return type(profile) ~= 'table' or profile.enabled ~= false
end

local function playTabNotificationSound(channelId)
	if State.whisperSoundEnabled ~= true then
		return false
	end

	local normalized = Client.normalizeKey(channelId) or 'whispers'
	if not isTabSoundEnabled(normalized) then
		return false
	end

	local profile = resolveNotificationProfile(normalized)
	local sound = type(profile.sound) == 'table' and profile.sound or {}
	local fallbackSound = type(profile.fallbackSound) == 'table' and profile.fallbackSound or {}
	local soundName = tostring(sound.name or constants.whisperNotificationSoundName or 'SELECT')
	local soundSet = tostring(sound.set or constants.whisperNotificationSoundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
	local fallbackName = tostring(fallbackSound.name or constants.whisperNotificationFallbackSoundName or 'SELECT')
	local fallbackSet = tostring(fallbackSound.set or constants.whisperNotificationFallbackSoundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET')

	if soundName == '' or soundSet == '' then
		pcall(PlaySoundFrontend, -1, fallbackName, fallbackSet, true)
		return true
	end

	local ok = pcall(PlaySoundFrontend, -1, soundName, soundSet, true)
	if not ok then
		pcall(PlaySoundFrontend, -1, fallbackName, fallbackSet, true)
	end
	return true
end

local function playWhisperSound()
	return playTabNotificationSound('whispers')
end

local function registerFeatureHandlers()
	if handlersRegistered then
		return
	end

	if not ensureContext() then
		return
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
						local onScreen, screenX, screenY = getPedScreenCoord(entry.serverId, entry.offset, entry.maxDistance, myCoords, entry.style)

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
		refreshVoiceAvailability(true)

		CreateThread(function()
			local pollRate = math.max(100, tonumber(constants.voicePollRate) or 250)
			local modeRefreshEvery = math.max(1000, pollRate * 8)
			local nextModeRefreshAt = 0
			while true do
				Wait(pollRate)
				if State.voiceAvailable == true then
					local now = GetGameTimer()
					if now >= nextModeRefreshAt then
						refreshDistanceModeCount()
						nextModeRefreshAt = now + modeRefreshEvery
					else
						refreshDistanceState(false)
					end
				end
			end
		end)
	end

	AddEventHandler('onClientResourceStart', function(resName)
		if not State.distanceEnabled then
			return
		end

		local target = normalizeModeText(resName)
		local configured = normalizeModeText(constants.voiceResourceName or 'pma-voice')
		if target ~= configured then
			return
		end

		Wait(constants.pmaStartDelayMs or 0)
		refreshVoiceAvailability(false)
		sendFeatureState()
	end)

	AddEventHandler('onClientResourceStop', function(resName)
		if not State.distanceEnabled then
			return
		end

		local target = normalizeModeText(resName)
		local configured = normalizeModeText(constants.voiceResourceName or 'pma-voice')
		if target ~= configured then
			return
		end

		State.voiceAvailable = false
		State.voiceModes = {}
		State.voiceModeLabels = {}
		State.voiceLevelColors = {}
		State.distanceModeCount = nil
		refreshDistanceState(true)
		sendFeatureState()
	end)

	AddEventHandler('pma-voice:setTalkingMode', function()
		if State.distanceEnabled and State.voiceAvailable == true then
			refreshDistanceModeCount()
			refreshDistanceState(true)
		end
	end)

	if State.distanceEnabled and type(AddStateBagChangeHandler) == 'function' then
		AddStateBagChangeHandler('proximity', nil, function(bagName)
			if State.voiceAvailable ~= true then
				return
			end

			local localBag = 'player:' .. tostring(GetPlayerServerId(PlayerId()))
			if bagName ~= localBag then
				return
			end

			refreshDistanceModeCount()
		end)
	end

	handlersRegistered = true
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
Client.toggleWhisperSound = toggleWhisperSound
Client.toggleAutoScroll = toggleAutoScroll
Client.playWhisperSound = playWhisperSound
Client.playTabNotificationSound = playTabNotificationSound
Client.setWhisperSoundEnabled = setWhisperSoundEnabled
Client.setAutoScrollEnabled = setAutoScrollEnabled
Client.setTypingDisplayEnabled = setTypingDisplayEnabled
Client.setBubbleDisplayEnabled = setBubbleDisplayEnabled
Client.refreshVoiceAvailability = refreshVoiceAvailability
Client.registerFeatureHandlers = registerFeatureHandlers

