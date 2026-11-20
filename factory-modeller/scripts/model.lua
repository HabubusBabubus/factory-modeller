-- Data model: projects, nodes, links and prototype helpers.
local M = {}

-------------------------------------------------------------------------------
-- Item keys: "item/iron-plate", "fluid/water"
-------------------------------------------------------------------------------
function M.split_key(key)
  if not key then return nil, nil end
  local t, n = key:match("^(%a+)/(.+)$")
  return t, n
end

function M.key_valid(key)
  local t, n = M.split_key(key)
  if t == "item" then return prototypes.item[n] ~= nil end
  if t == "fluid" then return prototypes.fluid[n] ~= nil end
  return false
end

function M.rich(key)
  local t, n = M.split_key(key)
  if not t or not M.key_valid(key) then return "[virtual-signal=signal-unknown]" end
  return "[" .. t .. "=" .. n .. "]"
end

function M.key_name(key)
  local t, n = M.split_key(key)
  if t == "item" and prototypes.item[n] then return prototypes.item[n].localised_name end
  if t == "fluid" and prototypes.fluid[n] then return prototypes.fluid[n].localised_name end
  return key or "?"
end

-------------------------------------------------------------------------------
-- Recipe definitions (cached per session; prototypes never change at runtime)
-------------------------------------------------------------------------------
local def_cache = {}
local machine_cache = {}
local producers_index, consumers_index

local function product_amount(p)
  local base = p.amount
  if not base then base = ((p.amount_min or 0) + (p.amount_max or 0)) / 2 end
  local prob = p.independent_probability or p.probability or 1
  local sp = p.shared_probability
  if sp and sp.max and sp.min then
    local span = sp.max - sp.min
    if span > 0 then prob = prob * span end
  end
  local amount = base * prob + (p.extra_count_fraction or 0)
  local ignored = math.min(p.ignored_by_productivity or 0, amount)
  return amount, ignored
end

