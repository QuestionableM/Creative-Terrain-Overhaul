dofile( "$GAME_DATA/Scripts/game/BasePlayer.lua" )
Player = class( BasePlayer )

function Player:sv_e_onSpawnCharacter()
	print("Player:sv_e_onSpawnCharacter")
	sm.event.sendToGame("sv_e_onSpawnPlayerCharacter", self.player)
end