-- A "network space", also read as "the space of all networks" or "the set of all networks".
-- The code below creates a handle to interact with networks of a given kind.
-- "kind" here is just an abstract label, and implicit in the handle -
-- you just request one from a mod,
-- then use that handle from whatever callbacks which should participate in that kind of network.
-- e.g. if mesecons used this, it would obtain a network space,
-- then all mesecons-related nodes would interact with the "mesecons network space".

-- it is perfectly possible for a node to belong to more than one network space.
-- they all effectively "overlap" in the world's area,
-- but not every node participates in a given network space.
-- or it can participate in multiple;
-- the same way certain technic nodes respond to mesecons and/or digilines events.

local modulefactory = function(deps)
	local logger = deps.logger

	local interface = {
		register = function(name)
			logger("networkspace.register.stub", {name=name})
		end
	}
	return interface
end

return modulefactory
