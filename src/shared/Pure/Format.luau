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

-- 확률 막대나 로그에 쓰는 짧은 비율 표기. 0.25 → "25%"
function Format.ratio(ratio: number, decimals: number?): string
	return Format.percent(ratio * 100, decimals)
end

return Format
