dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaterManager.lua" )

World = class( nil )
World.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
World.cellMinX = -101
World.cellMaxX = 100
World.cellMinY = -101
World.cellMaxY = 100
World.worldBorder = true
World.enableHarvestables = true

function World:server_onCreate()
    self.waterManager = WaterManager()
	self.waterManager:sv_onCreate(self)
end

function World:client_onCreate()
	if self.waterManager == nil then
		self.waterManager = WaterManager()
	end

	self.waterManager:cl_onCreate()
end

function World:server_onFixedUpdate(dt)
	self.waterManager:sv_onFixedUpdate()
end

function World:client_onFixedUpdate(dt)
	self.waterManager:cl_onFixedUpdate()
end

function World:server_onCellCreated(x, y)
	self.waterManager:sv_onCellLoaded(x, y)
end

function World:client_onCellLoaded(x, y)
	self.waterManager:cl_onCellLoaded(x, y)
end

function World:server_onCellLoaded(x, y)
	self.waterManager:sv_onCellReloaded(x, y)
end

function World:server_onCellUnloaded(x, y)
	self.waterManager:sv_onCellUnloaded(x, y)
end

function World:client_onCellUnloaded(x, y)
	self.waterManager:cl_onCellUnloaded(x, y)
end

function World:sv_n_clearWorld()
	for _, body in ipairs(sm.body.getAllBodies()) do
		for _, shape in ipairs(body:getShapes()) do
			shape:destroyShape()
		end
	end
end

function World.server_spawnNewCharacter(self, params)
    local spawnRayBegin = sm.vec3.new( params.x, params.y, 1024 )
	local spawnRayEnd = sm.vec3.new( params.x, params.y, -1024 )
	local valid, result = sm.physics.spherecast( spawnRayBegin, spawnRayEnd, 0.3 )
	local pos
	if valid then
		pos = result.pointWorld + sm.vec3.new( 0, 0, 0.4 )
	else
		pos = sm.vec3.new( params.x, params.y, 100 )
	end

	local character = sm.character.createCharacter( params.player, self.world, pos )
	params.player:setCharacter( character )
end

--Beacons
function World:sv_e_createBeacon(params)
	local p_player = params.player
	if p_player and sm.exists(p_player) then
		self.network:sendToClient(p_player, "cl_n_createBeacon", params)
	else
		self.network:sendToClients("cl_n_createBeacon", params)
	end
end

function World:cl_n_createBeacon(params)
	g_beaconManager:cl_createBeacon(params)
end

function World:sv_e_destroyBeacon(params)
	local p_player = params.player
	if p_player and sm.exists(p_player) then
		self.network:sendToClient(p_player, "cl_n_destroyBeacon", params)
	else
		self.network:sendToClients("cl_n_destroyBeacon", params)
	end
end

function World:cl_n_destroyBeacon(params)
	g_beaconManager:cl_destroyBeacon(params)
end

function World:sv_e_unloadBeacon(params)
	local p_player = params.player
	if p_player and sm.exists(p_player) then
		self.network:sendToClient(p_player, "cl_n_unloadBeacon", params)
	else
		self.network:sendToClients("cl_n_unloadBeacon", params)
	end
end

function World:cl_n_unloadBeacon(params)
	g_beaconManager:cl_unloadBeacon(params)
end

--Units
function World:server_onInteractableCreated(interactable)
	g_unitManager:sv_onInteractableCreated(interactable)
end

function World:server_onInteractableDestroyed(interactable)
	g_unitManager:sv_onInteractableDestroyed(interactable)
end

function World:server_onCollision(objectA, objectB, collisionPosition, objectAPointVelocity, objectBPointVelocity, collisionNormal)
	g_unitManager:sv_onWorldCollision(self, objectA, objectB, collisionPosition, objectAPointVelocity, objectBPointVelocity, collisionNormal)
end