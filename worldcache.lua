-- caching system to postpone node overwrites until the end of an operation,
-- and to alleviate multiple read accesses of the same node.
-- the rationale for this is that the vertex space code makes a deep assumption that the graph is not changed until it is finished.
-- changing a node from callbacks counts as violating this rule.
-- instead, this object allows writes to be postponed until completion, then written out all at once.
return {
	
}
