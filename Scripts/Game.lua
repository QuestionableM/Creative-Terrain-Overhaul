dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )

dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )

dofile("GameCommands.lua")

---@class TerrainOverhaulGame : GameClass
---@field sv table
---@field tmp_confirmDiag GuiInterface
Game = class( nil )
Game.enableLimitedInventory = false
Game.enableFuelConsumption = false
Game.enableAmmoConsumption = false
Game.enableRestrictions = true
Game.enableUpgrade = true

CREATIVE_TERRAIN_OVERHAUL_VERSION = 3

function Game.server_onCreate( self )
	self.sv = {}
	self.sv.weatherManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "46e23051-c20b-4929-9df1-7f4f838a3802" ), { permanentForecast = "CloudyDay", resetForecast = true } )

	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		self.sv.saved.seed = math.random(os.time())
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "WorldVer3", {}, self.sv.saved.seed )

		self.sv.saved.time = 0.2
		self.sv.saved.time_progress = true
		self.sv.saved.enable_healing = true

		self.sv.saved.version = 3

		self.storage:save(self.sv.saved)
	else
		if self.sv.saved.enable_healing == nil then self.sv.saved.enable_healing = true end

		self.storage:save(self.sv.saved)
	end

	g_enableCharacterHealing = self.sv.saved.enable_healing
	g_disableScrapHarvest = true

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate(nil, { aggroCreations = true })

	WorldManager.Sv_OnCreate()

	self:loadCraftingRecipes()
end

function Game:loadCraftingRecipes()
	local recipeSets = sm.json.open( "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json" )
	recipeSets.workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json"
	recipeSets.portablecrafter = "$SURVIVAL_DATA/CraftingRecipes/portablecrafter.json"
	recipeSets.dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json"
	recipeSets.cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json"
	recipeSets.dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	recipeSets.mininghubDispenser = "$SURVIVAL_DATA/CraftingRecipes/mininghubDispenser.json"
	recipeSets.sawtable = "$SURVIVAL_DATA/CraftingRecipes/sawtable.json"
	LoadCraftingRecipes( recipeSets )
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

