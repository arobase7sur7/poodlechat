local Client = PoodleChatClient
local State = nil
local config = nil
local constants = nil
local handlersRegistered = false
local tabGroupingKvpKey = 'poodlechat:tabGrouping:v1'
local tabGroupOrderKvpKey = 'poodlechat:tabGroupOrder:v1'
local tabGroupNamesKvpKey = 'poodlechat:tabGroupNames:v1'
local tabGroupDisplayModeKvpKey = 'poodlechat:tabGroupDisplayMode:v1'
local hiddenTabButtonsKvpKey = 'poodlechat:hiddenTabs:v1'
local tabNotificationKvpKey = 'poodlechat:tabNotifications:v1'
local notificationSoundKvpKey = 'poodlechat:notificationSound:v1'
local embeddedRadioRefreshWorkerRunning = false
local embeddedRadioRefreshDelayMs = 700
local embeddedRadioRefreshMaxAttempts = 40
local clearHistoryConfirmUntil = 0

local function normalizeResourceKey(resourceName)
	local value = tostring(resourceName or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
	if value == '' then
		return nil
	end

	return value:gsub('[^%w]', '')
end

local function resolveResourceName(resourceName)
	local configured = tostring(resourceName or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if configured == '' then
		return nil
	end

	local directState = GetResourceState(configured)
	if directState and directState ~= 'missing' and directState ~= 'unknown' then
		return configured
	end

	if type(GetNumResources) ~= 'function' or type(GetResourceByFindIndex) ~= 'function' then
		return configured
	end

	local expectedKey = normalizeResourceKey(configured)
	if not expectedKey then
		return configured
	end

	local fallback = nil
	for resourceIndex = 0, GetNumResources() - 1 do
		local candidate = GetResourceByFindIndex(resourceIndex)
		if type(candidate) == 'string' and candidate ~= '' then
			local candidateKey = normalizeResourceKey(candidate)
			if candidateKey == expectedKey then
				local state = GetResourceState(candidate)
				if state == 'started' or state == 'starting' then
					return candidate
				end
				if not fallback then
					fallback = candidate
				end
			end
		end
	end

	return fallback or configured
end

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

local function normalizeInboundText(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getInboundPrimaryText(raw)
	local args = type(raw.args) == 'table' and raw.args or nil
	if args and args[1] ~= nil then
		return normalizeInboundText(args[1])
	end

	return normalizeInboundText(raw.text or raw.message or '')
end

local function matchesInboundRule(rule, raw)
	if type(rule) ~= 'table' then
		return false
	end

	local label = Client.normalizeKey(normalizeInboundText(raw.label))
	local primaryText = getInboundPrimaryText(raw)
	local primaryLower = string.lower(primaryText)
	local templateText = tostring(raw.template or '')
	local templateLower = string.lower(templateText)

	local labels = type(rule.labels) == 'table' and rule.labels or {}
	for i = 1, #labels do
		local matchLabel = Client.normalizeKey(labels[i])
		if matchLabel and label and label == matchLabel then
			return true
		end
	end

	local prefixes = type(rule.prefixes) == 'table' and rule.prefixes or {}
	for i = 1, #prefixes do
		local prefix = normalizeInboundText(prefixes[i])
		if prefix ~= '' and primaryLower:sub(1, #prefix) == string.lower(prefix) then
			return true
		end
	end

	local pattern = type(rule.pattern) == 'string' and rule.pattern or nil
	if pattern and pattern ~= '' then
		local ok, matched = pcall(string.find, primaryText, pattern)
		if ok and matched then
			return true
		end
	end

	local templateContains = type(rule.templateContains) == 'table' and rule.templateContains or {}
	for i = 1, #templateContains do
		local fragment = normalizeInboundText(templateContains[i])
		if fragment ~= '' and string.find(templateLower, string.lower(fragment), 1, true) then
			return true
		end
	end

	local templatePattern = type(rule.templatePattern) == 'string' and rule.templatePattern or nil
	if templatePattern and templatePattern ~= '' then
		local ok, matched = pcall(string.find, templateText, templatePattern)
		if ok and matched then
			return true
		end
	end

	return false
end

local function shouldUseLegacyCommandContextFallback(raw)
	if type(raw) ~= 'table' then
		return false
	end

	if raw.channel ~= nil then
		return false
	end

	if raw.template ~= nil then
		return false
	end

	local metadata = type(raw.metadata) == 'table' and raw.metadata or nil
	if metadata and next(metadata) ~= nil then
		return false
	end

	local label = normalizeInboundText(raw.label)
	if label ~= '' then
		return false
	end

	local args = type(raw.args) == 'table' and raw.args or nil
	if args then
		if #args ~= 1 then
			return false
		end

		local onlyArg = normalizeInboundText(args[1])
		if onlyArg == '' or onlyArg:sub(1, 1) == '[' then
			return false
		end

		return true
	end

	local text = normalizeInboundText(raw.text or raw.message or '')
	if text == '' or text:sub(1, 1) == '[' then
		return false
	end

	return true
end

local function resolveInboundMessageChannel(raw)
	local channelId = Client.normalizeKey(raw.channel)
	if channelId and constants.channelById[channelId] then
		return channelId
	end

	local inboundRules = type(constants.inboundMessageRules) == 'table' and constants.inboundMessageRules or {}
	for i = 1, #inboundRules do
		local rule = inboundRules[i]
		if matchesInboundRule(rule, raw) then
			return rule.channel
		end
	end

	if shouldUseLegacyCommandContextFallback(raw) then
		local legacyChannelId = Client.getActiveCommandContextChannel()
		if legacyChannelId and constants.channelById[legacyChannelId] then
			return legacyChannelId
		end
	end

	return constants.defaultChannelId
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

local function canChannelReceiveGroupedChannels(channelId)
	local id = Client.normalizeKey(channelId)
	if not id then
		return false
	end

	local relayTargets = type(constants.tabGroupRelayTargetByChannel) == 'table' and constants.tabGroupRelayTargetByChannel or {}
	if relayTargets[id] == nil then
		return true
	end

	return relayTargets[id] == true
end

local function assignRelayTargetGrouping(provisional)
	local membersByGroup = {}
	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local groupId = tonumber(provisional[channelId])
		if groupId and groupId > 0 then
			groupId = math.floor(groupId)
			if not membersByGroup[groupId] then
				membersByGroup[groupId] = {}
			end
			membersByGroup[groupId][#membersByGroup[groupId] + 1] = channelId
		end
	end

	local anchorByChannel = {}
	for _, members in pairs(membersByGroup) do
		local memberSet = {}
		for i = 1, #members do
			memberSet[members[i]] = true
		end

		local relayAnchor = nil
		for i = 1, #constants.channelList do
			local candidateId = constants.channelList[i].id
			if memberSet[candidateId] and canChannelReceiveGroupedChannels(candidateId) then
				relayAnchor = candidateId
				break
			end
		end

		if relayAnchor then
			for i = 1, #members do
				anchorByChannel[members[i]] = relayAnchor
			end
		else
			for i = 1, #members do
				anchorByChannel[members[i]] = members[i]
			end
		end
	end

	local normalized = {}
	local groupIdByAnchor = {}
	local nextGroupId = 0
	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local anchorId = anchorByChannel[channelId] or channelId
		if not groupIdByAnchor[anchorId] then
			nextGroupId = nextGroupId + 1
			groupIdByAnchor[anchorId] = nextGroupId
		end
		normalized[channelId] = groupIdByAnchor[anchorId]
	end

	return normalized
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

	return assignRelayTargetGrouping(defaults)
end

local function normalizeTabGrouping(rawGrouping)
	local provisional = {}
	local highestGroup = 0

	if type(rawGrouping) == 'table' then
		for i = 1, #constants.channelList do
			local channelId = constants.channelList[i].id
			local groupId = tonumber(rawGrouping[channelId])
			if groupId and groupId > 0 then
				groupId = math.floor(groupId)
				provisional[channelId] = groupId
				if groupId > highestGroup then
					highestGroup = groupId
				end
			end
		end
	end

	local defaults = buildDefaultTabGrouping()
	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		if not provisional[channelId] then
			local fallbackGroup = tonumber(defaults[channelId])
			if fallbackGroup and fallbackGroup > 0 then
				fallbackGroup = math.floor(fallbackGroup)
				provisional[channelId] = fallbackGroup
				if fallbackGroup > highestGroup then
					highestGroup = fallbackGroup
				end
			else
				highestGroup = highestGroup + 1
				provisional[channelId] = highestGroup
			end
		end
	end

	return assignRelayTargetGrouping(provisional)
end

local function normalizeTabGroupOrder(rawOrder)
	local normalized = {}
	local nextOrder = 1

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local value = type(rawOrder) == 'table' and tonumber(rawOrder[channelId]) or nil
		if value and value > 0 then
			normalized[channelId] = math.floor(value)
		else
			normalized[channelId] = nextOrder
		end
		nextOrder = nextOrder + 1
	end

	return normalized
end

local function buildValidTabGroupLookup(grouping)
	local valid = {}
	local source = type(grouping) == 'table' and grouping or {}

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		local groupId = tonumber(source[channelId])
		if groupId and groupId > 0 then
			valid[tostring(math.floor(groupId))] = true
		end
	end

	return valid
end

local function normalizeTabGroupNames(rawNames, grouping)
	local normalized = {}
	local validGroups = buildValidTabGroupLookup(grouping)

	if type(rawNames) == 'table' then
		for groupId, label in pairs(rawNames) do
			local normalizedGroupId = tostring(math.floor(tonumber(groupId) or 0))
			local normalizedLabel = tostring(label or ''):gsub('^%s+', ''):gsub('%s+$', '')
			if validGroups[normalizedGroupId] and normalizedLabel ~= '' then
				normalized[normalizedGroupId] = normalizedLabel:sub(1, 48)
			end
		end
	end

	return normalized
end

local function normalizeTabGroupDisplayMode(rawModes, grouping)
	local normalized = {}
	local validGroups = buildValidTabGroupLookup(grouping)

	if type(rawModes) == 'table' then
		for groupId, mode in pairs(rawModes) do
			local normalizedGroupId = tostring(math.floor(tonumber(groupId) or 0))
			local normalizedMode = tostring(mode or ''):gsub('_', '-'):lower()
			if normalizedMode == 'foldermerged' then
				normalizedMode = 'folder-merged'
			end
			if validGroups[normalizedGroupId] and (normalizedMode == 'folder' or normalizedMode == 'merged' or normalizedMode == 'folder-merged') then
				normalized[normalizedGroupId] = normalizedMode
			end
		end
	end

	return normalized
end

local function getTabGroupingAnchorChannelId(channelId, grouping)
	local id = Client.normalizeKey(channelId)
	if not id or not constants.channelById[id] then
		return nil
	end

	local source = type(grouping) == 'table' and grouping or State.TabGrouping or buildDefaultTabGrouping()
	local groupId = tonumber(source[id])
	if not groupId or groupId <= 0 then
		return id
	end

	for i = 1, #constants.channelList do
		local candidateId = constants.channelList[i].id
		if tonumber(source[candidateId]) == groupId and canChannelReceiveGroupedChannels(candidateId) then
			return candidateId
		end
	end

	return id
end

local function isPinnedTab(channelId)
	local id = Client.normalizeKey(channelId)
	if not id then
		return false
	end

	local pinnedByChannel = type(constants.tabPinnedByChannel) == 'table' and constants.tabPinnedByChannel or {}
	if pinnedByChannel[id] == nil then
		return id == 'local' or id == 'global'
	end

	return pinnedByChannel[id] == true
end

local function canHideTabButton(channelId, grouping)
	local id = Client.normalizeKey(channelId)
	if not id or not constants.channelById[id] then
		return false
	end

	if isPinnedTab(id) then
		return false
	end

	return getTabGroupingAnchorChannelId(id, grouping) ~= id
end

local function normalizeHiddenTabButtons(rawHidden, grouping)
	local normalized = {}
	if type(rawHidden) ~= 'table' then
		return normalized
	end

	for i = 1, #constants.channelList do
		local channelId = constants.channelList[i].id
		if rawHidden[channelId] == true and canHideTabButton(channelId, grouping) then
			normalized[channelId] = true
		end
	end

	return normalized
end

local function ensureActiveChannelVisible()
	local current = Client.normalizeKey(State.Channel)
	if not current or State.HiddenTabButtons[current] ~= true then
		return
	end

	local fallback = getTabGroupingAnchorChannelId(current, State.TabGrouping)
	State.Channel = resolveChannelWithFallback(fallback)
end

local function isWhisperDedicatedTabActive()
	local whisperChannel = constants.channelById.whispers
	if constants.whisperChannelEnabled ~= true or not whisperChannel then
		return false
	end

	if whisperChannel.visible == false or not Client.canAccessChannel('whispers') then
		return false
	end

	if canChannelReceiveGroupedChannels('whispers') then
		return false
	end

	return getTabGroupingAnchorChannelId('whispers') == 'whispers'
end

local function isEmbeddedRadioTabActive()
	if constants.radioIntegrationEnabled ~= true then
		return false
	end

	local radioChannelId = Client.normalizeKey(constants.radioIntegrationChannelId)
	if not radioChannelId or not constants.channelById[radioChannelId] then
		return false
	end

	local radioChannel = constants.channelById[radioChannelId]
	if radioChannel.visible == false or not Client.canAccessChannel(radioChannelId) then
		return false
	end

	if canChannelReceiveGroupedChannels(radioChannelId) then
		return false
	end

	return getTabGroupingAnchorChannelId(radioChannelId) == radioChannelId
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

local function isEmbeddedRadioResourceStarted()
	if constants.radioIntegrationEnabled ~= true then
		return false
	end

	local resourceName = resolveResourceName(constants.radioIntegrationResource or '7-radio')
	local state = GetResourceState(resourceName)
	return state == 'started' or state == 'starting'
end

local function buildDefaultRadioSlot(slotName)
	return {
		slot = slotName,
		frequency = nil,
		label = '',
		color = nil,
		relay = false
	}
end

local function buildDefaultEmbeddedRadioState()
	return {
		enabled = constants.radioIntegrationEnabled == true,
		available = false,
		resource = resolveResourceName(constants.radioIntegrationResource or '7-radio') or tostring(constants.radioIntegrationResource or '7-radio'),
		channelId = Client.normalizeKey(constants.radioIntegrationChannelId) or 'radio',
		active = 'primary',
		relayLocked = false,
		slots = {
			primary = buildDefaultRadioSlot('primary'),
			secondary = buildDefaultRadioSlot('secondary')
		},
		historyByFrequency = {}
	}
end

local function cloneEmbeddedRadioMessage(entry, fallbackFrequency)
	if type(entry) ~= 'table' then
		return nil
	end

	local frequency = tostring(entry.frequency or fallbackFrequency or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if frequency == '' then
		return nil
	end

	local clientMessageId = tostring(entry.clientMessageId or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if clientMessageId == '' then
		clientMessageId = nil
	end

	local slot = tostring(entry.slot or entry.channel or ''):lower()
	if slot ~= 'secondary' then
		slot = 'primary'
	end

	return {
		frequency = frequency,
		sender = tostring(entry.sender or ''),
		message = tostring(entry.message or ''),
		senderId = tonumber(entry.senderId) or nil,
		clientMessageId = clientMessageId,
		timestamp = tonumber(entry.timestamp) or 0,
		slot = slot
	}
end

local function cloneEmbeddedRadioHistory(rawHistory)
	local cloned = {}
	if type(rawHistory) ~= 'table' then
		return cloned
	end

	for frequency, entries in pairs(rawHistory) do
		local freqLabel = tostring(frequency or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if freqLabel ~= '' then
			local normalizedEntries = {}
			if type(entries) == 'table' then
				for i = 1, #entries do
					local normalizedEntry = cloneEmbeddedRadioMessage(entries[i], freqLabel)
					if normalizedEntry then
						normalizedEntries[#normalizedEntries + 1] = normalizedEntry
					end
				end
			end
			cloned[freqLabel] = normalizedEntries
		end
	end

	return cloned
end

local function normalizeEmbeddedRadioSlot(slotName, rawSlot, fallbackFrequency, fallbackRelay)
	local normalized = buildDefaultRadioSlot(slotName)
	local source = type(rawSlot) == 'table' and rawSlot or {}
	local frequency = tostring(source.frequency or fallbackFrequency or ''):gsub('^%s+', ''):gsub('%s+$', '')

	if frequency ~= '' then
		normalized.frequency = frequency
	end

	normalized.label = tostring(source.label or '')
	if normalized.label == '' and normalized.frequency then
		normalized.label = normalized.frequency
	end

	if source.color ~= nil then
		normalized.color = tostring(source.color)
	end

	if source.relay ~= nil then
		normalized.relay = source.relay == true
	else
		normalized.relay = fallbackRelay == true
	end

	return normalized
end

local function applyEmbeddedRadioActiveFallback(rawState)
	if rawState.active == 'primary' and not rawState.slots.primary.frequency and rawState.slots.secondary.frequency then
		rawState.active = 'secondary'
	elseif rawState.active == 'secondary' and not rawState.slots.secondary.frequency and rawState.slots.primary.frequency then
		rawState.active = 'primary'
	elseif rawState.active ~= 'secondary' then
		rawState.active = 'primary'
	end
end

local function embeddedRadioStateHasFrequency(rawState)
	if type(rawState) ~= 'table' then
		return false
	end

	local slots = type(rawState.slots) == 'table' and rawState.slots or nil
	local primary = tostring((slots and slots.primary and slots.primary.frequency) or rawState.primary or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if primary ~= '' then
		return true
	end

	local secondary = tostring((slots and slots.secondary and slots.secondary.frequency) or rawState.secondary or ''):gsub('^%s+', ''):gsub('%s+$', '')
	return secondary ~= ''
end

local function setEmbeddedRadioState(rawState, includeHistory)
	local previousState = type(State.RadioIntegration) == 'table' and State.RadioIntegration or buildDefaultEmbeddedRadioState()
	local normalized = buildDefaultEmbeddedRadioState()
	local source = type(rawState) == 'table' and rawState or {}

	normalized.enabled = constants.radioIntegrationEnabled == true and source.enabled ~= false
	normalized.available = source.available == true
	normalized.active = tostring(source.active or previousState.active or 'primary') == 'secondary' and 'secondary' or 'primary'
	normalized.relayLocked = source.relayLocked == true
	normalized.slots.primary = normalizeEmbeddedRadioSlot(
		'primary',
		type(source.slots) == 'table' and source.slots.primary or nil,
		source.primary,
		source.primaryChatRelay
	)
	normalized.slots.secondary = normalizeEmbeddedRadioSlot(
		'secondary',
		type(source.slots) == 'table' and source.slots.secondary or nil,
		source.secondary,
		source.secondaryChatRelay
	)

	local historySource = nil
	if includeHistory == true then
		if type(source.history) == 'table' then
			historySource = source.history
		elseif type(source.historyByFrequency) == 'table' then
			historySource = source.historyByFrequency
		end
	end

	if historySource then
		normalized.historyByFrequency = cloneEmbeddedRadioHistory(historySource)
	else
		normalized.historyByFrequency = cloneEmbeddedRadioHistory(previousState.historyByFrequency)
	end

	applyEmbeddedRadioActiveFallback(normalized)
	State.RadioIntegration = normalized
	return normalized
end

local function getEmbeddedRadioPayload()
	local current = type(State.RadioIntegration) == 'table' and State.RadioIntegration or buildDefaultEmbeddedRadioState()
	return {
		enabled = current.enabled == true,
		available = current.available == true,
		resource = current.resource,
		channelId = current.channelId,
		active = current.active,
		relayLocked = current.relayLocked == true,
		slots = {
			primary = normalizeEmbeddedRadioSlot('primary', current.slots and current.slots.primary or nil, nil, nil),
			secondary = normalizeEmbeddedRadioSlot('secondary', current.slots and current.slots.secondary or nil, nil, nil)
		},
		historyByFrequency = cloneEmbeddedRadioHistory(current.historyByFrequency)
	}
end

local function syncEmbeddedRadioStateToNui()
	if State.chatLoaded ~= true then
		return
	end

	Client.sendNuiMessage({
		type = 'setRadioState',
		state = getEmbeddedRadioPayload()
	})
end

local function preserveEmbeddedRadioAvailability(available)
	local current = getEmbeddedRadioPayload()
	current.available = available == true
	return setEmbeddedRadioState(current, true)
end

local function refreshEmbeddedRadioState()
	if constants.radioIntegrationEnabled ~= true then
		return setEmbeddedRadioState({}, false)
	end

	if not isEmbeddedRadioResourceStarted() then
		return preserveEmbeddedRadioAvailability(false)
	end

	local ok, rawState = pcall(function()
		local resourceName = resolveResourceName(constants.radioIntegrationResource or '7-radio')
		return exports[resourceName]:GetState()
	end)

	if not ok or type(rawState) ~= 'table' then
		return preserveEmbeddedRadioAvailability(false)
	end

	if rawState.available == nil then
		rawState.available = true
	end

	return setEmbeddedRadioState(rawState, true)
end

local function ensureEmbeddedRadioStateSynced()
	if constants.radioIntegrationEnabled ~= true then
		return
	end

	if embeddedRadioRefreshWorkerRunning then
		return
	end

	embeddedRadioRefreshWorkerRunning = true

	CreateThread(function()
		for _ = 1, embeddedRadioRefreshMaxAttempts do
			if constants.radioIntegrationEnabled ~= true then
				break
			end

			local current = type(State.RadioIntegration) == 'table' and State.RadioIntegration or buildDefaultEmbeddedRadioState()
			if current.available == true and embeddedRadioStateHasFrequency(current) then
				break
			end

			if not isEmbeddedRadioResourceStarted() then
				break
			end

			Wait(embeddedRadioRefreshDelayMs)

			local nextState = refreshEmbeddedRadioState()
			if type(nextState) == 'table' then
				syncEmbeddedRadioStateToNui()
				if nextState.available == true and embeddedRadioStateHasFrequency(nextState) then
					break
				end
			end
		end

		embeddedRadioRefreshWorkerRunning = false
	end)
end

local function appendEmbeddedRadioMessage(rawMessage)
	if type(State.RadioIntegration) ~= 'table' then
		State.RadioIntegration = buildDefaultEmbeddedRadioState()
	end

	local normalizedMessage = cloneEmbeddedRadioMessage(rawMessage, rawMessage and rawMessage.frequency or nil)
	if not normalizedMessage then
		return nil
	end

	local historyByFrequency = State.RadioIntegration.historyByFrequency
	if type(historyByFrequency) ~= 'table' then
		historyByFrequency = {}
		State.RadioIntegration.historyByFrequency = historyByFrequency
	end

	local history = historyByFrequency[normalizedMessage.frequency]
	if type(history) ~= 'table' then
		history = {}
		historyByFrequency[normalizedMessage.frequency] = history
	end

	if normalizedMessage.clientMessageId then
		for i = 1, #history do
			if history[i].clientMessageId == normalizedMessage.clientMessageId then
				return nil
			end
		end
	end

	history[#history + 1] = normalizedMessage
	if #history > 500 then
		local trimmed = {}
		for i = math.max(1, #history - 499), #history do
			trimmed[#trimmed + 1] = history[i]
		end
		historyByFrequency[normalizedMessage.frequency] = trimmed
	end

	return normalizedMessage
end

local function sendEmbeddedRadioMessage(slot, message, explicitFrequency)
	if constants.radioIntegrationEnabled ~= true then
		return {
			ok = false,
			reason = 'disabled',
			state = getEmbeddedRadioPayload()
		}
	end

	if not isEmbeddedRadioResourceStarted() then
		preserveEmbeddedRadioAvailability(false)
		return {
			ok = false,
			reason = 'unavailable',
			state = getEmbeddedRadioPayload()
		}
	end

	local currentState = type(State.RadioIntegration) == 'table' and State.RadioIntegration or buildDefaultEmbeddedRadioState()
	local slotKey = tostring(slot or ''):lower() == 'secondary' and 'secondary' or 'primary'
	local slotState = currentState.slots and currentState.slots[slotKey] or nil
	local slotFrequency = slotState and slotState.frequency or nil
	local frequency = tostring(explicitFrequency or slotFrequency or ''):gsub('^%s+', ''):gsub('%s+$', '')
	if frequency == '' then
		frequency = nil
	end

	local ok, response = pcall(function()
		local resourceName = resolveResourceName(constants.radioIntegrationResource or '7-radio')
		return exports[resourceName]:SendMessageFromSlot(slotKey, message, frequency)
	end)

	if not ok or type(response) ~= 'table' then
		local nextState = refreshEmbeddedRadioState()
		if type(nextState) == 'table' and not embeddedRadioStateHasFrequency(nextState) then
			ensureEmbeddedRadioStateSynced()
		end
		return {
			ok = false,
			reason = 'export_failed',
			state = getEmbeddedRadioPayload()
		}
	end

	if type(response.state) == 'table' then
		setEmbeddedRadioState(response.state, true)
	else
		local nextState = refreshEmbeddedRadioState()
		if type(nextState) == 'table' and not embeddedRadioStateHasFrequency(nextState) then
			ensureEmbeddedRadioStateSynced()
		end
	end
	return {
		ok = response.success == true,
		reason = response.reason,
		clientMessageId = response.clientMessageId,
		frequency = response.frequency,
		slot = response.slot,
		state = getEmbeddedRadioPayload()
	}
end

local function getHiddenRadioFallbackChannelId()
	local radioChannelId = Client.normalizeKey(constants.radioIntegrationChannelId)
	local candidates = {
		constants.radioIntegrationFallbackChannelId,
		constants.defaultChannelId,
		'local',
		'global'
	}

	for i = 1, #candidates do
		local candidateId = Client.normalizeKey(candidates[i])
		local channel = candidateId and constants.channelById[candidateId] or nil
		if candidateId and candidateId ~= radioChannelId and channel and channel.visible ~= false and Client.canAccessChannel(candidateId) then
			return candidateId
		end
	end

	for i = 1, #constants.channelList do
		local channel = constants.channelList[i]
		if channel and channel.id ~= radioChannelId and channel.visible ~= false and Client.canAccessChannel(channel.id) then
			return channel.id
		end
	end

	return getFirstAccessibleChannelId()
end

local function shouldRouteRadioRelayToFallback(rawMessage, resolvedChannelId)
	if constants.radioIntegrationEnabled ~= true then
		return false
	end

	if Client.normalizeKey(resolvedChannelId) ~= Client.normalizeKey(constants.radioIntegrationChannelId) then
		return false
	end

	local metadata = type(rawMessage.metadata) == 'table' and rawMessage.metadata or nil
	if not metadata or tostring(metadata.type or '') ~= 'radioRelay' then
		return false
	end

	return not isEmbeddedRadioTabActive()
end

local function shouldSuppressEmbeddedRadioRelay(normalizedMessage)
	if constants.radioIntegrationEnabled ~= true or not isEmbeddedRadioTabActive() then
		return false
	end

	local radioChannelId = Client.normalizeKey(constants.radioIntegrationChannelId)
	if not radioChannelId or normalizedMessage.channel ~= radioChannelId then
		return false
	end

	local metadata = type(normalizedMessage.metadata) == 'table' and normalizedMessage.metadata or nil
	if not metadata or tostring(metadata.type or '') ~= 'radioRelay' then
		return false
	end

	return normalizeResourceKey(metadata.resource) == normalizeResourceKey(resolveResourceName(constants.radioIntegrationResource or '7-radio'))
end

local function normalizeMessagePayload(message)
	local raw = type(message) == 'table' and message or {text = tostring(message or '')}
	local channelId = resolveInboundMessageChannel(raw)
	if shouldRouteRadioRelayToFallback(raw, channelId) then
		channelId = getHiddenRadioFallbackChannelId()
	end

	channelId = resolveChannelWithFallback(channelId)

	local channel = getChannel(channelId)
	local color = Client.normalizeRgbColor(raw.color, channel and channel.color or {255, 255, 255})
	local metadata = type(raw.metadata) == 'table' and raw.metadata or nil

	local metadataType = metadata and tostring(metadata.type or '') or ''
	local metadataChannel = metadata and Client.normalizeKey(metadata.channel) or nil
	if channelId == 'local'
		and metadata
		and metadataType == 'chat'
		and (metadataChannel == nil or metadataChannel == 'local')
		and type(Client.getVoiceColorForLocalMessage) == 'function' then
		local distanceColor = Client.getVoiceColorForLocalMessage(
			metadata.authorSource or metadata.source,
			metadata.senderDistance or metadata.distance
		)
		if distanceColor then
			color = distanceColor
		end
	end

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
		messageId = tostring(raw.messageId or (metadata and metadata.messageId) or ''),
		channel = channelId,
		label = label,
		color = color,
		args = args,
		template = raw.template,
		templateId = raw.templateId,
		multiline = raw.multiline ~= false,
		metadata = metadata,
		timestamp = tonumber(raw.timestamp) or os.time()
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
	State.TabGroupOrder = normalizeTabGroupOrder(Client.decodeJson(GetResourceKvpString(tabGroupOrderKvpKey)))
	State.TabGroupNames = normalizeTabGroupNames(Client.decodeJson(GetResourceKvpString(tabGroupNamesKvpKey)), State.TabGrouping)
	State.TabGroupDisplayMode = normalizeTabGroupDisplayMode(Client.decodeJson(GetResourceKvpString(tabGroupDisplayModeKvpKey)), State.TabGrouping)
	State.HiddenTabButtons = normalizeHiddenTabButtons(Client.decodeJson(GetResourceKvpString(hiddenTabButtonsKvpKey)), State.TabGrouping)

	local tabNotificationSaved = Client.decodeJson(GetResourceKvpString(tabNotificationKvpKey))
	State.TabNotificationToggles = normalizeTabNotificationToggles(tabNotificationSaved)
	ensureActiveChannelVisible()

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
	local function paramsFor(commandName)
		local name = Client.normalizeKey(commandName)
		if name == 'whisper' or name == 'w' or name == 'msg' or name == 'dm' then
			return {
				{name = 'player', help = 'Player server ID or name', type = 'player', required = true},
				{name = 'message', help = 'Message text', type = 'text', required = true}
			}
		end
		if name == 'reply' or name == 'r' then
			return {{name = 'message', help = 'Reply text', type = 'text', required = true}}
		end
		if name == 'report' then
			return {
				{name = 'player', help = 'Optional player server ID', type = 'player', required = false},
				{name = 'reason', help = 'Report reason', type = 'text', required = true}
			}
		end
		if name == 'mute' or name == 'unmute' then
			return {{name = 'player', help = 'Player server ID or name', type = 'player', required = true}}
		end
		if name == 'clearhistory' or name == 'clearhist' then
			return {{name = 'confirm', help = 'Type confirm to clear saved history', type = 'text', required = false}}
		end
		if name == 'global' or name == 'g' or name == 'say' or name == 'me' or name == 'do' or name == 'staff' or name == 'nick' then
			return {{name = 'message', help = 'Message text', type = 'text', required = true}}
		end
		return nil
	end
	for _, command in pairs(constants.commandByKey) do
		if command.enabled == true then
			suggestions[#suggestions + 1] = {
				'/' .. command.command,
				command.help ~= '' and command.help or ('Send a message in ' .. tostring(command.label)),
				paramsFor(command.command)
			}
			for i = 1, #command.aliases do
				suggestions[#suggestions + 1] = {
					'/' .. command.aliases[i],
					command.help ~= '' and command.help or ('Alias for /' .. command.command),
					paramsFor(command.aliases[i]) or paramsFor(command.command)
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
				help = '',
				params = command.params or command.arguments or {}
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

local function applyChannelDefinitions(rawChannels)
	if type(rawChannels) ~= 'table' then
		return false
	end

	local list = {}
	local byId = {}
	for i = 1, #rawChannels do
		local raw = type(rawChannels[i]) == 'table' and rawChannels[i] or nil
		local id = raw and Client.normalizeKey(raw.id)
		if id then
			local entry = {
				id = id,
				label = tostring(raw.label or id),
				color = raw.color,
				order = tonumber(raw.order) or 100,
				visible = raw.visible ~= false,
				cycle = raw.cycle ~= false,
				canSend = raw.canSend ~= false,
				maxHistory = normalizeLimit(raw.maxHistory or raw.history, 250),
				scope = Client.normalizeKey(raw.scope) or 'global',
				distance = tonumber(raw.distance)
			}
			list[#list + 1] = entry
			byId[id] = entry
		end
	end

	if #list == 0 then
		return false
	end

	table.sort(list, function(a, b)
		if a.order == b.order then
			return a.id < b.id
		end
		return a.order < b.order
	end)

	constants.channelList = list
	constants.channelById = byId
	if not byId[constants.defaultChannelId] then
		constants.defaultChannelId = byId.global and 'global' or list[1].id
	end
	return true
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

local function setTabGrouping(rawGrouping, rawOrder)
	if not ensureContext() then
		return {grouping = {}, order = {}}
	end

	State.TabGrouping = normalizeTabGrouping(rawGrouping)
	State.TabGroupOrder = normalizeTabGroupOrder(rawOrder)
	State.TabGroupNames = normalizeTabGroupNames(State.TabGroupNames, State.TabGrouping)
	State.TabGroupDisplayMode = normalizeTabGroupDisplayMode(State.TabGroupDisplayMode, State.TabGrouping)
	Client.encodeAndStore(tabGroupingKvpKey, State.TabGrouping)
	Client.encodeAndStore(tabGroupOrderKvpKey, State.TabGroupOrder)
	Client.encodeAndStore(tabGroupNamesKvpKey, State.TabGroupNames)
	Client.encodeAndStore(tabGroupDisplayModeKvpKey, State.TabGroupDisplayMode)
	State.HiddenTabButtons = normalizeHiddenTabButtons(State.HiddenTabButtons, State.TabGrouping)
	Client.encodeAndStore(hiddenTabButtonsKvpKey, State.HiddenTabButtons)
	ensureActiveChannelVisible()
	return {
		grouping = State.TabGrouping,
		order = State.TabGroupOrder,
		groupNames = State.TabGroupNames,
		groupDisplayMode = State.TabGroupDisplayMode
	}
end

local function setTabGroupSettings(rawNames, rawDisplayMode)
	if not ensureContext() then
		return {groupNames = {}, groupDisplayMode = {}}
	end

	State.TabGroupNames = normalizeTabGroupNames(rawNames, State.TabGrouping)
	State.TabGroupDisplayMode = normalizeTabGroupDisplayMode(rawDisplayMode, State.TabGrouping)
	Client.encodeAndStore(tabGroupNamesKvpKey, State.TabGroupNames)
	Client.encodeAndStore(tabGroupDisplayModeKvpKey, State.TabGroupDisplayMode)
	return {
		groupNames = State.TabGroupNames,
		groupDisplayMode = State.TabGroupDisplayMode
	}
end

local function setHiddenTabButton(channelId, hidden)
	if not ensureContext() then
		return {}
	end

	local normalizedChannelId = Client.normalizeKey(channelId)
	if not normalizedChannelId or not constants.channelById[normalizedChannelId] then
		return {}
	end

	if type(State.HiddenTabButtons) ~= 'table' then
		State.HiddenTabButtons = {}
	end

	if hidden == true and canHideTabButton(normalizedChannelId, State.TabGrouping) then
		State.HiddenTabButtons[normalizedChannelId] = true
	else
		State.HiddenTabButtons[normalizedChannelId] = nil
	end

	State.HiddenTabButtons = normalizeHiddenTabButtons(State.HiddenTabButtons, State.TabGrouping)
	Client.encodeAndStore(hiddenTabButtonsKvpKey, State.HiddenTabButtons)
	ensureActiveChannelVisible()

	return State.HiddenTabButtons
end

local function getHiddenTabButtons()
	if not ensureContext() then
		return {}
	end
	if type(State.HiddenTabButtons) ~= 'table' then
		State.HiddenTabButtons = {}
	end
	return State.HiddenTabButtons
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

	refreshEmbeddedRadioState()
	ensureEmbeddedRadioStateSynced()

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
			order = State.TabGroupOrder,
			groupNames = State.TabGroupNames or {},
			groupDisplayMode = State.TabGroupDisplayMode or {},
			defaultGrouping = buildDefaultTabGrouping(),
			groupRelayTargetByChannel = constants.tabGroupRelayTargetByChannel or {},
			pinnedByChannel = constants.tabPinnedByChannel or {},
			hidden = getHiddenTabButtons()
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
			channelEnabled = constants.whisperChannelEnabled == true,
			separateWhisperTab = isWhisperDedicatedTabActive(),
			fallbackChannel = constants.whisperFallbackChannelId or constants.defaultChannelId,
			playerListEnabled = constants.whisperPlayerListEnabled == true,
			notifications = {
				enabled = State.whisperSoundEnabled == true,
				allowToggle = State.whisperSoundToggleAllowed == true,
				volume = tonumber(constants.whisperNotificationVolume) or 0.65
			},
			sidebar = {
				enabled = true,
				collapsible = constants.whisperSidebarCollapsible == true,
				defaultCollapsed = constants.whisperSidebarDefaultCollapsed == true,
				showPlayerMeta = constants.whisperSidebarShowPlayerMeta ~= false
			}
		},
		emoji = {},
		emojiPanel = Client.getEmojiPanelData(),
		distance = State.distanceState,
		features = Client.getFeatureStatePayload(),
		radio = getEmbeddedRadioPayload(),
		permissions = State.Permissions,
		ui = {
			fadeTimeout = tonumber(config.ui.fadeTimeout) or 7000,
			suggestionLimit = math.max(1, tonumber(config.ui.suggestionLimit) or 5),
			style = config.ui.chatStyle or {},
			separateChannelTabs = constants.separateChannelTabs ~= false,
			singleChannelId = constants.singleChannelId or constants.defaultChannelId,
			autoScrollDefault = State.autoScrollEnabled == true,
			opacity = tonumber(GetResourceKvpString('poodlechat:uiOpacity')) or 88,
			fontFamily = tostring(GetResourceKvpString('poodlechat:fontFamily:v1') or 'inter'),
			fontScale = tonumber(GetResourceKvpString('poodlechat:fontScale:v1')) or 1.0,
			templates = config.ui.templates or {},
			defaultTemplateId = tostring(config.ui.defaultTemplateId or 'default'),
			defaultAltTemplateId = tostring(config.ui.defaultAltTemplateId or 'defaultAlt'),
			theme = type(config.ui.theme) == 'table' and config.ui.theme or {},
			messages = type(config.ui.messages) == 'table' and config.ui.messages or {},
			contextMenu = type(config.ui.contextMenu) == 'table' and config.ui.contextMenu or {},
			colorPicker = type(config.ui.colorPicker) == 'table' and config.ui.colorPicker or {},
			animations = type(config.ui.animations) == 'table' and config.ui.animations or {},
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
	if shouldSuppressEmbeddedRadioRelay(normalized) then
		return
	end

	local metadata = normalized.metadata or {}
	local license = metadata.license or message.license
	if isMutedLicense(license) then
		return
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

	if handler == 'scene' then
		TriggerServerEvent('poodlechat:sceneMessage', message)
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

		if isWhisperDedicatedTabActive() then
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
			if isWhisperDedicatedTabActive() then
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

	if handler == 'clearhistory' then
		local now = GetGameTimer()
		local confirm = Client.normalizeKey(args[1]) == 'confirm'
		if confirm and clearHistoryConfirmUntil > now then
			clearHistoryConfirmUntil = 0
			TriggerServerEvent('poodlechat:clearHistory')
			return
		end

		clearHistoryConfirmUntil = now + 30000
		local suffix = confirm and 'Confirmation expired. ' or ''
		sendChannelMessage({
			channel = constants.defaultChannelId,
			label = 'SYSTEM',
			color = {255, 211, 101},
			args = {'System', suffix .. 'Run /clearhistory confirm within 30 seconds to permanently clear your saved and session chat history.'},
			metadata = {
				type = 'system',
				subtype = 'clearHistoryConfirm'
			}
		})
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

		Client.sendNuiMessage({
			type = 'setChatHidden',
			hidden = State.HideChat
		})

		return
	end

	if handler == 'staff' then
		if message ~= '' then
			TriggerServerEvent('poodlechat:staffMessage', message)
		end
		return
	end

	if handler == 'report' then
		if State.Permissions
			and State.Permissions.moderation
			and State.Permissions.moderation.builtInReportsEnabled ~= true
		then
			sendSimpleError('The built-in report flow is disabled')
			return
		end

		local player = ''
		local reason = table.concat(args, ' ')
		if #args > 0 then
			local candidate = tostring(args[1] or '')
			if candidate:match('^%d+$') then
				player = candidate
				table.remove(args, 1)
				reason = table.concat(args, ' ')
			end
		end
		Client.sendNuiMessage({
			type = 'openReportModal',
			targetId = tostring(player),
			targetName = tostring(player),
			reason = reason
		})
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
		scene = true,
		whisper = true,
		reply = true,
		clear = true,
		clearhistory = true,
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
	refreshEmbeddedRadioState()

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
				authorSource = id,
				authorName = name,
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
					authorSource = id,
					authorName = name,
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
				authorSource = id,
				authorName = name,
				license = license
			}
		})
		end
	end)

	AddEventHandler('poodlechat:scene', function(id, license, name, message)
		if isMutedLicense(license) then
			return
		end

		if Client.isInProximity(id, State.SceneMessageDistance or State.ActionMessageDistance) then
			addEnvelopeToChat({
				channel = 'local',
				label = 'DO',
				color = State.SceneMessageColor or State.ActionMessageColor,
				args = {'DO', message},
				metadata = {
					type = 'scene',
					source = id,
					authorSource = id,
					authorName = name,
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
				authorSource = GetPlayerServerId(PlayerId()),
				authorName = GetPlayerName(PlayerId()),
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
				authorSource = id,
				authorName = name,
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
				source = id,
				authorSource = id,
				authorName = name
			}
		})
	end)

	AddEventHandler('7_radio:client:stateChanged', function(payload)
		if constants.radioIntegrationEnabled ~= true then
			return
		end

		local nextState = nil
		if isEmbeddedRadioResourceStarted() then
			nextState = refreshEmbeddedRadioState()
			if (type(nextState) ~= 'table' or not embeddedRadioStateHasFrequency(nextState)) and embeddedRadioStateHasFrequency(payload) then
				nextState = setEmbeddedRadioState(payload or {}, true)
			end
		else
			nextState = setEmbeddedRadioState(payload or {}, true)
		end

		if type(nextState) == 'table' then
			syncEmbeddedRadioStateToNui()
			if nextState.available ~= true or not embeddedRadioStateHasFrequency(nextState) then
				ensureEmbeddedRadioStateSynced()
			end
		end
	end)

	AddEventHandler('7_radio:client:messageReceived', function(payload)
		if constants.radioIntegrationEnabled ~= true then
			return
		end

		local normalizedMessage = appendEmbeddedRadioMessage(payload)
		if not normalizedMessage then
			return
		end

		if State.chatLoaded == true then
			Client.sendNuiMessage({
				type = 'radioMessage',
				message = normalizedMessage
			})
		end
	end)

	AddEventHandler('onClientResourceStart', function(resourceName)
		if constants.radioIntegrationEnabled ~= true then
			return
		end

		if normalizeResourceKey(resourceName) ~= normalizeResourceKey(resolveResourceName(constants.radioIntegrationResource or '7-radio')) then
			return
		end

		refreshEmbeddedRadioState()
		syncEmbeddedRadioStateToNui()
		ensureEmbeddedRadioStateSynced()
	end)

	AddEventHandler('onClientResourceStop', function(resourceName)
		if constants.radioIntegrationEnabled ~= true then
			return
		end

		if normalizeResourceKey(resourceName) ~= normalizeResourceKey(resolveResourceName(constants.radioIntegrationResource or '7-radio')) then
			return
		end

		preserveEmbeddedRadioAvailability(false)
		syncEmbeddedRadioStateToNui()
	end)

	AddEventHandler('poodlechat:setPermissions', function(permissions)
		if type(permissions) ~= 'table' then
			permissions = {}
		end

		if type(permissions.channels) ~= 'table' then
			permissions.channels = {}
		end

		if type(permissions.moderation) ~= 'table' then
			permissions.moderation = {}
		end

		applyChannelDefinitions(permissions.channelDefinitions)
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

	exports('GetEmbeddedRadioIntegration', function()
		if not ensureContext() then
			return {
				enabled = false,
				resource = '7-radio',
				channelId = 'radio'
			}
		end

		return {
			enabled = isEmbeddedRadioTabActive(),
			resource = resolveResourceName(constants.radioIntegrationResource or '7-radio') or tostring(constants.radioIntegrationResource or '7-radio'),
			channelId = Client.normalizeKey(constants.radioIntegrationChannelId) or 'radio'
		}
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
Client.setTabGroupSettings = setTabGroupSettings
Client.setHiddenTabButton = setHiddenTabButton
Client.getHiddenTabButtons = getHiddenTabButtons
Client.setTabNotificationToggle = setTabNotificationToggle
Client.getTabNotificationToggles = getTabNotificationToggles
Client.getEmbeddedRadioPayload = getEmbeddedRadioPayload
Client.refreshEmbeddedRadioState = refreshEmbeddedRadioState
Client.ensureEmbeddedRadioStateSynced = ensureEmbeddedRadioStateSynced
Client.sendEmbeddedRadioMessage = sendEmbeddedRadioMessage
Client.registerChatHandlers = registerChatHandlers
