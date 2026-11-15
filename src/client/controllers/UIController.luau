--!strict
--[[
	UIController — 대장간 화면 (강화의 중심, 통합 기획서 8·8-1절).

	왼쪽 무대: 검 이름(누르면 이름 짓기) · 검 미리보기 자리 · 큰 레벨 숫자(쇠 달구는 색) · 피드 칸(FeedController)
	오른쪽 조작부: 구간 안내 · 이벤트 · 확률 글자와 막대 · 방지권 토글 + "확률표" 버튼 ·
	              비용과 지금 몇 번 가능한지 · 아래 줄 [검][기록][상점] + 큰 강화 버튼

	규칙:
	- 숫자는 서버가 보낸 값이거나 서버와 같은 Pure/ 함수로 계산한 값이다.
	- 확률(성공/유지/실패 %)과 비용은 항상 보인다. 방지권이 효과를 내면 바뀐 확률(실패 0)을 바로 보여 준다.
	- 요청 중에는 버튼을 잠근다. 연출은 서버 응답을 받은 뒤에만 시작하고, 결과 숫자는 연출이 공개할 때 바뀐다.
	- 표시 문자열은 전부 Locale 키를 거친다.

	이 컨트롤러는 접속 직후 상태 받기(GetState)와 데이터 복제·라이브 운영 이벤트 수신도 맡는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))
local ForgeLayout = require(ui:WaitForChild("ForgeLayout"))

local controllers = script.Parent
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))
local EffectsController = require(controllers:WaitForChild("EffectsController"))
local HudController = require(controllers:WaitForChild("HudController"))

local UIController = {}
UIController.Name = "UIController"

local C = Theme.color
local GAP = 6
local ROW = {
	title = 40,
	info = 24,
	odds = 26,
	bar = 22,
	protect = 60,
	cost = 26,
}

local gui: ScreenGui
local panel: Frame
local leftColumn: Frame
local rightColumn: Frame

local nameButton: TextButton
local rarityTag: TextLabel
local stage: Frame
local previewSlot: Frame
local levelLabel: TextLabel
local tierLabel: TextLabel

local titleLabel: TextLabel
local infoLabel: TextLabel
local eventLabel: TextLabel
local oddsLabel: TextLabel
local oddsBar: Components.OddsBar
local protectButton: TextButton
local tableButton: TextButton
local costLabel: TextLabel
local bottomRow: Frame
local swordsTile: TextButton
local recordsTile: TextButton
local shopTile: TextButton
local enhanceButton: TextButton
local tutorialBubble: Frame
local tutorialText: TextLabel
local skipCatcher: TextButton

local renamePanel: Frame
local renameTitle: TextLabel
local renameBox: TextBox
local renameConfirm: TextButton
local renameCancel: TextButton

local enhanceRemote: RemoteFunction
local renameRemote: RemoteFunction

local busy = false
-- 연출 중에는 결과가 공개되기 전 레벨을 계속 보여 준다 (복제된 데이터가 먼저 도착해도)
local revealLevel: number? = nil
local errorText: string? = nil
local errorToken = 0

--------------------------------------------------------------------------------
-- 만들기
--------------------------------------------------------------------------------

