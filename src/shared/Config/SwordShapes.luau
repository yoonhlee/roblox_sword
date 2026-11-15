--!strict
--[[
	SwordShapes — 블록으로 짓는 3D 검 모양 (통합 기획서 8-2절).

	숫자 데이터만 둔다. 실제 파트는 shared/SwordModel 이 만든다.
	좌표(스터드): 손잡이 가운데가 원점, 칼날은 +Y 로 뻗는다. 두께는 Z.
	부위(role)마다 색이 정해진다.
	  blade  칼날 바탕 (강철색)
	  edge   칼날 테두리 (레벨 색 = 쇠 달구는 색, 5강부터 빛남)
	  core   늘 빛나는 속심 (accent 색, 네온)
	  guard  손잡이 위 가드 (등급 색)
	  grip   손잡이 (나무·가죽)
	  pommel 손잡이 끝 (등급 색)
	  accent 장식 (accent 색)
	shape: "Block" | "Wedge" | "Ball" | "Cylinder". rot 은 도(°) 단위 X·Y·Z 회전.

	새 검을 추가하면 여기에 모양을 넣는다. 없으면 DEFAULT(무쇠 검 모양)로 보인다.
]]

export type PartSpec = {
	role: string,
	shape: string,
	size: { number },
	pos: { number },
	rot: { number }?,
}

export type Shape = {
	accent: { number }?, -- core·accent 부위 색 (없으면 레벨 색)
	parts: { PartSpec },
}

local SwordShapes = {}

-- 공통 손잡이 (가드는 검마다 다르다)
local function grip(length: number): { PartSpec }
	return {
		{
			role = "grip",
			shape = "Cylinder",
			size = { length, 0.32, 0.32 },
			pos = { 0, 0, 0 },
			rot = { 0, 0, 90 },
		},
		{
			role = "pommel",
			shape = "Ball",
			size = { 0.5, 0.5, 0.5 },
			pos = { 0, -length / 2 - 0.15, 0 },
		},
	}
end

local function concat(...: { PartSpec }): { PartSpec }
	local result: { PartSpec } = {}
	for _, list in { ... } do
		for _, part in list do
			table.insert(result, part)
		end
	end
	return result
end

