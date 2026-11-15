--!strict
--[[
	CollectionController — 기록 창: 도감 / 랭킹 / 설정 탭 (통합 기획서 5-5·8절).

	도감: 20칸 격자(검 1종 = 1칸). 가진 검은 이름·등급 색 테두리·역대 최고 레벨(레벨 색)·
	      5/10/15/20강 기념 점 4개. 아직 없는 검은 어두운 "?" 칸, 아직 만들지 않은 칸은 "준비 중".
	랭킹: 최고 강화 상위 목록 (배틀 레이팅 순위는 폐지, 대체는 D7 미정).
	설정: 소리, 언어.
	도감은 서버에 따로 묻지 않고 복제받은 데이터(swords, codex)로 그린다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local CollectionController = {}
CollectionController.Name = "CollectionController"

local C = Theme.color
local CODEX_SLOTS = 20 -- 기본 검 20종 (지금 정의된 검이 적으면 나머지는 "준비 중")
local RANK_KIND = "level"

type Tab = "codex" | "rank" | "settings"

local gui: ScreenGui
local panel: Frame
local tabs: Components.Tabs
local content: Frame
local open = false
local activeTab: Tab = "codex"

local boardRemote: RemoteFunction
local settingRemote: RemoteFunction

local function codexCell(
	parent: Instance,
	language: string,
	weaponId: string?,
	data: any,
	order: number
)
	local info = if weaponId then Weapons.get(weaponId) else nil
	local sword = if weaponId and data then data.swords[weaponId] else nil

	local cell = Components.frame(parent, {
		BackgroundColor3 = if sword then C.sub else C.bg,
		BackgroundTransparency = if sword then 0.1 else 0.3,
		LayoutOrder = order,
	})
	Components.corner(cell, 10)

	if info == nil then
		-- 아직 만들지 않은 검 칸 (D22)
		Components.stroke(cell, C.line, 1)
		local soon = Components.label(cell, {
			text = Locale.get(language, "ui.codexSoon"),
			size = Theme.text.small,
			color = C.disabled,
			align = Enum.TextXAlignment.Center,
		})
		soon.Size = UDim2.fromScale(1, 1)
		return
	end

	local rarityColor = Theme.rarityColor(info.rarity)
	Components.stroke(cell, if sword then rarityColor else Theme.shade(rarityColor, -0.6), 2)

	if sword == nil then
		local mark = Components.label(cell, {
			text = "?",
			font = Theme.font.display,
			size = Theme.text.big,
			color = Theme.shade(rarityColor, -0.4),
			align = Enum.TextXAlignment.Center,
		})
		mark.Size = UDim2.new(1, 0, 0.62, 0)
		local rarity = Components.label(cell, {
			text = Locale.get(language, `rarity.{info.rarity}`),
			size = Theme.text.small,
			color = C.muted,
			align = Enum.TextXAlignment.Center,
		})
		rarity.Position = UDim2.fromScale(0, 0.62)
		rarity.Size = UDim2.new(1, 0, 0.3, 0)
		return
	end

	local name = Components.label(cell, {
		text = Locale.get(language, info.nameKey),
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
	})
	name.Position = UDim2.fromOffset(4, 4)
	name.Size = UDim2.new(1, -8, 0, 22)

	local best = Components.label(cell, {
		text = Format.level(sword.bestLevel),
		font = Theme.font.display,
		size = Theme.text.title,
		color = Theme.heatColor(sword.bestLevel),
		outline = true,
		align = Enum.TextXAlignment.Center,
	})
	best.Position = UDim2.new(0, 0, 0.32, 0)
	best.Size = UDim2.new(1, 0, 0.34, 0)

	-- 기념 점 4개 (5·10·15·20강)
	local dots = Components.frame(
		cell,
		{ Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 12) }
	)
	local dotList = Components.list(dots, "horizontal", 5, Enum.HorizontalAlignment.Center)
	dotList.VerticalAlignment = Enum.VerticalAlignment.Center
	for index, milestone in Weapons.CODEX_MILESTONES do
		local reached = data.codex[`{weaponId}:{milestone}`] == true
		local dot = Components.frame(dots, {
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = if reached then Theme.heatColor(milestone) else C.bg,
			BackgroundTransparency = 0,
			LayoutOrder = index,
		})
		Components.round(dot)
		Components.stroke(dot, C.line, 1)
	end
end

local function renderCodex()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	Components.clear(content)
	local holder = Components.frame(content)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.line
	scroll.Parent = holder

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.CellSize = UDim2.new(0.2, -8, 0, 104)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	if data == nil then
		return
	end

	for slot = 1, CODEX_SLOTS do
		codexCell(scroll, language, Weapons.Order[slot], data, slot)
	end
end

local function renderRanking()
	local language = ClientState.getLanguage()
	Components.clear(content)

	local title = Components.label(content, {
		text = Locale.get(language, `ui.rank.{RANK_KIND}`),
		font = Theme.font.display,
		size = Theme.text.label,
		color = C.gold,
	})
	title.Size = UDim2.new(1, 0, 0, 30)

	local holder = Components.frame(
		content,
		{ Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) }
	)
	local scroll = Components.scroller(holder, 4)
	Components.label(scroll, { text = "...", color = C.muted })

	task.spawn(function()
		local ok, entries = pcall(function()
			return boardRemote:InvokeServer(RANK_KIND)
		end)
		if not open or activeTab ~= "rank" then
			return
		end

		Components.clear(scroll)
		if not ok or type(entries) ~= "table" or #entries == 0 then
			Components.label(
				scroll,
				{ text = Locale.get(language, "ui.rank.empty"), color = C.muted }
			)
			return
		end

		local myUserId = Players.LocalPlayer.UserId
		for index, entry in entries do
			local mine = entry.userId == myUserId
			local row = Components.frame(scroll, {
				Size = UDim2.new(1, -8, 0, 40),
				BackgroundColor3 = if mine then Theme.shade(C.ember, -0.5) else C.sub,
				BackgroundTransparency = 0.3,
				LayoutOrder = index,
			})
			Components.corner(row, 8)
			local medal = if entry.rank == 1
				then C.gold
				elseif entry.rank == 2 then Color3.fromRGB(216, 216, 216)
				elseif entry.rank == 3 then Color3.fromRGB(217, 154, 106)
				else C.muted
			local rank = Components.label(row, {
				text = `{entry.rank}`,
				font = Theme.font.display,
				size = Theme.text.label,
				color = medal,
				align = Enum.TextXAlignment.Center,
			})
			rank.Size = UDim2.new(0, 48, 1, 0)
			local name = Components.label(row, {
				text = tostring(entry.name),
				font = Theme.font.bodyBold,
				color = if mine then C.ember else C.text,
			})
			name.Position = UDim2.fromOffset(52, 0)
			name.Size = UDim2.new(1, -140, 1, 0)
			local value = Components.label(row, {
				text = Format.level(entry.value),
				font = Theme.font.display,
				size = Theme.text.label,
				color = Theme.heatColor(entry.value),
				outline = true,
				align = Enum.TextXAlignment.Right,
			})
			value.AnchorPoint = Vector2.new(1, 0)
			value.Position = UDim2.new(1, -12, 0, 0)
			value.Size = UDim2.new(0, 80, 1, 0)
		end
	end)
