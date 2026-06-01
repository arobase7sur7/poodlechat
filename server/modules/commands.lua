local Server = PoodleChatServer

local commandsInitialized = false
local registeredCustomNames = {}
local customCooldowns = {}
local customUsageCounts = {}

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

local function normalizeCommandName(value)
	local name = normalizeKey(value)
	if not name or not name:match('^[%w_%-]+$') then
		return nil
	end
	return name
end

local function getCommandBuilderConfig()
	local config = type(Config) == 'table' and Config or {}
	local builder = type(config.commandBuilder) == 'table' and config.commandBuilder or {}
	return {
		allowDangerousOverride = builder.allowDangerousOverride == true,
		maxActions = math.max(1, tonumber(builder.maxActions) or 24),
		maxAliases = math.max(0, tonumber(builder.maxAliases) or 8),
		maxTextLength = math.max(20, tonumber(builder.maxTextLength) or 300),
		cooldownDefault = math.max(0, tonumber(builder.defaultCooldownSeconds) or 0),
		safeEvents = type(builder.safeEvents) == 'table' and builder.safeEvents or {},
		internalActions = type(builder.internalActions) == 'table' and builder.internalActions or {},
		dangerousCommands = type(builder.dangerousCommands) == 'table' and builder.dangerousCommands or {
			'quit', 'restart', 'start', 'stop', 'ensure', 'exec', 'refresh',
			'add_ace', 'remove_ace', 'add_principal', 'remove_principal'
		}
	}
end

local function getStore(name)
	local store = type(Server.getRuntimeStore) == 'function' and Server.getRuntimeStore(name) or nil
	return type(store) == 'table' and store or {}
end

local function getBlocksStore()
	local store = getStore('commandBlocks')
	if type(store.entries) ~= 'table' then
		store.entries = {}
	end
	return store
end

local function getRoutesStore()
	local store = getStore('commandRoutes')
	if type(store.overrides) ~= 'table' then
		store.overrides = {}
	end
	if type(store.inboundMessageRules) ~= 'table' then
		store.inboundMessageRules = {}
	end
	return store
end

local function getCustomStore()
	local store = getStore('customCommands')
	if type(store.entries) ~= 'table' then
		store.entries = {}
	end
	return store
end

local function getRegistryMetaStore()
	local store = getStore('commandRegistry')
	if type(store.notes) ~= 'table' then
		store.notes = {}
	end
	if type(store.enabled) ~= 'table' then
		store.enabled = {}
	end
	return store
end

local function isDangerousCommand(name)
	local normalized = normalizeCommandName(name)
	if not normalized then
		return true
	end
	local builder = getCommandBuilderConfig()
	for i = 1, #builder.dangerousCommands do
		if normalizeCommandName(builder.dangerousCommands[i]) == normalized then
			return true
		end
	end
	return false
end

