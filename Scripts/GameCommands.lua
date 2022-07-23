dofile("CommonFunctions.lua")

local function gc_clear_command_func(self, params)
	self.network:sendToServer("server_clearWorld")
end

local function gc_spawn_character_func(self, params)
	self.network:sendToServer("server_respawnPlayer")
end

local function gc_teleport_character_func(self, params)
	local player_id = params[1]
	local all_players = sm.player.getAllPlayers()
	local selected_pl = all_players[player_id]

	if selected_pl == nil then
		cf_errorChatMessage("Invalid character id")
		return
	end

	if selected_pl == sm.localPlayer.getPlayer() then
		cf_errorChatMessage("You can't teleport to yourself")
		return
	end

	local pl_char = selected_pl.character
	if not (pl_char and sm.exists(pl_char)) then
		cf_errorChatMessage("The specified player does not have a character.")
		return
	end

	self.network:sendToServer("server_teleportToPlayer", selected_pl)
end

local function gc_display_player_list(self, params)
	sm.gui.chatMessage("List of Players:")
	for k, v in pairs(sm.player.getAllPlayers()) do
		sm.gui.chatMessage(("Id: #ffff00%i#ffffff, Name: #ffff00%s#ffffff"):format(k, v.name))
	end
end

local function  gc_set_time(self, params)
	local new_time = params[1]
	if new_time > 1.0 or new_time < 0.0 then
		cf_errorChatMessage("Time value should be between 0 and 1")
		return
	end

	self.network:sendToServer("sv_n_setTime", new_time)
end

local function gc_set_time_progress(self, params)
	self.network:sendToServer("sv_n_setTimeProgress", params[1])
end

local gc_command_list =
{
	["/clear"] = {
		desc = "Removes all the loaded shapes in the world.",
		func = gc_clear_command_func
	},
	["/spawn"] = {
		desc = "Spawns your character at the spawn location.",
		func = gc_spawn_character_func
	},
	["/tp"] = {
		desc = "Teleports your character to other players.",
		args = { { "int", "player id", false } },
		func = gc_teleport_character_func
	},
	["/playerlist"] = {
		desc = "Displays the list of players in the world.",
		func = gc_display_player_list
	},
	["/timeset"] = {
		desc = "Sets the time for all the players (range: 0 to 1)",
		args = { { "number", "time", false } },
		func = gc_set_time
	},
	["/timeprogress"] = {
		desc = "Determines whether the time should progress or not.",
		args = { { "bool", "should progress", true } },
		func = gc_set_time_progress
	}
}

function gc_cl_bindChatCommands()
	for com_name, data in pairs(gc_command_list) do
		sm.game.bindChatCommand(com_name, data.args or {}, "cl_onChatCommand", data.desc)
	end
end

function gc_cl_handleCommands(self, params)
	local com_name = params[1]
	local cur_com = gc_command_list[com_name]
	if cur_com ~= nil then
		--Remove the command name itself from arg list
		table.remove(params, 1)

		cur_com.func(self, params)
	else
		sm.gui.chatMessage(("#ff0000ERROR#ffffff: Command \"#ffff00%s#ffffff\" doesn't exist!"):format(com_name))
	end
end