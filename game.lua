-- title:   TODO
-- author:  Wojciech Graj
-- desc:    TODO
-- site:    TODO
-- license: AGPL-3.0-only
-- version: 0.0
-- script:  lua

--- Conventions
-- VARIABLE delta: time since last frame (ms)
-- VARIABLE g_*: global variable
-- VARIABLE dir_*: normalized direction
-- VARIABLE c_*: constant variable
-- FUNCTION Class:process(delta): executed every frame. May return boolean,
-- where true signifies that object should be deleted

--- Interfaces
-- Entity:
-- VARIABLES: pos_x, pos_y, angle, health
-- FUNCTIONS: move_abs, move_rel, damage

----------------------------------------
-- utility functions -------------------
----------------------------------------

--- Get the sign of a number
-- @param x number
-- @return int
function g_math_sign(x)
   return x > 0 and 1 or x < 0 and -1 or 0
end

--- Calculate a ray-map intersection
-- Uses Digital Differential Analyzer (DDA) voxel traversal to find closest wall
-- intersection.
-- @param pos_x number
-- @param pos_y number
-- @param dir_x number
-- @param dir_y number
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
      if tile_data == 1 then
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
-- @param rel_pos_x number
-- @param rel_pos_y number
-- @param dir_x number
-- @param dir_y number
-- @param rad number
-- @return distance along ray if colliding, 1e9 otherwise
function g_ray_circ_collides(rel_pos_x, rel_pos_y, dir_x, dir_y, rad)
   if (rel_pos_x * dir_x + rel_pos_y * dir_y) / math.sqrt(rel_pos_x * rel_pos_x + rel_pos_y * rel_pos_y) > 0 then --in front
      local dist_perp = math.abs(dir_x * rel_pos_y - dir_y * rel_pos_x)
      if dist_perp < rad then
         return rel_pos_x * rel_pos_x + rel_pos_y * rel_pos_y - dist_perp * dist_perp
      end
   end
   return 1e9
end

--- Draw a triangular sprite
-- @param pos_x number
-- @param pos_y number
-- @param angle number
-- @param color int
function g_draw_sprite(pos_x, pos_y, angle, color)
   local math_cos = math.cos
   local math_sin = math.sin
   local pos_x_scl = 8 * pos_x
   local pos_y_scl = 8 * pos_y

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

--- Spawn explosion projectiles
-- @param pos_x number
-- @param pos_y number
function g_explode(pos_x, pos_y)
   local table_insert = table.insert
   local projs = g_projs
   local math_cos = math.cos
   local math_sin = math.sin
   for theta = 0, 6.28, 0.55 do
      table_insert(projs, Proj.new(pos_x, pos_y, theta, .005, .5, false, 3))
   end
end

--- Pick up item
-- @param pos_x number
-- @param pos_y number
function g_item_pickup(pos_x, pos_y)
   mset(pos_x, pos_y, 0)
   g_state = 2
   local math_random = math.random
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
   local player = g_player

   map(210, 34, 5, 17, 200, 0)
   map(217 - player.health, 51, 1, 3, 208, 8)
   map(210 + 7 * player.ping_cooldown / player.ping_cooldown_max, 57, 1, 3, 216, 8)
   map(210 + 7 * player.weapon.cooldown / player.weapon.cooldown_max, 54, 1, 3, 224, 8)

   local string_format = string.format
   print("SELF", 208, 34, 2, true)
   print(string_format("SPD:%.1f", player.speed * 1000), 209, 42, 2, false, 1, true)

   print("SCAN", 208, 50, 8, true)
   print(string_format("RNG:%d", player.ping_range), 209, 58, 8, false, 1, true)
   print(string_format("REL:%.1f", player.ping_cooldown_max * .001), 209, 66, 8, false, 1, true)
   print(string_format("SPR:%d", player.ping_spread * 10), 209, 74, 8, false, 1, true)

   local weapon = player.weapon
   if weapon.proj_type == 0 then
      print("GUN", 212, 82, 7, true)
   else -- weapon.proj_type == 1
      print("RCKT", 208, 82, 7, true)
   end
   print(string_format("DMG:%d", weapon.damage), 209, 90, 7, false, 1, true)
   print(string_format("REL:%.1f", weapon.cooldown_max * .001), 209, 98, 7, false, 1, true)
   print(string_format("BUL:%d", weapon.proj_cnt), 209, 106, 7, false, 1, true)
   print(string_format("SPR:%d", weapon.spread * 10), 209, 114, 7, false, 1, true)
   print(string_format("RNG:%d", weapon.range), 209, 122, 7, false, 1, true)
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
         self.data = Weapon.new(self.type_idx - 3, 1, bullet_cnt, spread, .1, cooldown, 20, -1, damage)
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
         player.cooldown_max = (1 - self.data * .01) * player.cooldown_max
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
         player.weapon.can_bounce = true
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
-- @param dist_front number
-- @param dist_side number
function Entity:move_rel(dist_front, dist_side)
   local dir_x_self = math.cos(self.angle)
   local dir_y_self = math.sin(self.angle)
   self:move_abs(dist_front * dir_x_self + dist_side * dir_y_self, dist_front * dir_y_self - dist_side * dir_x_self)
