PoodleChatClient = PoodleChatClient or {}

local Client = PoodleChatClient

local function safeCall(label, fn)
	if type(fn) ~= 'function' then
		print(('[poodlechat] Missing client initializer: %s'):format(label))
		return
	end

	local ok, err = pcall(fn)
	if not ok then
		print(('[poodlechat] Client initializer failed (%s): %s'):format(label, tostring(err)))
	end
end

local function registerNetEvents()
	local events = type(Client.netEvents) == 'table' and Client.netEvents or {}

	for i = 1, #events do
		RegisterNetEvent(events[i])
	end
end

safeCall('setupBootstrap', Client.setupBootstrap)
safeCall('registerNetEvents', registerNetEvents)
safeCall('registerFeatureHandlers', Client.registerFeatureHandlers)
safeCall('registerChatHandlers', Client.registerChatHandlers)
safeCall('registerNuiHandlers', Client.registerNuiHandlers)

