local Server = PoodleChatServer

local storeLoaded = false

local storeDefinitions = {
	runtimeConfig = {
		key = 'poodlechat:runtimeConfig:v1',
		default = {
			version = 1,
			channels = {},
			settings = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	runtimeAcl = {
		key = 'poodlechat:runtimeAcl:v1',
		default = {
			version = 1,
			allow = {},
			deny = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	commandRegistry = {
		key = 'poodlechat:commandRegistry:v1',
		default = {
			version = 1,
			notes = {},
			enabled = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	commandBlocks = {
		key = 'poodlechat:commandBlocks:v1',
		default = {
			version = 1,
			entries = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	commandRoutes = {
		key = 'poodlechat:commandRoutes:v1',
		default = {
			version = 1,
			overrides = {},
			inboundMessageRules = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	customCommands = {
		key = 'poodlechat:customCommands:v1',
		default = {
			version = 1,
			entries = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	autoMessages = {
		key = 'poodlechat:autoMessages:v1',
		default = {
			version = 1,
			items = {},
			updatedAt = 0,
			updatedBy = nil
		}
	},
	auditLog = {
		key = 'poodlechat:auditLog:v1',
		default = {
			version = 1,
			entries = {}
		}
	},
	reports = {
		key = 'poodlechat:reports:v1',
		default = {
			version = 1,
			items = {}
		}
	}
}

local function clone(value, seen)
	if type(value) ~= 'table' then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy
	for key, entry in pairs(value) do
		copy[clone(key, seen)] = clone(entry, seen)
	end
	return copy
end

local function tableCount(value)
	if type(value) ~= 'table' then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count
end

local function normalizeStoreShape(name, value)
	local definition = storeDefinitions[name]
	local fallback = clone(definition.default)
	local source = type(value) == 'table' and value or {}

	for key, entry in pairs(source) do
		fallback[key] = entry
	end

	fallback.version = tonumber(fallback.version) or 1
	return fallback
end

local function decodeKvpStore(name)
	local definition = storeDefinitions[name]
	if not definition then
		return {}
	end

	local raw = GetResourceKvpString(definition.key)
	if not raw or raw == '' then
		return clone(definition.default)
	end

	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= 'table' then
		if Server.log then
			Server.log('warning', ('Invalid runtime KVP %s; using defaults.'):format(definition.key))
		end
		return clone(definition.default)
	end

	return normalizeStoreShape(name, decoded)
end

local function encodeKvpStore(name, value)
	local definition = storeDefinitions[name]
	if not definition then
		return false, 'unknown_store'
	end

	local ok, encoded = pcall(json.encode, normalizeStoreShape(name, value))
	if not ok or type(encoded) ~= 'string' or encoded == '' then
		return false, 'encode_failed'
	end

	local stored, err = pcall(SetResourceKvp, definition.key, encoded)
	if not stored then
		return false, tostring(err or 'store_failed')
	end

	return true
end

local function ensureRuntimeStore()
	if storeLoaded then
		return Server.runtimeStore
	end

	local runtimeStore = {}
	for name in pairs(storeDefinitions) do
		runtimeStore[name] = decodeKvpStore(name)
	end

	Server.runtimeStore = runtimeStore
	storeLoaded = true
	return runtimeStore
end

local function touchStore(name, actor)
	local store = ensureRuntimeStore()[name]
	if type(store) ~= 'table' then
		return
	end

	store.updatedAt = os.time()
	if actor ~= nil then
		store.updatedBy = actor
	end
end

local function getStore(name)
	return ensureRuntimeStore()[name]
end

local function replaceStore(name, value, actor)
	local definition = storeDefinitions[name]
	if not definition then
		return false, 'unknown_store'
	end

	local normalized = normalizeStoreShape(name, value)
	ensureRuntimeStore()[name] = normalized
	touchStore(name, actor)
	return encodeKvpStore(name, normalized)
end

local function saveStore(name, actor)
	if not storeDefinitions[name] then
		return false, 'unknown_store'
	end

	touchStore(name, actor)
	return encodeKvpStore(name, ensureRuntimeStore()[name])
end

local function getPublicRuntimeSummary()
	local store = ensureRuntimeStore()
	return {
		stores = {
			runtimeConfig = tableCount(store.runtimeConfig),
			runtimeAcl = tableCount(store.runtimeAcl),
			commandBlocks = tableCount((store.commandBlocks or {}).entries),
			commandRoutes = tableCount((store.commandRoutes or {}).overrides),
			customCommands = tableCount((store.customCommands or {}).entries),
			autoMessages = tableCount((store.autoMessages or {}).items),
			auditLog = #((store.auditLog or {}).entries or {}),
			reports = #((store.reports or {}).items or {})
		}
	}
end

local function setupRuntimeConfig()
	ensureRuntimeStore()
end

Server.setupRuntimeConfig = setupRuntimeConfig
Server.ensureRuntimeStore = ensureRuntimeStore
Server.getRuntimeStore = getStore
Server.replaceRuntimeStore = replaceStore
Server.saveRuntimeStore = saveStore
Server.cloneRuntimeValue = clone
Server.getPublicRuntimeSummary = getPublicRuntimeSummary
