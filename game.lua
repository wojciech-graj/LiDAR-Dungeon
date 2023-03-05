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

function g_item_pickup(pos_x, pos_y)
   mset(pos_x, pos_y, 0)
   g_state = 1
end

----------------------------------------
-- Item --------------------------------
----------------------------------------

--- type_idx:
-- 1: speed
-- 2: ping spread
-- 3: ping range
-- 4: ping bounce

Item = {
   type_idx = 0,
}
Item.__index = Item

function Item.new()
   self.type_idx = math.random(4)
end

----------------------------------------
-- Entity ------------------------------
----------------------------------------

--- Move an entity
-- @param dist_front number
-- @param dist_side number
function Entity_move(self, dist_front, dist_side)
   local dir_x_self = math.cos(self.angle)
   local dir_y_self = math.sin(self.angle)
   local dir_x = dist_front * dir_x_self + dist_side * dir_y_self
   local dir_y = dist_front * dir_y_self - dist_side * dir_x_self
   local isect = g_ray_isect(self.pos_x, self.pos_y, dir_x, dir_y)
   if isect.dist > 0.4 then
      local dist_min = math.min(math.sqrt(dist_front * dist_front + dist_side * dist_side), math.max(0, isect.dist - 0.4))
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
      self:move(self.speed, 0)
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

function Player:process(delta)
   self.ping_cooldown = math.max(self.ping_cooldown - delta, 0)
   self.ping_passive_cooldown = self.ping_passive_cooldown - delta

   if self.ping_passive_cooldown < 0 then
      self.ping_passive_cooldown = 800
      local table_insert = table.insert
      local projs = g_projs
      for theta = 0, 6.28, .1 do
         table_insert(projs, Proj.new(self.pos_x, self.pos_y, self.angle + theta, .01, 1.5, false, 0))
      end
   end

   local mouse_x, mouse_y, mouse_left, mouse_mid, mouse_right = mouse()

   local pos_x_rel = mouse_x - 8 * self.pos_x
   local pos_y_rel = mouse_y - 8 * self.pos_y
   self.angle = math.atan2(pos_y_rel, pos_x_rel)

   local mov_front = 0
   if btn(0) then
      mov_front = 1
   elseif btn(1) then
      mov_front = -1
   end

   local mov_side = 0
   if btn(2) then
      mov_side = 1
   elseif btn(3) then
      mov_side = -1
   end

   if mov_front ~= 0 or mov_side ~= 0 then
      local mov_scl = delta * .02 / math.sqrt(mov_front * mov_front + mov_side * mov_side)
      self:move(mov_front * mov_scl, mov_side * mov_scl)
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

----------------------------------------
-- main --------------------------------
----------------------------------------

--- g_state:
-- 0: game
-- 1: item pickup

function init()
   g_player = Player.new()
   g_projs = {}
   g_hitmarks = {}
   g_enemies = {}
   g_state = 0
   g_items = {}
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
end

function process_item_pickup(delta)

end

function TIC()
   local t = time()
   local delta = t - g_prev_time
   g_prev_time = t

   -- Hide mouse
   poke(0x3FFB, 0)

   local state = g_state
   if state == 0 then
      process_game(delta)
   else -- state == 1
      process_item_pickup(delta)
   end

   -- Custom mouse
   local mouse_x, mouse_y = mouse()
   spr(257, mouse_x - 4, mouse_y - 4, 0)

   print(string.format("FPS %d", math.floor(1000 / delta)), 0, 0, 5)
end

-- <TILES>
-- 001:1111111111111111111111111111111111111111111111111111111111111111
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
-- 026:000000000000000000000000c0000000655c000076666550c77766666557fff6
-- 027:000000000000000000000000000000000000000000000000000000aa66600ba0
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
-- 043:ff666baaff766cbaff777ba0f666cbaa7776baaa667bbaa0766caa00770bbbaa
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
-- </TILES>

-- <SPRITES>
-- 001:0000000000cccc000cc00cc00c0000c00c0000c00cc00cc000cccc0000000000
-- </SPRITES>

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

