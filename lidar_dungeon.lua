-- title:   LiDAR Dungeon
-- author:  Wojciech Graj
-- desc:    A Bullet-Hell Roguelike made for 7DRL2023
-- site:    https://github.com/wojciech-graj/LiDAR-Dungeon
-- license: AGPL-3.0-or-later
-- version: 1.0
-- script:  lua

--[[
    LiDAR Dungeon
    Copyright (C) 2023  Wojciech Graj

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

--- Conventions
-- VARIABLE delta: time since last frame (ms)
-- VARIABLE g_*: global variable
-- VARIABLE dir_*: normalized direction
-- VARIABLE c_*: constant variable
-- VARIABLE room: {start_x, start_x, end_x, end_y}
-- FUNCTION Class:process(delta): executed every frame. May return boolean,
-- where true signifies that object should be deleted

--- Interfaces
-- Entity:
-- VARIABLES: pos_x, pos_y, angle, health
-- FUNCTIONS: move_abs, move_rel, damage, draw_sprite

--- Map Data
-- 0: Empty
-- &0x7: Enemy count
-- &0x38: Tile:
-- 8: Wall
-- 16: Item
-- 24: Inactive Enemy
-- 32: Exit
-- 40: Boss
-- Temporary values:
-- 128: Map filler
-- 1: Map air filler

----------------------------------------
-- utility functions -------------------
----------------------------------------

--- Calculate a ray-map intersection
-- Uses Digital Differential Analyzer (DDA) voxel traversal to find closest wall
-- intersection.
-- @return dist number, side int
function g_ray_isect(pos_x, pos_y, dir_x, dir_y)
   local math_floor = math.floor
   local math_abs = math.abs

   local map_x = math_floor(pos_x)
   local map_y = math_floor(pos_y)
   local delta_dist_x = math_abs(1 / dir_x)
   local delta_dist_y = math_abs(1 / dir_y)

   local step_x
   local side_dist_x
   if dir_x < 0 then
      step_x = -1
      side_dist_x = (pos_x - map_x) * delta_dist_x
   else
      step_x = 1
      side_dist_x = (map_x + 1.0 - pos_x) * delta_dist_x
   end

   local step_y
   local side_dist_y
   if dir_y < 0 then
      step_y = -1
      side_dist_y = (pos_y - map_y) * delta_dist_y
   else
      step_y = 1
      side_dist_y = (map_y + 1.0 - pos_y) * delta_dist_y
   end

   -- DDA
   local side
   local iters = 0
   while iters < 96 do
      if side_dist_x < side_dist_y then
         side_dist_x = side_dist_x + delta_dist_x
         map_x = map_x + step_x
         side = 0
      else
         side_dist_y = side_dist_y + delta_dist_y
         map_y = map_y + step_y
         side = 1
      end
      iters = iters + 1
      tile_data = mget(map_x, map_y)
      if tile_data & 0x38 == 8 then
         break
      end
   end

   local dist
   if side == 0 then
      dist = side_dist_x - delta_dist_x
   else -- side == 1
      dist = side_dist_y - delta_dist_y
   end

   return dist, side
end

--- Get ray-circle collision
-- @return squared distance along ray if colliding, 1e9 otherwise
function g_ray_circ_collides(rel_pos_x, rel_pos_y, dir_x, dir_y, rad)
   if (rel_pos_x * dir_x + rel_pos_y * dir_y) / math.sqrt(rel_pos_x * rel_pos_x + rel_pos_y * rel_pos_y) > 0 then -- in front
      local dist_perp = math.abs(dir_x * rel_pos_y - dir_y * rel_pos_x)
      if dist_perp < rad then -- within radius
         return rel_pos_x * rel_pos_x + rel_pos_y * rel_pos_y - dist_perp * dist_perp
      end
   end
   return 1e9
end

--- Spawn explosion projectiles
function g_explode(pos_x, pos_y)
   local table_insert = table.insert
   local projs = g_projs
   local math_cos = math.cos
   local math_sin = math.sin
   for theta = 0, 6.28, .55 do
      table_insert(projs, Proj.new(pos_x, pos_y, theta, .005, .5, 0, 3))
   end
end

--- Pick up item
function g_item_pickup(pos_x, pos_y)
   mset(pos_x, pos_y, mget(pos_x, pos_y) & 0x7)
   g_state = 2
   sfx(21)
   local math_random = math.random

   -- select 2 different item types
   local item_1 = Item.new()
   local item_2
   repeat
      item_2 = Item.new()
   until (item_1.type_idx ~= item_2.type_idx)

   g_items = {
      item_1,
      item_2,
   }
end

-- Draw UI
function g_ui_render()
   -- Draw borders
   map(210, 34, 5, 17, 200, 0)

   local player = g_player

   -- Draw bars
   map(217 - player.health, 51, 1, 3, 208, 8)
   map(210 + 7 * player.ping_cooldown / player.ping_cooldown_max, 57, 1, 3, 216, 8)
   map(210 + 7 * player.weapon.cooldown / player.weapon.cooldown_max, 54, 1, 3, 224, 8)

   -- Draw compass
   local comp_pos_x = g_comp_pos_x
   local comp_pos_y = g_comp_pos_y
   local dir_x_comp
   local dir_y_comp
   if comp_pos_x == -1 and comp_pos_y == -1 then
      local theta = g_t / 300 + math.random() * .5
      dir_x_comp = math.cos(theta) * 4
      dir_y_comp = math.sin(theta) * 4
   else
      dir_x_comp = comp_pos_x - player.pos_x
      dir_y_comp = comp_pos_y - player.pos_y
      local dir_comp_mul = 4 / math.sqrt(dir_y_comp * dir_y_comp + dir_x_comp * dir_x_comp)
      dir_x_comp = dir_x_comp * dir_comp_mul
      dir_y_comp = dir_y_comp * dir_comp_mul
   end
   line(220, 4, 220 + dir_x_comp, 4 + dir_y_comp, 2)

   local string_format = string.format
   local math_floor = math.floor

   -- Print self stats
   print("SELF", 208, 34, 2, true)
   print(string_format("SPD:%.1f", player.speed * 1000), 209, 42, 2, false, 1, true)

   -- Print scanner stats
   print("SCAN", 208, 50, 8, true)
   print(string_format("RNG:%d", math_floor(player.ping_range)), 209, 58, 8, false, 1, true)
   print(string_format("REL:%.1f", player.ping_cooldown_max * .001), 209, 66, 8, false, 1, true)
   print(string_format("SPR:%d", math_floor(player.ping_spread * 57.296)), 209, 74, 8, false, 1, true)

   -- Print weapon stats
   local weapon = player.weapon
   if weapon.proj_type == 0 then
      print("GUN", 212, 82, 7, true)
   else -- weapon.proj_type == 1
      print("RCKT", 208, 82, 7, true)
   end
   print(string_format("DMG:%.1f", weapon.damage), 209, 90, 7, false, 1, true)
   print(string_format("REL:%.1f", weapon.cooldown_max * .001), 209, 98, 7, false, 1, true)
   print(string_format("BUL:%d", weapon.proj_cnt), 209, 106, 7, false, 1, true)
   print(string_format("SPR:%d", math_floor(weapon.spread * 57.296)), 209, 114, 7, false, 1, true)
   print(string_format("RNG:%d", math_floor(weapon.range)), 209, 122, 7, false, 1, true)
end

--- pix, but with absolute position and checks to verify if on screen
function g_pix_bounded(pos_x, pos_y, color)
   local player = g_player
   if pos_x > player.pos_x_scr * 25 and pos_x < player.pos_x_scr * 25 + 25
      and pos_y > player.pos_y_scr * 17 and pos_y < player.pos_y_scr * 17 + 17 then
      pix((pos_x % 25) * 8, (pos_y % 17) * 8, color)
   end
end

--- Print rainbow text that bobs up and down
-- @param text table: table of characters to print
-- @param start int: color on which to start
-- @param range int: no. colors to include in rainbow
function g_print_rainbow(text, pos_x, pos_y, start, range)
   local t = g_t
   local color_start = t // 70
   local offset_y = t / 100
   local math_sin = math.sin

   for k, v in ipairs(text) do
      print(v, pos_x + 6 * k, pos_y + math_sin(offset_y + k * .7), (color_start + k) % range + start, true)
   end
end

--- Print stats
-- @param floors int or nil
function g_print_stats(stats, pos_x, pos_y, floors)
   local string_format = string.format
   local math_floor = math.floor

   if floors then
      print(string_format("Floors Cleared.....%d", floors), pos_x, pos_y, 13, true, 1, true)
      pos_y = pos_y + 8
   end

   local format_values = {
      stats.damage_taken,
      stats.damage_dealt,
      stats.bullets_fired,
      math_floor(stats.time_total / 1000),
      stats.bullets_taken,
      stats.pings,
      stats.items_collected,
      stats.enemies_destroyed,
      math_floor(stats.distance_travelled),
   }
   local formats = gc_stats_format_strings
   for i = 1, #formats do
      print(string_format(formats[i], format_values[i]), pos_x, pos_y + i * 8 - 8, 13, true, 1, true)
   end
end
gc_stats_format_strings = {
   "Damage Taken.......%.1f",
   "Damage Dealt.......%.1f",
   "Bullets Fired......%d",
   "Seconds Elapsed....%d",
   "Bullets Taken......%d",
   "Scans Performed....%d",
   "Upgrades Obtained..%d",
   "Enemies Destroyed..%d",
   "Distance Travelled.%d",
}

--- Place an exit on the map
function g_exit_spawn(tile_x, tile_y)
   g_comp_pos_x = tile_x + .5
   g_comp_pos_y = tile_y + .5
   mset(tile_x, tile_y, (mget(tile_x, tile_y) & 0x7) + 32)
end

--- pix, but for the title screen
function g_pix_title_screen(pos_x, pos_y, color)
   pix((pos_x - 208) * 8, (pos_y - 102) * 8, color)
end

----------------------------------------
-- map generation ----------------------
----------------------------------------

--- Naming:
-- s*: (start) top left corner
-- e*: (end) bottom right corner
-- l*: (length) width/height including walls
-- r*: (room) relating to current room
-- t*: screen index

--- Adds area to free areas if suitable
function g_map_gen_add_area(tab, sx, sy, ex, ey, lx, ly)
   if lx >= 6 and ly >= 6 then
      table.insert(tab, {sx, sy, ex, ey, lx, ly})
   end
end

--- Digs a corridor out of room
function g_dig_corridor(x, y, dx, dy)
   local math_random = math.random

   -- Don't always dig tunnel
   if math_random() < .3 then
      return
   end

   while mget(x, y) ~= 1 do -- haven't reached open space
      -- Dig
      mset(x, y, 1)
      if mget(x + dy, y + dx) ~= 1 then
         mset(x + dy, y + dx, 8)
      end
      if mget(x - dy, y - dx) ~= 1 then
         mset(x - dy, y - dx, 8)
      end

      -- Check edge of map collision, exit if so
      if x >= 199 then
         mset(199, y, 8)
         return
      elseif x <= 0 then
         mset(0, y, 8)
         return
      end
      if y >= 118 then
         mset(x, 118, 8)
         return
      elseif y <= 0 then
         mset(x, 0, 8)
         return
      end

      -- Meander sometimes
      if math_random() < .1 then
         x = x + dy
         y = y + dx
      else
         x = x + dx
         y = y + dy
      end
   end
end

--- Places a tile cnt times in a room
function g_map_place_rand(room, tile, cnt)
   local math_random = math.random
   for _ = 1, cnt do
      mset(
         math_random(room[1] + 2, room[3] - 2),
         math_random(room[2] + 2, room[4] - 2),
         tile
      )
   end
end

--- Generates map
function g_map_gen()
   -- Clear map
   for x = 0, 199 do
      for y = 0, 118 do
         mset(x, y, 128)
      end
   end

   local math_min = math.min
   local math_max = math.max
   local table_insert = table.insert
   local table_remove = table.remove
   local table_unpack = table.unpack
   local math_random = math.random
   local math_floor = math.floor
   local map_gen_add_area = g_map_gen_add_area

   local rooms = {}

   -- Place rooms
   for tx = 0, 7 do -- Generate each screen separately to limit rooms to single screen
      for ty = 0, 6 do
         local free_area = {{25 * tx, 17 * ty, 25 * tx + 24, 17 * ty + 16, 24, 16}}
         while #free_area > 0 do
            local sx, sy, ex, ey, lx, ly = table_unpack(table_remove(free_area))

            -- Place room
            local rlx = math_random(6, math_min(lx, 11))
            local rly = math_random(6, math_min(ly, 9))
            local rsx = (ex - rlx ~= sx) and math_random(sx, ex - rlx) or sx
            local rsy = (ey - rly ~= sy) and math_random(sy, ey - rly) or sy
            local rex = rsx + rlx
            local rey = rsy + rly
            table_insert(rooms, {rsx, rsy, rex, rey})

            -- Draw to map
            for x = rsx, rex do
               mset(x, rsy, 8)
               mset(x, rey, 8)
            end
            for y = rsy, rey do
               mset(rsx, y, 8)
               mset(rex, y, 8)
            end
            for y = rsy + 1, rey - 1 do
               for x = rsx + 1, rex - 1 do
                  mset(x, y, 1)
               end
            end

            local right = ex - rex
            local left = rsx - sx
            local top = rsy - sy
            local bottom = ey - rey

            -- Split remaining space into 4 areas
            if math_max(left, right) > math_max(top, bottom) then
               map_gen_add_area(free_area, sx, sy, rsx, ey, left, ly)
               map_gen_add_area(free_area, rex, sy, ex, ey, right, ly)
               map_gen_add_area(free_area, rsx, sy, rex, rsy, rlx, top)
               map_gen_add_area(free_area, rsx, rey, rex, ey, rlx, bottom)
            else
               map_gen_add_area(free_area, sx, sy, ex, rsy, lx, top)
               map_gen_add_area(free_area, sx, rey, ex, ey, lx, bottom)
               map_gen_add_area(free_area, sx, rsy, rsx, rey, left, rly)
               map_gen_add_area(free_area, rex, rsy, ex, rey, right, rly)
            end
         end
      end
   end

   local dig_corridor = g_dig_corridor

   -- Dig corridors
   for _, room in pairs(rooms) do
      local sx, sy, ex, ey = table_unpack(room)
      dig_corridor(ex, sy + math_random(ey - sy - 2), 1, 0)
      dig_corridor(sx, sy + math_random(ey - sy - 2), -1, 0)
      dig_corridor(sx + math_random(ex - sx - 2), ey, 0, 1)
      dig_corridor(sx + math_random(ex - sx - 2), sy, 0, -1)
   end

   -- Flood-fill air placeholder with air
   local room = rooms[1]
   local x = room[1] + 1
   local y = room[2] + 1
   local stack = {{x, y}}
   while #stack > 0 do
      local x, y = table_unpack(table_remove(stack))
      if mget(x, y) == 1 then
         mset(x, y, 0)
         table_insert(stack, {x - 1, y})
         table_insert(stack, {x + 1, y})
         table_insert(stack, {x, y - 1})
         table_insert(stack, {x, y + 1})
      end
   end

   -- Count disconnected tiles and fill
   local discon_cnt = 0
   for x = 0, 199 do
      for y = 0, 118 do
         local tile_data = mget(x, y)
         if tile_data == 128 then
            mset(x, y, 8)
         elseif tile_data == 1 then
            discon_cnt = discon_cnt + 1
            mset(x, y, 8)
         end
      end
   end

   -- Re-do generation if too many disconnected tiles
   if discon_cnt > 363 then
      return g_map_gen()
   end

   -- Cull invalid rooms
   if discon_cnt > 0 then
      for k, v in pairs(rooms) do
         if mget(v[1], v[2]) ~= 1 then
            table_remove(rooms, k)
         end
      end
   end

   local map_place_rand = g_map_place_rand

   local start_room = table_remove(rooms, math_random(#rooms))
   map_place_rand(start_room, 16, 3) -- Place 3 upgrades in start room

   -- Place items, enemies
   for _, room in pairs(rooms) do
      map_place_rand(room, 8, math_random(3) - 1)
      map_place_rand(room, 16, math_random() < .15 and 1 or 0)
      map_place_rand(room, 24, math.floor(math_random(2, 8) ^ .7 - 1))
   end

   -- Place exit
   local exit_room
   repeat
      exit_room = rooms[math_random(#rooms)]
   until ((start_room[1] - exit_room[1]) ^ 2 + (start_room[2] - exit_room[2]) ^ 2 > 70)
   g_exit_spawn(math_random(exit_room[1] + 2, exit_room[3] - 2),
      math_random(exit_room[2] + 2, exit_room[4] - 2)
   )

   return start_room
end

----------------------------------------
-- Item --------------------------------
----------------------------------------

--- type_idx:
-- 1: speed
-- 2: ping
-- 3: gun
-- 4: rocket
-- 5: repair

--- subtype_idx:
-- ping:
-- 1: range
-- 2: spread
-- 3: cooldown
-- 4: bounce
-- gun/rocket:
-- 1: new weapon
-- 2: bullet_cnt
-- 3: damage
-- 4: spread
-- 5: cooldown
-- 6: range
-- 7: bounce

Item = {
   type_idx = 0,
   data = nil,
   subtype_idx = 1,
   desc = nil,
   c_data = {
      [1] = {
         name = "THRUSTER",
         color = 2,
      },
      [2] = {
         name = " SCANNER",
         color = 8,
      },
      [3] = {
         name = "     GUN",
         color = 7,
      },
      [4] = {
         name = " ROCKETS",
         color = 7,
      },
      [5] = {
         name = "  REPAIR",
         color = 2,
      },
   },
}
Item.__index = Item

function Item.new()
   local self = setmetatable({}, Item)
   local math_random = math.random
   self.type_idx = math_random(5)

   if self.type_idx == 1 then
      self.data = math_random() * .0002 + .0001
      self.desc = string.format("+%.1f\nSPEED", self.data * 1000)
   elseif self.type_idx == 2 then
      local roll = math_random()
      if roll < .31 then
         self.subtype_idx = 1
         self.data = math_random(3)
         self.desc = string.format("+%d\nRANGE", self.data)
      elseif roll < .62 then
         self.subtype_idx = 2
         self.data = math_random(10)
         self.desc = string.format("+%d DEG\nSPREAD", self.data)
         self.data = self.data * .0175
      elseif roll < .93 then
         self.subtype_idx = 3
         self.data = math.random() * .06 + .01
         self.desc = string.format("-%.2f\nCOOLDOWN", self.data)
      else
         self.subtype_idx = 4
         self.data = math_random() * .3 + .2
         self.desc = string.format("+1BOUNCE\n-%d%%RNG", math.floor(self.data * 100))
      end
   elseif self.type_idx == 3 or self.type_idx == 4 then
      local player = g_player
      local roll = math_random()
      if roll < .05 then
         self.subtype_idx = 1
         local bullet_cnt = player.weapon.proj_cnt
         local damage = player.weapon.damage + (math_random() - .5)
         local spread = math_random(1000) / 1000
         local cooldown = math_random(500, 1000)
         local speed = (cooldown - 500) // 250 + 1
         self.data = Weapon.new(self.type_idx - 3, 1, bullet_cnt, spread, .1, cooldown, 20, -1, damage, .005)
         self.desc = string.format("%dBUL %dDMG\n%sSPR %sSPD", bullet_cnt, math.max(1, math.floor(damage)), math.floor(spread * 9), speed)
      else
         self.type_idx = player.weapon.proj_type + 3
         if roll < .1 then
            self.subtype_idx = 2
            self.data = math_random() * .2 + .2
            self.desc = string.format("+1BULLET\n-%d%%DMG", math.floor(self.data * 100))
         elseif roll < .36 then
            self.subtype_idx = 3
            self.data = math_random() * .2 + .1
            self.desc = string.format("+%.1f\nDAMAGE", self.data)
         elseif roll < .51 then
            self.subtype_idx = 4
            self.data = math_random(20) - 10
            self.desc = string.format("%s%d DEG\nSPREAD", (self.data < 0) and "" or "+", self.data)
            self.data = self.data * .0175
         elseif roll < .66 then
            self.subtype_idx = 5
            self.data = math_random() * .06 + .01
            self.desc = string.format("-%.2f\nCOOLDOWN", self.data)
         elseif roll < .95 then
            self.subtype_idx = 6
            self.data = math.random(2)
            self.desc = string.format("+%d\nRANGE", self.data)
         else
            self.subtype_idx = 7
            self.data = math_random() * .3 + .2
            self.desc = string.format("+1BOUNCE\n-%d%%RNG", math.floor(self.data * 100))
         end
      end
   else -- self.type_idx == 5
      self.data = math_random(3) + 1
      self.desc = string.format("+%d\nHEALTH", self.data)
   end

   return self
end

function Item:render(pos_x, pos_y)
   map(206 + 4 * self.type_idx, 17, 4, 4, pos_x, pos_y)
   local data = self.c_data[self.type_idx]
   print(data.name, pos_x, 34 + pos_y, data.color, false, 1, true)
   print(self.desc, pos_x, 42 + pos_y, data.color, false, 1, true)
end

function Item:apply()
   local player = g_player
   if self.type_idx == 1 then
      player.speed = player.speed + self.data
   elseif self.type_idx == 2 then
      if self.subtype_idx == 1 then
         player.ping_range = player.ping_range + self.data
      elseif self.subtype_idx == 2 then
         player.ping_spread = player.ping_spread + self.data
      elseif self.subtype_idx == 3 then
         player.ping_cooldown_max = math.max(player.ping_cooldown_max - self.data, 100)
      else -- self.subtype_idx == 4
         player.ping_bounces = player.ping_bounces + 1
         player.ping_range = player.ping_range * (1 - self.data)
      end
   elseif self.type_idx == 3 or self.type_idx == 4 then
      if self.subtype_idx == 1 then
         player.weapon = self.data
      elseif self.subtype_idx == 2 then
         player.weapon.proj_cnt = player.weapon.proj_cnt + 1
         player.weapon.damage = player.weapon.damage * (1 - self.data)
      elseif self.subtype_idx == 3 then
         player.weapon.damage = player.weapon.damage + self.data
      elseif self.subtype_idx == 4 then
         player.weapon.spread = player.weapon.spread + self.data
      elseif self.subtype_idx == 5 then
         player.weapon.cooldown_max = math.max(player.weapon.cooldown_max - self.data, 100)
      elseif self.subtype_idx == 6 then
         player.weapon.range = player.weapon.range + self.data
      else -- self.subtype_idx == 7
         player.weapon.bounces = player.weapon.bounces + 1
         player.weapon.range = player.weapon.range * (1 - self.data)
      end
   else -- self.type_idx == 5
      player:heal(self.data)
   end
end

----------------------------------------
-- Entity ------------------------------
----------------------------------------

Entity = {}
Entity.__index = Entity

--- Move an entity relative to its angle
function Entity:move_rel(dist_front, dist_side)
   local dir_x_self = math.cos(self.angle)
   local dir_y_self = math.sin(self.angle)
   return self:move_abs(dist_front * dir_x_self + dist_side * dir_y_self, dist_front * dir_y_self - dist_side * dir_x_self)
end

--- Move an entity relative to the XY axes
function Entity:move_abs(dist_x, dist_y)
   local dist_mag = math.sqrt(dist_x * dist_x + dist_y * dist_y)
   local dist_invmag = 1 / dist_mag
   local dir_x = dist_x * dist_invmag
   local dir_y = dist_y * dist_invmag
   local isect_dist = g_ray_isect(self.pos_x, self.pos_y, dir_x, dir_y)
   if isect_dist > .4 then -- not approaching wall
      local dist_min = math.min(dist_mag, math.max(0, isect_dist - .4))
      self.pos_x = self.pos_x + dir_x * dist_min
      self.pos_y = self.pos_y + dir_y * dist_min
      return dist_min
   end
   return 0
end

--- Draw a triangular sprite
function Entity:draw_sprite(color)
   local player = g_player

   if self.pos_x > player.pos_x_scr * 25 and self.pos_x < player.pos_x_scr * 25 + 25
      and self.pos_y > player.pos_y_scr * 17 and self.pos_y < player.pos_y_scr * 17 + 17 then
      local math_cos = math.cos
      local math_sin = math.sin
      local pos_x_scl = (self.pos_x % 25) * 8
      local pos_y_scl = (self.pos_y % 17) * 8

      tri(
         pos_x_scl + 4 * math_cos(self.angle),
         pos_y_scl + 4 * math_sin(self.angle),
         pos_x_scl + 4 * math_cos(self.angle + 2.7),
         pos_y_scl + 4 * math_sin(self.angle + 2.7),
         pos_x_scl + 4 * math_cos(self.angle - 2.7),
         pos_y_scl + 4 * math_sin(self.angle - 2.7),
         color
      )
   end
end

----------------------------------------
-- Hitmark -----------------------------
----------------------------------------

-- type_idx:
-- 1: wall
-- 2: item
-- 3: exit

--- Map-Proj hit indicator
Hitmark = {
   pos_x = 0,
   pos_y = 0,
   age = 0,
   type_idx = 0,
}
Hitmark.__index = Hitmark

function Hitmark.new(pos_x, pos_y, type_idx)
   local self = setmetatable({}, Hitmark)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.type_idx = type_idx
   return self
end

function Hitmark:process(delta)
   self.age = self.age + delta
   local color
   if self.type_idx == 1 then
      color = 12 + self.age * .002
   elseif self.type_idx == 2 then
      color = 4
   else -- self.type_idx == 3
      color = 11
   end
   if g_state == 6 then
      g_pix_title_screen(self.pos_x, self.pos_y, color)
   else
      g_pix_bounded(self.pos_x, self.pos_y, color)
   end
   return self.age > 1000
end



----------------------------------------
-- Weapon ------------------------------
----------------------------------------

--- proj_type:
-- 0: bullet
-- 1: missile

--- target:
-- 0: player
-- 1: enemy

Weapon = {
   proj_type = 0,
   damage = 0,
   target = 0,
   proj_cnt = 0,
   spread = 0,
   accuracy = 0,
   cooldown = 0,
   cooldown_max = 0,
   range = 0,
   ammo = 0,
   speed = 0,
   bounces = 0,
}
Weapon.__index = Weapon

function Weapon.new(proj_type, target, proj_cnt, spread, accuracy, cooldown, range, ammo, damage, speed, bounces)
   local self = setmetatable({}, Weapon)
   self.proj_type = proj_type
   self.target = target
   self.proj_cnt = proj_cnt
   self.spread = spread
   self.accuracy = accuracy
   self.cooldown_max = cooldown
   self.range = range
   self.ammo = ammo
   self.damage = damage
   self.speed = speed
   self.bounces = bounces or 0
   return self
end

function Weapon.new_random(target)
   local math_random = math.random
   local wpn_type = math_random(4)
   if wpn_type == 1 then -- gun
      return Weapon.new(0,
         target,
         1,
         0,
         math_random() * .5,
         math_random(800, 1300),
         math_random(10, 15),
         -1,
         math_random() + .5,
         math_random() * .002 + .004,
         math_random() < .5 and 2 or 0
      )
   elseif wpn_type == 2 then -- shotgun
      return Weapon.new(0,
         target,
         math_random(2, 3),
         math_random() * .9,
         math_random() * .5,
         math_random(1000, 1500),
         math_random(6, 9),
         -1,
         1,
         math_random() * .002 + .003,
         math_random() < .1 and 3 or ((math_random() < .5) and 1 or 0)
      )
   elseif wpn_type == 3 then -- circle
      return Weapon.new(0,
         target,
         math_random(4, 6),
         3.14,
         .3,
         math_random(1000, 1200),
         math_random(6, 9),
         -1,
         1,
         math_random() * .002 + .0015,
         math_random() < .1 and 3 or 0
      )
   else -- wpn_type == 4 -- rapid-fire
      return Weapon.new(1,
         target,
         1,
         0,
         .4,
         math_random(300, 700),
         math_random(7, 11),
         -1,
         .5,
         math_random() * .001 + .0032,
         math_random() < .1 and 1 or 0
      )
   end
end

function Weapon:process(delta)
   self.cooldown = math.max(self.cooldown - delta, 0)
end

function Weapon:fire(pos_x, pos_y, angle)
   if self.cooldown == 0 and self.ammo ~= 0 then
      self.cooldown = self.cooldown_max
      self.ammo = self.ammo - 1
      local math_random = math.random
      local dangle = (self.proj_cnt == 1 and 1 or 2) * self.spread / self.proj_cnt
      local projs = g_projs
      local table_insert = table.insert
      for i = 1, self.proj_cnt do
         table_insert(projs, Proj.new(pos_x, pos_y, angle - self.spread + dangle * i + (2 * math.random() - 1) * self.accuracy, self.speed, self.range, self.bounces, self.target + 1 + 3 * self.proj_type, self.damage))
      end

      if self.target == 1 then
         local player = g_player
         player.stats_flr.bullets_fired = player.stats_flr.bullets_fired + self.proj_cnt
      end
   end
end

----------------------------------------
-- Enemy -------------------------------
----------------------------------------

--- Naming:
-- Enemy.b_*: (boss) boss-specific variables

--- ai_idx:
-- 1: follow
-- 2: encircle
-- 3: erratic
-- 4: RESERVED
-- 5: boss

Enemy = {
   pos_x = 0,
   pos_y = 0,
   angle = 0,
   display_timer = 0,
   move_abs = Entity.move_abs,
   move_rel = Entity.move_rel,
   draw_sprite = Entity.draw_sprite,
   speed = 0,
   health = 0,
   weapon = nil,
   ai_idx = 1,
   pos_x_player_last = 0,
   pos_y_player_last = 0,
   vel_side = 0,
   loot_chance = 0,
   -- b_ai_timer
   -- b_weapons
}
Enemy.__index = Enemy

function Enemy.new(pos_x, pos_y, speed, health, weapon, ai_idx, loot_chance)
   local self = setmetatable({}, Enemy)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.speed = speed
   self.health = health
   self.weapon = weapon
   self.ai_idx = ai_idx
   self.loot_chance = loot_chance or .33
   mset(pos_x, pos_y, mget(pos_x, pos_y) & 0x7)
   self:mark_area(true)
   return self
end

function Enemy.new_random(pos_x, pos_y)
   local math_random = math.random
   return Enemy.new(
      pos_x,
      pos_y,
      math_random() * .025 + .005,
      math_random(5 + g_player.floor * 2),
      Weapon.new_random(0),
      math_random(3)
   )
end

function Enemy.new_boss(pos_x, pos_y)
   local math_random = math.random
   local self = Enemy.new(
      pos_x,
      pos_y,
      math_random() * .005 + .04,
      15 + g_player.floor * 8,
      nil,
      5
   )
   self.b_ai_timer = 0
   self.b_weapons = {
      Weapon.new(0, 0, 6, 3.14, .4, 900, 17, -1, 1, .005, 2),
      Weapon.new(0, 0, 9, 1.5, .3, 750, 12, -1, 1, .006),
      Weapon.new(1, 0, 1, 0, .8, 350, 15, -1, 1, .008),
   }
   return self
end

-- Calculate tiles within hitbox on an axis
function Enemy.calc_occupied(pos)
   local pos_frac = pos % 1
   if pos_frac < .4 then
      return {pos, pos - 1}
   elseif pos_frac > .6 then
      return {pos, pos + 1}
   else
      return {pos}
   end
end

--- Mark/unmark map tiles containing self
-- @param mark boolean: true to mark, false to unmark
function Enemy:mark_area(mark)
   for _, v_x in pairs(self.calc_occupied(self.pos_x)) do
      for _, v_y in pairs(self.calc_occupied(self.pos_y)) do
         local tile_data = mget(v_x, v_y)
         mset(v_x, v_y, mark and tile_data + 1 or tile_data - 1)
      end
   end
end

function Enemy:process(delta)
   self.display_timer = self.display_timer + delta
   if self.display_timer < 500 then
      self:draw_sprite(2)
   end

   self:mark_area(false)

   local player = g_player
   local dir_x = player.pos_x - self.pos_x
   local dir_y = player.pos_y - self.pos_y
   local dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)

   if self.ai_idx < 5 then
      self.weapon:process(delta)
      local dir_invmag = 1 / dir_mag
      local isect_dist = g_ray_isect(self.pos_x, self.pos_y, dir_invmag * dir_x, dir_invmag * dir_y)
      local speed_fwd
      if dir_mag < isect_dist then -- in line-of-sight
         self.pos_x_player_last = player.pos_x
         self.pos_y_player_last = player.pos_y
         if dir_mag < 2 then
            speed_fwd = -self.speed
         elseif dir_mag > 3 then
            speed_fwd = self.speed
         else
            speed_fwd = 0
         end
         self.weapon:fire(self.pos_x, self.pos_y, self.angle)
         self.angle = math.atan2(dir_y, dir_x)
      else
         dir_x = self.pos_x_player_last - self.pos_x
         dir_y = self.pos_y_player_last - self.pos_y
         dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)
         speed_fwd = math.min(self.speed, dir_mag)
         self.angle = math.atan2(dir_y, dir_x)

         if isect_dist < 1 then -- wiggle to get unstuck
            self.angle = self.angle + (math.random() - .5) * .5
         end
      end

      if self.ai_idx == 1 then
         --
      elseif self.ai_idx == 2 or self.ai_idx == 3 then
         self.vel_side = self.vel_side + (math.random() - .5) * self.speed * .2
         if self.ai_idx == 3 then
            speed_fwd = speed_fwd + (math.random() - .5) * self.vel_side * 2
         end
      end
      self.vel_side = math.min(math.max(self.speed * -.4, self.vel_side), self.speed * .4)
      self:move_rel(speed_fwd, self.vel_side)
   else -- self.ai_idx == 5
      self.angle = math.atan2(dir_y, dir_x)
      self.b_ai_timer = self.b_ai_timer + delta
      local ai_state = (self.b_ai_timer // 7000) % 4
      if ai_state < 3 then
         local speed_fwd
         if dir_mag < 3.5 then
            speed_fwd = -self.speed
         elseif dir_mag > 5 then
            speed_fwd = self.speed
         else
            speed_fwd = 0
         end
         self:move_rel(speed_fwd, (math.random() - .5) * self.speed * .1)
         local weapon = self.b_weapons[ai_state + 1]
         weapon:process(delta)
         weapon:fire(self.pos_x, self.pos_y, self.angle)
      else -- ai_state == 3
         if #g_enemies < 4 and math.random() < .05 then
            local math_random = math.random
            table.insert(g_enemies, Enemy.new(self.pos_x,
               self.pos_y,
               .02,
               1,
               Weapon.new(1, 0, 1, 0, .2, 300, 7, -1, 1, .004),
               1,
               .1
            ))
         end
      end
   end

   self:mark_area(true)
end

function Enemy:damage(dmg)
   self.health = self.health - dmg
   if self.health <= 0 then
      local explode = g_explode
      local math_random = math.random

      self:mark_area(false)

      local explosion_cnt
      local explosion_spread
      if self.ai_idx == 5 then
         explosion_cnt = 20
         explosion_spread = 4

         -- Drop loot
         for i = 1, math_random(3) + 2 do
            local pos_x = self.pos_x + math_random(3) - 2
            local pos_y = self.pos_y + math_random(3) - 2
            local tile_data = mget(pos_x, pos_y)
            if tile_data < 8 then
               mset(pos_x, pos_y, tile_data + 16)
            end
         end

         sfx(22)
         g_exit_spawn(211, 127)
      else
         explosion_cnt = 5
         explosion_spread = 1
         local tile_data = mget(self.pos_x, self.pos_y)
         if math_random() < self.loot_chance and tile_data < 8 then
            mset(self.pos_x, self.pos_y, tile_data + 16)
            sfx(17)
         else
            sfx(19)
         end
      end

      for i = 1, explosion_cnt do
         explode(self.pos_x + (math_random() - .5) * explosion_spread, self.pos_y + (math_random() - .5) * explosion_spread)
      end

      local player = g_player
      player.stats_flr.enemies_destroyed = player.stats_flr.enemies_destroyed + 1
      return true
   end
   sfx(18)
   return false
end

function Enemy:pinged()
   self.display_timer = 0
end

----------------------------------------
-- Proj --------------------------------
----------------------------------------

--- type_idx:
-- 0: ping
-- 1: enemy's bullet
-- 2: player's bullet
-- 3: explosion
-- 4: homing enemy's bullet
-- 5: homing player's bullet
-- 6: firework

--- Projectile
Proj = {
   pos_x = 0,
   pos_y = 0,
   dir_x = 0,
   dir_y = 0,
   vel = 0,
   wall_dist = 0,
   wall_side = 0,
   dist_rem = 0,
   dist_max = 0,
   bounces_rem = 0,
   type_idx = 0,
   damage = 0,
}
Proj.__index = Proj

function Proj.new(pos_x, pos_y, angle, vel, dist_max, bounces, type_idx, damage)
   local self = setmetatable({}, Proj)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.dir_x = math.cos(angle)
   self.dir_y = math.sin(angle)
   self.vel = vel
   self.dist_max = dist_max
   self.dist_rem = dist_max
   self.bounces_rem = bounces
   self.type_idx = type_idx
   self.damage = damage
   if type_idx ~= 6 then
      self.wall_dist, self.wall_side = g_ray_isect(pos_x, pos_y, self.dir_x, self.dir_y)
   else -- type_idx == 6
      self.wall_dist = 1e9
   end
   return self
end

function Proj:process(delta)
   local dist = self.vel * delta
   self.dist_rem = self.dist_rem - dist
   if self.dist_rem < 0 then -- beyond range
      return true
   end

   while true do -- Repeat until wall collisions resolved
      local min_dist = math.min(self.wall_dist, dist)

      -- Entity collision
      if self.type_idx == 1 or self.type_idx == 4 then -- enemy's projectile
         local ray_circ_collides = g_ray_circ_collides
         local player = g_player
         local rel_pos_x = player.pos_x - self.pos_x
         local rel_pos_y = player.pos_y - self.pos_y

         -- Homing
         if self.type_idx == 4 then
            local tgt_angle = math.atan2(rel_pos_x * self.dir_y - rel_pos_y * self.dir_x,
               self.dir_x * rel_pos_x + self.dir_y * rel_pos_y)
            local dangle = math.min(math.max(-.005, tgt_angle), .005)
            local own_angle = math.atan2(self.dir_y, self.dir_x) - dangle
            self.dir_x = math.cos(own_angle)
            self.dir_y = math.sin(own_angle)
         end

         -- Collision
         local dist_coll_sqr = ray_circ_collides(rel_pos_x, rel_pos_y, self.dir_x, self.dir_y, .4)
         if dist_coll_sqr <= min_dist * min_dist then
            local dist_coll = math.sqrt(dist_coll_sqr)
            g_explode(self.pos_x + self.dir_x * dist_coll, self.pos_y + self.dir_y * dist_coll)
            player:damage(self.damage)
            return true
         end
      elseif self.type_idx == 0 or self.type_idx == 2 or self.type_idx == 5 then -- player's projectile or ping
         -- Homing
         if self.type_idx == 5 then
            local player = g_player
            local mouse_x, mouse_y = table.unpack(g_mouse)
            local rel_pos_x = mouse_x / 8 + player.pos_x_scr * 25 - self.pos_x
            local rel_pos_y = mouse_y / 8 + player.pos_y_scr * 17 - self.pos_y
            local tgt_angle = math.atan2(rel_pos_x * self.dir_y - rel_pos_y * self.dir_x,
               self.dir_x * rel_pos_x + self.dir_y * rel_pos_y)
            local dangle = math.min(math.max(-.015, tgt_angle), .015)
            local own_angle = math.atan2(self.dir_y, self.dir_x) - dangle
            self.dir_x = math.cos(own_angle)
            self.dir_y = math.sin(own_angle)
         end

         if mget(self.pos_x, self.pos_y) & 0x7 > 0 then -- on tile containing enemy
            local enemies = g_enemies
            local ray_circ_collides = g_ray_circ_collides
            for k, v in pairs(enemies) do
               local rel_pos_x = v.pos_x - self.pos_x
               local rel_pos_y = v.pos_y - self.pos_y

               -- Collision
               local dist_coll_sqr = ray_circ_collides(rel_pos_x, rel_pos_y, self.dir_x, self.dir_y, .4)
               if dist_coll_sqr <= min_dist * min_dist then
                  if self.type_idx == 0 then
                     v:pinged()
                  else -- self.type_idx == 2
                     local dist_coll = math.sqrt(dist_coll_sqr)
                     g_explode(self.pos_x + self.dir_x * dist_coll, self.pos_y + self.dir_y * dist_coll)
                     local player = g_player
                     player.stats_flr.damage_dealt = player.stats_flr.damage_dealt + self.damage
                     if v:damage(self.damage) then -- enemy should die
                        enemies[k] = nil
                     end
                     return true
                  end
               end
            end
         end
      end

      self.wall_dist = self.wall_dist - dist
      self.pos_x = self.pos_x + self.dir_x * min_dist
      self.pos_y = self.pos_y + self.dir_y * min_dist

      if self.type_idx == 0 then -- ping
         local tile_data = mget(self.pos_x, self.pos_y)
         local tile = tile_data & 0x38
         -- Show item or exit
         if tile == 16 or tile == 32 then -- item or exit
            local math_floor = math.floor
            local pos_x_floor = math_floor(self.pos_x)
            local pos_y_floor = math_floor(self.pos_y)
            local rad_x = 2 * (self.pos_x - pos_x_floor - .5)
            local rad_y = 2 * (self.pos_y - pos_y_floor - .5)
            local angle = math.atan2(rad_y, rad_x)
            table.insert(g_hitmarks, Hitmark.new(
               pos_x_floor + .5 + .3 * math.cos(angle),
               pos_y_floor + .5 + .3 * math.sin(angle),
               (tile == 16) and 2 or 3
            ))
            return false
         -- Spawn Enemy
         elseif tile_data == 24 or tile_data == 40 then
            local math_floor = math.floor
            local pos_x_floor = math_floor(self.pos_x)
            local pos_y_floor = math_floor(self.pos_y)

            if tile_data == 24 then
               table.insert(g_enemies, Enemy.new_random(pos_x_floor + .5, pos_y_floor + .5))
            else -- tile_data == 40
               table.insert(g_enemies, Enemy.new_boss(pos_x_floor + .5, pos_y_floor + .5))
            end
            return false
         end
      end

      if self.wall_dist > 0 then -- not colliding with wall
         local color
         if self.type_idx == 0 then
            color = 16 - 4 * (self.dist_rem / self.dist_max)
         elseif self.type_idx == 1 or self.type_idx == 4 then
            color = 2
         elseif self.type_idx == 2 or self.type_idx == 5 then
            color = 6
         elseif self.type_idx == 3 then
            color = 5 - 3 * (self.dist_rem / self.dist_max)
         else -- self.type_idx == 6
            color = 16 * (self.dist_rem / self.dist_max)
         end

         if g_state == 6 then
            g_pix_title_screen(self.pos_x, self.pos_y, color)
         elseif self.type_idx ~= 6 then
            g_pix_bounded(self.pos_x, self.pos_y, color)
         else -- self.type_idx == 6
            pix(self.pos_x * 8, self.pos_y * 8, color)
         end
         return false
      end

      table.insert(g_hitmarks, Hitmark.new(self.pos_x, self.pos_y, 1))

      if self.bounces_rem <= 0 then
         return true
      end

      -- Bounce
      self.bounces_rem = self.bounces_rem - 1
      self.dist = -self.wall_dist
      if self.wall_side == 0 then
         self.dir_x = -self.dir_x
      else -- self.wall_side == 1
         self.dir_y = -self.dir_y
      end

      self.wall_dist, self.wall_side = g_ray_isect(self.pos_x, self.pos_y, self.dir_x, self.dir_y)
   end
end

----------------------------------------
-- Stats -------------------------------
----------------------------------------

Stats = {
   damage_taken = 0,
   damage_dealt = 0,
   bullets_fired = 0,
   bullets_hit = 0,
   bullets_taken = 0,
   pings = 0,
   items_collected = 0,
   enemies_destroyed = 0,
   distance_travelled = 0,
   time_total = 0,
}
Stats.__index = Stats

function Stats.new()
   local self = setmetatable({}, Stats)
   return self
end

function Stats:add(stat)
   self.damage_taken = self.damage_taken + stat.damage_taken
   self.damage_dealt = self.damage_dealt + stat.damage_dealt
   self.bullets_fired = self.bullets_fired + stat.bullets_fired
   self.bullets_hit = self.bullets_hit + stat.bullets_hit
   self.bullets_taken = self.bullets_taken + stat.bullets_taken
   self.pings = self.pings + stat.pings
   self.items_collected = self.items_collected + stat.items_collected
   self.enemies_destroyed = self.enemies_destroyed + stat.enemies_destroyed
   self.distance_travelled = self.distance_travelled + stat.distance_travelled
   self.time_total = self.time_total + stat.time_total
end

----------------------------------------
-- Player ------------------------------
----------------------------------------

Player = {
   pos_x = 3,
   pos_y = 3,
   pos_x_scr = 0,
   pos_y_scr = 0,
   angle = 0,
   ping_cooldown = 0,
   ping_passive_cooldown = 0,
   ping_spread = 1,
   ping_range = 8,
   weapon = nil,
   move_abs = Entity.move_abs,
   move_rel = Entity.move_rel,
   draw_sprite = Entity.draw_sprite,
   health = 5,
   speed = .0035,
   ping_cooldown_max = 400,
   ping_bounces = 0,
   stats_flr = nil,
   stats_total = nil,
   floor = 1,
   iframe_cooldown = 0,
}
Player.__index = Player

function Player.new(room)
   local self = setmetatable({}, Player)
   self.weapon = Weapon.new(0, 1, 1, .3, .15, 600, 7, -1, 1, .005)
   self.stats_flr = Stats.new()
   self.stats_total = Stats.new()
   self:place_in_room(room)
   mset(self.pos_x, self.pos_y, 0)
   return self
end

function Player:place_in_room(room)
   local math_random = math.random
   self.pos_x = math_random(room[1] + 1, room[3] - 1) + .5
   self.pos_y = math_random(room[2] + 1, room[4] - 1) + .5
end

function Player:ping()
   local projs = g_projs
   self.ping_cooldown = self.ping_cooldown_max
   self.stats_flr.pings = self.stats_flr.pings + 1
   local table_insert = table.insert
   local ping_spread_half = self.ping_spread * .5
   for theta = -ping_spread_half, ping_spread_half, .003 do
      table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, self.ping_range, self.ping_bounces, 0))
   end
end

function Player:process(delta)
   local math_max = math.max
   self.ping_cooldown = math_max(self.ping_cooldown - delta, 0)
   self.ping_passive_cooldown = self.ping_passive_cooldown - delta
   self.iframe_cooldown = math_max(self.iframe_cooldown - delta, 0)
   self.stats_flr.time_total = self.stats_flr.time_total + delta

   if self.ping_passive_cooldown < 0 then
      self.ping_passive_cooldown = self.ping_cooldown_max
      local table_insert = table.insert
      local projs = g_projs
      for theta = 0, 6.28, .1 do
         table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 2, 0, 0))
      end
   end

   local mouse_x, mouse_y, mouse_left, mouse_mid, mouse_right = table.unpack(g_mouse)

   local pos_x_rel = mouse_x - 8 * (self.pos_x % 25)
   local pos_y_rel = mouse_y - 8 * (self.pos_y % 17)
   self.angle = math.atan2(pos_y_rel, pos_x_rel)

   local mov_front = 0
   if btn(0) then
      mov_front = -1
   elseif btn(1) then
      mov_front = 1
   end

   local mov_side = 0
   if btn(2) then
      mov_side = -1
   elseif btn(3) then
      mov_side = 1
   end

   if mov_front ~= 0 or mov_side ~= 0 then
      local mov_scl = delta * self.speed / math.sqrt(mov_front * mov_front + mov_side * mov_side)
      local dist = self:move_abs(mov_side * mov_scl, mov_front * mov_scl)
      self.stats_flr.distance_travelled = self.stats_flr.distance_travelled + dist
   end

   self.pos_x_scr = self.pos_x // 25
   self.pos_y_scr = self.pos_y // 17

   if mouse_right and self.ping_cooldown == 0 then
      self:ping()
   end

   if self.weapon then
      self.weapon:process(delta)
      if mouse_left then
         self.weapon:fire(self.pos_x, self.pos_y, self.angle)
      end
   end

   local tile = mget(self.pos_x, self.pos_y) & 0x38
   if tile == 16 then
      g_item_pickup(self.pos_x, self.pos_y)
      self.stats_flr.items_collected = self.stats_flr.items_collected + 1
   elseif tile == 32 then
      self.stats_total:add(self.stats_flr)
      g_floor_clear_text_tab[7] = self.floor
      if self.floor == 4 then
         g_state = 7
      else
         g_state = 3
      end
   end
end

function Player:damage(dmg)
   if self.iframe_cooldown == 0 then
      sfx(16)
      self.health = self.health - dmg
      self.stats_flr.damage_taken = self.stats_flr.damage_taken + dmg
      self.stats_flr.bullets_taken = self.stats_flr.bullets_taken + 1
      if self.health < 0 then
         self.health = 0
         self.stats_total:add(self.stats_flr)
         g_state = 4
      end
      self.iframe_cooldown = 600
      g_screen_shake_timer = 0
   end
end

function Player:heal(amount)
   self.health = math.min(self.health + amount, 7)
end

function Player:draw()
   if (self.iframe_cooldown // 100) % 2 == 0 then
      self:draw_sprite(5)
   end
end

----------------------------------------
-- main --------------------------------
----------------------------------------

--- g_state:
-- 1: game
-- 2: item pickup
-- 3: floor clear
-- 4: game over
-- 5: controls
-- 6: title screen
-- 7: victory

--- Begin new run
function init()
   local start_room = g_map_gen()
   g_player = Player.new(start_room)
   g_projs = {}
   g_hitmarks = {}
   g_enemies = {}
   g_screen_shake_timer = 1e9
end

function BOOT()
   g_menu_ping_cooldown = 0
   g_menu_ping_counter = 0
   g_projs = {}
   g_hitmarks = {}
   g_state = 6
   g_items = {}
   g_t = time()
   g_mouse = table.pack(mouse())
   g_mouse_prev = {}
   g_debug = false
   g_prev_time = time()
   music(0, 0, 0, true)
   g_music_enabled = true
end

function process_game(delta)
   cls()

   local player = g_player
   local projs = g_projs
   local hitmarks = g_hitmarks
   local enemies = g_enemies

   if g_screen_shake_timer < 250 then
      local screen_shake_timer = g_screen_shake_timer
      local math_random = math.random
      g_screen_shake_timer = screen_shake_timer + delta
      poke(0x3FF9, (math_random() - .5) * (600 - screen_shake_timer) * .03)
      poke(0x3FFA, (math_random() - .5) * (600 - screen_shake_timer) * .03)
      poke(0x3FF8, math_random(4))
   end

   if g_debug then
      map(player.pos_x_scr * 25, player.pos_y_scr * 17)
   end
   g_ui_render()

   -- Processes
   player:process(delta)

   -- Projectile process
   for k, v in pairs(projs) do
      if v:process(delta) then
         projs[k] = nil
      end
   end

   -- Hitmark process
   for k, v in pairs(hitmarks) do
      if v:process(delta) then
         hitmarks[k] = nil
      end
   end

   -- Enemies process
   for k, v in pairs(enemies) do
      v:process(delta)
   end

   player:draw()
end

function process_item_pickup(delta)
   cls()

   map(210, 0, 18, 15, 28, 8)
   print("SKIP", 88, 106, 2, true)
   g_print_rainbow(gc_upgrade_text_tab, 73, 10, 0, 16)

   local items = g_items
   items[1]:render(52, 32)
   items[2]:render(116, 32)

   g_ui_render()

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3] then
      if mouse_y >= 24 and mouse_y <= 96 then
         if mouse_x >= 44 and mouse_x <= 92 then
            items[1]:apply()
            g_state = 1
            sfx(20)
         elseif mouse_x >= 116 and mouse_x < 164 then
            items[2]:apply()
            g_state = 1
            sfx(20)
         end
      elseif mouse_y >= 104 and mouse_y <= 112
         and mouse_x >= 76 and mouse_x <= 124 then
         g_state = 1
         sfx(20)
      end
   end
end
gc_upgrade_text_tab = {"U", "P", "G", "R", "A", "D", "E"}

function process_floor_clear(delta)
   cls()

   map(210, 68, 16, 15, 36, 8)
   print("CONTINUE", 77, 106, 6, true)
   g_print_rainbow(g_floor_clear_text_tab, 55, 10, 0, 16)

   g_ui_render()

   local player = g_player

   g_print_stats(player.stats_flr, 56, 24)

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3]
      and mouse_y >= 104 and mouse_y <= 112
      and mouse_x >= 68 and mouse_x <= 132 then
      sfx(20)
      player.floor = player.floor + 1
      if player.floor % 2 == 1 then
         for _, v in pairs(g_enemies) do
            v:damage(1e9)
         end
         local start_room = g_map_gen()
         g_player:place_in_room(start_room)
      else -- boss fight
         local player = g_player
         player.pos_x = 201
         player.pos_y = 127
         g_comp_pos_x = -1
         g_comp_pos_y = -1
         mset(211, 127, 0) -- Hide exit

         -- Place boss
         local math_random = math.random
         local pos_x_boss
         local pos_y_boss
         repeat
            pos_x_boss = math_random(200, 222)
            pos_y_boss = math_random(120, 133)
         until (mget(pos_x_boss, pos_y_boss) == 0
            and (player.pos_x - pos_x_boss) ^ 2 + (player.pos_y - pos_y_boss) ^ 2 > 36)
         mset(pos_x_boss, pos_y_boss, 40)
      end
      g_enemies = {}
      g_projs = {}
      g_state = 1
      g_hitmarks = {}
   end
