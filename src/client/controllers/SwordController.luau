--!strict
--[[
	SwordController — 검 보관함 창 (통합 기획서 5절).

	왼쪽: 가진 검 카드(등급 색 띠, 이름, 레벨 색 숫자, 착용 표시). 누르면 그 검을 착용한다.
	오른쪽: 새 검 뽑기. 가격(모자라면 빨간 글씨), "지금 내 기준" 등급별·검별 확률(합계 100%),
	        두 번 눌러야 골드를 쓰는 버튼. 뽑으면 등급 색으로 새 검이 나타난다.

	확률은 서버가 실제 뽑기에 쓰는 것과 같은 Pure/SwordLogic 함수로 만든다.
	클라이언트는 "착용할 검 id" 와 "뽑기 요청"만 보낸다. 가격·결과는 서버가 정한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local controllers = script.Parent
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local SwordController = {}
SwordController.Name = "SwordController"

local C = Theme.color
local RARITY_OF = Weapons.rarityMap()

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local listTitle: TextLabel
local listScroller: ScrollingFrame
local drawScroller: ScrollingFrame
local buyButton: TextButton
local revealCard: Frame
local revealName: TextLabel
local revealRarity: TextLabel
local revealIcon: Frame

local equipRemote: RemoteFunction
local drawRemote: RemoteFunction

local open = false
local busy = false
local confirming = false -- 뽑기 버튼을 한 번 누른 상태 (두 번째에 실제로 요청)

local refresh: () -> ()

local function showError(reason: string)
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), C.fail)
end

local function displayName(language: string, weaponId: string, sword: any): string
	if sword and sword.customName and sword.customName ~= "" then
		return sword.customName
	end
	local info = Weapons.get(weaponId)
	return if info then Locale.get(language, info.nameKey) else weaponId
end

local function swordCard(
	parent: Instance,
	language: string,
	weaponId: string,
	sword: any,
	equipped: boolean,
	order: number
)
	local info = Weapons.get(weaponId)
	if info == nil then
		return
	end

	local card = Instance.new("TextButton")
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = if equipped then Theme.shade(C.ember, -0.5) else C.sub
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, -8, 0, 64)
	card.LayoutOrder = order
	card.Parent = parent
	Components.corner(card)
	Components.stroke(card, if equipped then C.ember else C.line, if equipped then 2 else 1)

	local strip = Components.frame(card, {
		BackgroundColor3 = Theme.rarityColor(info.rarity),
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 8, 1, -16),
		Position = UDim2.fromOffset(8, 8),
	})
	Components.corner(strip, 4)

	local icon = Components.frame(card, {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 24, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Components.glyph(icon, "sword", Theme.heatColor(sword.level))

	local name = Components.label(card, {
		text = displayName(language, weaponId, sword),
		font = Theme.font.bodyBold,
		size = Theme.text.body,
	})
	name.Position = UDim2.fromOffset(68, 8)
	name.Size = UDim2.new(1, -150, 0, 24)

	local sub = Components.label(card, {
		text = Locale.get(language, `rarity.{info.rarity}`)
			.. (if equipped then "  ·  " .. Locale.get(language, "ui.equipped") else ""),
		size = Theme.text.small,
		color = if equipped then C.ember else C.muted,
	})
	sub.Position = UDim2.fromOffset(68, 34)
	sub.Size = UDim2.new(1, -150, 0, 22)

	local level = Components.label(card, {
		text = Format.level(sword.level),
		font = Theme.font.display,
		size = Theme.text.big,
		color = Theme.heatColor(sword.level),
		outline = true,
		align = Enum.TextXAlignment.Right,
	})
	level.AnchorPoint = Vector2.new(1, 0.5)
	level.Position = UDim2.new(1, -12, 0.5, 0)
	level.Size = UDim2.fromOffset(80, 44)

	if not equipped then
		card.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local ok, response = pcall(function()
				return equipRemote:InvokeServer(weaponId)
			end)
			busy = false
			if not ok or type(response) ~= "table" then
				showError("unknown")
			elseif response.ok ~= true then
				showError(tostring(response.reason))
			else
				ClientState.setOdds(response.odds)
				SoundController.play("click")
			end
		end)
	end
end

-- 확률 한 줄: 이름 · 막대 · %
local function oddsRow(
	parent: Instance,
	text: string,
	percent: number,
	color: Color3,
	order: number,
	strong: boolean
)
	local row = Components.frame(parent, { Size = UDim2.new(1, -8, 0, 26), LayoutOrder = order })
	local name = Components.label(row, {
		text = text,
		size = Theme.text.small,
		color = if strong then C.text else C.muted,
		font = if strong then Theme.font.bodyBold else Theme.font.body,
	})
	name.Size = UDim2.new(0.5, 0, 1, 0)

	local bar = Components.progressBar(row, color, 10)
	bar.frame.AnchorPoint = Vector2.new(0, 0.5)
	bar.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	bar.frame.Size = UDim2.new(0.3, 0, 0, 10)
	bar.set(percent / 100)

	local value = Components.label(row, {
		text = Format.percent(percent, SwordLogic.PERCENT_DECIMALS),
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		color = color,
		align = Enum.TextXAlignment.Right,
	})
	value.Size = UDim2.new(0.2, 0, 1, 0)
	value.Position = UDim2.new(0.8, 0, 0, 0)
end

local function showReveal(weaponId: string)
	local info = Weapons.get(weaponId)
	if info == nil then
		return
	end
	local language = ClientState.getLanguage()
	local color = Theme.rarityColor(info.rarity)

	revealName.Text = Locale.get(language, info.nameKey)
	revealRarity.Text = Locale.get(language, `rarity.{info.rarity}`)
	revealRarity.TextColor3 = color
	Components.clear(revealIcon)
	Components.glyph(revealIcon, "sword", color)
	local stroke = revealCard:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end

	local scale = revealCard:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.3
	revealCard.Visible = true
	TweenService:Create(scale, Theme.motion.pop, { Scale = 1 }):Play()

	task.delay(2.4, function()
		revealCard.Visible = false
	end)
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
	elseif response.ok ~= true then
		showError(tostring(response.reason))
	else
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
				Theme.rarityColor(info.rarity)
			)
		end
		ClientState.setOdds(response.odds)
		SoundController.play("success")
		showReveal(tostring(response.swordId))
	end

	refresh()
