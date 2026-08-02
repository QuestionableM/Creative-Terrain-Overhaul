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

local function gc_vanilla_set_no_aggro(self, params)
	self.network:sendToServer("sv_n_setAggro", params[1])
end

local function gc_vanilla_set_no_aggro_creations(self, params)
	self.network:sendToServer("sv_n_setAggroCreations", params[1])
end

local function gc_vanilla_pop_capsules(self, params)
	self.network:sendToServer("sv_n_popCapsules", params[1])
end

local function gc_vanilla_aggro_all_units(self, params)
	self.network:sendToServer("sv_n_aggroAllUnits")
end

local function gc_vanilla_kill_all_units(self, params)
	self.network:sendToServer("sv_n_killAllUnits")
end

local function gc_vanilla_toggle_drop_scrap(self, params)
	self.network:sendToServer("sv_n_toggleDropScrap", params[1])
end

local function gc_set_character_fly(self, params)
	self.network:sendToServer("sv_n_toggleFlyMode", params[1])
end

local function gc_vanilla_place_harvestable(self, params)
	local param_data = { [1] = params[1] }

	local range = 7.5
	local success, result = sm.localPlayer.getRaycast(range)
	if success then
		param_data[2] = result.pointWorld
	else
		param_data[2] = sm.localPlayer.getRaycastStart() + sm.localPlayer.getDirection() * range
	end

	self.network:sendToServer("sv_n_placeHarvestable", param_data)
end

local WeatherConditionToId = {
	["rain"] = 1,
	["thunder"] = 2,
	["clear"] = 3,
	["cloudy"] = 4,
	["drizzle"] = 5
}

local IdToWeatherCondition = {
	[1] = { event = "Rain"       , displayName = "Rain"    },
	[2] = { event = "ThunderRain", displayName = "Thunder" },
	[3] = { event = "Clear"      , displayName = "Clear"   },
	[4] = { event = "Clouds01"   , displayName = "Cloudy"  },
	[5] = { event = "Drizzle"    , displayName = "Drizzle" }
}

function GetWeatherConditionFromId(id)
	return IdToWeatherCondition[id]
end

local function gc_vanilla_set_weather(self, params)
	local condition = WeatherConditionToId[string.lower(params[1])]
	if condition ~= nil then
		self.network:sendToServer("sv_n_setWeather", condition)
	end
end

local function gc_create_yesno_dialog(self, title, message, yesCallback)
	local confirmDiag = sm.gui.createGuiFromLayout("$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout")
	confirmDiag:setButtonCallback("Yes", "cl_diag_onButtonCallback")
	confirmDiag:setButtonCallback("No", "cl_diag_onButtonCallback")
	confirmDiag:setOnCloseCallback("cl_diag_onCloseCallback")
	confirmDiag:setText("Title", title)
	confirmDiag:setText("Message", message)
	confirmDiag:open()

	self.tmp_confirmDiag = confirmDiag
	self.tmp_diag_yes_callback = yesCallback
end

local function gc_regenerate_world(self, params)
	local version_param = params[1]
	if version_param ~= nil then
		if version_param < 0 then
			cf_errorChatMessage("Invalid version value: minimum = #ffff000#ffffff")
			return
		end
	
		if version_param > CREATIVE_TERRAIN_OVERHAUL_VERSION then
			cf_errorChatMessage("Invalid version value: maximum = #ffff00"..CREATIVE_TERRAIN_OVERHAUL_VERSION.."#ffffff")
			return
		end
	end

	gc_create_yesno_dialog(
		self,
		"Regenerate World",
		"#888888Are you sure that you want to regenerate the world? #ffff00All#888888 unsaved creations will be lost!",
		function (self)
			self.network:sendToServer("sv_n_regenerateWorld", params)
		end
	)
end

local function gc_get_world_seed(self, params)
	self.network:sendToServer("sv_n_getTerrainSeed")
end

local function gc_import_creation(self, params)
	local valid, result = sm.localPlayer.getRaycast(100)
	if valid then
		local pl_char = sm.localPlayer.getPlayer():getCharacter()
		if pl_char and sm.exists(pl_char) then
			local import_params = {
				[1] = pl_char:getWorld(),
				[2] = params[1],
				[3] = result.pointWorld
			}

			self.network:sendToServer("sv_n_importCreation", import_params)
		end
	else
		sm.gui.chatMessage("#ffff00Hint#ffffff: Aim at the ground. (raycast radius: #ffff00100#ffffff meters).")
	end
end

local function gc_export_creation(self, params)
	local valid, result = sm.localPlayer.getRaycast(100)
	if valid and result.type == "body" then
		local export_params = {
			[1] = params[1],
			[2] = result:getBody()
		}

		self.network:sendToServer("sv_n_exportCreation", export_params)
	else
		sm.gui.chatMessage("#ffff00Hint#ffffff: Aim on a creation to export it!")
	end
end

local function gc_enable_character_health(self, params)
	self.network:sendToServer("sv_n_toggleCharHealth", params[1])
end

local function gc_kill_own_character(self, params)
	self.network:sendToServer("sv_n_killCharacter")
end

local function gc_set_spawnpoint(self, params)
	self.network:sendToServer("sv_n_setSpawnpoint")
end

local function gc_damage_character(self, params)
	self.network:sendToServer("sv_n_damageCharacter", params[1])