SwordShapes.List = {
	-- 무쇠 검: 곧은 외날, 장식 없음
	ironBlade = {
		parts = concat(grip(1.1), {
			{ role = "guard", shape = "Block", size = { 1.5, 0.22, 0.4 }, pos = { 0, 0.66, 0 } },
			{ role = "blade", shape = "Block", size = { 0.42, 3.1, 0.1 }, pos = { 0, 2.32, 0 } },
			{ role = "edge", shape = "Block", size = { 0.06, 3.1, 0.12 }, pos = { 0.24, 2.32, 0 } },
			{
				role = "edge",
				shape = "Block",
				size = { 0.06, 3.1, 0.12 },
				pos = { -0.24, 2.32, 0 },
			},
			{
				role = "blade",
				shape = "Wedge",
				size = { 0.1, 0.5, 0.42 },
				pos = { 0, 4.12, 0 },
				rot = { 0, 90, 0 },
			},
		}),
	},

	-- 잉걸불 검: 톱니 같은 숯 모서리, 속심이 늘 주황
	emberEdge = {
		accent = { 255, 138, 42 },
		parts = concat(grip(1.1), {
			{ role = "guard", shape = "Block", size = { 1.4, 0.26, 0.42 }, pos = { 0, 0.66, 0 } },
			{ role = "blade", shape = "Block", size = { 0.5, 3.0, 0.12 }, pos = { 0, 2.28, 0 } },
			{ role = "core", shape = "Block", size = { 0.1, 2.8, 0.14 }, pos = { 0, 2.28, 0 } },
			{
				role = "edge",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.22 },
				pos = { 0.34, 1.4, 0 },
				rot = { 0, 90, 0 },
			},
			{
				role = "edge",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.22 },
				pos = { 0.34, 2.1, 0 },
				rot = { 0, 90, 0 },
			},
			{
				role = "edge",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.22 },
				pos = { 0.34, 2.8, 0 },
				rot = { 0, 90, 0 },
			},
			{
				role = "edge",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.22 },
				pos = { -0.34, 1.75, 0 },
				rot = { 0, -90, 0 },
			},
			{
				role = "edge",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.22 },
				pos = { -0.34, 2.45, 0 },
				rot = { 0, -90, 0 },
			},
			{
				role = "blade",
				shape = "Wedge",
				size = { 0.12, 0.6, 0.5 },
				pos = { 0, 4.08, 0 },
				rot = { 0, 90, 0 },
			},
		}),
	},

	-- 물결 송곳니: 물결처럼 휜 날(세 마디), 끝이 송곳니
	tideFang = {
		accent = { 140, 210, 255 },
		parts = concat(grip(1.1), {
			{ role = "guard", shape = "Block", size = { 1.3, 0.22, 0.4 }, pos = { 0, 0.66, 0 } },
			{
				role = "blade",
				shape = "Block",
				size = { 0.44, 1.1, 0.1 },
				pos = { 0.04, 1.3, 0 },
				rot = { 0, 0, -6 },
			},
			{
				role = "blade",
				shape = "Block",
				size = { 0.44, 1.1, 0.1 },
				pos = { -0.02, 2.3, 0 },
				rot = { 0, 0, 8 },
			},
			{
				role = "blade",
				shape = "Block",
				size = { 0.42, 1.1, 0.1 },
				pos = { 0.05, 3.28, 0 },
				rot = { 0, 0, -8 },
			},
			{ role = "edge", shape = "Block", size = { 0.06, 3.2, 0.12 }, pos = { 0.27, 2.3, 0 } },
			{
				role = "accent",
				shape = "Block",
				size = { 0.08, 2.6, 0.12 },
				pos = { -0.18, 2.3, 0 },
			},
			{
				role = "blade",
				shape = "Wedge",
				size = { 0.1, 0.7, 0.42 },
				pos = { 0.1, 4.18, 0 },
				rot = { 0, 90, -12 },
			},
		}),
	},

	-- 폭풍 바늘: 아주 가는 찌르기 검, 둥근 가드, 잔 번개 무늬
	stormNeedle = {
		accent = { 201, 162, 255 },
		parts = concat(grip(1.2), {
			{
				role = "guard",
				shape = "Cylinder",
				size = { 0.16, 1.1, 1.1 },
				pos = { 0, 0.7, 0 },
				rot = { 0, 0, 90 },
			},
			{ role = "blade", shape = "Block", size = { 0.12, 3.6, 0.12 }, pos = { 0, 2.6, 0 } },
			{ role = "edge", shape = "Block", size = { 0.04, 3.6, 0.14 }, pos = { 0.07, 2.6, 0 } },
			{
				role = "accent",
				shape = "Block",
				size = { 0.05, 0.6, 0.15 },
				pos = { 0, 1.6, 0 },
				rot = { 0, 0, 25 },
			},
			{
				role = "accent",
				shape = "Block",
				size = { 0.05, 0.6, 0.15 },
				pos = { 0, 2.6, 0 },
				rot = { 0, 0, -25 },
			},
			{
				role = "accent",
				shape = "Block",
				size = { 0.05, 0.6, 0.15 },
				pos = { 0, 3.6, 0 },
				rot = { 0, 0, 25 },
			},
			{
				role = "blade",
				shape = "Wedge",
				size = { 0.12, 0.5, 0.12 },
				pos = { 0, 4.65, 0 },
				rot = { 0, 90, 0 },
			},
		}),
	},

	-- 새벽가르기: 넓은 대검, 금빛 날개 가드
	dawnbreaker = {
		accent = { 255, 244, 200 },
		parts = concat(grip(1.4), {
			{ role = "guard", shape = "Block", size = { 1.1, 0.3, 0.46 }, pos = { 0, 0.82, 0 } },
			{
				role = "guard",
				shape = "Wedge",
				size = { 0.46, 0.7, 0.6 },
				pos = { 0.85, 0.95, 0 },
				rot = { 0, 90, -30 },
			},
			{
				role = "guard",
				shape = "Wedge",
				size = { 0.46, 0.7, 0.6 },
				pos = { -0.85, 0.95, 0 },
				rot = { 0, -90, 30 },
			},
			{ role = "blade", shape = "Block", size = { 0.9, 3.4, 0.14 }, pos = { 0, 2.67, 0 } },
			{ role = "edge", shape = "Block", size = { 0.08, 3.4, 0.16 }, pos = { 0.47, 2.67, 0 } },
			{
				role = "edge",
				shape = "Block",
				size = { 0.08, 3.4, 0.16 },
				pos = { -0.47, 2.67, 0 },
			},
			{ role = "core", shape = "Block", size = { 0.14, 3.0, 0.18 }, pos = { 0, 2.6, 0 } },
			{
				role = "blade",
				shape = "Wedge",
				size = { 0.14, 0.9, 0.9 },
				pos = { 0, 4.82, 0 },
				rot = { 0, 90, 0 },
			},
			{ role = "accent", shape = "Ball", size = { 0.4, 0.4, 0.4 }, pos = { 0, -0.95, 0 } },
		}),
	},
} :: { [string]: Shape }

SwordShapes.DEFAULT = SwordShapes.List.ironBlade

SwordShapes.ROLES = { "blade", "edge", "core", "guard", "grip", "pommel", "accent" }
SwordShapes.SHAPES = { "Block", "Wedge", "Ball", "Cylinder" }

function SwordShapes.get(id: string): Shape
	return SwordShapes.List[id] or SwordShapes.DEFAULT
end

-- 손에 쥐는 위치(원점)에서 칼끝까지 대략 길이 (미리보기 카메라 거리 계산용)
function SwordShapes.length(shape: Shape): number
	local top, bottom = 0, 0
	for _, part in shape.parts do
		top = math.max(top, part.pos[2] + part.size[2] / 2)
		bottom = math.min(bottom, part.pos[2] - part.size[2] / 2)
	end
	return top - bottom
end

return SwordShapes
