dofile( "$SURVIVAL_DATA/Scripts/game/managers/PesticideManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaterManager.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

---@class WorldClass
World = class( nil )
World.terrainScript = "$CONTENT_DATA/Scripts/Terrain/Terrain_v1.lua"
World.cellMinX = -101
World.cellMaxX = 100
World.cellMinY = -101
World.cellMaxY = 100
World.worldBorder = true
World.enableHarvestables = true

function World:server_onCreate()
    self.waterManager = WaterManager()
	self.waterManager:sv_onCreate(self)

	self.pesticideManager = PesticideManager()
	self.pesticideManager:sv_onCreate()
end

function World:client_onCreate()
	if self.waterManager == nil then
		self.waterManager = WaterManager()
	end

	if self.pesticideManager == nil then
		self.pesticideManager = PesticideManager()
	end

	self.waterManager:cl_onCreate()
	self.pesticideManager:cl_onCreate()
end

function World:server_onFixedUpdate(dt)
	self.waterManager:sv_onFixedUpdate()
	self.pesticideManager:sv_onWorldFixedUpdate(self)
end

function World:cl_n_pesticideMsg(msg)
	self.pesticideManager[msg.fn]( self.pesticideManager, msg )
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

function World:server_onProjectile(hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid)
	-- Notify units about projectile hit
	if isAnyOf( projectileUuid, g_potatoProjectiles ) then
		local units = sm.unit.getAllUnits()
		for i, unit in ipairs( units ) do
			if InSameWorld( self.world, unit ) then
				sm.event.sendToUnit( unit, "sv_e_worldEvent", { eventName = "projectileHit", hitPos = hitPos, hitTime = hitTime, hitVelocity = hitVelocity, attacker = attacker, damage = damage })
			end
		end
	end

	if projectileUuid == projectile_pesticide then
		local forward = sm.vec3.new( 0, 1, 0 )
		local randomDir = forward:rotateZ( math.random( 0, 359 ) )
		local effectPos = hitPos
		local success, result = sm.physics.raycast( hitPos + sm.vec3.new( 0, 0, 0.1 ), hitPos - sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 ), nil, sm.physics.filter.static + sm.physics.filter.dynamicBody )
		if success then
			effectPos = result.pointWorld + sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 )
		end
		self.pesticideManager:sv_addPesticide( self, effectPos, sm.vec3.getRotation( forward, randomDir ) )
	end

	if projectileUuid == projectile_glowstick then
		sm.harvestable.createHarvestable( hvs_remains_glowstick, hitPos, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), hitVelocity:normalize() ) )
	end

	if projectileUuid == projectile_explosivetape then
		sm.physics.explode( hitPos, 7, 2.0, 6.0, 25.0, "RedTapeBot - ExplosivesHit" )
	end
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

--Commands
function World:sv_e_onChatCommand(params)
	if params[1] == "/aggroall" then
		local units = sm.unit.getAllUnits()
		for _, unit in ipairs( units ) do
			sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = params.player.character } )
		end
		sm.gui.chatMessage( "Hostiles received " .. params.player:getName() .. "'s position." )
	elseif params[1] == "/killall" then
		local units = sm.unit.getAllUnits()
		for _, unit in ipairs( units ) do
			unit:destroy()
		end
	end
end

--World versions
WorldVer2 = class(World)
WorldVer2.terrainScript = "$CONTENT_DATA/Scripts/Terrain/Terrain_v2.lua"