PoodleChatServer = PoodleChatServer or {}

local Server = PoodleChatServer

local function safeCall(label, fn)
	if type(fn) ~= 'function' then
		print(('[poodlechat] Missing server initializer: %s'):format(label))
		return
	end

	local ok, err = pcall(fn)
	if not ok then
		print(('[poodlechat] Server initializer failed (%s): %s'):format(label, tostring(err)))
	end
end

local function registerNetEvents()
	local serverEvents = {
		'chat:init',
		'chat:addTemplate',
		'chat:addMessage',
		'chat:addSuggestion',
		'chat:removeSuggestion',
		'_chat:messageEntered',
		'chat:clear',
		'__cfx_internal:commandFallback'
	}

	local networkEvents = {
		'playerJoining',
		'poodlechat:staffMessage',
		'poodlechat:globalMessage',
		'poodlechat:actionMessage',
		'poodlechat:whisperMessage',
		'poodlechat:getPermissions',
		'poodlechat:report',
		'poodlechat:mute',
		'poodlechat:unmute',
		'poodlechat:showMuted',
		'poodlechat:typingState',
		'poodlechat:bubbleMessage'
	}

	for i = 1, #serverEvents do
		RegisterServerEvent(serverEvents[i])
	end

	for i = 1, #networkEvents do
		RegisterNetEvent(networkEvents[i])
	end
end

safeCall('setupBootstrap', Server.setupBootstrap)
safeCall('registerNetEvents', registerNetEvents)
safeCall('registerNicknameCommand', Server.registerNicknameCommand)
safeCall('initializeEmoji', Server.initializeEmoji)
safeCall('registerChatHandlers', Server.registerChatHandlers)
safeCall('registerModerationHandlers', Server.registerModerationHandlers)

