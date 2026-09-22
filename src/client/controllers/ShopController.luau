--!strict
--[[
	ShopController — 상점 화면.

	클라이언트는 상품 ID 를 알지 못한다. "이 항목을 사고 싶다"는 키만 서버에 보내고,
	실제 구매창은 서버가 띄운다. 지급도 전부 서버가 한다.

	상품이 아직 등록되지 않았으면(ID 가 0) 서버가 목록에서 빼기 때문에
	여기서는 빈 목록 안내만 띄운다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))

local ShopController = {}
ShopController.Name = "ShopController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)

local TOUCH_MIN = 44

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local noticeLabel: TextLabel
local scroller: ScrollingFrame
local closeButton: TextButton

local itemsRemote: RemoteFunction
local promptRemote: RemoteFunction

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

-- 상품 한 줄에 쓸 이름. 지급량이 있는 상품은 수량을 함께 보여 준다.
local function itemLabel(language: string, item: any): string
	if item.goldAmount > 0 then
		return Locale.get(language, `shop.{item.key}`, Format.comma(item.goldAmount))
	end
	if item.ticketAmount > 0 then
		return Locale.get(language, `shop.{item.key}`, item.ticketAmount)
	end
	return Locale.get(language, `shop.{item.key}`)
end

local function refresh()
	local language = ClientState.getLanguage()

	titleLabel.Text = Locale.get(language, "ui.shopTitle")
	noticeLabel.Text = Locale.get(language, "shop.notice")
	closeButton.Text = Locale.get(language, "ui.close")

	for _, child in scroller:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local ok, items = pcall(function()
		return itemsRemote:InvokeServer()
	end)

	if not ok or type(items) ~= "table" or #items == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 15
		empty.TextColor3 = COLOR_MUTED
		empty.TextWrapped = true
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Text = Locale.get(language, "ui.shopEmpty")
		empty.Parent = scroller
		return
	end

	for index, item in items do
		local text = itemLabel(language, item)
		if item.owned then
			text ..= `  ({Locale.get(language, "ui.owned")})`
		end

		local row = makeButton(scroller, {
			Text = text,
			LayoutOrder = index,
			TextColor3 = if item.owned then COLOR_MUTED else COLOR_TEXT,
		})

		if not item.owned then
			row.Activated:Connect(function()
				task.spawn(function()
					local success, response = pcall(function()
						return promptRemote:InvokeServer(item.kind, item.key)
					end)

					if success and type(response) == "table" and response.ok ~= true then
						FeedController.pushRaw(
							Locale.get(language, `error.{tostring(response.reason)}`),
							COLOR_ACCENT
						)
					end
				end)
			end)
		end
	end
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
	panel.Size = UDim2.new(0.9, 0, 0.72, 0)
	panel.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(460, 560)
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
end

function ShopController.Start() end

return ShopController
