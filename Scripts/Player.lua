dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$GAME_DATA/Scripts/game/BasePlayer.lua" )

---@class BTGPlayer : PlayerClass
---@field sv table
---@field cl table
Player = class( BasePlayer )

--[[function Player:sv_e_onSpawnCharacter()
	print("Player:sv_e_onSpawnCharacter")
	sm.event.sendToGame("sv_e_onSpawnPlayerCharacter", self.player)
end]]

local StatsTickRate = 40
local PerMinute = StatsTickRate / ( 40 * 60 )
local HpRecovery = 50 * PerMinute
local RespawnTimeout = 60 * 40
local RespawnFadeDuration = 0.45
local RespawnEndFadeDuration = 0.45
local RespawnFadeTimeout = 5.0
local RespawnDelay = RespawnFadeDuration * 40
local RespawnEndDelay = 1.0 * 40

function Player.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stats = { hp = 100, maxhp = 100 }
		self.sv.saved.isConscious = true
		self.sv.saved.isNewPlayer = true
		self.sv.saved.inChemical = false
		self.sv.saved.inOil = false
		self.storage:save( self.sv.saved )
	else
		if self.sv.saved.stats == nil then
			self.sv.saved.stats = { hp = 100, maxhp = 100 }
		end
		
		if self.sv.saved.isConscious == nil then
			self.sv.saved.isConscious = true
		end

		if self.sv.saved.isNewPlayer == nil then
			self.sv.saved.isNewPlayer = true
		end

		if self.sv.saved.inChemical == nil then
			self.sv.saved.inChemical = false
		end

		if self.sv.saved.inOil == nil then
			self.sv.saved.inOil = false
		end

		self.storage:save(self.sv.saved)
	end

	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function Player.server_onRefresh( self )
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function Player.server_onInventoryChanges( self, container, changes )
	self.network:sendToClient( self.player, "cl_n_onInventoryChanges", { container = container, changes = changes } )
end

function Player.sv_init( self )
	BasePlayer.sv_init( self )
	self.sv.statsTimer = Timer()
	self.sv.statsTimer:start( StatsTickRate )
	self.sv.spawnparams = {}
end

function Player.client_onCancel( self )
	BasePlayer.client_onCancel( self )
	g_effectManager:cl_cancelAllCinematics()
end

function Player.client_onCreate( self )
	BasePlayer.client_onCreate( self )
	self.cl = self.cl or {}
	if self.player == sm.localPlayer.getPlayer() then
		if g_survivalHud then
			g_survivalHud:open()
		end
	end
end

function Player.client_onClientDataUpdate( self, data )
	BasePlayer.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() == self.player then
		if self.cl.stats == nil then self.cl.stats = data.stats end -- First time copy to avoid nil errors

		if g_survivalHud then
			g_survivalHud:setVisible( "HealthBar", data.enableHealth )
			g_survivalHud:setSliderData( "Health", data.stats.maxhp * 10 + 1, data.stats.hp * 10 )
		end

		self.cl.enableHealth = data.enableHealth
		self.cl.stats = data.stats
		self.cl.isConscious = data.isConscious
	end
end

function Player.cl_n_onInventoryChanges( self, params )
	if params.container == sm.localPlayer.getInventory() then
		for i, item in ipairs( params.changes ) do
			if item.difference > 0 then
				g_survivalHud:addToPickupDisplay( item.uuid, item.difference )
			end
		end
	end
end

function Player.cl_localPlayerUpdate( self, dt )
	BasePlayer.cl_localPlayerUpdate( self, dt )

	local character = self.player:getCharacter()
	if character and not self.cl.isConscious then
		local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_RESPAWN}" )
	end
end

function Player.client_onInteract( self, character, state )
	if state == true then
		if not self.cl.isConscious then
			self.network:sendToServer( "sv_n_tryRespawn" )
		end
	end
end

function Player.server_onFixedUpdate( self, dt )
	BasePlayer.server_onFixedUpdate( self, dt )

	-- Delays the respawn so clients have time to fade to black
	if self.sv.respawnDelayTimer then
		self.sv.respawnDelayTimer:tick()
		if self.sv.respawnDelayTimer:done() then
			self:sv_e_respawn()
			self.sv.respawnDelayTimer = nil
		end
	end

	-- End of respawn sequence
	if self.sv.respawnEndTimer then
		self.sv.respawnEndTimer:tick()
		if self.sv.respawnEndTimer:done() then
			self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = RespawnEndFadeDuration } )
			self.sv.respawnEndTimer = nil
		end
	end

	-- If respawn failed, restore the character
	if self.sv.respawnTimeoutTimer then
		self.sv.respawnTimeoutTimer:tick()
		if self.sv.respawnTimeoutTimer:done() then
			self:sv_e_onSpawnCharacter()
		end
	end

	local character = self.player:getCharacter()
	if character and self.sv.saved.isConscious then
		self.sv.statsTimer:tick()
		if self.sv.statsTimer:done() then
			self.sv.statsTimer:start( StatsTickRate )

			self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + HpRecovery, self.sv.saved.stats.maxhp )

			self.storage:save( self.sv.saved )
			self.network:setClientData( self.sv.saved )
		end
	end
