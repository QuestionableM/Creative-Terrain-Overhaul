dofile( "$SURVIVAL_DATA/Scripts/game/managers/AttachedFireManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaterManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/FireManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_sob.lua" )

dofile( "$GAME_DATA/Scripts/game/managers/RenderSettingsManager.lua" )

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
	self.fireManager = FireManager()
	self.fireManager:sv_onCreate(self)

    self.waterManager = WaterManager()
	self.waterManager:sv_onCreate(self)

	self.sv = {}
	self.sv.ambienceManager = sm.scriptableObject.createScriptableObject( sm.uuid.new("635b5d17-fa35-4591-82ec-358da595bac0"), nil, self.world )
	self.sv.rayProjectileManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "8504131e-8f58-4d25-beab-3bc996b7a95e" ), nil, self.world )

	WorldManager.Sv_RegisterWorld( "weatherworld", self.world )
end

function World:client_onCreate()
	if self.fireManager == nil then
		self.fireManager = FireManager()
	end

	if self.waterManager == nil then
		self.waterManager = WaterManager()
	end

	self.fireManager:cl_onCreate()
	self.waterManager:cl_onCreate()

	WorldManager.Cl_RegisterWorld( "weatherworld", self.world )
end

function World:server_onFixedUpdate(dt)
	AttachedFireManager.Sv_OnWorldFixedUpdate( self.world )
	CablebotManager.Cl_OnWorldFixedUpdate( self.world )
	self.fireManager:sv_onFixedUpdate()
	self.waterManager:sv_onFixedUpdate()
end

function World:client_onFixedUpdate(dt)
	AttachedFireManager.Cl_OnWorldFixedUpdate( self.world )
	CablebotManager.Cl_OnWorldFixedUpdate( self.world )
	self.waterManager:cl_onFixedUpdate()
end

function World:sv_n_fireMsg( msg, player )
	self.fireManager:sv_handleMsg( msg, player )
end

function World:cl_n_fireMsg( msg )
	self.fireManager:cl_handleMsg( msg )
end

function World:sv_e_activateFire( name )
	self.fireManager:sv_activateInactiveFire( name )
end

function World:sv_e_activateFires( fireList )
	for _, name in ipairs( fireList ) do
		self.fireManager:sv_activateInactiveFire( name )
	end
end

function World:sv_e_removeFiresInCell( cell )
	self.fireManager:sv_removeAllFiresInCell( cell.x, cell.y )
end

function World:server_onCellCreated(x, y)
	self.fireManager:sv_onCellLoaded(x, y)
	self.waterManager:sv_onCellLoaded(x, y)
end

function World:client_onCellLoaded(x, y)
	self.fireManager:cl_onCellLoaded(x, y)
	self.waterManager:cl_onCellLoaded(x, y)
	RenderSettingsManager.Cl_onCellLoaded( x, y )
end

function World:server_onCellLoaded(x, y)
	self.fireManager:sv_onCellReloaded(x, y)
	self.waterManager:sv_onCellReloaded(x, y)
end

function World:server_onCellUnloaded(x, y)
	self.fireManager:sv_onCellUnloaded(x, y)
	self.waterManager:sv_onCellUnloaded(x, y)
end

