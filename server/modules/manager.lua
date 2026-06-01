local Server = PoodleChatServer

local managerInitialized = false
local requestRate = {}
local reportSequence = 0

local function trim(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeKey(value)
	if type(Server.normalizeKey) == 'function' then
		return Server.normalizeKey(value)
	end
	local text = trim(value):lower()
	return text ~= '' and text or nil
end

local function isManager(source)
	return Server.hasManagerPermission and Server.hasManagerPermission(source)
end

local function isStaff(source)
	return (Server.hasModerationPermission and Server.hasModerationPermission(source, 'staff')) or isManager(source)
end

local function denied()
	return {ok = false, reason = 'forbidden'}
end

local function reasonWhenFailed(ok, value)
	if ok == true then
		return nil
	end
	return value
end

local function getReportsStore()
	local store = type(Server.getRuntimeStore) == 'function' and Server.getRuntimeStore('reports') or nil
	if type(store) ~= 'table' then
		return {items = {}}
	end
	if type(store.items) ~= 'table' then
		store.items = {}
	end
	return store
end

local function actorSnapshot(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return {
			source = 0,
			name = 'console'
		}
	end
	return {
		source = src,
		name = tostring((Server.getName and Server.getName(src)) or GetPlayerName(src) or src),
		realName = tostring((Server.getRealName and Server.getRealName(src)) or GetPlayerName(src) or src),
		citizenid = tostring((Server.getCurrentCitizenId and Server.getCurrentCitizenId(src)) or ''),
		discord = tostring((Server.getIdFromSource and Server.getIdFromSource('discord', src)) or ''),
		license = tostring((Server.getIdFromSource and Server.constants and Server.getIdFromSource(Server.constants.IdentifierType, src)) or ''),
		identifier = tostring((Server.getIdFromSource and Server.constants and Server.getIdFromSource(Server.constants.IdentifierType, src)) or '')
	}
end

local function getOnlinePlayersForManager()
	local players = {}
	for _, playerId in ipairs(GetPlayers()) do
		local src = tonumber(playerId) or playerId
		local snapshot = actorSnapshot(src)
		snapshot.serverId = src
		players[#players + 1] = snapshot
	end
	table.sort(players, function(a, b)
		return (tonumber(a.source) or 0) < (tonumber(b.source) or 0)
	end)
	return players
end

local function recordReport(source, targetSnapshot, reason, context, attemptedTarget)
	reportSequence = reportSequence + 1
	local store = getReportsStore()
	local item = {
		id = ('report:%d:%d'):format(os.time(), reportSequence),
		status = 'open',
		reason = trim(reason),
		reporter = actorSnapshot(source),
		target = type(targetSnapshot) == 'table' and targetSnapshot or nil,
		targetInput = trim(attemptedTarget),
		context = type(context) == 'table' and context or nil,
		notes = {},
		createdAt = os.time(),
		updatedAt = os.time()
	}
	store.items[#store.items + 1] = item

	local maxReports = 300
	local managerConfig = type((Config or {}).manager) == 'table' and Config.manager or {}
	local moderationConfig = type(managerConfig.moderation) == 'table' and managerConfig.moderation or {}
	maxReports = math.max(25, tonumber(moderationConfig.maxReports) or maxReports)
	while #store.items > maxReports do
		table.remove(store.items, 1)
	end

	if Server.saveRuntimeStore then
		Server.saveRuntimeStore('reports', source)
	end
	if Server.appendAuditLog then
		Server.appendAuditLog(source, 'report.create', {reportId = item.id, targetInput = item.targetInput})
	end
	return item
end

local function getReports(limit, status)
	local max = math.max(1, math.min(tonumber(limit) or 100, 300))
	local normalizedStatus = normalizeKey(status)
	local items = getReportsStore().items
	local result = {}
	for i = #items, 1, -1 do
		local report = items[i]
		if type(report) == 'table' and (not normalizedStatus or normalizeKey(report.status) == normalizedStatus) then
			result[#result + 1] = report
			if #result >= max then
				break
			end
		end
	end
	return result
end

local function updateReport(actor, payload)
	local data = type(payload) == 'table' and payload or {}
	local reportId = trim(data.reportId or data.id)
	if reportId == '' then
		return false, 'invalid_report'
	end

	local status = normalizeKey(data.status)
	local allowedStatuses = {open = true, handled = true, closed = true}
	if status and not allowedStatuses[status] then
		return false, 'invalid_status'
	end

	local store = getReportsStore()
	for i = 1, #store.items do
		local report = store.items[i]
		if type(report) == 'table' and report.id == reportId then
			if status then
				report.status = status
			end
			local note = trim(data.note)
			if note ~= '' then
				if type(report.notes) ~= 'table' then
					report.notes = {}
				end
				report.notes[#report.notes + 1] = {
					text = note,
					actor = actorSnapshot(actor),
					createdAt = os.time()
				}
			end
			report.updatedAt = os.time()
			report.updatedBy = actorSnapshot(actor)
			Server.saveRuntimeStore('reports', actor)
			if Server.appendAuditLog then
				Server.appendAuditLog(actor, 'report.update', {reportId = reportId, status = status, note = note ~= ''})
			end
			return true, report
		end
	end

	return false, 'not_found'
end

local function getRecentMessages(limit, channel)
	local max = math.max(1, math.min(tonumber(limit) or 100, 250))
	local normalizedChannel = normalizeKey(channel)
	local registry = Server.state and Server.state.liveMessageRegistry or {}
	local result = {}
	for _, record in pairs(registry) do
		local envelope = type(record) == 'table' and record.envelope or nil
		if type(envelope) == 'table' and (not normalizedChannel or normalizeKey(envelope.channel) == normalizedChannel) then
			result[#result + 1] = envelope
		end
	end
	table.sort(result, function(a, b)
		return tonumber(a.timestamp) or 0 > (tonumber(b.timestamp) or 0)
	end)
	while #result > max do
		table.remove(result)
	end
	return result
end

local function getIntegrationWarnings()
	local warnings = {}
	local config = type(Config) == 'table' and Config or {}
	local voice = type(config.voice) == 'table' and config.voice or {}
	if voice.enabled == true and GetResourceState(tostring(voice.resource or 'pma-voice')) ~= 'started' then
		warnings[#warnings + 1] = {
			id = 'pma-voice-missing',
			severity = 'warning',
			text = ('%s is not started. Voice range labels will use fallback data.'):format(tostring(voice.resource or 'pma-voice'))
		}
	end

	local integrations = type(config.integrations) == 'table' and config.integrations or {}
	local radio = type(integrations.radio) == 'table' and integrations.radio or {}
	if radio.enabled == true and GetResourceState(tostring(radio.resource or '7-Radio')) ~= 'started' then
		warnings[#warnings + 1] = {
			id = 'radio-missing',
			severity = 'info',
			text = ('%s is not started. Embedded radio chat will show unavailable.'):format(tostring(radio.resource or '7-Radio'))
		}
	end
	return warnings
end

local function buildChannelsPayload(source)
	local result = {}
	local constants = Server.constants or {}
	for i = 1, #(constants.ChannelList or {}) do
		local channel = constants.ChannelList[i]
		if channel then
			result[#result + 1] = {
				id = channel.id,
				label = channel.label,
				color = channel.color,
				order = channel.order,
				visible = channel.visible ~= false,
				cycle = channel.cycle ~= false,
				canSend = channel.canSend ~= false,
				requiresAce = channel.requiresAce,
				allowed = Server.canAccessChannel and Server.canAccessChannel(source, channel.id) or true
			}
		end
	end
	return result
end

local function getBootstrap(source)
	local permissions = Server.getResolvedPlayerPermissions and Server.getResolvedPlayerPermissions(source) or {}
	return {
		ok = true,
		serverTime = os.time(),
		resource = GetCurrentResourceName(),
		permissions = permissions,
		channels = buildChannelsPayload(source),
		commandPolicy = Server.getClientCommandPolicy and Server.getClientCommandPolicy(source) or {},
		runtime = Server.getPublicRuntimeSummary and Server.getPublicRuntimeSummary() or {},
		warnings = getIntegrationWarnings(),
		players = isManager(source) and getOnlinePlayersForManager() or {},
		recentReports = isStaff(source) and getReports(8) or {},
		recentAudit = isManager(source) and (Server.getAuditLog and Server.getAuditLog(8) or {}) or {}
	}
end

local function getAdminState(source)
	if not isManager(source) then
		return denied()
	end

	return {
		ok = true,
		runtimeConfig = Server.getRuntimeStore('runtimeConfig'),
		runtimeAcl = Server.getRuntimeStore('runtimeAcl'),
		commandBlocks = Server.getRuntimeStore('commandBlocks'),
		commandRoutes = Server.getRuntimeStore('commandRoutes'),
		customCommands = Server.getRuntimeStore('customCommands'),
		autoMessages = Server.getAutoMessages and Server.getAutoMessages() or {},
		commandRegistry = Server.buildCommandRegistry and Server.buildCommandRegistry(source) or {},
		reports = getReports(100),
		audit = Server.getAuditLog and Server.getAuditLog(100) or {},
		recentMessages = getRecentMessages(100),
		players = getOnlinePlayersForManager(),
		warnings = getIntegrationWarnings()
	}
end

local function updateRuntimeConfig(source, payload)
	if not isManager(source) then
		return denied()
	end

	local data = type(payload) == 'table' and payload or {}
	if data.aclAction then
		local acl = type(data.aclAction) == 'table' and data.aclAction or {}
		local ok, reason
		if acl.action == 'remove' then
			ok, reason = Server.removeRuntimeAclEntry(acl.kind, acl.capability, acl.entry, source)
		else
			ok, reason = Server.addRuntimeAclEntry(acl.kind, acl.capability, acl.entry, source)
		end
		if ok == true and Server.syncAllPermissions then
			Server.syncAllPermissions()
		end
		return {ok = ok == true, reason = reason, runtimeAcl = Server.getRuntimeStore('runtimeAcl')}
	end

	local storeName = trim(data.store)
	local allowedStores = {
		runtimeConfig = true,
		runtimeAcl = true,
		commandRoutes = true,
		commandRegistry = true
	}
	if not allowedStores[storeName] then
		storeName = 'runtimeConfig'
	end

	local value = type(data.value) == 'table' and data.value or {}
	local ok, reason = Server.replaceRuntimeStore(storeName, value, source)
	if ok and storeName == 'runtimeConfig' and Server.applyRuntimeChannelConfig then
		Server.applyRuntimeChannelConfig()
		if Server.syncAllPermissions then
			Server.syncAllPermissions()
		end
	end
	if ok and Server.appendAuditLog then
		Server.appendAuditLog(source, 'runtime.update', {store = storeName})
	end
	return {ok = ok == true, reason = reason, [storeName] = Server.getRuntimeStore(storeName)}
end

local function getModeration(source, payload)
	if not isStaff(source) then
		return denied()
	end
	local data = type(payload) == 'table' and payload or {}
	return {
		ok = true,
		reports = getReports(data.limit or 100, data.status),
		audit = Server.getAuditLog and Server.getAuditLog(data.auditLimit or 100, data.query) or {},
		recentMessages = getRecentMessages(data.messageLimit or 100, data.channel)
	}
end

local function moderationAction(source, payload)
	if not isStaff(source) then
		return denied()
	end

	local data = type(payload) == 'table' and payload or {}
	local action = normalizeKey(data.action)
	if action == 'updatereport' then
		local ok, result = updateReport(source, data)
		return {ok = ok == true, reason = reasonWhenFailed(ok, result), report = ok and result or nil}
	end
	if action == 'deletemessage' and Server.deleteMessageById then
		return {ok = Server.deleteMessageById(source, data.messageId) == true}
	end
	return {ok = false, reason = 'invalid_action'}
end

local function getNicknameState(source)
	return {
		ok = true,
		nicknameState = {
			nickname = Server.getNickname and Server.getNickname(source) or '',
			history = Server.getNicknameHistory and Server.getNicknameHistory(source) or {},
			pinned = Server.getPinnedNicknames and Server.getPinnedNicknames(source) or {},
			maxPinned = 5,
			canUse = true
		}
	}
end

local function setManagerNickname(source, payload)
	local data = type(payload) == 'table' and payload or {}
	local nickname = trim(data.nickname)
	if nickname == '' then
		nickname = nil
	end
	if nickname and Server.constants and string.len(nickname) > tonumber(Server.constants.MaxNicknameLen or 40) then
		return {ok = false, reason = 'too_long'}
	end
	local ok, reason = false, 'not_ready'
	if Server.setNickname then
		ok, reason = Server.setNickname(source, nickname)
	end
	if ok and Server.updateCharacterDirectoryEntry then
		Server.updateCharacterDirectoryEntry(source)
	end
	if ok and Server.refreshIdentityState then
		Server.refreshIdentityState(source)
	end
	if ok ~= true then
		return {ok = false, reason = reason or 'failed'}
	end
	return getNicknameState(source)
end

local function pinManagerNickname(source, payload)
	local data = type(payload) == 'table' and payload or {}
	local nickname = trim(data.nickname)
	if nickname == '' then
		return {ok = false, reason = 'invalid_nickname'}
	end
	local ok, reason
	if data.pinned == false then
		if Server.unpinNickname then
			ok, reason = Server.unpinNickname(source, nickname)
		else
			ok, reason = false, 'not_ready'
		end
	else
		if Server.pinNickname then
			ok, reason = Server.pinNickname(source, nickname)
		else
			ok, reason = false, 'not_ready'
		end
	end
	if ok ~= true then
		return {ok = false, reason = reason or 'failed'}
	end
	return getNicknameState(source)
end

local handlers = {
	managerGetBootstrap = function(source)
		return getBootstrap(source)
	end,
	managerGetNicknameState = getNicknameState,
	managerSetNickname = setManagerNickname,
	managerPinNickname = pinManagerNickname,
	managerGetAdminState = function(source)
		return getAdminState(source)
	end,
	managerUpdateRuntimeConfig = updateRuntimeConfig,
	managerGetCommandRegistry = function(source)
		if not isManager(source) then
			return denied()
		end
		return {ok = true, registry = Server.buildCommandRegistry and Server.buildCommandRegistry(source) or {}}
	end,
	managerUpdateCommandRoute = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local data = type(payload) == 'table' and payload or {}
		local ok, result
		if data.delete == true then
			ok, result = Server.deleteCommandRoute(source, data.command)
		else
			ok, result = Server.saveCommandRoute(source, data)
		end
		return {ok = ok == true, reason = reasonWhenFailed(ok, result), route = ok and result or nil, commandRoutes = Server.getRuntimeStore('commandRoutes')}
	end,
	managerUpdateCommandBlock = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local data = type(payload) == 'table' and payload or {}
		local ok, result
		if data.delete == true then
			ok, result = Server.deleteCommandBlock(source, data.command)
		else
			ok, result = Server.saveCommandBlock(source, data)
		end
		return {ok = ok == true, reason = reasonWhenFailed(ok, result), block = ok and result or nil, commandBlocks = Server.getRuntimeStore('commandBlocks')}
	end,
	managerSaveCustomCommand = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local ok, result = Server.saveCustomCommand(source, payload)
		return {ok = ok == true, reason = reasonWhenFailed(ok, result), command = ok and result or nil, customCommands = Server.getRuntimeStore('customCommands')}
	end,
	managerDeleteCustomCommand = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local data = type(payload) == 'table' and payload or {}
		local ok, reason = Server.deleteCustomCommand(source, data.command or data.name)
		return {ok = ok == true, reason = reason, customCommands = Server.getRuntimeStore('customCommands')}
	end,
	managerGetModeration = getModeration,
	managerModerationAction = moderationAction,
	managerGetAutoMessages = function(source)
		if not isManager(source) then
			return denied()
		end
		return {ok = true, autoMessages = Server.getAutoMessages and Server.getAutoMessages() or {}}
	end,
	managerSaveAutoMessage = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local ok, result = Server.saveAutoMessage(source, payload)
		return {ok = ok == true, reason = reasonWhenFailed(ok, result), autoMessage = ok and result or nil, autoMessages = Server.getAutoMessages()}
	end,
	managerDeleteAutoMessage = function(source, payload)
		if not isManager(source) then
			return denied()
		end
		local data = type(payload) == 'table' and payload or {}
		local ok, reason = Server.deleteAutoMessage(source, data.id)
		return {ok = ok == true, reason = reason, autoMessages = Server.getAutoMessages()}
	end
}

local readOnlyActions = {
	managerGetBootstrap = true,
	managerGetNicknameState = true,
	managerGetAdminState = true,
	managerGetCommandRegistry = true,
	managerGetModeration = true,
	managerGetAutoMessages = true
}

local function handleManagerRequest(source, requestId, action, payload)
	local id = trim(requestId)
	local actionName = trim(action)
	local handler = handlers[actionName]
	if id == '' then
		return
	end
	if not handler then
		TriggerClientEvent('poodlechat:manager:response', source, id, {ok = false, reason = 'unknown_action'})
		return
	end

	local now = GetGameTimer()
	local last = tonumber(requestRate[source]) or 0
	if readOnlyActions[actionName] ~= true and now - last < 150 then
		TriggerClientEvent('poodlechat:manager:response', source, id, {ok = false, reason = 'rate_limited'})
		return
	end
	if readOnlyActions[actionName] ~= true then
		requestRate[source] = now
	end

	local ok, result = pcall(handler, source, payload)
	if not ok then
		if Server.log then
			Server.log('error', ('Manager action failed (%s): %s'):format(tostring(action), tostring(result)))
		end
		result = {ok = false, reason = 'server_error'}
	end
	TriggerClientEvent('poodlechat:manager:response', source, id, result or {ok = true})
end

local function setupManager()
	if managerInitialized then
		return
	end

	Server.recordReport = recordReport
	Server.getManagerReports = getReports
	Server.updateManagerReport = updateReport
	Server.getRecentMessagesForManager = getRecentMessages
	Server.handleManagerRequest = handleManagerRequest

	AddEventHandler('poodlechat:manager:request', function(requestId, action, payload)
		handleManagerRequest(source, requestId, action, payload)
	end)

	managerInitialized = true
end

Server.setupManager = setupManager
