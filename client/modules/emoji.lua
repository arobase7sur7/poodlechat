local Client = PoodleChatClient
local SharedEmoji = (PoodleChatShared and PoodleChatShared.Emoji) or {}
local State = nil

local function ensureContext()
	if State then
		return true
	end

	State = Client.state
	return State ~= nil
end

local function normalizeCategoryId(value, fallback)
	if type(SharedEmoji.normalizeCategoryId) == 'function' then
		return SharedEmoji.normalizeCategoryId(value, fallback)
	end

	local normalized = tostring(value or ''):lower()
	normalized = normalized:gsub('&', ' and ')
	normalized = normalized:gsub('[^%w]+', '-')
	normalized = normalized:gsub('^-+', '')
	normalized = normalized:gsub('-+$', '')
	normalized = normalized:gsub('%-+', '-')

	if normalized == '' then
		return fallback
	end

	return normalized
end

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

local function markEmojiDirty()
	if not ensureContext() then
		return
	end

	State.sortedEmojiDirty = true
end

local function buildEmojiIndex()
	if not ensureContext() then
		return
	end

	State.emojiAliasesByGlyph = {}

	for i = 1, #State.emojiEntries do
		local entry = State.emojiEntries[i]
		local aliases = type(entry[1]) == 'table' and entry[1] or {}
		local glyph = entry[2]

		if type(glyph) == 'string' and glyph ~= '' then
			local aliasList = State.emojiAliasesByGlyph[glyph]
			if not aliasList then
				aliasList = {}
				State.emojiAliasesByGlyph[glyph] = aliasList
			end

			for k = 1, #aliases do
				local alias = aliases[k]
				if type(alias) == 'string' and alias ~= '' then
					aliasList[#aliasList + 1] = alias
				end
			end
		end
	end
end

local function getSortedEmoji()
	if not ensureContext() then
		return {}
	end

	if State.sortedEmojiCache and not State.sortedEmojiDirty then
		return State.sortedEmojiCache
	end

	local sorted = {}

	for i = 1, #State.emojiEntries do
		sorted[i] = State.emojiEntries[i]
	end

	table.sort(sorted, function(a, b)
		local aUsage = State.EmojiUsage[a[2]] or 0
		local bUsage = State.EmojiUsage[b[2]] or 0

		if aUsage == bUsage then
			local aAlias = type(a[1]) == 'table' and tostring(a[1][1] or '') or ''
			local bAlias = type(b[1]) == 'table' and tostring(b[1][1] or '') or ''
			return aAlias < bAlias
		end

		return aUsage > bUsage
	end)

	State.sortedEmojiCache = sorted
	State.sortedEmojiDirty = false

	return sorted
end

function SortEmoji()
	return getSortedEmoji()
end

local function buildEmojiUsageEntriesFromGlyphs(glyphList, limit)
	if not ensureContext() then
		return {}
	end

	local entries = {}
	local maxEntries = math.max(1, tonumber(limit) or 10)

	for i = 1, #glyphList do
		if #entries >= maxEntries then
			break
		end

		local glyph = glyphList[i]
		if type(glyph) == 'string' and glyph ~= '' then
			entries[#entries + 1] = {
				emoji = glyph,
				aliases = State.emojiAliasesByGlyph[glyph] or {},
				usage = State.EmojiUsage[glyph] or 0
			}
		end
	end

	return entries
end

local function buildTopEmojiUsageEntries(limit)
	if not ensureContext() then
		return {}
	end

	local entries = {}
	local sorted = getSortedEmoji()
	local maxEntries = math.max(1, tonumber(limit) or 10)

	for i = 1, #sorted do
		if #entries >= maxEntries then
			break
		end

		local glyph = sorted[i][2]
		local usage = State.EmojiUsage[glyph] or 0

		if usage > 0 then
			entries[#entries + 1] = {
				emoji = glyph,
				aliases = State.emojiAliasesByGlyph[glyph] or {},
				usage = usage
			}
		end
	end

	return entries
end

local function addEmojiRecent(glyph)
	if not ensureContext() then
		return
	end

	if type(glyph) ~= 'string' or glyph == '' then
		return
	end

	local updated = {glyph}

	for i = 1, #State.EmojiRecent do
		local current = State.EmojiRecent[i]
		if current ~= glyph then
			updated[#updated + 1] = current
		end

		if #updated >= State.EmojiRecentLimit then
			break
		end
	end

	State.EmojiRecent = updated
	Client.encodeAndStore('emojiRecent', State.EmojiRecent)
end

local function buildCategoryListFromRawEntries(rawEntries)
	if type(rawEntries) ~= 'table' then
		return {}
	end

	local byId = {}
	local order = {}

	for i = 1, #rawEntries do
		local entry = rawEntries[i]
		if type(entry) == 'table' then
			local label = tostring(entry.category or 'misc')
			local id = normalizeCategoryId(label, 'category_' .. i)
			local bucket = byId[id]

			if not bucket then
				bucket = {
					id = id,
					label = label,
					emojis = {}
				}
				byId[id] = bucket
				order[#order + 1] = id
			end

			bucket.emojis[#bucket.emojis + 1] = entry
		end
	end

	local categories = {}

	for i = 1, #order do
		categories[#categories + 1] = byId[order[i]]
	end

	return categories
end

local function parseEmojiDataset()
	if not ensureContext() then
		return
	end

	local data = LoadResourceFile(GetCurrentResourceName(), 'html/emojibase.json')

	if not data or data == '' then
		State.emojiDataset = {categories = {}}
		State.emojiEntries = {}
		State.emojiAliasesByGlyph = {}
		markEmojiDirty()
		return
	end

	local decoded = Client.decodeJson(data)
	if type(decoded) ~= 'table' then
		State.emojiDataset = {categories = {}}
		State.emojiEntries = {}
		State.emojiAliasesByGlyph = {}
		markEmojiDirty()
		return
	end

	local rawCategories = type(decoded.categories) == 'table' and decoded.categories or buildCategoryListFromRawEntries(decoded)
	local categories = {}
	local entries = {}

	for i = 1, #rawCategories do
		local category = rawCategories[i]
		local id = normalizeCategoryId(category.id or category.label, 'category_' .. i)
		local label = tostring(category.label or id)
		local emojis = {}

		if type(category.emojis) == 'table' then
			for k = 1, #category.emojis do
				local entry = category.emojis[k]
				local glyph = resolveEmojiGlyph(entry)

				if type(glyph) == 'string' and glyph ~= '' then
					local aliases = {}
					if type(entry.aliases) == 'table' then
						for a = 1, #entry.aliases do
							local alias = entry.aliases[a]
							if type(alias) == 'string' and alias ~= '' then
								aliases[#aliases + 1] = alias
							end
						end
					end

					if #aliases == 0 then
						local generatedAlias = buildEmojiAliasFromName(entry.name)
						if generatedAlias then
							aliases[1] = generatedAlias
						end
					end

					local search = tostring(entry.search or '')
					if search == '' then
						local parts = {}
						if type(entry.name) == 'string' and entry.name ~= '' then
							parts[#parts + 1] = entry.name
						end
						if type(entry.group) == 'string' and entry.group ~= '' then
							parts[#parts + 1] = entry.group
						end
						parts[#parts + 1] = label
						search = table.concat(parts, ' ')
					end

					emojis[#emojis + 1] = {
						emoji = glyph,
						aliases = aliases,
						search = search:lower()
					}

					entries[#entries + 1] = {aliases, glyph}
				end
			end
		end

		categories[#categories + 1] = {
			id = id,
			label = label,
			emojis = emojis
		}
	end

	State.emojiDataset = {
		categories = categories
	}
	State.emojiEntries = entries
	markEmojiDirty()
	buildEmojiIndex()
end

local function getEmojiPanelData()
	if not ensureContext() then
		return {
			recent = {},
			top = {}
		}
	end

	return {
		recent = buildEmojiUsageEntriesFromGlyphs(State.EmojiRecent, State.EmojiRecentLimit),
		top = buildTopEmojiUsageEntries(State.EmojiTopLimit)
	}
end

local function handleEmojiUse(glyph)
	if not ensureContext() then
		return {
			panel = {
				recent = {},
				top = {}
			}
		}
	end

	if type(glyph) == 'string' and glyph ~= '' then
		local current = tonumber(State.EmojiUsage[glyph]) or 0
		State.EmojiUsage[glyph] = current + 1
		addEmojiRecent(glyph)
		Client.encodeAndStore('emojiUsage', State.EmojiUsage)
		markEmojiDirty()
	end

	return {
		panel = getEmojiPanelData()
	}
end

local function addEmojiSuggestions()
	if not ensureContext() then
		return
	end

	local suggestions = {}

	for i = 1, #State.emojiEntries do
		local aliases = type(State.emojiEntries[i][1]) == 'table' and State.emojiEntries[i][1] or {}
		local glyph = State.emojiEntries[i][2]

		for k = 1, #aliases do
			suggestions[#suggestions + 1] = {
				name = aliases[k],
				help = glyph
			}
		end
	end

	TriggerEvent('chat:addSuggestions', suggestions)
end

Client.markEmojiDirty = markEmojiDirty
Client.buildEmojiIndex = buildEmojiIndex
Client.getSortedEmoji = getSortedEmoji
Client.addEmojiRecent = addEmojiRecent
Client.parseEmojiDataset = parseEmojiDataset
Client.getEmojiPanelData = getEmojiPanelData
Client.handleEmojiUse = handleEmojiUse
Client.AddEmojiSuggestions = addEmojiSuggestions

