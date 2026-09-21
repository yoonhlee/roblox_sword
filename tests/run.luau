--!strict
--[[
	run — 전체 테스트 엔트리포인트.

	실행:  lune run tests/run
	(새 spec 파일을 추가하면 아래 목록에 require 한 줄을 더한다)
]]

local t = require("./harness")

require("./Format.spec")
require("./EnhanceTable.spec")
require("./EnhanceLogic.spec")
require("./RateLimiter.spec")
require("./BattleLogic.spec")

t.finish()
