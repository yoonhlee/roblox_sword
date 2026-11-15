--!strict
--[[
	불씨 광장 배치(Config/World)와 블록 검 모양(Config/SwordShapes)이 서로 맞는지 고정해 둔다
	(통합 기획서 8-2절). 겹치거나 광장 밖으로 나가면 Studio 에서 보기 전에 여기서 잡는다.
]]

local t = require("./harness")
local World = require("../src/shared/Config/World")
local SwordShapes = require("../src/shared/Config/SwordShapes")
local Weapons = require("../src/shared/Config/Weapons")
local Locale = require("../src/shared/Locale")

local LOBBY = World.LOBBY
local HALF_X, HALF_Z = LOBBY.sizeX / 2, LOBBY.sizeZ / 2

type Box = { minX: number, maxX: number, minZ: number, maxZ: number, name: string }

local function box(name: string, x: number, z: number, sizeX: number, sizeZ: number): Box
	return {
		name = name,
		minX = x - sizeX / 2,
		maxX = x + sizeX / 2,
		minZ = z - sizeZ / 2,
		maxZ = z + sizeZ / 2,
	}
end

local function overlap(a: Box, b: Box): boolean
	return a.minX < b.maxX and b.minX < a.maxX and a.minZ < b.maxZ and b.minZ < a.maxZ
end

local function insideLobby(b: Box): boolean
	return b.minX >= -HALF_X and b.maxX <= HALF_X and b.minZ >= -HALF_Z and b.maxZ <= HALF_Z
end

-- 바닥에 놓이는 큰 시설 (서로 겹치면 안 된다)
local function facilities(): { Box }
	local list: { Box } = {}
	local forge = World.FORGE
	table.insert(list, box("대장간", forge.x, forge.z, forge.sizeX, forge.sizeZ))
	local gate = World.GATE
	table.insert(
		list,
		box("관문 원", gate.ringX, gate.ringZ, gate.ringRadius * 2, gate.ringRadius * 2)
	)
	table.insert(list, box("관문", gate.x, gate.z, gate.width, gate.pillarSize))
	table.insert(list, box("스폰", LOBBY.spawnX, LOBBY.spawnZ, LOBBY.spawnSize, LOBBY.spawnSize))
	for index, pad in World.TREADMILL_PADS do
		table.insert(
			list,
			box(
				`러닝머신 {index}`,
				pad.x,
				pad.z,
				World.TREADMILL_PAD.sizeX,
				World.TREADMILL_PAD.sizeZ
			)
		)
	end
	local wall = World.RANKING_WALL
	table.insert(list, box("명예의 벽", wall.x, wall.z, 2, wall.width))
	table.insert(list, box("진열대", World.SHOWCASE.x, World.SHOWCASE.z, 4, 4))
	return list
end