local function add_entry(list, key, amount, ignored)
  for _, e in pairs(list) do
    if e.key == key then
      e.amount = e.amount + amount
      e.ignored = (e.ignored or 0) + (ignored or 0)
      return
    end
  end
  list[#list + 1] = { key = key, amount = amount, ignored = ignored or 0 }
end

function M.get_def(recipe_name)
  if not recipe_name then return nil end
  local cached = def_cache[recipe_name]
  if cached ~= nil then return cached or nil end
  local def
  local res = recipe_name:match("^mine:(.+)$")
  if res then
    local ent = prototypes.entity[res]
    if ent and ent.type == "resource" and ent.mineable_properties and ent.mineable_properties.minable then
      local mp = ent.mineable_properties
      def = {
        name = recipe_name, kind = "mining", resource = res,
        energy = mp.mining_time or 1,
        categories = { ent.resource_category or "basic-solid" },
        ingredients = {}, products = {},
        sprite = "entity/" .. res,
        localised_name = ent.localised_name,
      }
      if mp.required_fluid and prototypes.fluid[mp.required_fluid] then
        add_entry(def.ingredients, "fluid/" .. mp.required_fluid, (mp.fluid_amount or 0) / 10)
      end
      for _, p in pairs(mp.products or {}) do
        local a, ig = product_amount(p)
        add_entry(def.products, p.type .. "/" .. p.name, a, ig)
      end
    end
  else
    local r = prototypes.recipe[recipe_name]
    if r then
      local cats = r.categories
      if not cats then cats = { r.category } end
      def = {
        name = recipe_name, kind = "recipe",
        energy = r.energy > 0 and r.energy or 0.01,
        categories = cats,
        ingredients = {}, products = {},
        sprite = "recipe/" .. recipe_name,
        localised_name = r.localised_name,
      }
      for _, ing in pairs(r.ingredients) do
        add_entry(def.ingredients, ing.type .. "/" .. ing.name, ing.amount)
      end
      for _, p in pairs(r.products) do
        local a, ig = product_amount(p)
        add_entry(def.products, p.type .. "/" .. p.name, a, ig)
      end
      if r.main_product then
        def.main = r.main_product.type .. "/" .. r.main_product.name
      end
    end
  end
  if def and not def.main and def.products[1] then def.main = def.products[1].key end
  def_cache[recipe_name] = def or false
  return def
end

-- Machines for one category. kind = "recipe" (crafting category) or "mining" (resource category).
local cat_cache = {}
function M.machines_for(cat, kind)
  local ck = kind .. ":" .. cat
  if cat_cache[ck] then return cat_cache[ck] end
  local list = {}
  local found
  if kind == "mining" then
    found = prototypes.get_entity_filtered({ { filter = "type", type = "mining-drill" } })
  else
    found = prototypes.get_entity_filtered({ { filter = "crafting-category", crafting_category = cat } })
  end
  for name, proto in pairs(found) do
    if proto.type ~= "character" and not proto.hidden then
      local speed
      if kind == "mining" then
        if proto.resource_categories and proto.resource_categories[cat] then speed = proto.mining_speed end
      else
        speed = proto.get_crafting_speed()
      end
      if speed and speed > 0 then
        local m = { name = name, speed = speed, power = (proto.energy_usage or 0) * 60 }
        local bp = proto.burner_prototype
        if bp then
          local cats = {}
          for c, _ in pairs(bp.fuel_categories or {}) do cats[c] = true end
          m.burner = { effectivity = bp.effectivity or 1, categories = cats }
        elseif proto.electric_energy_source_prototype then
          m.electric = true
        end
        list[#list + 1] = m
      end
    end
  end
  table.sort(list, function(a, b)
    if a.speed ~= b.speed then return a.speed < b.speed end
    return a.name < b.name
  end)
  cat_cache[ck] = list
  return list
end

-- Machines able to run a definition, sorted by speed (slowest first).
function M.get_machines(def)
  if not def then return {} end
  local ck = def.name
  if machine_cache[ck] then return machine_cache[ck] end
  local list, seen = {}, {}
  for _, cat in pairs(def.categories) do
    for _, m in pairs(M.machines_for(cat, def.kind == "mining" and "mining" or "recipe")) do
      if not seen[m.name] then
        seen[m.name] = true
        list[#list + 1] = m
      end
    end
  end
  table.sort(list, function(a, b)
    if a.speed ~= b.speed then return a.speed < b.speed end
    return a.name < b.name
  end)
  machine_cache[ck] = list
  return list
end

function M.get_machine(def, name)
  for _, m in pairs(M.get_machines(def)) do
    if m.name == name then return m end
  end
  return nil
end

-- mining productivity from research (player force), as a fraction (0.2 = +20%)
function M.mining_research_bonus()
  if M.settings().use_research == false then return 0 end
  local f = game and game.forces and game.forces["player"]
  return (f and f.mining_drill_productivity_bonus) or 0
end

function M.settings()
  storage.fm_settings = storage.fm_settings or { unit = "minute", machines = {} }
  storage.fm_settings.machines = storage.fm_settings.machines or {}
  return storage.fm_settings
end

function M.category_key(cat, kind) return (kind == "mining" and "mining:" or "") .. cat end

function M.default_machine(def)
  local list = M.get_machines(def)
  if #list == 0 then return nil end
  local st = M.settings()
  for _, cat in pairs(def.categories) do
    local d = st.machines[M.category_key(cat, def.kind)]
    if d and M.get_machine(def, d) then return d end
  end
  -- prefer the middle tier (e.g. assembling-machine-2) like most planners
  return list[math.min(#list, 2)].name
end

-- All categories that have at least one machine and one visible recipe/resource
function M.all_categories()
  local cats, seen = {}, {}
  for _, r in pairs(prototypes.recipe) do
    if not r.hidden and not r.parameter then
      for _, c in pairs(r.categories or { r.category }) do
        if not seen["r:" .. c] and #M.machines_for(c, "recipe") > 0 then
          seen["r:" .. c] = true
          cats[#cats + 1] = { cat = c, kind = "recipe" }
        end
      end
    end
  end
  for _, e in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "resource" } })) do
    local c = e.resource_category
    if c and not seen["m:" .. c] and e.mineable_properties and e.mineable_properties.minable and #M.machines_for(c, "mining") > 0 then
      seen["m:" .. c] = true
      cats[#cats + 1] = { cat = c, kind = "mining" }
    end
  end
  table.sort(cats, function(a, b)
    if a.kind ~= b.kind then return a.kind == "recipe" end
    return a.cat < b.cat
  end)
  return cats
end

-------------------------------------------------------------------------------
-- Fuel for burner machines
-------------------------------------------------------------------------------
local fuel_cache
local function item_fuel_categories(item)
  local cats = item.fuel_categories
  if cats then return cats end
  if item.fuel_category then return { item.fuel_category } end
  return {}
end

-- all fuel items: { name, value (J), categories = {cat = true} }, sorted by value
function M.get_fuels()
  if fuel_cache then return fuel_cache end
  fuel_cache = {}
  for name, it in pairs(prototypes.item) do
    if not it.hidden and (it.fuel_value or 0) > 0 then
      local cats = {}
      for _, c in pairs(item_fuel_categories(it)) do cats[c] = true end
      if next(cats) then fuel_cache[#fuel_cache + 1] = { name = name, value = it.fuel_value, categories = cats } end
    end
  end
  table.sort(fuel_cache, function(a, b) if a.value ~= b.value then return a.value < b.value end return a.name < b.name end)
  return fuel_cache
end

function M.fuels_for(burner)
  local list = {}
  for _, f in pairs(M.get_fuels()) do
    for c, _ in pairs(f.categories) do
      if burner.categories[c] then list[#list + 1] = f break end
    end
  end
  return list
end

function M.fuel(name)
  for _, f in pairs(M.get_fuels()) do if f.name == name then return f end end
  return nil
end

-- the fuel a burner machine uses: the node's own choice, the default from settings, coal, or the first that fits
function M.node_fuel(node, machine)
  if not machine or not machine.burner then return nil end
  local list = M.fuels_for(machine.burner)
  local function ok(name)
    for _, f in pairs(list) do if f.name == name then return f end end
  end
  return ok(node.fuel) or ok(M.settings().fuel) or ok("coal") or list[1]
end

-------------------------------------------------------------------------------
-- Power generation entities (steam engines/turbines, boilers, solar panels, offshore pumps)
-------------------------------------------------------------------------------
local gen_cache = {}
M.SOLAR_AVERAGE = 0.7 -- day/night average of a solar panel

local function fluid_filter(proto, wanted_type)
  for _, fb in pairs(proto.fluidbox_prototypes or {}) do
    local pt = fb.production_type
    if fb.filter and (pt == wanted_type or (wanted_type == "input" and pt == "input-output")) then return fb.filter end
  end
  return nil
end

function M.gen_info(name)
  if gen_cache[name] ~= nil then return gen_cache[name] or nil end
  local p = prototypes.entity[name]
  local info
  if p then
    if p.type == "generator" then
      local per_tick = p.get_fluid_usage_per_tick and p.get_fluid_usage_per_tick() or 0
      local f = fluid_filter(p, "input")
      info = { kind = "engine", power = (p.get_max_power_output and p.get_max_power_output() or 0) * 60, ins = {}, outs = {} }
      if f and per_tick > 0 then info.ins[1] = { key = "fluid/" .. f.name, per = per_tick * 60 } end
    elseif p.type == "boiler" then
      local inf = fluid_filter(p, "input") or prototypes.fluid["water"]
      local outf = fluid_filter(p, "output") or prototypes.fluid["steam"]
      local energy = (p.get_max_energy_usage and p.get_max_energy_usage() or 0) * 60
      local dt = (p.target_temperature or 165) - (inf and inf.default_temperature or 15)
      local hc = outf and outf.heat_capacity or 200
      local rate = (dt > 0 and hc > 0) and energy / (hc * dt) or 0
      info = { kind = "boiler", power = 0, energy = energy, ins = {}, outs = {} }
      if inf then info.ins[1] = { key = "fluid/" .. inf.name, per = rate } end
      if outf then info.outs[1] = { key = "fluid/" .. outf.name, per = rate } end
      local bp = p.burner_prototype
      if bp then
        local cats = {}
        for c, _ in pairs(bp.fuel_categories or {}) do cats[c] = true end
        info.burner = { effectivity = bp.effectivity or 1, categories = cats }
      end
    elseif p.type == "solar-panel" then
      info = { kind = "solar", power = (p.get_max_energy_production and p.get_max_energy_production() or 0) * 60 * M.SOLAR_AVERAGE, ins = {}, outs = {} }
    elseif p.type == "offshore-pump" then
      local rate = (p.get_pumping_speed and p.get_pumping_speed() or 0) * 60
      info = { kind = "pump", power = 0, ins = {}, outs = { { key = "fluid/water", per = rate } } }
    end
  end
  gen_cache[name] = info or false
  return info
end

-------------------------------------------------------------------------------
-- Belts and inserters
-------------------------------------------------------------------------------
local belt_cache, inserter_cache
function M.get_belts()
  if belt_cache then return belt_cache end
  belt_cache = {}
  for name, p in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "transport-belt" } })) do
    if not p.hidden and p.belt_speed and p.belt_speed > 0 then
      belt_cache[#belt_cache + 1] = { name = name, rate = p.belt_speed * 60 * 8 } -- items per second, both lanes
    end
  end
  table.sort(belt_cache, function(a, b) return a.rate < b.rate end)
  return belt_cache
end

function M.belt(name)
  for _, b in pairs(M.get_belts()) do if b.name == name then return b end end
  return nil
end

function M.default_belt()
  local st = M.settings()
  local b = st.belt and M.belt(st.belt)
  return b or M.get_belts()[1]
end

function M.get_inserters()
  if inserter_cache then return inserter_cache end
  inserter_cache = {}
  for name, p in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "inserter" } })) do
    local rot = p.get_inserter_rotation_speed and p.get_inserter_rotation_speed() or p.rotation_speed
    if not p.hidden and rot and rot > 0 then
      inserter_cache[#inserter_cache + 1] = { name = name, rot = rot, bonus = p.inserter_stack_size_bonus or 0, bulk = p.bulk or false }
    end
  end
  table.sort(inserter_cache, function(a, b) return a.rot < b.rot end)
  return inserter_cache
end

function M.default_inserter()
  local st = M.settings()
  for _, i in pairs(M.get_inserters()) do if i.name == st.inserter then return i end end
  local list = M.get_inserters()
  for _, i in pairs(list) do if i.name == "fast-inserter" then return i end end
  return list[1]
end

-- rough chest-to-chest throughput, items per second (one swing there and back = one full rotation)
function M.inserter_rate(ins, force)
  if not ins then return nil end
  local stack = 1 + (ins.bonus or 0)
  if force then
    if ins.bulk then stack = stack + (force.bulk_inserter_capacity_bonus or 0)
    else stack = stack + (force.inserter_stack_size_bonus or 0) end
  end
  return 60 * ins.rot * stack
end

local function build_indexes()
  producers_index, consumers_index = {}, {}
  local function push(idx, key, rname)
    idx[key] = idx[key] or {}
    table.insert(idx[key], rname)
  end
  for name, r in pairs(prototypes.recipe) do
    if not r.hidden and not r.parameter then
      for _, ing in pairs(r.ingredients) do push(consumers_index, ing.type .. "/" .. ing.name, name) end
      for _, p in pairs(r.products) do push(producers_index, p.type .. "/" .. p.name, name) end
    end
  end
  for name, e in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "resource" } })) do
    local mp = e.mineable_properties
    if mp and mp.minable and not e.hidden then
      for _, p in pairs(mp.products or {}) do push(producers_index, p.type .. "/" .. p.name, "mine:" .. name) end
      if mp.required_fluid then push(consumers_index, "fluid/" .. mp.required_fluid, "mine:" .. name) end
    end
  end
  for _, idx in pairs({ producers_index, consumers_index }) do
    for _, l in pairs(idx) do table.sort(l) end
  end