function World:client_onCellUnloaded(x, y)
	self.waterManager:cl_onCellUnloaded(x, y)
	RenderSettingsManager.Cl_onCellUnloaded( x, y )
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

	if isAnyOf(projectileUuid, g_potatoProjectiles) then
		sm.message.send(MESSAGE_TYPES.GENERAL.ProjectileHit, { world = self.world, position = hitPos, attacker = attacker })
	elseif projectileUuid == projectile_clay then
		local clayMaterial = 0
		self.world:voxelDensityAddition(hitPos, hitNormal, 2.5, 5, clayMaterial, sm.world.voxelFilter.all, attacker)
	elseif projectileUuid == projectile_pesticide then
		local forward = sm.vec3.new( 0, 1, 0 )
		local randomDir = forward:rotateZ( math.rad( math.random( 0, 359 ) ) )
		local effectPos = hitPos
		local success, result = sm.physics.raycast( hitPos + sm.vec3.new( 0, 0, 0.1 ), hitPos - sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 ), nil, sm.physics.filter.static + sm.physics.filter.dynamicBody )
		if success then
			effectPos = result.pointWorld + sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 )
		end
		sm.scriptableObject.createScriptableObject( sob_pesticide_cloud, { position = effectPos, rotation = sm.vec3.getRotation( forward, randomDir ) }, self.world )
	elseif projectileUuid == projectile_glowstick or projectileUuid == projectile_glowstick_detach then
		if target then
			local targetType = type( target )
			if not (targetType == "Shape" or targetType == "Harvestable" or targetType == "VoxelTerrain" ) then
				sm.effect.playEffect( "GlowstickProjectile - Bounce", hitPos )
				return
			end
		end
		local inputLifetime = nil
		if userData then
			inputLifetime = userData.lifetime
		end
		GlowstickManager.Sv_CreateGlowstick( { hitPos = hitPos, hitTime = hitTime, hitNormal = hitNormal, target = target, world = self.world, lifetime = inputLifetime, projectileUuid = projectileUuid } )
	elseif projectileUuid == projectile_explosivetape then
		sm.physics.explode( hitPos, 7, 2.0, 6.0, 25.0, "RedTapeBot - ExplosivesHit", nil, nil, nil, 35 )
	elseif projectileUuid == projectile_smallexplosive then
		sm.physics.explode( hitPos, 7, 2.0, 6.0, 25.0, "PropaneTank - ExplosionSmall", nil, nil, nil, 35 )
	elseif projectileUuid == projectile_cornade_explosive then
		sm.physics.explode( hitPos, 5, 3.0, 6.0, 25.0, "Cornnade - Explosion", nil, nil, nil, 35, attacker, EXPLOSIONS.explosion_cornade )
	elseif projectileUuid == projectile_water then
		AttachedFireManager.Sv_Quench( hitPos )
		local contacts = sm.physics.getSphereContacts( hitPos, 0.4 )
		if contacts.harvestables then
			for _,harvestable in ipairs( contacts.harvestables ) do
				if WaterSplashableSet[tostring( harvestable.uuid )] then
					sm.event.sendToHarvestable( harvestable, "sv_e_waterSoil" )
				end
			end
		end
	elseif projectileUuid == projectile_flame then
		if attacker and type( attacker ) == "Player" and sm.exists( attacker ) then
			PotatoLauncherSplash( self.world, hitPos )
		else
			sm.fire.igniteSphere( hitPos, 0.25, true )
		end
	elseif projectileUuid == projectile_foam then
		AttachedFireManager.Sv_Quench( hitPos )
	elseif projectileUuid == projectile_cablebot then
		CablebotManager.Sv_AttachCablebot( hitPos, hitVelocity:safeNormalize( sm.vec3.new( 0, 1, 0 ) ) )
	elseif projectileUuid == projectile_trashbomb_green or projectileUuid == projectile_trashbomb_purple then
		sm.physics.explode( hitPos, 0, 3.0, 2.0, 0, nil, nil, nil, nil, 15 )
		local spawnChance = math.random()
		if spawnChance <= 0.25 and attacker and type( attacker ) == "Unit" and sm.exists( attacker ) then -- 25% chance
			self:sv_spawnTrashbubbleLoot( hitPos, attacker )
		end
	elseif projectileUuid == projectile_trashbomb_mass_green or projectileUuid == projectile_trashbomb_mass_purple then
		local spawnChance = math.random()
		if spawnChance <= 0.05 and attacker and type( attacker ) == "Unit" and sm.exists( attacker ) then -- 5% chance
			self:sv_spawnTrashbubbleLoot( hitPos, attacker )
		end
	elseif projectileUuid == projectile_trashbubble_green or projectileUuid ==  projectile_trashbubble_purple then
		self.network:sendToClients( "cl_n_updateTrashSpray", { hitPos = hitPos } )
	elseif isAnyOf( projectileUuid, g_spawnerProjectiles ) then
		if userData and userData.unit then
			local yaw = math.random() * 2 * math.pi
			if self.world:getWeightedVoxelDensityInWorldPoint( hitPos ) > 0 then
				hitPos = hitPos + hitNormal * 1.5 -- move out of terrain in case of hitting area with high voxel density
			end
			sm.unit.createUnit( userData.unit, hitPos, yaw, { aggressive = true } )
		end
	elseif isAnyOf( projectileUuid, NuggetProjectiles ) then
		sm.shape.createPart( ProjectileToNugget[tostring(projectileUuid)], hitPos + sm.vec3.new( 0, 0, 0.5 ), sm.quat.identity(), true )
	end

	if type( target ) == "Shape" and sm.exists( target ) and target.interactable and target.interactable:hasSeat() then
		-- pass on damage from projectiles that hit a seat
		if type( attacker ) == "Unit" or ( type( attacker ) == "Shape" and isTrapProjectile( projectileUuid ) ) or ( userData and userData.damagePlayer ) then
			local source = "shock"
			if projectileUuid == projectile_tape or projectileUuid == projectile_bubblewrap then
				source = "tapebotprojectile"
			end
			local targetCharacter = target.interactable:getSeatCharacter()
			local targetPlayer = targetCharacter and targetCharacter:getPlayer() or nil
			if targetPlayer then
				sm.event.sendToPlayer( targetPlayer, "sv_e_receiveDamage", { damage = damage, source = source } )
			end
		end
	end