local function build()
	gui = ScreenManager.createScreen("ForgeMain", 5)

	panel = Components.panel(gui, { Name = "ForgePanel" })
	Components.closeButton(panel, function()
		SoundController.play("click")
		ScreenManager.setForgeOpen(false)
	end)

	-- 왼쪽 무대
	leftColumn = Components.frame(panel, { Name = "Left" })

	nameButton = Instance.new("TextButton")
	nameButton.Name = "WeaponName"
	nameButton.BackgroundTransparency = 1
	nameButton.AutoButtonColor = false
	nameButton.Font = Theme.font.display
	nameButton.TextSize = Theme.text.title
	nameButton.TextColor3 = C.text
	nameButton.TextXAlignment = Enum.TextXAlignment.Left
	nameButton.TextTruncate = Enum.TextTruncate.AtEnd
	nameButton.Size = UDim2.new(1, -96, 0, ForgeLayout.NAME_ROW)
	nameButton.Parent = leftColumn
	Components.stroke(nameButton, C.outline, Theme.strokeText, true)

	rarityTag = Components.label(leftColumn, {
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
		height = 26,
	})
	rarityTag.AnchorPoint = Vector2.new(1, 0)
	rarityTag.Position = UDim2.new(1, 0, 0, 7)
	rarityTag.Size = UDim2.fromOffset(88, 26)
	rarityTag.BackgroundTransparency = 0
	Components.corner(rarityTag, 13)

	stage = Components.frame(panel, {
		Name = "Stage",
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.35,
	})
	Components.corner(stage, 12)

	-- 3D 검 미리보기가 들어갈 자리 (월드 쪽 SwordPreview 가 채운다)
	previewSlot = Components.frame(stage, { Name = "PreviewSlot" })

	tierLabel = Components.label(stage, {
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
		color = C.muted,
	})
	tierLabel.AnchorPoint = Vector2.new(0.5, 1)

	levelLabel = Components.label(stage, {
		font = Theme.font.display,
		size = Theme.text.huge,
		align = Enum.TextXAlignment.Center,
		outline = true,
	})
	levelLabel.Name = "Level"
	levelLabel.AnchorPoint = Vector2.new(0.5, 1)
	levelLabel.TextTruncate = Enum.TextTruncate.None
	local levelStroke = levelLabel:FindFirstChildOfClass("UIStroke")
	if levelStroke then
		levelStroke.Thickness = 4
	end

	-- 오른쪽 조작부
	rightColumn = Components.frame(panel, { Name = "Right" })

	titleLabel = Components.label(rightColumn, {
		font = Theme.font.display,
		size = Theme.text.title,
		color = C.gold,
		outline = true,
	})
	infoLabel = Components.label(rightColumn, { size = Theme.text.small, color = C.muted })
	eventLabel = Components.label(rightColumn, {
		size = Theme.text.small,
		color = C.event,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Right,
	})
	oddsLabel =
		Components.label(rightColumn, { size = Theme.text.label, font = Theme.font.bodyBold })
	oddsBar = Components.oddsBar(rightColumn, ROW.bar)

	protectButton = Components.button(rightColumn, { style = "secondary", size = Theme.text.body })
	tableButton = Components.button(rightColumn, { style = "secondary", size = Theme.text.body })
	local tableIcon = Components.frame(tableButton, {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Components.glyph(tableIcon, "table", C.gold)

	costLabel =
		Components.label(rightColumn, { size = Theme.text.body, font = Theme.font.bodyBold })

	bottomRow = Components.frame(rightColumn, { Name = "Bottom" })
	swordsTile = Components.tile(bottomRow, "sword", "", 60)
	recordsTile = Components.tile(bottomRow, "book", "", 60)
	shopTile = Components.tile(bottomRow, "bag", "", 60)
	enhanceButton = Components.button(bottomRow, { style = "primary", size = Theme.text.big })

	-- 첫 강화 안내 말풍선 (강화 버튼 위)
	tutorialBubble = Components.frame(panel, {
		Name = "Tutorial",
		BackgroundColor3 = C.gold,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 8,
	})
	Components.corner(tutorialBubble, 10)
	tutorialText = Components.label(tutorialBubble, {
		size = Theme.text.small,
		color = C.ink,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	tutorialText.Size = UDim2.new(1, -12, 1, 0)
	tutorialText.Position = UDim2.fromOffset(6, 0)
	tutorialText.ZIndex = 9
	local tail = Components.frame(tutorialBubble, {
		BackgroundColor3 = C.gold,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		ZIndex = 8,
	})
	tail.Name = "Tail"

	-- 망치질 연출 중 아무 데나 누르면 건너뛴다
	skipCatcher = Instance.new("TextButton")
	skipCatcher.Name = "SkipCatcher"
	skipCatcher.Text = ""
	skipCatcher.BackgroundTransparency = 1
	skipCatcher.AutoButtonColor = false
	skipCatcher.Size = UDim2.fromScale(1, 1)
	skipCatcher.ZIndex = 30
	skipCatcher.Visible = false
	skipCatcher.Parent = panel
	skipCatcher.Activated:Connect(function()
		EffectsController.skip()
	end)

	-- 이름 짓기 창
	renamePanel = Components.panel(gui, { Name = "Rename", Visible = false, ZIndex = 40 })
	renamePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	Components.padding(renamePanel, 16)
	Components.list(renamePanel, "vertical", 10)

	renameTitle =
		Components.label(renamePanel, { size = Theme.text.body, color = C.muted, order = 1 })

	renameBox = Instance.new("TextBox")
	renameBox.BackgroundColor3 = C.sub
	renameBox.BorderSizePixel = 0
	renameBox.Font = Theme.font.bodyBold
	renameBox.TextSize = Theme.text.label
	renameBox.TextColor3 = C.text
	renameBox.PlaceholderColor3 = C.muted
	renameBox.ClearTextOnFocus = false
	renameBox.Text = ""
	renameBox.Size = UDim2.new(1, 0, 0, Theme.touchHeight)
	renameBox.LayoutOrder = 2
	renameBox.Parent = renamePanel
	Components.corner(renameBox)

	local renameRow = Components.frame(
		renamePanel,
		{ Size = UDim2.new(1, 0, 0, Theme.touchHeight), LayoutOrder = 3 }
	)
	Components.list(renameRow, "horizontal", 8)
	renameCancel =
		Components.button(renameRow, { style = "secondary", width = UDim.new(0.5, -4), order = 1 })
	renameConfirm =
		Components.button(renameRow, { style = "primary", width = UDim.new(0.5, -4), order = 2 })
end

--------------------------------------------------------------------------------
-- 배치
--------------------------------------------------------------------------------

local function place()
	local layout = ScreenManager.getLayout()
	if layout == nil then
		return
	end

	local rect = layout.forgePanel
	ScreenManager.place(panel, rect)
	local inner = ForgeLayout.compute(rect)

	local function put(object: GuiObject, x: number, y: number, w: number, h: number)
		object.Position = UDim2.fromOffset(x, y)
		object.Size = UDim2.fromOffset(w, h)
	end

	put(leftColumn, inner.left.x, inner.left.y, inner.left.w, ForgeLayout.NAME_ROW)
	put(stage, inner.stage.x, inner.stage.y, inner.stage.w, inner.stage.h)

	local stageH = inner.stage.h
	levelLabel.Size = UDim2.new(1, 0, 0, math.min(110, stageH * 0.55))
	levelLabel.Position = UDim2.new(0.5, 0, 1, -24)
	tierLabel.Size = UDim2.new(1, 0, 0, 22)
	tierLabel.Position = UDim2.new(0.5, 0, 1, -4)
	previewSlot.Size = UDim2.new(1, 0, 1, 0)

	-- 오른쪽 줄 높이 계산: 고정 줄을 위에서부터 쌓고 남는 높이를 아래 줄(강화 버튼)에
	local right = inner.right
	put(rightColumn, right.x, right.y, right.w, right.h)

	local fixed = ROW.title + ROW.info + ROW.odds + ROW.bar + ROW.protect + ROW.cost + GAP * 6
	local bottomH = math.clamp(right.h - fixed, 64, 96)

	local y = 0
	titleLabel.Position = UDim2.fromOffset(0, y)
	titleLabel.Size = UDim2.new(1, -56, 0, ROW.title) -- 오른쪽 위 X 자리 비움
	y += ROW.title + GAP

	infoLabel.Position = UDim2.fromOffset(0, y)
	infoLabel.Size = UDim2.new(0.55, 0, 0, ROW.info)
	eventLabel.Position = UDim2.new(0.55, 0, 0, y)
	eventLabel.Size = UDim2.new(0.45, 0, 0, ROW.info)
	y += ROW.info + GAP

	oddsLabel.Position = UDim2.fromOffset(0, y)
	oddsLabel.Size = UDim2.new(1, 0, 0, ROW.odds)
	y += ROW.odds + GAP

	oddsBar.frame.Position = UDim2.fromOffset(0, y)
	oddsBar.frame.Size = UDim2.new(1, 0, 0, ROW.bar)
	y += ROW.bar + GAP

	local tableWidth = math.min(150, math.floor(right.w * 0.36))
	protectButton.Position = UDim2.fromOffset(0, y)
	protectButton.Size = UDim2.new(1, -(tableWidth + 8), 0, ROW.protect)
	tableButton.Position = UDim2.new(1, -tableWidth, 0, y)
	tableButton.Size = UDim2.fromOffset(tableWidth, ROW.protect)
	y += ROW.protect + GAP

	costLabel.Position = UDim2.fromOffset(0, y)
	costLabel.Size = UDim2.new(1, 0, 0, ROW.cost)

	-- 아래 줄: 오른쪽 맨 아래에 붙인다
	bottomRow.Position = UDim2.new(0, 0, 1, -bottomH)
	bottomRow.Size = UDim2.new(1, 0, 0, bottomH)
	local tileSize = math.min(bottomH, 72)
	for index, tile in { swordsTile, recordsTile, shopTile } do
		tile.Size = UDim2.fromOffset(tileSize, tileSize)
		tile.Position = UDim2.new(0, (index - 1) * (tileSize + 6), 1, -tileSize)
	end
	local enhanceLeft = 3 * (tileSize + 6)
	enhanceButton.Position = UDim2.fromOffset(enhanceLeft, 0)
	enhanceButton.Size = UDim2.new(1, -enhanceLeft, 1, 0)

	-- 안내 말풍선: 강화 버튼 바로 위
	local bubbleW = math.min(280, right.w - enhanceLeft)
	tutorialBubble.Size = UDim2.fromOffset(bubbleW, 44)
	tutorialBubble.Position = UDim2.fromOffset(
		right.x + enhanceLeft + (right.w - enhanceLeft - bubbleW) / 2,
		right.y + right.h - bottomH - 44 - 10
	)

	renamePanel.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y + rect.h / 2)
	renamePanel.Size =
		UDim2.fromOffset(math.min(440, rect.w - 40), 16 * 2 + 28 + 10 + Theme.touchHeight * 2 + 10)
end

--------------------------------------------------------------------------------
-- 그리기
--------------------------------------------------------------------------------

local function weaponDisplayName(language: string, sword: any): string
	if sword == nil then
		return ""
	end
	if sword.customName and sword.customName ~= "" then
		return sword.customName
	end
	local info = Weapons.get(sword.id)
	return if info then Locale.get(language, info.nameKey) else sword.id
end

local function render()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()
	local mode = ScreenManager.getMode()

	gui.Enabled = mode == "forge"

	titleLabel.Text = Locale.get(language, "ui.forgeTitle")
	tableButton.Text = "      " .. Locale.get(language, "ui.oddsTable")
	Components.setTileText(swordsTile, Locale.get(language, "ui.swords"))
	Components.setTileText(recordsTile, Locale.get(language, "ui.records"))
	Components.setTileText(shopTile, Locale.get(language, "ui.shop"))
	renameTitle.Text = Locale.get(language, "ui.renamePrompt")
	renameConfirm.Text = Locale.get(language, "ui.rename")
	renameCancel.Text = Locale.get(language, "ui.cancel")
	FeedController.setBannerCheck(HudController.isBannerVisible)

	if data == nil then
		enhanceButton.Text = Locale.get(language, "ui.loading")
		Components.setEnabled(enhanceButton, false)
		return
	end

	local sword = ClientState.getEquipped()
	local level = revealLevel or (if sword then sword.level else 0)
	local info = if sword then Weapons.get(sword.id) else nil

	nameButton.Text = weaponDisplayName(language, sword)
	if info then
		rarityTag.Text = Locale.get(language, `rarity.{info.rarity}`)
		rarityTag.BackgroundColor3 = Theme.rarityColor(info.rarity)
		rarityTag.TextColor3 = C.ink
		rarityTag.Visible = true
	else
		rarityTag.Visible = false
	end

	levelLabel.Text = Format.level(level)
	levelLabel.TextColor3 = Theme.heatColor(level)
	tierLabel.Text = Locale.get(language, Theme.heatTier(level).nameKey)
	tierLabel.TextColor3 = Theme.heatColor(level)

	-- 첫 강화 3번 안내
	local tries = data.stats.enhanceTries
	if tries < 3 then
		tutorialBubble.Visible = true
		tutorialText.Text = Locale.get(language, `tutorial.step{tries + 1}`)
	else
		tutorialBubble.Visible = false
	end

	-- 확률 (연출 중이면 공개 전 확률을 계속 보여 준다: setOdds 를 공개 때 부른다)
	local odds = ClientState.getOdds()
	local useProtect = ClientState.getUseProtect()
	local inSecondZone = level >= EnhanceTable.SAFE_LEVEL

	protectButton.Text = Locale.get(
		language,
		if inSecondZone then "ui.protectToggle" else "ui.protectIdle",
		Locale.get(language, if useProtect then "ui.on" else "ui.off"),
		data.protectTickets
	)
	Components.setStyle(protectButton, if useProtect then "primary" else "secondary")

	if odds == nil then
		oddsLabel.Text = ""
		costLabel.Text = ""
		eventLabel.Visible = false
		return
	end

	eventLabel.Visible = odds.eventName ~= nil
	if odds.eventName ~= nil then
		eventLabel.Text =
			Locale.get(language, "ui.eventActive", Locale.get(language, odds.eventName))
	end

	if odds.cost <= 0 then
		infoLabel.Text = Locale.get(language, "ui.zoneMax")
		oddsLabel.Text = Locale.get(language, "ui.maxLevel")
		oddsBar.set(1, 0, 0)
		costLabel.Text = ""
		enhanceButton.Text = Locale.get(language, "ui.maxShort")
		Components.setEnabled(enhanceButton, false)
		return
	end

	infoLabel.Text = Locale.get(language, if inSecondZone then "ui.zone2" else "ui.zone1")

	-- 방지권이 효과를 내는 동안에는 바뀐 확률(실패 0, 그만큼 유지)을 보여 준다.
	local shown: EnhanceLogic.Odds = odds
	if ClientState.isProtectActive() then
		shown = EnhanceLogic.applyProtect(odds)
	end

	oddsLabel.Text = Locale.get(
		language,
		"ui.odds",
		Format.percent(shown.success),
		Format.percent(shown.keep),
		Format.percent(shown.fail)
	)
	oddsBar.set(shown.success, shown.keep, shown.fail)

	local times = math.floor(data.gold / odds.cost)
	if errorText then
		costLabel.Text = errorText
		costLabel.TextColor3 = C.fail
	elseif times <= 0 then
		costLabel.Text = Locale.get(language, "ui.costShort", Format.comma(odds.cost))
		costLabel.TextColor3 = C.fail
	else
		costLabel.Text =
			Locale.get(language, "ui.costTimes", Format.comma(odds.cost), Format.comma(times))
		costLabel.TextColor3 = C.text
	end

	if busy then
		enhanceButton.Text = Locale.get(language, "ui.enhancing")
		Components.setEnabled(enhanceButton, false)
	else
		enhanceButton.Text = Locale.get(language, "ui.enhance")
		Components.setEnabled(enhanceButton, times > 0)
	end
end

local function showError(reason: string)
	errorText = Locale.get(ClientState.getLanguage(), `error.{reason}`)
	errorToken += 1
	local token = errorToken
	render()
	task.delay(3, function()
		if token == errorToken then
			errorText = nil
			render()
		end
	end)
end

--------------------------------------------------------------------------------
-- 요청
--------------------------------------------------------------------------------

local function requestEnhance()
	if busy then
		return
	end

	local odds = ClientState.getOdds()
	local sword = ClientState.getEquipped()
	if odds == nil or sword == nil or odds.cost <= 0 then
		return
	end

	local startLevel = sword.level
	busy = true
	revealLevel = startLevel
	errorText = nil
	render()

	local ok, response = pcall(function()
		return enhanceRemote:InvokeServer(ClientState.getUseProtect())
	end)

	if not ok or type(response) ~= "table" or response.ok ~= true then
		busy = false
		revealLevel = nil
		showError(if ok and type(response) == "table" then tostring(response.reason) else "unknown")
		return
	end

	-- 서버 응답을 받은 뒤에만 연출을 시작한다. 결과는 연출이 "공개"할 때 화면에 반영한다.
	local outcome = tostring(response.result)
	local newLevel = tonumber(response.newLevel) or startLevel
	local isMax = outcome == "success" and newLevel >= EnhanceTable.MAX_LEVEL
	local pendingOdds = response.odds

	skipCatcher.Visible = true
	EffectsController.playReveal(startLevel, outcome, newLevel, isMax, function()
		revealLevel = nil
		if type(pendingOdds) == "table" then
			ClientState.setOdds(pendingOdds)
		end
		FeedController.pushOutcome(outcome)
		if isMax then
			FeedController.pushOutcome("max")
		end
		render()
	end, function()
		skipCatcher.Visible = false
		busy = false
		render()
	end)
end

local function requestRename()
	local text = renameBox.Text
	renamePanel.Visible = false

	if text == "" then
		return
	end

	local ok, response = pcall(function()
		return renameRemote:InvokeServer(text)
	end)

	if not ok or type(response) ~= "table" then
		showError("unknown")
		return
	end
	if response.ok ~= true then
		showError(tostring(response.reason))
		return
	end

	-- 서버가 돌려준 "필터링을 통과한" 이름만 화면에 쓴다.
	FeedController.pushRaw(
		Locale.get(ClientState.getLanguage(), "ui.renamed", response.name),
		C.ember
	)
	render()
end

--------------------------------------------------------------------------------

function UIController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	enhanceRemote = remotesFolder:WaitForChild(Remotes.Functions.Enhance) :: RemoteFunction
	renameRemote = remotesFolder:WaitForChild(Remotes.Functions.RenameWeapon) :: RemoteFunction

	local dataChanged = remotesFolder:WaitForChild(Remotes.Events.DataChanged) :: RemoteEvent
	dataChanged.OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			ClientState.setData(data)
		end
	end)

	local liveOpsRemote = remotesFolder:WaitForChild(Remotes.Events.LiveOpsChanged) :: RemoteEvent
	liveOpsRemote.OnClientEvent:Connect(function(config: any)
		if type(config) == "table" then
			ClientState.setLiveOps(config)
		end
	end)

	ScreenManager.onLayout(place)
	ScreenManager.onStateChanged(render)
	ClientState.onChanged(render)

	enhanceButton.Activated:Connect(function()
		if enhanceButton.Active then
			task.spawn(requestEnhance)
		end
	end)

	protectButton.Activated:Connect(function()
		SoundController.play("click")
		ClientState.setUseProtect(not ClientState.getUseProtect())
	end)

	tableButton.Activated:Connect(function()
		SoundController.play("click")
		ScreenManager.openModal("odds")
	end)
	swordsTile.Activated:Connect(function()
		SoundController.play("click")
		ScreenManager.openModal("swords")
	end)
	recordsTile.Activated:Connect(function()
		SoundController.play("click")
		ScreenManager.openModal("records")
	end)
	shopTile.Activated:Connect(function()
		SoundController.play("click")
		ScreenManager.openModal("shop")
	end)

	nameButton.Activated:Connect(function()
		local sword = ClientState.getEquipped()
		renameBox.Text = if sword and sword.customName then sword.customName else ""
		renamePanel.Visible = true
	end)
	renameConfirm.Activated:Connect(function()
		task.spawn(requestRename)
	end)
	renameCancel.Activated:Connect(function()
		renamePanel.Visible = false
	end)

	EffectsController.bind(stage, levelLabel)
	render()
end

-- 3D 검 미리보기를 넣을 자리 (월드 쪽 컨트롤러가 쓴다)
function UIController.getPreviewSlot(): Frame
	return previewSlot
end

function UIController.Start()
	-- 접속 직후 현재 상태를 한 번 받아 온다 (프로필 로드가 아직 끝나지 않았을 수 있어 잠시 재시도).
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
		local stateRemote = remotesFolder:WaitForChild(Remotes.Functions.GetState) :: RemoteFunction

		for _ = 1, 30 do
			local ok, response = pcall(function()
				return stateRemote:InvokeServer()
			end)

			if ok and type(response) == "table" and response.ok == true then
				if type(response.liveOps) == "table" then
					ClientState.setLiveOps(response.liveOps)
				end
				ClientState.setData(response.data)
				ClientState.setOdds(response.odds)
				return
			end

			task.wait(1)
		end

		warn("[UIController] 상태를 받아 오지 못했습니다")
	end)
end

return UIController
