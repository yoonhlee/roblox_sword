--!strict
--[[
	ShopController — 상점 창 (통합 기획서 7·8절).

	위: Robux 로 사는 방지권 상품 카드 (확정 1개 / 확정 묶음 / 확률형)
	아래: 파편으로 하는 방지권 뽑기 (Robux 가 닿지 않는다)

	클라이언트는 상품 ID 를 모른다. "이 항목을 사고 싶다"는 키만 보내고 구매창·지급·뽑기는 서버가 한다.

	확률 공개 (로블록스 유료 확률형 정책, 기획서 P10):
	- 확률형 상품과 파편 뽑기는 사기 전에 모든 결과와 확률(%, 합계 100)을 버튼 바로 아래에 항상 보여 준다.
	  이 숫자는 서버가 보낸 값이다. 숨겨진 창이나 아이콘 뒤에 두지 않는다.
	- 천장 포인트(꽝 3번이면 방지권 1개)는 규칙과 현재 점수(막대 n/3)를 함께 보여 주고,
	  다음 꽝에서 천장이 차는 상태면 꽝 줄의 설명을 "방지권을 받는다"로 바꿔 보여 준다.
	아직 등록되지 않았거나 내용이 비어 있는 상품은 서버가 목록에서 빼므로 여기 오지 않는다.
	유료 확률형이 제한된 유저에게는 서버가 확률형 상품을 보내지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local DrawLogic = require(Pure:WaitForChild("DrawLogic"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local controllers = script.Parent
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local ShopController = {}
ShopController.Name = "ShopController"

local C = Theme.color
local PERCENT_DECIMALS = 2

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local noticeLabel: TextLabel
local scroller: ScrollingFrame

local itemsRemote: RemoteFunction
local promptRemote: RemoteFunction
local shardRemote: RemoteFunction

local shopState: any = nil
local loading = false
local drawing = false
local open = false

local function showError(reason: string)
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), C.fail)
end

local function line(
	parent: Instance,
	text: string,
	color: Color3,
	order: number,
	bold: boolean?,
	height: number?
): TextLabel
	local label = Components.label(parent, {
		text = text,
		color = color,
		size = Theme.text.small,
		font = if bold then Theme.font.bodyBold else Theme.font.body,
		wrap = height ~= nil,
		order = order,
		height = height,
	})
	label.Size = UDim2.new(1, -8, 0, height or 24)
	return label
end

local function outcomeText(language: string, outcome: any, missKey: string, ...: any): string
	local percent = Format.percent(tonumber(outcome.percent) or 0, PERCENT_DECIMALS)
	local tickets = tonumber(outcome.tickets) or 0
	if tickets > 0 then
		return Locale.get(language, "shop.outcomeTickets", tickets, percent)
	end
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
		local language = ClientState.getLanguage()
		local tickets = tonumber(response.tickets) or 0
		if tickets > 0 then
			SoundController.play("success")
			FeedController.pushRaw(Locale.get(language, "shop.shardDrawWin", tickets), C.ticket)
		else
			SoundController.play("keep")
			FeedController.pushRaw(Locale.get(language, "shop.shardDrawMiss"), C.muted)
		end
	end
	render()
end

-- 상품 카드 하나
local function productCard(
	language: string,
	item: any,
	order: number,
	pity: {
		points: number,
		perMiss: number,
		threshold: number,
		tickets: number,
	}
)
	local isRandom = item.kind == "random"
	local card = Components.panel(scroller, {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.bg,
		LayoutOrder = order,
	})
	Components.padding(card, 12)
	Components.list(card, "vertical", 6)

	local head = Components.frame(card, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	local icon = Components.frame(head, {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Components.glyph(icon, "ticket", C.ticket)
	local title = Components.label(head, {
		text = Locale.get(language, `shop.{tostring(item.key)}`, tonumber(item.ticketAmount) or 0),
		font = Theme.font.display,
		size = Theme.text.label,
		outline = true,
	})
	title.Position = UDim2.fromOffset(44, 0)
	title.Size = UDim2.new(1, -44, 1, 0)

	if isRandom and type(item.outcomes) == "table" then
		-- 사기 전에 모든 결과와 확률 (합계 100%)
		line(card, Locale.get(language, "shop.oddsTitle"), C.muted, 2, true)
		local pityNext = DrawLogic.isPityNext(pity.points, pity.perMiss, pity.threshold)
		for index, outcome in item.outcomes do
			local text = if pityNext
				then outcomeText(language, outcome, "shop.outcomeMissPity", pity.tickets)
				else outcomeText(language, outcome, "shop.outcomeMiss", pity.perMiss)
			line(
				card,
				text,
				if (tonumber(outcome.tickets) or 0) > 0 then C.ticket else C.text,
				2 + index
			)
		end

		local gauge = Components.frame(card, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 50 })
		local gaugeLabel = Components.label(gauge, {
			text = Locale.get(language, "shop.pityShort", pity.points, pity.threshold),
			size = Theme.text.small,
			font = Theme.font.bodyBold,
			color = C.ember,
		})
		gaugeLabel.Size = UDim2.new(0.42, 0, 1, 0)
		local bar = Components.progressBar(gauge, C.ember, 12)
		bar.frame.AnchorPoint = Vector2.new(0, 0.5)
		bar.frame.Position = UDim2.new(0.44, 0, 0.5, 0)
		bar.frame.Size = UDim2.new(0.56, 0, 0, 12)
		bar.set(if pity.threshold > 0 then pity.points / pity.threshold else 0)

		line(
			card,
			Locale.get(
				language,
				"shop.pity",
				pity.points,
				pity.threshold,
				pity.perMiss,
				pity.threshold,
				pity.tickets
			),
			C.muted,
			51,
			false,
			44
		)
	end

	local buy = Components.button(
		card,
		{ text = Locale.get(language, "shop.buy"), style = "primary", order = 99 }
	)
	local key = tostring(item.key)
	buy.Activated:Connect(function()
		SoundController.play("click")
		task.spawn(requestPurchase, key)
	end)
end

render = function()
	if not open then
		return
	end

	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	titleLabel.Text = Locale.get(language, "ui.shopTitle")
	noticeLabel.Text = Locale.get(language, "shop.notice")
	Components.clear(scroller)

	local state = shopState
	if type(state) ~= "table" then
		line(
			scroller,
			Locale.get(language, if loading then "ui.loading" else "ui.shopEmpty"),
			C.muted,
			1,
			false,
			60
		)
		return
	end

	local items = if type(state.items) == "table" then state.items else {}
	local shardDraw = if type(state.shardDraw) == "table" then state.shardDraw else nil

	if #items == 0 and shardDraw == nil then
		-- 빈 상태: 지금은 상품 ID·수치가 미정이라 이게 정상이다
		local empty = Components.panel(
			scroller,
			{ Size = UDim2.new(1, -8, 0, 150), BackgroundColor3 = C.bg, LayoutOrder = 1 }
		)
		local icon = Components.frame(empty, {
			Size = UDim2.fromOffset(56, 56),
			Position = UDim2.new(0.5, 0, 0, 16),
			AnchorPoint = Vector2.new(0.5, 0),
		})
		Components.glyph(icon, "bag", C.gold)
		local soon = Components.label(empty, {
			text = Locale.get(language, "ui.shopEmpty"),
			font = Theme.font.display,
			size = Theme.text.label,
			color = C.gold,
			align = Enum.TextXAlignment.Center,
		})
		soon.Position = UDim2.fromOffset(0, 80)
		local promise = Components.label(empty, {
			text = Locale.get(language, "shop.promise"),
			size = Theme.text.small,
			color = C.muted,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		promise.Position = UDim2.fromOffset(12, 108)
		promise.Size = UDim2.new(1, -24, 0, 36)
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local pity = {
		points = if data then data.pityPoints else 0,
		perMiss = tonumber(state.pityPerMiss) or 1,
		threshold = tonumber(state.pityThreshold) or 0,
		tickets = tonumber(state.pityTickets) or 0,
	}

	if #items > 0 then
		line(scroller, Locale.get(language, "shop.sectionPaid"), C.ember, nextOrder(), true)
	end
	for _, item in items do
		if type(item) == "table" and type(item.key) == "string" then
			productCard(language, item, nextOrder(), pity)
		end
	end

	if shardDraw ~= nil and type(shardDraw.outcomes) == "table" then
		local cost = tonumber(shardDraw.cost) or 0
		local shards = if data then data.shards else 0
		local affordable = shards >= cost and not drawing

		line(scroller, Locale.get(language, "shop.sectionFree"), C.ember, nextOrder(), true)
		local card = Components.panel(scroller, {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.bg,
			LayoutOrder = nextOrder(),
		})
		Components.padding(card, 12)
		Components.list(card, "vertical", 6)

		line(
			card,
			Locale.get(language, "shop.shardOwned", Format.comma(shards)),
			if affordable then C.shard else C.fail,
			1,
			true
		)
		line(card, Locale.get(language, "shop.oddsTitle"), C.muted, 2, true)
		for index, outcome in shardDraw.outcomes do
			line(card, outcomeText(language, outcome, "shop.outcomeMissFree"), C.text, 2 + index)
		end
		local draw = Components.button(
			card,
			{ text = Locale.get(language, "shop.shardDraw", cost), style = "primary", order = 99 }
		)
		Components.setEnabled(draw, affordable)
		draw.Activated:Connect(function()
			if draw.Active then
				SoundController.play("click")
				task.spawn(requestShardDraw)
			end
		end)
	end
end

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
	gui = ScreenManager.createScreen("ForgeShop", 10)
	gui.Enabled = false

	panel = Components.panel(gui, { Name = "Panel" })
	Components.closeButton(panel, function()
		ScreenManager.closeModal()
	end)

	titleLabel = Components.label(
		panel,
		{ font = Theme.font.display, size = Theme.text.title, color = C.gold, outline = true }
	)
	titleLabel.Position = UDim2.fromOffset(16, 12)
	titleLabel.Size = UDim2.new(1, -80, 0, 40)

	local holder = Components.frame(
		panel,
		{ Position = UDim2.fromOffset(16, 58), Size = UDim2.new(1, -32, 1, -58 - 48) }
	)
	scroller = Components.scroller(holder, 10)

	noticeLabel = Components.label(panel, { size = Theme.text.small, color = C.muted, wrap = true })
	noticeLabel.AnchorPoint = Vector2.new(0, 1)
	noticeLabel.Position = UDim2.new(0, 16, 1, -8)
	noticeLabel.Size = UDim2.new(1, -32, 0, 36)
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout then
		ScreenManager.place(panel, layout.modal)
	end
end

function ShopController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	itemsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetShopItems) :: RemoteFunction
	promptRemote = remotesFolder:WaitForChild(Remotes.Functions.PromptPurchase) :: RemoteFunction
	shardRemote = remotesFolder:WaitForChild(Remotes.Functions.ShardDraw) :: RemoteFunction

	ScreenManager.registerModal("shop", function()
		open = true
		gui.Enabled = true
		task.spawn(refresh)
	end, function()
		open = false
		gui.Enabled = false
	end)

	ScreenManager.onLayout(place)
	-- 천장 포인트나 파편이 바뀌면(구매·뽑기 직후) 열려 있는 상점을 바로 다시 그린다.
	ClientState.onChanged(render)
end

function ShopController.Start() end

return ShopController