end

local function gc_enable_healing(self, params)
	self.network:sendToServer("sv_n_toggleHealing", params[1])
end

local function gc_ragdoll_character(self, params)
	self.network:sendToServer("sv_n_ragdollCharacter")
end

local function gc_vanilla_kickban_generic(self, isBanMode, playerId)
	local actionName = isBanMode and "Ban" or "Kick"
	local callbackName = isBanMode and "sv_n_banPlayer" or "sv_n_kickPlayer"

	if sm.player.getHostPlayer().id == playerId then
		sm.gui.chatMessage(("#ff0000ERROR#ffffff: You cannot %s yourself"):format(string.lower(actionName)))
		return
	end

	for _, v in pairs(sm.player.getAllPlayers()) do
		if v.id == playerId then
			gc_create_yesno_dialog(
				self,
				("%s player"):format(actionName),
				("#888888Are you sure you want to %s #ffff00%s#888888?"):format(string.lower(actionName), v.name),
				function (self)
					self.network:sendToServer(callbackName, playerId)
				end
			)
			return
		end
	end

	sm.gui.chatMessage("#ff0000ERROR#ffffff: The specified player could not be found")
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
	},
	["/fly"] = {
		desc = "Makes your character fly in the air",
		--args = { { "int", "fly speed", true } },
		func = gc_set_character_fly
	},
	["/regenerate"] = {
		desc = "Regenerates the world. Has 1 optional argument (generator version): 1, 2",
		args = { { "int", "version (auto = 0)", true }, { "int", "seed (optional)", true } },
		func = gc_regenerate_world,
		host_only = true
	},
	["/seed"] = {
		desc = "Gets the seed of and the version of the current terrain generation.",
		func = gc_get_world_seed
	},

	["/import"] = {
		desc = "Imports a creation from survival files and custom game files.",
		func = gc_import_creation,
		args = { { "string", "creation_name", false } },
		host_only = true
	},
	["/export"] = {
		desc = "Exports the creation you're currently looking at.",
		func = gc_export_creation,
		args = { { "string", "creation_name", false } },
		host_only = true
	},
	["/enablehealth"] = {
		desc = "Enables health for your character.",
		func = gc_enable_character_health,
		args = { { "bool", "enable", true } }
	},
	["/die"] = {
		desc = "Kills the character.",
		func = gc_kill_own_character
	},
	["/spawnpoint"] = {
		desc = "Sets the spawn point for your character",
		func = gc_set_spawnpoint
	},
	["/damage"] = {
		desc = "Damages the player",
		args = { { "int", "damage", false } },
		func = gc_damage_character
	},
	["/enablehealing"] = {
		desc = "Toggles healing for all the players. (Host only)",
		args = { { "bool", "enable", true } },
		func = gc_enable_healing,
		host_only = true
	},
	["/ragdoll"] = {
		desc = "Puts your character in ragdoll state.",
		func = gc_ragdoll_character
	},

	--Vanilla Commands
	["/noaggro"] = {
		desc = "Toggles the player as a target",
		args = { { "bool", "enable", true } },
		func = gc_vanilla_set_no_aggro
	},
	["/noaggrocreations"] = {
		desc = "Toggles whether the Tapebots will shoot at creations",
		args = { { "bool", "enable", true } },
		func = gc_vanilla_set_no_aggro_creations
	},
	["/popcapsules"] = {
		desc = "Opens all capsules. An optional filter controls which type of capsules to open: 'bot', 'animal'",
		args = { { "string", "filter", true } },
		func = gc_vanilla_pop_capsules
	},
	["/aggroall"] = {
		desc = "All hostile units will be made aware of the player's position",
		func = gc_vanilla_aggro_all_units
	},
	["/killall"] = {
		desc = "Kills all spawned units",
		func = gc_vanilla_kill_all_units
	},
	["/dropscrap"] = {
		desc = "Toggles the scrap loot from Haybots",
		args = { { "bool", "enable", true } },
		func = gc_vanilla_toggle_drop_scrap
	},
	["/place"] = {
		desc = "Places a harvestable at the aimed position. Must be placed on the ground. The harvestable parameter controls which harvestable to place: 'stone', 'tree', 'birch', 'leafy', 'spruce', 'pine'",
		args = { { "string", "harvestable", false } },
		func = gc_vanilla_place_harvestable
	},
	["/weather"] = {
		desc = "Sets the weather condition",
		args = { { "string", "condition", false, { "rain", "thunder", "clear", "cloudy", "drizzle" } } },
		func = gc_vanilla_set_weather
	},

	["/kick"] = {
		desc = "Kick a player from server",
		args = { { "int", "player id", false } },
		func = function (self, params) gc_vanilla_kickban_generic(self, false, params[1]) end,
		host_only = true
	},
	["/ban"] = {
		desc = "Ban a player from server",
		args = { { "int", "player id", false } },
		func = function (self, params) gc_vanilla_kickban_generic(self, true, params[1]) end,
		host_only = true
	}
}

function gc_cl_bindChatCommands()
	local is_host = sm.isHost

	for com_name, data in pairs(gc_command_list) do
		local host_only = data.host_only
		if not host_only or (is_host and host_only) then
			sm.game.bindChatCommand(com_name, data.args or {}, "cl_onChatCommand", data.desc)
		end
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