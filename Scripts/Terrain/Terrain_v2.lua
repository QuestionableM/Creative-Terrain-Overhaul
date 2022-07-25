--[[
	Copyright (c) 2022
	Questionable Mark
]]

dofile("$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua")

local WORLD_HEIGHT_OFFSET = 200

function Init()
	print("Init Terrain v2")

	g_terrainCellCacheX = {}
	g_terrainCellCacheY = {}
end

function InitTerrainSeedGlobals(seed)
	g_terrainSeed = seed
	g_terrainSeed_3 = g_terrainSeed + 3
	g_terrainSeed_4 = g_terrainSeed + 4
	g_terrainSeed_5 = g_terrainSeed + 5
	g_terrainSeed_10 = g_terrainSeed + 10
	g_terrainSeed_12 = g_terrainSeed + 12
	g_terrainSeed_45 = g_terrainSeed + 45
	g_terrainSeed_58 = g_terrainSeed + 58
	g_terrainSeed_59 = g_terrainSeed + 59
	g_terrainSeed_92 = g_terrainSeed + 92
	g_terrainSeed_192 = g_terrainSeed + 192
	g_terrainSeed_371 = g_terrainSeed + 371
	g_terrainSeed_712 = g_terrainSeed + 712
	g_terrainSeed_981 = g_terrainSeed + 981
end

function Create( xMin, xMax, yMin, yMax, seed, data )
	InitTerrainSeedGlobals(seed)
	sm.terrainData.save(seed)
end

function Load()
	if sm.terrainData.exists() then
		local saved_seed = sm.terrainData.load()
		InitTerrainSeedGlobals(saved_seed)
		
		return true
	end

	return false
end

function GetTilePath( uid )
	return ""
end

local _util_clamp = sm.util.clamp
local _sm_noise_octaveNoise2d = sm.noise.octaveNoise2d
local _math_abs = math.abs
local _math_min = math.min

--Height: terrain_height + mountain_height - water_noise
local function CalculateTerrainHeight(x, y)
	local x_h = x * 0.5
	local y_h = y * 0.5

	--Water Noise
	local water_noise = _math_abs(_sm_noise_octaveNoise2d(x_h, y_h, 12, g_terrainSeed)) * 100

	--Calculate Terrain Height
	local height_limiter = _sm_noise_octaveNoise2d(x_h, y_h, 9, g_terrainSeed) * 3
	local height_final = height_limiter * (_sm_noise_octaveNoise2d(x, y, 10, g_terrainSeed_10) * 50)

	--Calculate Mountain Height
	if height_limiter > 0.05 then --Skip mountain calculations if height_limiter < 0.05
		local clamped_mountains = _math_min(height_limiter - 0.05, 1) * 500
		local mountain_limiter = _sm_noise_octaveNoise2d(x, y, 10, g_terrainSeed) * clamped_mountains
		local mountain_height = _util_clamp(_sm_noise_octaveNoise2d(x * 0.2, y * 0.2, 7, g_terrainSeed) * mountain_limiter, 0, 500)

		height_final = height_final + mountain_height
	end

	return _util_clamp(height_final - water_noise, -50, 1000)
end

local function isInWaterHeight(height)
	return (height < -15)
end

function GetHeightAt( x, y, lod )
	return CalculateTerrainHeight(x, y)
end

local FAR_LANDS_START = 6460
local function isInFarLands(x, y)
	return (_math_abs(x) > FAR_LANDS_START or _math_abs(y) > FAR_LANDS_START)
end

local _sm_vec3_cross = sm.vec3.cross
local _sm_vec3_normalize = sm.vec3.normalize
local _sm_vec3_new = sm.vec3.new
local _sm_vec3_dot = sm.vec3.dot
local function NormalFrom3Points(a_vec, b_vec, c_vec)
	local dir = _sm_vec3_cross(b_vec - a_vec, c_vec - a_vec)
	return _sm_vec3_normalize(dir)
end

