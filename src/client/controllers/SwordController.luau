--!strict
--[[
	SwordController — 검 보관함 화면 (통합 기획서 5절).

	위쪽: 가진 검 목록. 눌러서 착용 검을 바꾼다.
	아래쪽: 새 검 뽑기. 가격과 "지금 내 기준" 확률표(등급별·검별 %)를 항상 보여 주고,
	        버튼을 두 번 눌러야 골드를 쓴다(한 번 누르면 확인 문구로 바뀐다).

	확률표는 서버가 실제 뽑기에 쓰는 것과 같은 Pure/SwordLogic 함수로 만든다.
	클라이언트는 "착용할 검 id" 와 "뽑기 요청"만 보낸다. 가격·결과는 서버가 정한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local SwordLogic = require(Pure:WaitForChild("SwordLogic"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local SwordController = {}
SwordController.Name = "SwordController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_DISABLED = Color3.fromRGB(72, 68, 76)

local TOUCH_MIN = 44

local RARITY_OF = Weapons.rarityMap()

local gui: ScreenGui
local titleLabel: TextLabel
local scroller: ScrollingFrame
local closeButton: TextButton

local equipRemote: RemoteFunction
local drawRemote: RemoteFunction

local busy = false
-- 뽑기 버튼을 한 번 누른 상태인지 (두 번째에 실제로 요청한다)
local confirming = false

local function makeLabel(text: string, color: Color3, order: number, height: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Size = UDim2.new(1, 0, 0, height or 22)
	label.Text = text
	label.LayoutOrder = order
	label.Parent = scroller
	return label
end

local function makeButton(text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLOR_SUB
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.TextColor3 = COLOR_TEXT
	button.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	button.Text = text
	button.LayoutOrder = order
	button.Parent = scroller

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function showError(reason: string)
	FeedController.pushRaw(
		Locale.get(ClientState.getLanguage(), `error.{reason}`),
		Color3.fromRGB(255, 140, 130)
	)
end

local refresh: () -> ()

local function requestEquip(swordId: string)
	if busy then
		return
	end
	busy = true

	local ok, response = pcall(function()
		return equipRemote:InvokeServer(swordId)
	end)

	busy = false

	if not ok or type(response) ~= "table" then
		showError("unknown")
		return
	end
	if response.ok ~= true then
		showError(tostring(response.reason))
		return
	end

	ClientState.setOdds(response.odds)
	SoundController.play("click")
end

local function requestDraw()
	if busy then
		return
	end
	busy = true
	confirming = false
	refresh()

	local ok, response = pcall(function()
		return drawRemote:InvokeServer()
	end)

	busy = false

	if not ok or type(response) ~= "table" then
		showError("unknown")
		refresh()
		return
	end
	if response.ok ~= true then
		showError(tostring(response.reason))
		refresh()
		return
	end

	-- 서버 응답을 받은 뒤에만 결과를 알린다.
	local language = ClientState.getLanguage()
	local info = Weapons.get(tostring(response.swordId))
	if info then
		FeedController.pushRaw(
			Locale.get(
				language,
				"ui.drawResult",
				Locale.get(language, info.nameKey),
				Locale.get(language, `rarity.{info.rarity}`)
			),
			COLOR_ACCENT
		)
	end

	ClientState.setOdds(response.odds)
	SoundController.play("success")
	refresh()
end

function refresh()
	if not gui.Enabled then
		return
	end

	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	titleLabel.Text = Locale.get(language, "ui.swordsTitle")
	closeButton.Text = Locale.get(language, "ui.close")

	for _, child in scroller:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child:Destroy()
		end
	end

	if data == nil then
		makeLabel(Locale.get(language, "error.not_ready"), COLOR_MUTED, 1)
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- 가진 검 목록 (눌러서 착용)
	local swordCount = 0
	for _, weaponId in Weapons.Order do
		local sword = data.swords[weaponId]
		local info = Weapons.get(weaponId)
		if sword == nil or info == nil then
			continue
		end
		swordCount += 1

		local name = if sword.customName and sword.customName ~= ""
			then sword.customName
			else Locale.get(language, info.nameKey)
		local text = Locale.get(
			language,
			"ui.swordRow",
			name,
			Locale.get(language, `rarity.{info.rarity}`),
			sword.level
		)

		local isEquipped = data.equippedId == weaponId
		if isEquipped then
			text = Locale.get(language, "ui.equipped") .. " " .. text
		end

		local button = makeButton(text, nextOrder())
		button.TextColor3 = if isEquipped then COLOR_ACCENT else COLOR_TEXT

		if not isEquipped then
			button.Activated:Connect(function()
				task.spawn(requestEquip, weaponId)
			end)
		end
	end

	-- 새 검 뽑기
	makeLabel(Locale.get(language, "ui.drawTitle"), COLOR_ACCENT, nextOrder(), 26)
	makeLabel(Locale.get(language, "ui.drawDesc"), COLOR_MUTED, nextOrder(), 54)

	local drawTable =
		SwordLogic.buildDrawTable(Weapons.Order, RARITY_OF, Weapons.DRAW_WEIGHTS, data.swords)

	if #drawTable.entries == 0 then
		makeLabel(Locale.get(language, "ui.drawNone"), COLOR_MUTED, nextOrder())
		return
	end

	local price = SwordLogic.slotPrice(
		EnhanceLogic.cost(
			Weapons.SLOT_PRICE_LEVEL,
			math.max(1, swordCount),
			EnhanceTable.COST_BASE,
			EnhanceTable.SWORD_COUNT_EXPONENT
		),
		Weapons.SLOT_PRICE_MULTIPLIER
	)

	makeLabel(Locale.get(language, "ui.drawPrice", Format.comma(price)), COLOR_TEXT, nextOrder())

	-- 확률표: 등급별 합계 다음에 검별. 전부 합치면 100%.
	makeLabel(Locale.get(language, "ui.drawOddsTitle"), COLOR_MUTED, nextOrder())

	for _, share in drawTable.rarities do
		makeLabel(
			Locale.get(
				language,
				"ui.drawRarityRow",
				Locale.get(language, `rarity.{share.rarity}`),
				Format.percent(share.percent, SwordLogic.PERCENT_DECIMALS)
			),
			COLOR_TEXT,
			nextOrder()
		)
	end

	for _, entry in drawTable.entries do
		local info = Weapons.get(entry.id)
		makeLabel(
			Locale.get(
				language,
				"ui.drawSwordRow",
				if info then Locale.get(language, info.nameKey) else entry.id,
				Locale.get(language, `rarity.{entry.rarity}`),
				Format.percent(entry.percent, SwordLogic.PERCENT_DECIMALS)
			),
			COLOR_MUTED,
			nextOrder()
		)
	end

	local affordable = data.gold >= price
	local buyButton = makeButton(
		if confirming
			then Locale.get(language, "ui.drawConfirm", Format.comma(price))
			else Locale.get(language, "ui.drawBuy"),
		nextOrder()
	)
	buyButton.Font = Enum.Font.GothamBold
	buyButton.BackgroundColor3 = if affordable and not busy then COLOR_ACCENT else COLOR_DISABLED
	buyButton.TextColor3 = Color3.fromRGB(24, 18, 10)

	buyButton.Activated:Connect(function()
		if busy then
			return
		end
		if not affordable then
			showError("not_enough_gold")
			return
		end

		if confirming then
			task.spawn(requestDraw)
		else
			confirming = true
			refresh()
		end
	end)
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeSwords"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 13
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = gui

	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)
	panel.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(520, 640)
	sizeConstraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 20
	titleLabel.TextColor3 = COLOR_TEXT
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Size = UDim2.new(1, 0, 0, 28)
	titleLabel.Text = ""
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = panel

	scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.new(1, 0, 1, -96)
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 4
	scroller.LayoutOrder = 2
	scroller.Parent = panel

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, 4)
	scrollList.Parent = scroller

	closeButton = Instance.new("TextButton")
	closeButton.BackgroundColor3 = COLOR_SUB
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = COLOR_TEXT
	closeButton.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	closeButton.Text = ""
	closeButton.LayoutOrder = 3
	closeButton.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = closeButton

	local function close()
		gui.Enabled = false
		confirming = false
	end

	closeButton.Activated:Connect(close)
	dim.Activated:Connect(close)
end

function SwordController.toggle()
	if gui.Enabled then
		gui.Enabled = false
		confirming = false
		return
	end

	gui.Enabled = true
	refresh()
end

function SwordController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	equipRemote = remotesFolder:WaitForChild(Remotes.Functions.EquipSword) :: RemoteFunction
	drawRemote = remotesFolder:WaitForChild(Remotes.Functions.BuySwordSlot) :: RemoteFunction
end

function SwordController.Start()
	-- 착용·뽑기·강화로 데이터가 바뀌면 열려 있는 화면을 다시 그린다.
	ClientState.onChanged(refresh)
end

return SwordController
