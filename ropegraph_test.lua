local checkers = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
local mkassert = checkers.mkassert

local m = _mod.modules.ropegraph

local mkemptychecker = function(caller)
	return function(tbl, label)
		if type(tbl) ~= "table" then
			error(caller.." "..label.." expected to be a table")
		end
		for k, v in pairs(tbl) do
			error(caller.." "..label.." table expected to be empty")
		end
	end
end

m.test = function()
	local dname = ("ropegraph.test()")
	local assert = mkassert(dname)
	local emptycheck = mkemptychecker(dname)
	local g = m.new()

	emptycheck(g:successor(1), "successor list for non-existant group")
	--print("-- before update --")
	g:update("foo", "a", 1, {b="bar"}, {b=2})
	--print("-- after update --")
	local successors = g:successor(1)
	local size = #successors
	--print(dump(g.groupmap))
	assert(size == 1, "successor list should now have one entry, actual="..size)
	assert(successors[1] == 2, "successor group should have ID 2")

	-- add another edge which still connects groups 1 and 2.
	-- behaviour of ropes should not change.
	g:update("foo", "c", 1, {b="bar"}, {b=2})
	successors = g:successor(1)
	assert(size == 1, "successor list should now have one entry, actual="..size)
	assert(successors[1] == 2, "successor group should have ID 2")

	-- remove that edge we specified first, the second one should hold the rope open.
	g:update("foo", "a", 1, {}, {})
	successors = g:successor(1)
	assert(size == 1, "successor list should now have one entry, actual="..size)
	assert(successors[1] == 2, "successor group should have ID 2")

	return "self-tests completed successfully"
end
