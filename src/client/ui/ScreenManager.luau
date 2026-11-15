--!strict
--[[
	ScreenManager — 화면 상태와 배치를 한 곳에서 정한다 (통합 기획서 8-1절).

	화면 상태 (mode)
	  lobby   로비를 돌아다닌다. 가장자리 HUD 만. 이동 컨트롤 보임
	  forge   대장간 화면이 열려 있다. 이동 컨트롤 숨김
	  race    경주 중(출발선 ~ 탈락 전). 경주 HUD 만. 이동 컨트롤 보임
	  raceOut 탈락 후 관전·결과. 이동 컨트롤 숨김
	큰 창(확률표·검·기록·상점)은 상태와 따로 "modal" 로 하나만 열린다. 열려 있으면 이동 컨트롤을 숨긴다.

	배치: 모든 ScreenGui 는 ScreenInsets = CoreUISafeInsets 를 쓴다(로블록스 위쪽 버튼·노치를 피함).
	그 영역 크기로 Pure/UILayout 을 계산하고, 등록된 ScreenGui 마다 UIScale = 배율을 건다.
	컨트롤러는 onLayout 으로 구역 사각형을 받아 자기 화면을 그 자리에 놓는다.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VisualConfig = require(Shared:WaitForChild("Config"):WaitForChild("VisualConfig"))
local UILayout = require(Shared:WaitForChild("Pure"):WaitForChild("UILayout"))

local ScreenManager = {}

export type Mode = "lobby" | "forge" | "race" | "raceOut"

type ModalSpec = {
	onOpen: () -> (),
	onClose: () -> (),
}

local mode: Mode = "forge" -- 처음 접속하면 대장간이 열린 채 시작한다 (첫 강화 안내)
local modal: string? = nil
local modals: { [string]: ModalSpec } = {}
local layout: UILayout.Layout? = nil

local scales: { UIScale } = {}
local layoutListeners: { (UILayout.Layout) -> () } = {}
local stateListeners: { () -> () } = {}

local probe: ScreenGui? = nil
local dimGui: ScreenGui? = nil

local function playerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

local function safeCall(callback: (...any) -> (), ...: any)
	local ok, err = pcall(callback, ...)
	if not ok then
		warn(`[ScreenManager] 리스너 오류: {err}`)
	end
end

local function applyTouchControls()
	local hideControls = modal ~= nil or mode == "forge" or mode == "raceOut"
	local ok, err = pcall(function()
		GuiService.TouchControlsEnabled = not hideControls
	end)
	if not ok then
		warn(`[ScreenManager] 이동 컨트롤 표시를 바꾸지 못했습니다: {err}`)
	end
end

local function notifyState()
	applyTouchControls()

	local dim = dimGui
	if dim then
		dim.Enabled = modal ~= nil
	end

	for _, listener in stateListeners do
		safeCall(listener)
	end
end

local function recompute()
	local gui = probe
	if gui == nil then
		return
	end

	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local computed =
		UILayout.compute(size.X, size.Y, UserInputService.TouchEnabled, VisualConfig.Layout)
	layout = computed

	for _, scale in scales do
		scale.Scale = computed.scale
	end
	for _, listener in layoutListeners do
		safeCall(listener, computed)
	end
end

--------------------------------------------------------------------------------
-- 등록
--------------------------------------------------------------------------------

--[[
	화면용 ScreenGui 를 만든다. 로블록스 위쪽 버튼과 노치를 피하고(CoreUISafeInsets),
	배율이 자동으로 걸린다.
]]
function ScreenManager.createScreen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder

	local scale = Instance.new("UIScale")
	scale.Scale = if layout then layout.scale else 1
	scale.Parent = gui
	table.insert(scales, scale)

	gui.Parent = playerGui()
	return gui
end

-- 화면 전체를 덮는 장식용(눌리지 않는) ScreenGui. 번쩍임·어둡게 덮기 등에 쓴다.
function ScreenManager.createOverlay(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = playerGui()
	return gui
end

function ScreenManager.onLayout(listener: (UILayout.Layout) -> ())
	table.insert(layoutListeners, listener)
	if layout then
		safeCall(listener, layout)
	end
end

function ScreenManager.onStateChanged(listener: () -> ())
	table.insert(stateListeners, listener)
end

function ScreenManager.getLayout(): UILayout.Layout?
	return layout
end

-- 사각형 하나를 GuiObject 의 위치·크기로 (디자인 칸 단위, UIScale 이 배율을 곱한다)
function ScreenManager.place(object: GuiObject, rect: UILayout.Rect)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(rect.x, rect.y)
	object.Size = UDim2.fromOffset(rect.w, rect.h)
end

--------------------------------------------------------------------------------
-- 상태
--------------------------------------------------------------------------------

function ScreenManager.getMode(): Mode
	return mode
end

function ScreenManager.setMode(newMode: Mode)
	if mode == newMode then
		return
	end
	mode = newMode
	-- 경주로 들어가면 열려 있던 창은 닫는다.
	if (newMode == "race" or newMode == "raceOut") and modal ~= nil then
		ScreenManager.closeModal()
		return
	end
	notifyState()
end

function ScreenManager.isRacing(): boolean
	return mode == "race" or mode == "raceOut"
end

-- 대장간을 열고 닫는다 (경주 중에는 무시)
function ScreenManager.setForgeOpen(open: boolean)
	if ScreenManager.isRacing() then
		return
	end
	ScreenManager.setMode(if open then "forge" else "lobby")
end

function ScreenManager.isForgeOpen(): boolean
	return mode == "forge"
end

--[[
	큰 창 등록. 이름 하나에 여는 함수·닫는 함수.
	열 때는 다른 창을 먼저 닫는다(한 번에 하나만).
]]
function ScreenManager.registerModal(name: string, onOpen: () -> (), onClose: () -> ())
	modals[name] = { onOpen = onOpen, onClose = onClose }
end

function ScreenManager.getModal(): string?
	return modal
end

function ScreenManager.openModal(name: string)
	if ScreenManager.isRacing() then
		return
	end

	local spec = modals[name]
	if spec == nil then
		warn(`[ScreenManager] 등록되지 않은 창: {name}`)
		return
	end

	if modal == name then
		return
	end
	if modal ~= nil then
		local previous = modals[modal]
		if previous then
			safeCall(previous.onClose)
		end
	end

	modal = name
	safeCall(spec.onOpen)
	notifyState()
end

function ScreenManager.closeModal()
	local current = modal
	if current == nil then
		return
	end

	modal = nil
	local spec = modals[current]
	if spec then
		safeCall(spec.onClose)
	end
	notifyState()
end

function ScreenManager.toggleModal(name: string)
	if modal == name then
		ScreenManager.closeModal()
	else
		ScreenManager.openModal(name)
	end
end

--------------------------------------------------------------------------------

-- 부트스트랩이 컨트롤러보다 먼저 한 번 부른다.
function ScreenManager.init()
	if probe ~= nil then
		return
	end

	-- 안전 영역 크기를 재는 보이지 않는 화면
	local measure = Instance.new("ScreenGui")
	measure.Name = "ForgeLayoutProbe"
	measure.ResetOnSpawn = false
	measure.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	measure.Parent = playerGui()
	probe = measure

	-- 큰 창 뒤를 어둡게. 누르면 창이 닫힌다.
	local dim = ScreenManager.createOverlay("ForgeDim", 9)
	dim.Enabled = false
	local dimButton = Instance.new("TextButton")
	dimButton.Name = "Dim"
	dimButton.Text = ""
	dimButton.AutoButtonColor = false
	dimButton.BackgroundColor3 = Color3.new(0, 0, 0)
	dimButton.BackgroundTransparency = 0.45
	dimButton.BorderSizePixel = 0
	dimButton.Size = UDim2.fromScale(1, 1)
	dimButton.Parent = dim
	dimButton.Activated:Connect(function()
		ScreenManager.closeModal()
	end)
	dimGui = dim

	measure:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
	recompute()
	applyTouchControls()
end

return ScreenManager
