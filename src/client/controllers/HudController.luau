--!strict
--[[
	HudController — 위쪽 왼쪽 재화 칩(골드 · 파편 · 방지권)과 공지·점검 배너 (통합 기획서 8-1절).

	- 칩은 모양과 색이 고정이다: 골드 = 금색 동그라미, 파편 = 하늘색 마름모, 방지권 = 초록 방패 모양.
	- 큰 숫자는 줄여 쓴다(1.2억 / 120M). 정확한 값은 대장간 화면과 채팅 /정보 에서 볼 수 있다.
	- 골드가 늘면 칩이 잠깐 커졌다 돌아오고 "+N" 이 떠오른다.
	- 로비·대장간에서 보이고 경주 중에는 숨는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local HudController = {}
HudController.Name = "HudController"

local gui: ScreenGui
local chipRow: Frame
local goldChip: Components.Chip
local shardChip: Components.Chip
local ticketChip: Components.Chip
local banner: TextLabel

local lastGold: number? = nil

local function pop(frame: GuiObject)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 1.12
	TweenService:Create(uiScale, Theme.motion.pop, { Scale = 1 }):Play()
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout == nil then
		return
	end

	ScreenManager.place(chipRow, layout.chips)

	-- 배너: 로비에서는 피드 한 줄 자리, 대장간에서는 칩 오른쪽 위 띠 전체
	local mode = ScreenManager.getMode()
	if mode == "lobby" then
		ScreenManager.place(banner, layout.feedLobby)
	else
		local x = layout.chips.x + layout.chips.w + 8
		ScreenManager.place(banner, {
			x = x,
			y = layout.chips.y,
			w = layout.width - layout.chips.x - x,
			h = layout.chips.h,
		})
	end
end

local function render()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	gui.Enabled = not ScreenManager.isRacing()

	if data then
		goldChip.value.Text = Format.short(data.gold, language)
		shardChip.value.Text = Format.short(data.shards, language)
		ticketChip.value.Text = Format.short(data.protectTickets, language)

		local previous = lastGold
		if previous ~= nil and data.gold > previous then
			pop(goldChip.frame)
			Components.floatText(
				goldChip.frame,
				"+" .. Format.short(data.gold - previous, language),
				Theme.color.gold,
				UDim2.new(0.5, 0, 1, 26),
				Theme.text.label
			)
		end
		lastGold = data.gold
	else
		goldChip.value.Text = "-"
		shardChip.value.Text = "-"
		ticketChip.value.Text = "-"
	end

	local liveOps = ClientState.getLiveOps()
	if liveOps.maintenance then
		banner.Visible = true
		banner.Text = Locale.get(language, "ui.maintenance")
	elseif liveOps.notice ~= "" then
		banner.Visible = true
		banner.Text = liveOps.notice
	else
		banner.Visible = false
	end

	place()
end

-- 피드가 배너와 같은 자리를 쓰므로, 배너가 떠 있는지 알려 준다.
function HudController.isBannerVisible(): boolean
	return banner ~= nil and banner.Visible
end

function HudController.Init()
	gui = ScreenManager.createScreen("ForgeHud", 4)

	chipRow = Components.frame(gui, { Name = "Chips" })
	Components.list(chipRow, "horizontal", 8)

	goldChip = Components.chip(chipRow, "coin", Theme.color.gold)
	shardChip = Components.chip(chipRow, "shard", Theme.color.shard)
	ticketChip = Components.chip(chipRow, "ticket", Theme.color.ticket)
	for index, chip in { goldChip, shardChip, ticketChip } do
		chip.frame.Size = UDim2.new(1 / 3, -6, 1, 0)
		chip.frame.LayoutOrder = index
	end

	banner = Components.label(gui, {
		size = Theme.text.small,
		color = Theme.color.gold,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	banner.Name = "Banner"
	banner.BackgroundColor3 = Theme.color.bg
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	Components.corner(banner, 10)
	Components.stroke(banner, Theme.color.ember, 1.5)

	ScreenManager.onLayout(place)
	ScreenManager.onStateChanged(render)
	ClientState.onChanged(render)
	render()
end

function HudController.Start() end

return HudController
