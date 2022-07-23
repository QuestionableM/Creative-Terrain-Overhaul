dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )

dofile("GameCommands.lua")

Game = class( nil )

local data = sm.json.open("$SURVIVAL_DATA/Harvestables/Database/HarvestableSets/hvs_trees.json")
local final_string = "\nlocal hvs_table =\n{\n"
for k, v in pairs(data.harvestableList) do
	final_string = final_string.."\t{ sm.uuid.new(\""..tostring(v.uuid).."\"), { "

	for i, a in pairs(v.color) do
		if i > 1 then
			final_string = final_string..", "
		end
		final_string = final_string.."0x"..a
	end

	final_string = final_string.." }, "..#v.color.." }, --"..v.name.."\n"
end
final_string = final_string.."}"
print(final_string)

function Game.server_onCreate( self )
	print("Game.server_onCreate")
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "World", {}, math.random(os.time()) )
		self.storage:save( self.sv.saved )

		self.sv.saved.time = 0.2
		self.sv.saved.time_progress = true
	end

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate(nil, { aggroCreations = true })
end

function Game:client_onCreate()
	gc_cl_bindChatCommands()

	self.network:sendToServer("sv_n_requestTime")

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

function Game:sv_n_setTimeProgress(new_progress)
	if new_progress then
		self.sv.saved.time_progress = new_progress
	else
		self.sv.saved.time_progress = not self.sv.saved.time_progress
	end

	self:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_onTimeProgressChange", self.sv.saved.time_progress)
end

function Game:cl_n_onTimeProgressChange(new_state)
	sm.gui.chatMessage("Time Progress Changed to "..cf_boolToString[new_state])
end

function Game:cl_n_onTimeChangeMsg(new_time)
	sm.gui.chatMessage(("Time set to #ffff00%.3f#ffffff"):format(new_time))
end

function Game:sv_n_setTime(new_time)
	self.sv.saved.time = new_time

	self:server_saveAndSyncTime()
	self.network:sendToClients("cl_n_onTimeChangeMsg", new_time)
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