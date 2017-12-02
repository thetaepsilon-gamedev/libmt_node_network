-- See also the comments in networkspace_register.lua.
--[[
In order for a network space to be useful, it needs to know some things.
When a network is first built (more on that later),
spreading out from the initial position, potential neighbour nodes are examined.
The network space's owner should register the following for each node that is to participate in the network:

* A "neighbour function":
Related to the concept of "successors" in the search algorithm,
this function is provided with private data (set at registration time),
and the node's data and metadata.
It is expected to return a list of neighbour offsets.

* A "direction function":
For each neighbour returned per above,
each of *those* nodes are in turn examined and their direction functions are invoked.
Again, it is provided private data and information about the node,
and a direction vector (from the neighbour back to the initating node).
If that node should be allowed to connect in that direction,
the direction function should return true.
For example, a node that can only connect to a network on the bottom could use the following:
local directionfn = function(direction, node, meta)
	return vector.equals(direction, {x=0, y=-1, z=0})
end

Both the above functions are looked up by node name,
however the node and meta fields in the callback allow more fine grained control.
If a node is pointed to by the neighbour function's offsets,
*and* the pointed-to node's direction function agrees that it can connect back in that direction,
then the neighbour node is added to the search.

It is assumed that the neighbourfn and directionfn are consistent with each other;
that is, a given node's potential neighbours should be the same as the nodes it would allow connecting from in directionfn.
e.g. a node whose neighbour function returns {{x=0,y=1,z=0}, {x=0,y=-1,z=0}}
should have a directionfn which answers true if either of those are passed in.
The only reason they are separate is to avoid having to search through the entire neighbour set all the time.
As the order of the search algorithm is not guaranteed,
not observing this restriction will likely cause the network search to do strange things.

Look out for the helpers below for common types of "directionality",
such as "simple" nodes which can connect in all directions.
These helpers will take care of creating the necessary functions.
]]
