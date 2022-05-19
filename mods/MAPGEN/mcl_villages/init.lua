settlements = {}
settlements.modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(settlements.modpath.."/const.lua")
dofile(settlements.modpath.."/utils.lua")
dofile(settlements.modpath.."/foundation.lua")
dofile(settlements.modpath.."/buildings.lua")
dofile(settlements.modpath.."/paths.lua")
--dofile(settlements.modpath.."/convert_lua_mts.lua")
--
-- load settlements on server
--
settlements.grundstellungen()


local villagegen={}
--
-- register block for npc spawn
--
minetest.register_node("mcl_villages:stonebrickcarved", {
	description = ("Chiseled Stone Village Bricks"),
	_doc_items_longdesc = doc.sub.items.temp.build,
	tiles = {"mcl_core_stonebrick_carved.png"},
	stack_max = 64,
	drop = "mcl_core:stonebrickcarved",
	groups = {pickaxey=1, stone=1, stonebrick=1, building_block=1, material_stone=1},
	sounds = mcl_sounds.node_sound_stone_defaults(),
	is_ground_content = false,
	_mcl_blast_resistance = 6,
	_mcl_hardness = 1.5,
})

minetest.register_node("mcl_villages:structblock", {drawtype="airlike",groups = {not_in_creative_inventory=1},})



--[[ Enable for testing, but use MineClone2's own spawn code if/when merging.
--
-- register inhabitants
--
if minetest.get_modpath("mobs_mc") then
  mobs:register_spawn("mobs_mc:villager", --name
    {"mcl_core:stonebrickcarved"}, --nodes
    15, --max_light
    0, --min_light
    20, --chance
    7, --active_object_count
    31000, --max_height
    nil) --day_toggle
end
--]]

local function spawn_villagers(minp,maxp)
	local beds=minetest.find_nodes_in_area(minp,maxp,{"mcl_beds:bed_red_bottom"})
	for _,bed in pairs(beds) do
		minetest.get_meta(bed):set_string("villagebed","true")
		local v=minetest.add_entity(bed,"mobs_mc:villager")
		if v then
			v:get_luaentity().bed = bed
		end
	end
	local p = minetest.find_node_near(minp,50,"mcl_core:grass_path")
	minetest.add_entity(p,"mobs_mc:iron_golem")
end

--
-- on map generation, try to build a settlement
--
local function build_a_settlement(minp, maxp, blockseed)
	local pr = PseudoRandom(blockseed)

	-- fill settlement_info with buildings and their data
	local settlement_info = settlements.create_site_plan(maxp, minp, pr)
	if not settlement_info then return end

	-- evaluate settlement_info and prepair terrain
	settlements.terraform(settlement_info, pr)

	-- evaluate settlement_info and build paths between buildings
	settlements.paths(settlement_info)

	-- evaluate settlement_info and place schematics
	settlements.place_schematics(settlement_info, pr)

	minetest.after(60,function()
		spawn_villagers(minp,maxp)
	end) --give the village some time to fully generate
end

local function ecb_village(blockpos, action, calls_remaining, param)
	if calls_remaining >= 1 then return end
	local minp, maxp, blockseed = param.minp, param.maxp, param.blockseed
	build_a_settlement(minp, maxp, blockseed)
end

-- Disable natural generation in singlenode.
local mg_name = minetest.get_mapgen_setting("mg_name")
if mg_name ~= "singlenode" then
	mcl_mapgen_core.register_generator("villages", nil, function(minp, maxp, blockseed)
		-- don't build settlement underground
		if maxp.y < 0 then return end
		-- randomly try to build settlements
		if blockseed % 77 ~= 17 then return end
		-- needed for manual and automated settlement building
		-- don't build settlements on (too) uneven terrain
		local n=minetest.get_node_or_nil(minp)
		if n and n.name == "mcl_villages:structblock" then return end
		if villagegen[minetest.pos_to_string(minp)] ~= nil then return end
		minetest.set_node(minp,{name="mcl_villages:structblock"})

		local height_difference = settlements.evaluate_heightmap()
		if height_difference > max_height_difference then return end

		villagegen[minetest.pos_to_string(minp)]={minp=vector.new(minp), maxp=vector.new(maxp), blockseed=blockseed}
	end)
end

minetest.register_lbm({
	name = "mcl_villages:structblock",
	run_at_every_load = true,
	nodenames = {"mcl_villages:structblock"},
	action = function(pos, node)
		minetest.set_node(pos, {name = "air"})
		if not villagegen[minetest.pos_to_string(pos)] then return end
		local minp=villagegen[minetest.pos_to_string(pos)].minp
		local maxp=villagegen[minetest.pos_to_string(pos)].maxp
		minetest.emerge_area(minp, maxp, ecb_village, villagegen[minetest.pos_to_string(minp)])
		villagegen[minetest.pos_to_string(minp)]=nil
	end
})
-- manually place villages
if minetest.is_creative_enabled("") then
	minetest.register_craftitem("mcl_villages:tool", {
		description = "mcl_villages build tool",
		inventory_image = "default_tool_woodshovel.png",
		-- build ssettlement
		on_place = function(itemstack, placer, pointed_thing)
			if not pointed_thing.under then return end
			local minp = vector.subtract(	pointed_thing.under, half_map_chunk_size)
		        local maxp = vector.add(	pointed_thing.under, half_map_chunk_size)
			build_a_settlement(minp, maxp, math.random(0,32767))
		end
	})
	mcl_wip.register_experimental_item("mcl_villages:tool")
end