end

--- Move an entity relative to the XY axes
-- @param dist_front number
-- @param dist_side number
function Entity:move_abs(dist_x, dist_y)
   local dist_mag = math.sqrt(dist_x * dist_x + dist_y * dist_y)
   local dist_invmag = 1 / dist_mag
   local dir_x = dist_x * dist_invmag
   local dir_y = dist_y * dist_invmag
   local isect = g_ray_isect(self.pos_x, self.pos_y, dir_x, dir_y)
   if isect.dist > 0.4 then
      local dist_min = math.min(dist_mag, math.max(0, isect.dist - 0.4))
      self.pos_x = self.pos_x + dir_x * dist_min
      self.pos_y = self.pos_y + dir_y * dist_min
   end
end

----------------------------------------
-- Hitmark -----------------------------
----------------------------------------

-- type_idx:
-- 0: wall
-- 1: item

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
      color = 12 + self.age * 0.002
   else -- self.type_idx == 1
      color = 6
   end
   pix(self.pos_x * 8, self.pos_y * 8, color)
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
   can_bounce = false,
}
Weapon.__index = Weapon

function Weapon.new(proj_type, target, proj_cnt, spread, accuracy, cooldown, range, ammo, damage, can_bounce)
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
   self.can_bounce = can_bounce or false
   return self
end

function Weapon:process(delta)
   self.cooldown = math.max(self.cooldown - delta, 0)
end

function Weapon:fire(pos_x, pos_y, angle)
   if self.cooldown == 0 and self.ammo ~= 0 then
      self.cooldown = self.cooldown_max
      self.ammo = self.ammo - 1
      local math_random = math.random
      local dangle = (self.spread * 2) / self.proj_cnt
      local projs = g_projs
      local table_insert = table.insert
      for i = 0, self.proj_cnt - 1 do
         table_insert(projs, Proj.new(pos_x, pos_y, angle - self.spread + dangle * i + (2 * math.random() - 1) * self.accuracy, .01, 5, self.can_bounce, self.target + 1, self.damage))
      end
   end
end

----------------------------------------
-- Enemy -------------------------------
----------------------------------------

Enemy = {
   pos_x = 0,
   pos_y = 0,
   angle = 0,
   display_timer = 0,
   move_abs = Entity.move_abs,
   move_rel = Entity.move_rel,
   speed = 0,
   health = 0,
   tab_idx = 0,
   weapon = nil,
}
Enemy.__index = Enemy

function Enemy.new(pos_x, pos_y, speed, health, weapon)
   local self = setmetatable({}, Enemy)
   self.pos_x = pos_x
   self.pos_y = pos_y
   self.speed = speed
   self.health = health
   self.weapon = weapon
   local enemies = g_enemies
   self.tab_idx = enemies and #enemies + 1 or 1
   mset(pos_x, pos_y, 0)
   return self
end

function Enemy:process(delta)
   self.display_timer = self.display_timer + delta
   self.weapon:process(delta)
   if self.display_timer > 1500 then
      self.display_timer = 0
   elseif self.display_timer < 300 then
      g_draw_sprite(self.pos_x, self.pos_y, self.angle, 2)
   end

   local player = g_player
   local dir_x = player.pos_x - self.pos_x
   local dir_y = player.pos_y - self.pos_y
   local dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)
   local dir_invmag = 1 / dir_mag
   local isect = g_ray_isect(self.pos_x, self.pos_y, dir_invmag * dir_x, dir_invmag * dir_y)
   if dir_mag < isect.dist then -- if in line-of-sight
      self.angle = math.atan2(dir_y, dir_x)
      self:move_rel(self.speed, 0)
      self.weapon:fire(self.pos_x, self.pos_y, self.angle)
   end
