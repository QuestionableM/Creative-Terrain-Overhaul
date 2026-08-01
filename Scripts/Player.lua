dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$CONTENT_DATA/Scripts/BasePlayer.lua" )

---@class BTGPlayer : PlayerClass
---@field sv table
---@field cl table
Player = class( BasePlayer )

local HealthWarningThreshold = 25
local OxygenWarningThreshold = 25

Player.Perks = {
	BonusHealth = 1,
	HammerSpeed = 2,
	FallProtection = 3,
	HighJump = 4
}

local StatusPanelGui = {}
StatusPanelGui.root = sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/StatusPanel.gui" )
StatusPanelGui.index = IndexWidgets( StatusPanelGui.root )
StatusPanelGui.index["StatusPanel"].Visible = false

StatusPanelGui.bar = {}
StatusPanelGui.bar["Health"] = { baseWidth = 122, border = 2 }
StatusPanelGui.bar["HealthLoss"] = { baseWidth = 122, border = 2 }
StatusPanelGui.bar["HealthGain"] = { baseWidth = 122, border = 2 }

StatusPanelGui.buff = DeepCopy( StatusPanelGui.index["BuffBase"] )

local OxygenPanelGui = {}
OxygenPanelGui.root = sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/OxygenPanel.gui" )
OxygenPanelGui.index = IndexWidgets( OxygenPanelGui.root )

OxygenPanelGui.bar = {}
OxygenPanelGui.bar["Oxygen"] = { baseWidth = 122, border = 2 }

local StatsTickRate = 40
local PerMinute = StatsTickRate / ( 40 * 60 )
local HpRecovery = 50 * PerMinute
local RespawnTimeout = 60 * 40
local RespawnFadeDuration = 0.45
local RespawnEndFadeDuration = 0.45
local RespawnFadeTimeout = 5.0
local RespawnDelay = RespawnFadeDuration * 40
local RespawnEndDelay = 1.0 * 40

local BreathLostPerTick = ( 100 / 60 ) / 40
local DrownDamage = 5
local DrownDamageCooldown = 40

function Player.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stats = { hp = 100, maxhp = 100, breath = 100, maxbreath = 100, perks = {} }
		self.sv.saved.enableHealth = false
		self.sv.saved.isConscious = true
		self.sv.saved.isNewPlayer = true
		self.sv.saved.inChemical = false
		self.sv.saved.inOil = false
		self.storage:save( self.sv.saved )
	else
		if self.sv.saved.stats == nil then
			self.sv.saved.stats = { hp = 100, maxhp = 100, breath = 100, maxbreath = 100, perks = {} }
		else
			if self.sv.saved.stats.hp == nil then
				self.sv.saved.stats.hp = 100
				self.sv.saved.stats.maxhp = 100
			end

			if self.sv.saved.stats.breath == nil then
				self.sv.saved.stats.breath = 100
				self.sv.saved.stats.maxbreath = 100
			end

			if self.sv.saved.stats.perks == nil then
				self.sv.saved.stats.perks = {}
			end
		end
		
		if self.sv.saved.enableHealth == nil then self.sv.saved.enableHealth = false end
		if self.sv.saved.isConscious == nil then self.sv.saved.isConscious = true end
		if self.sv.saved.isNewPlayer == nil then self.sv.saved.isNewPlayer = true end
		if self.sv.saved.inChemical == nil then self.sv.saved.inChemical = false end
		if self.sv.saved.inOil == nil then self.sv.saved.inOil = false end

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

	self.sv.drownTimer = Timer()
	self.sv.drownTimer:stop()

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
		g_svServerHost = sm.localPlayer.getPlayer()
		if g_survivalHud then
			g_survivalHud:open()
		end

		self.cl.statusPanelGui = sm.jsonGui.createGui( { isHud = true, isInteractive = false, needsCursor = true, layer = "Middle" } )
		self.cl.oxygenPanelGui = sm.jsonGui.createGui( { isHud = true, isInteractive = false, needsCursor = false } )

		self.cl.underwaterEffect = sm.effect.createEffect( "Mechanic - StatusUnderwater" )
		self.cl.raidCompletedEffect = sm.effect.createEffect2D ( "audio:event:/ui/raid/end" )
	end
end

