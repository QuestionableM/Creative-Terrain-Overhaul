dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )

dofile("GameCommands.lua")

---@class GameClass
Game = class( nil )
Game.enableLimitedInventory = false
Game.enableFuelConsumption = false
Game.enableAmmoConsumption = false
Game.enableRestrictions = true
Game.enableUpgrade = true

CREATIVE_TERRAIN_OVERHAUL_VERSION = 2

function Game.server_onCreate( self )
	print("Game.server_onCreate")

	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		self.sv.saved.seed = math.random(os.time())
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "WorldVer2", {}, self.sv.saved.seed )

		self.sv.saved.time = 0.2
		self.sv.saved.time_progress = true

		self.sv.saved.version = 2

		self.storage:save( self.sv.saved )
	end

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate(nil, { aggroCreations = true })

	g_disableScrapHarvest = true

	--LoadCraftingRecipes
	self:g_loadCraftingRecipes()
end

function Game:g_loadCraftingRecipes()
	LoadCraftingRecipes({
		craftbot = "$SURVIVAL_DATA/CraftingRecipes/craftbot.json"
	})
end

function Game:cl_n_versionMismatch(id)
	self.cl_version_mismatch = id
	if self.cl_is_loaded then
		self:client_displayVersionMismatch()
	end
end

function Game:cl_n_newVersionAvailable()
	self.cl_new_version_available = true
	if self.cl_is_loaded then
		self:client_displayNewVersionAvailableMsg()
	end
end

local version_mismatch_code =
{
	client_outdated = 1,
	server_outdated = 2
}

local version_mismatch_messages =
{
	[version_mismatch_code.client_outdated] = {
		chat = "[#ffff00TerrainOverhaul#ffffff] #ffff00WARNING#ffffff: Your custom game version is outdated. Please update the custom game.",
		alert = "#ffff00WARNING#ffffff: Your custom game version is outdated.\nPlease update the custom game."
	},
	[version_mismatch_code.server_outdated] = {
		chat = "[#ffff00TerrainOverhaul#ffffff] #ffff00WARNING#ffffff: Server host has outdated version of custom game. Tell the host to update the custom game.",
		alert = "#ffff00WARNING#ffffff: Server host has outdated version of custom game.\nTell the host to update the custom game."
	}
}

function Game:client_displayVersionMismatch()
	local msg_data = version_mismatch_messages[self.cl_version_mismatch]

	sm.gui.chatMessage(msg_data.chat)
	sm.gui.displayAlertText(msg_data.alert, 10)
end

function Game:client_displayNewVersionAvailableMsg()
	sm.gui.chatMessage("[#ffff00TerrainOverhaul#ffffff] New version of terrain generation is available! You can try the newest version by creating a new world.")
end

function Game:sv_n_checkVersion(version, caller)
	if version ~= CREATIVE_TERRAIN_OVERHAUL_VERSION then
		if version < CREATIVE_TERRAIN_OVERHAUL_VERSION then
			self.network:sendToClient(caller, "cl_n_versionMismatch", version_mismatch_code.client_outdated)
		elseif version > CREATIVE_TERRAIN_OVERHAUL_VERSION then
			self.network:sendToClient(caller, "cl_n_versionMismatch", version_mismatch_code.server_outdated)
		end

		return
	end

	if self.sv.saved.version < CREATIVE_TERRAIN_OVERHAUL_VERSION then
		self.network:sendToClient(caller, "cl_n_newVersionAvailable")
	end
end

function Game:client_onLoadingScreenLifted()
	self.cl_is_loaded = true

	if self.cl_version_mismatch ~= nil then
		self:client_displayVersionMismatch()
	end

	if self.cl_new_version_available ~= nil then
		self:client_displayNewVersionAvailableMsg()
	end
end

function Game:client_onCreate()
	if not sm.isHost then
		self:g_loadCraftingRecipes()
	end

	gc_cl_bindChatCommands()

	self.network:sendToServer("sv_n_requestTime")
	self.network:sendToServer("sv_n_checkVersion", CREATIVE_TERRAIN_OVERHAUL_VERSION)

	self.cl_time_progress = true
	self.cl_time = 0.3

	if g_beaconManager == nil then
		g_beaconManager = BeaconManager()
	end

	if g_unitManager == nil then
		g_unitManager = UnitManager()
	end

	g_beaconManager:cl_onCreate()
	g_unitManager:cl_onCreate()
end

local GAME_DAYCYCLE_TIME = 900.0

function Game:client_onUpdate(dt)
	if self.cl_time_progress then
		self.cl_time = math.fmod(self.cl_time + dt / GAME_DAYCYCLE_TIME, 1.0) 
	end

	sm.render.setOutdoorLighting(self.cl_time)
	sm.game.setTimeOfDay(self.cl_time)
end

function Game:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_receiveTime", { self.sv.saved.time, self.sv.saved.time_progress })
	self.storage:save(self.sv.saved)
end

