--!strict
--[[
	OddsTableController — 확률표 창 (통합 기획서 3·8절).

	대장간 화면의 "확률표" 버튼(글자가 있는 버튼)으로 언제든 연다.
	표에 보이는 값은 "지금 실제로 적용되는" 최종 확률과 비용이다.
	  - 기본값: shared/Config/EnhanceTable
	  - 확률 버프 이벤트가 있으면 성공 + / 유지 - (실패는 그대로)
	  - 방지권을 켜 두었고 방지권이 있으면 실패 0%, 그만큼 유지
	  - 비용에는 가진 검 수 할증이 들어간다
	서버와 같은 Pure/EnhanceLogic 함수로 계산하므로 실제 판정과 어긋나지 않는다.
	1구간(실패 없음)과 2구간(실패하면 +10) 사이에 구분 줄이 있고, 지금 레벨 줄은 주황으로 강조한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local EnhanceTable = require(Shared:WaitForChild("Config"):WaitForChild("EnhanceTable"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local OddsTableController = {}
OddsTableController.Name = "OddsTableController"

local C = Theme.color
local ROW_HEIGHT = 30
local COLUMNS = { 0.14, 0.2, 0.2, 0.2, 0.26 }
local HEADER_KEYS =
	{ "ui.column.level", "ui.column.success", "ui.column.keep", "ui.column.fail", "ui.column.cost" }

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local stateLabel: TextLabel
local header: Frame
local headerCells: { TextLabel } = {}
local scroller: ScrollingFrame
local open = false

local function makeRow(parent: Instance, order: number, highlight: boolean): Frame
	local row = Components.frame(parent, {
		BackgroundColor3 = if highlight then Theme.shade(C.ember, -0.45) else C.sub,
		BackgroundTransparency = if highlight then 0 else 0.55,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		LayoutOrder = order,
	})
	Components.corner(row, 6)
	Components.list(row, "horizontal", 0)
	return row
end

local function cell(
	row: Instance,
	index: number,
	text: string,
	color: Color3,
	bold: boolean?
): TextLabel
	local label = Components.label(row, {
		text = text,
		color = color,
		size = Theme.text.small,
		font = if bold then Theme.font.bodyBold else Theme.font.body,
		align = Enum.TextXAlignment.Center,
		order = index,
		height = ROW_HEIGHT,
	})
	label.Size = UDim2.new(COLUMNS[index], 0, 1, 0)
	return label
end

local function build()
	gui = ScreenManager.createScreen("ForgeOddsTable", 10)
	gui.Enabled = false

	panel = Components.panel(gui, { Name = "Panel" })
	Components.closeButton(panel, function()
		ScreenManager.closeModal()
	end)

	local body = Components.frame(
		panel,
		{ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 1, -24) }
	)

	titleLabel = Components.label(body, {
		font = Theme.font.display,
		size = Theme.text.title,
		color = C.gold,
		outline = true,
		height = 40,
	})
	titleLabel.Size = UDim2.new(1, -56, 0, 40)

	stateLabel = Components.label(
		body,
		{ size = Theme.text.small, color = C.event, wrap = true, height = 40 }
	)
	stateLabel.Position = UDim2.fromOffset(0, 40)

	header = Components.frame(
		body,
		{ Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, -8, 0, ROW_HEIGHT) }
	)
	Components.list(header, "horizontal", 0)
	for index in HEADER_KEYS do
		headerCells[index] = cell(header, index, "", C.muted, true)
	end

	local scrollHolder = Components.frame(body, {
		Position = UDim2.fromOffset(0, 84 + ROW_HEIGHT + 4),
		Size = UDim2.new(1, 0, 1, -(84 + ROW_HEIGHT + 4)),
	})
	scroller = Components.scroller(scrollHolder, 3)
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout then
		ScreenManager.place(panel, layout.modal)
	end
end

local function refresh()
	if not open then
		return
	end

	local language = ClientState.getLanguage()
	local sword = ClientState.getEquipped()
	local currentLevel = if sword then sword.level else -1
	local swordCount = ClientState.getSwordCount()

	titleLabel.Text = Locale.get(language, "ui.oddsTableTitle")
	for index, key in HEADER_KEYS do
		headerCells[index].Text = Locale.get(language, key)
	end

	-- 지금 적용 중인 것: 이벤트(성공 +, 유지 -), 방지권(실패 → 유지)
	local event = ClientState.getLiveOps().event
	local buff = 0
	local notes: { string } = {}
	if type(event) == "table" and type(event.successBuff) == "number" then
		buff = event.successBuff
		table.insert(
			notes,
			Locale.get(language, "ui.eventActive", Locale.get(language, tostring(event.nameKey)))
		)
	end
	local protectActive = ClientState.isProtectActive()
	table.insert(
		notes,
		Locale.get(language, if protectActive then "ui.oddsProtectOn" else "ui.protectNote")
	)
	stateLabel.Text = table.concat(notes, "  ·  ")
	stateLabel.TextColor3 = if protectActive then C.protect else C.muted

	Components.clear(scroller)
	local order = 0

	for level = 0, EnhanceTable.MAX_LEVEL do
		-- 1구간과 2구간 사이 구분 줄
		if level == EnhanceTable.SAFE_LEVEL then
			order += 1
			local divider = Components.label(scroller, {
				text = Locale.get(language, "ui.zone2"),
				size = Theme.text.small,
				color = C.fail,
				font = Theme.font.bodyBold,
				align = Enum.TextXAlignment.Center,
				order = order,
				height = 24,
			})
			divider.Size = UDim2.new(1, -8, 0, 24)
		elseif level == 0 then
			order += 1
			local divider = Components.label(scroller, {
				text = Locale.get(language, "ui.zone1"),
				size = Theme.text.small,
				color = C.muted,
				font = Theme.font.bodyBold,
				align = Enum.TextXAlignment.Center,
				order = order,
				height = 24,
			})
			divider.Size = UDim2.new(1, -8, 0, 24)
		end

		order += 1
		local isCurrent = level == currentLevel
		local row = makeRow(scroller, order, isCurrent)
		cell(row, 1, Format.level(level), Theme.heatColor(level), true)

		local base = EnhanceTable.Odds[level]
		if base then
			local entry = EnhanceLogic.applyBuff(base, buff)
			if protectActive then
				entry = EnhanceLogic.applyProtect(entry)
			end
			local cost = EnhanceLogic.cost(
				level,
				swordCount,
				EnhanceTable.COST_BASE,
				EnhanceTable.SWORD_COUNT_EXPONENT
			)

			cell(row, 2, Format.percent(entry.success), C.ember, isCurrent)
			cell(row, 3, Format.percent(entry.keep), C.keep, isCurrent)
			cell(
				row,
				4,
				Format.percent(entry.fail),
				if entry.fail > 0 then C.fail else C.muted,
				isCurrent
			)
			cell(row, 5, Format.short(cost, language), C.text, isCurrent)
		else
			for index = 2, 5 do
				cell(row, index, "-", C.muted)
			end
		end
	end
end

function OddsTableController.Init()
	build()

	ScreenManager.registerModal("odds", function()
		open = true
		gui.Enabled = true
		refresh()
	end, function()
		open = false
		gui.Enabled = false
	end)

	ScreenManager.onLayout(place)
end

function OddsTableController.Start()
	ClientState.onChanged(refresh)
end

return OddsTableController