end
g_floor_clear_text_tab = {
   "F", "L", "O", "O", "R",
   " ", 0,
   " ", "C", "L", "E", "A", "R"
}

function process_game_end(delta)
   cls()

   map(210, 68, 16, 15, 36, 8)
   print("NEW RUN", 80, 106, 6, true)
   g_print_rainbow(gc_game_over_text_tab, 68, 10, 2, 1)

   g_ui_render()

   local player = g_player

   g_print_stats(player.stats_total, 56, 20, player.floor - 1)

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3]
      and mouse_y >= 104 and mouse_y <= 112
      and mouse_x >= 68 and mouse_x <= 132 then
      g_state = 6
      sfx(20)
   end
end
gc_game_over_text_tab = {
   "G", "A", "M", "E",
   " ", "O", "V", "E", "R"
}

function process_controls(delta)
   cls()

   map(210, 85, 30, 15, 0, 8)
   print("CONTROLS", 41, 10, 15, true)
   print("HOW TO PLAY", 148, 10, 15, true)
   g_print_rainbow(gc_enter_ship_text_tab, 144, 114, 0, 16)

   local text = gc_controls_how_to_play_text
   for i = 1, #text, 4 do
      print(text[i], text[i + 1], text[i + 2], text[i + 3], false, 1, true)
   end

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3]
      and mouse_y >= 112 and mouse_y <= 120
      and mouse_x >= 136 and mouse_x <= 224 then
      sfx(20)
      init()
      g_state = 1
   end
