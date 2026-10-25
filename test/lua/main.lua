-- The entry of the Lua tests: the pieces of the program that are plain Lua, and the page against
-- the kit's page API. test/lua.test.mjs packs this with src/program/ into the runner and runs it.

local t = require("t")

require("parse_test")
require("feed_test")
require("page_test")

t.run()
