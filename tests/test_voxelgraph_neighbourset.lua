#!/usr/bin/env lua5.1
local errors =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.errors")
local expect_error = errors.expect_error
local neighbourset =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.neighbourset")

local testing =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.testing")



local get_test_object = function()
	return neighbourset.mk_neighbour_lut()
end



-- test helper data:
-- neighbour set table which should be passed through unchanged.
-- it is assumed that the neighbourset will NOT copy the handler's return tables.
local testdata = {}
local delay = function(v)
	return function()
		return v
	end
end
local testhandler = delay(testdata)
local failhandler = function() end
local nodatahandler = function() return nil, "ENODATA" end

-- test helper: assert that the query for a given node name returns no data.
local assert_no_data = function(set, name)
	local data, err = set:query_neighbour_set({name=name})
	assert(data == nil)
	assert(err == "ENODATA")
end

-- test helper: assert that a query returns EHOOKFAIL.
local assert_hook_fail = function(set, name)
	local data, err = set:query_neighbour_set({name=name})
	assert(data == nil)
	assert(err == "EHOOKFAIL")
end



local dummy = function() end
local n = "example"
local testvecs = {
	function(dep)
		-- test wrongly typed objects,
		-- and that normal functions can still go in afterwards.
		dep:add_custom_hook("1", dummy)
		expect_error("err.args.expected_t.func", function()
			dep:add_custom_hook(n, 1)
		end)
		dep:add_custom_hook("2", dummy)
		expect_error("err.args.expected_t.func", function()
			dep:add_custom_hook("3", 1)
		end)
	end,

	function(dep)
		-- check that duplicate insertions are caught correctly.
		dep:add_custom_hook(n, dummy)
		dep:add_custom_hook("example2", dummy)
		expect_error("err.register.duplicate", function()
			dep:add_custom_hook(n, dummy)
		end)
	end,

	function(dep)
		-- a completely emtpy neighbour set should not respond to anything.
		assert_no_data(dep, n)
		assert_no_data(dep, "wat")
	end,

	function(dep)
		-- check that first no data is returned,
		-- then that it starts returning the expected data after registration.
		-- meanwhile another name should still return empty.
		local n2 = "1234"
		assert_no_data(dep, n)
		assert_no_data(dep, n2)
		dep:add_custom_hook(n, testhandler)
		local r = dep:query_neighbour_set({name=n})
		assert(r == testdata)
		assert_no_data(dep, n2)
	end,

	function(dep)
		-- test that different handlers remain separate.
		for i = 1, 5, 1 do
			local t = {}
			local n = tostring(i)
			dep:add_custom_hook(n, delay(t))
			assert(dep:query_neighbour_set({name=n}) == t)
		end
	end,

	function(dep)
		-- test that a handler which simply returns nil,
		-- with no other error indicated, causes EHOOKFAIL.
		-- this is to catch handler function bugs,
		-- as a mistaken return can result in nil results.
		dep:add_custom_hook(n, failhandler)
		assert_hook_fail(dep, n)
	end,

	function(dep)
		-- likewise catch that a hook that explicitly indicates EHOOKFAIL itself
		-- (by returning it as a second value)
		-- also gets passed through.
		dep:add_custom_hook(n, function() return nil, "EHOOKFAIL" end)
		assert_hook_fail(dep, n)
	end,

	function(dep)
		-- a handler should be able to explicitly indicate a non-fatal "no data available",
		-- in the same way the top-level object does if no handlers are present.
		-- this is to allow neighbour sets to compose,
		-- in that the handler for a given node type might be a sub-object
		-- which further looks up handlers based on e.g. metadata keys.
		dep:add_custom_hook(n, nodatahandler)
		local data, err = dep:query_neighbour_set({name=n})
		assert(data == nil)
		assert(err == "ENODATA")
	end,
}

testing.test_harness_with_deps({testvecs=testvecs, get_dep = get_test_object})


