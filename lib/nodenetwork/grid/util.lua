--[[
Various helpers and utilities for working with linked grid objects.
]]

local getint = function(n)
	assert(type(n) == "number")
	assert((n % 1.0) == 0)
	return n
end

local i = {}
-- get data from a grid in an iterator form.
-- will copy coordinates during initialisation;
-- does *NOT* sort the coordinates first.
-- also doesn't take into consideration neighbour direction traversals / grid links.
local grid_node_iterator = function(gridget, minpos, maxpos)
	local xm = getint(minpos.x)
	local ym = getint(minpos.y)
	local zm = getint(minpos.z)
	local xh = getint(maxpos.x)
	local yh = getint(maxpos.y)
	local zh = getint(maxpos.z)

	local xi, yi, zi = 0, 0, 0
	return coroutine.wrap(function()
		for z = zm, zh, 1 do
		for y = ym, yh, 1 do
		for x = xm, xh, 1 do
			local data = gridget({x=x,y=y,z=z})
			coroutine.yield(data)
		end
		end
		end
	end)
end
i.grid_node_iterator = grid_node_iterator





local take_iterator_n_ = function(n)
	local count = getint(n)
	assert(count > 0)
	return function(it)
		local ret = {}
		for i = 1, count, 1 do
			local v = it()
			assert(v ~= nil)
			ret[i] = v
		end
		return ret
	end
end

-- show a portion of a grid in 2D;
-- mostly useful for debugging grid contents from the console.
local dprint = print
local debug_show_grid_ = function(_w, _h, print, get, concat, prefix)
	local width = getint(_w)
	local height = getint(_h)
	local take_n = take_iterator_n_(width)

	return function(gridit)
		for i = 1, height, 1 do
			local row = take_n(gridit)
			-- there's something functional in here trying to get out...
			-- I just can't get my head around what right now.
			local fold = prefix
			-- oh wait...
			for i = 1, width, 1 do
				local v = row[i]
				--dprint(i)
				--dprint(v)
				fold = concat(fold, get(v))
				--dprint("fold:", fold)
			end
			print(fold)
		end
	end
end
i.debug_show_grid_ = debug_show_grid_