end

function World:server_onExplosion(center, destructionLevel, radius, uDamage, src, srcTypeUid)
	self.world:sphereVoxelDensitySubtraction( center, radius, bit.bor( sm.world.voxelFilter.material0, sm.world.voxelFilter.material1, sm.world.voxelFilter.material2, sm.world.voxelFilter.material3 ), 10.0 )
	CablebotManager.Sv_Explosion( center, radius )
end

function World:server_onMelee( hitPos, attacker, target, damage, power, hitDirection, hitNormal )
	if type( target ) == "VoxelTerrain" and type( attacker ) == "Player" then
		local radius = 2
		local world = attacker:getCharacter():getWorld()
		world:voxelDensitySubtraction( hitPos, sm.vec3.zero(), radius, { 30, 30, 30, 30, 30, 30, 30, 30 }, sm.world.voxelFilter.all )
	end
end

function World:server_onVoxelConstruction( constructions )
	local glowstickIds = {}
	for _, construction in ipairs( constructions ) do
		for i = 1, 8 do
			if construction.densities[i] > 0 then
				GlowstickManager.Sv_GetGlowstickIds( construction.aabbsMin[i] - 1, construction.aabbsMax[i] + 1, glowstickIds, false )
			end
		end
	end

	if not IsEmptyTable( glowstickIds ) then
		GlowstickManager.Sv_CheckVoxelContact( glowstickIds )
	end
end

function World:server_onVoxelDestruction( destructions )
	local glowstickIds = {}
	for _, destruction in ipairs( destructions ) do
		for i = 1, 8 do
			if destruction.densities[i] > 0 then
				GlowstickManager.Sv_GetGlowstickIds( destruction.aabbsMin[i] - 1, destruction.aabbsMax[i] + 1, glowstickIds, true )
			end
		end
	end

	if not IsEmptyTable( glowstickIds ) then
		GlowstickManager.Sv_CheckVoxelContact( glowstickIds )
	end
end

function World:cl_n_worldCleanedMsg(bodies)
	sm.gui.chatMessage("Successfully removed #ffff00"..bodies.."#ffffff bodies")
end

