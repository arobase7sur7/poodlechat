local Server = PoodleChatServer

local autoMessagesStarted = false
local lastSentAt = {}

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

local function getAutoConfig()
	local config = type(Config) == 'table' and Config or {}
	local auto = type(config.autoMessages) == 'table' and config.autoMessages or {}
	return {
		enabled = auto.enabled ~= false,
		minInterval = math.max(30, tonumber(auto.minIntervalSeconds) or 120),
		maxTextLength = math.max(20, tonumber(auto.maxTextLength) or 240),
		defaults = type(auto.defaults) == 'table' and auto.defaults or {}
	}
end

local function getStore()
	local store = type(Server.getRuntimeStore) == 'function' and Server.getRuntimeStore('autoMessages') or nil
	if type(store) ~= 'table' then
		return {items = {}}
	end
	if type(store.items) ~= 'table' then
		store.items = {}
	end
	return store
end

local function normalizeAutoMessage(raw, fallbackId)
	local source = type(raw) == 'table' and raw or {}
	local config = getAutoConfig()
	local id = normalizeKey(source.id or fallbackId or source.label)
	if not id then
		return nil, 'invalid_id'
	end

	local text = trim(source.text)
	if text == '' then
		return nil, 'invalid_text'
	end
	if #text > config.maxTextLength then
		text = text:sub(1, config.maxTextLength)
	end

	local channel = normalizeKey(source.channel) or normalizeKey(config.defaults.channel) or 'global'
	if Server.constants and Server.constants.ChannelById and not Server.constants.ChannelById[channel] then
		channel = Server.constants.DefaultChannelId or 'global'
	end

	return {
		id = id,
		enabled = source.enabled == true,
		label = trim(source.label) ~= '' and trim(source.label) or 'Auto',
		text = text,
		channel = channel,
		interval = math.max(config.minInterval, tonumber(source.interval or source.intervalSeconds) or config.minInterval),
		color = type(source.color) == 'table' and source.color or nil,
		template = source.template,
		templateId = source.templateId,
		permission = trim(source.permission) ~= '' and trim(source.permission) or nil,
		updatedAt = tonumber(source.updatedAt) or os.time()
	}
end

local function saveAutoMessage(actor, raw)
	local item, reason = normalizeAutoMessage(raw)
	if not item then
		return false, reason
	end

	local store = getStore()
	store.items[item.id] = item
	Server.saveRuntimeStore('autoMessages', actor)
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'automessage.save', {id = item.id, channel = item.channel})
	end
	return true, item
end

local function deleteAutoMessage(actor, id)
	local normalized = normalizeKey(id)
	if not normalized then
		return false, 'invalid_id'
	end

	local store = getStore()
	store.items[normalized] = nil
	Server.saveRuntimeStore('autoMessages', actor)
	lastSentAt[normalized] = nil
	if Server.appendAuditLog then
		Server.appendAuditLog(actor, 'automessage.delete', {id = normalized})
	end
	return true
end

local function getAutoMessages()
	local items = {}
	for id, item in pairs(getStore().items) do
		local normalized = normalizeAutoMessage(item, id)
		if normalized then
			items[#items + 1] = normalized
		end
	end
	table.sort(items, function(a, b)
		return tostring(a.label) < tostring(b.label)
	end)
	return items
end

local function collectRecipients(item)
	if not item.permission or item.permission == '' then
		return nil
	end

	local recipients = {}
	for _, player in ipairs(GetPlayers()) do
		if IsPlayerAceAllowed(player, item.permission) then
			recipients[#recipients + 1] = player
		end
	end
	return recipients
end

local function dispatchAutoMessage(item)
	if not Server.sendRawChannelMessage then
		return
	end

	local recipients = collectRecipients(item)
	Server.sendRawChannelMessage(recipients, item.channel, {
		label = item.label,
		color = item.color or {255, 255, 255},
		args = {item.label, item.text},
		template = item.template,
		templateId = item.templateId,
		authorName = item.label,
		metadata = {
			type = 'system',
			subtype = 'automessage',
			autoMessageId = item.id,
			authorName = item.label
		}
	})
end

local function startAutoMessages()
	if autoMessagesStarted then
		return
	end
	autoMessagesStarted = true

	CreateThread(function()
		while true do
			Wait(10000)
			local config = getAutoConfig()
			if config.enabled and Server.constants then
				local now = os.time()
				for _, item in ipairs(getAutoMessages()) do
					if item.enabled then
						local previous = tonumber(lastSentAt[item.id]) or 0
						if now - previous >= item.interval then
							lastSentAt[item.id] = now
							dispatchAutoMessage(item)
						end
					end
				end
			end
		end
	end)
end

local function setupAutoMessages()
	getStore()
	startAutoMessages()
end

Server.setupAutoMessages = setupAutoMessages
Server.getAutoMessages = getAutoMessages
Server.saveAutoMessage = saveAutoMessage
Server.deleteAutoMessage = deleteAutoMessage
