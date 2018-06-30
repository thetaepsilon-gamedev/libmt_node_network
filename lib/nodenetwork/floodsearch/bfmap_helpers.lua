--[[
The bfmap module (see bfmap.lua)
does allow the set-up of a lot of parameters controlling it's behaviour.
This is to the point that client code may not always wish to have to handle this.
This calls for a factory function; set some defaults,
then request a new instance of a preset search from a single function,
while allowing for keeping setup and usage code separate.

This file contains such factory constructors,
as well as various generic utilities for working with bfmap callbacks.
]]

local m_bfmap =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.floodsearch.bfmap")
local newsearch = m_bfmap.new

local i = {}



-- creates a visitor callback that collects found vertices into a hashed set,
-- using the usual convention of using the vertices themselves as values
-- and the respective hashes as keys.
-- returns the visitor and the collection table.
local mk_set_visitor = function(opts)
	local gathered = {}
	local visitor = function(vertex, hash)
		-- usually, bfmap guarantees that duplicate visits cannot happen,
		-- just sanity check so we don't overwrite keys silently from bugs
		assert(gathered[hash] == nil, "WTF condition: duplicate visitation!?")
		gathered[hash] = vertex
	end
	return visitor, gathered
end
i.mk_set_visitor = mk_set_visitor

-- wrapper for the above function when we only care about visitation
-- (and not any of the other callbacks, like testvertex etc.).
-- expects a function taking option values and returning a visitor function and extra data
-- (e.g. in the above case the gathered set table that it populates).
local mk_visitor_callback_wrapper__ = function(visitor_f_)
	assert(type(visitor_f_) == "function")
	return function(opts)
		return function()
			local visitor, extradata = visitor_f_(opts)
			return { visitor = visitor }, extradata
		end
	end
end
i.mk_visitor_callback_wrapper__ = mk_visitor_callback_wrapper__






-- next, the bfmap search factory.
-- generally speaking, we have three sets of things we'd want to customise:
-- * the passed succcessor (which may require separate instances).
-- * misc options table, for e.g. limiting search depth.
-- * the callback table.
-- The successor and callbacks are significant,
-- because we may want to create extra tables or such that they write to,
-- or in general want an extra handle to so they can be communicated with.
-- (e.g. see the gathering visitor above)
local search_factory__ = function(callback_f_)
	assert(type(callback_f_) == "function")

	-- currying, currying everwhere
	return function(opts)
		local factory = function(initialv, initialhash, successor)
			local callbacks, extradata = callback_f_()
			local search = newsearch(
				initialv,
				initialhash,
				successor,
				callbacks,
				opts)
			return search, extradata
		end
		return factory
	end
end
i.search_factory__ = search_factory__

-- similarly, sometimes we need to extract additional data from the successor function.
-- a good example of this is in the graphtracker code,
-- where remote groups are not considered successors but they are noted for later.
-- furthermore, some successor setup functions return an associated hasher
-- (e.g. see voxelgraph.searchimpl) that should be used to get initial hashes.
-- kill two birds with one stone here,
-- resulting in a function that can create a search just from a single vertex.
-- the resulting factory will produce the search object when called with a vertex,
-- as well as an extradata table containing the following:
--[[
extradata = {
	base = ...,	-- returned from base_factory
	successor = ....,	-- returned from successor_factory
}
]]
local search_factory_prehash_ = function(base_factory, successor_factory)
	assert(type(base_factory) == "function")
	assert(type(successor_factory) == "function")

	return function(initialv)
		local successor, hasher, sextra = successor_factory()
		local initialhash = hasher(initialv)
		local search, bextra = base_factory(initialv, initialhash, successor)
		return search, {
			base = bextra,
			successor = sextra,
		}
	end
end
i.search_factory_prehash_ = search_factory_prehash_





return i

