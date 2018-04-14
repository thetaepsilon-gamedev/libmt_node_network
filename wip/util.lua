-- internal warning function - currently prints to console.
local warn_console = function(msg)
	minetest.log("warning", msg)
end
_mod.util.warning = warn_console

-- formatter function for table data
local logformat = function(msg, data)
	if data ~= nil then
		for k, v in pairs(data) do
			msg = msg.." "..tostring(k).."="..tostring(v)
		end
	end
	return msg
end
_mod.util.logformat = logformat

-- get a warning function which additionally prints to a caller-passed printer.
local mkwarning = function(callername, extraprinter)
	return function(msg, data)
		local str = "["..callername.."] "..logformat(msg, data)
		warn_console(str)
		extraprinter(str)
	end
end
_mod.util.mkwarning = mkwarning
