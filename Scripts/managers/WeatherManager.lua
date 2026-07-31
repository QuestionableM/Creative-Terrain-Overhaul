dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
WeatherManager = class( nil )

local WeatherSettings = dofile( "$GAME_DATA/Weather/main.weather" )

local CONDITION_DURATION = ( 1.0 / 4.0 );
local CONDITION_TRANSITION = ( CONDITION_DURATION / 5.0 );
local WEATHER_START_OFFSET = ( CONDITION_DURATION / 2.0 );
local RainDirection = sm.vec3.new( 0, -0.25, -0.95 )

function GetForecastProbabilitySum()
	local total = 0
	for _, forecast in pairs( WeatherSettings.forecasts ) do
		total = total + forecast.probability
	end
	return total
end

function GetRandomForecast()
	local rand = math.random() * GetForecastProbabilitySum()
	local total = 0
	for name, forecast in pairs( WeatherSettings.forecasts ) do
		total = total + forecast.probability
		if rand <= total then
			return name
		end
	end
	return "forecast"
end

function GetRandomCondition()
	local count = 0
	for name, _ in pairs( WeatherSettings.conditions ) do
		count = count + 1
	end
	local rand = math.random() * count
	local total = 0
	for name, _ in pairs( WeatherSettings.conditions ) do
		total = total + 1
		if rand <= total then
			return name
		end
	end
	return "condition"
end

function WeatherManager.Get()
	return W_weatherManagerClient;
end