end
gc_enter_ship_text_tab = {
   "E", "N", "T", "E", "R",
   " ", "S", "H", "I", "P"
}
gc_controls_how_to_play_text = {
   "MOVE", 57, 66, 2,
   "AIM", 27, 106, 3,
   "FIRE", 57, 106, 6,
   "SCAN", 89, 106, 8,
   "You", 130, 17, 5,
   "are a robot tasked", 153, 17, 12,
   "with exploring a mysterious\nspaceship. Within, you will be\nreliant solely on your", 130, 23, 12,
   "scanner,", 130, 41, 8,
   "weapon,", 163, 41, 6,
   "and your", 192, 41, 12,
   "own quick thinking.", 130, 47, 12,
   "Upgrades", 130, 53, 4,
   "will prove", 171, 53, 12,
   "crucial to your survival but\nbeware of the", 130, 59, 12,
   "alien foes", 180, 65, 2,
   "that carry and guard them.\nYour", 130, 71, 12,
   "compass", 148, 77, 13,
   "will guide", 188, 77, 12,
   "you towards", 130, 83, 12,
   "teleporters,", 174, 83, 11,
   "allowing you to venture\ndeeper into the ship.", 130, 89, 12,
   "Good Luck. Try not to die ;)", 130, 101, 12,
}

