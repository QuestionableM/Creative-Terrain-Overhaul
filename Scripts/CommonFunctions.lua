cf_boolToString =
{
	[true] = "#00ff00true#ffffff",
	[false] = "#ff0000false#ffffff"
}

cf_errorChatMessage = function(msg)
	sm.gui.chatMessage("#ff0000ERROR#ffffff: "..msg)
end