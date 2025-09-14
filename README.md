![PreviewImage](https://github.com/QuestionableM/Creative-Terrain-Overhaul/blob/main/preview.jpg)
# Creative Terrain Overhaul
A fully functional copy of Scrap Mechanic Creative Game, but with better terrain generation and bigger world to explore.

![Steam Downloads](https://img.shields.io/steam/downloads/2839940307?style=for-the-badge)<br/>
[Steam Workshop Link](https://steamcommunity.com/sharedfiles/filedetails/?id=2839940307)

# Available Commands
```
/clear - Removes all the loaded bodies in the world.
/spawn - Teleports your character to spawn position.
/tp [player_id] - Teleports your character to selected player.
/playerlist - Displays the list of all players in the world.
/timeset [time from 0.0 to 1.0] - Sets the current time.
/timeprogress [bool (optional)] - Stops the time when set to false.
/fly - Toggles fly mode for your character.
/seed - Shows the seed and version of the current terrain generation.
/noaggro [bool (optional)] - Toggles the player as a target.
/noaggrocreations [bool (optional)] - Toggles whether the Tapebots will shoot at creations.
/popcapsules [filter (optional)] - Opens all capsules. An optional filter controls which type of capsules to open: 'bot', 'animal'.
/aggroall - All hostile units will be made aware of the player's position.
/killall - Kills all spawned units.
/dropscrap [bool (optional)] - Toggles the scrap loot from Haybots.
/place [harvestable] - Places a harvestable at the aimed position. Must be placed on the ground. The harvestable parameter controls which harvestable to place: 'stone', 'tree', 'birch', 'leafy', 'spruce', 'pine'.
/enablehealth - Makes your character receive damage.
/die - Kills your character if your health is enabled.
/spawnpoint - Sets a location at which the character is respawned after death.
/ragdoll - Sets your character into a ragdoll state.
/damage [(int)damage] - Damages your character if health is enabled.
```

# Host Only Commands
```
/regenerate [version (auto = 0)] [seed (optional)] - Regenerates the world with the specified parameters.
/import [creation_name] - Imports a creation from survival files and custom game files.
/export [creation_name] - Exports the creation you're currently looking at.
/enablehealing [bool (optional)] - Toggles the healing for all the characters in the world.
```

Have Fun :)

Preview image was created by [Dart Frog](https://steamcommunity.com/profiles/76561198318189561)