function process_victory(delta)
   cls()

   map(222, 34, 18, 15, 48, 8)

   local print_rainbow = g_print_rainbow
   print_rainbow(gc_victory_text_tab, 84, 10, 0, 16)
   print_rainbow(gc_credits_text_tab, 94, 74, 0, 16)
   print("CONTINUE", 97, 106, 6, true)

   print("Congratulations! You voyaged deep\ninto the ship and gathered more\nthan enough information to\nconsider this mission a success.\nUnfortunately, getting back out\nwas not part of the mission\ndescription, so there's only one\nthing left for you to do:\nKEEP GOING DEEPER!", 59, 18, 12, false, 1, true)
   print("Development: Wojciech Graj", 59, 84, 12, true, 1, true)
   print("Testing:     Jan Czajka", 59, 90, 12, true, 1, true)
   print("Testing:     Yahor Dauksha", 59, 96, 12, true, 1, true)

   local projs = g_projs

   if math.random() < .03 then
      local math_random = math.random
      local table_insert = table.insert
      local pos_x = math_random() * 30
      local pos_y = math_random() * 17
      sfx(16)
      for theta = 0, 6.28, .2 do
         table_insert(projs, Proj.new(pos_x, pos_y, theta, .003, 3, 0, 6))
      end
   end

   -- Projectile process
   for k, v in pairs(projs) do
      if v:process(delta) then
         projs[k] = nil
      end
   end

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3]
      and mouse_y >= 104 and mouse_y <= 112
      and mouse_x >= 88 and mouse_x <= 152 then
      sfx(20)
      g_state = 3
   end