end

function Enemy:damage(dmg)
   self.health = self.health - dmg
   self.display_timer = 0
   if self.health <= 0 then
      g_enemies[self.tab_idx] = nil
   end
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
   if self.dist_rem < 0 then
      return true
   end

   while true do
      local min_dist = math.min(self.wall_dist, dist)

      -- Entity collision
      if self.type_idx == 1 or self.type_idx == 4 then
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
         local coll_dist = ray_circ_collides(rel_pos_x, rel_pos_y, self.dir_x, self.dir_y, 0.4)
         if coll_dist <= min_dist * min_dist then
            g_explode(self.pos_x + self.dir_x * coll_dist, self.pos_y + self.dir_y * coll_dist)
            player:damage(self.damage)
            return true
         end
      elseif self.type_idx == 2 then
         local enemies = g_enemies
         local ray_circ_collides = g_ray_circ_collides
         for k, v in pairs(enemies) do
            local rel_pos_x = v.pos_x - self.pos_x
            local rel_pos_y = v.pos_y - self.pos_y
            local coll_dist = ray_circ_collides(rel_pos_x, rel_pos_y, self.dir_x, self.dir_y, 0.4)
            if coll_dist <= min_dist * min_dist then
               g_explode(self.pos_x + self.dir_x * coll_dist, self.pos_y + self.dir_y * coll_dist)
               v:damage(self.damage)
               return true
            end
         end
      end

      self.wall_dist = self.wall_dist - dist
      self.pos_x = self.pos_x + self.dir_x * min_dist
      self.pos_y = self.pos_y + self.dir_y * min_dist

      if self.type_idx == 0 then
         local tile_data = mget(self.pos_x, self.pos_y)
         if tile_data == 2 then
            local math_floor = math.floor
            local pos_x_floor = math_floor(self.pos_x)
            local pos_y_floor = math_floor(self.pos_y)
            local rad_x = 2 * (self.pos_x - pos_x_floor - .5)
            local rad_y = 2 * (self.pos_y - pos_y_floor - .5)
            local angle = math.atan2(rad_y, rad_x)
            table.insert(g_hitmarks, Hitmark.new(
                  pos_x_floor + .5 + .3 * math.cos(angle),
                  pos_y_floor + .5 + .3 * math.sin(angle),
                  1
            ))
            return false
         elseif tile_data == 3 then
            local math_floor = math.floor
            local pos_x_floor = math_floor(self.pos_x)
            local pos_y_floor = math_floor(self.pos_y)
            table.insert(g_enemies, Enemy.new(pos_x_floor + .5, pos_y_floor + .5, 0.001, 4,
               Weapon.new(0, 0, 2, .2, .4, 1300, 7, -1, 1)))
            return false
         end
      end

      if self.wall_dist > 0 then
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
         pix(self.pos_x * 8, self.pos_y * 8, color)
         return false
      end

      table.insert(g_hitmarks, Hitmark.new(self.pos_x, self.pos_y, 0))

      if not self.can_bounce then
         return true
      end

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
-- Player ------------------------------
----------------------------------------

Player = {
   pos_x = 3,
   pos_y = 3,
   angle = 0,
   ping_cooldown = 0,
   ping_passive_cooldown = 0,
   ping_spread = 1,
   ping_range = 10,
   weapon = nil,
   move_abs = Entity.move_abs,
   move_rel = Entity.move_rel,
   health = 5,
   speed = .005,
   ping_cooldown_max = 800,
   can_bounce = false,
}
Player.__index = Player

function Player.new()
   local self = setmetatable({}, Player)
   self.weapon = Weapon.new(0, 1, 1, 0, 0, 600, 20, -1, 1)
   return self
end

function Player:ping()
   local projs = g_projs
   self.ping_cooldown = self.ping_cooldown_max
   local table_insert = table.insert
   local ping_spread_half = self.ping_spread * .5
   for theta = -ping_spread_half, ping_spread_half, .003 do
      table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, self.ping_range, self.can_bounce, 0))
   end
end

