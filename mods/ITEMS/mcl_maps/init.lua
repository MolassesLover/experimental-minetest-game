-- Turn empty map into filled map by rightclick
local make_filled_map = function(itemstack, placer, pointed_thing)
	local new_map = ItemStack("mcl_maps:filled_map")
	itemstack:take_item()
	if itemstack:is_empty() then
		return new_map
	else
		local inv = placer:get_inventory()
		if inv:room_for_item("main", new_map) then
			inv:add_item("main", new_map)
		else
			minetest.add_item(placer:getpos(), new_map)
		end
		return itemstack
	end
end

minetest.register_craftitem("mcl_maps:empty_map", {
	description = "Empty Map",
	inventory_image = "mcl_maps_map_empty.png",
	groups = { not_in_creative_inventory = 1 },
	on_place = make_filled_map,
	on_secondary_use = make_filled_map,
	stack_max = 64,
})

-- Enables minimap if carried in hotbar.
-- If this item is NOT in the hotbar, the minimap is unavailable
-- Note: This is not at all like Minecraft right now. Minetest's minimap is pretty overpowered, it
-- has a very greatly zoomed-out version and even a radar mode
minetest.register_craftitem("mcl_maps:filled_map", {
	description = "Map",
	inventory_image = "mcl_maps_map_filled.png^(mcl_maps_map_filled_markings.png^[colorize:#000000)",
	stack_max = 1,
})

minetest.register_craft({
	output = "mcl_maps:filled_map",
	recipe = {
		{ "mcl_core:paper", "mcl_core:paper", "mcl_core:paper" },
		{ "mcl_core:paper", "group:compass", "mcl_core:paper" },
		{ "mcl_core:paper", "mcl_core:paper", "mcl_core:paper" },
	}
})

local function has_item_in_hotbar(player, item)
	-- Requirement: player carries the tool in the hotbar
	local inv = player:get_inventory()
	local hotbar = player:hud_get_hotbar_itemcount()
	for i=1, hotbar do
		if inv:get_stack("main", i):get_name() == item then
			return true
		end
	end
	return false
end

-- Checks if player is still allowed to display the minimap
local function update_minimap(player)
	if has_item_in_hotbar(player, "mcl_maps:filled_map") then
		player:hud_set_flags({minimap = true})
	else
		player:hud_set_flags({minimap = false})
	end
end

minetest.register_on_joinplayer(function(player)
	update_minimap(player)
end)

local updatetimer = 0
minetest.register_globalstep(function(dtime)
	updatetimer = updatetimer + dtime
	if updatetimer > 0.1 then
		local players = minetest.get_connected_players()
		for i=1, #players do
			update_minimap(players[i])
		end
		updatetimer = updatetimer - dtime
	end
end)