function Player.client_onClientDataUpdate( self, data )
	BasePlayer.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() == self.player then
		if self.cl.stats == nil then self.cl.stats = data.stats end -- First time copy to avoid nil errors

		local pl_char = self.player.character
		if pl_char then
			local charParam = self.player:isMale() and 1 or 2
			self.cl.underwaterEffect:setParameter("char", charParam)
			
			if data.stats.breath <= 15 and not self.cl.underwaterEffect:isPlaying() and data.isConscious then
				self.cl.underwaterEffect:start()
			elseif ( data.stats.breath > 15 or not data.isConscious ) and self.cl.underwaterEffect:isPlaying() then
				self.cl.underwaterEffect:stop()
			end
		end

		if data.stats.breath <= 0 and self.cl.stats.breath > 0 then
			NotificationManager.Cl_AddGenericNotification( "#{DAMAGE_BREATH}", 5, true )
		end

		if data.stats.hp < self.cl.stats.hp and data.stats.breath == 0 then
			sm.gui.displayAlertText( "#{DAMAGE_BREATH}", 1 )
		end

		self.cl.enableHealth = data.enableHealth
		self.cl.stats = data.stats
		self.cl.isConscious = data.isConscious
		self.cl.statsAge = 0
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

local function SetBarWidth( panel, name, value, max )
	local bar = panel.bar[name]
	local width = math.floor( clamp( value / max, 0.0, 1.0 ) * bar.baseWidth ) + bar.border * 2
	if panel.index[name] == nil then
		sm.log.error( "Missing widget: " .. name )
	end
	panel.index[name].width = width
	panel.index[name].Visible = value > 0
end