local function HeightAndPosToNormal(global_x, global_y, height)
	local point_1 = _sm_vec3_new(global_x, global_y, height)

	--Point 2
	local pt2_x = global_x + 0.25
	local pt2_y = global_y + 0.25
	local pt2_height = CalculateTerrainHeight(pt2_x, pt2_y)
	local point_2 = _sm_vec3_new(pt2_x, pt2_y, pt2_height)

	--Point 3
	local pt3_x = global_x + 0.25
	local pt3_height = CalculateTerrainHeight(pt3_x, global_y)
	local point_3 = _sm_vec3_new(pt3_x, global_y, pt3_height)

	return NormalFrom3Points(point_1, point_2, point_3)
end

local _up_direction = _sm_vec3_new(0, 0, 1)
local function isTooSteep(x, y, height)
	local ground_normal = HeightAndPosToNormal(x, y, height)
	local normal_dot = _sm_vec3_dot(ground_normal, _up_direction)

	return (normal_dot > -0.8)
end

function GetColorAt( x, y, lod )
	if isInFarLands(x, y) then
		return 0.8, 0.8, 0.8
	end

	local l_height = CalculateTerrainHeight(x, y)
	if isInWaterHeight(l_height) then
		local _noise = _sm_noise_octaveNoise2d(x, y, 6, g_terrainSeed) * 0.15
		return 0.71 + _noise, 0.753 + _noise, 0.788 + _noise
	end

	if isTooSteep(x, y, l_height) then
		return 0.859, 0.859, 0.855
	end

	local grass_noise = _sm_noise_octaveNoise2d(x, y, 6, g_terrainSeed) * 0.1 + 0.851
	return grass_noise, grass_noise, grass_noise
end

function GetMaterialAt( x, y, lod )
	if isInFarLands(x, y) then
		return 0, 1, 0, 0, 0, 0, 0, 0
	end

	local mat_height = CalculateTerrainHeight(x, y)
	if isInWaterHeight(mat_height) then
		return 0, 1, 0, 0, 0, 0, 0, 0
	end

	if isTooSteep(x, y, mat_height) then
		return 1, 0, 0, 0, 0, 0, 0, 0
	end

	return 0, 0, 0, 0, 0, 0, 0, 0
end

local ground_clutter = { -1, 9, 0, 15, 19, 14, 20, 22 }
local underwater_clutter =
{
	--id -> max_height
	--{ 18, -470 },
	{ -1, 0 },
	{ 39, -474 },
	{ 40, -476 },
	{ 41, -500 }
}

local ground_clutter_sz = #ground_clutter
local underwater_clutter_sz = #underwater_clutter

--36 37
function GetClutterIdxAt( x, y )
	local d_x = x * 0.5
	local d_y = y * 0.5

	if isInFarLands(d_x, d_y) then
		return -1
	end

	local clutter_height = CalculateTerrainHeight(d_x, d_y)
	if isTooSteep(d_x, d_y, clutter_height) then
		return -1
	end

	if isInWaterHeight(clutter_height) then
		local underwater_clutter_noise = _sm_noise_octaveNoise2d(x * 2.832, y * 2.832, 11, g_terrainSeed)
		local clutter_idx = math.floor(underwater_clutter_noise * 23.129) % underwater_clutter_sz
		local cur_clutter_data = underwater_clutter[clutter_idx + 1]

		--Compare max height with current height
		if cur_clutter_data[2] > clutter_height then
			return cur_clutter_data[1]
		end

		return -1
	end

	local clutter_noise = _sm_noise_octaveNoise2d(x, y, 12, g_terrainSeed_59) * _sm_noise_octaveNoise2d(x, y, 11, g_terrainSeed_4)
	local clutter_idx = math.floor(clutter_noise * 42.234) % ground_clutter_sz

	return ground_clutter[clutter_idx + 1]
end