end

function refresh()
	if not open then
		return
	end

	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	titleLabel.Text = Locale.get(language, "ui.swordsTitle")
	listTitle.Text = Locale.get(language, "ui.swordListTitle")

	Components.clear(listScroller)
	Components.clear(drawScroller)

	if data == nil then
		Components.label(
			listScroller,
			{ text = Locale.get(language, "error.not_ready"), color = C.muted }
		)
		return
	end

	-- 가진 검
	local swordCount = 0
	for index, weaponId in Weapons.Order do
		local sword = data.swords[weaponId]
		if sword ~= nil then
			swordCount += 1
			swordCard(listScroller, language, weaponId, sword, data.equippedId == weaponId, index)
		end
	end

	-- 새 검 뽑기
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Components.label(drawScroller, {
		text = Locale.get(language, "ui.drawTitle"),
		font = Theme.font.display,
		size = Theme.text.label,
		color = C.gold,
		order = nextOrder(),
	})
	Components.label(drawScroller, {
		text = Locale.get(language, "ui.drawDesc"),
		size = Theme.text.small,
		color = C.muted,
		wrap = true,
		order = nextOrder(),
		height = 70,
	}).Size =
		UDim2.new(1, -8, 0, 70)

	local drawTable =
		SwordLogic.buildDrawTable(Weapons.Order, RARITY_OF, Weapons.DRAW_WEIGHTS, data.swords)
	if #drawTable.entries == 0 then
		Components.label(
			drawScroller,
			{ text = Locale.get(language, "ui.drawNone"), color = C.muted, order = nextOrder() }
		)
		buyButton.Visible = false
		return
	end
	buyButton.Visible = true

	local price = SwordLogic.slotPrice(
		EnhanceLogic.cost(
			Weapons.SLOT_PRICE_LEVEL,
			math.max(1, swordCount),
			EnhanceTable.COST_BASE,
			EnhanceTable.SWORD_COUNT_EXPONENT
		),
		Weapons.SLOT_PRICE_MULTIPLIER
	)
	local affordable = data.gold >= price

	Components.label(drawScroller, {
		text = Locale.get(language, "ui.drawPrice", Format.comma(price)),
		font = Theme.font.bodyBold,
		color = if affordable then C.gold else C.fail,
		order = nextOrder(),
	})

	-- 확률: 등급별 합계, 그다음 검별. 전부 합치면 100%.
	Components.label(drawScroller, {
		text = Locale.get(language, "ui.drawOddsTitle"),
		size = Theme.text.small,
		color = C.text,
		font = Theme.font.bodyBold,
		order = nextOrder(),
	})
	for _, share in drawTable.rarities do
		oddsRow(
			drawScroller,
			Locale.get(language, `rarity.{share.rarity}`),
			share.percent,
			Theme.rarityColor(share.rarity),
			nextOrder(),
			true
		)
	end
	for _, entry in drawTable.entries do
		local info = Weapons.get(entry.id)
		oddsRow(
			drawScroller,
			"· " .. (if info then Locale.get(language, info.nameKey) else entry.id),
			entry.percent,
			Theme.rarityColor(entry.rarity),
			nextOrder(),
			false
		)
	end

	buyButton.Text = if confirming
		then Locale.get(language, "ui.drawConfirm", Format.comma(price))
		else Locale.get(language, "ui.drawBuy")
	Components.setStyle(buyButton, if confirming then "danger" else "primary")
	Components.setEnabled(buyButton, affordable and not busy)
