--!strict
--[[
	SoundController — 결과 연출 사운드.

	설정(sfx)을 존중하는 재생 창구. 음원이 없으면 아무 일도 하지 않는다.
	다른 컨트롤러는 이 함수만 호출한다.
]]

local SoundService = game:GetService("SoundService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local SoundController = {}
SoundController.Name = "SoundController"

--[[
	[개발자 입력 필요] 소리 에셋 ID 를 채운다 ("rbxassetid://숫자"). 비어 있으면 재생하지 않는다.
	느낌은 디자인 시안(통합 기획서 8-2절)의 "소리 자리" 표를 따른다.
]]
local SOUND_IDS: { [string]: string } = {
	success = "", -- 강화 성공
	keep = "", -- 유지
	fail = "", -- 실패 (치익 식는 소리)
	protected = "", -- 방지권이 막음
	max = "", -- 20강
	hammer = "", -- 망치질 "깡"
	click = "", -- 버튼
	coin = "", -- 금화 짤랑 (러닝머신·경주 보상)
	tick = "", -- 카운트다운 째깍
	go = "", -- 출발
	caught = "", -- 잡힘
}

local cache: { [string]: Sound } = {}

function SoundController.play(key: string)
	local data = ClientState.getData()
	if data and data.settings and data.settings.sfx == false then
		return
	end

	local assetId = SOUND_IDS[key]
	if assetId == nil or assetId == "" then
		return
	end

	local sound = cache[key]
	if sound == nil then
		sound = Instance.new("Sound")
		sound.SoundId = assetId
		sound.Parent = SoundService
		cache[key] = sound
	end

	sound:Play()
end

function SoundController.Init() end

function SoundController.Start() end

return SoundController
