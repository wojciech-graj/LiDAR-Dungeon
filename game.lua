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
-- FUNCTION Class:process(delta): executed every frame. May return boolean,
-- where true signifies that object should be deleted

--- Interfaces
-- Entity: pos_x, pos_y, angle, health, move, damage

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
function g_explode(pos_x, pos_y)
   local table_insert = table.insert
   local projs = g_projs
   local math_cos = math.cos
   local math_sin = math.sin
   for theta = 0, 6.28, 0.55 do
      table_insert(projs, Proj.new(pos_x, pos_y, theta, .005, .5, false, 3))
   end
end

----------------------------------------
-- Entity ------------------------------
----------------------------------------

--- Move an entity
-- @param dist number
-- @param dir int: either 1 or -1 for forwards or backwards respectively
function Entity_move(self, dist, dir)
   local dir_x = dir * math.cos(self.angle)
   local dir_y = dir * math.sin(self.angle)
   local isect = g_ray_isect(self.pos_x, self.pos_y, dir_x, dir_y)
   if isect.dist > 0.4 then
      local dist_min = math.min(dist, math.max(0, isect.dist - 0.4))
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

--- target:
-- 0: player
-- 1: enemy

Weapon = {
   proj_type = 0,
   target = 0,
   proj_cnt = 0,
   spread = 0,
   accuracy = 0,
   cooldown = 0,
   cooldown_max = 0,
   range = 0,
   ammo = 0,
}
Weapon.__index = Weapon

g_damage_type_idx = {
   [1] = 1,
   [2] = 1,
}

function Weapon.new(proj_type, target, proj_cnt, spread, accuracy, cooldown, range, ammo)
   local self = setmetatable({}, Weapon)
   self.proj_type = proj_type
   self.target = target
   self.proj_cnt = proj_cnt
   self.spread = spread
   self.accuracy = accuracy
   self.cooldown_max = cooldown
   self.range = range
   self.ammo = ammo
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
         table_insert(projs, Proj.new(pos_x, pos_y, angle - self.spread + dangle * i + (2 * math.random() - 1) * self.accuracy, .01, 5, false, self.target + 1))
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
   move = Entity_move,
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
      self:move(self.speed, 1)
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
}
Proj.__index = Proj

function Proj.new(pos_x, pos_y, angle, vel, dist_max, can_bounce, type_idx)
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
            player:damage(g_damage_type_idx[self.type_idx])
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
               v:damage(g_damage_type_idx[self.type_idx])
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
               Weapon.new(0, 0, 2, .2, .4, 1300, 7, -1)))
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
   weapon = nil,
   move = Entity_move,
   health = 5,
}
Player.__index = Player

function Player.new()
   local self = setmetatable({}, Player)
   self.weapon = Weapon.new(0, 1, 1, 0, 0, 600, 20, -1)
   return self
end

function Player:ping()
   local projs = g_projs
   self.ping_cooldown = 1000
   local table_insert = table.insert
   for theta = -.5, .5, .003 do
      table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 10, false, 0))
   end
end

function Player:rotate(theta)
   self.angle = self.angle + theta
end

function Player:process(delta)
   self.ping_cooldown = math.max(self.ping_cooldown - delta, 0)
   self.ping_passive_cooldown = self.ping_passive_cooldown - delta

   if self.weapon then
      self.weapon:process(delta)
      if btn(5) then
         self.weapon:fire(self.pos_x, self.pos_y, self.angle)
      end
   end

   if self.ping_passive_cooldown < 0 then
      self.ping_passive_cooldown = 800
      local table_insert = table.insert
      local projs = g_projs
      for theta = 0, 6.28, .1 do
         table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 1.5, false, 0))
      end
   end

   if btn(0) then
      self:move(0.01 * delta, 1)
   elseif btn(1) then
      self:move(0.01 * delta, -1)
   end

   if btn(2) then
      self:rotate(-0.005 * delta)
   elseif btn(3) then
      self:rotate(0.005 * delta)
   end

   if btn(4) and self.ping_cooldown == 0 then
      self:ping()
   end

   g_draw_sprite(self.pos_x, self.pos_y, self.angle, 5)
end

function Player:damage(dmg)
   self.health = self.health - dmg
end

----------------------------------------
-- main --------------------------------
----------------------------------------

function init()
   g_player = Player.new()
   g_projs = {}
   g_hitmarks = {}
   g_enemies = {}
end

function BOOT()
   init()
   g_prev_time = time()
end

function TIC()
   local t = time()
   local delta = t - g_prev_time
   g_prev_time = t

   cls()

   local player = g_player
   local projs = g_projs
   local hitmarks = g_hitmarks
   local enemies = g_enemies

   -- map(0, 0)
   map(30, 0, 4, 17, 208, 0)

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

   print(string.format("FPS %d", math.floor(1000 / delta)), 0, 0, 5)
end

-- <TILES>
-- 001:1111111111111111111111111111111111111111111111111111111111111111
-- 002:0004400004400440040000404000000440000004040000400440044000044000
-- 003:0000000000000000000000000002200000022000000000000000000000000000
-- </TILES>

-- <MAP>
-- 000:101010101010101010101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:100000000010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:100000000000003020001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:100000000010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:101010101010000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:100000000000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:100000001000000000001000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:100000001010100010101010101010100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:100000001000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:100000001000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:101010101000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:100000000000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:100000001000000000000000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:101010101010101010101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
