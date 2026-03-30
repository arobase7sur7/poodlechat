local Server = PoodleChatServer
local SharedEmoji = (PoodleChatShared and PoodleChatShared.Emoji) or {}

local emojiAliasLookup = {}
local emojiFallbackAliases = {}

local function buildEmojiAliasFromName(name)
	if type(SharedEmoji.buildAliasFromName) == 'function' then
		return SharedEmoji.buildAliasFromName(name)
	end

	if type(name) ~= 'string' or name == '' then
		return nil
	end

	local alias = name:lower()
	alias = alias:gsub('&', ' and ')
	alias = alias:gsub('[^%w]+', '_')
	alias = alias:gsub('^_+', '')
	alias = alias:gsub('_+$', '')
	alias = alias:gsub('_+', '_')

	if alias == '' then
		return nil
	end

	return ':' .. alias .. ':'
end

local function resolveEmojiGlyph(entry)
	if type(SharedEmoji.resolveGlyph) == 'function' then
		return SharedEmoji.resolveGlyph(entry)
	end

	if type(entry) ~= 'table' then
		return nil
	end

	if type(entry.emoji) == 'string' and entry.emoji ~= '' then
		return entry.emoji
	end

	if type(entry.value) == 'string' and entry.value ~= '' then
		return entry.value
	end

	return nil
end

local function addEmojiAlias(alias, value)
	if type(alias) ~= 'string' or alias == '' or type(value) ~= 'string' or value == '' then
		return
	end

	if alias:match('^:[%w_#%+%-]+:$') then
		emojiAliasLookup[alias] = value
	else
		emojiFallbackAliases[#emojiFallbackAliases + 1] = {
			alias = alias,
			pattern = Server.escapePattern(alias),
			value = value
		}
	end
end

local function loadEmojiAliasLookup()
	emojiAliasLookup = {}
	emojiFallbackAliases = {}

	local data = LoadResourceFile(GetCurrentResourceName(), 'html/emojibase.json')
	if not data or data == '' then
		Server.log('warning', 'Missing html/emojibase.json, emoji alias replacement is disabled.')
		return
	end

	local decoded = Server.decodeTableOrEmpty(data)
	local loadedAliases = 0

	local function processEntry(entry)
		local value = resolveEmojiGlyph(entry)
		if not value then
			return
		end

		local hasAlias = false

		if type(entry.aliases) == 'table' then
			for aliasIndex = 1, #entry.aliases do
				local alias = entry.aliases[aliasIndex]
				if type(alias) == 'string' and alias ~= '' then
					addEmojiAlias(alias, value)
					loadedAliases = loadedAliases + 1
					hasAlias = true
				end
			end
		end

		if not hasAlias then
			local generatedAlias = buildEmojiAliasFromName(entry.name)
			if generatedAlias then
				addEmojiAlias(generatedAlias, value)
				loadedAliases = loadedAliases + 1
			end
		end
	end

	if type(decoded.categories) == 'table' then
		for categoryIndex = 1, #decoded.categories do
			local category = decoded.categories[categoryIndex]
			if type(category) == 'table' and type(category.emojis) == 'table' then
				for entryIndex = 1, #category.emojis do
					processEntry(category.emojis[entryIndex])
				end
			end
		end
	else
		for entryIndex = 1, #decoded do
			processEntry(decoded[entryIndex])
		end
	end

	if loadedAliases > 0 then
		Server.log('success', ('Loaded %d emoji aliases from emojibase.json'):format(loadedAliases))
	else
		Server.log('warning', 'No emoji aliases loaded from html/emojibase.json.')
	end
end

local function Emojit(text)
	if not text or text == '' then
		return text
	end

	if not string.find(text, ':', 1, true) then
		return text
	end

	text = text:gsub(':[%w_#%+%-]+:', function(alias)
		return emojiAliasLookup[alias] or alias
	end)

	for index = 1, #emojiFallbackAliases do
		local entry = emojiFallbackAliases[index]
		if string.find(text, entry.alias, 1, true) then
			text = text:gsub(entry.pattern, entry.value)
		end
	end

	return text
end

loadEmojiAliasLookup()

Server.loadEmojiAliasLookup = loadEmojiAliasLookup
Server.Emojit = Emojit