t.describe("불씨 광장 배치", function()
	t.it("모든 시설이 광장 안에 있다", function()
		for _, b in facilities() do
			t.expect(insideLobby(b), `{b.name} 이 광장 밖`)
		end
	end)

	t.it("시설끼리 겹치지 않는다", function()
		local list = facilities()
		for i = 1, #list do
			for j = i + 1, #list do
				t.expect(
					not overlap(list[i], list[j]),
					`{list[i].name} 와 {list[j].name} 가 겹친다`
				)
			end
		end
	end)

	t.it("러닝머신 옆 풀무도 광장 안이고 대장간과 겹치지 않는다", function()
		local forge = World.FORGE
		local forgeBox = box("대장간", forge.x, forge.z, forge.sizeX, forge.sizeZ)
		for index, pad in World.TREADMILL_PADS do
			local bellows =
				box(`풀무 {index}`, pad.x + World.TREADMILL_PAD.bellowsOffsetX, pad.z, 2.6, 3.6)
			t.expect(insideLobby(bellows), `풀무 {index} 가 광장 밖`)
			t.expect(not overlap(bellows, forgeBox), `풀무 {index} 가 대장간과 겹친다`)
		end
	end)

	t.it("경주에서 돌아오는 자리는 관문 원 밖, 광장 안이다", function()
		local point = World.RETURN_POINT
		local gate = World.GATE
		local dx, dz = point.x - gate.ringX, point.z - gate.ringZ
		local distance = math.sqrt(dx * dx + dz * dz)
		t.expect(
			distance > gate.ringRadius + point.scatter,
			"돌아오자마자 원 안이면 바로 다시 대기열에 들어간다"
		)
		t.expect(
			insideLobby(
				box("돌아오는 자리", point.x, point.z, point.scatter * 2, point.scatter * 2)
			)
		)
	end)

	t.it(
		"모루 근접 버튼 거리 안에 모루 영감이 있고 스폰은 밖이다",
		function()
			local forge = World.FORGE
			local function dist(x: number, z: number): number
				return math.sqrt((x - forge.anvil.x) ^ 2 + (z - forge.anvil.z) ^ 2)
			end
			t.expect(
				dist(forge.npc.x, forge.npc.z) < forge.promptDistance,
				"모루 영감이 모루에서 너무 멀다"
			)
			t.expect(
				dist(LOBBY.spawnX, LOBBY.spawnZ) > forge.promptDistance,
				"스폰에서 바로 근접 버튼이 뜬다"
			)
		end
	)

	t.it("관 경로가 풀무에서 시작해 대장간 서쪽 벽에서 끝난다", function()
		for index, pad in World.TREADMILL_PADS do
			local path = World.pipePath(index)
			t.expectEqual(#path, 4)
			t.expectEqual(path[1][1], pad.x + World.TREADMILL_PAD.bellowsOffsetX)
			t.expectEqual(path[#path][1], World.FORGE.x - World.FORGE.sizeX / 2)
		end
		t.expectEqual(#World.pipePath(99), 0)
	end)

	t.it("횃불과 표지판이 광장 안에 있고 표지판 문구가 있다", function()
		for index, torch in World.TORCHES do
			t.expect(
				math.abs(torch.x) <= HALF_X and math.abs(torch.z) <= HALF_Z,
				`횃불 {index} 가 광장 밖`
			)
		end
		for _, sign in World.SIGNS do
			t.expect(
				math.abs(sign.x) < HALF_X and math.abs(sign.z) < HALF_Z,
				`표지판이 광장 밖: {sign.key}`
			)
			t.expect(
				Locale.Strings.ko[sign.key] ~= nil and Locale.Strings.en[sign.key] ~= nil,
				`문구 없음: {sign.key}`
			)
		end
	end)

	t.it("러닝머신은 4대이고 모두 1단계다 (2단계 이상은 미정 D18)", function()
		t.expectEqual(#World.TREADMILL_PADS, 4)
		for _, pad in World.TREADMILL_PADS do
			t.expectEqual(pad.tierId, "tier1")
		end
	end)

	t.it("코스는 광장보다 멀리 북쪽에서 시작한다", function()
		t.expect(
			World.COURSE.startZ - World.COURSE.chaserDepth - 60 > HALF_Z,
			"코스 뒤쪽이 광장과 겹친다"
		)
	end)
end)

t.describe("블록 검 모양", function()
	local function has(roleList: { string }, value: string): boolean
		return table.find(roleList, value) ~= nil
	end

	t.it("지금 있는 검 5종 모두 모양이 있다", function()
		for id in Weapons.List do
			t.expect(SwordShapes.List[id] ~= nil, `모양 없음: {id}`)
		end
	end)

	t.it("모양이 없는 검은 기본 모양으로 보인다", function()
		t.expectEqual(SwordShapes.get("아직없는검"), SwordShapes.DEFAULT)
	end)

	t.it(
		"모든 모양에 칼날·테두리·가드·손잡이가 있고 부위·모양 이름이 올바르다",
		function()
			for id, shape in SwordShapes.List do
				local roles: { [string]: boolean } = {}
				for index, part in shape.parts do
					t.expect(
						has(SwordShapes.ROLES, part.role),
						`{id}[{index}] 모르는 부위 {part.role}`
					)
					t.expect(
						has(SwordShapes.SHAPES, part.shape),
						`{id}[{index}] 모르는 모양 {part.shape}`
					)
					t.expectEqual(#part.size, 3, `{id}[{index}] 크기`)
					t.expectEqual(#part.pos, 3, `{id}[{index}] 위치`)
					for _, value in part.size do
						t.expect(value > 0, `{id}[{index}] 크기가 0 이하`)
					end
					roles[part.role] = true
				end
				for _, required in { "blade", "edge", "guard", "grip" } do
					t.expect(roles[required] == true, `{id} 에 {required} 가 없다`)
				end
			end
		end
	)

	t.it(
		"검 길이는 3.5~6.5칸 사이다 (대검 새벽가르기가 가장 길다, 손에 들면 0.62배)",
		function()
			for id, shape in SwordShapes.List do
				local length = SwordShapes.length(shape)
				t.expect(length >= 3.5 and length <= 6.5, `{id} 길이 {length}`)
			end
		end
	)

	t.it("칼날은 손잡이 위(+Y)로 뻗는다", function()
		for id, shape in SwordShapes.List do
			for _, part in shape.parts do
				if part.role == "blade" then
					t.expect(part.pos[2] > 0.5, `{id} 칼날이 손잡이 아래에 있다`)
				end
			end
		end
	end)
end)
