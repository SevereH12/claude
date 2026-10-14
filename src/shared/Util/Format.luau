--!strict
-- Number formatting for the UI: 1234 -> "1.23K", 5600000 -> "5.6M".

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

-- "1.50" -> "1.5", "2.00" -> "2"; leaves whole numbers like "100" alone
local function trimZeros(text: string): string
	if not text:find(".", 1, true) then
		return text
	end
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return text
end

function Format.abbreviate(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- 3 significant digits: 1.23K, 12.3K, 123K
	local text = if scaled < 10
		then string.format("%.2f", scaled)
		elseif scaled < 100 then string.format("%.1f", scaled)
		else string.format("%d", math.floor(scaled))
	return sign .. trimZeros(text) .. SUFFIXES[tier + 1]
end

-- 1.5 -> "x1.5", 2 -> "x2"
function Format.multiplier(n: number): string
	return "x" .. trimZeros(string.format("%.2f", n))
end

return Format
