PoodleChatShared = PoodleChatShared or {}

local Shared = PoodleChatShared
local Emoji = {}

local function normalizeToken(value)
	if type(value) ~= 'string' then
		return ''
	end

	return value
end

function Emoji.decodeCodepoint(codepoint)
	if type(codepoint) ~= 'number' or codepoint < 0 or codepoint > 1114111 then
		return nil
	end

	if codepoint >= 55296 and codepoint <= 57343 then
		return nil
	end

	if utf8 and type(utf8.char) == 'function' then
		local ok, char = pcall(utf8.char, codepoint)
		if ok and type(char) == 'string' then
			return char
		end
	end

	if codepoint <= 127 then
		return string.char(codepoint)
	end

	if codepoint <= 2047 then
		return string.char(
			192 + math.floor(codepoint / 64),
			128 + (codepoint % 64)
		)
	end

	if codepoint <= 65535 then
		return string.char(
			224 + math.floor(codepoint / 4096),
			128 + (math.floor(codepoint / 64) % 64),
			128 + (codepoint % 64)
		)
	end

	return string.char(
		240 + math.floor(codepoint / 262144),
		128 + (math.floor(codepoint / 4096) % 64),
		128 + (math.floor(codepoint / 64) % 64),
		128 + (codepoint % 64)
	)
end

function Emoji.decodeFromUnicodeList(unicodeList)
	if type(unicodeList) ~= 'table' then
		return nil
	end

	local chunks = {}

	for i = 1, #unicodeList do
		local token = unicodeList[i]
		if type(token) == 'string' then
			local hex = token:match('^%s*[Uu]%+([0-9A-Fa-f]+)%s*$') or token:match('^%s*([0-9A-Fa-f]+)%s*$')
			if hex then
				local codepoint = tonumber(hex, 16)
				local char = Emoji.decodeCodepoint(codepoint)
				if char then
					chunks[#chunks + 1] = char
				end
			end
		end
	end

	if #chunks == 0 then
		return nil
	end

	return table.concat(chunks)
end

function Emoji.decodeFromHtmlCodeList(htmlCodeList)
	if type(htmlCodeList) ~= 'table' then
		return nil
	end

	local chunks = {}

	for i = 1, #htmlCodeList do
		local raw = htmlCodeList[i]
		if type(raw) == 'string' and raw ~= '' then
			for entity in raw:gmatch('&#[xX]?[%x]+;') do
				local body = entity:sub(3, -2)
				local base = 10

				if body:sub(1, 1):lower() == 'x' then
					body = body:sub(2)
					base = 16
				end

				local codepoint = tonumber(body, base)
				local char = Emoji.decodeCodepoint(codepoint)
				if char then
					chunks[#chunks + 1] = char
				end
			end
		end
	end

	if #chunks == 0 then
		return nil
	end

	return table.concat(chunks)
end

function Emoji.buildAliasFromName(name)
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

function Emoji.resolveGlyph(entry)
	if type(entry) ~= 'table' then
		return nil
	end

	if type(entry.emoji) == 'string' and entry.emoji ~= '' then
		return entry.emoji
	end

	if type(entry.value) == 'string' and entry.value ~= '' then
		return entry.value
	end

	local unicodeGlyph = Emoji.decodeFromUnicodeList(entry.unicode)
	if unicodeGlyph and unicodeGlyph ~= '' then
		return unicodeGlyph
	end

	local htmlGlyph = Emoji.decodeFromHtmlCodeList(entry.htmlCode)
	if htmlGlyph and htmlGlyph ~= '' then
		return htmlGlyph
	end

	return nil
end

function Emoji.normalizeCategoryId(value, fallback)
	local normalized = normalizeToken(value):lower()
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

Shared.Emoji = Emoji
