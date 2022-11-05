
local function check_spawn_pos(pos)
	return minetest.get_natural_light(pos) < 7
end

local function spawn_zombies(self)
	local nn = minetest.find_nodes_in_area_under_air(vector.offset(self.pos,-32,-32,-32),vector.offset(self.pos,32,32,32),{"group:solid"})
	table.shuffle(nn)
	for i=1,20 do
		local p = vector.offset(nn[i%#nn],0,1,0)
		if check_spawn_pos(p) then
			local m = mcl_mobs.spawn(p,"mobs_mc:zombie")
			local l = m:get_luaentity()
			mcl_mobs:gopath(m:get_luaentity(),self.pos)
			table.insert(self.mobs,m)
			self.health_max = self.health_max + l.health
		end
	end
end

mcl_events.register_event("zombie_siege",{
	readable_name = "Zombie Siege",
	max_stage = 1,
	health = 1,
	health_max = 1,
	exclusive_to_area = 128,
	enable_bossbar = false,
	cond_start  = function(self)
		local t = minetest.get_timeofday()
		local r = {}
		for _,p in pairs(minetest.get_connected_players()) do
			local village = mcl_raids.find_village(p:get_pos())
			if t < 0.1 and village then
				table.insert(r,{ player = p:get_player_name(), pos = village})
			end
		end
		if #r > 0 then return r end
	end,
	on_start = function(self)
		self.mobs = {}
		self.health_max = 1
		self.health = 0
	end,
	cond_progress = function(self)
		local m = {}
		local h = 0
		for k,o in pairs(self.mobs) do
			if o and o:get_pos() then
				local l = o:get_luaentity()
				h = h + l.health
				table.insert(m,o)
			end
		end
		self.mobs = m
		self.health = h
		self.percent = math.max(0,(self.health / self.health_max ) * 100)
		if #m < 1 then
			return true end
	end,
	on_stage_begin = spawn_zombies,
	cond_complete = function(self)
		local m = {}
		for k,o in pairs(self.mobs) do
			if o and o:get_pos() then
				local l = o:get_luaentity()
				table.insert(m,o)
			end
		end
		return self.stage >= self.max_stage and #m < 1
	end,
	on_complete = function(self)
		--minetest.log("SIEGE complete")
		--awards.unlock(self.player,"mcl:hero_of_the_village")
	end,
})