end
gc_victory_text_tab = {
   "Y", "O", "U",
   " ", "W", "O", "N",
   "!", "!", "!"
}
gc_credits_text_tab = {
   "C", "R", "E", "D", "I", "T", "S"
}

function process_title_screen(delta)
   cls()

   local projs = g_projs
   local hitmarks = g_hitmarks
   local table_insert = table.insert

   -- Ping
   local cooldown = g_menu_ping_cooldown
   g_menu_ping_cooldown = cooldown - delta
   if cooldown < 0 then
      g_menu_ping_cooldown = 300
      local ping_counter = g_menu_ping_counter
      local ping_locs = gc_menu_ping_locs
      local ping_locs_idx = (ping_counter * 2) % #ping_locs
      local pos_x = ping_locs[ping_locs_idx + 1]
      local pos_y = ping_locs[ping_locs_idx + 2]
      for theta = 0, 6.28, .007 do
         table_insert(projs, Proj.new(pos_x, pos_y, theta, .01, 12, 0, 0))
      end
      g_menu_ping_counter = ping_counter + 1
   end

   -- Projectile process
   for k, v in pairs(projs) do
      if v:process(delta) then
         projs[k] = nil
      end
   end

   -- Hitmark process
   for k, v in pairs(hitmarks) do
      if v:process(delta * .1) then
         hitmarks[k] = nil
      end
   end

   if (g_t // 500) % 2 == 0 then
      print("PRESS ANY MOUSE BUTTON TO BEGIN", 35, 116, 2)
   end
   print("(c) Wojciech Graj 2023", 62, 126, 4)

   local mouse_x, mouse_y, mouse_left, mouse_mid, mouse_right = table.unpack(g_mouse)
   if mouse_left or mouse_mid or mouse_right then
      g_state = 5
      sfx(20)
   end
end
gc_menu_ping_locs = {
   208.5, 102.5,
   216.5, 102.5,
   219.5, 102.5,
   222.5, 102.5,
   226.5, 102.5,
   230.5, 102.5,
   238, 102.5,

   222.5, 106.5,
   226.5, 106,
   230.5, 105.5,

   211.5, 109.5,
   213.5, 109.5,
   215.5, 109.5,
   216.5, 109.5,
   218, 109.5,
   221, 109.5,
   222.5, 109.5,
   225, 109.5,
   226.5, 109.5,
   229, 109.5,
   230.5, 109.5,
   233.5, 109.5,
   235.5, 109.5,

   211.5, 112.5,
   223.5, 112.5,
   228.5, 111.5,
   228.5, 113.5,
   231.5, 112.5,

   208.5, 118.5,
   211.5, 118.5,
   215.5, 118.5,
   219.5, 118.5,
   223.5, 118.5,
   227.5, 118.5,
   231.5, 118.5,
   235.5, 118.5,
   238, 118.5,
}

function TIC()
   local t = time()
   g_t = t
   local delta = t - g_prev_time
   g_prev_time = t

   g_mouse_prev = g_mouse
   local v_mouse = table.pack(mouse())
   g_mouse = v_mouse

   -- Hide mouse
   poke(0x3FFB, 0)

   -- Reset screen shake
   poke(0x3FF9, 0)
   poke(0x3FFA, 0)
   poke(0x3FF8, 0)

   -- Toggle music
   if btnp(4) then
      local music_enabled = g_music_enabled
      if music_enabled then
         music()
      else
         music(0, 0, 0, true)
      end
      g_music_enabled = not g_music_enabled
   end

   -- process
   local state = g_state
   if state == 1 then
      process_game(delta)
   elseif state == 2 then
      process_item_pickup(delta)
   elseif state == 3 then
      process_floor_clear(delta)
   elseif state == 4 then
      process_game_end(delta)
   elseif state == 5 then
      process_controls(delta)
   elseif state == 6 then
      process_title_screen(delta)
   else -- state == 7
      process_victory(delta)
   end

   -- Custom mouse sprite
   spr(257, v_mouse[1] - 4, v_mouse[2] - 4, 0)

   if g_debug then
      print(string.format("FPS %d", math.floor(1000 / delta)), 0, 0, 5)
   end
end

-- <TILES>
-- 001:00000000ffffffffffccccffcccccddecccdddeefcdddeeffdddeeefffeeefff
-- 002:0ff00ff00cce0ccefccefccefccefccefddefdde0eef0eef0ff00ff000000000
-- 003:0eeeef00fcccdef0fcccdef000fff0000eeeef00fcccdef0fcccdef000fff000
-- 004:0ffffff00ccccdfffccccddffcccdddffddddeef0feeeeff0ffffff000000000
-- 005:00fff000fcccddf0fcccddeffcccddeffccdddeffddddeefffddeeff0ffffff0
-- 006:0ffffff0ffdcccc0fddccccffdddcccffeeddddfffeeeef00ffffff000000000
-- 007:0ffffff0ffcccdfffcccddeffccddeeffccddeeffccddeeffccddef000fff000
-- 008:fffccff0fcccdff0cccddef0ccddeef0dddeef00ffeeff00ffff000000000000
-- 009:0ffccfff0ffdcccf0feddccc0feeddcc00feeddd00ffeeff0000ffff00000000
-- 010:00000000ffff0000ccccff00cccccf00ccddccf0eedddcf0feeedff0fffeeff0
-- 011:000000000000ffff00ffcccc00fccccc0fccddcc0fcdddee0ffdeeef0ffeefff
-- 012:ffffffffccccccccccccccccccccccccccccccccddddddddeeeeeeeeffffffff
-- 013:fffccff0fcccdff0cccdddf0ccddddf0dddeeef0fdeeeef0feeeeff0fffeeff0
-- 014:0ffccfff0ffdcccf0fdddccc0fddddcc0feeeddd0feeeedf0ffeeeef0ffeefff
-- 015:ffcccffffcccddeffccddeefccddeeeedddeeeeeffeeeeffffffffff00000000
-- 016:00000000000000000000088800888888888888999999999999999aaaaaaaaaaa
-- 017:000000000888888888888999889999999999999a9999aaaaaaaaaaaaaaaaaaab
-- 018:000000009999911099911f11aaffffffaaffffffafff6fffbfff6fff1ddd6ddd
-- 019:0000000000000011000001ff11111ffff2ffffff2ffffffc22ffffcdd22ffcdd
-- 020:00000999000baa0000ba00000ba000000ba00000ba000000ba000001ba0ccc11
-- 021:00000000000000000000000000000001000011110111100c110000cd000000cd
-- 022:000000c10000111d01111ddd11ddddddcdddddddddddddeeddddeeeedddeeeee
-- 023:c0000000dcc00000ddcc0000ddddc000deeed000eeeedd00eefedd00effedd00
-- 024:0000000000000ccc000000dd000ccccc0000ddcc0000ccdd0ccccccc00ddcccc
-- 025:00000000ccc00000ccccc500ddddd655ccc5c766dd776577c7777665655c7766
-- 026:000000000000000000000000c0000000655c000076666550c77766656557fff6
-- 027:000000000000000000000000000000000000000000000000c00000aa65500ba0
-- 030:0000000000000000000022dd00002ddd00002dd7000022dc0000000c000000cc
-- 031:0000000000000000e0000000de000000700000007e00000077ecccccc7ccdeee
-- 032:aaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccc
-- 033:aaaaaabbaaabbbbbbbbbbbbbbbbbbbbcbbbbbbccbbcccccccccccccccccccccc
-- 034:11ee6ddd1fd66ccd1166dccde66deeecdddddddeddddddddddddddddcccccddd
-- 035:dd22cdffddd2dfffc222ffffccddffffeeddffddddddddccddddccffddddfff1
-- 036:ba0c1110ba001001ba0010000ba011000ba0010000ba0110000ba01000009010
-- 037:00000ccd0000ccdd1100ccdd011ccddd0011cddd00c11ddd00cc1ddd00ccd11e
-- 038:ddeeeeeedeeeeeeedeeeeeeeeeeeeeffeeeeeeffeeeeefffeeeeefffeeeeffff
-- 039:effedd00effedd00fffeddf0fffeddf0ffeed0f0ffedd0f0feedd4ffeeddd40f
-- 040:ccccddd60ddccc77000dd6650000077700000000000000000000000000000000
-- 041:66665577776666655c7776666565c77f776665ff00776fff0000ffff000000ff
-- 042:766fffff77fffeef6fffeeeefffeeeefffeeeefffeeddf66e3eddf77e3ddd667
-- 043:ff65cbaaff766cbaff777ba0f666cbaa7776baaa667bbaa0766caa00770bbbaa
-- 044:0000000024000000334ceeed034efffd340effdd000000dc4400eedc344effdc
-- 045:00000000cc000eeddcedddffceeeffffcffffff000000000eeeeddddffeeeeee
-- 046:00000cccdddccccefffcceeefffcceee00cceeee00cceeeeddcceeeeeccceeed
-- 047:ce7eeeeeee7eeeeeee7eddddee7dffffed7777ffdfff17ffdfff111fdffff11f
-- 048:ccccccccbbbcccccbbbbbbbbbbbbbbbbbbbbbbbbaaaaaaaaaaaaaaaaaaaaaaaa
-- 049:ccccccccccccccccbbccccccbbbbbbccbbbbbbbcbbbbbbbbaaabbbbbaaaaaabb
-- 050:dddddeeecccccddddddddddddddddddee1ddaeec11ddaccd1fdeaccd11eeaadd
-- 051:edddff11ddddff1133ddfff1e3ddddffc33dcdddcc3dfcccdd3dffffdd3fffff
-- 052:0000001100000001000000010000000100000000000000000000000000000000
-- 053:0ccddd110ccddde10ccdddee0ccdddee1ccdddee1ccdddee1ccdddee01cdddde
-- 054:eeeeffff1eeeffff11effffeee1ffffeeef1feeeeff11eedefffe1ddefffed11
-- 055:eeddf40fedd0f4ffedd0f4ffed00f40fd770440fd074400f0074f00f0077000f
-- 057:000000000000000000000000000000000000000000000000000000000000000e
-- 058:2fddd76622ddd07700ed330000e3c000003dc000003dd200ee3edd20e3eed220
-- 059:6ccbbaa07abba00000baaa0000ba00a0000a0000000a00000000000000000000
-- 060:23ceffdc240effdc000000dc000000dd034efeed34cefffe240efffe00000fff
-- 061:ffffffffffffffff00000000c0000000deeeeee0ddffffeeedffffffedffffff
-- 062:fccceeedfccceeed0cceeeed00ceeee900ceee9deeecee9efffce99effffc9ee
-- 063:ffff111fffffffffffffcfff9999ceefffffceefffffceefefffffffeeffffff
-- 064:aaaaaaaa99999aaa999999998888889900888888000008880000000000000000
-- 065:aaaaaaabaaaaaaaa9999aaaa9999999a88999999888889990888888800000000
-- 066:1ddddaddbfffffffafffffffaaffffffaaefffff999eeffe99999ee000000000
-- 067:dd3ddffff33ccdfff3ffccdfffffffcdeeeeeffc00000eff000000ef00000000
-- 069:011cdddd001cdddd0000ccdd000000cc00000000000000000000000000000000
-- 070:eeeeedd0deeddd00ddddd000ccc000000000000f0000000f000000ff000000f0
-- 071:0f47f00f04f7f00ff4070f0ff4070fff007700ff0074000f077f400f77004ff0
-- 073:000003ee00003eed00003ed0000e33f0000ee3df00eed30d00ee03000eed0300
-- 074:d30ed2d000ed2ddc02ed00dd02ed000d002d000df0d2fdd0dddd2d000ed02000
-- 075:0000000000000000c0000000dc000000dd000000ddc000000dc000000ddd0000
-- 077:ed00000000000000000000000000000000000000000000000000000000000000
-- 078:000099ee00000fee000000ff00000ddf00000d4c00000e44000000dd00000d4c
-- 079:eeefffffeeeeefffeeeeeeeeffffffeeccceffff444e0000eeee0000ccce0000
-- 080:000000000000000000000000000000000000000c0000000c0000000c00000ccd
-- 081:0000000000c000000cdc0000cdddc000dddddc00ddeeddc0deeeedd0deeedd00
-- 082:000000000000000000000000000000cc00000cdd0000cddd000cddd0000dddd0
-- 083:000000000000000000000000cc000000c0000000000000000000000000000000
-- 088:0000000005000000055000005555000055555000000555000000005000000000
-- 089:000fffff00ffffff00ffeddd00ffddde00ffdded00ffdded00ffeeed00ffddde
-- 090:000fffff00ffffff00ffabbb00ffbbba00ffbbad00ffbbad00ffaaad00ffddde
-- 091:fffff000ffffff00dddeff00edddff00deddff00deddff00deeeff00edddff00
-- 092:00ffffff0fffffff0ffedddd0ffddddd0ffdddde0ffdddee0ffddeee0ffdddde
-- 093:fffff000ffffff00dddeff00ddddff00ddddff00edddff00eeddff00ddddff00
-- 094:000fffff00fffff400ffef4400ffd33300ffdded00ff3ded00f43eed0f443dde
-- 095:fffff0004fffff0044feff00333dff00deddff00ded3ff00dee34f00edd344f0
-- 096:0000cdde0000cdee000cdeee00cddeef00cdefff0cdeff000deff0000def0000
-- 097:eeffd000ed000000eed00000eedc0000feddc000ffeddc000ffeddc000ffedcc
-- 098:00cddee000dddee000ddeeed00deeedd00deeeed0cdeeeeecddeffffddeef000
-- 099:000000c000000cd00000cde0ccccde00ddddee00eeeee000fff0000000000000
-- 104:0000000000200000002200000222200002222200000022200000000200000000
-- 105:fffff000ffffff00bbbaff00abbbff00dabbff00dabbff00daaaff00edddff00
-- 106:00ffdddd00ffdddd00ffdddd00ffccdd00fffecc000fffee0000ffff00000fff
-- 107:ddddff00ddddff00ddddff00ddccff00ccefff00eefff000ffff0000fff00000
-- 108:0ffdddde0ffddddd0ffdcccc0ffceeee0ffeeeee0fffffff00ffffff00000000
-- 109:ddddff00ddddff00cccdff00eeecff00eeeeff00ffffff00fffff00000000000
-- 110:0f443ddd00f43ddd00ff3ddd00ffccdd00fff333000fff440000fff400000fff
-- 111:ddd344f0ddd34f00ddd3ff00ddccff00333fff0044fff0004fff0000fff00000
-- 112:0ef000000ee000000000000000000000000000000000000c000000cd00000cdd
-- 113:000fccdd000cddde00cdddee0cdddeeecdddeeffdddeefffddeefff0deefff00
-- 114:deef0000eeffc000effddc00ffedddc0feeedddcfffeeddd0fffeedd00fffeed
-- 115:0000000000000000000000000000000000000000c0000000dc000000ddc00000
-- 120:0ffffff0ffeeeefffeeddeeffedccdeffedccdeffeeddeefffeeeeff0ffffff0
-- 122:0000ffff000fffff000ffedd000ffddd000ffddd000ffddd000ffdde000ffddd
-- 123:fffffff0ffffffffdddddeffddddddffdeddddffeeddddffeeeeddffeeddddff
-- 124:00ffffff0fffffff0ffedddd0ffddddd0ffdddde0ffdddde0ffddeee0ffdddee
-- 125:fffff000ffffff0fdddeff0fddddff0fddddff0fddddff0feeddff0fedddff0f
-- 126:fffffffffffffffffeddddddfdddddddfddddeddfddddeedfddeeeeefddddeed
-- 127:fff00000ffff0000deff0000ddff0000ddff0000ddff0000ddff0000ddff0000
-- 128:0000cddd000cddde00cdddee00cd0eef00d000ef00d000ff00eefff0000fff00
-- 129:eefff000efff0000fff00000ff000000f0000000000000000000000000000000
-- 130:000fffee0000fffe00000fff000000ff0000000f000000000000000000000000
-- 131:dddc0000edddc000eedddc00feedddc0ffeeddc0fffeede00fffeef000fffff0
-- 138:000ffddd000ffddd000ffdcc000ffcee000ffeee000fffff0000ffff00000000
-- 139:deddddffddddddffcccccdffeeeeecffeeeeeefffffffffffffffff000000000
-- 140:0ffdddde0ffddddd0ffdcccc0ffceeee0ffeeeee0fffffff00ffffff00000000
-- 141:ddddff0fddddff0fcccdff0feeecff0feeeeff0fffffff0ffffff00000000000
-- 142:fddddeddfdddddddfdccccccfceeeeeefeeeeeeeffffffffffffffff00000000
-- 143:ddff0000ddff0000cdff0000ecff0000eeff0000ffff0000fff0000000000000
-- 144:00ccde000e1111e0f244322ff244322ff011110ff244322ff244322ff011110f
-- 145:00ccde000effffe0feccdeeffeccdeeff011110ff244322ff244322ff011110f
-- 146:00ccde000effffe0feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff011110f
-- 147:00ccde000e7777e0f644566ff644566ff077770ff644566ff644566ff077770f
-- 148:00ccde000effffe0feccdeeffeccdeeff077770ff644566ff644566ff077770f
-- 149:00ccde000effffe0feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff077770f
-- 150:00ccde000e8888e0f9bba99ff9bba99ff088880ff9bba99ff9bba99ff088880f
-- 151:00ccde000effffe0feccdeeffeccdeeff088880ff9bba99ff9bba99ff088880f
-- 152:00ccde000effffe0feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff088880f
-- 153:00ccde000effffe0feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff0ffff0f
-- 154:0000000000000000000000000000000000000000000044440004400400040000
-- 155:0000000000000000000000000000000000000000000000004000000040000000
-- 156:0000000000000000000000000000000000ffffff0ffeeeef022eddee0fe22cde
-- 157:0000000000000000000000000000000000000000f0000000f0000000f0000000
-- 158:000000000000000000000000000000000000000b0000000b0000000b0000000b
-- 159:000000000000000000000000bbbb0000b00bb0000000b0000000b000b00bb000
-- 160:f244322ff244322ff011110ff244322ff244322ff011110ff244322ff244322f
-- 161:feccdeeffeccdeeff011110ff244322ff244322ff011110ff244322ff244322f
-- 162:feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff011110ff244322ff244322f
-- 163:f644566ff644566ff077770ff644566ff644566ff077770ff644566ff644566f
-- 164:feccdeeffeccdeeff077770ff644566ff644566ff077770ff644566ff644566f
-- 165:feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff077770ff644566ff644566f
-- 166:f9bba99ff9bba99ff088880ff9bba99ff9bba99ff088880ff9bba99ff9bba99f
-- 167:feccdeeffeccdeeff088880ff9bba99ff9bba99ff088880ff9bba99ff9bba99f
-- 168:feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff088880ff9bba99ff9bba99f
-- 169:feccdeeffeccdeeff0ffff0ffeccdeeffeccdeeff0ffff0ffeccdeeffeccdeef
-- 170:0004000000044004000044440000000000000000000000000000000000000000
-- 171:4000000040000000000000000000000000000000000000000000000000000000
-- 172:0fedc2de0feeddee0ffeeeef00ffffff00000000000000000000000000000000
-- 173:f0000000f0000000f00000000000000000000000000000000000000000000000
-- 175:bbbb000000000000000000000000000000000000000000000000000000000000
-- 176:f011110ff244322ff244322ff011110ff244322ff244322f0e1111e000ccde00
-- 177:f0ffff0ffdccdeeffdccdeeff011110ff244322ff244322f0e1111e000ccde00
-- 178:f0ffff0ffdccdeeffdccdeeff0ffff0ffeccdeeffeccdeef0e1111e000ccde00
-- 179:f077770ff644566ff644566ff077770ff644566ff644566f0e7777e000ccde00
-- 180:f0ffff0ffdccdeeffdccdeeff077770ff644566ff644566f0e7777e000ccde00
-- 181:f0ffff0ffdccdeeffdccdeeff0ffff0ffeccdeeffeccdeef0e7777e000ccde00
-- 182:f088880ff9bba99ff9bba99ff088880ff9bba99ff9bba99f0e8888e000ccde00
-- 183:f0ffff0ffdccdeeffdccdeeff088880ff9bba99ff9bba99f0e8888e000ccde00
-- 184:f0ffff0ffdccdeeffdccdeeff0ffff0ffeccdeeffeccdeef0e8888e000ccde00
-- </TILES>

-- <SPRITES>
-- 001:0000000000cccc000cc00cc00c0000c00c0000c00cc00cc000cccc0000000000
-- </SPRITES>

-- <MAP>
-- 000:808080808080808080808080808080808080808080808080800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b06020204060c0c0c0c0c0c04060202040a0000000000000000000000000
-- 001:800000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000070000000000000000000000000
-- 002:8000000000000101010101000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000b060202040a00000b060202040a00030000000000000000000000000
-- 003:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 004:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 005:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 006:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 007:8000000000000101010101000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000e0c0c0c0c0d00000e0c0c0c0c0d00030000000000000000000000000
-- 008:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 009:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 010:800000000000010101010100000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300090602020408000009060202040800030000000000000000000000000
-- 011:800000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000030000000000000000000000000
-- 012:80000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000060c0c0c0c040000000000030000000000000000000000000
-- 013:800000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000050000000000000000000000000
-- 014:800000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020202020202020202020202020204080000000000000000000000000
-- 015:800000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:808080808080808080808080808080808080808080808080800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111213141516171c1d1e1f18191a1b10515253500000000000000000000
-- 018:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000212223242526272c2d2e2f28292a2b20616263600000000000000000000
-- 019:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313233343536373c3d3e3f38393a3b30717273700000000000000000000
-- 020:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000414243444546474c4d4e4f48494a4b40818283800000000000000000000
-- 034:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b0608740a000000000000000b060204060c0c0c0c0c0c0c0c040602040a0
-- 035:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000700000000000000000000000000000000070
-- 036:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000300000000000000000000000000000000030
-- 037:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000005000000000000000300000000000000000000000000000000030
-- 038:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000300000000000000000000000000000000030
-- 039:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000300000000000000000000000000000000030
-- 040:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000300000000000000000000000000000000030
-- 041:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000500000000000000000000000000000000050
-- 042:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000e06020204060c0c0c0c0c0c04060202040d0
-- 043:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000005000000000000000700000000000000000000000000000000070
-- 044:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000300000000000000000000000000000000030
-- 045:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000300000000000000000000000000000000030
-- 046:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000300000000060c0c0c0c0c0c0400000000030
-- 047:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000500000000000000000000000000000000050
-- 048:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000906020202020202020202020202020204080
-- 049:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000005000000000000000000000000000000000000000000000000000
-- 050:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020408000000000000000000000000000000000000000000000000000
-- 051:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000091999999999999900000000000000000000000000000000000000000000
-- 052:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0a0a1a2a9a9a9a00000000000000000000000000000000000000000000
-- 053:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b0b0b0b0b0b1b2b00000000000000000000000000000000000000000000
-- 054:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000394959999999999900000000000000000000000000000000000000000000
-- 055:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a3a3a4a5a9a9a9a00000000000000000000000000000000000000000000
-- 056:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b3b3b3b3b3b4b5b00000000000000000000000000000000000000000000
-- 057:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000697989999999999900000000000000000000000000000000000000000000
-- 058:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006a6a6a7a8a9a9a9a00000000000000000000000000000000000000000000
-- 059:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b6b6b6b6b6b7b8b00000000000000000000000000000000000000000000
-- 068:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b02060c0c0c0c0c0c0c0c0c0c04020a00000000000000000000000000000
-- 069:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000700000000000000000000000000000
-- 070:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 071:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 072:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 073:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 074:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 075:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 076:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 077:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 078:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 079:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000300000000000000000000000000000
-- 080:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000060c0c0c0c0c0c040000000300000000000000000000000000000
-- 081:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000500000000000000000000000000000
-- 082:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020202020202020202020202040800000000000000000000000000000
-- 085:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b060204060c0c0c0c0c0c040602040102060c0c0c0c0c0c0c0c0c04020a0
-- 086:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000700000850000000000000000000070
-- 087:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000b0602020202040a0000000300000000000000000000000000030
-- 088:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000700000c5d5000070000000300000000000000000000000000030
-- 089:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000300000c6d6000030000000300000000000000000000000000030
-- 090:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000030a7b7c7d7e7f7300000003000000000a9b90000000000000030
-- 091:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000050a8b8c8d8e8f8500000003000000000aaba0000000000000030
-- 092:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000902060c0c0402080000000300000000000000000000000860030
-- 093:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000030000000000000c9d9000000000030
-- 094:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000b02020a0b02020a0b02020a00030000000000000cada000000e9f930
-- 095:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030e5f53030a5b5303095963000300000000000000000000000eafa30
-- 096:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030e6f63030a6b63030a6b63000300000000000000000000000000030
-- 097:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300090c0c08090c0c08090c0c08000300000000000000000000000000030
-- 098:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000500060c0c0c0c0c0c0c0c0c0400050
-- 099:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020202020202020202020202040f06020202020202020202020204080
-- 101:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080808080808080808080808080808080808080808080808080808080808080808080
-- 102:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 103:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 104:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000080000000800080800000008000008080000000000000000080
-- 105:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000080000000000080008000800080008000800000000000000080
-- 106:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000080000000800080008000800080008080000000000000000080
-- 107:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000080000000800080008000808080008000800000000000000080
-- 108:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000080808000800080800000800080008000800000000000000080
-- 109:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 110:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000808000008000800080808000808080008080800080808000808080000080
-- 111:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000800080008000800080008000800000008000000080008000800080000080
-- 112:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000800080008000800080008000800000008080000080008000800080000080
-- 113:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000800080008000800080008000800080008000000080008000800080000080
-- 114:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000808000000080000080008000808080008080800080808000800080000080
-- 115:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 116:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 117:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 118:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000080
-- 119:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080808080808080808080808080808080808080808080808080808080808080808080808080
-- 120:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000008080808080808080800000000000000080808080808080808000000000000000000000000000000000
-- 121:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080000000000000000000000000000000808080808000000000000000000000000000000000
-- 122:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080800000000000000000000000000000000000000080808000000000000000000000000000000000
-- 123:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 124:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 125:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 126:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 127:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 128:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 129:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 130:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 131:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 132:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080800000000000000000000000000000000000000080808000000000000000000000000000000000
-- 133:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080000000000000000000000000000000808080808000000000000000000000000000000000
-- 134:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080808080800000000000000080808080808080808000000000000000000000000000000000
-- 135:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080808080808080808080808080808080808080808000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdefedcb456789abcba9
-- </WAVES>

-- <SFX>
-- 000:0400040034008400c400e400e400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400300000000000
-- 001:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000
-- 002:010001000100010001000100010001000100010001000100010001000100010001000100010001000100010001000100010001000100010001000100300000000000
-- 016:23a053a073a083a093a0a3a0a3a0c3a0c3a0d3a0e3a0e3a0e3a0e390e370e360e340f320f310f300f300f300f300f300f300f300f300f300f300f300075000000000
-- 017:e120c130b150918081b061d051f041e031c041a0619081609140b130b110c110d100e100f100f100f100f100f100f100f100f100f100e100e100f100400000000000
-- 018:13b07370c320e310f310f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300005000000000
-- 019:631063106310632063206330634063606370639063b063c063c063a06390738083609340a330b310c300d300e300e300f300f300f300f300f300f300005000000000
-- 020:9140910091d0f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f10070b000000000
-- 021:510051005100510051005100510051005100519051905190519051905190519051905190519061906190719081909190a190b190c190d190e190f190500000000000
-- 022:03f013c023c023b023a023a0339033903380338043804370537063606360735073508350834093409330a330b320b320c310d310d310e310f300f300065000000000
-- </SFX>

-- <PATTERNS>
-- 000:455104000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000400004000000000000000000
-- 001:455112100000400012100000000010000000000000000000000000000000000000000000400012100000400012100000000000000000000000000000000000000000000000000000400012100000400012100000000000000000000000000000000000000000000000000000700012a00012b00012400012100000400012100000000000000000000000000000000000700012a00012b00012400012100000400012100000000000000000000000800012b00012c00012400012100010400012
-- 002:155110000010000010000000000000000000000000000000000010000010000010000010700012b00012900012c00012600012100010600012100000000000000000000000000000700012d00012b00012e00012600012100010600012100010000010000000000000000000800012e00012c00012f00012700012100000700012100000000000000000000000000000900012c00012800012a00012900012b00012a00012900012800012700012600012100010600012100010000010000010
-- 003:055110900012c00012800012a00012800012700012600012a00012900012800012700012600012100010600012100010000010000010000010000010800012b00012700012900012600012800012500012700012500012600012400012100010400012100000000000000000000000000000000000000000a00012d00012b00012d00012a00012c00012900012e00012800012f00012700012e00012800012d00012900012c00012600012100010600012100010000010000000000000000000
-- 004:900012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:b00022000000000000100000000000000000000000000000000020000020000020000020800022000020000020100020600022000020000020100020000000000000000000000000700022000020100020000000c00022000000100000000000000000000000000000000000800022000020100020000020600022000020100010000000000000000000000000000000000000b00022700022a00022100020900022100020600022000020100020000000000000000000000000000000000000
-- 006:600022c00022100020800022100020600022a00022100020800022000020600022100020000000000000000000000000000000000000000000000000800022000000a00022000020900022000020700022000020600022000000500022000000100020000000000000000000000000000000000000000000a00022700022b00022700022a00022800022b00022600022c00022500022b00022600022a00022700022900022700022000000600022100020000000000000000000000000000000
-- 008:000000000000000000100000600022100000600022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:1800001c00001010001c06001017001c0600101700000000000000000000000000000000000000000000000000000000ab00ef
-- </TRACKS>

-- <SCREEN>
-- 000:ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd0d000000000d0ddddddddddd0ddddddddddddd00d00d0d0d0dde000ddddddddddddddd00d00d0d0ddd0dd0ddddddddddddddddddddddddddededddddddddddddddddddddddddddcdddddddddddddddddddddddddddddd
-- 015:000000000000000000000000000000000000000000000000000000000d000d000000000000000000000000000000000000000000d00d00dd00d0dddd00000000000000000000000000d0dddd0000000000000000dddddddddddddddd00000000000000000000000000000000000000000000000000000000
-- 016:0000000000000000000000000000000000000000000000000000000dd00d0dedd0000000000000000000000d0d0d0dddd00000000dd0ddd0ddddddddd00000000000000000000000dd0d0dddd000000000000000ddddddddddddddddd0000000000000000000000000000000000000000000000000000000
-- 017:00000000000000000000000000000000000000000000000000000000d0000000d00000000000000000000000d000000dd0000000000000000000000dd000000000000000000000000000000dd000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000
-- 018:00000000000000000000000000000000000000000000000000000000d000000dd0000000000000000000000000000000d0000000000000000000000dd0000000000000000000000000000000d000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000
-- 019:0000000000000000000000000000000000000000000000000000000dd000000ed00000000000000000000000d0000000d0000000000000000000000dd000000000000000000000000000000dd000000000000000e000000000000000d0000000000000000000000000000000000000000000000000000000
-- 020:0000000000000000000000000000000000000000000000000000000d0000000de00000000000000000000000d0000000000000000000000000000000d000000000000000000000000000000dd00000000000000ee00000000000000dd0000000000000000000000000000000000000000000000000000000
-- 021:0000000000000000000000000000000000000000000000000000000dd000000e00000000000000000000000000000000d0000000000000000000000dd000000000000000000000000000000dd000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000
-- 022:0000000000000000000000000000000000000000000000000000000dd000000ee00000000000000000000000d0000000d0000000000000000000000dd000000000000000000000000000000dd0000000000000000000000000000000d0000000000000000000000000000000000000000000000000000000
-- 023:0000000000000000000000000000000000000000000000000000000dd0000000d00000000000000000000000d0d0000d0000000000000000ddddddddddd00de00000000000000000ddddddddd0dd0d0d0000000000000000ddddddddd0dddddd000000000000000000000000000000000000000000000000
-- 024:0000000000000000000000000000000000000000000000000000000dd000000dd00000000000000000000000dd000ddd000000000000000ddddddddddddddeeee00000000000000ddddddddddddddddd0000000e0000000dddddddddd0ddddddd00000000000000000000000000000000000000000000000
-- 025:0000000000000000000000000000000000000000000000000000000dd000000dd0000000000000000000000000000000000000000000000dd000000dd000000ed00000000000000dd000000dd0000000d0000000e000000dd000000dd000000dd00000000000000000000000000000000000000000000000
-- 026:0000000000000000000000000000000000000000000000000000000dd0000000d00000000000000000000000000000000000000000000000d000000dd000000dd00000000000000dd000000dd000000d0000000ed000000dd000000dd000000cd00000000000000000000000000000000000000000000000
-- 027:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000000000000000000000000000dd000000dd000000dd00000000000000dd000000dd0000000d0000000d000000dd000000dd000000dc00000000000000000000000000000000000000000000000
-- 028:0000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000d000000dd0000000d00000000000000dd000000dd0000000d000000dd000000dd000000dd000000cd00000000000000000000000000000000000000000000000
-- 029:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000000000000000000000000000dd000000dd000000dd00000000000000dd000000dd0000000d000000dd000000dd000000dd000000dd00000000000000000000000000000000000000000000000
-- 030:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000000000000000000000000000dd000000dd000000dd00000000000000dd000000dd000000d0000000dd000000dd000000dd000000dc00000000000000000000000000000000000000000000000
-- 031:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000000000000000000000000000dd000000dd000000dd00000000000000dd000000dd0000000d000000dd000000dddddddddd0cccc0dd00000000000000000000000000000000000000000000000
-- 032:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd0000000d00000000000000dd000000dd000000dd00000000000000dd000000dd0000000d000000dd0000000ddddddddcccccccc000000000000000000000000000000000000000000000000
-- 033:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000d00000000d00000000000000dd000000dd000000dd00000000000000dd000000dd000000dd0000000d000000000000000c0000000000000000000000000000000000000000000000000000000
-- 034:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000dd000000dd000000dd00000000000000dd000000dd000000dd0000000d00000000000000c00000000000000000000000000000000000000000000000000000000
-- 035:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd0000000d00000000000000dd000000dd000000dd00000000000000dd000000dd0000000d000000dd00000000000000000000000000000000000000000000000000000000000000000000000
-- 036:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000dd000000dd000000dd00000000000000dd000000dd0000000d000000dd000000000000000d0000000000000000000000000000000000000000000000000000000
-- 037:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000dd000000dd000000dd00000000000000dd000000dd0000000d0000000d00000000000000dd0000000000000000000000000000000000000000000000000000000
-- 038:0000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000d000000dd00000000000000dd000000dd0000000d00000000000000dd000000dd0000000d0000000000000000000000dd0000000000000000000000000000000000000000000000000000000
-- 039:0000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000d000000dd00000000000000dd000000dd000000dd00000000000000dddddddddd000000dd000000000000000cc0cccccd000dddd000000000000000000000000000000000000000000000000
-- 040:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd0000000d00000000000000dd000000dd000000dd000000dd0000000dddddddd00000000d000000000000000ccccccccddddd00dd00000000000000000000000000000000000000000000000
-- 041:0000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000d0000000d00000000000000dd000000dd000000dd000000dd00000000000000000000000d000000000000000c000000cc000000dc00000000000000000000000000000000000000000000000
-- 042:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd0000000d00000000000000dd000000dd0000000d000000dd0000000000000000000000dd000000000000000c000000cc000000dd00000000000000000000000000000000000000000000000
-- 043:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd000000000000000d000000dd0000000d000000dd00000000000000000000000d00000000000000cc0000000c000000dd00000000000000000000000000000000000000000000000
-- 044:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000dd0000000d0000000d000000dd00000000000000000000000d000000000000000c000000cc000000dd00000000000000000000000000000000000000000000000
-- 045:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd0000000d00000000000000dd0000000d0000000d000000dd0000000000000000000000dd000000000000000c000000cc000000cd00000000000000000000000000000000000000000000000
-- 046:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000dd000000dd000000dd000000dd0000000000000000000000dd000000000000000c000000cc000000cd00000000000000000000000000000000000000000000000
-- 047:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd00000000000000ddddddddddd0dddddd000000dd0000000dddddddd0000000dd00000000000000dd000000dd000000dc00000000000000000000000000000000000000000000000
-- 048:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd000000000000000dddddddddddddddd00000000d000000dddddddddd000000dd00000000000000dd0000000d000000cd00000000000000000000000000000000000000000000000
-- 049:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd0000000000000000000000dd00000000000000dd000000dd0000000d000000dd00000000000000dd000000dd000000dd00000000000000000000000000000000000000000000000
-- 050:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd0000000000000000000000dd00000000000000dd000000dd000000dd000000dd00000000000000dd0000000d000000cd00000000000000000000000000000000000000000000000
-- 051:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd0000000000000000000000dd00000000000000dd000000dd000000dd000000dd00000000000000dd000000dd000000dc00000000000000000000000000000000000000000000000
-- 052:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd0000000000000000000000dd00000000000000dd0000000d000000dd000000dd00000000000000dd000000dd000000dc00000000000000000000000000000000000000000000000
-- 053:0000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000dd000000dd0000000000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000d000000dd000000dd00000000000000000000000000000000000000000000000
-- 054:0000000000000000000000000000000000000000000000000000000dd0000000000000000000000dd000000dd000000dd000000dd00000000000000dd00000000000000dd000000dd000000dd000000dd000000dd000000cd000000dd000000cd00000000000000000000000000000000000000000000000
-- 055:0000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddddd000000dddddddddd000000dddddddddddddddddd00000000000000dddddddddd000000ddddd0dddd000000dddddddddc000000dddcdcdddd00000000000000000000000000000000000000000000000
-- 056:00000000000000000000000000000000000000000000000000000000dddddddddddddddddddddddd00000000dddddddd00000000dddddddddddddddd0000000000000000dddddddd00000000dddddddd00000000dddddddd00000000ccdddddd000000000000000000000000000000000000000000000000
-- 063:0000000000000000dd0ddddddddddddd0000000000000000dddddddd00000000dddddddd00000000dddddddddddddddddddddddd00000000dddddddddddddddddddddddd00000000dddddddddddddddddddddddd00000000ddddddddcdddddddddddddcc00000000ccccddddcdddddddddcddddd00000000
-- 064:0000000000000000ddddddddddddddddd00000000000000dddddddddd000000dddddddddd000000dddddddddddddddddddddddddd000000dddddddddddddddddddddddddd000000dddddddddddddddddddddddddc000000dddddddcdddddddddddcdddddd000000cdddddddcdddddddcdcdddddd00000000
-- 065:0000000000000000000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000cd000000dd0000000000000000000000dc000000cc00000000000000000000000d0000000
-- 066:000000000000000c000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000cc000000dd0000000000000000000000cd000000cc0000000000000000000000000000000
-- 067:0000000000000000000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000cc000000dd0000000000000000000000dc000000cc0000000000000000000000000000000
-- 068:0000000000000000c00000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000cc000000cd0000000000000000000000cd0000000c00000000000000000000000d0000000
-- 069:0000000000000000000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000cd0000000000000000000000cc000000dd0000000000000000000000dc000000cc0000000000000000000000000000000
-- 070:0000000000000000000000000000000dd00000000000000dd000000dd000000dd000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000dd000000dd0000000000000000000000cc000000dd0000000000000000000000cd0000000c0000000000000000000000000000000
-- 071:000000000000000c00000000cccccccdd0dddddd0000000dd000000dd000000dd000000dd000000dd0000000cc00cc0c0000000dd000000dd0000000cccccccccccccccdd000000cd0000000ccccccccccccccccc000000dd0000000cccccccc0000000dc000000cc0000000000000000000000000000000
-- 072:00000000000000000000000cccccccccdddddddcd000000dd000000dd0000000d0000000d000000000000000c0cc0ccc000000000000000dd0000000cccccccccccccccc0000000dd000000ccccccccccccccccc0000000cd000000cccccccccc000000cd000000cc00000000000000000000000d0000000
-- 073:0000000000000000c000000cc0000000c000000cd000000dc000000dd0000000d000000dd0000000c00000000000000c000000000000000dd000000cc0000000000000000000000cd000000cc0000000000000000000000dd0000000c000000cc000000dc000000cc0000000000000000000000000000000
-- 074:00000000000000000000000cc000000cc000000cd0000000c000000dd000000dd000000dd0000000c000000000000000000000000000000dd000000cc0000000000000000000000dd000000cc0000000000000000000000cd000000cc000000cc000000dc0000000c0000000000000000000000000000000
-- 075:0000000000000000c0000000c000000cc0000000d000000cd000000dd0000000d000000dd000000c0000000000000000000000000000000dd0000000c0000000000000000000000dd000000cc0000000000000000000000dd000000cc000000cc0000000d000000cc0000000000000000000000000000000
-- 076:000000000000000000000000c000000cc000000dc000000dc000000dd0000000d0000000d0000000c0000000c0000000000000000000000dd000000cc0000000000000000000000dd000000cc0000000000000000000000cd000000cc000000cc0000000c0000000c00000000000000000000000d0000000
-- 077:000000000000000c00000000c0000000c000000cd000000dd0000000d0000000d000000dd000000000000000000000000000000000000000d000000cc0000000000000000000000cd000000cc0000000000000000000000dd000000cc000000cc000000dc0000000c0000000000000000000000000000000
-- 078:0000000000000000c000000cc000000cc0000000c000000dc0000000d000000d0000000dd0000000c000000000000000000000000000000dd000000cc0000000000000000000000cd000000cc0000000000000000000000dd000000cc000000cc000000d00000000c0000000000000000000000000000000
-- 079:00000000000000000000000cc000000cc000000cd000000dc000000d00000000d000000dd0000000c000000000000000c000000000000000d0000000c0000000000000000000000dd000000ccccccccc000000000000000dd000000cc000000cc000000cc000000cc0000000000000000000000000000000
-- 080:0000000000000000c000000cc000000cc0000000c0000000c0000000d0000000d000000dd000000c0000000000000000000000000000000dd000000cc0000000000000000000000cd0000000ccccccccc00000000000000cd000000cc000000cc0000000c0000000c0000000000000000000000000000000
-- 081:00000000000000000000000cc000000cc0000000c000000cd0000000d0000000d0000000d000000c00000000c00000000000000000000000d000000cc0000000000000000000000cd00000000000000cc00000000000000dd000000cc000000cc0000000c0000000c0000000000000000000000000000000
-- 082:0000000000000000c000000cc000000cc000000cd0000000c0000000d0000000d000000d00000000c0000000000000000000000000000000d000000cc0000000000000000000000dd00000000000000cc00000000000000dd000000cc000000cc000000c0000000c000000000000000000000000d0000000
-- 083:000000000000000c0000000cc000000cc0000000c000000dc0000000d0000000d000000dd0000000c00000000000000c000000000000000dd000000cc0000000000000000000000cd00000000000000cc00000000000000cd000000cc000000cc0000000c0000000c0000000000000000000000000000000
-- 084:00000000000000000000000cc000000cc0000000c000000cd00000000000000d0000000dd000000c0000000000000000000000000000000d0000000cc0000000000000000000000cd00000000000000cc0000eee0000000dd000000cc000000cc000000000000000c0000000000000000000000000000000
-- 085:000000000000000c0000000cc000000cc0000000c0000000c000000d0000000d00000000c0000000c000000c0000000000000000c0000000d000000cc0000000000000000000000dc000000000000000c00eee000000000dc000000cc000000cc000000c00000000c0000000000000000000000000000000
-- 086:0000000000000000c000000cc000000cc0000000c000000c0000000d00000000d000000dc0000000c00000000000000000000000c0000000c000000cc0000000000000000000000cd00000000000000cc0ee00000000000cc000000cc000000cc000000c00000000c0000000000000000000000000000000
-- 087:0000000000000000c000000cc000000cc000000c0000000dc0000000d000000d0000000cd000000cc00000000000000c00000000c000000cc000000cc0000000cccccccc0000000cc0000000cc0cccccc00000000000000cc000000cc000000cc0000000c000000c000000000000000000000000d0000000
-- 088:000000000000000c0000000cc000000cc000000dc000000cc0000000d000000000000000c0000000c000000c0000000000000000c000000c0000000cc000000cccccccccc000000cd000000ccccccccc000000000000000cd000000cc000000cc0000000c000000c00000000000000000000000000000000
-- 089:00000000000000000000000cc000000cc0000000c000000dc000000000000000d000000cc000000c00000000000000000000000cc000000cd000000cc000000cc0000000c000000cd000000cc0000000000000000000000cd000000cc000000cc00000000000000c00000000000000000000000000000000
-- 090:0000000000000000c000000cc000000cc0000000c000000dc0000000d000000d00000000c000000c000000000000000c00000000c000000cc000000cc000000cc0000000c000000cc000000cc0000000000000000000000cc000000cc000000cc0000000c000000cc0000000000000000000000000000000
-- 091:0000000000000000c000000cc000000cc0000000c000000cc00000000000000000000000c000000c00000000c00000000000000cc0000000c000000cc000000cc0000000c0000000c000000cc0000000000000000000000cc000000cc000000cc00000000000000c00000000000000000000000000000000
-- 092:000000000000000c0000000cc000000cc000000cc000000cc0000000d0000000d000000dc000000cc00000000000000000000000c0000000c000000cc0000000c000000c00000000c000000cc0000000000000000000000cc0000000c000000cc0000000c000000cc0000000000000000000000000000000
-- 093:0000000000000000c000000cc000000cc000000cc000000cc00000000000000000000000c000000cc000000000000000c000000cc000000cc000000cc0000000c000000c00000000c000000cc0000000000000000000000cc000000cc0000000c00000000000000cc0000000000000000000000000000000
-- 094:000000000000000cc0000000c000000cc000000cc000000cc0000000d000000d00000000c000000cc0000000c000000000000000c0000000c000000cc000000cc0000000c0000000c000000cc0000000000000000000000cc000000cc000000cc000000c0000000cc00000000000000000000000d0000000
-- 095:000000000000000c0000000cccccccccccccccccc000000cccccccccdddddddd0ccc0cccc000000cc000000000000000c000000cc0000000c0000000ccc0ccccc000000c00000000c000000ccc0c0ccccccccccc0000000cc0000000ccccccccc00000000000000cc0000000000000000000000000000000
-- 096:0000000000000000c0000000cccccccccccccccc00000000cccccccccddddddccccccccc0000000cc000000cc0000000c0000000c0000000c0000000cccccccc00000000c000000cc0000000ccccccccccccccccc000000cc0000000cccccccc00000000c0000000c000000000000000c000000000000000
-- 097:0000000000000000c00000000000000cc0000000000000000000000cc000000cc00000000000000cc0000000c0000000c000000cc000000cc00000000000000000000000c000000cc00000000000000000000000c000000cc0000000000000000000000000000000c00000000000000cc000000000000000
-- 098:0000000000000000c00000000000000cc0000000000000000000000cc000000cc00000000000000cc000000cc0000000c000000cc000000dc0000000000000000000000cc000000dc0000000000000000000000c0000000cc0000000000000000000000000000000c000000000000000c000000000000000
-- 099:0000000000000000c00000000000000cc0000000000000000000000cc000000cc00000000000000cc000000c0000000cc000000cc000000cc0000000000000000000000cc000000cc00000000000000000000000c000000cc00000000000000000000000c000000cc00000000000000cc000000000000000
-- 100:0000000000000000c000000000000000c0000000000000000000000cc000000cc00000000000000cc000000cc000000cc000000cc000000cc00000000000000000000000c000000cc0000000000000000000000cc000000cc000000000000000000000000000000cc00000000000000cc000000000000000
-- 101:000000000000000cc00000000000000cc00000000000000000000000c000000cc00000000000000cc000000cc000000cc000000cc0000000c0000000000000000000000cc000000cc00000000000000000000000c000000cc00000000000000000000000c000000cc00000000000000cc000000000000000
-- 102:0000000000000000c00000000000000cc0000000000000000000000cc000000cc00000000000000cc000000cc000000cc000000cc000000cc0000000000000000000000c0000000cc00000000000000000000000c000000cc000000000000000000000000000000cc00000000000000cc000000000000000
-- 103:0000000000000000ccccccccccccccccc0000000000000000000000cccccccccc00000000000000cccccccccc000000cccccccccc000000cccccccccccccccccccccccccc000000cccccccccc0c0ccccccccccccc000000ccccccccccccccccccccccccc0000000cc0ccc00c0000000cccccc0cc00000000
-- 104:0000000000000000cccccccccccccccc000000000000000000000000cccccccc0000000000000000cccccccc00000000cccccccc00000000cccccccccccccccccccccccc0000000ecccccccccccccccccccccccc00000000cccccccccccccccccccccccc00000000cccccccc00000000cc0cccc0e0000000
-- 105:0000000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000000ee0000000000000000000000000000000000000000000000000000000000000000000000ddddddddddddd0ff00e0000000
-- 106:0000000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000dddd000000000000dddd000e000000
-- 107:0000000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000ee00000000000000000000000000000000000000000000000000000000000000000ddd000000000000000000ddd0ee00000
-- 108:000000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000ddd000000000000000000000fddde00000
-- 109:000000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000ee000000000000000000000000000000000000000000000000000000000000000dd00000000000000000000000f00ddd0000
-- 110:000000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000f0000dd000
-- 111:00000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000dd00000000000000000000000000ff000edd00
-- 112:00000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000f0000edd0
-- 113:00000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000dd00000000000000000000000000000f0000e0dd
-- 114:00000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000ee00000000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000f0000ee0d
-- 115:0000000000000000000000000000000000000000000000000000000000000000000000000000000ff000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000dd00000000000000000000000000000000f0000e00
-- 116:0000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000f0000e00
-- 117:0000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000ee0000000000000000000000000000000000000000000000000000000000d0000000000000000000000000000000000f0000ee0
-- 118:0000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000f00000e0
-- 119:0000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000d00000000000000000000000000000000000f00000e0
-- 120:0000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000dd00000000000000000000000000000000000ff0000e0
-- 121:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000ee000000000000000000000000000000000000000000000000000000000d0000000000000000000000000000000000000f0000ee
-- 122:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000f00000e
-- 123:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d00000000000000000000000000000000000000f00000e
-- 124:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d00000000000000000000000000000000000000f00000e
-- 125:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d00000000000000000000000000000000000000f00000e
-- 126:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f00000e
-- 127:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f00000e
-- 128:000000000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f00000e
-- 129:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 130:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 131:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 132:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 133:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 134:000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000d000000000000000000000000000000000000000f000000
-- 135:ccccccccccccccccc0ccccccccccccccccccdccccccccccdddcccccccccccccccccd0cccccccccccc0cccccccccccccccccccccccccc0ccccccccccccccccccccccc0ccccccccdccccccccccccccccccccccccccccccccccc0cccccccccccccccccccc0cccccccc0ccccccc0cccccccccccc0ccccfcc000c
-- </SCREEN>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
