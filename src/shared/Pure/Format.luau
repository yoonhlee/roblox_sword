--!strict
--[[
	Format — 표시용 문자열 포맷터. Roblox API 를 전혀 쓰지 않으므로
	Lune(또는 순수 Luau)에서 그대로 테스트할 수 있다.

	여기 있는 함수는 숫자/기호만 다룬다. 사람이 읽는 문장은
	LocalizationTable 이 담당한다.
]]

local Format = {}

-- 1234567 → "1,234,567" (소수는 반올림, 음수는 부호 유지)
function Format.comma(value: number): string
	local negative = value < 0
	local whole = tostring(math.floor(math.abs(value) + 0.5))

	local chunked = (whole:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	if chunked:sub(1, 1) == "," then
		chunked = chunked:sub(2)
	end

	if negative and chunked ~= "0" then
		return "-" .. chunked
	end
	return chunked
end

-- 12.5 → "12.5%" / 20 → "20%"  (decimals 기본 1자리, 정수면 소수점 생략)
function Format.percent(value: number, decimals: number?): string
	local places = decimals or 1
	local rounded = math.floor(value * 10 ^ places + 0.5) / 10 ^ places

	if rounded == math.floor(rounded) then
		return string.format("%d%%", rounded)
	end
	return string.format("%." .. places .. "f%%", rounded)
end

-- 7 → "+7" / 0 → "+0"  (강화 레벨 표기)
function Format.level(level: number): string
	return string.format("+%d", level)
end

-- 65 → "1:05", 3725 → "1:02:05"
function Format.duration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

--[[
	큰 숫자를 줄여 쓴다 (화면 공간이 좁은 곳: 재화 칩, 보상 표시).
	  한국어: 9,999 까지 그대로, 1.2만 · 123만 · 1.2억 · 4.9억 · 1.2조
	  영어:   999 까지 그대로, 1.2K · 120K · 1.2M · 1.05B · 1.2T
	소수는 한 자리(영어 B·T 는 두 자리까지), 끝의 0 은 뗀다. 음수는 부호를 붙인다.
]]
local KO_UNITS = { { 1e12, "조" }, { 1e8, "억" }, { 1e4, "만" } }
local EN_UNITS = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

local function trimNumber(value: number, decimals: number): string
	local scale = 10 ^ decimals
	local rounded = math.floor(value * scale + 0.5) / scale
	local text = string.format("%." .. decimals .. "f", rounded)
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function Format.short(value: number, language: string?): string
	local negative = value < 0
	local amount = math.abs(value)
	local isEnglish = language == "en"
	local units = if isEnglish then EN_UNITS else KO_UNITS
	local step = if isEnglish then 1e3 else 1e4 -- 한 단위가 다음 단위가 되는 배수

	local text: string? = nil
	for index, unit in units do
		local size, suffix = unit[1], unit[2]
		if amount < size then
			continue
		end

		local scaled = amount / size
		local decimals = if scaled >= 100 then 0 elseif isEnglish and size >= 1e9 then 2 else 1
		local shown = trimNumber(scaled, decimals)

		-- 반올림해서 한 단위가 꽉 차면(예: 9,999.99만 → 10000만) 바로 위 단위로 쓴다.
		local larger = units[index - 1]
		if larger ~= nil and (tonumber(shown) or 0) >= step then
			shown = trimNumber(amount / larger[1], 1)
			suffix = larger[2]
		end

		text = shown .. suffix
		break
	end

	local result = text or Format.comma(amount)
	if negative and result ~= "0" then
		return "-" .. result
	end
	return result
end

-- 확률 막대나 로그에 쓰는 짧은 비율 표기. 0.25 → "25%"
function Format.ratio(ratio: number, decimals: number?): string
	return Format.percent(ratio * 100, decimals)
end

return Format