function Player.cl_localPlayerUpdate( self, dt )
	BasePlayer.cl_localPlayerUpdate( self, dt )

	local character = self.player:getCharacter()
	if character then
		if not self.cl.isConscious then
			local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
			sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_RESPAWN}" )
		end

		self.cl.underwaterEffect:setPosition(character.worldPosition)
	end

	if character and self.cl.stats then
		self.cl.statsAge = self.cl.statsAge + dt
		local FlashTimeInterval = 0.9
		self.cl.flashTimeFraction = self.cl.flashTimeFraction or 0
		local lowFlash = false
		local highFlash = false
		if self.cl.resetFlashTime then
			self.cl.flashTimeFraction = 0.0
			lowFlash = true
		else
			if self.cl.flashTimeFraction < 1 and self.cl.flashTimeFraction + dt / FlashTimeInterval >= 1 then
				lowFlash = true
			end
			if self.cl.flashTimeFraction < 0.5 and self.cl.flashTimeFraction + dt / FlashTimeInterval >= 0.5 then
				highFlash = true
			end
			self.cl.flashTimeFraction = ( self.cl.flashTimeFraction + dt / FlashTimeInterval ) % 1
		end
		self.cl.resetFlashTime = true

		local flash = math.cos( ( self.cl.flashTimeFraction + 0.5 ) * math.pi * 2 ) * 0.5 + 0.5

		self.cl.hpLoss = self.cl.hpLoss or self.cl.stats.hp
		if self.cl.hpHistory then
			local delayedHp = self.cl.hpHistory[40]
			if self.cl.hpLoss > delayedHp then
				self.cl.hpLoss = math.max( self.cl.hpLoss - self.cl.stats.maxhp * dt, delayedHp )
			elseif self.cl.hpLoss < delayedHp then
				self.cl.hpLoss = self.cl.stats.hp
			end
		end

		local screenWidth, screenHeight = sm.jsonGui.getViewSize()
		StatusPanelGui.root.x = math.floor( -screenWidth / 2 + StatusPanelGui.root.width * 0.5 )
		StatusPanelGui.root.y = math.floor( screenHeight / 2 - StatusPanelGui.root.height * 0.5 )
		StatusPanelGui.index["StatusPanel"].Visible = self.cl.enableHealth
		if StatusPanelGui.index["StatusPanel"].Visible then	
			SetBarWidth( StatusPanelGui, "Health", self.cl.stats.hp, self.cl.stats.maxhp )
			SetBarWidth( StatusPanelGui, "HealthLoss", self.cl.hpLoss, self.cl.stats.maxhp )
	
			local activeItem = sm.localPlayer.getActiveItem()
			local edible = sm.item.getEdible( activeItem )
			if edible and not character:isSeated() then
				local hpGain = edible.hpGain or 0
				SetBarWidth( StatusPanelGui, "HealthGain", self.cl.stats.hp + hpGain, self.cl.stats.maxhp )
			else
				SetBarWidth( StatusPanelGui, "HealthGain", self.cl.stats.hp, self.cl.stats.maxhp )
			end
	
			-- Health warning flash
			if self.cl.stats.hp > 0 and self.cl.stats.hp < HealthWarningThreshold then
				if not StatusPanelGui.index["HealthIconGlow"].Visible and lowFlash then
					StatusPanelGui.index["HealthIconGlow"].Visible = true
				end
				self.cl.resetFlashTime = false
			else
				if StatusPanelGui.index["HealthIconGlow"].Visible and lowFlash then
					StatusPanelGui.index["HealthIconGlow"].Visible = false
				end
			end
			if StatusPanelGui.index["HealthIconGlow"].Visible then
				StatusPanelGui.index["HealthIconGlow"].Alpha = flash
				self.cl.resetFlashTime = false
			end
		end

		-- Oxygen
		OxygenPanelGui.root.x = 0
		OxygenPanelGui.root.y = math.floor( -screenHeight / 2 + OxygenPanelGui.root.height * 0.5 )

		OxygenPanelGui.index["OxygenPanel"].Visible = self.cl.stats.breath < self.cl.stats.maxbreath

		if OxygenPanelGui.index["OxygenPanel"].Visible then
			local beathEstimate = self.cl.stats.breath - BreathLostPerTick * 40 * self.cl.statsAge
			SetBarWidth( OxygenPanelGui, "Oxygen", beathEstimate, self.cl.stats.maxbreath )

			-- Oxygen update flash
			if self.cl.stats.breath < self.cl.stats.maxbreath then
				if not self.cl.flashBreath and highFlash then
					self.cl.flashBreath = true
				end
				self.cl.resetFlashTime = false
			else
				if self.cl.flashBreath and highFlash then
					self.cl.flashBreath = false
				end
			end
			if self.cl.flashBreath then
				OxygenPanelGui.index["OxygenIcon"].Alpha = flash * 0.5 + 0.5
				self.cl.resetFlashTime = false
			else
				OxygenPanelGui.index["OxygenIcon"].Alpha = 1.0
			end

			-- Oxygen warning flash
			if self.cl.stats.breath < OxygenWarningThreshold then
				if not OxygenPanelGui.index["OxygenIconGlow"].Visible and lowFlash then
					OxygenPanelGui.index["OxygenIconGlow"].Visible = true
				end
				self.cl.resetFlashTime = false
			else
				if OxygenPanelGui.index["OxygenIconGlow"].Visible and lowFlash then
					OxygenPanelGui.index["OxygenIconGlow"].Visible = false
				end
			end
			if OxygenPanelGui.index["OxygenIconGlow"].Visible then
				OxygenPanelGui.index["OxygenIconGlow"].Alpha = flash
				self.cl.resetFlashTime = false
			end
		else
			self.cl.flashBreath = nil
			OxygenPanelGui.index["OxygenIconGlow"].Visible = false
		end

		-- Perks
		local count = 0
		local BuffHolderChilds = StatusPanelGui.index["BuffHolder"].Childs

		for key, _ in pairs( self.cl.stats.perks ) do
			count = count + 1

			local buffBase
			if BuffHolderChilds[count] then
				buffBase = BuffHolderChilds[count]
			else
				buffBase = DeepCopy( StatusPanelGui.buff )
				BuffHolderChilds[#BuffHolderChilds+1] = buffBase
			end

			if key == Player.Perks.BonusHealth then
				buffBase.Childs[1].Skin = "StatusPanelBuffBonusHealth"
				buffBase.Childs[1].ToolTip.Text = "#{STATUS_PANEL_BUFF_BONUS_HEALTH}"
			elseif key == Player.Perks.HammerSpeed then
				buffBase.Childs[1].Skin = "StatusPanelBuffHammer"
				buffBase.Childs[1].ToolTip.Text = "#{STATUS_PANEL_BUFF_HAMMER_SPEED}"
			elseif key == Player.Perks.FallProtection then
				buffBase.Childs[1].Skin = "StatusPanelBuffFallDamage"
				buffBase.Childs[1].ToolTip.Text = "#{STATUS_PANEL_BUFF_FALL_PROTECTION}"
			elseif key == Player.Perks.HighJump then
				buffBase.Childs[1].Skin = "StatusPanelBuffJump"
				buffBase.Childs[1].ToolTip.Text = "#{STATUS_PANEL_BUFF_HIGH_JUMP}"
			else
				buffBase.Childs[1].Skin = "WhiteSkin"
			end

			if self.cl.newPerks and self.cl.newPerks[key] == true then
				buffBase.Childs[1].Childs[1].Effects[1].PlayState = "Auto play once"
				buffBase.Childs[1].Childs[1].Effects[1].ResetPlayOnce = true
				self.cl.newPerks[key] = nil
			else
				buffBase.Childs[1].Childs[1].Effects[1].PlayState = "Auto play off"
			end
		end

		while #BuffHolderChilds > count do
			table.remove( BuffHolderChilds )
		end
		
		if self.cl.statusPanelGui then
			self.cl.statusPanelGui:render( StatusPanelGui.root )
		end
		if self.cl.oxygenPanelGui then
			self.cl.oxygenPanelGui:render( OxygenPanelGui.root )
		end
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
	if character then
		local isDiving = character:isDiving() and not ( character:getLockingInteractable() and isAnyOf( character:getLockingInteractable().shape.uuid, SubmersibleSeats ) )
		if isDiving and self.sv.saved.enableHealth then
			self.sv.saved.stats.breath = math.max( self.sv.saved.stats.breath - BreathLostPerTick, 0 )
			if self.sv.saved.stats.breath == 0 then
				self.sv.drownTimer:tick()
				if self.sv.drownTimer:done() then
					if self.sv.saved.isConscious then
						print( "'SurvivalPlayer' is drowning!" )
						self:sv_takeDamage( DrownDamage, "drown" )
					end
					self.sv.drownTimer:start( DrownDamageCooldown )
				end
			end
		else
			if self.sv.saved.stats.breath == 0 then
				sm.effect.playEffect( "Mechanic - Exhausted", self.player.character.worldPosition )
			end
			self.sv.saved.stats.breath = self.sv.saved.stats.maxbreath
			self.sv.drownTimer:start( DrownDamageCooldown )
		end

		if g_enableCharacterHealing then
			self.sv.statsTimer:tick()
			if self.sv.statsTimer:done() then
				self.sv.statsTimer:start( StatsTickRate )

				self.sv.saved.stats.hp = math.min( self.sv.saved.stats.hp + HpRecovery, self.sv.saved.stats.maxhp )

				self.storage:save( self.sv.saved )
				self.network:setClientData( self.sv.saved )
			end
		end
	end
end

local DamageSourceToEvent = {
	-- standard
	["drown"] = "drown",
	["fatigue"] = "fatigue",
	["shock"] = "shock",
	["impact"] = "impact",
	["fire"] = "fire",
	["poison"] = "poison",
	-- custom
	["scannerbot"] = "impact",
	["minerbotprojectile"] = "shock",
	["minerbotexplosion"] = "impact",
	["tapebotprojectile"] = "shock"
}

local SeatSafeDamageSources = {
	["fatigue"] = true,
	["scannerbot"] = true,
	["minerbotprojectile"] = true,
	["minerbotexplosion"] = true,
	["tapebotprojectile"] = true
}

local function GetDamageEvent( source )
	if DamageSourceToEvent[source] then
		return DamageSourceToEvent[source]
	end
	return "impact"
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

		if self.sv.saved.enableHealth then
			if self.sv.saved.isConscious and self.sv.damageCooldown:done() then
				self.sv.saved.stats.hp = math.max( self.sv.saved.stats.hp - damage, 0 )
				print( "'Player' took:", damage, "damage.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP" )

				if source then
					local event = GetDamageEvent(source)
					self.network:sendToClients( "cl_n_onEvent", { event = event, pos = character:getWorldPosition(), damage = damage * 0.01 } )
				else
					self.player:sendCharacterEvent( "hit" )
				end

				if self.sv.saved.stats.hp <= 0 then
					print( "'Player' knocked out!" )
					self.sv.respawnInteractionAttempted = false
					self.sv.saved.isConscious = false
					character:setTumbling( true )
					character:setDowned( true )
					sm.effect.playEffect( "Mechanic - Ko", character.worldPosition )
				end

				self.storage:save( self.sv.saved )
				self.network:setClientData( self.sv.saved )
			end

			local isSeatSafeDamage = SeatSafeDamageSources[source] or false
			if not isSeatSafeDamage then
				if self.sv.saved.isConscious then
					local lockingInteractable = character:getLockingInteractable()
					if lockingInteractable and lockingInteractable:hasSeat() then
						lockingInteractable:setSeatCharacter( character )
					end
				end
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

function Player:sv_e_enableHealth( enableHealth )
	if enableHealth == nil then
		self.sv.saved.enableHealth = not self.sv.saved.enableHealth
	else
		self.sv.saved.enableHealth = enableHealth
	end

	self.network:setClientData( self.sv.saved )
end