end

function Player.sv_takeDamage( self, damage, source )
	if not sm.exists( self.player.character ) then
		return
	end

	if damage > 0 then
		damage = damage * GetDifficultySettings().playerTakeDamageMultiplier
		local character = self.player:getCharacter()
		local lockingInteractable = character:getLockingInteractable()
		if lockingInteractable and lockingInteractable:hasSeat() then
			lockingInteractable:setSeatCharacter( character )
		end

		if self.sv.saved.enableHealth and self.sv.damageCooldown:done() then
			if self.sv.saved.isConscious then
				self.sv.saved.stats.hp = math.max( self.sv.saved.stats.hp - damage, 0 )

				print( "'Player' took:", damage, "damage.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP" )

				if source then
					self.network:sendToClients( "cl_n_onEvent", { event = source, pos = character:getWorldPosition(), damage = damage * 0.01 } )
				else
					self.player:sendCharacterEvent( "hit" )
				end

				if self.sv.saved.stats.hp <= 0 then
					print( "'Player' knocked out!" )
					self.sv.respawnInteractionAttempted = false
					self.sv.saved.isConscious = false
					character:setTumbling( true )
					character:setDowned( true )
				end

				self.storage:save( self.sv.saved )
				self.network:setClientData( self.sv.saved )
			end
		else
			print( "'Player' resisted", damage, "damage" )
		end
	end
end

function Player.sv_n_tryRespawn( self )
	if not self.sv.saved.isConscious and not self.sv.respawnDelayTimer and not self.sv.respawnInteractionAttempted then
		self.sv.respawnInteractionAttempted = true
		self.sv.respawnEndTimer = nil
		self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = RespawnFadeDuration, timeout = RespawnFadeTimeout } )

		self.sv.respawnDelayTimer = Timer()
		self.sv.respawnDelayTimer:start( RespawnDelay )
	end
end

function Player.sv_e_respawn( self )
	if self.sv.spawnparams.respawn then
		if not self.sv.respawnTimeoutTimer then
			self.sv.respawnTimeoutTimer = Timer()
			self.sv.respawnTimeoutTimer:start( RespawnTimeout )
		end
		return
	end
	if not self.sv.saved.isConscious then
		self.sv.spawnparams.respawn = true
		sm.event.sendToGame( "sv_e_respawn", { player = self.player, spawnPoint = self.sv.saved.spawnPoint } )
	else
		print( "Player must be unconscious to respawn" )
	end
end

function Player.sv_e_onSpawnCharacter( self )
	if self.sv.spawnparams.respawn then
		self.sv.respawnEndTimer = Timer()
		self.sv.respawnEndTimer:start( RespawnEndDelay )
	end

	if self.sv.saved.isNewPlayer or self.sv.spawnparams.respawn then
		print( "Player", self.player.id, "spawned" )
		self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
		self.sv.saved.isConscious = true
		self.sv.saved.isNewPlayer = false
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )

		self.player.character:setTumbling( false )
		self.player.character:setDowned( false )
		self.sv.damageCooldown:start( 40 )
	else
		-- Player rejoined the game or fell off the map
		if self.sv.saved.stats.hp <= 0 or not self.sv.saved.isConscious then
			self.player.character:setTumbling( true )
			self.player.character:setDowned( true )
		end
	end

	self.sv.respawnInteractionAttempted = false
	self.sv.respawnDelayTimer = nil
	self.sv.respawnTimeoutTimer = nil
	self.sv.spawnparams = {}

	sm.event.sendToGame("sv_e_onSpawnPlayerCharacter", self.player)
end

function Player:cl_e_spawnpointMsg(data)
	local d_player = data[1]
	local d_pos = data[2]

	sm.gui.chatMessage(("#ffff00%s#ffffff set their spawn point at (#ffff00%0.3f#ffffff, #ffff00%0.3f#ffffff, #ffff00%0.3f#ffffff)"):format(d_player.name, d_pos.x, d_pos.y, d_pos.z))
end

function Player:cl_e_spawnpointError()
	sm.gui.chatMessage("#ffff00ERROR#ffffff: You can't set a spawn point while unconscious.")
end

function Player:sv_e_setSpawnpoint()
	if self.sv.saved.isConscious then
		local pl_char = self.player.character
		if pl_char and sm.exists(pl_char) then
			self.sv.saved.spawnPoint = pl_char.worldPosition
			self.storage:save(self.sv.saved)

			self.network:sendToClients("cl_e_spawnpointMsg", { self.player, pl_char.worldPosition })
		end
	else
		self.network:sendToClient(self.player, "cl_e_spawnpointError")
	end
end

function Player.sv_e_enableHealth( self, enableHealth )
	if enableHealth == nil then
		self.sv.saved.enableHealth = not self.sv.saved.enableHealth
	else
		self.sv.saved.enableHealth = enableHealth
	end

	self.network:setClientData( self.sv.saved )
end