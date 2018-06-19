--[[
An implementation of a grid interface
(see voxelgraph.searchimpl) which reads node data from a flat array.
Mostly useful for testing code which operates on one without needing to fire up MT.
]]

--[[
The flat array is indexed as (Zi * Xstride * Ystride) + (Yi * Xstride) + (Xi) + 1.
This means that all the values for a given Z coord come first,
then the Z plane above that one, etc.
The +1 is because the dimensions are zero-indexed,
but array-like tables in lua are naturally 1-based*.

* And luajit appears to do weird things for t[0]
as opposed to the regular array-like part for t[1], t[2] etc.
]]
local linkedgrid = 
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.grid.linkedgrid")
local oob = linkedgrid.constants.out_of_bounds()





-- compute base index into array (handles increment).
-- x/y/z are region relative.
-- xw, yw and zw are the dimensions of the region in nodes.
local flat_xyz_index = function(x, y, z, xw, yw, zw)
	assert(0 <= x)
	assert(0 <= y)
	assert(0 <= z)
	-- could have width of one but dim indexes start at zero here
	assert(x < xw)
	assert(y < yw)
	assert(z < zw)

	local v = (z * yw * xw) + (y * xw) + (x)
	assert(v < (zw * yw * xw))
	return v + 1
end

-- given a base position, and an offset plus width in each dimension
-- to describe the region's position and size,
-- calculate the coordinates inside the region or nil if it falls outside.
local fail = function() return nil, nil, nil end
local coordinates_inside_region = function(xb, yb, zb, xw, yw, zw, xi, yi, zi)
	-- subtract the base coordinates so we work in region relative.
	-- if this results in negative numbers we know we're outside the region
	local xr = xi - xb
	local yr = yi - yb
	local zr = zi - zb
	if xr < 0 then return fail() end
	if yr < 0 then return fail() end
	if zr < 0 then return fail() end

	-- check if it's outside the upper limit (note zero-based)
	if xr >= xw then return fail() end
	if yr >= yw then return fail() end
	if zr >= zw then return fail() end

	-- if it's inside the range then it's already region relative, so return
	return xr, yr, zr
end





-- get the data for a position inside the region from the backing array.
-- we have to raise an error on a missing entry (i.e. a[i] == nil) here,
-- as nil means something else to code which consumes the grid interface.
-- the "trans" (translator) function is responsible
-- for creating independent copies of array entries;
-- it is assumed that this function knows about the format of the array elements.
-- it is required to be independent as the consumers might want to mutate the data they get.
-- WARNING: LONG AF FUNCTION SIGNATURE INCOMING
local get_node_at_position = function(xb, yb, zb, xw, yw, zw, xi, yi, zi, array, trans)
	-- note that we assume the entry point checks that everything is an integer here.
	local xr, yr, zr =
		coordinates_inside_region(xb, yb, zb, xw, yw, zw, xi, yi, zi)
	--print(xr, yr, zr)
	if xr == nil then return oob end
	local i = flat_xyz_index(xr, yr, zr, xw, yw, zw)
	local data = array[i]
	--print(i)
	assert(data ~= nil, "get_node_at_position(): array index nil!? (check size and/or array population)")
	local copy = trans(array[i])
	assert(copy ~= nil)
	return copy
end



-- FIXME: minor DRY violation, copy+pasted, but too many chars to import
local checkint = function(n) return (n % 1.0) == 0 end

-- look up neighbour position:
-- as this is a simple 2D grid, all we have to do is do a vector add.
-- this grid doesn't support linking to other grids, so it must return self.
-- the inbound direction is unmodified and returned directly.
local mk_grid_neighbour_pos = function(selfgrid, xb, yb, zb, xw, yw, zw)
	return function(pos, off)
		local xi, yi, zi = pos.x, pos.y, pos.z
		assert(checkint(xi))
		assert(checkint(yi))
		assert(checkint(zi))

		local xo, yo, zo = off.x, off.y, off.z
		assert(checkint(xo))
		assert(checkint(yo))
		assert(checkint(zo))

		local xnew = xi + xo
		local ynew = yi + yo
		local znew = zi + zo

		-- check that resulting coordinates are inside the region,
		-- however we don't need to load anything with the resulting relpos.
		local xr, yr, zr =
			coordinates_inside_region(xb, yb, zb, xw, yw, zw, xnew, ynew, znew)
		if (xr == nil) then return oob end

		return {
			grid = selfgrid,
			pos = {
				x = xnew,
				y = ynew,
				z = znew,
			},
			direction = off,
		}
	end
end





--[[
Constructor. Options table:
+ translator: function which knows how to make independent copies of node data,
	including all possible levels of tables etc.
	this item has no default as an identity function
	(i.e. it returns the array index directly)
	would be potentially unsafe if the consumer decides to modify them.
+ srcarray: the backing array to use for node data
+ basepos: xyz table describing base position of region
	(coordinates must be integers)
+ size: xyz table describing the size of the region.
	note that Xbase + Xsize would be just outside the region,
	the last node inside the region on that axis is (Xbase + Xsize - 1).
	XYZ values must be integers > 0.
]]
local construct = function(opts)
	assert(type(opts) == "table")

	local trans = opts.translator
	assert(type(trans) == "function")

	local store = opts.srcarray
	assert(type(store) == "table")

	local b = opts.basepos
	local xb, yb, zb = b.x, b.y, b.z
	assert(checkint(xb))
	assert(checkint(yb))
	assert(checkint(zb))

	local s = opts.size
	local xw, yw, zw = s.x, s.y, s.z
	assert(checkint(xw))
	assert(checkint(yw))
	assert(checkint(zw))
	assert(xw > 0)
	assert(yw > 0)
	assert(zw > 0)

	local id = {}
	local selfgrid	-- the neighbour function needs to retain this
	local get = function(pos)
		local xi, yi, zi = pos.x, pos.y, pos.z
		assert(checkint(xi))
		assert(checkint(yi))
		assert(checkint(zi))
		--print(xi, yi, zi)
		return get_node_at_position(xb, yb, zb, xw, yw, zw, xi, yi, zi, store, trans)
	end
	selfgrid = {
		get = get,
		id = id,
	}
	selfgrid.neighbour =
		mk_grid_neighbour_pos(selfgrid, xb, yb, zb, xw, yw, zw)
	return selfgrid
end
return construct