function Game:server_onFixedUpdate(dt)
	if self.sv.saved.time_progress then
		self.sv.saved.time = math.fmod(self.sv.saved.time + dt / GAME_DAYCYCLE_TIME, 1.0) 
	end

	if (sm.game.getCurrentTick() % 401) == 0 then
		self:server_saveAndSyncTime()
	end

	g_unitManager:sv_onFixedUpdate()
end

function Game:sv_n_requestTime(data, caller)
	self.network:sendToClient(caller, "cl_n_receiveTime", { self.sv.saved.time, self.sv.saved.time_progress })
end

function Game:cl_n_receiveTime(time_data)
	self.cl_time = time_data[1]
	self.cl_time_progress = time_data[2]
end

function Game:cl_onChatCommand(params)
	gc_cl_handleCommands(self, params)
end

function Game:server_teleportToPlayer(player, caller)
	local pl_char = player.character
	if pl_char and sm.exists(pl_char) then
		local new_char = sm.character.createCharacter(caller, pl_char:getWorld(), pl_char.worldPosition, 0, 0)
		caller:setCharacter(new_char)
	end
end

function Game:server_respawnPlayer(data, caller)
	self.sv.saved.world:loadCell(0, 0, caller, "sv_createPlayerCharacter")
end

function Game:server_clearWorld(data, caller)
	local pl_char = caller.character
	if pl_char and sm.exists(pl_char) then
		sm.event.sendToWorld(pl_char:getWorld(), "sv_n_clearWorld")
	end
end

function Game:server_onPlayerJoined(player, isNewPlayer)
	if isNewPlayer then
		if not sm.exists( self.sv.saved.world ) then
			sm.world.loadWorld( self.sv.saved.world )
		end

		self.sv.saved.world:loadCell( 0, 0, player, "sv_createPlayerCharacter" )
	end

	g_unitManager:sv_onPlayerJoined(player)
end

function Game.sv_createPlayerCharacter( self, world, x, y, player, params )
	local params = { player = player, x = x, y = y }
	sm.event.sendToWorld(world, "server_spawnNewCharacter", params)
end

function Game:sv_e_onSpawnPlayerCharacter(player)
	print("Game:sv_e_onSpawnPlayerCharacter")
	local pl_char = player.character
	if pl_char and sm.exists(pl_char) then
		g_beaconManager:sv_onSpawnCharacter(player)
	end
end

--Beacons
function Game:sv_e_createBeacon(params)
	if sm.exists(params.beacon.world) then
		sm.event.sendToWorld(params.beacon.world, "sv_e_createBeacon", params)
	else
		sm.log.warning("Game:sv_e_createBeacon in a world that doesn't exist")
	end
end

function Game:sv_e_destroyBeacon(params)
	if sm.exists(params.beacon.world) then
		sm.event.sendToWorld(params.beacon.world, "sv_e_destroyBeacon", params)
	else
		sm.log.warning("Game:sv_e_destroyBeacon in a world that doesn't exist")
	end
end

function Game:sv_e_unloadBeacon(params)
	if sm.exists(params.beacon.world) then
		sm.event.sendToWorld(params.beacon.world, "sv_e_unloadBeacon", params)
	else
		sm.log.warning("Game:sv_e_unloadBeacon in a world that doesn't exist")
	end
end

--CommandCallbacks
function Game:cl_n_onTimeProgressChange(new_state)
	sm.gui.chatMessage("Time Progress Changed to "..cf_boolToString[new_state])
end

function Game:sv_n_setTimeProgress(new_progress)
	if new_progress then
		self.sv.saved.time_progress = new_progress
	else
		self.sv.saved.time_progress = not self.sv.saved.time_progress
	end

	self:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_onTimeProgressChange", self.sv.saved.time_progress)
end

function Game:cl_n_onTimeChangeMsg(new_time)
	sm.gui.chatMessage(("Time set to #ffff00%.3f#ffffff"):format(new_time))
end

function Game:sv_n_setTime(new_time)
	self.sv.saved.time = new_time

	self:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_onTimeChangeMsg", new_time)
end

function Game:cl_n_setAggroMessage(aggro)
	sm.gui.chatMessage("AGGRO: "..(aggro and "On" or "Off"))
end

function Game:sv_n_setAggro(params)
	local aggro = not sm.game.getEnableAggro()
	if type(params) == "boolean" then
		aggro = not params
	end

	sm.game.setEnableAggro(aggro)
	self.network:sendToClients("cl_n_setAggroMessage", aggro)
end

function Game:cl_n_setAggroCreationsMsg(aggro_creations)
	sm.gui.chatMessage("AGGRO CREATIONS: "..(aggro_creations and "On" or "Off"))
end

function Game:sv_n_setAggroCreations(params)
	local aggroCreations = not g_unitManager:sv_getHostSettings().aggroCreations
	if type(params) == "boolean" then
		aggroCreations = not params
	end

	g_unitManager:sv_setHostSettings({ aggroCreations = aggroCreations })
	self.network:sendToClients("cl_n_setAggroCreationsMsg")
