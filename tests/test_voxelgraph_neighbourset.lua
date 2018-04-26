#!/usr/bin/env lua5.1
local errors =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.errors")
local expect_error = errors.expect_error
local neighbourset =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.neighbourset")

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

-- test helper: assert that the query for a given node name returns no data.
local assert_no_data = function(set, name)
	local data, err = set:query_neighbour_set({name=name}, nil)
	assert(data == nil)
	assert(err == "ENODATA")
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
		local r = dep:query_neighbour_set({name=n}, nil)
		assert(r == testdata)
		assert_no_data(dep, n2)
	end,
}

local total = #testvecs
for index, vec in ipairs(testvecs) do
	local dep = get_test_object()
	ok, err = pcall(vec, dep)
	if (not ok) then
		error("test case "..index.."/"..total.." failure: "..tostring(err))
	end
end

local n = "neighbourset"
print(n..": all cases run successfully")
