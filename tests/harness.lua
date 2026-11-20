-- Minimal Factorio runtime stubs to exercise the mod's logic outside the game.
-- the mod sources live in ../factory-modeller relative to this file
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
package.path = here .. "../factory-modeller/?.lua;" .. package.path

local function proto(t) t.localised_name = t.localised_name or { "n." .. t.name } t.hidden = false return t end

local entity_protos = {
  ["assembling-machine-1"] = proto({ name = "assembling-machine-1", type = "assembling-machine", crafting_categories = { crafting = true, ["crafting-with-fluid"] = false }, energy_usage = 75000 / 60, cs = 0.5, electric_energy_source_prototype = {} }),
  ["assembling-machine-2"] = proto({ name = "assembling-machine-2", type = "assembling-machine", crafting_categories = { crafting = true }, energy_usage = 150000 / 60, cs = 0.75, electric_energy_source_prototype = {} }),
  ["stone-furnace"] = proto({ name = "stone-furnace", type = "furnace", crafting_categories = { smelting = true }, energy_usage = 90000 / 60, cs = 1, burner_prototype = { effectivity = 1, fuel_categories = { chemical = true } } }),
  ["electric-furnace"] = proto({ name = "electric-furnace", type = "furnace", crafting_categories = { smelting = true }, energy_usage = 180000 / 60, cs = 1, electric_energy_source_prototype = {} }),
  ["electric-mining-drill"] = proto({ name = "electric-mining-drill", type = "mining-drill", resource_categories = { ["basic-solid"] = true }, mining_speed = 0.5, energy_usage = 90000 / 60 }),
  ["steam-engine"] = proto({ name = "steam-engine", type = "generator", fluidbox_prototypes = { { production_type = "input", filter = { name = "steam" } } } }),
  ["boiler"] = proto({ name = "boiler", type = "boiler", target_temperature = 165, fluidbox_prototypes = { { production_type = "input-output", filter = { name = "water", default_temperature = 15 } }, { production_type = "output", filter = { name = "steam", heat_capacity = 200 } } }, burner_prototype = { effectivity = 1, fuel_categories = { chemical = true } } }),
  ["solar-panel"] = proto({ name = "solar-panel", type = "solar-panel" }),
  ["small-electric-pole"] = proto({ name = "small-electric-pole", type = "electric-pole" }),
  ["transport-belt"] = proto({ name = "transport-belt", type = "transport-belt", belt_speed = 0.03125 }),
  ["fast-transport-belt"] = proto({ name = "fast-transport-belt", type = "transport-belt", belt_speed = 0.0625 }),
  ["splitter"] = proto({ name = "splitter", type = "splitter" }),
  ["inserter"] = proto({ name = "inserter", type = "inserter", rot = 0.014 }),
  ["fast-inserter"] = proto({ name = "fast-inserter", type = "inserter", rot = 0.04 }),
  ["character"] = proto({ name = "character", type = "character", crafting_categories = { crafting = true }, cs = 1 }),
  ["iron-ore"] = proto({ name = "iron-ore", type = "resource", resource_category = "basic-solid", mineable_properties = { minable = true, mining_time = 1, products = { { type = "item", name = "iron-ore", amount = 1, independent_probability = 1 } } } }),
}
entity_protos["steam-engine"].get_fluid_usage_per_tick = function() return 0.5 end
entity_protos["steam-engine"].get_max_power_output = function() return 15000 end
entity_protos["boiler"].get_max_energy_usage = function() return 30000 end
entity_protos["solar-panel"].get_max_energy_production = function() return 1000 end
for _, e in pairs(entity_protos) do
  local cs = e.cs
  e.get_crafting_speed = function() return cs end
  local rot = e.rot
  e.get_inserter_rotation_speed = function() return rot end
end

