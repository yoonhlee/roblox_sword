--!strict
--[[
	화면 구역이 겹치거나 잘리지 않는지 기기 크기별로 확인한다 (통합 기획서 8-1절).

	크기는 "화면 전체"에서 로블록스 위쪽 메뉴 줄(58px)과 기기 노치를 뺀 값이다.
	(실제 값은 기기마다 조금씩 다르다. Studio 스크린샷으로 다시 확인한다.)
]]

local t = require("./harness")
local VisualConfig = require("../src/shared/Config/VisualConfig")
local UILayout = require("../src/shared/Pure/UILayout")

local C = VisualConfig.Layout

type Device = { name: string, width: number, height: number, touch: boolean }

local TOPBAR = 58

local DEVICES: { Device } = {
	{ name = "폰 667×375", width = 667, height = 375 - TOPBAR, touch = true },
	{
		name = "폰 844×390 (노치)",
		width = 844 - 47 * 2,
		height = 390 - TOPBAR - 21,
		touch = true,
	},
	{ name = "폰 915×412", width = 915, height = 412 - TOPBAR, touch = true },
	{ name = "태블릿 1024×768", width = 1024, height = 768 - TOPBAR, touch = true },
	{ name = "태블릿 1180×820", width = 1180, height = 820 - TOPBAR - 20, touch = true },
	{ name = "PC 1366×768", width = 1366, height = 768 - TOPBAR, touch = false },
	{ name = "PC 1920×1080", width = 1920, height = 1080 - TOPBAR, touch = false },
}

local function zone(layout: UILayout.Layout, name: string): UILayout.Rect
	return (layout :: any)[name]
end

for _, device in DEVICES do
	local layout = UILayout.compute(device.width, device.height, device.touch, C)

	t.describe(`화면 배치 · {device.name}`, function()
		t.it("배율이 허용 범위 안이다", function()
			t.expect(
				layout.scale >= C.minScale - 1e-9 and layout.scale <= C.maxScale + 1e-9,
				`배율 {layout.scale}`
			)
		end)

		t.it("모든 구역이 화면 안에 있다", function()
			for _, names in UILayout.MODE_ZONES do
				for _, name in names do
					local r = zone(layout, name)
					t.expect(
						UILayout.inside(r, layout.width, layout.height),
						`{name} 이 화면 밖`
					)
				end
			end
		end)

		t.it("같은 화면 상태에서 보이는 구역끼리 겹치지 않는다", function()
			for mode, names in UILayout.MODE_ZONES do
				for i = 1, #names do
					for j = i + 1, #names do
						local a, b = zone(layout, names[i]), zone(layout, names[j])
						t.expect(
							not UILayout.overlaps(a, b),
							`{mode}: {names[i]} 와 {names[j]} 가 겹침`
						)
					end
				end
			end
		end)

		t.it("버튼이 실제 화면에서 44px 이상이다", function()
			local s = layout.scale
			t.expect(C.menuButton * s >= C.minTouchPx - 1e-9, `메뉴 버튼 {C.menuButton * s}px`)
			t.expect(C.raceButtonHeight * s >= C.minTouchPx - 1e-9, "경주 버튼")
			t.expect(C.chipHeight * s >= 26, "재화 칩이 너무 작다")
		end)

		t.it("쓸 만한 크기의 구역이 나온다", function()
			t.expect(layout.forgePanel.w >= 600, `대장간 너비 {layout.forgePanel.w}`)
			t.expect(layout.forgePanel.h >= 280, `대장간 높이 {layout.forgePanel.h}`)
			t.expect(layout.modal.h >= 300, `창 높이 {layout.modal.h}`)
			t.expect(layout.feedLobby.w >= 200, `피드 너비 {layout.feedLobby.w}`)
			t.expect(
				layout.lobbyStatus.w >= 180,
				`트레드밀 막대 너비 {layout.lobbyStatus.w}`
			)
			t.expect(layout.raceResult.h >= 180, `결과 카드 높이 {layout.raceResult.h}`)
		end)

		if device.touch then
			t.it("이동 컨트롤 자리가 실제 크기만큼 비어 있다", function()
				t.expectNear(layout.joystick.w * layout.scale, C.joystickWidth, 1e-6)
				t.expectNear(layout.jump.h * layout.scale, C.jumpHeight, 1e-6)
			end)
		else
			t.it(
				"PC 에는 이동 컨트롤 자리가 없고 메뉴가 세로 한 줄이다",
				function()
					t.expectEqual(layout.joystick.w, 0)
					t.expectEqual(layout.menuColumns, 1)
				end
			)
		end
	end)
end

t.describe("UILayout 보조 함수", function()
	t.it("겹침 판정", function()
		local a = { x = 0, y = 0, w = 10, h = 10 }
		t.expect(UILayout.overlaps(a, { x = 5, y = 5, w = 10, h = 10 }))
		t.expect(
			not UILayout.overlaps(a, { x = 10, y = 0, w = 5, h = 5 }),
			"맞닿기만 하면 겹침 아님"
		)
		t.expect(
			not UILayout.overlaps(a, { x = 3, y = 3, w = 0, h = 0 }),
			"크기 0 은 겹침 아님"
		)
	end)

	t.it("태블릿 이상에서는 메뉴가 세로 한 줄", function()
		local layout = UILayout.compute(1024, 768 - TOPBAR, true, C)
		t.expectEqual(layout.menuColumns, 1)
	end)
end)