function Player:process(delta)
   self.ping_cooldown = math.max(self.ping_cooldown - delta, 0)
   self.ping_passive_cooldown = self.ping_passive_cooldown - delta

   if self.ping_passive_cooldown < 0 then
      self.ping_passive_cooldown = self.ping_cooldown_max
      local table_insert = table.insert
      local projs = g_projs
      for theta = 0, 6.28, .1 do
         table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 1.5, self.can_bounce, 0))
      end
   end

   local mouse_x, mouse_y, mouse_left, mouse_mid, mouse_right = mouse()

   local pos_x_rel = mouse_x - 8 * self.pos_x
   local pos_y_rel = mouse_y - 8 * self.pos_y
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
      self:move_abs(mov_side * mov_scl, mov_front * mov_scl)
   end

   if mouse_right and self.ping_cooldown == 0 then
      self:ping()
   end

   if self.weapon then
      self.weapon:process(delta)
      if mouse_left then
         self.weapon:fire(self.pos_x, self.pos_y, self.angle)
      end
   end

   local tile_data = mget(self.pos_x, self.pos_y)
   if tile_data == 2 then
      g_item_pickup(self.pos_x, self.pos_y)
   end

   g_draw_sprite(self.pos_x, self.pos_y, self.angle, 5)
end

function Player:damage(dmg)
   self.health = self.health - dmg
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

function init()
   g_player = Player.new()
   g_projs = {}
   g_hitmarks = {}
   g_enemies = {}
   g_state = 1
   g_items = {}
   g_t = time()
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

   -- map(0, 0)
   g_ui_render()

   -- process
   player:process(delta)

   for k, v in pairs(projs) do
      if v:process(delta) then
         projs[k] = nil
      end
   end

   for k, v in pairs(hitmarks) do
      if v:process(delta) then
         hitmarks[k] = nil
      end
   end

   for k, v in pairs(enemies) do
      v:process(delta)
   end
end

function process_item_pickup(delta)
   cls()

   map(210, 0, 18, 15, 28, 8)
   print("SKIP", 88, 106, 2, true)
   local t = g_t
   local color_start = t // 70
   local offset_y = t / 100
   local math_sin = math.sin
   for k, v in ipairs(gc_upgrade_text_tab) do
      print(v, 73 + 6 * k, 10 + math_sin(offset_y + k * .7), color_start + k, true)
   end

   local items = g_items
   items[1]:render(52, 32)
   items[2]:render(116, 32)

   g_ui_render()

   local mouse_x, mouse_y, mouse_left = mouse()
   if mouse_left and g_item_pickup_mouse_rel then
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
   else
      g_item_pickup_mouse_rel = true
   end
end
gc_upgrade_text_tab = {
   "U",
   "P",
   "G",
   "R",
   "A",
   "D",
   "E",
}

function TIC()
   local t = time()
   g_t = t
   local delta = t - g_prev_time
   g_prev_time = t

   -- Hide mouse
   poke(0x3FFB, 0)

   local state = g_state
   if state == 1 then
      process_game(delta)
   else -- state == 2
      process_item_pickup(delta)
   end

   -- Custom mouse
   local mouse_x, mouse_y = mouse()
   spr(257, mouse_x - 4, mouse_y - 4, 0)

   print(string.format("FPS %d", math.floor(1000 / delta)), 0, 0, 5)
end

-- <TILES>
-- 001:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
-- 002:0ff00ff00cce0ccefccefccefccefccefddefdde0eef0eef0ff00ff000000000
-- 003:0eeeef00fcccdef0fcccdef000fff0000eeeef00fcccdef0fcccdef000fff000
-- 004:0ffffff00ccccdfffccccddffcccdddffddddeef0feeeeff0ffffff000000000
-- 005:fcccddf0fcccddf0fcccddeffcccddeffccdddeffddddeefffddeeff0ffffff0
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
-- 000:101010101010101010101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b06020204060c0c0c0c0c0c04060202040a0000000000000000000000000
-- 001:100000000010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000070000000000000000000000000
-- 002:1000000000000030200010000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000b060202040a00000b060202040a00030000000000000000000000000
-- 003:100000000010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 004:101010101010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 005:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300030000000003000003000000000300030000000000000000000000000
-- 006:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 007:1000000000000000000010000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000e0c0c0c0c0d00000e0c0c0c0c0d00030000000000000000000000000
-- 008:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300070000000007000007000000000700030000000000000000000000000
-- 009:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300050000000005000005000000000500030000000000000000000000000
-- 010:100000001010100010101010101010100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300090602020408000009060202040800030000000000000000000000000
-- 011:100000001000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000030000000000000000000000000
-- 012:10000000100000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000060c0c0c0c040000000000030000000000000000000000000
-- 013:101010101000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000050000000000000000000000000
-- 014:100000000000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000906020202020202020202020202020204080000000000000000000000000
-- 015:100000001000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:101010101010101010101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
