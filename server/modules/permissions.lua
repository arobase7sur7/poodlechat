local Server = PoodleChatServer

local permissionsInitialized = false
local baseCanAccessChannel = nil
local baseHasModerationPermission = nil
local baseGetResolvedPlayerPermissions = nil

local function normalizeKey(value)
	if type(Server.normalizeKey) == 'function' then
		return Server.normalizeKey(value)
	end

	if type(value) ~= 'string' then
		return nil
	end

	local normalized = value:lower():gsub('^%s+', ''):gsub('%s+$', '')
	return normalized ~= '' and normalized or nil
end

local function trim(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getAclStore()
	local store = type(Server.getRuntimeStore) == 'function' and Server.getRuntimeStore('runtimeAcl') or nil
	if type(store) ~= 'table' then
		return {allow = {}, deny = {}}
	end

	if type(store.allow) ~= 'table' then
		store.allow = {}
	end
	if type(store.deny) ~= 'table' then
		store.deny = {}
	end

	return store
end

local function buildSubjectSet(source)
	local subjects = {}

	local function add(value)
		local normalized = trim(value):lower()
		if normalized ~= '' then
			subjects[normalized] = true
		end
	end

	local src = tonumber(source)
	if src then
		add('source:' .. src)
		local name = GetPlayerName(src)
		if name then
			add('name:' .. name)
		end
		if type(Server.getName) == 'function' then
			add('chatname:' .. tostring(Server.getName(src) or ''))
			add('displayname:' .. tostring(Server.getName(src) or ''))
		end
		if type(Server.getCurrentCitizenId) == 'function' then
			local citizenid = trim(Server.getCurrentCitizenId(src))
			if citizenid ~= '' then
				add('citizenid:' .. citizenid)
				add('character:' .. citizenid)
			end
		end

		local identifiers = GetPlayerIdentifiers(src)
		for i = 1, #identifiers do
			local identifier = tostring(identifiers[i])
			add(identifier)
			local idType, idValue = identifier:match('^([^:]+):(.+)$')
			if idType and idValue then
				add(('identifier.%s:%s'):format(idType, idValue))
				add(('%s:%s'):format(idType, idValue))
			end
		end
	end

	return subjects
end

local function entryMatches(source, entry, capability)
	local raw = trim(entry)
	if raw == '' then
		return false
	end

	local lowered = raw:lower()
	local subjects = buildSubjectSet(source)
	if subjects[lowered] then
		return true
	end

	local ace = lowered:match('^ace:(.+)$')
	if ace and IsPlayerAceAllowed(source, ace) then
		return true
	end

	if lowered == '*' or lowered == 'all' then
		return true
	end

	local capabilityValue = lowered:match('^capability:(.+)$')
	return capabilityValue ~= nil and capabilityValue == capability
end

local function getCapabilityList(bucket, capability)
	local normalized = normalizeKey(capability)
	if not normalized then
		return {}
	end

	local entries = bucket[normalized]
	if type(entries) ~= 'table' then
		return {}
	end

	return entries
end

local function getRuntimeAclDecision(source, capability)
	local normalized = normalizeKey(capability)
	if not normalized then
		return nil
	end

	local store = getAclStore()
	local deny = getCapabilityList(store.deny, normalized)
	for i = 1, #deny do
		if entryMatches(source, deny[i], normalized) then
			return false
		end
	end

	local allow = getCapabilityList(store.allow, normalized)
	for i = 1, #allow do
		if entryMatches(source, allow[i], normalized) then
			return true
		end
	end

	return nil
end

local function addRuntimeAclEntry(kind, capability, entry, actor)
	local normalizedKind = normalizeKey(kind)
	local normalizedCapability = normalizeKey(capability)
	local value = trim(entry)
	if normalizedKind ~= 'allow' and normalizedKind ~= 'deny' then
		return false, 'invalid_kind'
	end
	if not normalizedCapability or value == '' then
		return false, 'invalid_entry'
	end

	local store = getAclStore()
	local bucket = store[normalizedKind]
	if type(bucket[normalizedCapability]) ~= 'table' then
		bucket[normalizedCapability] = {}
	end

	for i = 1, #bucket[normalizedCapability] do
		if trim(bucket[normalizedCapability][i]):lower() == value:lower() then
			return true
		end
	end

	bucket[normalizedCapability][#bucket[normalizedCapability] + 1] = value
	Server.saveRuntimeStore('runtimeAcl', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'permission.change', {
			action = 'add',
			kind = normalizedKind,
			capability = normalizedCapability,
			entry = value
		})
	end
	if Server.syncAllPermissions then
		Server.syncAllPermissions()
	end
	return true
end

local function removeRuntimeAclEntry(kind, capability, entry, actor)
	local normalizedKind = normalizeKey(kind)
	local normalizedCapability = normalizeKey(capability)
	local value = trim(entry)
	if normalizedKind ~= 'allow' and normalizedKind ~= 'deny' then
		return false, 'invalid_kind'
	end
	if not normalizedCapability or value == '' then
		return false, 'invalid_entry'
	end

	local store = getAclStore()
	local bucket = store[normalizedKind]
	local list = type(bucket[normalizedCapability]) == 'table' and bucket[normalizedCapability] or {}
	local nextList = {}
	local changed = false

	for i = 1, #list do
		if trim(list[i]):lower() == value:lower() then
			changed = true
		else
			nextList[#nextList + 1] = list[i]
		end
	end

	if not changed then
		return true
	end

	if #nextList == 0 then
		bucket[normalizedCapability] = nil
	else
		bucket[normalizedCapability] = nextList
	end

	Server.saveRuntimeStore('runtimeAcl', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'permission.change', {
			action = 'remove',
			kind = normalizedKind,
			capability = normalizedCapability,
			entry = value
		})
	end
	if Server.syncAllPermissions then
		Server.syncAllPermissions()
	end
	return true
end

local function hasRuntimePermission(source, capability, fallback)
	local decision = getRuntimeAclDecision(source, capability)
	if decision ~= nil then
		return decision
	end

	if type(fallback) == 'function' then
		return fallback()
	end

	return fallback == true
end

local function hasRuntimePermissionAny(source, capabilities, fallback)
	local list = type(capabilities) == 'table' and capabilities or {capabilities}
	for i = 1, #list do
		local decision = getRuntimeAclDecision(source, list[i])
		if decision ~= nil then
			return decision
		end
	end

	if type(fallback) == 'function' then
		return fallback()
	end

	return fallback == true
end

local function hasManagerPermission(source)
	return hasRuntimePermissionAny(source, {'chat.manager', 'manager'}, function()
		if IsPlayerAceAllowed(source, 'chat.manager') then
			return true
		end
		if baseHasModerationPermission and baseHasModerationPermission(source, 'staff') then
			return true
		end
		return false
	end)
end

local function hasModerationPermission(source, capability)
	local normalized = normalizeKey(capability)
	if not normalized then
		return false
	end

	local aliases = {
		staff = {'chat.staffchannel', 'staff'},
		delete = {'chat.deletemessage', 'delete'},
		viewdeleted = {'chat.viewdeletedmessage', 'chat.deletemessage', 'viewdeleted'},
		nomute = {'chat.nomute', 'nomute'}
	}
	local capabilities = aliases[normalized] or {normalized}

	return hasRuntimePermissionAny(source, capabilities, function()
		if baseHasModerationPermission then
			return baseHasModerationPermission(source, normalized)
		end
		return false
	end)
end

local function canAccessChannel(source, channelId)
	local normalizedChannel = normalizeKey(channelId)
	if not normalizedChannel then
		return false
	end

	return hasRuntimePermission(source, 'channel:' .. normalizedChannel, function()
		if normalizedChannel == 'staff' then
			local staffDecision = getRuntimeAclDecision(source, 'staff')
			if staffDecision ~= nil then
				return staffDecision
			end
			local aceStaffDecision = getRuntimeAclDecision(source, 'chat.staffChannel')
			if aceStaffDecision ~= nil then
				return aceStaffDecision
			end
		end

		if baseCanAccessChannel then
			return baseCanAccessChannel(source, normalizedChannel)
		end
		return false
	end)
end

local function getResolvedPlayerPermissions(source)
	local resolved = baseGetResolvedPlayerPermissions and baseGetResolvedPlayerPermissions(source) or {channels = {}, moderation = {}}
	if type(resolved.channels) ~= 'table' then
		resolved.channels = {}
	end
	if type(resolved.moderation) ~= 'table' then
		resolved.moderation = {}
	end

	local constants = Server.constants or {}
	local channels = constants.ChannelList or {}
	for i = 1, #channels do
		local channel = channels[i]
		if channel and channel.id then
			resolved.channels[channel.id] = canAccessChannel(source, channel.id)
		end
	end

	resolved.canManagePoodleChat = hasManagerPermission(source)
	resolved.manager = resolved.canManagePoodleChat
	resolved.staff = hasModerationPermission(source, 'staff')
	resolved.capabilities = type(resolved.capabilities) == 'table' and resolved.capabilities or {}
	resolved.capabilities['chat.manager'] = resolved.canManagePoodleChat
	resolved.capabilities['chat.staffChannel'] = resolved.staff
	resolved.capabilities['chat.deleteMessage'] = hasModerationPermission(source, 'delete')
	resolved.capabilities['chat.noMute'] = hasModerationPermission(source, 'nomute')
	resolved.moderation.canAccessStaff = resolved.staff
	resolved.moderation.canDeleteMessages = resolved.capabilities['chat.deleteMessage']
	resolved.moderation.canViewDeletedMessages = hasModerationPermission(source, 'viewdeleted')
	resolved.moderation.canManagePoodleChat = resolved.canManagePoodleChat
	return resolved
end

local function setupPermissions()
	if permissionsInitialized then
		return
	end

	baseCanAccessChannel = Server.canAccessChannel
	baseHasModerationPermission = Server.hasModerationPermission
	baseGetResolvedPlayerPermissions = Server.getResolvedPlayerPermissions

	Server.getRuntimeAclDecision = getRuntimeAclDecision
	Server.hasRuntimePermission = hasRuntimePermission
	Server.hasRuntimePermissionAny = hasRuntimePermissionAny
	Server.hasManagerPermission = hasManagerPermission
	Server.hasModerationPermission = hasModerationPermission
	Server.canAccessChannel = canAccessChannel
	Server.getResolvedPlayerPermissions = getResolvedPlayerPermissions
	Server.addRuntimeAclEntry = addRuntimeAclEntry
	Server.removeRuntimeAclEntry = removeRuntimeAclEntry

	permissionsInitialized = true
end

Server.setupPermissions = setupPermissions
