--MCmobs v0.4
--maikerumine
--made for MC like Survival game
--License for code WTFPL and otherwise stated in readmes

--###################
--################### VILLAGER
--###################
-- Summary: Villagers are complex NPCs, their main feature allows players to trade with them.

-- TODO: Particles
-- TODO: 4s Regeneration I after trade unlock
-- TODO: Behaviour:
-- TODO: Run into house on rain or danger, open doors
-- TODO: Internal inventory, trade with other villagers
-- TODO: Schedule stuff (work,sleep,father)

local weather_mod = minetest.get_modpath("mcl_weather")

local S = minetest.get_translator("mobs_mc")
local N = function(s) return s end
local F = minetest.formspec_escape

-- playername-indexed table containing the previously used tradenum
local player_tradenum = {}
-- playername-indexed table containing the objectref of trader, if trading formspec is open
local player_trading_with = {}

local DEFAULT_WALK_CHANCE = 33 -- chance to walk in percent, if no player nearby
local PLAYER_SCAN_INTERVAL = 5 -- every X seconds, villager looks for players nearby
local PLAYER_SCAN_RADIUS = 4 -- scan radius for looking for nearby players

local PATHFINDING = "gowp"

--[=======[ TRADING ]=======]

-- LIST OF VILLAGER PROFESSIONS AND TRADES

-- TECHNICAL RESTRICTIONS (FIXME):
-- * You can't use a clock as requested item
-- * You can't use a compass as requested item if its stack size > 1
-- * You can't use a compass in the second requested slot
-- This is a problem in the mcl_compass and mcl_clock mods,
-- these items should be implemented as single items, then everything
-- will be much easier.

local LOGGING_ON = minetest.settings:get_bool("mcl_logging_mobs_villager",false)
local LOG_MODULE = "[Mobs - Villager]"
local function mcl_log (message)
	if LOGGING_ON and message then
		minetest.log(LOG_MODULE .. " " .. message)
	end
end

local COMPASS = "mcl_compass:compass"
if minetest.registered_aliases[COMPASS] then
	COMPASS = minetest.registered_aliases[COMPASS]
end

local E1 = { "mcl_core:emerald", 1, 1 } -- one emerald

-- Special trades for v6 only
-- NOTE: These symbols MUST only be added at the end of a tier
local TRADE_V6_RED_SANDSTONE, TRADE_V6_DARK_OAK_SAPLING, TRADE_V6_ACACIA_SAPLING, TRADE_V6_BIRCH_SAPLING
if minetest.get_mapgen_setting("mg_name") == "v6" then
	TRADE_V6_RED_SANDSTONE = { E1, { "mcl_core:redsandstone", 12, 16 } }
	TRADE_V6_DARK_OAK_SAPLING = { { "mcl_core:emerald", 6, 9 }, { "mcl_core:darksapling", 1, 1 } }
	TRADE_V6_ACACIA_SAPLING = { { "mcl_core:emerald", 14, 17 }, { "mcl_core:acaciasapling", 1, 1 } }
	TRADE_V6_BIRCH_SAPLING = { { "mcl_core:emerald", 8, 11 }, { "mcl_core:birchsapling", 1, 1 } }
end

local tiernames = {
	"Novice",
	"Apprentice",
	"Journeyman",
	"Expert",
	"Master",
}

local badges = {
	"mobs_mc_stone.png",
	"mobs_mc_iron.png",
	"mobs_mc_gold.png",
	"mobs_mc_emerald.png",
	"mobs_mc_diamond.png",
}