local recipes = {
  ["gear-user"] = proto({ name = "gear-user", categories = { "crafting" }, energy = 1, ingredients = { { type = "item", name = "iron-gear-wheel", amount = 2 } }, products = { { type = "item", name = "iron-plate", amount = 1, independent_probability = 1 } } }),
  ["iron-plate"] = proto({ name = "iron-plate", categories = { "smelting" }, energy = 3.2, ingredients = { { type = "item", name = "iron-ore", amount = 1 } }, products = { { type = "item", name = "iron-plate", amount = 1, independent_probability = 1, shared_probability = { min = 0, max = 1 } } } }),
  ["iron-gear-wheel"] = proto({ name = "iron-gear-wheel", categories = { "crafting" }, energy = 0.5, ingredients = { { type = "item", name = "iron-plate", amount = 2 } }, products = { { type = "item", name = "iron-gear-wheel", amount = 1, independent_probability = 1 } } }),
}
for _, r in pairs(recipes) do r.main_product = r.products[1] end

prototypes = {
  entity = entity_protos,
  recipe = recipes,
  item = { coal = proto({ name = "coal", fuel_value = 4e6, fuel_categories = { "chemical" } }), wood = proto({ name = "wood", fuel_value = 2e6, fuel_categories = { "chemical" } }), ["iron-ore"] = proto({ name = "iron-ore" }), ["iron-plate"] = proto({ name = "iron-plate" }), ["iron-gear-wheel"] = proto({ name = "iron-gear-wheel" }) },
  fluid = { water = proto({ name = "water", default_temperature = 15, heat_capacity = 200 }), steam = proto({ name = "steam", default_temperature = 15, heat_capacity = 200 }) },
  recipe_category = { crafting = { localised_name = "Crafting" }, smelting = { localised_name = "Smelting" } },
  resource_category = { ["basic-solid"] = { localised_name = "Basic solid" } },
  get_entity_filtered = function(filters)
    local out = {}
    for n, e in pairs(entity_protos) do
      for _, f in pairs(filters) do
        if f.filter == "type" and e.type == f.type then out[n] = e end
        if f.filter == "crafting-category" and e.crafting_categories and e.crafting_categories[f.crafting_category] then out[n] = e end
      end
    end
    return out
  end,
}

storage = {}
helpers = { is_valid_sprite_path = function(p) return true end }
settings = {
  global = { ["fm-rate-unit"] = { value = "minute" }, ["fm-text-scale"] = { value = 1 } },
  get_player_settings = function() return { ["fm-camera-ui-scale"] = { value = true }, ["fm-min-zoom"] = { value = 0.3 }, ["fm-show-top-button"] = { value = true } } end,
}

local robj_id = 0
local robjs = {}
local function mkobj()
  robj_id = robj_id + 1
  local o = { id = robj_id, valid = true }
  o.destroy = function() o.valid = false robjs[o.id] = nil end
  robjs[o.id] = o
  return o
end
local function check_target(t)
  assert(type(t) == "table" and type(t.x) == "number" and type(t.y) == "number", "bad target")