end

function M.recipes_producing(key)
  if not producers_index then build_indexes() end
  return producers_index[key] or {}
end

function M.recipes_consuming(key)
  if not consumers_index then build_indexes() end
  return consumers_index[key] or {}
end

-------------------------------------------------------------------------------
-- Storage / projects
-------------------------------------------------------------------------------
function M.init_storage()
  storage.projects = storage.projects or {}
  storage.next_project_id = storage.next_project_id or 1
  storage.next_region = storage.next_region or 1
  storage.players = storage.players or {}
  M.settings()
end

function M.new_region()
  local r = storage.next_region
  storage.next_region = r + 1
  return r
end

function M.region_offset(region)
  local col = region % 64
  local row = math.floor(region / 64)
  return { x = col * 2048, y = row * 2048 }
end

function M.create_project(name)
  local id = storage.next_project_id
  storage.next_project_id = id + 1
  local project = { id = id, name = name or ("Project " .. id), next_id = 1, nodes = {}, links = {}, results = nil, render = {} }
  local root = M.add_node(project, { type = "factory", name = project.name, x = 0, y = 0 })
  project.root = root.id
  storage.projects[id] = project
  return project
end

function M.delete_project(project)
  storage.projects[project.id] = nil
end

function M.add_node(project, fields)
  local id = project.next_id
  project.next_id = id + 1
  local node = fields
  node.id = id
  node.x = node.x or 0
  node.y = node.y or 0
  if node.type == "factory" then
    node.region = node.region or M.new_region()
    node.name = node.name or ("Factory " .. id)
  elseif node.type == "recipe" then
    node.speed = node.speed or 0
    node.prod = node.prod or 0
    if not node.machine then node.machine = M.default_machine(M.get_def(node.recipe)) end
    if node.fixed == nil then node.fixed = false end
    node.value = node.value or 1
  elseif node.type == "split" or node.type == "wout" or node.type == "win" then
    node.fixed = false
    node.value = 0
    if (node.type == "wout" or node.type == "win") and not node.channel then node.channel = 1 end
  elseif node.type == "gen" then
    node.fixed = true
    node.value = node.value or 1
  elseif node.type == "psplit" then
    node.fixed = false
    node.value = 0
    if not node.slots then
      node.slots = {}
      node.next_slot = 1
      for _ = 1, (node.count or 2) do
        node.slots[#node.slots + 1] = node.next_slot
        node.next_slot = node.next_slot + 1
      end
    end
    node.count = nil
  elseif node.type == "input" or node.type == "output" then
    if node.fixed == nil then node.fixed = (node.type == "output") end
    node.value = node.value or 1 -- items per second
  end
  project.nodes[id] = node
  return node
end

function M.add_link(project, from_node, from_port, to_node, to_port)
  for _, l in pairs(project.links) do
    if l.from.node == from_node and l.from.port == from_port and l.to.node == to_node and l.to.port == to_port then
      return nil
    end
  end
  local id = project.next_id
  project.next_id = id + 1
  local link = { id = id, from = { node = from_node, port = from_port }, to = { node = to_node, port = to_port } }
  project.links[id] = link
  return link
end

function M.children(project, factory_id)
  local list = {}
  for _, n in pairs(project.nodes) do
    if n.parent == factory_id then list[#list + 1] = n end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- Children shown on the canvas (automatic surplus outputs stay hidden)
function M.visible_children(project, factory_id)
  local list = {}
  for _, n in pairs(M.children(project, factory_id)) do
    if not n.auto then list[#list + 1] = n end
  end
  return list
end

function M.visible_links(project, factory_id)
  local list = {}
  for _, l in pairs(M.links_in(project, factory_id)) do
    local a, b = project.nodes[l.from.node], project.nodes[l.to.node]
    if a and b and not a.auto and not b.auto then list[#list + 1] = l end
  end
  return list
end

-- Links that are drawn inside a given factory
function M.links_in(project, factory_id)
  local list = {}
  for _, l in pairs(project.links) do
    local a = project.nodes[l.from.node]
    if a and a.parent == factory_id then list[#list + 1] = l end
  end
  return list
end

function M.is_ancestor(project, anc_id, node)
  local p = node.parent
  while p do
    if p == anc_id then return true end
    local pn = project.nodes[p]
    p = pn and pn.parent
  end
  return false
end

-- Path of factory ids from root to factory_id
function M.factory_path(project, factory_id)
  local path = {}
  local id = factory_id
  while id do
    table.insert(path, 1, id)
    local n = project.nodes[id]
    id = n and n.parent
  end
  return path
end

-------------------------------------------------------------------------------
-- Ports
-- returns ins, outs: lists of { key = port key, item = item key, per_x = rate per unit x (per second) }
-------------------------------------------------------------------------------
function M.recipe_rates(node)
  local def = M.get_def(node.recipe)
  if not def then return nil end
  local m = M.get_machine(def, node.machine)
  local speed = m and m.speed or 1
  local crafts = speed * (1 + (node.speed or 0) / 100) / def.energy -- crafts per second per machine
  return def, m, crafts
end

-- order of a factory's ports: explicit port_order first, then by position inside the factory
function M.port_less(a, b)
  local oa, ob = a.port_order or 1e9, b.port_order or 1e9
  if oa ~= ob then return oa < ob end
  if a.y ~= b.y then return a.y < b.y end
  return a.id < b.id
end

-- Move nodes by (dx, dy); anchors of links between two moved nodes move along
function M.move_nodes(project, ids, dx, dy)
  for id, _ in pairs(ids) do
    local n = project.nodes[id]
    if n then n.x, n.y = n.x + dx, n.y + dy end
  end
  for _, l in pairs(project.links) do
    if l.points and ids[l.from.node] and ids[l.to.node] then
      for _, p in pairs(l.points) do p.x, p.y = p.x + dx, p.y + dy end
    end
  end
end

-- Move an input/output port of a factory up (-1) or down (+1). Nothing inside the factory moves.
function M.move_port(project, factory_id, child_id, delta)
  local child = project.nodes[child_id]
  if not child or child.parent ~= factory_id then return false end
  local list = {}
  for _, c in pairs(M.children(project, factory_id)) do
    if c.type == child.type then list[#list + 1] = c end
  end
  table.sort(list, M.port_less)
  local idx
  for i, c in pairs(list) do
    c.port_order = i
    if c.id == child_id then idx = i end
  end
  local j = idx and idx + delta
  if not j or j < 1 or j > #list then return false end
  list[idx].port_order, list[j].port_order = j, idx
  return true
end

-------------------------------------------------------------------------------
-- Priority splitter outputs
-------------------------------------------------------------------------------
local function slot_linked(project, node, sid)
  local key = "s" .. sid
  for _, l in pairs(project.links) do
    if l.from.node == node.id and l.from.port == key then return true end
  end
  return false
end
M.slot_linked = slot_linked

-- Move an output of a priority splitter up (-1) or down (+1); links stay on the same output.
function M.move_slot(node, sid, delta)
  local idx
  for i, v in pairs(node.slots) do if v == sid then idx = i end end
  local j = idx and idx + delta
  if not j or j < 1 or j > #node.slots then return false end
  node.slots[idx], node.slots[j] = node.slots[j], node.slots[idx]
  return true
end

-- smallest number of outputs allowed: every linked output and the overflow output must stay
function M.min_slots(project, node)
  local need = 0
  for _, sid in pairs(node.slots) do
    if slot_linked(project, node, sid) or sid == node.overflow then need = need + 1 end
  end
  return math.max(1, need)
end

-- Change the number of outputs. Returns false (and changes nothing) if that would drop a used output.
-- Free outputs are removed starting from the lowest priority; new ones are added at the bottom.
function M.set_slot_count(project, node, n)
  n = math.floor(n)
  if n < M.min_slots(project, node) or n > 32 then return false end
  while #node.slots < n do
    node.slots[#node.slots + 1] = node.next_slot
    node.next_slot = node.next_slot + 1
  end
  local i = #node.slots
  while #node.slots > n and i >= 1 do
    local sid = node.slots[i]
    if not slot_linked(project, node, sid) and sid ~= node.overflow then table.remove(node.slots, i) end
    i = i - 1
  end
  return true
end

function M.node_ports(project, node)
  local ins, outs = {}, {}
  if node.type == "recipe" then
    local def, mach, crafts = M.recipe_rates(node)
    if def then
      local prod = 1 + (node.prod or 0) / 100
      if def.kind == "mining" then prod = prod + M.mining_research_bonus() end
      for _, e in pairs(def.ingredients) do
        ins[#ins + 1] = { key = e.key, item = e.key, per_x = crafts * e.amount }
      end
      -- burner machines eat fuel: power / (fuel value * efficiency) items per second per machine
      local f = M.node_fuel(node, mach)
      if f and mach.power > 0 then
        local per = mach.power / (f.value * (mach.burner.effectivity or 1))
        local key = "item/" .. f.name
        local merged = false
        for _, p in pairs(ins) do
          if p.key == key then p.per_x = p.per_x + per merged = true end
        end
        if not merged then ins[#ins + 1] = { key = key, item = key, per_x = per, fuel = true } end
      end
      for _, e in pairs(def.products) do
        local amount = e.ignored + (e.amount - e.ignored) * prod
        outs[#outs + 1] = { key = e.key, item = e.key, per_x = crafts * amount }
      end
    end
  elseif node.type == "gen" then
    local g = M.gen_info(node.entity)
    if g then
      for _, p in pairs(g.ins) do ins[#ins + 1] = { key = p.key, item = p.key, per_x = p.per } end
      for _, p in pairs(g.outs) do outs[#outs + 1] = { key = p.key, item = p.key, per_x = p.per } end
      if g.burner then
        local f = M.node_fuel(node, { burner = g.burner })
        if f and g.energy > 0 then
          ins[#ins + 1] = { key = "item/" .. f.name, item = "item/" .. f.name, per_x = g.energy / (f.value * (g.burner.effectivity or 1)), fuel = true }
        end
      end
    end
  elseif node.type == "wout" then
    -- wireless output: takes items in, sends them over its channel ("wl" is not drawn)
    ins[1] = { key = "in", item = node.item, per_x = 1 }
    outs[1] = { key = "wl", item = node.item, per_x = 1 }
  elseif node.type == "win" then
    -- wireless input: receives from the outputs on the same channel, gives items out
    ins[1] = { key = "wl", item = node.item, per_x = 1 }
    outs[1] = { key = "out", item = node.item, per_x = 1 }
  elseif node.type == "psplit" then
    ins[1] = { key = "in", item = node.item, per_x = 1 }
    for i, sid in pairs(node.slots or {}) do
      outs[#outs + 1] = { key = "s" .. sid, item = node.item, per_x = 1, slot = sid, prio = i }
    end
  elseif node.type == "input" or node.type == "output" or node.type == "split" then
    ins[1] = { key = "in", item = node.item, per_x = 1 }
    outs[1] = { key = "out", item = node.item, per_x = 1 }
  elseif node.type == "factory" then
    local kids = M.children(project, node.id)
    table.sort(kids, M.port_less)
    for _, c in pairs(kids) do
      if c.type == "input" then ins[#ins + 1] = { key = "i:" .. c.id, item = c.item, per_x = 1, child = c.id } end
      if c.type == "output" then outs[#outs + 1] = { key = "o:" .. c.id, item = c.item, per_x = 1, child = c.id } end
    end
  end
  return ins, outs
end

-- Ports that are drawn/clickable on the canvas
function M.visible_ports(project, node)
  local ins, outs = M.node_ports(project, node)
  if node.type == "input" then return {}, outs end
  if node.type == "output" then return ins, {} end
  if node.type == "wout" then return ins, {} end
  if node.type == "win" then return {}, outs end
  return ins, outs
end

-------------------------------------------------------------------------------
-- Wireless links: outputs and inputs with the same channel number inside one factory
-------------------------------------------------------------------------------
-- wireless blocks of a factory on a channel
function M.wireless_on(project, factory_id, channel, kind)
  local list = {}
  for _, n in pairs(project.nodes) do
    if n.parent == factory_id and n.type == kind and n.channel == channel then list[#list + 1] = n end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- smallest channel number not used by any wireless output of the factory
function M.free_channel(project, factory_id)
  local used = {}
  for _, n in pairs(project.nodes) do
    if n.parent == factory_id and n.type == "wout" and n.channel then used[n.channel] = true end
  end
  local c = 1
  while used[c] do c = c + 1 end
  return c
end

-- wireless inputs without an item take it from the outputs on their channel
function M.sync_wireless(project)
  for _, n in pairs(project.nodes) do
    if n.type == "win" and not n.item then
      for _, o in pairs(M.wireless_on(project, n.parent, n.channel, "wout")) do
        if o.item then n.item = o.item break end
      end
    end
  end
end

function M.find_port(project, node, key, dir)
  local ins, outs = M.node_ports(project, node)
  for _, p in pairs(dir == "in" and ins or outs) do
    if p.key == key then return p end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Deleting
-------------------------------------------------------------------------------
local function remove_links_of(project, node_id, port_prefix_owner)
  for id, l in pairs(project.links) do
    if l.from.node == node_id or l.to.node == node_id then project.links[id] = nil end
  end
  -- links in the parent factory that reference this node through the factory's port
  if port_prefix_owner then
    local fid, ikey, okey = port_prefix_owner, "i:" .. node_id, "o:" .. node_id
    for id, l in pairs(project.links) do
      if (l.from.node == fid and l.from.port == okey) or (l.to.node == fid and l.to.port == ikey) then
        project.links[id] = nil
      end
    end
  end
end

function M.delete_node(project, node)
  if node.id == project.root then return end
  if node.type == "factory" then
    for _, c in pairs(M.children(project, node.id)) do M.delete_node(project, c) end
  end
  remove_links_of(project, node.id, (node.type == "input" or node.type == "output") and node.parent or nil)
  project.nodes[node.id] = nil
end

-------------------------------------------------------------------------------
-- Copy (duplicate) a set of nodes in the same factory, with internal links
-------------------------------------------------------------------------------
function M.duplicate(project, nodes, dx, dy)
  local map = {}
  local function copy_node(n, parent, ox, oy)
    local c = {}
    for k, v in pairs(n) do
      if type(v) == "table" then
        local t = {}
        for kk, vv in pairs(v) do t[kk] = vv end
        v = t
      end
      c[k] = v
    end
    c.id = nil
    c.region = nil
    c.parent = parent
    c.x = n.x + ox
    c.y = n.y + oy
    local nn = M.add_node(project, c)
    map[n.id] = nn.id
    if n.type == "factory" then
      for _, ch in pairs(M.children(project, n.id)) do copy_node(ch, nn.id, 0, 0) end
    end
    return nn
  end
  local created = {}
  for _, n in pairs(nodes) do created[#created + 1] = copy_node(n, n.parent, dx, dy) end
  local function remap_port(port)
    local k, id = port:match("^([io]):(%d+)$")
    if k and map[tonumber(id)] then return k .. ":" .. map[tonumber(id)] end
    return port
  end
  local new_links = {}
  for _, l in pairs(project.links) do
    if map[l.from.node] and map[l.to.node] then new_links[#new_links + 1] = l end
  end
  for _, l in pairs(new_links) do
    M.add_link(project, map[l.from.node], remap_port(l.from.port), map[l.to.node], remap_port(l.to.port))
  end
  return created
end

-------------------------------------------------------------------------------
-- Group / ungroup
-------------------------------------------------------------------------------
function M.group(project, nodes, parent_id)
  if #nodes == 0 then return nil end
  local set = {}
  local cx, cy = 0, 0
  for _, n in pairs(nodes) do
    set[n.id] = true
    cx, cy = cx + n.x, cy + n.y
  end
  cx, cy = math.floor(cx / #nodes + 0.5), math.floor(cy / #nodes + 0.5)
  local g = M.add_node(project, { type = "factory", parent = parent_id, x = cx, y = cy })
  local minx, maxx = math.huge, -math.huge
  for _, n in pairs(nodes) do
    n.parent = g.id
    minx = math.min(minx, n.x)
    maxx = math.max(maxx, n.x)
  end
  local inputs, outputs = {}, {}
  local to_fix = {}
  for _, l in pairs(project.links) do
    local fin, tin = set[l.from.node], set[l.to.node]
    if fin ~= tin then to_fix[#to_fix + 1] = { link = l, fin = fin, tin = tin } end
  end
  for _, t in pairs(to_fix) do
    local l = t.link
    local inner_end = t.tin and l.to or l.from
    local inner_node = project.nodes[inner_end.node]
    local port = M.find_port(project, inner_node, inner_end.port, t.tin and "in" or "out")
    local item = port and port.item
    if t.tin then
      -- outside -> inside: create (or reuse) an input node per item
      local io = inputs[item]
      if not io then
        io = M.add_node(project, { type = "input", parent = g.id, item = item, x = minx - 9, y = inner_node.y, fixed = false })
        inputs[item] = io
      end
      M.add_link(project, io.id, "out", l.to.node, l.to.port)
      l.to = { node = g.id, port = "i:" .. io.id }
      l.points, l.label_off = nil, nil
    else
      local io = outputs[item]
      if not io then
        io = M.add_node(project, { type = "output", parent = g.id, item = item, x = maxx + 10, y = inner_node.y, fixed = false })
        outputs[item] = io
      end
      M.add_link(project, l.from.node, l.from.port, io.id, "in")
      l.from = { node = g.id, port = "o:" .. io.id }
      l.points, l.label_off = nil, nil
    end
  end
  -- remove duplicate parent links that may now exist
  local seen = {}
  for id, l in pairs(project.links) do
    local k = l.from.node .. "|" .. l.from.port .. "|" .. l.to.node .. "|" .. l.to.port
    if seen[k] then project.links[id] = nil else seen[k] = true end
  end
  return g
end

function M.ungroup(project, g)
  if g.type ~= "factory" or g.id == project.root then return {} end
  local parent = g.parent
  local kids = M.children(project, g.id)
  local cx, cy = 0, 0
  local count = 0
  for _, c in pairs(kids) do
    if c.type ~= "input" and c.type ~= "output" then cx, cy, count = cx + c.x, cy + c.y, count + 1 end
  end
  if count > 0 then cx, cy = cx / count, cy / count end
  local moved = {}
  for _, c in pairs(kids) do
    if c.type == "input" then
      -- connect every outside source directly to every inside consumer
      local srcs, dsts = {}, {}
      for _, l in pairs(project.links) do
        if l.to.node == g.id and l.to.port == "i:" .. c.id then srcs[#srcs + 1] = l.from end
        if l.from.node == c.id then dsts[#dsts + 1] = l.to end
      end
      M.delete_node(project, c)
      for _, s in pairs(srcs) do
        for _, d in pairs(dsts) do M.add_link(project, s.node, s.port, d.node, d.port) end
      end
    elseif c.type == "output" then
      local srcs, dsts = {}, {}
      for _, l in pairs(project.links) do
        if l.from.node == g.id and l.from.port == "o:" .. c.id then dsts[#dsts + 1] = l.to end
        if l.to.node == c.id then srcs[#srcs + 1] = l.from end
      end
      M.delete_node(project, c)
      for _, s in pairs(srcs) do
        for _, d in pairs(dsts) do M.add_link(project, s.node, s.port, d.node, d.port) end
      end
    else
      c.parent = parent
      c.x = c.x + math.floor(g.x - cx + 0.5)
      c.y = c.y + math.floor(g.y - cy + 0.5)
      moved[#moved + 1] = c
    end
  end
  for id, l in pairs(project.links) do
    if l.from.node == g.id or l.to.node == g.id then project.links[id] = nil end
  end
  project.nodes[g.id] = nil
  return moved
end

return M