local professions = {
	unemployed = {
		name = N("Unemployed"),
		textures = {
				"mobs_mc_villager.png",
				"mobs_mc_villager.png",
			},
		trades = nil,
	},
	farmer = {
		name = N("Farmer"),
		texture = "mobs_mc_villager_farmer.png",
		jobsite = "mcl_composters:composter",
		trades = {
			{
			{ { "mcl_farming:wheat_item", 18, 22, }, E1 },
			{ { "mcl_farming:potato_item", 15, 19, }, E1 },
			{ { "mcl_farming:carrot_item", 15, 19, }, E1 },
			{ E1, { "mcl_farming:bread", 2, 4 } },
			},

			{
			{ { "mcl_farming:pumpkin", 6, 7 }, E1 },
			{ E1, { "mcl_farming:pumpkin_pie", 2, 3} },
			{ E1, { "mcl_core:apple", 2, 3} },
			},

			{
			{ { "mcl_farming:melon", 7, 12 }, E1 },
			{ E1, {"mcl_farming:cookie", 5, 7 }, },
			},
			{
			{ E1, { "mcl_mushrooms:mushroom_stew", 6, 10 } }, --FIXME: expert level farmer is supposed to sell sus stews.
			},
			{
			{ E1, { "mcl_farming:carrot_item_gold", 3, 10 } },
			{ E1, { "mcl_potions:speckled_melon", 4, 1 } },
			TRADE_V6_BIRCH_SAPLING,
			TRADE_V6_DARK_OAK_SAPLING,
			TRADE_V6_ACACIA_SAPLING,
			},
		}
	},
	fisherman = {
		name = N("Fisherman"),
		texture = "mobs_mc_villager_fisherman.png",
		jobsite = "mcl_barrels:barrel_closed",
		trades = {
			{
			{ { "mcl_fishing:fish_raw", 6, 6, "mcl_core:emerald", 1, 1 },{ "mcl_fishing:fish_cooked", 6, 6 } },
			{ { "mcl_mobitems:string", 15, 20 }, E1 },
			{ { "mcl_core:coal_lump", 15, 10 }, E1 },
			-- FIXME missing: bucket of cod + fish should be cod.
			},
			{
			{ { "mcl_fishing:fish_raw", 6, 15,}, E1 },
			{ { "mcl_fishing:salmon_raw", 6, 6, "mcl_core:emerald", 1, 1 },{ "mcl_fishing:salmon_cooked", 6, 6 } },
			{ { "mcl_core:emerald", 1, 2 },{"mcl_campfires:campfire_lit",1,1} },
			},
			{
			{ { "mcl_fishing:salmon_raw", 6, 13,}, E1 },
			{ { "mcl_core:emerald", 7, 22 }, { "mcl_fishing:fishing_rod_enchanted", 1, 1} },
			},
			{
			{ { "mcl_fishing:clownfish_raw", 6, 6,}, E1 },
			},
			{
			{ { "mcl_fishing:pufferfish_raw", 4, 4,}, E1 },

			{ { "mcl_boats:boat", 1, 1,}, E1 },
			{ { "mcl_boats:boat_acacia", 1, 1,}, E1 },
			{ { "mcl_boats:boat_spruce", 1, 1,}, E1 },
			{ { "mcl_boats:boat_dark_oak", 1, 1,}, E1 },
			{ { "mcl_boats:boat_birch", 1, 1,}, E1 },
			},
		},
	},
	fletcher = {
		name = N("Fletcher"),
		texture = "mobs_mc_villager_fletcher.png",
		jobsite = "mcl_fletching_table:fletching_table",
		trades = {
			{
			{ { "mcl_mobitems:string", 15, 20 }, E1 },
			{ E1, { "mcl_bows:arrow", 8, 12 } },
			{ { "mcl_core:gravel", 10, 10, "mcl_core:emerald", 1, 1 }, { "mcl_core:flint", 6, 10 } },
			},
			{
			{ { "mcl_core:flint", 26, 26 }, E1 },
			{ { "mcl_core:emerald", 2, 3 }, { "mcl_bows:bow", 1, 1 } },
			},
			{
			{ { "mcl_mobitems:string", 14, 14 }, E1 },
			{ { "mcl_core:emerald", 3, 3 }, { "mcl_bows:crossbow", 1, 1 } },
			},
			{
			{ { "mcl_mobitems:string", 24, 24 }, E1 },
			{ { "mcl_core:emerald", 7, 21 } , { "mcl_bows:bow_enchanted", 1, 1 } },
			},
			{
			--FIXME: supposed to be tripwire hook{ { "tripwirehook", 24, 24 }, E1 },
			{ { "mcl_core:emerald", 8, 22 } , { "mcl_bows:crossbow_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:healing_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:harming_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:night_vision_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:swiftness_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:slowness_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:leaping_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:poison_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:regeneration_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:invisibility_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:water_breathing_arrow", 5, 5 } },
			{ { "mcl_core:emerald", 2, 2, "mcl_bows:arrow", 5, 5 }, { "mcl_potions:fire_resistance_arrow", 5, 5 } },
			},
		}
	},
	shepherd ={
		name = N("Shepherd"),
		texture =  "mobs_mc_villager_sheperd.png",
		jobsite = "mcl_loom:loom",
		trades = {
			{
			{ { "mcl_wool:white", 16, 22 }, E1 },
			{ { "mcl_core:emerald", 3, 4 }, { "mcl_tools:shears", 1, 1 } },
			},

			{
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:white", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:grey", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:silver", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:black", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:yellow", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:orange", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:red", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:magenta", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:purple", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:blue", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:cyan", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:lime", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:green", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:pink", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:light_blue", 1, 1 } },
			{ { "mcl_core:emerald", 1, 2 }, { "mcl_wool:brown", 1, 1 } },
			},
		},
	},
	librarian = {
		name = N("Librarian"),
		texture = "mobs_mc_villager_librarian.png",
		jobsite = "mcl_books:bookshelf", --FIXME: lectern
		trades = {
			{
			{ { "mcl_core:paper", 24, 36 }, E1 },
			{ { "mcl_books:book", 8, 10 }, E1 },
			{ { "mcl_core:emerald", 9, 9 }, { "mcl_books:bookshelf", 1 ,1 }},
			{ { "mcl_core:emerald", 5, 64, "mcl_books:book", 1, 1 }, { "mcl_enchanting:book_enchanted", 1 ,1 }},
			},
			{
			{ { "mcl_books:written_book", 2, 2 }, E1 },
			{ { "mcl_core:emerald", 5, 64, "mcl_books:book", 1, 1 }, { "mcl_enchanting:book_enchanted", 1 ,1 }},
			{ E1, { "mcl_lanterns:lantern_floor", 1, 1 } },
			},

			{
			{ { "mcl_dye:black", 5, 5 }, E1 },
			{ { "mcl_core:emerald", 5, 64, "mcl_books:book", 1, 1 }, { "mcl_enchanting:book_enchanted", 1 ,1 }},
			{ E1, { "mcl_core:glass", 4, 4 } },
			},

			{
			{ E1, { "mcl_books:writable_book", 1, 1 } },
			{ { "mcl_core:emerald", 5, 64, "mcl_books:book", 1, 1 }, { "mcl_enchanting:book_enchanted", 1 ,1 }},
			{ { "mcl_core:emerald", 4, 4 }, { "mcl_compass:compass", 1 ,1 }},
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_clock:clock", 1, 1 } },
			},

			{
			{ { "mcl_core:emerald", 20, 20 }, { "mcl_mobs:nametag", 1, 1 } },
			}
		},
	},
	cartographer = {
		name = N("Cartographer"),
		texture = "mobs_mc_villager_cartographer.png",
		jobsite = "mcl_cartography_table:cartography_table",
		trades = {
			{
			{ { "mcl_core:paper", 24, 24 }, E1 },
			{ { "mcl_core:emerald", 7, 7}, { "mcl_maps:empty_map", 1, 1 } },
			},
			{
			-- compass subject to special checks
			{ { "xpanes:pane_natural_flat", 11, 11 }, E1 },
			--{ { "mcl_core:emerald", 13, 13, "mcl_compass:compass", 1, 1 }, { "FIXME:ocean explorer map" 1, 1} },
			},
			{
			{ { "mcl_compass:compass", 1, 1 }, E1 },
			--{ { "mcl_core:emerald", 13, 13, "mcl_compass:compass", 1, 1 }, { "FIXME:woodland explorer map" 1, 1} },
			},
			{
			{ { "mcl_core:emerald", 7, 7}, { "mcl_itemframes:item_frame", 1, 1 }},

			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_white", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_grey", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_silver", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_black", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_red", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_green", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_cyan", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_blue", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_magenta", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_orange", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_purple", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_brown", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_pink", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_lime", 1, 1 }},
			{ { "mcl_core:emerald", 7, 7}, { "mcl_banners:banner_item_light_blue", 1, 1 }},
			},
			{
			--{ { "mcl_core:emerald", 8, 8}, { "FIXME: globe banner pattern", 1, 1 } },
			},
			-- TODO: special maps
		},
	},
	armorer = {
		name = N("Armorer"),
		texture = "mobs_mc_villager_armorer.png",
		jobsite = "mcl_blast_furnace:blast_furnace",
		trades = {
			{
			{ { "mcl_core:coal_lump", 15, 15 }, E1 },
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_armor:helmet_iron", 1, 1 } },
			{ { "mcl_core:emerald", 9, 9 }, { "mcl_armor:chestplate_iron", 1, 1 } },
			{ { "mcl_core:emerald", 7, 7 }, { "mcl_armor:leggings_iron", 1, 1 } },
			{ { "mcl_core:emerald", 4, 4 }, { "mcl_armor:boots_iron", 1, 1 } },
			},

			{
			{ { "mcl_core:iron_ingot", 4, 4 }, E1 },
			{ { "mcl_core:emerald", 36, 36 }, { "mcl_bells:bell", 1, 1 } },
			{ { "mcl_core:emerald", 3, 3 }, { "mcl_armor:leggings_chain", 1, 1 } },
			{ { "mcl_core:emerald", 1, 1 }, { "mcl_armor:boots_chain", 1, 1 } },
			},
			{
			{ { "mcl_buckets:bucket_lava", 1, 1 }, E1 },
			{ { "mcl_core:diamond", 1, 1 }, E1 },
			{ { "mcl_core:emerald", 1, 1 }, { "mcl_armor:helmet_chain", 1, 1 } },
			{ { "mcl_core:emerald", 4, 4 }, { "mcl_armor:chestplate_chain", 1, 1 } },
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_shields:shield", 1, 1 } },
			},

			{
			{ { "mcl_core:emerald", 19, 33 }, { "mcl_armor:leggings_diamond_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 13, 27 }, { "mcl_armor:boots_diamond_enchanted", 1, 1 } },
			},
			{
			{ { "mcl_core:emerald", 13, 27 }, { "mcl_armor:helmet_diamond_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 21, 35 }, { "mcl_armor:chestplate_diamond_enchanted", 1, 1 } },
			},
		},
	},
	leatherworker = {
		name = N("Leatherworker"),
		texture = "mobs_mc_villager_leatherworker.png",
		jobsite = "mcl_cauldrons:cauldron",
		trades = {
			{
			{ { "mcl_mobitems:leather", 9, 12 }, E1 },
			{ { "mcl_core:emerald", 3, 3 }, { "mcl_armor:leggings_leather", 2, 4 } },
			{ { "mcl_core:emerald", 7, 7 }, { "mcl_armor:chestplate_leather", 2, 4 } },
			},
			{
			{ { "mcl_core:flint", 26, 26 }, E1 },
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_armor:helmet_leather", 2, 4 } },
			{ { "mcl_core:emerald", 4, 4 }, { "mcl_armor:boots_leather", 2, 4 } },
			},
			{
			{ { "mcl_mobitems:rabbit_hide", 9, 9 }, E1 },
			{ { "mcl_core:emerald", 7, 7 }, { "mcl_armor:chestplate_leather", 1, 1 } },
			},
			{
			--{ { "FIXME: scute", 4, 4 }, E1 },
			{ { "mcl_core:emerald", 8, 10 }, { "mcl_mobitems:saddle", 1, 1 } },
			},
			{
			{ { "mcl_core:emerald", 6, 6 }, { "mcl_mobitems:saddle", 1, 1 } },
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_armor:helmet_leather", 2, 4 } },
			},
		},
	},
	butcher = {
		name = N("Butcher"),
		texture = "mobs_mc_villager_butcher.png",
		jobsite = "mcl_smoker:smoker",
		trades = {
			{
			{ { "mcl_mobitems:beef", 14, 14 }, E1 },
			{ { "mcl_mobitems:chicken", 7, 7 }, E1 },
			{ { "mcl_mobitems:rabbit", 4, 4 }, E1 },
			{ E1, { "mcl_mobitems:rabbit_stew", 1, 1 } },
			},

			{
			{ { "mcl_core:coal_lump", 15, 15 }, E1 },
			{ E1, { "mcl_mobitems:cooked_porkchop", 5, 5 } },
			{ E1, { "mcl_mobitems:cooked_chicken", 8, 8 } },
			},
			{
			{ { "mcl_mobitems:mutton", 7, 7 }, E1 },
			{ { "mcl_mobitems:beef", 10, 10 }, E1 },
			},
			{
			{ { "mcl_mobitems:mutton", 7, 7 }, E1 },
			{ { "mcl_mobitems:beef", 10, 10 }, E1 },
			},
			{
			--{ { "FIXME: Sweet Berries", 10, 10 }, E1 },
			},
		},
	},
	weapon_smith = {
		name = N("Weapon Smith"),
		texture = "mobs_mc_villager_weaponsmith.png",
		jobsite = "mcl_grindstone:grindstone",
		trades = {
			{
			{ { "mcl_core:coal_lump", 15, 15 }, E1 },
			{ { "mcl_core:emerald", 3, 3 }, { "mcl_tools:axe_iron", 1, 1 } },
			{ { "mcl_core:emerald", 7, 21 }, { "mcl_tools:sword_iron_enchanted", 1, 1 } },
			},

			{
			{ { "mcl_core:iron_ingot", 4, 4 }, E1 },
			{ { "mcl_core:emerald", 36, 36 }, { "mcl_bells:bell", 1, 1 } },
			},
			{
			{ { "mcl_core:flint", 7, 9 }, E1 },
			},
			{
			{ { "mcl_core:diamond", 7, 9 }, E1 },
			{ { "mcl_core:emerald", 17, 31 }, { "mcl_tools:axe_diamond_enchanted", 1, 1 } },
			},

			{
			{ { "mcl_core:emerald", 13, 27 }, { "mcl_tools:sword_diamond_enchanted", 1, 1 } },
			},
		},
	},
	tool_smith = {
		name = N("Tool Smith"),
		texture = "mobs_mc_villager_toolsmith.png",
		jobsite = "mcl_smithing_table:table",
		trades = {
			{
			{ { "mcl_core:coal_lump", 15, 15 }, E1 },
			{ E1, { "mcl_tools:axe_stone", 1, 1 } },
			{ E1, { "mcl_tools:shovel_stone", 1, 1 } },
			{ E1, { "mcl_tools:pick_stone", 1, 1 } },
			{ E1, { "mcl_farming:hoe_stone", 1, 1 } },
			},

			{
			{ { "mcl_core:iron_ingot", 4, 4 }, E1 },
			{ { "mcl_core:emerald", 36, 36 }, { "mcl_bells:bell", 1, 1 } },
			},
			{
			{ { "mcl_core:flint", 30, 30 }, E1 },
			{ { "mcl_core:emerald", 6, 20 }, { "mcl_tools:axe_iron_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 7, 21 }, { "mcl_tools:shovel_iron_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 8, 22 }, { "mcl_tools:pick_iron_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 4, 4 }, { "mcl_farming:hoe_diamond", 1, 1 } },
			},
			{
			{ { "mcl_core:diamond", 1, 1 }, E1 },
			{ { "mcl_core:emerald", 17, 31 }, { "mcl_tools:axe_diamond_enchanted", 1, 1 } },
			{ { "mcl_core:emerald", 10, 24 }, { "mcl_tools:shovel_diamond_enchanted", 1, 1 } },
			},
			{
			{ { "mcl_core:emerald", 18, 32 }, { "mcl_tools:pick_diamond_enchanted", 1, 1 } },
			},
		},
	},
	cleric = {
		name = N("Cleric"),
		texture = "mobs_mc_villager_priest.png",
		jobsite = "mcl_brewing:stand_000",
		trades = {
			{
			{ { "mcl_mobitems:rotten_flesh", 32, 32 }, E1 },
			{ E1, { "mesecons:redstone", 2, 2  } },
			},
			{
			{ { "mcl_core:gold_ingot", 3, 3 }, E1 },
			{ E1, { "mcl_dye:blue", 1, 1 } },
			},
			{
			{ { "mcl_mobitems:rabbit_foot", 2, 2 }, E1 },
			{ E1, { "mcl_nether:glowstone", 4, 4 } },
			},
			{
			--{ { "FIXME: scute", 4, 4 }, E1 },
			{ { "mcl_potions:glass_bottle", 9, 9 }, E1 },
			{ { "mcl_core:emerald", 5, 5 }, { "mcl_throwing:ender_pearl", 1, 1 } },
			TRADE_V6_RED_SANDSTONE,
			},
			{
			 { { "mcl_nether:nether_wart_item", 22, 22 }, E1 },
			 { { "mcl_core:emerald", 3, 3 }, { "mcl_experience:bottle", 1, 1 } },
			},
		},
	},
	nitwit = {
		name = N("Nitwit"),
		texture = "mobs_mc_villager_nitwit.png",
		-- No trades for nitwit
		trades = nil,
	}
}

local WORK = "work"
local SLEEP = "sleep"
local GATHERING = "gathering"

local profession_names = {}
for id, _ in pairs(professions) do
	table.insert(profession_names, id)
end

local function populate_jobsites (profession)
	if profession then
		mcl_log("populate_jobsites: ".. tostring(profession))
	end
	local jobsites_requested={}
	for _,n in pairs(profession_names) do
		if n and professions[n].jobsite then
			if not profession or (profession and profession == n) then
				--minetest.log("populate_jobsites. Adding: ".. tostring(n))
				table.insert(jobsites_requested,professions[n].jobsite)
			end
		end
	end
	return jobsites_requested
end

jobsites = populate_jobsites()

local spawnable_bed={}
table.insert(spawnable_bed, "mcl_beds:bed_red_bottom")

local function stand_still(self)
	self.walk_chance = 0
	self.jump = false
end

local function init_trader_vars(self)
	if not self._max_trade_tier then
		self._max_trade_tier = 1
	end
	if not self._locked_trades then
		self._locked_trades = 0
	end
	if not self._trading_players then
		self._trading_players = {}
	end
end

local function get_badge_textures(self)
	local t = professions[self._profession].texture
	if self._profession == "unemployed"	then
		t = professions[self._profession].textures -- ideally both scenarios should be textures with a list containing 1 or multiple
		--mcl_log("t: " .. tostring(t))
	end

	if self._profession == "unemployed" or self._profession == "nitwit" then return t end
	local tier = self._max_trade_tier or 1
	return {
		t .. "^" .. badges[tier]
	}
end

local function set_textures(self)
	local badge_textures = get_badge_textures(self)
	--mcl_log("Setting textures: " .. tostring(badge_textures))
	self.object:set_properties({textures=badge_textures})
end

function get_activity(tod)
	-- night hours = tod > 18541 or tod < 5458
	if not tod then
		tod = minetest.get_timeofday()
	end
	tod = ( tod * 24000 ) % 24000


	local lunch_start = 12000
	local lunch_end = 13500
	local work_start = 8500
	local work_end = 16500

	local activity = nil
	if weather_mod and mcl_weather.get_weather() == "thunder" then
		mcl_log("Better get to bed. Weather is: " .. mcl_weather.get_weather())
		activity = SLEEP
	elseif (tod > work_start and tod < lunch_start) or  (tod > lunch_end and tod < work_end) then
		activity = WORK
	elseif mcl_beds.is_night() then
		activity = SLEEP
	elseif tod > lunch_start and tod < lunch_end then
		activity = GATHERING
	else
		activity = "chill"
	end
	mcl_log("Time is " .. tod ..". Activity is: ".. activity)
	return activity

end

local function check_bed (entity)
	local b = entity._bed
	if not b then
		--minetest.log("No bed set on villager")
		return false
	end

	local n = minetest.get_node(b)
	if n and n.name ~= "mcl_beds:bed_red_bottom" then
		mcl_log("Where did my bed go?!")
		entity._bed = nil --the stormtroopers have killed uncle owen
		return false
	else
		return true
	end
end

local function go_home(entity, sleep)

	if not check_bed (entity) then
		mcl_log("Cannot find bed, so cannot go home")
	end

	local b = entity._bed
	if not b then
		return
	end

	local bed_node = minetest.get_node(b)
	if not bed_node then
		entity._bed = nil
		mcl_log("Cannot find bed. Unset it")
		return
	end

	if vector.distance(entity.object:get_pos(),b) < 2 then
		if sleep then
			entity.order = SLEEP
			mcl_log("Sleep time!")
		end
	else
		if sleep and entity.order == SLEEP then
			entity.order = nil
			return
		end

		mcl_mobs:gopath(entity,b,function(entity,b)
			local b = entity._bed

			if not b then
				--minetest.log("NO BED, problem")
				return false
			end

			if not minetest.get_node(b) then
				--minetest.log("NO BED NODE, problem")
				return false
			end

			if vector.distance(entity.object:get_pos(),b) < 2 then
				--minetest.log("Managed to walk home callback!")
				return true
			else
				--minetest.log("Need to walk to home")
			end
		end)
	end
end



local function take_bed (entity)
	if not entity then return end

	local p = entity.object:get_pos()
	local nn = minetest.find_nodes_in_area(vector.offset(p,-48,-48,-48), vector.offset(p,48,48,48), spawnable_bed)

	for _,n in pairs(nn) do
		local m=minetest.get_meta(n)
		--mcl_log("Bed owner: ".. m:get_string("villager"))
		if m:get_string("villager") == "" and not (entity.state == PATHFINDING) then
			mcl_log("Can we path to bed: "..minetest.pos_to_string(n) )
			local gp = mcl_mobs:gopath(entity,n,function(self)
				if self then
					self.order = "sleep"
					mcl_log("Sleepy time" )
				else
					mcl_log("Can't sleep, no self in the callback" )
				end
			end)
			if gp then
				mcl_log("Nice bed. I'll defintely take it as I can path")
				m:set_string("villager", entity._id)
				entity._bed = n
				break
			else
				mcl_log("Awww. I can't find my bed.")
			end
		else
			mcl_log("Currently gowp, or it's taken: ".. m:get_string("villager"))
		end
	end
end

local function has_golem(pos)
	local r = false
	for _,o in pairs(minetest.get_objects_inside_radius(pos,16)) do
		local l = o:get_luaentity()
		if l and l.name == "mobs_mc:iron_golem" then return true end
	end
end

local function has_summon_participants(self)
	local r = 0
	for _,o in pairs(minetest.get_objects_inside_radius(self.object:get_pos(),10)) do
		local l = o:get_luaentity()
		--TODO check for panicking or gossiping
		if l and l.name == "mobs_mc:villager" then r = r + 1 end
	end
	return r > 2
end

local function summon_golem(self)
	vector.offset(self.object:get_pos(),-10,-10,-10)
	local nn = minetest.find_nodes_in_area_under_air(vector.offset(self.object:get_pos(),-10,-10,-10),vector.offset(self.object:get_pos(),10,10,10),{"group:solid","group:water"})
	table.shuffle(nn)
	for _,n in pairs(nn) do
		local up = minetest.find_nodes_in_area(vector.offset(n,0,1,0),vector.offset(n,0,3,0),{"air"})
		if up and #up >= 3 then
			minetest.sound_play("mcl_portals_open_end_portal", {pos=n, gain=0.5, max_hear_distance = 16}, true)
			return minetest.add_entity(vector.offset(n,0,1,0),"mobs_mc:iron_golem")
		end
	end
end

local function check_summon(self,dtime)
	-- TODO has selpt in last 20?
	if self._summon_timer and self._summon_timer > 30 then
		local pos = self.object:get_pos()
		self._summon_timer = 0
		if has_golem(pos) then return false end
		if not has_summon_participants(self) then return end
		summon_golem(self)
	elseif self._summon_timer == nil  then
		self._summon_timer = 0
	end
	self._summon_timer = self._summon_timer + dtime
end

local function debug_trades(self)
	mcl_log("Start debug trades")
	if not self or not self._trades then return end
	local trades = minetest.deserialize(self._trades)
	if trades and type(trades) == "table" then
		for trader, trade in pairs(trades) do
			--mcl_log("Current record: ".. tostring(trader))
			for tr3, tr4 in pairs (trade) do
				mcl_log("Key: ".. tostring(tr3))
				mcl_log("Value: ".. tostring(tr4))
			end
		end
	end
	mcl_log("End debug trades")
end

local function has_traded (self)
	if not self._trades then
		mcl_log("No trades set. has_traded is false")
		return false
	end
	local cur_trades_tab = minetest.deserialize(self._trades)
	if cur_trades_tab and type(cur_trades_tab) == "table" then
		for trader, trades in pairs(cur_trades_tab) do
			if trades.traded_once then
				mcl_log("Villager has traded before. Returning true")
				return true
			end
		end
	end
	mcl_log("Villager has not traded before")
	return false
end

local function unlock_trades (self)
	if not self._trades then
		mcl_log("No trades set. has_traded is false")
		return false
	end
	mcl_log("Unlocking trades")
	local has_unlocked = false

	local trades = minetest.deserialize(self._trades)
	if trades and type(trades) == "table" then
		for trader, trade in pairs(trades) do
			local trade_tier_too_high = trade.tier > self._max_trade_tier
			--mcl_log("Max trade tier of villager: ".. tostring(self._max_trade_tier))
			--mcl_log("current trade.tier: ".. tostring(trade.tier))
			--mcl_log("trade tier too high: ".. tostring(trade_tier_too_high))
			--mcl_log("locked: ".. tostring(trade["locked"]))
			if not trade_tier_too_high then
				if trade["locked"] == true then
					trade.locked = false
					trade.trade_counter = 0
					has_unlocked = true
					mcl_log("Villager has a locked trade. Unlocking")
				end
			end
		end
		if has_unlocked then
			self._trades = minetest.serialize(trades)
		end
	end
end

----- JOBSITE LOGIC
local function get_profession_by_jobsite(js)
	for k,v in pairs(professions) do
		if v.jobsite == js then return k end
	end
end

local function employ(self,jobsite_pos)
	local n = minetest.get_node(jobsite_pos)
	local m = minetest.get_meta(jobsite_pos)
	local p = get_profession_by_jobsite(n.name)
	if p and m:get_string("villager") == "" then
		mcl_log("Taking this jobsite")

		m:set_string("villager",self._id)
		self._jobsite = jobsite_pos

		if not has_traded(self) then
			self._profession=p
			set_textures(self)
		end
		return true
	else
		mcl_log("I can not steal someone's job!")
	end
end


local function look_for_job(self, requested_jobsites)
	mcl_log("Looking for jobs")

	-- This logic is done twice. Remove this.
	local looking_for_type = jobsites
	if requested_jobsites then
		--mcl_log("Looking for jobs of my type: " .. tostring(requested_jobsites))
		looking_for_type = requested_jobsites
	else
		mcl_log("Looking for any job type")
	end

	local p = self.object:get_pos()
	local nn = minetest.find_nodes_in_area(vector.offset(p,-48,-48,-48),vector.offset(p,48,48,48), looking_for_type)

	local distance_to_closest_block = nil
	local closest_block = nil

	--Ideally should check for closest available. It'll make pathing easier.
	for i,n in pairs(nn) do
		local m = minetest.get_meta(n)
		mcl_log("Block: " .. minetest.pos_to_string(n).. "Job owner: ".. m:get_string("villager"))

		if m:get_string("villager") == "" then
			-- Distance check
			local distance_to_block = vector.distance(self.object:get_pos(), n)
			mcl_log("Distance to block ".. i .. ": ".. distance_to_block)

			if not distance_to_closest_block or distance_to_closest_block > distance_to_block then
				mcl_log("This block is closer than the last.")
				closest_block = n
				distance_to_closest_block = distance_to_block
			end
		end
	end

	if closest_block then
		mcl_log("It's a free job for me (" .. minetest.pos_to_string(p) .. ")! I might be interested: ".. minetest.pos_to_string(closest_block) )

		local gp = mcl_mobs:gopath(self, closest_block,function(self)
			mcl_log("Arrived at block callback")
			if self and self.state == "stand" then
				self.order = WORK
			else
				mcl_log("no self. passing param to callback failed")
			end
		end)

		if gp then
			if closest_block then
				mcl_log("We can path to this block.. " .. tostring(closest_block))
			end
			return closest_block
		else
			mcl_log("We could not path to block or it's not ready to path yet.")
		end
	else
		mcl_log("We don't have a job block to path to")
	end

	return nil
end



local function get_a_job(self)
	if self.order == WORK then self.order = nil end

	mcl_log("I'm unemployed or lost my job block and have traded. Can I get a job?")

	local requested_jobsites = jobsites
	if has_traded (self) then
		mcl_log("Has traded so look for job of my type")
		requested_jobsites = populate_jobsites(self._profession)
		-- Only pass in my jobsite to two functions here
	end

	local p = self.object:get_pos()
	local n = minetest.find_node_near(p,1,requested_jobsites)
	if n and employ(self,n) then return true end

	if self.state ~= PATHFINDING then
		mcl_log("Nothing near. Need to look for a job")
		look_for_job(self, requested_jobsites)
	end
end

local function retrieve_my_jobsite (self)
	if not self or not self._jobsite then
		mcl_log("find_jobsite. Invalid params. Should not happen")
		return
	end
	local n = mcl_vars.get_node(self._jobsite)
	local m = minetest.get_meta(self._jobsite)
	if m:get_string("villager") == self._id then
		--mcl_log("find_jobsite. is my job.")
		return n
	else
		mcl_log("This isn't my jobsite")
	end
	return
end

local function validate_jobsite(self)
	if self._profession == "unemployed" then return false end

	if not retrieve_my_jobsite (self) then
		self._jobsite = nil
		if self.order == WORK then
			self.order = nil
		end

		if not has_traded(self) then
			mcl_log("Cannot retrieve my jobsite. I am now unemployed.")
			self._profession = "unemployed"
			self._trades = nil
			set_textures(self)
		else
			mcl_log("Cannot retrieve my jobsite but I've traded so only remove jobsite.")
		end
		return false
	else
		return true
	end
end

local function do_work (self)
	--debug_trades(self)
	if self.child then
		mcl_log("A child so don't send to work")
		return
	end
	--mcl_log("Time for work")

	-- Don't try if looking_for_work, or gowp possibly
	if validate_jobsite(self) then
		--mcl_log("My jobsite is valid. Do i need to travel?")

		local jobsite2 = retrieve_my_jobsite (self)
		local jobsite = self._jobsite

		if self and jobsite2 and self._jobsite then
			local distance_to_jobsite = vector.distance(self.object:get_pos(),self._jobsite)
			--mcl_log("Villager: ".. minetest.pos_to_string(self.object:get_pos()) ..  ", jobsite: " .. minetest.pos_to_string(self._jobsite) .. ", distance to jobsite: ".. distance_to_jobsite)

			if distance_to_jobsite < 2 then
				if self.state ~= PATHFINDING and  self.order ~= WORK then
					mcl_log("Setting order to work.")
					self.order = WORK
					unlock_trades(self)
				else
					--mcl_log("Still pathfinding.")
				end
			else
				mcl_log("Not at job block. Need to commute.")
				if self.order == WORK then
					self.order = nil
					return
				end
				mcl_mobs:gopath(self, jobsite, function(self,jobsite)
					if not self then
						--mcl_log("missing self. not good")
						return false
					end
					if not self._jobsite then
						--mcl_log("Jobsite not valid")
						return false
					end
					if vector.distance(self.object:get_pos(),self._jobsite) < 2 then
						--mcl_log("Made it to work ok callback!")
						return true
					else
						--mcl_log("Need to walk to work. Not sure we can get here.")
					end
				end)
			end
		end
	elseif self._profession == "unemployed" or has_traded(self) then
		get_a_job(self)
	end
end

local function go_to_town_bell(self)
	if self.order == GATHERING then
		mcl_log("Already gathering")
		return
	else
		mcl_log("Current order" .. self.order)
	end
	mcl_log("Go to town bell")

	local looking_for_type={}
	table.insert(looking_for_type, "mcl_bells:bell")

	local p = self.object:get_pos()
	local nn = minetest.find_nodes_in_area(vector.offset(p,-48,-48,-48),vector.offset(p,48,48,48), looking_for_type)

	--Ideally should check for closest available. It'll make pathing easier.
	for _,n in pairs(nn) do
		mcl_log("Found bell")

		local gp = mcl_mobs:gopath(self,n,function(self)
			if self then
				self.order = GATHERING
				mcl_log("Callback has a self")
			end
			mcl_log("Arrived at block callback")
		end)

		if gp then
			if n then
				mcl_log("We can path to this block.. " .. tostring(n))
			end
			return n
		else
			mcl_log("We could not path to block or it's not ready to path yet.")
		end

	end

	return nil
end

local function do_activity (self)
	-- Maybe just check we're pathfinding first?

	if not self._bed then
		--mcl_log("Villager has no bed. Currently at location: "..minetest.pos_to_string(self.object:get_pos()))
		take_bed (self)
	end

	-- Only check in day or during thunderstorm but wandered_too_far code won't work
	local wandered_too_far = false
	if check_bed (self) then
		wandered_too_far = ( self.state ~= PATHFINDING ) and (vector.distance(self.object:get_pos(),self._bed) > 50 )
	end


	if wandered_too_far  then
		--mcl_log("Wandered too far! Return home ")
		go_home(self, false)
	elseif get_activity() == SLEEP then
		go_home(self, true)
	elseif get_activity() == WORK then
		do_work(self)
	elseif get_activity() == GATHERING then
		go_to_town_bell(self)
	else
		-- gossip at town bell or stroll around
		mcl_log("No order, so remove it.")
		self.order = nil
	end

	-- Daytime is work and play time
	if not mcl_beds.is_night() then
		if self.order == SLEEP then self.order = nil end
	else
		if self.order == WORK then self.order = nil end
	end

end

local function update_max_tradenum(self)
	if not self._trades then
		return
	end
	local trades = minetest.deserialize(self._trades)
	for t=1, #trades do
		local trade = trades[t]
		if trade.tier > self._max_trade_tier then
			self._max_tradenum = t - 1
			return
		end
	end
	self._max_tradenum = #trades
end

local function init_trades(self, inv)
	local profession = professions[self._profession]
	local trade_tiers = profession.trades
	if trade_tiers == nil then
		-- Empty trades
		self._trades = false
		return
	end

	local max_tier = #trade_tiers
	local trades = {}
	for tiernum=1, max_tier do
		local tier = trade_tiers[tiernum]
		for tradenum=1, #tier do
			local trade = tier[tradenum]
			local wanted1_item = trade[1][1]
			local wanted1_count = math.random(trade[1][2], trade[1][3])
			local offered_item = trade[2][1]
			local offered_count = math.random(trade[2][2], trade[2][3])

			local offered_stack = ItemStack({name = offered_item, count = offered_count})
			if mcl_enchanting.is_enchanted(offered_item) then
				if mcl_enchanting.is_book(offered_item) then
					offered_stack = mcl_enchanting.enchant_uniform_randomly(offered_stack, {"soul_speed"})
				else
					mcl_enchanting.enchant_randomly(offered_stack, math.random(5, 19), false, false, true)
					mcl_enchanting.unload_enchantments(offered_stack)
				end
			end

			local wanted = { wanted1_item .. " " ..wanted1_count }
			if trade[1][4] then
				local wanted2_item = trade[1][4]
				local wanted2_count = math.random(trade[1][5], trade[1][6])
				table.insert(wanted, wanted2_item .. " " ..wanted2_count)
			end

			table.insert(trades, {
				wanted = wanted,
				offered = offered_stack:to_table(),
				tier = tiernum, -- tier of this trade
				traded_once = false, -- true if trade was traded at least once
				trade_counter = 0, -- how often the this trade was mate after the last time it got unlocked
				locked = false, -- if this trade is locked. Locked trades can't be used
			})
		end
	end
	self._trades = minetest.serialize(trades)
	minetest.deserialize(self._trades)
end

local function set_trade(trader, player, inv, concrete_tradenum)
	local trades = minetest.deserialize(trader._trades)
	if not trades then
		init_trades(trader)
		trades = minetest.deserialize(trader._trades)
		if not trades then
			--minetest.log("error", "Failed to select villager trade!")
			return
		end
	end
	local name = player:get_player_name()

	-- Stop tradenum from advancing into locked tiers or out-of-range areas
	if concrete_tradenum > trader._max_tradenum then
		concrete_tradenum = trader._max_tradenum
	elseif concrete_tradenum < 1 then
		concrete_tradenum = 1
	end
	player_tradenum[name] = concrete_tradenum
	local trade = trades[concrete_tradenum]
	inv:set_stack("wanted", 1, ItemStack(trade.wanted[1]))
	local offered = ItemStack(trade.offered)
	-- Only load enchantments for enchanted items; fixes unnecessary metadata being applied to regular items from villagers.
	if mcl_enchanting.is_enchanted(offered:get_name()) then
		mcl_enchanting.load_enchantments(offered)
	end
	inv:set_stack("offered", 1, offered)
	if trade.wanted[2] then
		local wanted2 = ItemStack(trade.wanted[2])
		inv:set_stack("wanted", 2, wanted2)
	else
		inv:set_stack("wanted", 2, "")
	end

end

local function show_trade_formspec(playername, trader, tradenum)
	if not trader._trades then
		return
	end
	if not tradenum then
		tradenum = 1
	end
	local trades = minetest.deserialize(trader._trades)
	local trade = trades[tradenum]
	local profession = professions[trader._profession].name
	local disabled_img = ""
	if trade.locked then
		disabled_img = "image[4.3,2.52;1,1;mobs_mc_trading_formspec_disabled.png]"..
			"image[4.3,1.1;1,1;mobs_mc_trading_formspec_disabled.png]"
	end
	local tradeinv_name = "mobs_mc:trade_"..playername
	local tradeinv = F("detached:"..tradeinv_name)

	local b_prev, b_next = "", ""
	if #trades > 1 then
		if tradenum > 1 then
			b_prev = "button[1,1;0.5,1;prev_trade;<]"
		end
		if tradenum < trader._max_tradenum then
			b_next = "button[7.26,1;0.5,1;next_trade;>]"
		end
	end

	local inv = minetest.get_inventory({type="detached", name="mobs_mc:trade_"..playername})
	if not inv then
		return
	end
	local wanted1 = inv:get_stack("wanted", 1)
	local wanted2 = inv:get_stack("wanted", 2)
	local offered = inv:get_stack("offered", 1)

	local w2_formspec = ""
	if not wanted2:is_empty() then
		w2_formspec = "item_image[3,1;1,1;"..wanted2:to_string().."]"
		.."tooltip[3,1;0.8,0.8;"..F(wanted2:get_description()).."]"
	end
	local tiername = tiernames[trader._max_trade_tier]
	if tiername then
		tiername = S(tiername)
	else
		tiername = S("Master")
	end
	local formspec =
	"size[9,8.75]"
	.."background[-0.19,-0.25;9.41,9.49;mobs_mc_trading_formspec_bg.png]"
	..disabled_img
.."label[3,0;"..F(minetest.colorize("#313131", S(profession).." - "..tiername)) .."]"
	.."list[current_player;main;0,4.5;9,3;9]"
	.."list[current_player;main;0,7.74;9,1;]"
	..b_prev..b_next
	.."["..tradeinv..";wanted;2,1;2,1;]"
	.."item_image[2,1;1,1;"..wanted1:to_string().."]"
	.."tooltip[2,1;0.8,0.8;"..F(wanted1:get_description()).."]"
	..w2_formspec
	.."item_image[5.76,1;1,1;"..offered:get_name().." "..offered:get_count().."]"
	.."tooltip[5.76,1;0.8,0.8;"..F(offered:get_description()).."]"
	.."list["..tradeinv..";input;2,2.5;2,1;]"
	.."list["..tradeinv..";output;5.76,2.55;1,1;]"
	.."listring["..tradeinv..";output]"
	.."listring[current_player;main]"
	.."listring["..tradeinv..";input]"
	.."listring[current_player;main]"
	minetest.sound_play("mobs_mc_villager_trade", {to_player = playername,object=trader.object}, true)
	minetest.show_formspec(playername, tradeinv_name, formspec)
end

local function update_offer(inv, player, sound)
	local name = player:get_player_name()
	local trader = player_trading_with[name]
	local tradenum = player_tradenum[name]
	if not trader or not tradenum then
		return false
	end
	local trades = minetest.deserialize(trader._trades)
	if not trades then
		return false
	end
	local trade = trades[tradenum]
	if not trade then
		return false
	end
	local wanted1, wanted2 = inv:get_stack("wanted", 1), inv:get_stack("wanted", 2)
	local input1, input2 = inv:get_stack("input", 1), inv:get_stack("input", 2)

	-- BEGIN OF SPECIAL HANDLING OF COMPASS
	-- These 2 functions are a complicated check to check if the input contains a
	-- special item which we cannot check directly against their name, like
	-- compass.
	-- TODO: Remove these check functions when compass and clock are implemented
	-- as single items.
	local function check_special(special_item, group, wanted1, wanted2, input1, input2)
		if minetest.registered_aliases[special_item] then
			special_item = minetest.registered_aliases[special_item]
		end
		if wanted1:get_name() == special_item then
			local function check_input(input, wanted, group)
				return minetest.get_item_group(input:get_name(), group) ~= 0 and input:get_count() >= wanted:get_count()
			end
			if check_input(input1, wanted1, group) then
				return true
			elseif check_input(input2, wanted1, group) then
				return true
			else
				return false
			end
		end
		return false
	end
	-- Apply above function to all items which we consider special.
	-- This function succeeds if ANY item check succeeds.
	local function check_specials(wanted1, wanted2, input1, input2)
		return check_special(COMPASS, "compass", wanted1, wanted2, input1, input2)
	end
	-- END OF SPECIAL HANDLING OF COMPASS

	if (
			((inv:contains_item("input", wanted1) and
			(wanted2:is_empty() or inv:contains_item("input", wanted2))) or
			-- BEGIN OF SPECIAL HANDLING OF COMPASS
			check_specials(wanted1, wanted2, input1, input2)) and
			-- END OF SPECIAL HANDLING OF COMPASS
			(trade.locked == false)) then
		inv:set_stack("output", 1, inv:get_stack("offered", 1))
		if sound then
			minetest.sound_play("mobs_mc_villager_accept", {to_player = name,object=trader.object}, true)
		end
		return true
	else
		inv:set_stack("output", 1, ItemStack(""))
		if sound then
			minetest.sound_play("mobs_mc_villager_deny", {to_player = name,object=trader.object}, true)
		end
		return false
	end
end

-- Returns a single itemstack in the given inventory to the player's main inventory, or drop it when there's no space left
local function return_item(itemstack, dropper, pos, inv_p)
	if dropper:is_player() then
		-- Return to main inventory
		if inv_p:room_for_item("main", itemstack) then
			inv_p:add_item("main", itemstack)
		else
			-- Drop item on the ground
			local v = dropper:get_look_dir()
			local p = {x=pos.x, y=pos.y+1.2, z=pos.z}
			p.x = p.x+(math.random(1,3)*0.2)
			p.z = p.z+(math.random(1,3)*0.2)
			local obj = minetest.add_item(p, itemstack)
			if obj then
				v.x = v.x*4
				v.y = v.y*4 + 2
				v.z = v.z*4
				obj:set_velocity(v)
				obj:get_luaentity()._insta_collect = false
			end
		end
	else
		-- Fallback for unexpected cases
		minetest.add_item(pos, itemstack)
	end
	return itemstack
end

local function return_fields(player)
	local name = player:get_player_name()
	local inv_t = minetest.get_inventory({type="detached", name = "mobs_mc:trade_"..name})
	local inv_p = player:get_inventory()
	if not inv_t or not inv_p then
		return
	end
	for i=1, inv_t:get_size("input") do
		local stack = inv_t:get_stack("input", i)
		return_item(stack, player, player:get_pos(), inv_p)
		stack:clear()
		inv_t:set_stack("input", i, stack)
	end
	inv_t:set_stack("output", 1, "")
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 14) == "mobs_mc:trade_" then
		local name = player:get_player_name()
		if fields.quit then
			-- Get input items back
			return_fields(player)
			-- Reset internal "trading with" state
			local trader = player_trading_with[name]
			if trader then
				trader._trading_players[name] = nil
			end
			player_trading_with[name] = nil
		elseif fields.next_trade or fields.prev_trade then
			local trader = player_trading_with[name]
			if not trader or not trader.object:get_luaentity() then
				return
			end
			local trades = trader._trades
			if not trades then
				return
			end
			local dir = 1
			if fields.prev_trade then
				dir = -1
			end
			local tradenum = player_tradenum[name] + dir
			local inv = minetest.get_inventory({type="detached", name="mobs_mc:trade_"..name})
			if not inv then
				return
			end
			set_trade(trader, player, inv, tradenum)
			update_offer(inv, player, false)
			show_trade_formspec(name, trader, player_tradenum[name])
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	return_fields(player)
	player_tradenum[name] = nil
	local trader = player_trading_with[name]
	if trader then
		trader._trading_players[name] = nil
	end
	player_trading_with[name] = nil

end)

-- Return true if player is trading with villager, and the villager entity exists
local function trader_exists(playername)
	local trader = player_trading_with[playername]
	return trader ~= nil and trader.object:get_luaentity() ~= nil
end

local trade_inventory = {
	allow_take = function(inv, listname, index, stack, player)
		if listname == "input" then
			return stack:get_count()
		elseif listname == "output" then
			if not trader_exists(player:get_player_name()) then
				return 0
			-- Begin Award Code
			-- May need to be moved if award gets unlocked in the wrong cases.
			elseif trader_exists(player:get_player_name()) then
				awards.unlock(player:get_player_name(), "mcl:whatAdeal")
			-- End Award Code
			end
			-- Only allow taking full stack
			local count = stack:get_count()
			if count == inv:get_stack(listname, index):get_count() then
				-- Also update output stack again.
				-- If input has double the wanted items, the
				-- output will stay because there will be still
				-- enough items in input after the trade
				local wanted1 = inv:get_stack("wanted", 1)
				local wanted2 = inv:get_stack("wanted", 2)
				local input1 = inv:get_stack("input", 1)
				local input2 = inv:get_stack("input", 2)
				wanted1:set_count(wanted1:get_count()*2)
				wanted2:set_count(wanted2:get_count()*2)
				-- BEGIN OF SPECIAL HANDLING FOR COMPASS
				local function special_checks(wanted1, input1, input2)
					if wanted1:get_name() == COMPASS then
						local compasses = 0
						if (minetest.get_item_group(input1:get_name(), "compass") ~= 0) then
							compasses = compasses + input1:get_count()
						end
						if (minetest.get_item_group(input2:get_name(), "compass") ~= 0) then
							compasses = compasses + input2:get_count()
						end
						return compasses >= wanted1:get_count()
					end
					return false
				end
				-- END OF SPECIAL HANDLING FOR COMPASS
				if (inv:contains_item("input", wanted1) and
					(wanted2:is_empty() or inv:contains_item("input", wanted2)))
					-- BEGIN OF SPECIAL HANDLING FOR COMPASS
					or special_checks(wanted1, input1, input2) then
					-- END OF SPECIAL HANDLING FOR COMPASS
					return -1
				else
					-- If less than double the wanted items,
					-- remove items from output (final trade,
					-- input runs empty)
					return count
				end
			else
				return 0
			end
		else
			return 0
		end
	end,
	allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
		if from_list == "input" and to_list == "input" then
			return count
		elseif from_list == "output" and to_list == "input" then
			if not trader_exists(player:get_player_name()) then
				return 0
			end
			local move_stack = inv:get_stack(from_list, from_index)
			if inv:get_stack(to_list, to_index):item_fits(move_stack) then
				return count
			end
		end
		return 0
	end,
	allow_put = function(inv, listname, index, stack, player)
		if listname == "input" then
			if not trader_exists(player:get_player_name()) then
				return 0
			else
				return stack:get_count()
			end
		else
			return 0
		end
	end,
	on_put = function(inv, listname, index, stack, player)
		update_offer(inv, player, true)
	end,
	on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
		if from_list == "output" and to_list == "input" then
			inv:remove_item("input", inv:get_stack("wanted", 1))
			local wanted2 = inv:get_stack("wanted", 2)
			if not wanted2:is_empty() then
				inv:remove_item("input", inv:get_stack("wanted", 2))
			end
			local trader = player_trading_with[name]
			minetest.sound_play("mobs_mc_villager_accept", {to_player = player:get_player_name(),object=trader.object}, true)
		end
		update_offer(inv, player, true)
	end,
	on_take = function(inv, listname, index, stack, player)
		local accept
		local name = player:get_player_name()
		if listname == "output" then
			local wanted1 = inv:get_stack("wanted", 1)
			inv:remove_item("input", wanted1)
			local wanted2 = inv:get_stack("wanted", 2)
			if not wanted2:is_empty() then
				inv:remove_item("input", inv:get_stack("wanted", 2))
			end
			-- BEGIN OF SPECIAL HANDLING FOR COMPASS
			if wanted1:get_name() == COMPASS then
				for n=1, 2 do
					local input = inv:get_stack("input", n)
					if minetest.get_item_group(input:get_name(), "compass") ~= 0 then
						input:set_count(input:get_count() - wanted1:get_count())
						inv:set_stack("input", n, input)
						break
					end
				end
			end
			-- END OF SPECIAL HANDLING FOR COMPASS
			local trader = player_trading_with[name]
			local tradenum = player_tradenum[name]

			local trades
			trader._traded = true
			if trader and trader._trades then
				trades = minetest.deserialize(trader._trades)
			end
			if trades then
				local trade = trades[tradenum]
				local unlock_stuff = false
				if not trade.traded_once then
					-- Unlock all the things if something was traded
					-- for the first time ever
					unlock_stuff = true
					trade.traded_once = true
				elseif trade.trade_counter == 0 and math.random(1,5) == 1 then
					-- Otherwise, 20% chance to unlock if used freshly reset trade
					unlock_stuff = true
				end
				local update_formspec = false
				if unlock_stuff then
					-- First-time trade unlock all trades and unlock next trade tier
					if trade.tier + 1 > trader._max_trade_tier then
						trader._max_trade_tier = trader._max_trade_tier + 1
						if trader._max_trade_tier > 5 then
							trader._max_trade_tier =  5
						end
						set_textures(trader)
						update_max_tradenum(trader)
						update_formspec = true
					end
					for t=1, #trades do
						trades[t].locked = false
						trades[t].trade_counter = 0
					end
					trader._locked_trades = 0
					-- Also heal trader for unlocking stuff
					-- TODO: Replace by Regeneration I
					trader.health = math.min(trader.hp_max, trader.health + 4)
				end
				trade.trade_counter = trade.trade_counter + 1
				mcl_log("Trade counter is: ".. trade.trade_counter)
				-- Semi-randomly lock trade for repeated trade (not if there's only 1 trade)
				if trader._max_tradenum > 1 then
					if trade.trade_counter >= 12 then
						trade.locked = true
					elseif trade.trade_counter >= 2 then
						local r = math.random(1, math.random(4, 10))
						if r == 1 then
							trade.locked = true
						end
					end
				end

				if trade.locked then
					inv:set_stack("output", 1, "")
					update_formspec = true
					trader._locked_trades = trader._locked_trades + 1
					-- Check if we managed to lock ALL available trades. Rare but possible.
					if trader._locked_trades >= trader._max_tradenum then
						-- Emergency unlock! Unlock all other trades except the current one
						for t=1, #trades do
							if t ~= tradenum then
								trades[t].locked = false
								trades[t].trade_counter = 0
							end
						end
						trader._locked_trades = 1
						-- Also heal trader for unlocking stuff
						-- TODO: Replace by Regeneration I
						trader.health = math.min(trader.hp_max, trader.health + 4)
					end
				end
				trader._trades = minetest.serialize(trades)
				if update_formspec then
					show_trade_formspec(name, trader, tradenum)
				end
			else
				minetest.log("error", "[mobs_mc] Player took item from trader output but player_trading_with or player_tradenum is nil!")
			end

			accept = true
		elseif listname == "input" then
			update_offer(inv, player, false)
		end
		local trader = player_trading_with[name]
		if accept then
			minetest.sound_play("mobs_mc_villager_accept", {to_player = name,object=trader.object}, true)
		else
			minetest.sound_play("mobs_mc_villager_deny", {to_player = name,object=trader.object}, true)
		end
	end,
}

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	player_tradenum[name] = 1
	player_trading_with[name] = nil

	-- Create or get player-specific trading inventory
	local inv = minetest.get_inventory({type="detached", name="mobs_mc:trade_"..name})
	if not inv then
		inv = minetest.create_detached_inventory("mobs_mc:trade_"..name, trade_inventory, name)
	end
	inv:set_size("input", 2)
	inv:set_size("output", 1)
	inv:set_size("wanted", 2)
	inv:set_size("offered", 1)
end)

--[=======[ MOB REGISTRATION AND SPAWNING ]=======]

local pick_up = { "mcl_farming:bread", "mcl_farming:carrot_item", "mcl_farming:beetroot_item" , "mcl_farming:potato_item" }

mcl_mobs:register_mob("mobs_mc:villager", {
	description = S("Villager"),
	type = "npc",
	spawn_class = "passive",
	passive = true,
	hp_min = 20,
	hp_max = 20,
	head_swivel = "head.control",
	bone_eye_height = 6.3,
	head_eye_height = 2.2,
	curiosity = 10,
	runaway = true,
	collisionbox = {-0.3, -0.01, -0.3, 0.3, 1.94, 0.3},
	visual = "mesh",
	mesh = "mobs_mc_villager.b3d",
	textures = {
		"mobs_mc_villager.png",
		"mobs_mc_villager.png", --hat
	},
	makes_footstep_sound = true,
	walk_velocity = 1.2,
	run_velocity = 2.4,
	drops = {},
	can_despawn = false,
	-- TODO: sounds
	sounds = {
		random = "mobs_mc_villager",
		damage = "mobs_mc_villager_hurt",
		distance = 10,
	},
	animation = {
		stand_start = 0, stand_end = 0,
		walk_start = 0, walk_end = 40, walk_speed = 25,
		run_start = 0, run_end = 40, run_speed = 25,
		head_shake_start = 60, head_shake_end = 70, head_shake_loop = false,
		head_nod_start = 50, head_nod_end = 60, head_nod_loop = false,
	},
	child_animations = {
		stand_start = 71, stand_end = 71,
		walk_start = 71, walk_end = 111, walk_speed = 37,
		run_start = 71, run_end = 111, run_speed = 37,
		head_shake_start = 131, head_shake_end = 141, head_shake_loop = false,
		head_nod_start = 121, head_nod_end = 131, head_nod_loop = false,
	},
	follow = pick_up,
	nofollow = true,
	view_range = 16,
	fear_height = 4,
	jump = true,
	walk_chance = DEFAULT_WALK_CHANCE,
	_bed = nil,
	_id = nil,
	_profession = "unemployed",
	look_at_player = true,
	pick_up = pick_up,
	can_open_doors = true,
	on_pick_up = function(self,itementity)
		local clicker
		local it = ItemStack(itementity.itemstring)
		for _,p in pairs(minetest.get_connected_players()) do
			if vector.distance(p:get_pos(),self.object:get_pos()) < 10 then
				clicker = p
			end
		end
		if clicker and not self.horny then
			mcl_mobs:feed_tame(self, clicker, 1, true, false, true)
			it:take_item(1)
		end
		return it
	end,
	on_rightclick = function(self, clicker)
		if self.child or self._profession == "unemployed" or self._profession == "nitwit" then
			self.order = nil
			return
		end

		if self.state == PATHFINDING then
			self.state = "stand"
		end
		-- Can we remove now we possibly have fixed root cause
		if self.state == "attack" then
			mcl_log("Somehow villager got into an invalid attack state. Removed attack state.")
			-- Need to stop villager getting in attack state. This is a workaround to allow players to fix broken villager.
			self.state = "stand"
			self.attack = nil
		end
		-- Don't do at night. Go to bed? Maybe do_activity needs it's own method
		if validate_jobsite(self) and not self.order == WORK then
			--mcl_mobs:gopath(self,self._jobsite,function()
			--	minetest.log("sent to jobsite")
			--end)
		else
			self.state = "stand" -- cancel gowp in case it has messed up
			--self.order = nil -- cancel work if working
		end

		-- Initiate trading
		init_trader_vars(self)
		local name = clicker:get_player_name()
		self._trading_players[name] = true

		if self._trades == nil or self._trades == false then
			minetest.log("Trades is nil so init")
			init_trades(self)
		end
		update_max_tradenum(self)
		if self._trades == false then
			minetest.log("Trades is false. no right click op")
			-- Villager has no trades, rightclick is a no-op
			return
		end

		player_trading_with[name] = self

		local inv = minetest.get_inventory({type="detached", name="mobs_mc:trade_"..name})
		if not inv then
			return
		end

		set_trade(self, clicker, inv, 1)

		show_trade_formspec(name, self)

		-- Behaviour stuff:
		-- Make villager look at player and stand still
		local selfpos = self.object:get_pos()
		local clickerpos = clicker:get_pos()
		local dir = vector.direction(selfpos, clickerpos)
		self.object:set_yaw(minetest.dir_to_yaw(dir))
		stand_still(self)
	end,

	_player_scan_timer = 0,
	_trading_players = {}, -- list of playernames currently trading with villager (open formspec)
	do_custom = function(self, dtime)
		check_summon(self,dtime)

		-- Stand still if player is nearby.
		if not self._player_scan_timer then
			self._player_scan_timer = 0
		end
		self._player_scan_timer = self._player_scan_timer + dtime

		-- Check infrequently to keep CPU load low
		if self._player_scan_timer > PLAYER_SCAN_INTERVAL then

			self._player_scan_timer = 0
			local selfpos = self.object:get_pos()
			local objects = minetest.get_objects_inside_radius(selfpos, PLAYER_SCAN_RADIUS)
			local has_player = false

			for o, obj in pairs(objects) do
				if obj:is_player() then
					has_player = true
					break
				end
			end
			if has_player then
				minetest.log("verbose", "[mobs_mc] Player near villager found!")
				stand_still(self)
			else
				--minetest.log("verbose", "[mobs_mc] No player near villager found!")
				self.walk_chance = DEFAULT_WALK_CHANCE
				self.jump = true
			end

			do_activity (self)

		end
	end,

	on_spawn = function(self)
		if not self._profession then
			self._profession = "unemployed"
			if math.random(100) == 1 then
				self._profession = "nitwit"
			end
		end
		if self._id then
			set_textures(self)
			return
		end
		self._id=minetest.sha1(minetest.get_gametime()..minetest.pos_to_string(self.object:get_pos())..tostring(math.random()))
		set_textures(self)
	end,
	on_die = function(self, pos)
		-- Close open trade formspecs and give input back to players
		local trading_players = self._trading_players
		if trading_players then
			for name, _ in pairs(trading_players) do
				minetest.close_formspec(name, "mobs_mc:trade_"..name)
				local player = minetest.get_player_by_name(name)
				if player then
					return_fields(player)
				end
			end
		end

		local bed = self._bed
		if bed then
			local bed_meta = minetest.get_meta(bed)
			bed_meta:set_string("villager", nil)
			mcl_log("Died, so bye bye bed")
		end
		local jobsite = self._jobsite
		if jobsite then
			local jobsite_meta = minetest.get_meta(jobsite)
			jobsite_meta:set_string("villager", nil)
			mcl_log("Died, so bye bye jobsite")
		end
	end,
})


--[[
Villager spawning in mcl_villages
mcl_mobs:spawn_specific(
"mobs_mc:villager",
"overworld",
"ground",
{
"FlowerForest",
"Swampland",
"Taiga",
"ExtremeHills",
"BirchForest",
"MegaSpruceTaiga",
"MegaTaiga",
"ExtremeHills+",
"Forest",
"Plains",
"ColdTaiga",
"SunflowerPlains",
"RoofedForest",
"MesaPlateauFM_grasstop",
"ExtremeHillsM",
"BirchForestM",
},
0,
minetest.LIGHT_MAX+1,
30,
20,
4,
mobs_mc.water_level+1,
mcl_vars.mg_overworld_max)
--]]
-- spawn eggs
mcl_mobs:register_egg("mobs_mc:villager", S("Villager"), "#563d33", "#bc8b72", 0)