end
rendering = {
  draw_rectangle = function(p) check_target(p.left_top) check_target(p.right_bottom) assert(p.color and p.surface) return mkobj() end,
  draw_text = function(p) check_target(p.target) assert(p.text ~= nil and p.color) return mkobj() end,
  draw_line = function(p) check_target(p.from) check_target(p.to) assert(p.width) return mkobj() end,
  draw_circle = function(p) check_target(p.target) assert(p.radius) return mkobj() end,
  draw_polygon = function(p) assert(#p.vertices == 3) for _, v in pairs(p.vertices) do check_target(v) end return mkobj() end,
  draw_sprite = function(p) check_target(p.target) assert(type(p.sprite) == "string") return mkobj() end,
  get_object_by_id = function(id) return robjs[id] end,
  clear = function() robjs = {} end,
  count = function() local c = 0 for _ in pairs(robjs) do c = c + 1 end return c end,
}

local surface = { index = 2, name = "fm-canvas", request_to_generate_chunks = function() end }
game = {
  tick = 0, ticks_played = 0, tick_paused = false,
  surfaces = {},
  forces = { player = { name = "player", set_surface_hidden = function() end, mining_drill_productivity_bonus = 0 } },
  create_surface = function(name) game.surfaces[name] = surface return surface end,
  players = {},
  connected_players = {},
  get_player = function(i) return game.players[i] end,
}

-- permissive GUI mock
local Gui = {}
local function new_el(spec, parent)
  local el = { children = {}, style = {}, valid = true, tags = {}, parent = parent }
  for k, v in pairs(spec or {}) do if k ~= "style" then el[k] = v end end
  el.tags = spec and spec.tags or {}
  if el.type == "camera" then el._pos = { x = el.position[1] or el.position.x, y = el.position[2] or el.position.y } el.position = nil end
  return setmetatable(el, Gui)
end
Gui.__index = function(t, k)
  if rawget(t, "valid") == false then error("LuaGuiElement API call when LuaGuiElement was invalid.") end
  if k == "position" then return rawget(t, "_pos") end
  if k == "location" then return rawget(t, "_loc") end
  local m = rawget(Gui, k)
  if m and type(m) == "function" then return function(...) local args = { ... } if args[1] == t then return m(...) end return m(t, ...) end end
  for _, c in pairs(rawget(t, "children")) do
    if c.name == k then return c end
  end
  return nil
end
Gui.__newindex = function(t, k, v)
  if k == "location" and type(v) == "table" then rawset(t, "_loc", { x = v.x or v[1], y = v.y or v[2] }) return end
  if k == "position" and type(v) == "table" then rawset(t, "_pos", { x = v.x or v[1], y = v.y or v[2] }) return end
  rawset(t, k, v)
end
function Gui.add(self, spec)
  assert(spec.type, "no type")
  if spec.name then assert(self[spec.name] == nil, "duplicate child " .. spec.name) end
  local el = new_el(spec, self)
  table.insert(rawget(self, "children"), el)
  return el
end
function Gui.destroy(self)
  self.valid = false
  local p = rawget(self, "parent")
  if p then
    for i, c in pairs(rawget(p, "children")) do if c == self then table.remove(rawget(p, "children"), i) break end end
  end
end
function Gui.clear(self) rawset(self, "children", {}) end
function Gui.bring_to_front() end
function Gui.focus() end
function Gui.force_auto_center() end

function make_player(index)
  local p = {
    index = index, valid = true, display_resolution = { width = 1920, height = 1080 }, display_scale = 1,
    gui = { screen = new_el({ type = "empty-widget" }), top = new_el({ type = "flow" }) },
    force = { inserter_stack_size_bonus = 0, bulk_inserter_capacity_bonus = 0 },
    set_shortcut_toggled = function() end,
    controller_type = 1, position = { x = 0, y = 0 }, surface = { name = "nauvis" }, print = function() end,
  }
  p.set_controller = function(prm) p.controller_type = prm.type end
  p.exit_remote_view = function() p.controller_type = 1 end
  game.players[index] = p
  table.insert(game.connected_players, p)
  return p
end

defines = {
  controllers = { character = 1, remote = 2, god = 3 },
  mouse_button_type = { none = 0, left = 1, right = 2, middle = 3 },
  events = setmetatable({}, { __index = function(t, k) return k end }),
}

-- capture event handlers
handlers = {}
script = {
  on_init = function(f) handlers.init = f end,
  on_configuration_changed = function(f) handlers.config = f end,
  on_nth_tick = function(n, f) handlers.nth = f end,
  on_event = function(ev, f)
    if type(ev) == "table" then for _, e in pairs(ev) do handlers[e] = f end else handlers[ev] = f end
  end,
}

package.preload["mod-gui"] = function()
  local m = { button_style = "mod_gui_button" }
  function m.get_button_flow(player)
    local top = player.gui.top
    local f = top.mod_gui_top_frame or top.add({ type = "frame", name = "mod_gui_top_frame" })
    return f.mod_gui_inner_frame or f.add({ type = "frame", name = "mod_gui_inner_frame" })
  end
  return m
end

function table_size(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
commands = { add_command = function(name, help, f) handlers["cmd_" .. name] = f end }