local function normalizeAliases(rawAliases, primaryName)
	local builder = getCommandBuilderConfig()
	local aliases = {}
	local seen = {[primaryName] = true}
	if type(rawAliases) ~= 'table' then
		return aliases
	end

	for i = 1, #rawAliases do
		if #aliases >= builder.maxAliases then
			break
		end
		local alias = normalizeCommandName(rawAliases[i])
		if alias and not seen[alias] then
			aliases[#aliases + 1] = alias
			seen[alias] = true
		end
	end
	return aliases
end

local function normalizeArgsSchema(value)
	local result = {}
	if type(value) ~= 'table' then
		return result
	end

	for i = 1, #value do
		local entry = value[i]
		if type(entry) == 'table' then
			local name = normalizeKey(entry.name) or ('arg' .. i)
			result[#result + 1] = {
				name = name,
				help = trim(entry.help),
				type = trim(entry.type or entry.kind or entry.input),
				required = entry.required == true
			}
		end
	end
	return result
end

local function normalizeActionList(rawActions, depth)
	depth = tonumber(depth) or 0
	if depth > 4 or type(rawActions) ~= 'table' then
		return {}
	end

	local builder = getCommandBuilderConfig()
	local result = {}
	for i = 1, #rawActions do
		if #result >= builder.maxActions then
			break
		end
		local action = rawActions[i]
		if type(action) == 'table' then
			local kind = normalizeKey(action.type or action.kind or action.action)
			if kind then
				local copy = {}
				for key, value in pairs(action) do
					copy[key] = value
				end
				copy.type = kind
				if type(copy.thenActions) == 'table' then
					copy.thenActions = normalizeActionList(copy.thenActions, depth + 1)
				end
				if type(copy.elseActions) == 'table' then
					copy.elseActions = normalizeActionList(copy.elseActions, depth + 1)
				end
				result[#result + 1] = copy
			end
		end
	end
	return result
end

local function normalizeCustomCommand(raw, fallbackName)
	local source = type(raw) == 'table' and raw or {}
	local name = normalizeCommandName(source.name or source.command or fallbackName)
	if not name then
		return nil, 'invalid_name'
	end

	local builder = getCommandBuilderConfig()
	if isDangerousCommand(name) and builder.allowDangerousOverride ~= true and source.confirmDangerous ~= true then
		return nil, 'dangerous_command'
	end

	local constants = Server.constants or {}
	local channel = normalizeKey(source.channel or source.targetChannel) or constants.DefaultChannelId or 'global'
	if constants.ChannelById and not constants.ChannelById[channel] then
		channel = constants.DefaultChannelId or 'global'
	end

	return {
		name = name,
		aliases = normalizeAliases(source.aliases, name),
		enabled = source.enabled ~= false,
		visible = source.visible ~= false,
		staffOnly = source.staffOnly == true,
		help = trim(source.help),
		usage = trim(source.usage),
		permission = trim(source.permission) ~= '' and trim(source.permission) or nil,
		cooldown = math.max(0, tonumber(source.cooldown) or builder.cooldownDefault),
		usageLimit = math.max(0, tonumber(source.usageLimit or source.maxUses or source.numberOfUses) or 0),
		usageScope = normalizeKey(source.usageScope) == 'global' and 'global' or 'player',
		channel = channel,
		args = normalizeArgsSchema(source.args or source.arguments),
		conditions = type(source.conditions) == 'table' and source.conditions or {},
		flags = type(source.flags) == 'table' and source.flags or {},
		actions = normalizeActionList(source.actions),
		updatedAt = os.time()
	}
end

local function getCommandBlockEntry(commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return nil
	end
	local entry = getBlocksStore().entries[name]
	return type(entry) == 'table' and entry or nil
end

local function evaluateCommandBlock(source, commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return {allowed = false, mode = 'block', reason = 'invalid'}
	end

	local entry = getCommandBlockEntry(name)
	if not entry or entry.enabled == false then
		return {allowed = true}
	end

	local mode = normalizeKey(entry.mode) or 'block'
	if mode == 'hide' or mode == 'hide_suggestion' or mode == 'hidefromsuggestions' then
		return {allowed = true, hidden = true, mode = mode}
	end

	if mode == 'staff' or mode == 'staffonly' then
		local allowed = Server.hasModerationPermission and Server.hasModerationPermission(source, 'staff')
		local message = nil
		if allowed ~= true then
			message = 'That command is staff-only.'
		end
		return {
			allowed = allowed == true,
			mode = 'staff',
			message = message
		}
	end

	if mode == 'permission' or mode == 'permissionrequired' then
		local permission = trim(entry.permission)
		local allowed = permission ~= '' and IsPlayerAceAllowed(source, permission)
		local message = nil
		if allowed ~= true then
			message = 'You do not have permission to use that command.'
		end
		return {
			allowed = allowed == true,
			mode = 'permission',
			message = message
		}
	end

	if mode == 'redirect' then
		local redirect = normalizeCommandName(entry.redirect)
		if redirect and redirect ~= name then
			return {allowed = false, mode = 'redirect', redirect = redirect}
		end
		return {allowed = false, mode = 'block', message = 'That command is blocked.'}
	end

	return {
		allowed = false,
		mode = 'block',
		message = trim(entry.message) ~= '' and trim(entry.message) or 'That command is blocked in chat.'
	}
end

local function saveCommandBlock(actor, raw)
	local name = normalizeCommandName(type(raw) == 'table' and (raw.command or raw.name) or nil)
	if not name then
		return false, 'invalid_name'
	end

	local entry = type(raw) == 'table' and raw or {}
	local mode = normalizeKey(entry.mode) or 'block'
	local store = getBlocksStore()
	store.entries[name] = {
		command = name,
		enabled = entry.enabled ~= false,
		mode = mode,
		permission = trim(entry.permission) ~= '' and trim(entry.permission) or nil,
		redirect = normalizeCommandName(entry.redirect),
		message = trim(entry.message),
		notes = trim(entry.notes),
		updatedAt = os.time()
	}

	Server.saveRuntimeStore('commandBlocks', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.block.save', {command = name, mode = mode})
	end
	return true, store.entries[name]
end

local function deleteCommandBlock(actor, commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return false, 'invalid_name'
	end
	getBlocksStore().entries[name] = nil
	Server.saveRuntimeStore('commandBlocks', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.block.delete', {command = name})
	end
	return true
end

local function saveCommandRoute(actor, raw)
	local payload = type(raw) == 'table' and raw or {}
	local command = normalizeCommandName(payload.command or payload.name)
	local channel = normalizeKey(payload.channel or payload.route)
	if not command or not channel then
		return false, 'invalid_route'
	end
	if Server.constants and Server.constants.ChannelById and not Server.constants.ChannelById[channel] then
		return false, 'invalid_channel'
	end

	local store = getRoutesStore()
	store.overrides[command] = channel
	Server.saveRuntimeStore('commandRoutes', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.route.save', {command = command, channel = channel})
	end
	return true, {command = command, channel = channel}
end

local function deleteCommandRoute(actor, commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return false, 'invalid_name'
	end
	getRoutesStore().overrides[name] = nil
	Server.saveRuntimeStore('commandRoutes', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.route.delete', {command = name})
	end
	return true
end

local function resolveRuntimeCommandRoute(commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return nil
	end
	local channel = normalizeKey(getRoutesStore().overrides[name])
	if channel and Server.constants and Server.constants.ChannelById and Server.constants.ChannelById[channel] then
		return channel
	end
	return nil
end

local function formatTemplate(template, context)
	local text = tostring(template or '')
	local args = context.args or {}
	text = text:gsub('{source}', tostring(context.source or 0))
	text = text:gsub('{name}', tostring(context.name or ''))
	text = text:gsub('{args}', table.concat(args, ' '))
	text = text:gsub('{arg(%d+)}', function(index)
		return tostring(args[tonumber(index) or 0] or '')
	end)
	return text
end

local function isEventAllowed(kind, eventName)
	local event = trim(eventName)
	if event == '' then
		return false
	end
	local safeEvents = getCommandBuilderConfig().safeEvents
	local list = kind == 'client' and safeEvents.client or safeEvents.server
	if type(list) ~= 'table' then
		return false
	end
	for i = 1, #list do
		if trim(list[i]) == event then
			return true
		end
	end
	return false
end

local function evaluateCondition(context, rawCondition)
	local condition = type(rawCondition) == 'table' and rawCondition or {}
	local kind = normalizeKey(condition.type or condition.kind)
	local source = tonumber(context.source) or 0
	local args = context.args or {}

	if kind == 'ace' or kind == 'playerhasacepermission' then
		local permission = trim(condition.permission or condition.ace)
		return permission ~= '' and source > 0 and IsPlayerAceAllowed(source, permission)
	end

	if kind == 'staff' or kind == 'playerisstaff' then
		return source > 0 and Server.hasModerationPermission and Server.hasModerationPermission(source, 'staff')
	end

	if kind == 'argexists' or kind == 'argumentexists' then
		local index = math.max(1, tonumber(condition.index) or 1)
		return trim(args[index]) ~= ''
	end

	if kind == 'argcountmin' or kind == 'argumentcountminimum' then
		return #args >= math.max(0, tonumber(condition.count or condition.min) or 0)
	end

	if kind == 'targetexists' then
		local index = math.max(1, tonumber(condition.index) or 1)
		return Server.getPlayerId and Server.getPlayerId(args[index]) ~= nil
	end

	if kind == 'channelenabled' then
		local channel = normalizeKey(condition.channel)
		return channel ~= nil and Server.constants and Server.constants.ChannelById and Server.constants.ChannelById[channel] ~= nil
	end

	if kind == 'cooldownactive' then
		local untilAt = tonumber((customCooldowns[context.commandName] or {})[tostring(source)]) or 0
		return os.time() < untilAt
	end

	if kind == 'cooldowninactive' then
		local untilAt = tonumber((customCooldowns[context.commandName] or {})[tostring(source)]) or 0
		return os.time() >= untilAt
	end

	if kind == 'sourceisconsole' then
		return source <= 0
	end

	if kind == 'sourceisplayer' then
		return source > 0
	end

	if kind == 'flag' or kind == 'custombooleanflag' then
		local flag = normalizeKey(condition.flag or condition.name)
		return flag ~= nil and context.flags and context.flags[flag] == true
	end

	return false
end

local runActions

local function runAction(context, action)
	local kind = normalizeKey(action.type or action.kind)
	if kind == 'sendmessage' or kind == 'sendchannelmessage' then
		local channel = normalizeKey(action.channel or context.command.channel) or context.command.channel
		local text = formatTemplate(action.text or action.message or '{args}', context)
		Server.sendRawChannelMessage(nil, channel, {
			label = trim(action.label) ~= '' and trim(action.label) or context.command.name:upper(),
			color = type(action.color) == 'table' and action.color or nil,
			args = {trim(action.label) ~= '' and trim(action.label) or context.command.name:upper(), text},
			authorSource = context.source,
			authorName = context.name,
			metadata = {type = 'customCommand', command = context.command.name}
		})
		return
	end

	if kind == 'sendsourcemessage' or kind == 'sendprivatemessage' then
		local text = formatTemplate(action.text or action.message or '{args}', context)
		Server.sendSystemMessage(context.source, text, type(action.color) == 'table' and action.color or {255, 255, 255}, normalizeKey(action.channel) or context.command.channel)
		return
	end

	if kind == 'sendtargetmessage' then
		local index = math.max(1, tonumber(action.targetArgIndex or action.index) or 1)
		local target = Server.getPlayerId and Server.getPlayerId(context.args[index]) or nil
		if target then
			Server.sendSystemMessage(target, formatTemplate(action.text or action.message or '{args}', context), type(action.color) == 'table' and action.color or {255, 255, 255}, normalizeKey(action.channel) or context.command.channel)
		end
		return
	end

	if kind == 'giveitem' or kind == 'giveitems' then
		local item = trim(formatTemplate(action.item or action.itemName or '', context))
		local amount = math.max(1, math.min(1000, math.floor(tonumber(action.amount or action.count) or 1)))
		local index = math.max(1, tonumber(action.targetArgIndex or action.index) or 1)
		local target = action.target == 'source' and context.source or (Server.getPlayerId and Server.getPlayerId(context.args[index]) or context.source)
		if item ~= '' and target and tonumber(target) and tonumber(target) > 0 then
			local info = type(action.info) == 'table' and action.info or false
			local ok = false
			if GetResourceState('qb-inventory') == 'started' then
				local called, result = pcall(function()
					return exports['qb-inventory']:AddItem(tonumber(target), item, amount, false, info, 'poodlechat:customCommand')
				end)
				ok = called and result ~= false
			end
			if not ok and GetResourceState('qb-core') ~= 'missing' then
				local called, result = pcall(function()
					local qb = exports['qb-core']:GetCoreObject()
					local player = qb and qb.Functions and qb.Functions.GetPlayer and qb.Functions.GetPlayer(tonumber(target))
					if player and player.Functions and player.Functions.AddItem then
						return player.Functions.AddItem(item, amount, false, info)
					end
					return false
				end)
				ok = called and result ~= false
			end
			if ok and action.notify ~= false and Server.sendSystemMessage then
				local successMessage = tostring(action.successMessage or 'Received {amount}x {item}')
				successMessage = successMessage:gsub('{amount}', tostring(amount)):gsub('{item}', item)
				Server.sendSystemMessage(tonumber(target), formatTemplate(successMessage, context), {104, 216, 167}, context.command.channel)
			end
		end
		return
	end

	if kind == 'staffnotification' or kind == 'sendstaffnotification' then
		local recipients = {}
		for _, player in ipairs(GetPlayers()) do
			if Server.canAccessChannel and Server.canAccessChannel(player, 'staff') then
				recipients[#recipients + 1] = player
			end
		end
		Server.sendRawChannelMessage(recipients, 'staff', {
			label = trim(action.label) ~= '' and trim(action.label) or 'Staff',
			color = type(action.color) == 'table' and action.color or {255, 64, 0},
			args = {trim(action.label) ~= '' and trim(action.label) or 'Staff', formatTemplate(action.text or action.message or '{args}', context)},
			authorSource = context.source,
			authorName = context.name,
			metadata = {type = 'system', subtype = 'customStaffNotification', command = context.command.name}
		})
		return
	end

	if kind == 'discordwebhook' or kind == 'senddiscordwebhooklog' then
		if Server.sendDiscordWebhook then
			Server.sendDiscordWebhook(trim(action.kindName) ~= '' and trim(action.kindName) or 'default', context.source, context.name, Server.sanitizeDiscordText(formatTemplate(action.text or action.message or '{args}', context)), nil)
		end
		return
	end

	if kind == 'triggerserverevent' then
		local eventName = trim(action.event)
		if isEventAllowed('server', eventName) then
			TriggerEvent(eventName, context.source, context.args, action.payload)
		end
		return
	end

	if kind == 'triggerclientevent' then
		local eventName = trim(action.event)
		if isEventAllowed('client', eventName) then
			local target = context.source
			if action.target == 'all' then
				target = -1
			elseif action.targetArgIndex then
				target = Server.getPlayerId and Server.getPlayerId(context.args[tonumber(action.targetArgIndex) or 1]) or context.source
			end
			TriggerClientEvent(eventName, target, action.payload or {}, context.source)
		end
		return
	end

	if kind == 'internalaction' or kind == 'executepoodlechatinternalaction' then
		local internal = normalizeKey(action.name)
		if internal == 'refreshcommands' and Server.refreshCommands then
			for _, player in ipairs(GetPlayers()) do
				Server.refreshCommands(player)
			end
		elseif internal == 'sendbubble' and Server.emitBubble then
			Server.emitBubble(context.source, formatTemplate(action.text or action.message or '{args}', context))
		end
		return
	end

	if kind == 'delay' or kind == 'wait' then
		Wait(math.max(0, math.min(30000, tonumber(action.ms or action.durationMs) or 1000)))
		return
	end

	if kind == 'conditionalbranch' or kind == 'condition' then
		if evaluateCondition(context, action.condition or action) then
			runActions(context, type(action.thenActions) == 'table' and action.thenActions or {})
		else
			runActions(context, type(action.elseActions) == 'table' and action.elseActions or {})
		end
	end
end

runActions = function(context, actions)
	local list = type(actions) == 'table' and actions or {}
	for i = 1, #list do
		runAction(context, list[i])
	end
end

local function canRunCustomCommand(source, command)
	local sourceId = tonumber(source) or 0
	if command.staffOnly and sourceId > 0 and not (Server.hasModerationPermission and Server.hasModerationPermission(sourceId, 'staff')) then
		return false, 'This command is staff-only.'
	end
	if command.permission and command.permission ~= '' and sourceId > 0 and not IsPlayerAceAllowed(sourceId, command.permission) then
		return false, 'You do not have permission to use this command.'
	end
	local block = evaluateCommandBlock(sourceId, command.name)
	if block.allowed == false then
		return false, block.message or 'That command is blocked.'
	end
	return true
end

local function runCustomCommand(source, commandName, args)
	local name = normalizeCommandName(commandName)
	local command = name and getCustomStore().entries[name] or nil
	if type(command) ~= 'table' or command.enabled == false then
		return
	end

	local sourceId = tonumber(source) or 0
	local allowed, reason = canRunCustomCommand(sourceId, command)
	if not allowed then
		if sourceId > 0 and Server.sendSystemMessage then
			Server.sendSystemMessage(sourceId, reason, {255, 96, 96}, Server.constants.DefaultChannelId)
		end
		return
	end

	local cooldown = tonumber(command.cooldown) or 0
	if cooldown > 0 and sourceId > 0 then
		customCooldowns[name] = customCooldowns[name] or {}
		local sourceKey = tostring(sourceId)
		local untilAt = tonumber(customCooldowns[name][sourceKey]) or 0
		if os.time() < untilAt then
			Server.sendSystemMessage(sourceId, 'That command is on cooldown.', {255, 214, 102}, Server.constants.DefaultChannelId)
			return
		end
		customCooldowns[name][sourceKey] = os.time() + cooldown
	end

	local usageLimit = tonumber(command.usageLimit) or 0
	if usageLimit > 0 then
		customUsageCounts[name] = customUsageCounts[name] or {}
		local usageKey = command.usageScope == 'global' and 'global' or tostring(sourceId)
		local currentUsage = tonumber(customUsageCounts[name][usageKey]) or 0
		if currentUsage >= usageLimit then
			if sourceId > 0 and Server.sendSystemMessage then
				Server.sendSystemMessage(sourceId, 'That command has no uses left.', {255, 214, 102}, Server.constants.DefaultChannelId)
			end
			return
		end
		customUsageCounts[name][usageKey] = currentUsage + 1
	end

	local context = {
		source = sourceId,
		args = type(args) == 'table' and args or {},
		command = command,
		commandName = name,
		name = sourceId > 0 and ((Server.getName and Server.getName(sourceId)) or GetPlayerName(sourceId) or tostring(sourceId)) or 'console',
		flags = type(command.flags) == 'table' and command.flags or {}
	}

	CreateThread(function()
		runActions(context, command.actions)
	end)
end

local function registerCustomCommand(command)
	if type(command) ~= 'table' or command.enabled == false then
		return
	end

	local names = {command.name}
	for i = 1, #(command.aliases or {}) do
		names[#names + 1] = command.aliases[i]
	end

	for i = 1, #names do
		local name = normalizeCommandName(names[i])
		if name and not registeredCustomNames[name] then
			registeredCustomNames[name] = true
			RegisterCommand(name, function(source, args)
				local current = getCustomStore().entries[command.name]
				if type(current) == 'table' and current.enabled ~= false then
					runCustomCommand(source, command.name, args)
				end
			end, false)
		end
	end
end

local function registerRuntimeCustomCommands()
	local entries = getCustomStore().entries
	for _, command in pairs(entries) do
		registerCustomCommand(command)
	end
end

local function saveCustomCommand(actor, raw)
	local command, reason = normalizeCustomCommand(raw)
	if not command then
		return false, reason
	end
	local store = getCustomStore()
	store.entries[command.name] = command
	Server.saveRuntimeStore('customCommands', actor)
	registerCustomCommand(command)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.custom.save', {command = command.name})
	end
	return true, command
end

local function deleteCustomCommand(actor, commandName)
	local name = normalizeCommandName(commandName)
	if not name then
		return false, 'invalid_name'
	end
	getCustomStore().entries[name] = nil
	Server.saveRuntimeStore('customCommands', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'command.custom.delete', {command = name})
	end
	return true
end

local function buildCommandRegistry(source)
	local registry = {}
	local byName = {}
	local constants = Server.constants or {}
	local routes = getRoutesStore().overrides
	local blocks = getBlocksStore().entries
	local meta = getRegistryMetaStore()

	local function add(entry)
		local name = normalizeCommandName(entry.name)
		if not name then
			return
		end
		entry.name = name
		entry.route = routes[name] or entry.route
		entry.block = blocks[name]
		entry.notes = meta.notes[name] or entry.notes
		entry.enabled = meta.enabled[name] ~= nil and meta.enabled[name] ~= false or entry.enabled ~= false
		if byName[name] then
			local existing = byName[name]
			existing.aliases = existing.aliases or {}
			for i = 1, #(entry.aliases or {}) do
				existing.aliases[#existing.aliases + 1] = entry.aliases[i]
			end
			return
		end
		byName[name] = entry
		registry[#registry + 1] = entry
	end

	for key, command in pairs(constants.CommandByKey or {}) do
		add({
			name = command.command,
			aliases = command.aliases or {},
			origin = 'PoodleChat-managed',
			side = key == 'nick' and 'server' or 'client',
			source = GetCurrentResourceName(),
			restricted = command.permission ~= nil,
			permission = command.permission,
			enabled = command.enabled == true,
			route = command.channel,
			handlerType = command.handler,
			notes = command.help
		})
	end

	for _, command in pairs(getCustomStore().entries) do
		if type(command) == 'table' then
			add({
				name = command.name,
				aliases = command.aliases or {},
				origin = 'PoodleChat custom command',
				side = 'server',
				source = GetCurrentResourceName(),
				restricted = command.permission ~= nil or command.staffOnly == true,
				permission = command.permission,
				enabled = command.enabled ~= false,
				route = command.channel,
				handlerType = 'blueprint',
				notes = command.help
			})
		end
	end

	if GetRegisteredCommands then
		for _, command in ipairs(GetRegisteredCommands()) do
			local name = normalizeCommandName(command.name)
			if name and not byName[name] then
				add({
					name = name,
					aliases = {},
					origin = 'Discovered external command',
					side = 'server',
					source = tostring(command.resource or command.resourceName or 'unknown'),
					restricted = IsPlayerAceAllowed(source, ('command.%s'):format(name)) ~= true,
					permission = ('command.%s'):format(name),
					enabled = true,
					route = routes[name],
					handlerType = 'external',
					notes = 'Best-effort discovery from GetRegisteredCommands().'
				})
			end
		end
	end

	table.sort(registry, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return registry
end

local function getClientCommandPolicy(source)
	return {
		blocks = getBlocksStore().entries,
		routes = getRoutesStore().overrides,
		customCommands = getCustomStore().entries,
		registry = buildCommandRegistry(source)
	}
end

local function setupCommandsRuntime()
	if commandsInitialized then
		return
	end
	registerRuntimeCustomCommands()
	Server.getCommandBlockEntry = getCommandBlockEntry
	Server.evaluateCommandBlock = evaluateCommandBlock
	Server.saveCommandBlock = saveCommandBlock
	Server.deleteCommandBlock = deleteCommandBlock
	Server.saveCommandRoute = saveCommandRoute
	Server.deleteCommandRoute = deleteCommandRoute
	Server.resolveRuntimeCommandRoute = resolveRuntimeCommandRoute
	Server.saveCustomCommand = saveCustomCommand
	Server.deleteCustomCommand = deleteCustomCommand
	Server.buildCommandRegistry = buildCommandRegistry
	Server.getClientCommandPolicy = getClientCommandPolicy
	Server.registerRuntimeCustomCommands = registerRuntimeCustomCommands
	commandsInitialized = true
end

Server.setupCommandsRuntime = setupCommandsRuntime
