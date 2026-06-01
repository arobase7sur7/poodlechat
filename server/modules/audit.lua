local Server = PoodleChatServer

local auditInitialized = false
local auditSequence = 0

local function trim(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getAuditConfig()
	local config = type(Config) == 'table' and Config or {}
	local manager = type(config.manager) == 'table' and config.manager or {}
	local audit = type(manager.audit) == 'table' and manager.audit or {}
	return {
		maxEntries = math.max(25, tonumber(audit.maxEntries) or 500)
	}
end

local function getStore()
	local store = type(Server.getRuntimeStore) == 'function' and Server.getRuntimeStore('auditLog') or nil
	if type(store) ~= 'table' then
		return {entries = {}}
	end
	if type(store.entries) ~= 'table' then
		store.entries = {}
	end
	return store
end

local function actorSnapshot(source)
	local src = tonumber(source)
	if not src or src <= 0 then
		return {
			source = 0,
			name = 'console',
			identifier = 'console'
		}
	end

	return {
		source = src,
		name = tostring((Server.getName and Server.getName(src)) or GetPlayerName(src) or src),
		identifier = tostring((Server.getIdFromSource and Server.constants and Server.getIdFromSource(Server.constants.IdentifierType, src)) or '')
	}
end

local function appendAuditLog(actorSource, action, details)
	local normalizedAction = trim(action)
	if normalizedAction == '' then
		return false
	end

	auditSequence = auditSequence + 1
	local store = getStore()
	local entries = store.entries
	entries[#entries + 1] = {
		id = ('audit:%d:%d'):format(os.time(), auditSequence),
		action = normalizedAction,
		actor = actorSnapshot(actorSource),
		details = type(details) == 'table' and details or {},
		createdAt = os.time()
	}

	local maxEntries = getAuditConfig().maxEntries
	while #entries > maxEntries do
		table.remove(entries, 1)
	end

	if type(Server.saveRuntimeStore) == 'function' then
		Server.saveRuntimeStore('auditLog', actorSource)
	end
	return true
end

local function getAuditLog(limit, query)
	local entries = getStore().entries
	local normalizedQuery = trim(query):lower()
	local max = math.max(1, math.min(tonumber(limit) or 100, 300))
	local result = {}

	for i = #entries, 1, -1 do
		local entry = entries[i]
		if type(entry) == 'table' then
			local include = true
			if normalizedQuery ~= '' then
				local blob = json.encode(entry):lower()
				include = blob:find(normalizedQuery, 1, true) ~= nil
			end
			if include then
				result[#result + 1] = entry
				if #result >= max then
					break
				end
			end
		end
	end

	return result
end

local function setupAudit()
	if auditInitialized then
		return
	end

	if type(Server.getRuntimeStore) == 'function' then
		getStore()
	end

	Server.appendAuditLog = appendAuditLog
	Server.getAuditLog = getAuditLog
	auditInitialized = true
end

Server.setupAudit = setupAudit