local ground_asset_list =
{
	{ sm.uuid.new("4bd88efa-949c-4c0b-8517-2f2b1b2bdb01"), { 0xb0a926ff, 0xf1e929ff, 0xf1ac28ff, 0xcd7d00ff, 0xf5de00ff, 0xf5de00ff, 0xbef319ff }, 7, { leaves = 0 } }, --env_foliage_smallbirch01
	{ sm.uuid.new("f741ad80-c99a-4cec-b67d-e53ec82a7bd0"), { 0xb0a926ff, 0xf1e929ff, 0xf1ac28ff, 0xcd7d00ff, 0xf5de00ff, 0xf5de00ff, 0xbef319ff }, 7, { leaves = 0 } }, --env_foliage_smallbirch02
	{ sm.uuid.new("09a5a0ee-0fd1-4b32-86c0-9e6f2b701546"), { 0x097b81ff, 0x12784eff, 0x0c8120ff, 0x4cc569ff, 0x32931aff, 0xa3d821ff, 0xd8bc21ff, 0xd83f21ff }, 8, { leaves = 0 } }, --env_nature_foliage_wildbush01
	{ sm.uuid.new("b1e1b1bf-6175-465e-81c6-9ec9d0bf83d0"), { 0x097b81ff, 0x12784eff, 0x0c8120ff, 0x4cc569ff, 0x32931aff, 0xa3d821ff, 0xd8bc21ff, 0xd83f21ff }, 8, { leaves = 0 } }, --env_nature_foliage_wildbush02
	{ sm.uuid.new("796cabcd-5703-42af-b4e9-512c85abcf59"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus01
	{ sm.uuid.new("df1a36a3-6be0-4681-845e-d89d6c80d1a6"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus02
	{ sm.uuid.new("73acaa1d-d208-450b-8159-99d5914bbcde"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff }, 10, { leaves = 0 } }, --env_nature_foliage_buxus03
	{ sm.uuid.new("c63b9bff-0c25-460b-a1a3-af3161592170"), { 0x5b7f13ff, 0x678f0aff, 0x317f0fff, 0x0f7f52ff, 0x0f7f23ff, 0x3f5900ff, 0x576828ff, 0x636d48ff, 0x66552cff, 0x592300ff, 0x593e00ff }, 11, { leaves = 0 } }, --env_nature_foliage_boxwood
	{ sm.uuid.new("fd3844b5-58eb-4cb0-96d6-383b7fa83923"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff, 0x8bad02ff, 0x8bad02ff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }, --env_nature_foliage_columnshrub01
	{ sm.uuid.new("fe134420-39cb-450b-9560-5d3401556f7a"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff, 0x8bad02ff, 0x8bad02ff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }, --env_nature_foliage_columnshrub02
	{ sm.uuid.new("40ff23e6-3914-4d85-9048-fe012f72cba1"), { 0x0c7d35ff, 0x499931ff, 0x2c7f0fff, 0x5b7f13ff, 0x5c7c23ff, 0x75a80fff, 0x797f12ff, 0xa8850fff, 0x7f4b0fff, 0x7f0f23ff, 0x8bad02ff, 0x8bad02ff, 0xb1a803ff, 0xa1bc05ff }, 14, { leaves = 0 } }  --env_nature_foliage_columnshrub03
}

local ground_rock_list =
{
	{ sm.uuid.new("18d95c10-63a3-40a5-8edc-dc062d547b70"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock01
	{ sm.uuid.new("194e7c7f-26de-48a1-b8ee-775e68100ed1"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock02
	{ sm.uuid.new("6e8d9830-c956-4b1a-bb3e-bdf724ced968"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock03
	{ sm.uuid.new("dabe4e2b-f8f6-49df-8f20-6e31999c887d"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock04
	{ sm.uuid.new("84b1af25-76ce-48a5-8049-2f042e76985f"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock05
	{ sm.uuid.new("1454cc81-b071-48f2-bf50-8a0d8b93e393"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock06
	{ sm.uuid.new("2161d53a-1166-400f-a692-7055865d9fb9"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock07
	{ sm.uuid.new("388fdf39-b223-4649-aceb-eb609aee87ef"), {}, 0, { rock = 0x6e7569ff } }, --env_rocks_rock08
}

local ground_asset_list_sz = #ground_asset_list
local ground_rock_list_sz = #ground_rock_list

function AssetNoise(x, y)
	return _sm_noise_octaveNoise2d(x * 0.854, y * 0.854, 1, g_terrainSeed_92) *
		_sm_noise_octaveNoise2d(x * 1.2, y * 1.2, 2, g_terrainSeed_371)
end

local water_asset_uuid = sm.uuid.new( "990cce84-a683-4ea6-83cc-d0aee5e71e15" )
local _table_insert = table.insert
local _water_quaternion = sm.quat.new( 0.7071067811865475, 0.0, 0.0, 0.7071067811865475 )
local _water_position = sm.vec3.new(32, 32, -33)
local _water_scale = sm.vec3.new(64, 30, 64)
function AddWaterAsset(table)
	_table_insert(table, {
		rot = _water_quaternion,
		pos = _water_position,
		scale = _water_scale,
		tags = {},
		uuid = water_asset_uuid
	})
end

local _asset_scale = sm.vec3.new(0.25, 0.25, 0.25)
function AddRandomAsset(table, x, y, z, x_local, y_local, ass_list, ass_list_sz)
	local hvs_data_noise = _sm_noise_octaveNoise2d(x * 3, y * 3, 1, g_terrainSeed_192)
	local hvs_data_idx = math.floor(hvs_data_noise * 42.83291) % ass_list_sz
	local cur_hvs_data = ass_list[hvs_data_idx + 1]

	local asset_col_table = cur_hvs_data[2]
	local asset_col_table_sz = cur_hvs_data[3]

	local color_idx = 0
	local color_data = {}
	for k, v in pairs(cur_hvs_data[4]) do
		if v == 0 then
			local color_noise = _sm_noise_octaveNoise2d(x * 2.12, y * 2.12, 1, g_terrainSeed + color_idx)
			local color_array_idx = math.floor(color_noise * 92.2832) % asset_col_table_sz

			color_data[k] = sm.color.new(asset_col_table[color_array_idx + 1])
		else
			color_data[k] = sm.color.new(v)
		end

		color_idx = color_idx + 1
	end

	_table_insert(table, {
		rot = _water_quaternion,
		pos = sm.vec3.new(x_local, y_local, z),
		scale = _asset_scale,
		tags = {},
		uuid = cur_hvs_data[1],
		colors = color_data
	})
end

function GetAssetsForCell( cellX, cellY, lod )
	local cell_assets = {}

	--Add water asset to each cell
	AddWaterAsset(cell_assets)

	local x_pos = cellX * 64
	local y_pos = cellY * 64

	--make 10 samples of random points and check if they actually have the fitting values to place a tree
	for iter = 0, 10 do
		local terrain_seed_iter = g_terrainSeed + iter

		local x_local = _math_abs(_sm_noise_octaveNoise2d(x_pos * 0.5, y_pos * 0.5, 1, terrain_seed_iter)) * 64
		local y_local = _math_abs(_sm_noise_octaveNoise2d(x_pos * 0.343, y_pos * 0.343, 1, terrain_seed_iter)) * 64

		local g_x = x_pos + x_local
		local g_y = y_pos + y_local

		local asset_height = CalculateTerrainHeight(g_x, g_y)
		if not isTooSteep(g_x, g_y, asset_height) then
			if isInWaterHeight(asset_height) then
				local asset_noise = AssetNoise(g_x, g_y)
				if asset_noise > 0.4 then
					AddRandomAsset(cell_assets, g_x, g_y, asset_height, x_local, y_local, ground_rock_list, ground_rock_list_sz)
				end	
			else
				local asset_noise = AssetNoise(g_x, g_y)
				if asset_noise > 0.3 then
					AddRandomAsset(cell_assets, g_x, g_y, asset_height, x_local, y_local, ground_asset_list, ground_asset_list_sz)
				end
			end
		end
	end

	return cell_assets
end

function GetNodesForCell( cellX, cellY )
	local cell_assets = {}

	_table_insert(cell_assets, {
		pos = _water_position,
		rot = _water_quaternion,
		scale = _water_scale,
		tags = { "WATER" }
	})

	return cell_assets
end

function GetCreationsForCell( cellX, cellY )
	return {}
end

local function HarvestableNoise(x, y)
	return
		_sm_noise_octaveNoise2d(x, y, 1, g_terrainSeed_3) *
		_sm_noise_octaveNoise2d(x, y, 2, g_terrainSeed_5) *
		_sm_noise_octaveNoise2d(x, y, 3, g_terrainSeed_10)
end

-- hvs_uuid, color_table, color_table_sz
local hvs_table =
{
	{ sm.uuid.new("c4ea19d3-2469-4059-9f13-3ddb4f7e0b79"), { 0xdb9819ff, 0xfb843cff, 0xdabd5cff, 0xd5bc36ff, 0xd0db18ff, 0xffe224ff, 0xe8b743ff }, 7 }, --harvestable_tree_birch01
	{ sm.uuid.new("711c3e72-7ba1-4424-ae70-c13d23afe818"), { 0xdb9819ff, 0xfb843cff, 0xdabd5cff, 0xd5bc36ff, 0xd0db18ff, 0xffe224ff, 0xe8b743ff }, 7 }, --harvestable_tree_birch02
	{ sm.uuid.new("a7aa52af-4276-4b2d-af44-36bc41864e04"), { 0xdb9819ff, 0xfb843cff, 0xdabd5cff, 0xd5bc36ff, 0xd0db18ff, 0xffe224ff, 0xe8b743ff }, 7 }, --harvestable_tree_birch03
	{ sm.uuid.new("91ec04ea-9bf7-4a9d-bb7f-3d0125ff78c7"), { 0x54c51eff, 0x54c51eff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x065437ff, 0x541805ff, 0x7c5e2080 }, 15 }, --harvestable_tree_leafy01
	{ sm.uuid.new("4d482999-98b7-4023-a149-d47be709b8f7"), { 0x54c51eff, 0x54c51eff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x065437ff, 0x541805ff, 0x7c5e2080 }, 15 }, --harvestable_tree_leafy02
	{ sm.uuid.new("3db0a60d-8668-4c8a-8dd2-f5ceb294977e"), { 0x54c51eff, 0x54c51eff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x68cf37ff, 0x9ebe2bff, 0x4a8725ff, 0x68cf37ff, 0x0c7638ff, 0x065437ff, 0x541805ff, 0x7c5e2080 }, 15 }, --harvestable_tree_leafy03
	{ sm.uuid.new("8411caba-63db-4b93-ad67-7ae8e350d360"), { 0x005705ff, 0x005705ff, 0x146137ff, 0x7f882fff, 0x4e7108ff, 0x1a6822ff, 0x1a6822ff, 0x1a6822ff, 0x005b1fff, 0x8f4d00ff, 0x005b2aff, 0x1a6822ff }, 12 }, --harvestable_tree_pine01
	{ sm.uuid.new("1cb503a4-9306-412f-9e13-371bc634af60"), { 0x005705ff, 0x005705ff, 0x146137ff, 0x7f882fff, 0x4e7108ff, 0x1a6822ff, 0x1a6822ff, 0x1a6822ff, 0x005b1fff, 0x8f4d00ff, 0x005b2aff, 0x1a6822ff }, 12 }, --harvestable_tree_pine02
	{ sm.uuid.new("fa864e51-67db-4ac9-823b-cfbdf523375d"), { 0x005705ff, 0x005705ff, 0x146137ff, 0x7f882fff, 0x4e7108ff, 0x1a6822ff, 0x1a6822ff, 0x1a6822ff, 0x005b1fff, 0x8f4d00ff, 0x005b2aff, 0x1a6822ff }, 12 }, --harvestable_tree_pine03
	{ sm.uuid.new("73f968f0-d3a3-4334-86a8-a90203a3a56d"), { 0x016401ff, 0x016401ff, 0x016401ff, 0x00763eff, 0x147900ff, 0x368f00ff, 0x368f00ff, 0x368f00ff, 0x4e7600ff, 0x646200ff, 0x00640aff }, 11 }, --harvestable_tree_spruce01
	{ sm.uuid.new("86324c5b-e97a-41f6-aa2c-7c6462f1f2e7"), { 0x016401ff, 0x016401ff, 0x016401ff, 0x00763eff, 0x147900ff, 0x368f00ff, 0x368f00ff, 0x368f00ff, 0x4e7600ff, 0x646200ff, 0x00640aff }, 11 }, --harvestable_tree_spruce02
	{ sm.uuid.new("27aa53ea-1e09-4251-a284-437f93850409"), { 0x016401ff, 0x016401ff, 0x016401ff, 0x00763eff, 0x147900ff, 0x368f00ff, 0x368f00ff, 0x368f00ff, 0x4e7600ff, 0x646200ff, 0x00640aff }, 11 } --harvestable_tree_spruce03
}

local hvs_table_sz = #hvs_table

local function AddHarvestable(table, x, y, z, x_local, y_local)
	--Pick a random harvestable uuid
	local hvs_noise = _sm_noise_octaveNoise2d(x, y, 4, g_terrainSeed_45)
	local hvs_index = math.floor(hvs_noise * 23) % hvs_table_sz
	local cur_hvs_data = hvs_table[hvs_index + 1]

	--Pick a random color for harvestable
	local hvs_color_noise = _sm_noise_octaveNoise2d(x, y, 1, g_terrainSeed_12)
	local hvs_color_noise_2 = _math_abs(_sm_noise_octaveNoise2d(x * 0.5, y * 0.5, 3, g_terrainSeed_981)) * 100
	local hvs_color_idx = math.floor(hvs_color_noise * hvs_color_noise_2) % cur_hvs_data[3]
	local hvs_color = sm.color.new(cur_hvs_data[2][hvs_color_idx + 1])

	--Create a random harvestable rotation
	local rotation_noise = _sm_noise_octaveNoise2d(x, y, 1, g_terrainSeed_58)
	local hvs_rotation = sm.quat.angleAxis(rotation_noise * math.pi, sm.vec3.new(0, 1, 0))

	_table_insert(table, {
		pos = sm.vec3.new(x_local, y_local, z),
		rot = _water_quaternion * hvs_rotation,
		tags = {},
		color = hvs_color,
		uuid = cur_hvs_data[1]
	})
end

function GetHarvestablesForCell( cellX, cellY, lod )
	if g_terrainCellCacheX[cellX] ~= nil and g_terrainCellCacheY[cellY] ~= nil then
		return {}
	end

	g_terrainCellCacheX[cellX] = true
	g_terrainCellCacheY[cellY] = true

	local hvs_output = {}

	local x_pos = cellX * 64
	local y_pos = cellY * 64

	local terrain_seed_offset = g_terrainSeed_712
	for iter = 0, 10 do
		local terrain_seed_iter = terrain_seed_offset + iter

		local x_local = _math_abs(_sm_noise_octaveNoise2d(x_pos * 0.784, y_pos * 0.784, 1, terrain_seed_iter)) * 64
		local y_local = _math_abs(_sm_noise_octaveNoise2d(x_pos * 0.165, y_pos * 0.165, 1, terrain_seed_iter)) * 64

		local g_x = x_pos + x_local
		local g_y = y_pos + y_local

		local hvs_height = CalculateTerrainHeight(g_x, g_y)
		if not isInWaterHeight(hvs_height) and not isTooSteep(g_x, g_y, hvs_height) then
			local hvs_noise = HarvestableNoise(g_x, g_y)
			if hvs_noise > 0.015 then
				AddHarvestable(hvs_output, g_x, g_y, hvs_height, x_local, y_local)
			end
		end
	end

	return hvs_output
end

function GetKinematicsForCell( cellX, cellY, lod )
	return {}
end

function GetDecalsForCell( cellX, cellY, lod )
	return {}
end