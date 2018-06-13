--[[
This file serves both as documentation of the linked grid interface
(described below) and as a place to put some constants that grid implementations may use.

The rationale for the linked grid abstraction is as follows:
The intent here is to be as general as possible,
and not lock out tricks that break under the assumption of a singleton euclidian grid.
Singletons are bad enough practice as-is,
and if e.g. VAEs or other "dimensions" to the MT world get added at some point in the future,
most code using the singletone get/set_node api will fail to work with this.
Additionally, the chosen grid object(s) can correlate extra data with world positions if desired
(e.g. temperature, humitidy etc.), relieving the query functions of this burden.
]]



local i = {}
i.constants = {}
-- various constants useful for grid implementations.
local sentinel =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.datastructs.sentinel")
-- sentinel value indicating out-of-bounds for a grid.
local out_of_bounds = sentinel.mk("libmt_node_network.grid.out_of_bounds")
i.constants.out_of_bounds = function() return out_of_bounds end




--[[
-- READ THIS FIRST:
-- these functions are *not* members, but closures.
--	they would be called by grid.get(), not grid:get().
--	in other words, they are expected to maintain their "self" values using upvalues.
-- @INTERFACE linkedgrid
grid = {
	get = function(pos),
		-- where pos is the regular XYZ vector.
		-- returns a table, but no constraints are placed on it's contents;
		-- grids and query functions used together must pre-arrange needed data.
		-- it may assume that pos contains integer coordinates.
		-- please note: if providing a minetest metadata ref,
		-- *accessors are allowed to assume it can't change*.
		-- in other words, make it read only!
		-- may return SENTINEL linkedgrid.constants.out_of_bounds,
		--	if the given position is beyond the world/grid boundary.
	neighbour = function(pos, offset),
		-- offset is an MT XYZ offset vector from pos.
		-- must return the following:
		-- * table of { grid=..., pos=..., direction=... }
		--	The grid may be a different one from the original,
		--	to allow jumps across connected grids.
		--	Likewise, pos does not have to be euclidian pos + offset.
		--	Direction may also change,
		--	it must be the new direction going into the target node.
		-- Returning SENTINEL linkedgrid.constants.out_of_bounds
		-- is again allowed if the offset falls off the edge of the world.
	id = {},
		-- a unique, empty table
		-- (either a literal {} in source code or a sentinel)
		-- which serves to uniquely identify a grid.
		-- this object is used to determine the hash of a grid/position pair
		-- (and therefore if a given vertex has already been visited).
}
]]

return i

