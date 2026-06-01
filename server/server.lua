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
		'poodlechat:sceneMessage',
		'poodlechat:clearHistory',
		'poodlechat:whisperMessage',
		'poodlechat:getWhisperTargets',
		'poodlechat:getPermissions',
		'poodlechat:voiceDistanceState',
		'poodlechat:report',
		'poodlechat:deleteMessage',
		'poodlechat:mute',
		'poodlechat:unmute',
		'poodlechat:showMuted',
		'poodlechat:typingState',
		'poodlechat:bubbleMessage',
		'poodlechat:manager:request'
	}

	for i = 1, #serverEvents do
		RegisterServerEvent(serverEvents[i])
	end

	for i = 1, #networkEvents do
		RegisterNetEvent(networkEvents[i])
	end
end

safeCall('setupRuntimeConfig', Server.setupRuntimeConfig)
safeCall('setupBootstrap', Server.setupBootstrap)
safeCall('setupAudit', Server.setupAudit)
safeCall('setupPermissions', Server.setupPermissions)
safeCall('registerNetEvents', registerNetEvents)
safeCall('registerNicknameCommand', Server.registerNicknameCommand)
safeCall('initializeEmoji', Server.initializeEmoji)
safeCall('setupCommandsRuntime', Server.setupCommandsRuntime)
safeCall('registerChatHandlers', Server.registerChatHandlers)
safeCall('registerModerationHandlers', Server.registerModerationHandlers)
safeCall('setupAutoMessages', Server.setupAutoMessages)
safeCall('setupManager', Server.setupManager)