function WeatherManager.sv_addForecast( self, forecastName )
	local forecast = WeatherSettings.forecasts[forecastName] or WeatherSettings.forecasts["DefaultDay"]
	for i = 1, ( math.ceil( #forecast.timeline/4 ) * 4 ) do
		local index = i <= #forecast.timeline and i or #forecast.timeline
		self.sv.saved.conditionsQueue[#self.sv.saved.conditionsQueue+1] = forecast.timeline[index].condition;
	end
	self.sv.isDirty = true
end

function WeatherManager.server_onCreate( self )
	W_weatherManagerServer = self
	self.sv = {}
	self.sv.timeOfDay = 0.0
	self.sv.currentConditionName = "Clouds01"
	self.sv.permanentForecast = self.params and self.params.permanentForecast
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_WEATHER ) or {}
	if self.params and self.params.resetForecast then
		self.sv.saved.conditionsQueue = {}
		self:sv_addForecast( self.sv.permanentForecast or "DefaultDay" )
	elseif self.sv.saved.conditionsQueue == {} or self.sv.saved.conditionsQueue == nil then
		self.sv.saved.conditionsQueue = {}
		self:sv_addForecast( self.sv.permanentForecast or "DefaultDay" )
	end
	if self.sv.saved.todOffset == nil then
		self.sv.saved.todOffset = 0
	end
	if self.sv.saved.cloudScroll == nil then
		self.sv.saved.cloudScroll = sm.vec3.new( -100000, -100000, -100000 )
		self.sv.saved.cloudScrollRotation = sm.vec3.new( -100000, -100000, -100000 )
	elseif self.sv.saved.cloudScroll:length2() > 2000000 * 2000000 or self.sv.saved.cloudScrollRotation:length2() > 2000000 * 2000000 then
		-- resets before the values hit float errors
		self.sv.saved.cloudScroll = sm.vec3.new( -100000, -100000, -100000 )
		self.sv.saved.cloudScrollRotation = sm.vec3.new( -100000, -100000, -100000 )
	end
	sm.storage.save( STORAGE_CHANNEL_WEATHER, self.sv.saved )
	self:sv_updateClientData()
	self.network:sendToClients( "cl_n_updateCloudScroll", { cloudScroll = self.sv.saved.cloudScroll, cloudScrollRotation = self.sv.saved.cloudScrollRotation } )
end

function WeatherManager.sv_setTimeOfDay( self, timeOfDay )
	self.sv.timeOfDay = timeOfDay;
end

function WeatherManager.Sv_SetTimeOfDay( timeOfDay )
	if W_weatherManagerServer then
		W_weatherManagerServer:sv_setTimeOfDay( timeOfDay )
	end
end

function WeatherManager.sv_startCondition( self, condition )
	self.sv.saved.conditionsQueue = { condition, condition, condition, condition }
	self.sv.saved.todOffset = self.sv.timeOfDay + WEATHER_START_OFFSET - CONDITION_TRANSITION
	self.sv.isDirty = true
	self:sv_updateClientData()
end

function WeatherManager.Sv_StartCondition( condition )
	if W_weatherManagerServer then
		sm.event.sendToScriptableObject( W_weatherManagerServer.scriptableObject, "sv_e_startCondition", condition )
	end
end

function WeatherManager.sv_e_startCondition( self, condition )
	self:sv_startCondition( condition )
end

function WeatherManager.sv_startForecast( self, forecast )
	self.sv.saved.conditionsQueue = {}
	self:sv_addForecast( forecast )
end

function WeatherManager.sv_startRandomForecast( self )
	self.sv.saved.conditionsQueue = {}
end

function WeatherManager.sv_startRandomCondition( self )
	self.sv.saved.conditionsQueue = { GetRandomCondition(), GetRandomCondition(), GetRandomCondition(), GetRandomCondition() }
end

function WeatherManager.sv_nextDay( self )
	for _ = 1, 4 do
		table.remove( self.sv.saved.conditionsQueue, 1 )
	end
	self.sv.isDirty = true
end

function WeatherManager.sv_report( self )
	local report = ""
	for i, conditions in ipairs( self.sv.saved.conditionsQueue ) do
		if ( (i-1) % 4 ) == 0 then
			if (i-1) == 0 then
				report = report .. "today: "
			else
				report = report .. "\n day(" .. ( ( (i-1) / 4 ) + 1 ) .. "): "
			end
		end
		report = report .. conditions .. ", " 
	end
	return report
end

function WeatherManager.Sv_PlayerJoined( player )
	if W_weatherManagerServer then
		sm.event.sendToScriptableObject( W_weatherManagerServer.scriptableObject, "sv_e_playerJoined", player )
	end
end

function WeatherManager.sv_e_playerJoined( self, player )
	self.network:sendToClient( player, "cl_n_updateCloudScroll", { cloudScroll = self.sv.saved.cloudScroll, cloudScrollRotation = self.sv.saved.cloudScrollRotation } )
end

function WeatherManager.Sv_GetExtinguishFires()
	if W_weatherManagerServer then
		return W_weatherManagerServer:sv_getExtinguishFires()
	end
	return false
end

function WeatherManager.sv_getExtinguishFires( self )
	local condition = WeatherSettings.conditions[self.sv.currentConditionName]
	if condition then
		return condition.extinguishFires or false
	end
	return false
end

function WeatherManager.Sv_GetRainDirection()
	if W_weatherManagerServer then
		return W_weatherManagerServer:sv_getRainDirection()
	end
	return sm.vec3.new( 0, 0, -1 )
end

function WeatherManager.sv_getRainDirection( self )
	return RainDirection
end

function WeatherManager.Sv_IsRaining()
	if W_weatherManagerServer then
		return W_weatherManagerServer:sv_isRaining()
	end
	return false
end

function WeatherManager.sv_isRaining( self )
	local condition = WeatherSettings.conditions[self.sv.currentConditionName]
	if condition then
		return ( condition.rainAmount or 0 ) > 0
	end
	return false
end

-- Client

function WeatherManager.client_onCreate( self )
	W_weatherManagerClient = self
	self.cl = {}
	self.cl.timeOfDay = 0.0
	self.cl.cloudScroll = sm.vec3.zero()
	self.cl.cloudScrollRotation = sm.vec3.zero()
	self.cl.lastRainAmount = 0.0
	self.cl.lastWind = 0.0

	sm.audio.setGlobalParameter( "floatRainAmount", 0.0 );
	sm.audio.setGlobalParameter( "wind", 0.0 );
end

function WeatherManager.cl_updateEffect( self, activeEffect, effects, scene, world )
	for _, effect in pairs( effects ) do
		effect.active = false
	end

	for _, name in pairs( activeEffect ) do
		if name ~= "" then			
			if not effects[name] then
				effects[name] = {}
				if scene == "sky" then
					effects[name].effect = sm.effect.createEffectSky( name )
					effects[name].effect:setWorld( world )
				elseif scene == "2D" then
					effects[name].effect = sm.effect.createEffect2D( name )
				else
					effects[name].effect = sm.effect.createEffect( name )
					effects[name].effect:setWorld( world )
				end
			end
			effects[name].active = true
		end
	end

	for _, effect in pairs( effects ) do
		if effect.effect then
			if effect.active then
				if not effect.effect:isPlaying() then
					effect.effect:start()
				end
			else
				if effect.effect:isPlaying() then
					if scene == "sky" then
						effect.effect:stopImmediate()
					else
						effect.effect:stop()
					end
				end
			end
		end
	end
end

function WeatherManager.server_onUnload( self )
	sm.storage.save( STORAGE_CHANNEL_WEATHER, self.sv.saved )
end

function WeatherManager.server_onFixedUpdate( self )
	local todDelta = ( self.sv.timeOfDay + WEATHER_START_OFFSET ) - self.sv.saved.todOffset
	while todDelta >= ( CONDITION_DURATION * 6 ) do
		for _ = 1, 4 do
			table.remove( self.sv.saved.conditionsQueue, 1 )
			self.sv.saved.todOffset = self.sv.saved.todOffset + CONDITION_DURATION
		end
		self.sv.isDirty = true
		todDelta = ( self.sv.timeOfDay + WEATHER_START_OFFSET ) - self.sv.saved.todOffset
	end

	local conditionAName, conditionBName, progress = self.getConditionsAndProgress( self.sv.timeOfDay, self.sv.saved )

	if self.sv.currentConditionName ~= conditionAName then
		self.sv.currentConditionName = conditionAName
	end

	local conditionA = WeatherSettings.conditions[conditionAName] or WeatherSettings.conditions["Clouds01"]
	local conditionB = WeatherSettings.conditions[conditionBName] or WeatherSettings.conditions["Clouds01"]
	local cloudScroll = sm.vec3.lerp( conditionA.cloudScroll, conditionB.cloudScroll, progress )
	local cloudScrollRotation = sm.vec3.lerp( conditionA.cloudScrollRotation, conditionB.cloudScrollRotation, progress )

	self.sv.saved.cloudScroll = self.sv.saved.cloudScroll + ( cloudScroll * 1 / 40 )
	self.sv.saved.cloudScrollRotation = self.sv.saved.cloudScrollRotation + ( cloudScrollRotation * 1 / 40 )

	while #self.sv.saved.conditionsQueue < 8 do
		self:sv_addForecast( self.sv.permanentForecast or GetRandomForecast() )
	end

	if self.sv.isDirty then
		sm.storage.save( STORAGE_CHANNEL_WEATHER, self.sv.saved )
		self:sv_updateClientData()
		self.sv.isDirty = false
	end
end

function WeatherManager.sv_updateClientData( self )
	local clientData = {
		conditionsQueue = self.sv.saved.conditionsQueue,
		todOffset = self.sv.saved.todOffset
	}
	self.network:setClientData( clientData )
end

function WeatherManager.client_onClientDataUpdate( self, clientData )
	self.cl.clientData = clientData
end

function WeatherManager.cl_n_updateCloudScroll( self, cloudData )
	self.cl.cloudScroll = cloudData.cloudScroll
	self.cl.cloudScrollRotation = cloudData.cloudScrollRotation
end

function WeatherManager:cl_restartEffects(effectTable, newWorld)
	for k, v in pairs(effectTable) do
		local curEffect = v.effect
		if sm.exists(curEffect) then
			if curEffect:isPlaying() then
				curEffect:stopImmediate()
			end

			curEffect:setWorld(newWorld)
		end

		v.active = false
	end
end

function WeatherManager.client_onUpdate( self, dt )

	if self.cl.clientData == nil then
		return
	end

	local conditionAName, conditionBName, progress = self.getConditionsAndProgress( self.cl.timeOfDay, self.cl.clientData )

	local conditionA = WeatherSettings.conditions[conditionAName] or WeatherSettings.conditions["Clouds01"]
	local conditionB = WeatherSettings.conditions[conditionBName] or WeatherSettings.conditions["Clouds01"]

	local cloudCoverage = lerp( conditionA.cloudCoverage, conditionB.cloudCoverage, progress )
	local cloudHeight = lerp( conditionA.cloudHeight, conditionB.cloudHeight, progress )
	local cloudScroll = sm.vec3.lerp( conditionA.cloudScroll, conditionB.cloudScroll, progress )
	local cloudScrollRotation = sm.vec3.lerp( conditionA.cloudScrollRotation, conditionB.cloudScrollRotation, progress )
	local cloudTallnessScale = lerp( conditionA.cloudTallnessScale, conditionB.cloudTallnessScale, progress )
	local lightMod = lerp( conditionA.lightMod, conditionB.lightMod, progress )

	local rainAmount
	if conditionA.rainAmount == 0 then
		rainAmount = conditionA.rainAmount
	else
		rainAmount = lerp( conditionA.rainAmount, conditionB.rainAmount, progress )
	end
	
	
	local wind = lerp( conditionA.wind, conditionB.wind, progress )
	local world = WorldManager.Cl_GetWorld( "weatherworld" )
	if world then

		self.cl.skyEffects = self.cl.skyEffects or {}
		self:cl_updateEffect( conditionA.skyEffects, self.cl.skyEffects, "sky", world )

		self.cl.effects2D = self.cl.effects2D or {}
		self:cl_updateEffect( conditionA.effects2D, self.cl.effects2D, "2D", world )

		self.cl.normalEffects = self.cl.normalEffects or {}
		self:cl_updateEffect( conditionA.normalEffects, self.cl.normalEffects, "", world )

		-- update normalEffects positions
		local camPos = sm.camera.getDefaultPosition();
		local maxDistance = 40
		local minDistance = 15
		local length = minDistance
		local forward = sm.camera.getDirection()
		forward = sm.vec3.safeNormalize( forward, sm.vec3.new( 0, 0, 1 ) )
		forward.z = 0

		local myCharacter = sm.localPlayer.getPlayer().character
		if sm.exists( myCharacter ) then
			local velocity = myCharacter.velocity
			
			if myCharacter:isSeated() then
				if velocity.z > 0 then
					velocity.z = 0
				end
				forward = sm.vec3.safeNormalize( velocity, forward )
			end
			length = clamp( myCharacter.velocity:length(), minDistance, maxDistance )
		end
		local pos = camPos + forward * length
		
		for _, effect in pairs( self.cl.normalEffects ) do
			effect.effect:setPosition( pos )
		end

		local activeSkyEffects = {}
		local activeNormalEffects = {}
		local wrappedTod = math.fmod( self.cl.timeOfDay, 1.0 )
		for _, tod in ipairs( WeatherSettings.timeOfDayEffects ) do
			local inTime = false
			if tod.startTime > tod.endTime then
				inTime = wrappedTod > tod.startTime or wrappedTod < tod.endTime
			else
				inTime = wrappedTod > tod.startTime and wrappedTod < tod.endTime
			end
			if inTime then
				if tod.skyEffect and tod.skyEffect ~= "" then
					activeSkyEffects[#activeSkyEffects+1] = tod.skyEffect
				end
				if tod.normalEffect and tod.normalEffect ~= "" then
					activeNormalEffects[#activeNormalEffects+1] = tod.normalEffect
				end
			end
		end
		self.cl.todSkyEffects = self.cl.todSkyEffects or {}
		self:cl_updateEffect( activeSkyEffects, self.cl.todSkyEffects, "sky", world )
		
		self.cl.todNormalEffects = self.cl.todNormalEffects or {}
		self:cl_updateEffect( activeNormalEffects, self.cl.todNormalEffects, "", world )

		if rainAmount ~= self.cl.lastRainAmount then
			sm.audio.setGlobalParameter( "floatRainAmount", rainAmount );
			self.cl.lastRainAmount = rainAmount
		end
		if wind ~= self.cl.lastWind then
			sm.audio.setGlobalParameter( "wind", wind );
			self.cl.lastWind = wind
		end
		
		if not self.rainEffect then
			self.rainEffect = sm.effect.createEffect( "Weather - Audio" )
			self.rainEffect:setWorld( world )
			if not self.rainEffect:isPlaying() then
				self.rainEffect:start()
			end
        end

        if self.currentWorld ~= world then
			if self.currentWorld ~= nil then
				self:cl_restartEffects(self.cl.skyEffects, world)
				self:cl_restartEffects(self.cl.effects2D, world)
				self:cl_restartEffects(self.cl.normalEffects, world)
				self:cl_restartEffects(self.cl.todSkyEffects, world)
				self:cl_restartEffects(self.cl.todNormalEffects, world)

                if self.rainEffect and sm.exists(self.rainEffect) then
                    if self.rainEffect:isPlaying() then
                        self.rainEffect:stopImmediate()
                    end

                    self.rainEffect:destroy()
                    self.rainEffect = nil
                end
			end

			self.currentWorld = world
		end
	end

	self.cl.cloudScroll = self.cl.cloudScroll + ( cloudScroll * dt )
	self.cl.cloudScrollRotation = self.cl.cloudScrollRotation + ( cloudScrollRotation * dt )

	sm.render.setCloudSettings( cloudCoverage, cloudHeight, 15000.0, cloudTallnessScale, lightMod, self.cl.cloudScroll, self.cl.cloudScrollRotation );
end

function WeatherManager.cl_setTimeOfDay( self, timeOfDay )
	self.cl.timeOfDay = timeOfDay;
end

function WeatherManager.getConditionsAndProgress( timeOfDay, clientData )

	local conditionAName = "Clouds01"
	local conditionBName = "Clouds01"
	local progress = 0.0

	local todDelta = ( timeOfDay + WEATHER_START_OFFSET ) - clientData.todOffset
	for i = 1, #clientData.conditionsQueue do
		local offset = ( i * CONDITION_DURATION )
		if todDelta < offset then

			local time = ( todDelta - ( ( i - 1 ) * CONDITION_DURATION ) );

			if time < CONDITION_TRANSITION then
				conditionAName = clientData.conditionsQueue[i-1]
				conditionBName = clientData.conditionsQueue[i]
				progress = 0.5 + ( ( time / CONDITION_TRANSITION ) * 0.5 )
			else
				conditionAName = clientData.conditionsQueue[i]
				conditionBName = clientData.conditionsQueue[i+1]
				if time >= ( CONDITION_DURATION - CONDITION_TRANSITION ) then
					progress = ( ( time - ( CONDITION_DURATION - CONDITION_TRANSITION ) ) / CONDITION_TRANSITION ) * 0.5
				end
			end
			break;
		end
	end

	progress = sm.util.clamp( progress, 0.0, 1.0 )

	return conditionAName, conditionBName, progress
end

function WeatherManager.client_onDestroy( self )
	if sm.exists( self.rainEffect ) then
		self.rainEffect:stop()
		self.rainEffect:destroy()
		self.rainEffect = nil
	end
end