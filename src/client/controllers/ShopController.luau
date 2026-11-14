--!strict
--[[
	ShopController — 상점 화면 (통합 기획서 7·8절).

	위쪽: Robux 로 사는 방지권 상품 (확정 1개 / 확정 묶음 / 확률형)
	아래쪽: 파편으로 하는 방지권 뽑기 (Robux 가 닿지 않는다)

	클라이언트는 상품 ID 를 알지 못한다. "이 항목을 사고 싶다"는 키만 서버에 보내고,
	실제 구매창은 서버가 띄운다. 지급과 뽑기도 전부 서버가 한다.

	확률 공개 (로블록스 유료 확률형 정책, 기획서 P10):
	- 확률형 상품과 파편 뽑기는 사기 전에 모든 결과와 확률(%, 합계 100)을 버튼 바로 아래에 항상 보여 준다.
	  숨겨진 창이나 아이콘 뒤에 두지 않는다. 이 숫자는 서버가 보낸 값이다.
	- 천장 포인트(꽝 3번이면 방지권 1개)는 규칙과 현재 점수를 함께 보여 주고,
	  다음 꽝에서 천장이 차는 상태면 꽝 줄의 설명을 "방지권을 받는다"로 바꿔 보여 준다.

	아직 등록되지 않았거나 내용이 비어 있는 상품은 서버가 목록에서 빼기 때문에 여기에는 오지 않는다.
	유료 확률형이 제한된 유저에게는 서버가 확률형 상품을 보내지 않는다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local DrawLogic = require(Pure:WaitForChild("DrawLogic"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local ShopController = {}
ShopController.Name = "ShopController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_DISABLED = Color3.fromRGB(72, 68, 76)
local COLOR_ERROR = Color3.fromRGB(255, 140, 130)

local TOUCH_MIN = 44
local PERCENT_DECIMALS = 2

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local noticeLabel: TextLabel
local scroller: ScrollingFrame
local closeButton: TextButton

local itemsRemote: RemoteFunction
local promptRemote: RemoteFunction
local shardRemote: RemoteFunction

-- 서버가 마지막으로 보낸 상점 목록 (Types.ShopState). 아직 못 받았으면 nil.
local shopState: any = nil
local loading = false
local drawing = false

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLOR_SUB
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.TextColor3 = COLOR_TEXT
	button.TextSize = 15
	button.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	button.Text = ""
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function makeLine(text: string, color: Color3, order: number, height: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Size = UDim2.new(1, 0, 0, height or 20)
	label.Text = text
	label.LayoutOrder = order
	label.Parent = scroller
	return label
end

local function showError(reason: string)
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), COLOR_ERROR)
end

-- 상품 한 줄에 쓸 이름. 확정형은 방지권 개수를 함께 보여 준다.
local function itemLabel(language: string, item: any): string
	return Locale.get(language, `shop.{tostring(item.key)}`, tonumber(item.ticketAmount) or 0)
end

--[[
	결과 한 줄: "· 방지권 3개  10%" / "· 꽝 …  70%"
	missKey 는 꽝 줄에 쓸 문구 키(유료는 천장 포인트 안내가 붙고, 파편 뽑기는 그냥 꽝이다).
]]
local function outcomeText(language: string, outcome: any, missKey: string, ...: any): string
	local percent = Format.percent(tonumber(outcome.percent) or 0, PERCENT_DECIMALS)
	local tickets = tonumber(outcome.tickets) or 0

	if tickets > 0 then
		return Locale.get(language, "shop.outcomeTickets", tickets, percent)
	end

	-- 꽝 줄은 문구마다 끼워 넣는 값이 달라서 확률을 뒤에 따로 붙인다.
	return `{Locale.get(language, missKey, ...)}  {percent}`
end

local function requestPurchase(key: string)
	local ok, response = pcall(function()
		return promptRemote:InvokeServer(key)
	end)

	if not ok or type(response) ~= "table" then
		showError("unknown")
	elseif response.ok ~= true then
		showError(tostring(response.reason))
	end
end

local render: () -> ()

local function requestShardDraw()
	if drawing then
		return
	end
	drawing = true
	render()

	local ok, response = pcall(function()
		return shardRemote:InvokeServer()
	end)

	drawing = false

	if not ok or type(response) ~= "table" then
		showError("unknown")
	elseif response.ok ~= true then
		showError(tostring(response.reason))
	else
		-- 결과는 서버가 정한 값이다.
		local language = ClientState.getLanguage()
		local tickets = tonumber(response.tickets) or 0
		if tickets > 0 then
			SoundController.play("success")
			FeedController.pushRaw(Locale.get(language, "shop.shardDrawWin", tickets), COLOR_ACCENT)
		else
			SoundController.play("keep")
			FeedController.pushRaw(Locale.get(language, "shop.shardDrawMiss"), COLOR_MUTED)
		end
	end

	render()
end

-- 마지막으로 받은 목록과 지금 내 데이터(천장 포인트, 파편)로 화면을 다시 그린다. 서버를 부르지 않는다.
render = function()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	titleLabel.Text = Locale.get(language, "ui.shopTitle")
	noticeLabel.Text = Locale.get(language, "shop.notice")
	closeButton.Text = Locale.get(language, "ui.close")

	for _, child in scroller:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local state = shopState
	if type(state) ~= "table" then
		makeLine(
			Locale.get(language, if loading then "ui.loading" else "ui.shopEmpty"),
			COLOR_MUTED,
			1,
			40
		)
		return
	end

	local items = if type(state.items) == "table" then state.items else {}
	local shardDraw = if type(state.shardDraw) == "table" then state.shardDraw else nil

	if #items == 0 and shardDraw == nil then
		makeLine(Locale.get(language, "ui.shopEmpty"), COLOR_MUTED, 1, 40)
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local pityPerMiss = tonumber(state.pityPerMiss) or 1
	local pityThreshold = tonumber(state.pityThreshold) or 0
	local pityTickets = tonumber(state.pityTickets) or 0
	local pityPoints = if data then data.pityPoints else 0

	-- Robux 상품
	if #items > 0 then
		makeLine(Locale.get(language, "shop.sectionPaid"), COLOR_ACCENT, nextOrder(), 22)
	end

	for _, item in items do
		if type(item) ~= "table" or type(item.key) ~= "string" then
			continue
		end

		local key = item.key
		local row = makeButton(scroller, {
			Text = itemLabel(language, item),
			LayoutOrder = nextOrder(),
		})
		row.Activated:Connect(function()
			SoundController.play("click")
			task.spawn(requestPurchase, key)
		end)

		if item.kind == "random" and type(item.outcomes) == "table" then
			-- 사기 전에 모든 결과와 확률을 보여 준다(합계 100%).
			makeLine(Locale.get(language, "shop.oddsTitle"), COLOR_MUTED, nextOrder())

			local pityNext = DrawLogic.isPityNext(pityPoints, pityPerMiss, pityThreshold)
			for _, outcome in item.outcomes do
				local text = if pityNext
					then outcomeText(language, outcome, "shop.outcomeMissPity", pityTickets)
					else outcomeText(language, outcome, "shop.outcomeMiss", pityPerMiss)
				makeLine(text, COLOR_TEXT, nextOrder())
			end

			makeLine(
				Locale.get(
					language,
					"shop.pity",
					pityPoints,
					pityThreshold,
					pityPerMiss,
					pityThreshold,
					pityTickets
				),
				COLOR_ACCENT,
				nextOrder(),
				54
			)
		end
	end

	-- 파편 뽑기
	if shardDraw ~= nil and type(shardDraw.outcomes) == "table" then
		local cost = tonumber(shardDraw.cost) or 0
		local shards = if data then data.shards else 0
		local affordable = shards >= cost and not drawing

		makeLine(Locale.get(language, "shop.sectionFree"), COLOR_ACCENT, nextOrder(), 22)

		local row = makeButton(scroller, {
			Text = Locale.get(language, "shop.shardDraw", cost),
			LayoutOrder = nextOrder(),
			BackgroundColor3 = if affordable then COLOR_SUB else COLOR_DISABLED,
			TextColor3 = if affordable then COLOR_TEXT else COLOR_MUTED,
			Active = affordable,
			AutoButtonColor = affordable,
		})
		row.Activated:Connect(function()
			if affordable then
				SoundController.play("click")
				task.spawn(requestShardDraw)
			end
		end)

		makeLine(
			Locale.get(language, "shop.shardOwned", Format.comma(shards)),
			COLOR_MUTED,
			nextOrder()
		)
		makeLine(Locale.get(language, "shop.oddsTitle"), COLOR_MUTED, nextOrder())
		for _, outcome in shardDraw.outcomes do
			makeLine(
				outcomeText(language, outcome, "shop.outcomeMissFree"),
				COLOR_TEXT,
				nextOrder()
			)
		end
	end
end

-- 서버에서 상점 목록을 다시 받아 온다.
local function refresh()
	loading = true
	render()

	local ok, state = pcall(function()
		return itemsRemote:InvokeServer()
	end)

	loading = false
	shopState = if ok and type(state) == "table" then state else nil
	render()
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
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

	panel = Instance.new("Frame")
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.8, 0)
	panel.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(460, 620)
	sizeConstraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
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
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = panel

	scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.new(1, 0, 1, -140)
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 4
	scroller.LayoutOrder = 2
	scroller.Parent = panel

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, 6)
	scrollList.Parent = scroller

	noticeLabel = Instance.new("TextLabel")
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.GothamMedium
	noticeLabel.TextSize = 12
	noticeLabel.TextColor3 = COLOR_MUTED
	noticeLabel.TextWrapped = true
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.Size = UDim2.new(1, 0, 0, 36)
	noticeLabel.LayoutOrder = 3
	noticeLabel.Parent = panel

	closeButton = makeButton(panel, { LayoutOrder = 4 })
	closeButton.Activated:Connect(function()
		gui.Enabled = false
	end)
	dim.Activated:Connect(function()
		gui.Enabled = false
	end)
end

function ShopController.toggle()
	if gui.Enabled then
		gui.Enabled = false
		return
	end

	gui.Enabled = true
	task.spawn(refresh)
end

function ShopController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	itemsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetShopItems) :: RemoteFunction
	promptRemote = remotesFolder:WaitForChild(Remotes.Functions.PromptPurchase) :: RemoteFunction
	shardRemote = remotesFolder:WaitForChild(Remotes.Functions.ShardDraw) :: RemoteFunction

	-- 천장 포인트나 파편이 바뀌면(구매·뽑기 직후) 열려 있는 상점을 바로 다시 그린다.
	ClientState.onChanged(function()
		if gui.Enabled then
			render()
		end
	end)
end

function ShopController.Start() end

return ShopController
