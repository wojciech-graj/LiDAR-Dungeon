-- title:   TODO
-- author:  Wojciech Graj
-- desc:    TODO
-- site:    TODO
-- license: AGPL-3.0-or-later
-- version: 0.0
-- script:  lua

--[[
    TODO: <one line to give the program's name and a brief idea of what it does.>
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
-- FUNCTIONS: move_abs, move_rel, damage

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

--- Get the sign of a number
-- @return int
function g_math_sign(x)
   return x > 0 and 1 or x < 0 and -1 or 0
end

--- Calculate a ray-map intersection
-- Uses Digital Differential Analyzer (DDA) voxel traversal to find closest wall
-- intersection.
-- @return table
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

   local ray_isect_tab = g_ray_isect_tab
   ray_isect_tab.side = side
   if side == 0 then
      ray_isect_tab.dist = side_dist_x - delta_dist_x
   else -- side == 1
      ray_isect_tab.dist = side_dist_y - delta_dist_y
   end

   return ray_isect_tab
end
g_ray_isect_tab = {
   dist = 0,
   side = 0,
}

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

--- Draw a triangular sprite
function g_draw_sprite(pos_x, pos_y, angle, color)
   local math_cos = math.cos
   local math_sin = math.sin
   local player = g_player

   if pos_x > player.pos_x_scr * 25 and pos_x < player.pos_x_scr * 25 + 25
      and pos_y > player.pos_y_scr * 17 and pos_y < player.pos_y_scr * 17 + 17 then
      local pos_x_scl = (pos_x % 25) * 8
      local pos_y_scl = (pos_y % 17) * 8

      tri(
         pos_x_scl + 4 * math_cos(angle),
         pos_y_scl + 4 * math_sin(angle),
         pos_x_scl + 4 * math_cos(angle + 2.7),
         pos_y_scl + 4 * math_sin(angle + 2.7),
         pos_x_scl + 4 * math_cos(angle - 2.7),
         pos_y_scl + 4 * math_sin(angle - 2.7),
         color
      )
   end
end

--- Spawn explosion projectiles
function g_explode(pos_x, pos_y)
   local table_insert = table.insert
   local projs = g_projs
   local math_cos = math.cos
   local math_sin = math.sin
   for theta = 0, 6.28, .55 do
      table_insert(projs, Proj.new(pos_x, pos_y, theta, .005, .5, false, 3))
   end
end

--- Pick up item
function g_item_pickup(pos_x, pos_y)
   mset(pos_x, pos_y, 0)
   g_state = 2
   local math_random = math.random

   -- select 2 different item types
   local item_1_idx = math_random(5)
   local item_2_idx
   repeat
      item_2_idx = math_random(5)
   until (item_2_idx ~= item_1_idx)

   g_items = {
      Item.new(item_1_idx),
      Item.new(item_2_idx),
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

   local string_format = string.format
   local math_floor = math.floor

   -- Print self stats
   print("SELF", 208, 34, 2, true)
   print(string_format("SPD:%.1f", player.speed * 1000), 209, 42, 2, false, 1, true)

   -- Print scanner stats
   print("SCAN", 208, 50, 8, true)
   print(string_format("RNG:%d", math_floor(player.ping_range)), 209, 58, 8, false, 1, true)
   print(string_format("REL:%.1f", player.ping_cooldown_max * .001), 209, 66, 8, false, 1, true)
   print(string_format("SPR:%d", math_floor(player.ping_spread * 10)), 209, 74, 8, false, 1, true)

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
   print(string_format("SPR:%d", math_floor(weapon.spread * 10)), 209, 114, 7, false, 1, true)
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
function g_print_rainbow(text, pos_x, pos_y)
   local t = g_t
   local color_start = t // 70
   local offset_y = t / 100
   local math_sin = math.sin

   for k, v in ipairs(text) do
      print(v, pos_x + 6 * k, pos_y + math_sin(offset_y + k * .7), color_start + k, true)
   end
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
   if lx < 6 or ly < 6 then
      return
   end
   table.insert(tab, {sx, sy, ex, ey, lx, ly})
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

   local start_room = table_remove(rooms, math_random(#rooms))

   local map_place_rand = g_map_place_rand

   -- Place items, enemies
   for _, room in pairs(rooms) do
      map_place_rand(room, 8, math_random(3) - 1)
      map_place_rand(room, 16, math_random() < .3 and 1 or 0)
      map_place_rand(room, 24, math_random(4) - 1)
   end

   -- Place exits
   for i = 1, 3 do
      map_place_rand(rooms[math_random(#rooms)], 32, 1)
   end

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

function Item.new(type_idx)
   local self = setmetatable({}, Item)
   local math_random = math.random
   self.type_idx = type_idx or math_random(5)

   if self.type_idx == 1 then
      self.data = math_random(8)
      self.desc = string.format("+%d%%\nSPEED", self.data)
   elseif self.type_idx == 2 then
      self.subtype_idx = math_random(g_player.can_bounce and 3 or 4)
      if self.subtype_idx == 1 then
         self.data = math_random(4)
         self.desc = string.format("+%d\nRANGE", self.data)
      elseif self.subtype_idx == 2 then
         self.data = math_random(8)
         self.desc = string.format("+%d%%\nSPREAD", self.data)
      elseif self.subtype_idx == 3 then
         self.data = math.random(10)
         self.desc = string.format("-%d%%\nCOOLDOWN", self.data)
      else -- self.subtype_idx == 4
         self.desc = "+BOUNCE"
      end
   elseif self.type_idx == 3 or self.type_idx == 4 then
      local player = g_player
      self.subtype_idx = math_random(player.weapon.can_bounce and 6 or 7)
      if self.subtype_idx ~= 1 and player.weapon.proj_type ~= self.type_idx - 3 then
         self.type_idx = player.weapon.proj_type + 3
      end
      if self.subtype_idx == 1 then -- TODO
         local bullet_cnt = math_random(2)
         local damage = math_random(2)
         local spread = math_random(1000) / 1000
         local cooldown = math_random(600, 1500)
         local speed = (cooldown - 600) // 300 + 1
         self.data = Weapon.new(self.type_idx - 3, 1, bullet_cnt, spread, .1, cooldown, 20, -1, damage, .005)
         self.desc = string.format("%dBUL %dDMG\n%sSPR %sSPD", bullet_cnt, damage, math.floor(spread * 3), speed)
      elseif self.subtype_idx == 2 then
         self.data = math_random(2)
         self.desc = string.format("+%d\nBULLETS", self.data)
      elseif self.subtype_idx == 3 then
         self.data = math_random(30)
         self.desc = string.format("+%d%%\nDAMAGE", self.data)
      elseif self.subtype_idx == 4 then
         self.data = math_random(30) - 15
         self.desc = string.format("%s%d%%\nSPREAD", (self.data < 0) and "" or "+", self.data)
      elseif self.subtype_idx == 5 then
         self.data = math_random(20)
         self.desc = string.format("-%d%%\nCOOLDOWN", self.data)
      elseif self.subtype_idx == 6 then
         self.data = math.random(4)
         self.desc = string.format("+%d\nRANGE", self.data)
      else -- self.subtype_idx == 7
         self.desc = "+BOUNCE"
      end
   else -- self.type_idx == 5
      self.data = math_random(3)
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
      player.speed = player.speed * (1 + self.data * .01)
   elseif self.type_idx == 2 then
      if self.subtype_idx == 1 then
         player.ping_range = player.ping_range + self.data
      elseif self.subtype_idx == 2 then
         player.ping_spread = player.ping_spread * (1 + self.data * .01)
      elseif self.subtype_idx == 3 then
         player.ping_cooldown_max = (1 - self.data * .01) * player.ping_cooldown_max
      else -- self.subtype_idx == 4
         player.can_bounce = true
      end
   elseif self.type_idx == 3 or self.type_idx == 4 then
      if self.subtype_idx == 1 then
         player.weapon = self.data
      elseif self.subtype_idx == 2 then
         player.weapon.proj_cnt = player.weapon.proj_cnt + self.data
      elseif self.subtype_idx == 3 then
         player.weapon.damage = player.weapon.damage * (1 + self.data * .01)
      elseif self.subtype_idx == 4 then
         player.weapon.spread = player.weapon.spread * (1 + self.data * .01)
      elseif self.subtype_idx == 5 then
         player.weapon.cooldown_max = player.weapon.cooldown_max * (1 - self.data * .01)
      elseif self.subtype_idx == 6 then
         player.weapon.range = player.weapon.range + self.data
      else -- self.subtype_idx == 7
         playper.weapon.can_bounce = true
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
   local isect = g_ray_isect(self.pos_x, self.pos_y, dir_x, dir_y)
   if isect.dist > .4 then -- not approaching wall
      local dist_min = math.min(dist_mag, math.max(0, isect.dist - .4))
      self.pos_x = self.pos_x + dir_x * dist_min
      self.pos_y = self.pos_y + dir_y * dist_min
      return dist_min
   end
   return 0
end

----------------------------------------
-- Hitmark -----------------------------
----------------------------------------

-- type_idx:
-- 0: wall
-- 1: item
-- 2: exit

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
   if self.type_idx == 0 then
      color = 12 + self.age * .002
   elseif self.type_idx == 1 then
      color = 4
   else -- self.type_idx == 2
      color = 11
   end
   g_pix_bounded(self.pos_x, self.pos_y, color)
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
   can_bounce = false,
}
Weapon.__index = Weapon

function Weapon.new(proj_type, target, proj_cnt, spread, accuracy, cooldown, range, ammo, damage, speed, can_bounce)
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
   self.can_bounce = can_bounce or false
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
         math_random(1000, 1500),
         math_random(10, 15),
         -1,
         2,
         math_random() * .003 + .004,
         math_random() < .3
      )
   elseif wpn_type == 2 then -- shotgun
      return Weapon.new(0,
         target,
         math_random(2, 3),
         math_random() * .9,
         math_random() * .5,
         math_random(1500, 2000),
         math_random(6, 9),
         -1,
         1,
         math_random() * .002 + .003,
         math_random() < .1
      )
   elseif wpn_type == 3 then -- circle
      return Weapon.new(0,
         target,
         math_random(4, 6),
         6.28,
         .2,
         math_random(2000, 3000),
         math_random(6, 9),
         -1,
         1,
         math_random() * .002 + .0015,
         math_random() < .1
      )
   else -- wpn_type == 4 -- rapid-fire
      return Weapon.new(0,
         target,
         1,
         0,
         .4,
         math_random(500, 900),
         math_random(7, 11),
         -1,
         .5,
         math_random() * .001 + .0035,
         math_random() < .5
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
      local dangle = self.spread / self.proj_cnt
      local projs = g_projs
      local table_insert = table.insert
      for i = 1, self.proj_cnt do
         table_insert(projs, Proj.new(pos_x, pos_y, angle - self.spread + dangle * i + (2 * math.random() - 1) * self.accuracy, self.speed, self.range, self.can_bounce, self.target + 1, self.damage))
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
   speed = 0,
   health = 0,
   weapon = nil,
   ai_idx = 1,
   pos_x_player_last = 0,
   pos_y_player_last = 0,
   vel_side = 0,
}
Enemy.__index = Enemy

function Enemy.new(pos_x, pos_y, speed, health, weapon, ai_idx)
   local self = setmetatable({}, Enemy)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.speed = speed
   self.health = health
   self.weapon = weapon
   self.ai_idx = ai_idx
   mset(pos_x, pos_y, 0)
   self:mark_area(true)
   return self
end

function Enemy.new_random(pos_x, pos_y)
   local math_random = math.random
   return Enemy.new(
      pos_x,
      pos_y,
      math_random() * .025 + .005,
      math_random(5 + math.floor(g_player.floor * 2.5)),
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
      Weapon.new(0, 0, 8, 6.28, .1, 1100, 15, -1, 1, .005, true),
      Weapon.new(0, 0, 4, .5, .1, 800, 15, -1, 1, .006, false),
      Weapon.new(0, 0, 1, 0, .2, 250, 15, -1, 1, .008, false),
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
      g_draw_sprite(self.pos_x, self.pos_y, self.angle, 2)
   end

   self:mark_area(false)

   local player = g_player
   local dir_x = player.pos_x - self.pos_x
   local dir_y = player.pos_y - self.pos_y
   local dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)

   if self.ai_idx < 5 then
      self.weapon:process(delta)
      local dir_invmag = 1 / dir_mag
      local isect = g_ray_isect(self.pos_x, self.pos_y, dir_invmag * dir_x, dir_invmag * dir_y)
      local speed_fwd
      if dir_mag < isect.dist then -- in line-of-sight
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
      else
         dir_x = self.pos_x_player_last - self.pos_x
         dir_y = self.pos_y_player_last - self.pos_y
         dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)
         speed_fwd = math.min(self.speed, dir_mag)
      end
      self.angle = math.atan2(dir_y, dir_x)

      if self.ai_idx == 1 then
      elseif self.ai_idx == 2 or self.ai_idx == 3 then
         self.vel_side = self.vel_side + (math.random() - .5) * self.speed * .2
         if self.ai_idx == 3 then
            speed_fwd = speed_fwd + (math.random() - .5) * self.vel_side * 2
         end
      end
      self:move_rel(speed_fwd, self.vel_side)
   else -- self.ai_idx == 5
      self.angle = math.atan2(dir_y, dir_x)
      self.b_ai_timer = self.b_ai_timer + delta
      local ai_state = (self.b_ai_timer // 8000) % 4
      if ai_state < 3 then
         local speed_fwd
         if dir_mag < 5 then
            speed_fwd = -self.speed
         elseif dir_mag > 8 then
            speed_fwd = self.speed
         else
            speed_fwd = 0
         end
         self:move_rel(speed_fwd, (math.random() - .5) * self.speed * .1)
         local weapon = self.b_weapons[ai_state + 1]
         weapon:process(delta)
         weapon:fire(self.pos_x, self.pos_y, self.angle)
      else -- ai_state == 3
         if #g_enemies < 7 and math.random() < .01 then
            local math_random = math.random
            table.insert(g_enemies, Enemy.new(self.pos_x,
                  self.pos_y,
                  .02,
                  1,
                  Weapon.new(0, 0, 1, 0, .1, 1700, 7, -1, 1, 1, true),
                  1
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

      local explosion_cnt
      local explosion_spread
      if self.ai_idx == 5 then
         explosion_cnt = 20
         explosion_spread = 4

         -- Drop loot
         for i = 1, math_random(3) + 2 do
            local pos_x = self.pos_x + math_random(3) - 2
            local pos_y = self.pos_y + math_random(3) - 2
            if mget(pos_x, pos_y) == 0 then
               mset(pos_x, pos_y, 16)
            end
         end

         mset(211, 127, 32) -- Place exit
      else
         explosion_cnt = 5
         explosion_spread = 1
         if math_random() < .2 then
            mset(self.pos_x, self.pos_y, 16)
         end
      end
      for i = 1, explosion_cnt do
         explode(self.pos_x + (math_random() - .5) * explosion_spread, self.pos_y + (math_random() - .5) * explosion_spread)
      end

      self:mark_area(false)

      local player = g_player
      player.stats_flr.enemies_destroyed = player.stats_flr.enemies_destroyed + 1
      return true
   end
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
   can_bounce = false,
   type_idx = 0,
   damage = 0,
}
Proj.__index = Proj

function Proj.new(pos_x, pos_y, angle, vel, dist_max, can_bounce, type_idx, damage)
   local self = setmetatable({}, Proj)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.dir_x = math.cos(angle)
   self.dir_y = math.sin(angle)
   self.vel = vel
   self.dist_max = dist_max
   self.dist_rem = dist_max
   self.bounce_rem = bounce_rem
   self.can_bounce = can_bounce
   self.type_idx = type_idx
   self.damage = damage
   local isect = g_ray_isect(pos_x, pos_y, self.dir_x, self.dir_y)
   self.wall_dist = isect.dist
   self.wall_side = isect.side
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
            local own_angle = math.atan2(self.dir_y, self.dir_x)
            local tgt_angle = math.atan2(rel_pos_y, rel_pos_x)
            local dangle = math.min(math.max(-.015, tgt_angle - own_angle), .015)
            own_angle = own_angle + dangle
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
      elseif self.type_idx == 0 or self.type_idx == 2 then -- player's projectile or ping
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
               (tile == 16) and 1 or 2
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
         elseif self.type_idx == 1 then
            color = 2
         elseif self.type_idx == 2 then
            color = 6
         else -- self.type_idx == 3
            color = 5 - 3 * (self.dist_rem / self.dist_max)
         end
         g_pix_bounded(self.pos_x, self.pos_y, color)
         return false
      end

      table.insert(g_hitmarks, Hitmark.new(self.pos_x, self.pos_y, 0))

      if not self.can_bounce then
         return true
      end

      -- Bounce
      self.dist = -self.wall_dist
      if self.wall_side == 0 then
         self.dir_x = -self.dir_x
      else -- self.wall_side == 1
         self.dir_y = -self.dir_y
      end

      local isect = g_ray_isect(self.pos_x, self.pos_y, self.dir_x, self.dir_y)
      self.wall_dist = isect.dist
      self.wall_side = isect.side
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
   ping_range = 10,
   weapon = nil,
   move_abs = Entity.move_abs,
   move_rel = Entity.move_rel,
   health = 5,
   speed = .004,
   ping_cooldown_max = 400,
   can_bounce = false,
   stats_flr = Stats.new(),
   stats_total = Stats.new(),
   floor = 1,
   iframe_cooldown = 0,
}
Player.__index = Player

function Player.new(room)
   local self = setmetatable({}, Player)
   self.weapon = Weapon.new(0, 1, 1, .3, .15, 600, 7, -1, 1, .005)
   self:place_in_room(room)
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
      table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, self.ping_range, self.can_bounce, 0))
   end
end

function Player:process(delta)
   local math_max = math.max
   self.ping_cooldown = math_max(self.ping_cooldown - delta, 0)
   self.ping_passive_cooldown = self.ping_passive_cooldown - delta
   self.iframe_cooldown = math_max(self.iframe_cooldown - delta, 0)

   if self.ping_passive_cooldown < 0 then
      self.ping_passive_cooldown = self.ping_cooldown_max
      local table_insert = table.insert
      local projs = g_projs
      for theta = 0, 6.28, .1 do
         table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 2, self.can_bounce, 0))
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
      g_state = 3
   end

   if (self.iframe_cooldown // 100) % 2 == 0 then
      g_draw_sprite(self.pos_x, self.pos_y, self.angle, 5)
   end
end

function Player:damage(dmg)
   if self.iframe_cooldown == 0 then
      self.health = self.health - dmg
      self.stats_flr.damage_taken = self.stats_flr.damage_taken + dmg
      self.stats_flr.bullets_taken = self.stats_flr.bullets_taken + 1
      self.iframe_cooldown = 600
   end
end

function Player:heal(amount)
   self.health = math.min(self.health + amount, 7)
end

----------------------------------------
-- main --------------------------------
----------------------------------------

--- g_state:
-- 1: game
-- 2: item pickup
-- 3: floor clear

function init()
   local start_room = g_map_gen()
   g_player = Player.new(start_room)
   g_projs = {}
   g_hitmarks = {}
   g_enemies = {}
   g_state = 1
   g_items = {}
   g_t = time()
   g_mouse = table.pack(mouse())
   g_mouse_prev = {}
   g_debug = false
end

function BOOT()
   init()
   g_prev_time = time()
end

function process_game(delta)
   cls()

   local player = g_player
   local projs = g_projs
   local hitmarks = g_hitmarks
   local enemies = g_enemies

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
end

function process_item_pickup(delta)
   cls()

   map(210, 0, 18, 15, 28, 8)
   print("SKIP", 88, 106, 2, true)
   g_print_rainbow(gc_upgrade_text_tab, 73, 10)

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
         elseif mouse_x >= 116 and mouse_x < 164 then
            items[2]:apply()
            g_state = 1
         end
      elseif mouse_y >= 104 and mouse_y <= 112
         and mouse_x >= 76 and mouse_x <= 124 then
         g_state = 1
      end
   end
end
gc_upgrade_text_tab = {"U", "P", "G", "R", "A", "D", "E"}

function process_floor_clear(delta)
   cls()

   map(210, 68, 16, 15, 36, 8)
   print("CONTINUE", 77, 106, 6, true)
   g_print_rainbow(g_floor_clear_text_tab, 55, 10)

   g_ui_render()

   local string_format = string.format
   local player = g_player
   local stats = player.stats_flr

   print(string_format("Damage Taken.......%.1f", stats.damage_taken), 56, 24, 13, true, 1, true)
   print(string_format("Damage Dealt.......%.1f", stats.damage_dealt), 56, 32, 13, true, 1, true)
   print(string_format("Bullets Fired......%d", stats.bullets_fired), 56, 40, 13, true, 1, true)
   print(string_format("Accuracy...........%.1f", 100 * stats.bullets_hit / stats.bullets_fired), 56, 48, 13, true, 1, true)
   print(string_format("Bullets Taken......%d", stats.bullets_taken), 56, 56, 13, true, 1, true)
   print(string_format("Scans Performed....%d", stats.pings), 56, 64, 13, true, 1, true)
   print(string_format("Upgrades Obtained..%d", stats.items_collected), 56, 72, 13, true, 1, true)
   print(string_format("Enemies Destroyed..%d", stats.enemies_destroyed), 56, 80, 13, true, 1, true)
   print(string_format("Distance Travelled.%d", math.floor(stats.distance_travelled)), 56, 88, 13, true, 1, true)

   -- Check for selection
   local mouse_x, mouse_y, mouse_left = table.unpack(g_mouse)
   if mouse_left and not g_mouse_prev[3] then
      if mouse_y >= 104 and mouse_y <= 112
         and mouse_x >= 68 and mouse_x <= 132 then
         player.floor = player.floor + 1
         g_state = 1
         g_projs = {}
         g_hitmarks = {}
         g_enemies = {}
         if player.floor % 2 == 1 then
            local start_room = g_map_gen()
            g_player:place_in_room(start_room)
            mset(220, 127, 40)
            mset(211, 127, 0)
         else -- boss fight
            local player = g_player
            player.pos_x = 201
            player.pos_y = 127
         end
      end
   end
end
g_floor_clear_text_tab = {
   "F", "L", "O", "O", "R",
   " ", 0,
   " ", "C", "L", "E", "A", "R"
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

   -- process
   local state = g_state
   if state == 1 then
      process_game(delta)
   elseif state == 2 then
      process_item_pickup(delta)
   else -- state == 3
      process_floor_clear(delta)
   end

   -- Custom mouse sprite
   spr(257, v_mouse[1] - 4, v_mouse[2] - 4, 0)

   if g_debug then
      print(string.format("FPS %d", math.floor(1000 / delta)), 0, 0, 5)
   end
end

-- <TILES>
-- 001:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
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
-- 096:0000cdde0000cdee000cdeee00cddeef00cdefff0cdeff000deff0000def0000
-- 097:eeffd000ed000000eed00000eedc0000feddc000ffeddc000ffeddc000ffedcc
-- 098:00cddee000dddee000ddeeed00deeedd00deeeed0cdeeeeecddeffffddeef000
-- 099:000000c000000cd00000cde0ccccde00ddddee00eeeee000fff0000000000000
-- 112:0ef000000ee000000000000000000000000000000000000c000000cd00000cdd
-- 113:000fccdd000cddde00cdddee0cdddeeecdddeeffdddeefffddeefff0deefff00
-- 114:deef0000eeffc000effddc00ffedddc0feeedddcfffeeddd0fffeedd00fffeed
-- 115:0000000000000000000000000000000000000000c0000000dc000000ddc00000
-- 128:0000cddd000cddde00cdddee00cd0eef00d000ef00d000ff00eefff0000fff00
-- 129:eefff000efff0000fff00000ff000000f0000000000000000000000000000000
-- 130:000fffee0000fffe00000fff000000ff0000000f000000000000000000000000
-- 131:dddc0000edddc000eedddc00feedddc0ffeeddc0fffeede00fffeef000fffff0
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
-- 001:800000000080000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000070000000000000000000000000
-- 002:8000000000000081010080000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000b060202040a00000b060202040a00030000000000000000000000000
-- 003:800000000080000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 004:808080808080000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 005:800000008000000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 006:800000008000000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 007:8000000000000000000080000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000e0c0c0c0c0d00000e0c0c0c0c0d00030000000000000000000000000
-- 008:800000008000000200008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 009:800000008000000000008000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 010:800000008080800080808080808080800000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300090602020408000009060202040800030000000000000000000000000
-- 011:800000008000000000000000000000800000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000030000000000000000000000000
-- 012:80000000800000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000060c0c0c0c040000000000030000000000000000000000000
-- 013:808080808000000000000000000000800000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000050000000000000000000000000
-- 014:800000000000000000000000000000800000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020202020202020202020202020204080000000000000000000000000
-- 015:800000008000000000000000000000800000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:808080808080808080808080808080808080808080808080800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111213141516171c1d1e1f18191a1b10515253500000000000000000000
-- 018:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000212223242526272c2d2e2f28292a2b20616263600000000000000000000
-- 019:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000313233343536373c3d3e3f38393a3b30717273700000000000000000000
-- 020:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000414243444546474c4d4e4f48494a4b40818283800000000000000000000
-- 034:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b0602040a000000000000000000000000000000000000000000000000000
-- 035:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000000000000000000000000000000000000000
-- 036:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
-- 037:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000005000000000000000000000000000000000000000000000000000
-- 038:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000000000000000000000000000000000000000
-- 039:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
-- 040:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000000000000000000000000000000000000000
-- 041:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000000000000000000000000000000000000000
-- 042:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
-- 043:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000005000000000000000000000000000000000000000000000000000
-- 044:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0c0c0c0d000000000000000000000000000000000000000000000000000
-- 045:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000007000000000000000000000000000000000000000000000000000
-- 046:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
-- 047:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000003000000000000000000000000000000000000000000000000000
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
-- 119:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080808080808080808080808080808080808080808000000000000000000000000000000000
-- 120:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080808080800000000000000080808080808080808000000000000000000000000000000000
-- 121:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080808080000000000000000000000000000000808080808000000000000000000000000000000000
-- 122:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080800000000000000000000000000000000000000080808000000000000000000000000000000000
-- 123:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 124:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008080000000000000000000000000000000000000000000808000000000000000000000000000000000
-- 125:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 126:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000008000000000000000000000000000000000
-- 127:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000008200008000000000000000000000000000000000
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
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <TRACKS>
-- 000:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