function World:sv_n_clearWorld()
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs(bodies) do
		for _, shape in ipairs(body:getShapes()) do
			shape:destroyShape()
		end
	end

	self.network:sendToClients("cl_n_worldCleanedMsg", #bodies)
end

function World:server_spawnNewCharacter(params)
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

function World:server_respawnCharacter(params)
	local p_player = params.player
	local character = sm.character.createCharacter(p_player, self.world, params.pos)
	p_player:setCharacter(character)
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

function World:sv_e_aggroAll(player)
	local units = sm.unit.getAllUnits()
	for _, unit in ipairs(units) do
		sm.event.sendToUnit(unit, "sv_e_receiveTarget", { targetCharacter = player.character })
	end

	sm.gui.chatMessage("Hostiles received "..player:getName().."'s position.")
end

function World:sv_e_killAll()
	local units = sm.unit.getAllUnits()
	for _, unit in ipairs(units) do
		unit:destroy()
	end
end

local function selectHarvestableToPlace( keyword )
	if keyword == "stone" then
		local stones = {
			hvs_stone_small01, hvs_stone_small02, hvs_stone_small03
			--hvs_stone_medium01, hvs_stone_medium02, hvs_stone_medium03,
			--hvs_stone_large01, hvs_stone_large02, hvs_stone_large03
		}
		return stones[math.random( 1, #stones )]
	elseif keyword == "tree" then
		local trees = {
			hvs_tree_birch01, hvs_tree_birch02, hvs_tree_birch03,
			hvs_tree_leafy01, hvs_tree_leafy02, hvs_tree_leafy03,
			hvs_tree_spruce01, hvs_tree_spruce02, hvs_tree_spruce03,
			hvs_tree_pine01, hvs_tree_pine02, hvs_tree_pine03
		}
		return trees[math.random( 1, #trees )]
	elseif keyword == "birch" then
		local trees = { hvs_tree_birch01, hvs_tree_birch02, hvs_tree_birch03 }
		return trees[math.random( 1, #trees )]
	elseif keyword == "leafy" then
		local trees = { hvs_tree_leafy01, hvs_tree_leafy02, hvs_tree_leafy03 }
		return trees[math.random( 1, #trees )]
	elseif keyword == "spruce" then
		local trees = {	hvs_tree_spruce01, hvs_tree_spruce02, hvs_tree_spruce03 }
		return trees[math.random( 1, #trees )]
	elseif keyword == "pine" then
		local trees = { hvs_tree_pine01, hvs_tree_pine02, hvs_tree_pine03 }
		return trees[math.random( 1, #trees )]
	end
	return nil
end

function World:sv_e_placeHvs(params)
	local harvestableUuid = selectHarvestableToPlace( params[1] )
	local aim_pos = params[2]
	if harvestableUuid and aim_pos then
		local from = aim_pos + sm.vec3.new( 0, 0, 16.0 )
		local to = aim_pos - sm.vec3.new( 0, 0, 16.0 )
		local success, result = sm.physics.raycast( from, to, nil, sm.physics.filter.default )
		if success and result.type == "terrainSurface" then
			local harvestableYZRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) )
			local harvestableRotation = sm.quat.fromEuler( sm.vec3.new( 0, math.random( 0, 359 ), 0 ) )
			local placePosition = result.pointWorld
			if params[2] == "stone" then
				placePosition = placePosition + sm.vec3.new( 0, 0, 2.0 )
			end
			sm.harvestable.createHarvestable( harvestableUuid, placePosition, harvestableYZRotation * harvestableRotation )
		end
	end
end

function World:server_onTerrainCreated()
	GlowstickManager.Sv_WorldReady( self.world )
end

function World:server_onTerrainLoaded()
	GlowstickManager.Sv_WorldReady( self.world )
end

function World:client_onTerrainCreated()
	GlowstickManager.Cl_WorldReady( self.world )
end

function World:client_onTerrainLoaded()
	GlowstickManager.Cl_WorldReady( self.world )
end

--World versions

---@type WorldClass
WorldVer2 = class(World)
WorldVer2.terrainScript = "$CONTENT_DATA/Scripts/Terrain/Terrain_v2.lua"

---@type WorldClass
WorldVer3 = class(World)
WorldVer3.terrainScript = "$CONTENT_DATA/Scripts/Terrain/Terrain_v3.lua"