end

function Game:sv_n_popCapsules(params)
	g_unitManager:sv_openCapsules(params)
end

function Game:sv_n_aggroAllUnits(params, caller)
	local pl_char = caller.character
	if pl_char and sm.exists(pl_char) then
		sm.event.sendToWorld(pl_char:getWorld(), "sv_e_aggroAll", caller)
	end
end

function Game:sv_n_killAllUnits(params, caller)
	local pl_char = caller.character
	if pl_char and sm.exists(pl_char) then
		sm.event.sendToWorld(pl_char:getWorld(), "sv_e_killAll")
	end
end

function Game:cl_n_toggleDropScrapMsg(drop_scrap)
	sm.gui.chatMessage("SCRAP LOOT: "..(drop_scrap and "Off" or "On"))
end

function Game:sv_n_toggleDropScrap(params)
	local disableScrapHarvest = not g_disableScrapHarvest
	if type(params) == "boolean" then
		disableScrapHarvest = not params
	end

	g_disableScrapHarvest = disableScrapHarvest
	self.network:sendToClients("cl_n_toggleDropScrapMsg", disableScrapHarvest)
end

function Game:cl_n_toggleFlyMsg(is_swimming)
	sm.gui.chatMessage("Fly: "..(is_swimming and "On" or "Off"))
end

---@param params table Params.
---@param caller Player Caller.
function Game:sv_n_toggleFlyMode(params, caller)
	local pl_char = caller.character
	if pl_char and sm.exists(pl_char) then
		local is_swimming = not pl_char:isSwimming()

		pl_char:setSwimming(is_swimming)
		pl_char:setDiving(is_swimming)
		
		--[[local movement_speed = params and params[1] or 1
		if movement_speed < 1 then
			movement_speed = 1
		end

		pl_char:setMovementSpeedFraction(movement_speed)]]

		self.network:sendToClient(caller, "cl_n_toggleFlyMsg", is_swimming)
	end
end

---@param caller Player Caller.
function Game:sv_n_placeHarvestable(params, caller)
	local pl_char = caller.character
	if pl_char and sm.exists(pl_char) then
		sm.event.sendToWorld(pl_char:getWorld(), "sv_e_placeHvs", params)
	end
end

local available_world_classes =
{
	[1] = "World",
	[2] = "WorldVer2"
}

function Game:sv_n_regenerateWorld(data)
	local generator_version = CREATIVE_TERRAIN_OVERHAUL_VERSION
	local generator_seed = math.random(os.time())

	local gen_ver = data[1]
	if type(gen_ver) == "number" then
		local tmp_ver = gen_ver
		if tmp_ver < 1 or tmp_ver > CREATIVE_TERRAIN_OVERHAUL_VERSION then
			tmp_ver = CREATIVE_TERRAIN_OVERHAUL_VERSION
		end

		generator_version = tmp_ver
	end

	local gen_seed = data[2]
	if type(gen_seed) == "number" then
		generator_seed = gen_seed
	end

	--Destroy the old world
	local old_world = self.sv.saved.world
	if old_world and sm.exists(old_world) then
		old_world:destroy()
	end
	
	--Change and save the world settings
	local world_class = available_world_classes[generator_version]
	self.sv.saved.seed = generator_seed
	self.sv.saved.world = sm.world.createWorld("$CONTENT_DATA/Scripts/World.lua", world_class, {}, generator_seed)
	self.sv.saved.version = generator_version
	self.storage:save(self.sv.saved)

	local player_list = sm.player.getAllPlayers()
	for k, cur_pl in pairs(player_list) do
		self:server_onPlayerJoined(cur_pl, true)
	end
end

function Game:cl_n_displaySeedData(data)
	local terrain_ver  = data[1]
	local terrain_seed = data[2]

	local seed_string = "Couldn't get the seed (old save version)"
	if type(terrain_seed) == "number" then
		seed_string = tostring(terrain_seed)
	end

	sm.gui.chatMessage(("[#ffff00TerrainOverhaul#ffffff] Terrain Data:\nSeed: #ffff00%s#ffffff\nVersion: #ffff00%s#ffffff"):format(seed_string, terrain_ver))
end

--Seed doesn't exist in older save versions
function Game:sv_n_getTerrainSeed(data, caller)
	local sv_saved = self.sv.saved
	local terrain_data = { sv_saved.version, sv_saved.seed }

	self.network:sendToClient(caller, "cl_n_displaySeedData", terrain_data)
end

--Confirm Dialog Callbacks
function Game:cl_diag_onButtonCallback(button)
	if button == "Yes" then
		self.tmp_diag_yes_callback(self)
	end

	self.tmp_confirmDiag:close()
end

function Game:cl_diag_onCloseCallback()
	self.tmp_confirmDiag:destroy()
	self.tmp_diag_yes_callback = nil
end