end

local function applySetting(key: string, value: any)
	task.spawn(function()
		pcall(function()
			settingRemote:InvokeServer(key, value)
		end)
	end)
end

local function renderSettings()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()
	Components.clear(content)
	if data == nil then
		return
	end

	local list = Components.frame(content)
	Components.list(list, "vertical", 10)

	local sfx = Components.button(list, {
		text = Locale.get(language, if data.settings.sfx then "ui.sfxOn" else "ui.sfxOff"),
		style = if data.settings.sfx then "primary" else "secondary",
		order = 1,
	})
	sfx.Activated:Connect(function()
		applySetting("sfx", not data.settings.sfx)
	end)

	local lang = Components.button(
		list,
		{ text = Locale.get(language, "ui.language"), style = "secondary", order = 2 }
	)
	lang.Activated:Connect(function()
		applySetting("language", if ClientState.getLanguage() == "ko" then "en" else "ko")
	end)
end

local function refresh()
	if not open then
		return
	end
	local language = ClientState.getLanguage()
	for key, button in tabs.buttons do
		button.Text = Locale.get(language, `ui.tab.{key}`)
	end
	tabs.select(activeTab)

	if activeTab == "codex" then
		renderCodex()
	elseif activeTab == "rank" then
		renderRanking()
	else
		renderSettings()
	end
end

local function build()
	gui = ScreenManager.createScreen("ForgeRecords", 10)
	gui.Enabled = false

	panel = Components.panel(gui, { Name = "Panel" })
	Components.closeButton(panel, function()
		ScreenManager.closeModal()
	end)

	local tabHolder = Components.frame(
		panel,
		{ Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -80, 0, Theme.rowHeight) }
	)
	tabs = Components.tabs(tabHolder, { "codex", "rank", "settings" }, function(key)
		activeTab = key :: Tab
		refresh()
	end)

	content = Components.frame(panel, {
		Position = UDim2.fromOffset(16, 8 + Theme.rowHeight + 12),
		Size = UDim2.new(1, -32, 1, -(8 + Theme.rowHeight + 12 + 14)),
	})
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout then
		ScreenManager.place(panel, layout.modal)
	end
end

function CollectionController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	boardRemote = remotesFolder:WaitForChild(Remotes.Functions.GetLeaderboard) :: RemoteFunction
	settingRemote = remotesFolder:WaitForChild(Remotes.Functions.SetSetting) :: RemoteFunction

	ScreenManager.registerModal("records", function()
		open = true
		gui.Enabled = true
		refresh()
	end, function()
		open = false
		gui.Enabled = false
	end)

	ScreenManager.onLayout(place)
end

function CollectionController.Start()
	-- 설정을 바꾸면 서버가 데이터를 다시 내려 주므로 그때 갱신한다 (랭킹은 다시 묻지 않는다).
	ClientState.onChanged(function()
		if open and activeTab ~= "rank" then
			refresh()
		end
	end)
end

return CollectionController