--[[function Game:client_onRefresh()
	local ground_asset_list =
	{
		{ sm.uuid.new("4bd88efa-949c-4c0b-8517-2f2b1b2bdb01"), { 0xb0a926ff, 0xf1ac28ff, 0xcd7d00ff }, 7, { leaves = 0 } }, --env_foliage_smallbirch01
		{ sm.uuid.new("f741ad80-c99a-4cec-b67d-e53ec82a7bd0"), { 0xb0a926ff, 0xf1ac28ff, 0xcd7d00ff }, 7, { leaves = 0 } }, --env_foliage_smallbirch02
		{ sm.uuid.new("09a5a0ee-0fd1-4b32-86c0-9e6f2b701546"), { 0xd8bc21ff, 0xd83f21ff }, 8, { leaves = 0 } }, --env_nature_foliage_wildbush01
		{ sm.uuid.new("b1e1b1bf-6175-465e-81c6-9ec9d0bf83d0"), { 0xd8bc21ff, 0xd83f21ff }, 8, { leaves = 0 } }, --env_nature_foliage_wildbush02
		{ sm.uuid.new("796cabcd-5703-42af-b4e9-512c85abcf59"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus01
		{ sm.uuid.new("df1a36a3-6be0-4681-845e-d89d6c80d1a6"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus02
		{ sm.uuid.new("73acaa1d-d208-450b-8159-99d5914bbcde"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus03
		{ sm.uuid.new("c63b9bff-0c25-460b-a1a3-af3161592170"), { 0x3f5900ff, 0x576828ff, 0x66552cff }, 11, { leaves = 0 } }, --env_nature_foliage_boxwood
		{ sm.uuid.new("fd3844b5-58eb-4cb0-96d6-383b7fa83923"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }, --env_nature_foliage_columnshrub01
		{ sm.uuid.new("fe134420-39cb-450b-9560-5d3401556f7a"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }, --env_nature_foliage_columnshrub02
		{ sm.uuid.new("40ff23e6-3914-4d85-9048-fe012f72cba1"), { 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }  --env_nature_foliage_columnshrub03
	}

	sm.gui.chatMessage("A list of colors:")
	for i, v in pairs(ground_asset_list) do
		local chat_msg = i..": #ffff00"..tostring(v[1]).."#ffffff:\n"

		local color_table = v[2]
		for k, a in pairs(color_table) do
			if k > 1 then
				chat_msg = chat_msg..","

				if (k % 4) == 3 then
					chat_msg = chat_msg.."\n"
				end
			end

			local string_test = ("%08x"):format(a):sub(0, 6)
			
			chat_msg = chat_msg.."#"..string_test..string_test.."#ffffff"
		end

		sm.gui.chatMessage(chat_msg)
	end
end]]

function Game:client_onCreate()
	if not sm.isHost then
		self:loadCraftingRecipes()
	end

	gc_cl_bindChatCommands()
	WorldManager.Cl_OnCreate()
	self.cl_renderManager = sm.clientScriptableObject.createScriptableObject( sm.uuid.new( "54563daa-dd25-4f43-9e49-7e58bd59f66a" ) )

	self.network:sendToServer("sv_n_requestTime")
	self.network:sendToServer("sv_n_checkVersion", CREATIVE_TERRAIN_OVERHAUL_VERSION)

	self.cl_time_progress = true
	self.cl_time = 0.3

	if g_unitManager == nil then
		g_unitManager = UnitManager()
	end

	if g_beaconManager == nil then
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	g_radioTransmitter = sm.effect.createEffect( "Radio - Transmitter" )
	g_radioTransmitter:setWorldAny()
	g_boomboxTransmitter = sm.effect.createEffect( "Boombox - Transmitter" )
	g_boomboxTransmitter:setWorldAny()
	
	g_survivalHud = sm.gui.createSurvivalHudGui()
	g_survivalHud:setVisible("StatusPanel", false)
	g_survivalHud:setVisible("BreathPanel", false)
	g_survivalHud:setVisible("BindingPanel", false)

	self.cl_compass_enabled = sm.game.getSettingBoolean("CompassHud")
	g_compassHud = sm.gui.createCompassHudGui()
	self:cl_compassHudEnable( self.cl_compass_enabled )
end

function Game:cl_compassHudEnable( enable )
	if enable == true then
		g_compassHud:open()
	else
		g_compassHud:close()
	end
end

function Game:client_onFixedUpdate()
	local compassSetting = sm.game.getSettingBoolean( "CompassHud" )
	if self.cl_compass_enabled ~= compassSetting then
		self.cl_compass_enabled = compassSetting
		self:cl_compassHudEnable(self.cl_compass_enabled)
	end
end

local GAME_DAYCYCLE_TIME = 900.0

function Game:client_onUpdate(dt)
	if self.cl_time_progress then
		self.cl_time = math.fmod(self.cl_time + dt / GAME_DAYCYCLE_TIME, 1.0) 
	end

	sm.render.setOutdoorLighting(self.cl_time)
	sm.game.setTimeOfDay(self.cl_time)

	if WeatherManager.Get() then
		WeatherManager.Get():cl_setTimeOfDay( self.cl_time )
	end
end

function Game:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_receiveTime", { self.sv.saved.time, self.sv.saved.time_progress })
	self.storage:save(self.sv.saved)
end

function Game:server_onFixedUpdate(dt)
	if self.sv.saved.time_progress then
		self.sv.saved.time = math.fmod(self.sv.saved.time + dt / GAME_DAYCYCLE_TIME, 1.0) 
	end

	WeatherManager.Sv_SetTimeOfDay( self.sv.saved.time )

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
	WeatherManager.Sv_PlayerJoined( player )
	if isNewPlayer then
		if not sm.exists( self.sv.saved.world ) then
			sm.world.loadWorld( self.sv.saved.world )
		end

		self.sv.saved.world:loadCell( 0, 0, player, "sv_createPlayerCharacter" )
	end
end

function Game:sv_createPlayerCharacter(world, x, y, player, params)
	local param_table = { player = player, x = x, y = y }
	sm.event.sendToWorld(world, "server_spawnNewCharacter", param_table)
end

function Game:sv_e_respawn(data)
	local d_player = data.player
	local d_spawnPoint = data.spawnPoint

	local cur_world = self.sv.saved.world
	if d_spawnPoint ~= nil then
		sm.event.sendToWorld(cur_world, "server_respawnCharacter", { player = d_player, pos = d_spawnPoint })
	else
		sm.event.sendToWorld(cur_world, "server_spawnNewCharacter", { player = d_player, x = 0, y = 0 })
	end
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
	[2] = "WorldVer2",
	[3] = "WorldVer3"
}

function Game:sv_n_regenerateWorld(data, caller)
	if caller ~= g_svServerHost then
		return
	end

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

local function fileExistsSafe(path)
	local success, output = pcall(sm.json.fileExists, path)
	if success then
		return output
	end

	return false
end

function Game:cl_n_spawnCreationError(creation_name)
	cf_errorChatMessage("Couldn't find the specified creation: #ffff00"..creation_name.."#ffffff")
end

local content_local_bp = "$CONTENT_DATA/LocalBlueprints/"
local survival_local_bp = "$SURVIVAL_DATA/LocalBlueprints/"

function Game:sv_n_importCreation(data, caller)
	if caller ~= g_svServerHost then
		return
	end

	local world = data[1]
	local creation_name = data[2]
	local creation_pos = data[3]

	local final_path = nil
	local content_path = content_local_bp..creation_name..".blueprint"
	if fileExistsSafe(content_path) then
		final_path = content_path
	else
		local survival_path = survival_local_bp..creation_name..".blueprint"
		if fileExistsSafe(survival_path) then
			final_path = survival_path
		end
	end

	if final_path == nil then
		self.network:sendToClient(caller, "cl_n_spawnCreationError", creation_name)
		return
	end

	sm.creation.importFromFile(world, final_path, creation_pos)
end

function Game:cl_n_onExportCreationMsg(name)
	sm.gui.chatMessage("Creation exported as: #ffff00"..content_local_bp..name..".blueprint#ffffff")
end

function Game:sv_n_exportCreation(data, caller)
	if caller ~= g_svServerHost then
		return
	end

	local out_name = data[1]
	local body = data[2]

	local obj = sm.json.parseJsonString(sm.creation.exportToString(body))
	sm.json.save(obj, content_local_bp..out_name..".blueprint")

	self.network:sendToClient(caller, "cl_n_onExportCreationMsg", out_name)
end

function Game:sv_n_toggleCharHealth(data, caller)
	sm.event.sendToPlayer(caller, "sv_e_enableHealth", data)
end

function Game:sv_n_killCharacter(data, caller)
	sm.event.sendToPlayer(caller, "sv_e_receiveDamage", { damage = 99999 })
end

function Game:sv_n_setSpawnpoint(data, caller)
	sm.event.sendToPlayer(caller, "sv_e_setSpawnpoint")
end

function Game:sv_n_damageCharacter(damage_number, caller)
	sm.event.sendToPlayer(caller, "sv_e_receiveDamage", { damage = damage_number })
end

function Game:cl_n_toggleHealingMsg(healing_enabled)
	sm.gui.chatMessage("Healing: " .. (healing_enabled and "On" or "Off"))
end

---@param enable_healing nil|boolean
---@param caller Player
function Game:sv_n_toggleHealing(enable_healing, caller)
	if caller ~= g_svServerHost then
		return
	end

	if enable_healing == nil then
		self.sv.saved.enable_healing = not self.sv.saved.enable_healing
	else
		self.sv.saved.enable_healing = enable_healing
	end

	g_enableCharacterHealing = self.sv.saved.enable_healing

	self.storage:save(self.sv.saved)
	self.network:sendToClients("cl_n_toggleHealingMsg", g_enableCharacterHealing)
end

---@param data table
---@param caller Player
function Game:sv_n_ragdollCharacter(data, caller)
	local pl_char = caller:getCharacter()
	if pl_char and sm.exists(pl_char) then
		if not pl_char:isTumbling() then
			pl_char:setTumbling(true)
		end
	end
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

function Game:cl_n_setWeather(conditionId)
	local condition = GetWeatherConditionFromId(conditionId)
	if condition ~= nil then
		sm.gui.chatMessage(("Weather set to #ffff00%s#ffffff"):format(condition.displayName))
	end
end

function Game:sv_n_setWeather(conditionId)
	local condition = GetWeatherConditionFromId(conditionId)
	if condition ~= nil then
		WeatherManager.Sv_StartCondition( condition.event )
		self.network:sendToClients("cl_n_setWeather", conditionId)
	end
end

local PLAYER_MANAGEMENT_MESSAGE_IDS =
{
	FORBIDDEN = 1,
	NOT_FOUND = 2,
	KICKED = 3,
	BANNED = 4
}

local PLAYER_MANAGEMENT_MESSAGES =
{
	[PLAYER_MANAGEMENT_MESSAGE_IDS.FORBIDDEN] = "#ff0000ERROR#ffffff: You are not allowed to use this command",
	[PLAYER_MANAGEMENT_MESSAGE_IDS.NOT_FOUND] = "#ff0000ERROR#ffffff: The specified player could not be found",
	[PLAYER_MANAGEMENT_MESSAGE_IDS.KICKED] = "Player #ffff00%s#ffffff (id: #ffff00%i#ffffff) has been kicked!",
	[PLAYER_MANAGEMENT_MESSAGE_IDS.BANNED] = "Player #ffff00%s#ffffff (id: #ffff00%i#ffffff) has been banned!"
}

function Game:cl_n_playerManagementMessage(data)
	if type(data) ~= "table" or data.msg == nil then return end

	local curMsg = PLAYER_MANAGEMENT_MESSAGES[data.msg]
	if curMsg == nil then return end

	if data.arg	== nil then
		sm.gui.chatMessage(curMsg)
	elseif type(data.arg) == "table" then
		sm.gui.chatMessage((curMsg):format(unpack(data.arg)))
	end
end

function Game:sv_n_kickPlayer(playerId, sender)
	local hostPlayer = sm.player.getHostPlayer()
	if sender ~= hostPlayer then
		self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.FORBIDDEN })
		return
	end

	for _, v in pairs(sm.player.getAllPlayers()) do
		if v.id == playerId and v ~= hostPlayer then
			self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.KICKED, arg = { v.name, v.id } })
			sm.game.kickPlayer(v)
			return
		end
	end

	self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.NOT_FOUND })
end

function Game:sv_n_banPlayer(playerId, sender)
	local hostPlayer = sm.player.getHostPlayer()
	if sender ~= hostPlayer then
		self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.FORBIDDEN })
		return
	end

	for _, v in pairs(sm.player.getAllPlayers()) do
		if v.id == playerId and v ~= hostPlayer then
			self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.BANNED, arg = { v.name, v.id } })
			sm.game.banPlayer(v)
			return
		end
	end

	self.network:sendToClient(sender, "cl_n_playerManagementMessage", { msg = PLAYER_MANAGEMENT_MESSAGE_IDS.NOT_FOUND })
end