end

local function build()
	gui = ScreenManager.createScreen("ForgeSwords", 10)
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

	-- 왼쪽: 가진 검
	local left = Components.frame(
		panel,
		{ Position = UDim2.fromOffset(16, 58), Size = UDim2.new(0.46, -20, 1, -70) }
	)
	listTitle = Components.label(
		left,
		{ size = Theme.text.small, color = C.muted, font = Theme.font.bodyBold }
	)
	local listHolder = Components.frame(
		left,
		{ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26) }
	)
	listScroller = Components.scroller(listHolder, 6)

	-- 오른쪽: 뽑기
	local right = Components.panel(panel, {
		Position = UDim2.new(0.46, 4, 0, 58),
		Size = UDim2.new(0.54, -20, 1, -70),
		BackgroundColor3 = C.bg,
	})
	local drawHolder = Components.frame(right, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -(Theme.touchHeight + 30)),
	})
	drawScroller = Components.scroller(drawHolder, 4)

	buyButton = Components.button(right, { style = "primary", size = Theme.text.label })
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -10)
	buyButton.Size = UDim2.new(1, -24, 0, Theme.touchHeight)
	buyButton.Activated:Connect(function()
		if busy or not buyButton.Active then
			return
		end
		if confirming then
			task.spawn(requestDraw)
		else
			SoundController.play("click")
			confirming = true
			refresh()
		end
	end)

	-- 새 검 공개 카드
	revealCard = Components.panel(panel, {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 220),
		Visible = false,
		ZIndex = 20,
		BackgroundColor3 = C.bg,
	})
	local revealScale = Instance.new("UIScale")
	revealScale.Parent = revealCard
	local revealTitle = Components.label(revealCard, {
		text = "",
		font = Theme.font.display,
		size = Theme.text.label,
		color = C.gold,
		align = Enum.TextXAlignment.Center,
		outline = true,
	})
	revealTitle.Name = "RevealTitle"
	revealTitle.Position = UDim2.fromOffset(0, 12)
	revealIcon = Components.frame(revealCard, {
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.new(0.5, 0, 0, 44),
		AnchorPoint = Vector2.new(0.5, 0),
	})
	revealName = Components.label(revealCard, {
		font = Theme.font.display,
		size = Theme.text.title,
		align = Enum.TextXAlignment.Center,
		outline = true,
	})
	revealName.Position = UDim2.fromOffset(0, 140)
	revealRarity = Components.label(
		revealCard,
		{ font = Theme.font.bodyBold, size = Theme.text.body, align = Enum.TextXAlignment.Center }
	)
	revealRarity.Position = UDim2.fromOffset(0, 178)
	for _, child in revealCard:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 21
		end
	end
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout then
		ScreenManager.place(panel, layout.modal)
	end
end

function SwordController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	equipRemote = remotesFolder:WaitForChild(Remotes.Functions.EquipSword) :: RemoteFunction
	drawRemote = remotesFolder:WaitForChild(Remotes.Functions.BuySwordSlot) :: RemoteFunction

	ScreenManager.registerModal("swords", function()
		open = true
		confirming = false
		gui.Enabled = true
		local title = revealCard:FindFirstChild("RevealTitle")
		if title and title:IsA("TextLabel") then
			title.Text = Locale.get(ClientState.getLanguage(), "ui.drawNew")
		end
		refresh()
	end, function()
		open = false
		confirming = false
		revealCard.Visible = false
		gui.Enabled = false
	end)

	ScreenManager.onLayout(place)
end

function SwordController.Start()
	-- 착용·뽑기·강화로 데이터가 바뀌면 열려 있는 창을 다시 그린다.
	ClientState.onChanged(refresh)
end

return SwordController
