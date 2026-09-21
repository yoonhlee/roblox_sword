--!strict
--[[
	SoundController — 결과 연출 사운드.

	Phase 2 에서 실제 음원을 붙인다. 지금은 설정(sfx)을 존중하는 재생 창구만 있고
	음원이 없으면 아무 일도 하지 않는다. 다른 컨트롤러는 이미 이 함수만 호출한다.
]]

local SoundService = game:GetService("SoundService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local SoundController = {}
SoundController.Name = "SoundController"

-- [Phase 2] 사운드 에셋 ID 를 채운다. 비어 있으면 재생하지 않는다.
local SOUND_IDS: { [string]: string } = {
	success = "",
	keep = "",
	destroy = "",
	protected = "",
	click = "",
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
