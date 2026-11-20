-- Run from anywhere: lua5.2 tests/test.lua
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
dofile(here .. "harness.lua")
require("control")
local model = require("scripts.model")
local solver = require("scripts.solver")
local render = require("scripts.render")
local gui = require("scripts.gui")

local function approx(a, b, msg)
  if math.abs(a - b) > 1e-6 * math.max(1, math.abs(b)) then error(msg .. ": got " .. tostring(a) .. " expected " .. tostring(b), 2) end
end

handlers.init()
local player = make_player(1)
handlers["fm-toggle"]({ player_index = 1 })
assert(gui.is_open(player), "gui should be open")
local ps = storage.players[1]
local project = storage.projects[ps.project]
assert(project, "project")

-- convert local canvas pos -> screen location
local function loc_of(pos)
  local cam = player.gui.screen.fm_canvas
  local off = model.region_offset(project.nodes[ps.factory].region)
  local ppt = gui.ppt(player, cam.zoom)
  local cx = ps.cam_px.x + ps.cam_px.w / 2
  local cy = ps.cam_px.y + ps.cam_px.h / 2
  return { x = math.floor(cx + (pos.x + off.x - cam.position.x) * ppt + 0.5), y = math.floor(cy + (pos.y + off.y - cam.position.y) * ppt + 0.5) }
end
local function layer() return player.gui.screen.fm_layer end
local function click(pos, opts)
  opts = opts or {}
  local loc = loc_of(pos)
  game.ticks_played = game.ticks_played + 30 game.tick = game.tick + 30
  -- whatever GUI is under the cursor: a node handle or the canvas layer
  local target = layer().grip
  for _, ch in pairs(rawget(player.gui.screen, "children")) do
    if ch.name and ch.name:sub(1, 5) == "fm_h_" then
      local l = ch.location
      if loc.x >= l.x and loc.x < l.x + ch.style.width and loc.y >= l.y and loc.y < l.y + ch.style.height then target = ch.grip end
    end
  end
  handlers.on_gui_click({ player_index = 1, element = target, button = opts.button or 1, cursor_display_location = loc, shift = opts.shift or false, control = opts.control or false, alt = false })
end
local function tick(n) game.ticks_played = game.ticks_played + n end
-- native drag of a handle/layer frame by a pixel delta
-- like the game: a "click" at mouse-down on the grip, then location changes while dragging
local function native_drag(frame, dx, dy, press_at)
  local l = frame.location
  local grip = frame.grip
  local at = press_at or { x = math.max(l.x, ps.cam_px.x) + 3, y = math.max(l.y, ps.cam_px.y) + 3 }
  handlers.on_gui_click({ player_index = 1, element = grip, button = 1, cursor_display_location = at, shift = false, control = false })
  assert(frame.valid, "dragged frame destroyed by the press")
  l = frame.location
  local steps = 4
  for i = 1, steps do
    frame.location = { x = l.x + dx * i / steps, y = l.y + dy * i / steps }
    tick(1)
    handlers.on_gui_location_changed({ player_index = 1, element = frame })
    assert(frame.valid, "dragged frame destroyed during drag")
  end
  tick(30)
end
local function px_per_tile() local cam = player.gui.screen.fm_canvas return (gui.ppt(player, cam.zoom)) end
local function drag_node(node, dtx, dty)
  local h = player.gui.screen["fm_h_" .. node.id]
  assert(h, "handle for node " .. node.id)
  local k = px_per_tile()
  native_drag(h, dtx * k, dty * k)
end
local function pan(dtx, dty)
  local k = px_per_tile()
  native_drag(layer(), dtx * k, dty * k)
end
local function elem(tags, value)
  handlers.on_gui_elem_changed({ player_index = 1, element = { valid = true, tags = tags, elem_value = value } })
end

-- add output gear 60/min
elem({ fm = "add_io", io = "output", t = "item" }, "iron-gear-wheel")
local out = nil
for _, n in pairs(project.nodes) do if n.type == "output" then out = n end end
assert(out and out.fixed, "output fixed")
out.value = 1 -- 1/s
out.x, out.y = 30, 0

-- click its input port, then click empty space -> picker; pick gear recipe
local L = render.layout(project, out)
click({ x = L.ins[1].x, y = L.ins[1].y })
assert(ps.pending_link, "pending link")
click({ x = 20, y = 0 })
assert(player.gui.screen.fm_popup, "picker popup")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "x", type = "sprite-button", tags = { fm = "pick", kind = "recipe", recipe = "iron-gear-wheel" } }, button = 1, cursor_display_location = { x = 0, y = 0 } })
local gear
for _, n in pairs(project.nodes) do if n.recipe == "iron-gear-wheel" then gear = n end end
assert(gear and not gear.fixed, "gear auto node")
assert(gear.machine == "assembling-machine-2", "default machine " .. tostring(gear.machine))
local res = project.results
approx(res.nodes[gear.id].x, 1 / 1.5, "gear machines")

-- drag from gear input port to empty -> picker -> iron plate
local GL = render.layout(project, gear)
click({ x = GL.ins[1].x, y = GL.ins[1].y })
click({ x = 5, y = 0 })
assert(player.gui.screen.fm_popup, "picker 2")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "x", type = "sprite-button", tags = { fm = "pick", kind = "recipe", recipe = "iron-plate" } }, button = 1, cursor_display_location = { x = 0, y = 0 } })
local plate
for _, n in pairs(project.nodes) do if n.recipe == "iron-plate" then plate = n end end
approx(project.results.nodes[plate.id].x, 6.4, "furnaces")
-- mining
local PL = render.layout(project, plate)
click({ x = PL.ins[1].x, y = PL.ins[1].y })
click({ x = -12, y = 0 })
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "x", type = "sprite-button", tags = { fm = "pick", kind = "recipe", recipe = "mine:iron-ore" } }, button = 1, cursor_display_location = { x = 0, y = 0 } })
local mine
for _, n in pairs(project.nodes) do if n.recipe == "mine:iron-ore" then mine = n end end
assert(mine, "mine node")
approx(project.results.nodes[mine.id].x, 4, "drills")
print("chain OK: gear", project.results.nodes[gear.id].x, "plates", project.results.nodes[plate.id].x, "drills", project.results.nodes[mine.id].x)

-- move a node by dragging its body
local ox, oy = gear.x, gear.y
drag_node(gear, 3, 2)
assert(gear.x == ox + 3 and gear.y == oy + 2, "node moved " .. gear.x .. "," .. gear.y)

-- pan by dragging empty space
local v = gui.get_view(ps)
local vx = v.x
pan(-5, 0)
approx(v.x, vx + 5, "pan")

-- zoom on wheel keeps point under cursor
local cam = player.gui.screen.fm_canvas
local target = { x = 12, y = 3 }
local lc = loc_of(target)
handlers["fm-wheel-up"]({ player_index = 1, element = cam, cursor_display_location = lc })
local cam2 = player.gui.screen.fm_canvas
local loc2 = loc_of(target)
assert(math.abs(loc2.x - lc.x) <= 1 and math.abs(loc2.y - lc.y) <= 1, "zoom anchor")

-- fix gear to 2 machines -> plates and drills follow
gear.fixed, gear.value = true, 2
solver.solve(project)
approx(project.results.nodes[plate.id].x, 6.4 * 3, "furnaces after fix")
-- output is fixed at 1/s but gets 3/s: link from gear to out is pull limited (out demand 1), surplus on gear
local gr = project.results.nodes[gear.id].outs["item/iron-gear-wheel"]
approx(gr.produced, 3, "gear produced")
approx(gr.delivered, 1, "gear delivered")
gear.fixed = false
solver.solve(project)

-- select the gear + plate with shift-drag rectangle and group
ps.selection = {}
select_only_test = nil
click({ x = plate.x + 2, y = plate.y + 1 })
click({ x = gear.x + 2, y = gear.y + 1 }, { shift = true })
local selcount = 0
for _ in pairs(ps.selection) do selcount = selcount + 1 end
assert(ps.selection[gear.id] and ps.selection[plate.id], "rect select")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "group" } }, button = 1 })
local g = project.nodes[gear.parent]
assert(g and g.type == "factory" and plate.parent == g.id, "grouped")
local kids = model.children(project, g.id)
local nin, nout = 0, 0
for _, k in pairs(kids) do if k.type == "input" then nin = nin + 1 end if k.type == "output" then nout = nout + 1 end end
assert(nin == 1 and nout == 1, "group made ports " .. nin .. "/" .. nout)
-- same numbers after grouping
approx(project.results.nodes[mine.id].x, 4, "drills after group")
approx(project.results.nodes[gear.id].x, 1 / 1.5, "gears after group")
print("group OK, selected", selcount)

-- reorder factory inputs/outputs with the arrows on the block
do
  local i2 = model.add_node(project, { type = "input", item = "item/iron-plate", parent = g.id, x = -30, y = 50, fixed = false })
  local ins0 = model.node_ports(project, g)
  assert(#ins0 == 2, "two inputs")
  local first, second = ins0[1].child, ins0[2].child
  local inner_before = {}
  for _, c in pairs(model.children(project, g.id)) do inner_before[c.id] = c.x .. "," .. c.y end
  update_view = handlers -- noop
  gui.refresh_handles(player, ps)
  local arrows = render.port_arrows(project, g)
  local down
  for _, a in pairs(arrows) do if a.child == first and a.dir == 1 then down = a end end
  assert(down and down.enabled, "down arrow on first input")
  click({ x = down.x, y = down.y })
  local ins1 = model.node_ports(project, g)
  assert(ins1[1].child == second and ins1[2].child == first, "inputs swapped")
  for _, c in pairs(model.children(project, g.id)) do
    if inner_before[c.id] then assert(inner_before[c.id] == c.x .. "," .. c.y, "inner node moved") end
  end
  -- links still attached to the right ports
  approx(project.results.nodes[mine.id].x, 4, "drills after reorder")
  model.delete_node(project, i2)
  update_view = nil
  print("port order OK")
end

-- enter factory via double click
local GLy = render.layout(project, g)
click({ x = g.x + 1, y = g.y + 0.5 })
game.ticks_played = game.ticks_played - 20 game.tick = game.tick - 20 -- make the next click count as a double click (click() adds 30)
click({ x = g.x + 1, y = g.y + 0.5 })
assert(ps.factory == g.id, "entered factory")
local s = solver.summary(project, g.id)
approx(s.inputs["item/iron-ore"], 2, "factory input ore")
approx(s.outputs["item/iron-gear-wheel"], 1, "factory output gear")
-- back up
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "goto_factory", factory = project.root } }, button = 1 })
assert(ps.factory == project.root)

-- duplicate the factory, numbers of the copy are idle (no links)
ps.selection = { [g.id] = true }
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "duplicate_sel" } }, button = 1 })
local copies = 0
for _, n in pairs(project.nodes) do if n.recipe == "iron-gear-wheel" then copies = copies + 1 end end
assert(copies == 2, "duplicated recursively")

-- ungroup the original
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "ungroup", node = g.id } }, button = 1 })
assert(project.nodes[g.id] == nil and gear.parent == project.root, "ungrouped")
approx(project.results.nodes[mine.id].x, 4, "drills after ungroup")
approx(project.results.nodes[gear.id].x, 1 / 1.5, "gears after ungroup")

-- right click a link deletes it
local link
for _, l in pairs(project.links) do if l.to.node == out.id then link = l end end
local pts = render.link_points(project, link)
click(pts[5], { button = 2 })
assert(project.links[link.id] == nil, "link deleted by right click")
approx(project.results.nodes[gear.id].x, 0, "gear idle after unlink")

-- inspector for every node type renders
for _, n in pairs(project.nodes) do
  if n.parent == project.root then
    ps.selection = { [n.id] = true }
    gui.refresh_inspector(player, ps)
  end
end
-- text edit
ps.selection = { [gear.id] = true }
handlers.on_gui_text_changed({ player_index = 1, element = { valid = true, text = "3", tags = { fm = "set_value", node = gear.id } } })
assert(gear.fixed and gear.value == 3)
handlers.on_gui_text_changed({ player_index = 1, element = { valid = true, text = "50", tags = { fm = "set_prod", node = gear.id } } })
approx(project.results.nodes[gear.id].outs["item/iron-gear-wheel"].produced, 3 * 1.5 * 1.5, "productivity")

-- cycle test: A <-> B with surplus loop must converge
local p2 = model.create_project("cycle")
local a = model.add_node(p2, { type = "input", item = "item/iron-plate", parent = p2.root, fixed = false })
local o = model.add_node(p2, { type = "output", item = "item/iron-plate", parent = p2.root, fixed = true, value = 5 })
model.add_link(p2, a.id, "out", o.id, "in")
solver.solve(p2)
approx(p2.results.nodes[a.id].x, 5, "auto input pulled")

-- popup buttons are real elements that get destroyed by their own action
ps.selection = { [gear.id] = true }
local GL2 = render.layout(project, gear)
click({ x = GL2.x + 1, y = GL2.y + 0.5 }, { button = 2 })
local popup = player.gui.screen.fm_popup
assert(popup, "node menu")
local function find(el, pred)
  if pred(el) then return el end
  for _, c in pairs(rawget(el, "children")) do local r = find(c, pred) if r then return r end end
end
local btn = find(popup, function(el) return rawget(el, "tags") and rawget(el, "tags").fm == "toggle_fixed" end)
local was = gear.fixed
handlers.on_gui_click({ player_index = 1, element = btn, button = 1, cursor_display_location = { x = 0, y = 0 } })
assert(gear.fixed ~= was, "toggle via popup")
-- picker popup via real button
for _, n in pairs(project.nodes) do
  if n.parent == project.root and n.id ~= gear.id then
    local L = render.layout(project, n)
    if L.x < GL2.x + 2 and L.x + L.w > GL2.x - 1 and L.y < GL2.y + GL2.h and L.y + L.h > GL2.y then n.y = n.y + 60 end
  end
end
gui.refresh_handles(player, ps)
click({ x = GL2.ins[1].x, y = GL2.ins[1].y })
click({ x = GL2.x - 3, y = GL2.y - 3 })
local function count_plates() local c = 0 for _, n in pairs(project.nodes) do if n.recipe == "iron-plate" then c = c + 1 end end return c end
local before_plates = count_plates()
local pb = find(player.gui.screen.fm_popup, function(el) return rawget(el, "tags") and rawget(el, "tags").fm == "pick" and rawget(el, "tags").recipe == "iron-plate" end)
handlers.on_gui_click({ player_index = 1, element = pb, button = 1, cursor_display_location = { x = 0, y = 0 } })
assert(count_plates() == before_plates + 1, "picked via real popup button")

-- calibration: simulate a game whose real mapping is 1.25x scale and shifted by (+7, -4) px
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "calibrate" } }, button = 1 })
local cal = ps.calibrating
assert(cal, "calibrating")
local camx = player.gui.screen.fm_canvas
local v = gui.get_view(ps)
local function true_loc(lp) -- what the "real game" shows
  local base = 32 * camx.zoom * 1.25
  return { x = ps.cam_px.x + ps.cam_px.w / 2 + 7 + (lp.x - v.x) * base, y = ps.cam_px.y + ps.cam_px.h / 2 - 4 + (lp.y - v.y) * base }
end
for _, sg in pairs({ -1, 1 }) do
  local t = { x = cal.center.x + sg * cal.d, y = cal.center.y + sg * cal.d }
  handlers.on_gui_click({ player_index = 1, element = camx, button = 1, cursor_display_location = true_loc(t), shift = false, control = false })
end
assert(ps.calib and not ps.calibrating, "calibrated")
local probe = { x = v.x + 3.3, y = v.y - 2.1 }
-- local_pos is internal; check via hit: put cursor at gear header in "real" coords and click to select
ps.selection = {}
game.ticks_played = game.ticks_played + 100 game.tick = game.tick + 100
handlers.on_gui_click({ player_index = 1, element = camx, button = 1, cursor_display_location = true_loc({ x = gear.x + 0.3, y = gear.y + 0.2 }), shift = false, control = false })
assert(ps.selection[gear.id], "click lands on node after calibration")
print("calibration OK", ps.calib.kx, ps.calib.ox, ps.calib.oy)

-- group drag: both selected nodes move together, handles follow
ps.calib = nil
gui.apply_view(player, ps)
ps.selection = { [gear.id] = true, [plate.id] = true }
local gx, px = gear.x, plate.x
drag_node(gear, 4, 0)
assert(gear.x == gx + 4 and plate.x == px + 4, "group drag " .. gear.x - gx .. " " .. plate.x - px)
assert(player.gui.screen["fm_h_" .. gear.id] and not ps.drag, "handles rebuilt after drag")
print("drag OK")
-- every port sits on a whole tile when blocks are on the grid
for _, n in pairs(project.nodes) do
  if n.parent == project.root then
    assert(n.x == math.floor(n.x) and n.y == math.floor(n.y), "block on grid " .. n.x .. "," .. n.y)
    local L = render.layout(project, n)
    for _, p in pairs(L.ins) do assert(p.y == math.floor(p.y), "port row on a whole tile") end
    for _, p in pairs(L.outs) do assert(p.y == math.floor(p.y), "port row on a whole tile") end
    if #L.outs >= 2 then assert(L.outs[2].y - L.outs[1].y == 1, "1 tile between ports") end
  end
end
-- regression: pan, then press an unselected block and drag it -> block moves, view stays
ps.selection = {}
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "fit" } }, button = 1 })
local v0 = gui.get_view(ps)
pan(1, 0)
local vx0, vy0 = v0.x, v0.y
local mx = mine.x
drag_node(mine, 2, 0)
assert(mine.x == mx + 2, "block moved after pan")
assert(v0.x == vx0 and v0.y == vy0, "view did not move while dragging a block")
assert(ps.selection[mine.id], "dragged block selected")
-- pressing a selected block keeps it selected (a drag may follow); clicking empty space deselects
local ML = render.layout(project, mine)
click({ x = ML.x + 2, y = ML.y + 1 })
assert(ps.selection[mine.id], "press keeps selection")
click({ x = ML.x + 2, y = ML.y + 1 }, { shift = true })
assert(not ps.selection[mine.id], "shift+click toggles off")
click({ x = ML.x + 2, y = ML.y + 1 })
assert(ps.selection[mine.id], "click selects again")
-- press on a handle must not destroy that handle (it would cancel the drag in game)
local h_before = player.gui.screen["fm_h_" .. mine.id]
click({ x = ML.x + 2, y = ML.y + 1 })
assert(h_before.valid and player.gui.screen["fm_h_" .. mine.id] == h_before, "handle survives the press")
-- pan twice in a row (layer not reset in between, e.g. while paused) -> no jump
local vstart = v0.x
local lay = layer()
local k = px_per_tile()
lay.location = { x = lay.location.x + 2 * k, y = lay.location.y } handlers.on_gui_location_changed({ player_index = 1, element = lay })
lay.location = { x = lay.location.x + 1 * k, y = lay.location.y } handlers.on_gui_location_changed({ player_index = 1, element = lay })
approx(v0.x, vstart - 3, "incremental pan")
print("regression OK")
-- arrows move the selection
ps.selection = { [mine.id] = true }
local mx2 = mine.x
handlers["fm-pan-right"]({ player_index = 1, input_name = "fm-pan-right" })
assert(mine.x == mx2 + 1, "arrow moves selection")
handlers["cmd_fm-debug"]({ player_index = 1 })
handlers["cmd_fm-debug"]({ player_index = 1 })

-- top-left button
handlers.on_player_created({ player_index = 1 })
local tb = player.gui.top.mod_gui_top_frame.mod_gui_inner_frame.fm_top_button
assert(tb, "top button")
handlers.on_gui_click({ player_index = 1, element = tb, button = 1 })
assert(not gui.is_open(player), "top button closes")
handlers.on_gui_click({ player_index = 1, element = tb, button = 1 })
assert(gui.is_open(player), "top button opens")
print("top button OK")

-- input blocking + pause
assert(player.controller_type == 2, "remote view while open")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "toggle_pause" } }, button = 1 })
assert(game.tick_paused, "paused")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "toggle_pause" } }, button = 1 })
assert(not game.tick_paused, "resumed")
handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = true, tags = { fm = "auto_pause" } } })
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "close" } }, button = 1 })
assert(player.controller_type == 1 and not game.tick_paused, "restored on close")
handlers.on_lua_shortcut({ player_index = 1, prototype_name = "fm-shortcut" })
assert(game.tick_paused and player.controller_type == 2, "auto pause on open")
handlers.on_gui_closed({ player_index = 1, element = player.gui.screen.fm_top })
assert(not gui.is_open(player) and not game.tick_paused and player.controller_type == 1, "esc closes and restores")
handlers.on_lua_shortcut({ player_index = 1, prototype_name = "fm-shortcut" })
-- leaving remote view by hand closes window
player.controller_type = 1
handlers.on_player_controller_changed({ player_index = 1 })
assert(not gui.is_open(player), "controller change closes")
handlers.on_lua_shortcut({ player_index = 1, prototype_name = "fm-shortcut" })
handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = false, tags = { fm = "auto_pause" } } })
if game.tick_paused then game.tick_paused = false end
print("pause/input OK")

-- unit toggle
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "toggle_unit" } }, button = 1 })
assert(render.unit() == 1, "per second")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "toggle_unit" } }, button = 1 })
assert(render.unit() == 60, "per minute")

-- splitter: one plate source -> split -> two fixed gear outputs
local p3 = model.create_project("split")
ps.project, ps.factory = p3.id, p3.root
local src = model.add_node(p3, { type = "input", item = "item/iron-plate", parent = p3.root, fixed = false, x = 0, y = 0 })
local sp = model.add_node(p3, { type = "split", parent = p3.root, x = 10, y = 0 })
local g1 = model.add_node(p3, { type = "recipe", recipe = "iron-gear-wheel", parent = p3.root, fixed = true, value = 10, x = 20, y = 0 })
local g2 = model.add_node(p3, { type = "recipe", recipe = "iron-gear-wheel", parent = p3.root, fixed = true, value = 5, x = 20, y = 8 })
gui.refresh_all(player, ps)
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "fit" } }, button = 1 })
local function port_click(n, dir, idx)
  local L = render.layout(p3, n)
  local pp = (dir == "in" and L.ins or L.outs)[idx or 1]
  project = p3
  click({ x = pp.x, y = pp.y })
end
port_click(src, "out") port_click(sp, "in")
assert(sp.item == "item/iron-plate", "split took item")
port_click(sp, "out") port_click(g1, "in")
port_click(sp, "out") port_click(g2, "in")
local nlinks = 0 for _ in pairs(p3.links) do nlinks = nlinks + 1 end
assert(nlinks == 3, "3 links, got " .. nlinks)
local need = (10 + 5) * 1.5 * 2 -- plates per second
approx(p3.results.nodes[sp.id].x, need, "split total")
approx(p3.results.nodes[src.id].x, need, "source pulled")
local into
for _, l in pairs(p3.links) do if l.to.node == sp.id then into = l end end
local belts = render.belts_for(into, "item/iron-plate", p3.results.links[into.id].flow)
approx(belts, need / 15, "belts on link into splitter")
-- per-link belt choice
ps.selected_link = into.id
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_link_belt", link = into.id, name = "fast-transport-belt" } }, button = 1 })
approx((render.belts_for(into, "item/iron-plate", p3.results.links[into.id].flow)), need / 30, "fast belts")
gui.refresh_inspector(player, ps)
ps.selected_link = nil
ps.selection = { [sp.id] = true } gui.refresh_inspector(player, ps)
ps.selection = { [g1.id] = true } gui.refresh_inspector(player, ps)
print("split OK, belts", belts)

-- priority splitter
do
  local p4 = model.create_project("prio")
  local src4 = model.add_node(p4, { type = "input", item = "item/iron-plate", parent = p4.root, fixed = true, value = 5 })
  local ps4 = model.add_node(p4, { type = "psplit", parent = p4.root, x = 10, count = 3 })
  local cs = {}
  for i = 1, 3 do cs[i] = model.add_node(p4, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = p4.root, fixed = true, value = 1, x = 20, y = i * 6 }) end
  model.add_link(p4, src4.id, "out", ps4.id, "in")
  ps4.item = "item/iron-plate"
  for i = 1, 3 do model.add_link(p4, ps4.id, "s" .. ps4.slots[i], cs[i].id, "item/iron-plate") end
  solver.solve(p4)
  local function got(i) return p4.results.nodes[cs[i].id].ins["item/iron-plate"].received end
  approx(got(1), 3, "prio #1 full") approx(got(2), 2, "prio #2 rest") approx(got(3), 0, "prio #3 nothing")
  -- move output 3 to the top: links stay, priorities change
  local s3 = ps4.slots[3]
  model.move_slot(ps4, s3, -1) model.move_slot(ps4, s3, -1)
  solver.solve(p4)
  approx(got(3), 3, "moved to top") approx(got(1), 2, "now second") approx(got(2), 0, "now last")
  -- overflow: 12 in, 9 needed, extra goes to cs[2]'s output
  src4.value = 12
  ps4.overflow = ps4.slots[3] -- cs[2] is last now
  solver.solve(p4)
  approx(got(2), 6, "overflow output gets the extra")
  approx(p4.results.nodes[ps4.id].x, 12, "splitter passes everything")
  -- output count rules
  assert(not model.set_slot_count(p4, ps4, 2), "cannot drop below linked outputs")
  assert(model.set_slot_count(p4, ps4, 5), "grow to 5")
  -- unlink the middle-priority output -> linked at #1, #3 and new free #4/#5
  local mid = ps4.slots[2]
  for id, l in pairs(p4.links) do if l.from.port == "s" .. mid then p4.links[id] = nil end end
  ps4.overflow = ps4.slots[5] -- free output chosen for overflow must stay
  assert(model.min_slots(p4, ps4) == 3, "min = 2 linked + overflow, got " .. model.min_slots(p4, ps4))
  local keep_ovf = ps4.overflow
  assert(model.set_slot_count(p4, ps4, 3), "shrink to 3")
  assert(#ps4.slots == 3, "3 left")
  local has_ovf = false
  for _, v in pairs(ps4.slots) do if v == keep_ovf then has_ovf = true end end
  assert(has_ovf, "overflow output kept")
  for _, v in pairs(ps4.slots) do assert(v ~= mid, "free higher-priority output removed only after lower ones... ") end
  -- GUI: inspector, +/- buttons, overflow drop-down, arrows on the block
  local saved_p, saved_f = ps.project, ps.factory
  ps.project, ps.factory = p4.id, p4.root
  gui.refresh_all(player, ps)
  ps.selection = { [ps4.id] = true }
  gui.refresh_inspector(player, ps)
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "psplit_count", node = ps4.id, delta = 1 } }, button = 1 })
  assert(#ps4.slots == 4, "+ button")
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "psplit_count", node = ps4.id, delta = -1 } }, button = 1 })
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "psplit_count", node = ps4.id, delta = -1 } }, button = 1 })
  assert(#ps4.slots == 3, "- button stops at the minimum")
  handlers.on_gui_selection_state_changed({ player_index = 1, element = { valid = true, selected_index = 1, tags = { fm = "psplit_overflow", node = ps4.id } } })
  assert(ps4.overflow == nil, "overflow none")
  handlers.on_gui_selection_state_changed({ player_index = 1, element = { valid = true, selected_index = 2, tags = { fm = "psplit_overflow", node = ps4.id } } })
  assert(ps4.overflow == ps4.slots[1], "overflow = output 1")
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "fit" } }, button = 1 })
  local first = ps4.slots[1]
  local arr
  for _, a in pairs(render.port_arrows(p4, ps4)) do if a.slot == first and a.dir == 1 then arr = a end end
  project = p4
  click({ x = arr.x, y = arr.y })
  assert(ps4.slots[2] == first, "arrow on block lowers priority")
  ps.project, ps.factory = saved_p, saved_f
  print("priority splitter OK")
end

-- factory output shows surplus from inside
do
  local p5 = model.create_project("extra")
  local f = model.add_node(p5, { type = "factory", parent = p5.root, x = 0, y = 0 })
  local gr = model.add_node(p5, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = f.id, fixed = true, value = 2 })
  local io = model.add_node(p5, { type = "output", item = "item/iron-gear-wheel", parent = f.id, fixed = false })
  model.add_link(p5, gr.id, "item/iron-gear-wheel", io.id, "in")
  local sink = model.add_node(p5, { type = "output", item = "item/iron-gear-wheel", parent = p5.root, fixed = true, value = 1, x = 20 })
  model.add_link(p5, f.id, "o:" .. io.id, sink.id, "in")
  solver.solve(p5)
  local fo = p5.results.nodes[f.id].outs["o:" .. io.id]
  approx(fo.produced, 1, "factory output flow")
  approx(fo.extra, 2, "factory output shows the surplus inside")
  render.draw_factory(p5, p5.root)
  print("factory surplus OK")
end

-- anchors and movable labels on links
do
  local p6 = model.create_project("anchors")
  local a6 = model.add_node(p6, { type = "input", item = "item/iron-plate", parent = p6.root, fixed = true, value = 1, x = 0, y = 0 })
  local b6 = model.add_node(p6, { type = "output", item = "item/iron-plate", parent = p6.root, fixed = false, x = 20, y = 10 })
  local l6 = model.add_link(p6, a6.id, "out", b6.id, "in")
  local saved_p, saved_f = ps.project, ps.factory
  ps.project, ps.factory = p6.id, p6.root
  project = p6
  gui.refresh_all(player, ps)
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "fit" } }, button = 1 })
  solver.solve(p6)
  -- middle click on the curve adds an anchor
  local pts = render.link_points(p6, l6)
  local onlink = pts[9]
  handlers["fm-middle"]({ player_index = 1, element = layer().grip, cursor_display_location = loc_of(onlink), input_name = "fm-middle" })
  assert(l6.points and #l6.points == 1, "anchor added")
  assert(ps.selected_anchor and ps.selected_anchor.idx == 1, "anchor selected")
  -- the curve passes through the anchor
  local ap = l6.points[1]
  local through = false
  for _, p in pairs(render.link_points(p6, l6)) do if math.abs(p.x - ap.x) < 1e-6 and math.abs(p.y - ap.y) < 1e-6 then through = true end end
  assert(through, "path goes through anchor")
  -- drag the anchor
  local h = player.gui.screen["fm_h_a" .. l6.id .. "_1"]
  assert(h, "anchor handle")
  local k = px_per_tile()
  local ax, ay = ap.x, ap.y
  native_drag(h, 0, 4 * k)
  approx(l6.points[1].y, ay + 4, "anchor moved")
  -- add a second anchor, then delete the first with Delete
  local pts2 = render.link_points(p6, l6)
  handlers["fm-middle"]({ player_index = 1, element = layer().grip, cursor_display_location = loc_of(pts2[#pts2 - 3]), input_name = "fm-middle" })
  assert(#l6.points == 2, "second anchor")
  ps.selected_anchor = { link = l6.id, idx = 1 }
  handlers["fm-delete"]({ player_index = 1 })
  assert(#l6.points == 1, "anchor deleted with Delete")
  -- straight-line style goes horizontal first
  model.settings().link_style = "ortho"
  local op = render.link_points(p6, l6)
  assert(op[2].y == op[1].y, "ortho: horizontal first")
  for i = 1, #op - 1 do assert(op[i].x == op[i + 1].x or op[i].y == op[i + 1].y, "ortho segments are axis-aligned") end
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = true, tags = { fm = "link_style", style = "spline" } } })
  assert(model.settings().link_style == "spline")
  -- move the info label
  gui.refresh_handles(player, ps)
  local lh = player.gui.screen["fm_h_l" .. l6.id]
  assert(lh, "label handle")
  native_drag(lh, 3 * k, -2 * k)
  assert(l6.label_off and l6.label_off.x == 3 and l6.label_off.y == -2, "label moved")
  assert(ps.selected_link == l6.id, "label selects link")
  -- moving both nodes moves the anchors along
  ps.selection = { [a6.id] = true, [b6.id] = true }
  local before = l6.points[1].x
  handlers["fm-pan-right"]({ player_index = 1, input_name = "fm-pan-right" })
  approx(l6.points[1].x, before + 1, "anchor follows moved nodes")
  gui.refresh_inspector(player, ps)
  ps.selected_link = l6.id ps.selection = {} gui.refresh_inspector(player, ps)
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_link_color", link = l6.id, color = "blue" } }, button = 1 })
  assert(l6.color and l6.color.b == 1, "link painted blue")
  gui.refresh_inspector(player, ps)
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_link_color", link = l6.id } }, button = 1 })
  assert(l6.color == nil, "auto colour")
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "reset_anchors", link = l6.id } }, button = 1 })
  assert(l6.points == nil, "reset anchors")
  ps.project, ps.factory = saved_p, saved_f
  ps.project, ps.factory = p6.id, p6.root
  gui.refresh_all(player, ps)
  -- anchors straighten: dragging close to the input port's height snaps onto it
  local saved_style = model.settings().link_style
  local L6a = render.layout(p6, a6)
  local port_y = L6a.outs[1].y
  local mid6 = render.polyline_mid(render.link_points(p6, l6))
  l6.points = { { x = math.floor(mid6.x), y = port_y + 3 } }
  gui.refresh_handles(player, ps)
  local h6 = player.gui.screen["fm_h_a" .. l6.id .. "_1"]
  native_drag(h6, 0, (-3 + 0.15) * k)
  approx(l6.points[1].y, port_y, "anchor snapped onto the output line")
  -- label sliding along the link
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = true, tags = { fm = "label_mode", mode = "along" } } })
  gui.refresh_handles(player, ps)
  local lh2 = player.gui.screen["fm_h_l" .. l6.id]
  native_drag(lh2, 4 * k, 3 * k)
  assert(l6.label_t and l6.label_t > 0.5, "label moved along, t=" .. tostring(l6.label_t))
  local lp6 = render.label_pos(p6, l6)
  local pts6 = render.link_points(p6, l6)
  local on = false
  for i = 1, #pts6 - 1 do
    local a, b = pts6[i], pts6[i + 1]
    local cross = (b.x - a.x) * (lp6.y - a.y) - (b.y - a.y) * (lp6.x - a.x)
    local within = math.min(a.x, b.x) - 1e-6 <= lp6.x and lp6.x <= math.max(a.x, b.x) + 1e-6 and math.min(a.y, b.y) - 1e-6 <= lp6.y and lp6.y <= math.max(a.y, b.y) + 1e-6
    if math.abs(cross) < 1e-6 and within then on = true end
  end
  assert(on, "label sits on the link")
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = true, tags = { fm = "label_mode", mode = "free" } } })
  ps.project, ps.factory = saved_p, saved_f
  print("anchors OK")
end

-- automatic surplus outputs of a factory
do
  local p8 = model.create_project("auto")
  local f = model.add_node(p8, { type = "factory", parent = p8.root, x = 0, y = 0, auto_outputs = true })
  local gr = model.add_node(p8, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = f.id, fixed = true, value = 2 })
  solver.solve_all(p8)
  local auto
  for _, c in pairs(model.children(p8, f.id)) do if c.auto then auto = c end end
  assert(auto and auto.item == "item/iron-gear-wheel", "auto output created for gears")
  assert(#model.visible_children(p8, f.id) == 1, "auto output hidden inside")
  local fo = p8.results.nodes[f.id].outs["o:" .. auto.id]
  approx(fo.produced, 3, "all surplus on the output")
  -- plates are an unconnected ingredient, not a surplus: no output for them
  local n_auto = 0
  for _, c in pairs(model.children(p8, f.id)) do if c.auto then n_auto = n_auto + 1 end end
  assert(n_auto == 1, "only one auto output")
  -- link it outside
  local sink = model.add_node(p8, { type = "output", item = "item/iron-gear-wheel", parent = p8.root, fixed = true, value = 1, x = 30 })
  local ext = model.add_link(p8, f.id, "o:" .. auto.id, sink.id, "in")
  solver.solve_all(p8)
  approx(p8.results.links[ext.id].flow, 1, "outside gets what it asks")
  approx(p8.results.nodes[gr.id].x, 2, "producer not changed by the auto output")
  -- not enough any more
  gr.value = 0.5
  solver.solve_all(p8)
  fo = p8.results.nodes[f.id].outs["o:" .. auto.id]
  assert(fo.produced < fo.demand, "short now")
  render.draw_factory(p8, p8.root)
  -- the item disappears inside: output stays while linked
  gr.recipe = "iron-plate" gr.machine = "stone-furnace"
  solver.solve_all(p8)
  assert(p8.nodes[auto.id], "kept while linked outside")
  approx(p8.results.nodes[f.id].outs["o:" .. auto.id].produced, 0, "nothing flows")
  -- unlink -> it goes away; the new plate surplus gets its own output
  p8.links[ext.id] = nil
  solver.solve_all(p8)
  assert(not p8.nodes[auto.id], "removed after unlinking")
  local plate_auto
  for _, c in pairs(model.children(p8, f.id)) do if c.auto and c.item == "item/iron-plate" then plate_auto = c end end
  assert(plate_auto, "new surplus output for plates")
  -- switching off removes unlinked auto outputs
  f.auto_outputs = nil
  solver.solve_all(p8)
  assert(not p8.nodes[plate_auto.id], "auto outputs removed when switched off")
  -- connected products with unused surplus get an auto output too; nested factory surplus counts
  local p9 = model.create_project("auto2")
  local fa = model.add_node(p9, { type = "factory", parent = p9.root, auto_outputs = true })
  local pl = model.add_node(p9, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = fa.id, fixed = true, value = 2 }) -- 3 gears/s
  local out = model.add_node(p9, { type = "output", item = "item/iron-gear-wheel", parent = fa.id, fixed = false })
  model.add_link(p9, pl.id, "item/iron-gear-wheel", out.id, "in")
  local sink9 = model.add_node(p9, { type = "output", item = "item/iron-gear-wheel", parent = p9.root, fixed = true, value = 1 })
  model.add_link(p9, fa.id, "o:" .. out.id, sink9.id, "in")
  solver.solve_all(p9)
  local a9
  for _, c in pairs(model.children(p9, fa.id)) do if c.auto then a9 = c end end
  assert(a9, "auto output for a connected product with surplus")
  approx(p9.results.nodes[fa.id].outs["o:" .. a9.id].produced, 2, "its surplus is 2")
  approx(p9.results.nodes[fa.id].outs["o:" .. out.id].produced, 1, "the linked OUT still gets 1")
  -- 'only unconnected' option removes it again (nothing linked outside)
  fa.auto_outputs_unlinked = true
  solver.solve_all(p9)
  assert(not p9.nodes[a9.id], "only-unconnected mode skips connected products")
  fa.auto_outputs_unlinked = nil fa.auto_outputs = nil
  solver.solve_all(p9)
  -- OUT block = lowest priority: the ordinary consumer is served first, OUT gets the rest
  local cons = model.add_node(p9, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = fa.id, fixed = true, value = 1 }) -- needs 1.5 gears/s
  model.add_link(p9, pl.id, "item/iron-gear-wheel", cons.id, "item/iron-gear-wheel")
  sink9.value = 5 -- outside wants more than there is
  solver.solve_all(p9)
  approx(p9.results.nodes[cons.id].ins["item/iron-gear-wheel"].received, 1.5, "consumer fully served")
  approx(p9.results.nodes[fa.id].outs["o:" .. out.id].produced, 1.5, "OUT gets the rest")
  approx(p9.results.nodes[sink9.id].ins["in"].received, 1.5, "outside receives only what really comes out")
  -- surplus deep inside a nested factory comes out through the OUT block that is already linked
  local pA = model.create_project("nested")
  local outer = model.add_node(pA, { type = "factory", parent = pA.root, auto_outputs = true })
  local inner = model.add_node(pA, { type = "factory", parent = outer.id })
  local prod = model.add_node(pA, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = inner.id, fixed = true, value = 2 }) -- 3/s
  local iout = model.add_node(pA, { type = "output", item = "item/iron-gear-wheel", parent = inner.id, fixed = false })
  model.add_link(pA, prod.id, "item/iron-gear-wheel", iout.id, "in")
  local user = model.add_node(pA, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = outer.id, fixed = true, value = 1 }) -- 1.5/s
  model.add_link(pA, inner.id, "o:" .. iout.id, user.id, "item/iron-gear-wheel")
  solver.solve_all(pA)
  local au
  for _, c in pairs(model.children(pA, outer.id)) do if c.auto and c.item == "item/iron-gear-wheel" then au = c end end
  assert(au, "auto output for the nested surplus")
  approx(pA.results.nodes[outer.id].outs["o:" .. au.id].produced, 1.5, "nested surplus reaches the outer factory output")
  approx(pA.results.nodes[user.id].ins["item/iron-gear-wheel"].received, 1.5, "consumer still served")
  -- regression: an auto output linked into another factory's input must deliver to the consumer behind that input
  do
    local pB = model.create_project("auto->in")
    local A = model.add_node(pB, { type = "factory", parent = pB.root, auto_outputs = true })
    local N = model.add_node(pB, { type = "factory", parent = A.id })
    local g = model.add_node(pB, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = N.id, fixed = true, value = 2 })
    local nout = model.add_node(pB, { type = "output", item = "item/iron-gear-wheel", parent = N.id, fixed = false })
    model.add_link(pB, g.id, "item/iron-gear-wheel", nout.id, "in")
    local cons = model.add_node(pB, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = A.id, fixed = true, value = 1 })
    model.add_link(pB, N.id, "o:" .. nout.id, cons.id, "item/iron-gear-wheel")
    local B = model.add_node(pB, { type = "factory", parent = pB.root })
    local IN = model.add_node(pB, { type = "input", item = "item/iron-gear-wheel", parent = B.id, fixed = false })
    local u = model.add_node(pB, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = B.id, fixed = false })
    local sink = model.add_node(pB, { type = "output", item = "item/iron-plate", parent = B.id, fixed = true, value = 0.25 })
    model.add_link(pB, u.id, "item/iron-plate", sink.id, "in")
    model.add_link(pB, IN.id, "out", u.id, "item/iron-gear-wheel")
    solver.solve_all(pB)
    local au
    for _, c in pairs(model.children(pB, A.id)) do if c.auto and c.item == "item/iron-gear-wheel" then au = c end end
    model.add_link(pB, A.id, "o:" .. au.id, B.id, "i:" .. IN.id)
    solver.solve_all(pB)
    approx(pB.results.nodes[u.id].ins["item/iron-gear-wheel"].received, 0.5, "consumer behind the input gets the gears")
  end
  print("auto outputs OK")
end

-- electricity: own plants first, then the outer factory
do
  local pp = model.create_project("power")
  local F = model.add_node(pp, { type = "factory", parent = pp.root })
  -- 10 assembler-2 (150 kW each) inside F = 1.5 MW
  local asm = model.add_node(pp, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = F.id, fixed = true, value = 10 })
  -- F has a plant with 1 steam engine (900 kW) fed by 1 boiler (60 steam/s) on coal + water input
  local P = model.add_node(pp, { type = "factory", parent = F.id, plant = true })
  local eng = model.add_node(pp, { type = "gen", entity = "steam-engine", parent = P.id, value = 1 })
  local boi = model.add_node(pp, { type = "gen", entity = "boiler", parent = P.id, value = 1 })
  local wat = model.add_node(pp, { type = "input", item = "fluid/water", parent = P.id, fixed = false })
  model.add_link(pp, wat.id, "out", boi.id, "fluid/water")
  model.add_link(pp, boi.id, "fluid/steam", eng.id, "fluid/steam")
  -- the root has a solar farm: 20 panels * 60 kW * 0.7 = 840 kW
  local R0 = model.add_node(pp, { type = "factory", parent = pp.root, plant = true })
  model.add_node(pp, { type = "gen", entity = "solar-panel", parent = R0.id, value = 20 })
  solver.solve_all(pp)
  local res = pp.results
  approx(res.nodes[asm.id].power, 1.5e6, "assemblers draw 1.5 MW")
  approx(res.nodes[eng.id].power_cap, 900e3, "steam engine gives 900 kW")
  approx(res.nodes[boi.id].ins["item/coal"].need, 1.8e6 / 4e6, "boiler burns coal")
  local fp = res.nodes[F.id].power
  approx(fp.cap, 900e3, "F's own plant")
  approx(fp.unmet, 600e3, "600 kW taken from the outer factory")
  approx(res.nodes[P.id].power.plant_load, 1, "F's plant fully loaded")
  local rp = res.nodes[pp.root].power
  approx(rp.cap, 840e3, "root solar")
  approx(rp.unmet, 0, "outer covers the rest")
  approx(res.nodes[R0.id].power.plant_load, 600 / 840, "solar load")
  -- no steam -> engine gives nothing
  for id, l in pairs(pp.links) do if l.to.node == eng.id then pp.links[id] = nil end end
  solver.solve_all(pp)
  approx(pp.results.nodes[eng.id].power_cap, 0, "engine without steam")
  approx(pp.results.nodes[pp.root].power.unmet, 1.5e6 - 840e3, "deficit at the top")
  local sum = solver.summary(pp, pp.root)
  approx(sum.power_unmet, 1.5e6 - 840e3, "summary deficit")
  local saved_p, saved_f = ps.project, ps.factory
  ps.project, ps.factory = pp.id, pp.root
  gui.refresh_all(player, ps)
  update_dummy = nil
  render.draw_factory(pp, pp.root)
  render.draw_factory(pp, P.id)
  for _, id in pairs({ eng.id, P.id, F.id, boi.id }) do ps.selection = { [id] = true } gui.refresh_inspector(player, ps) end
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "add_plant" } }, button = 1 })
  handlers.on_gui_elem_changed({ player_index = 1, element = { valid = true, tags = { fm = "add_gen" }, elem_value = "steam-engine" } })
  local gens = 0
  for _, n in pairs(pp.nodes) do if n.type == "gen" then gens = gens + 1 end end
  assert(gens == 4, "generator added from the sidebar")
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = false, tags = { fm = "is_plant", node = P.id } } })
  assert(not P.plant, "plant flag off")
  ps.project, ps.factory = saved_p, saved_f
  print("power OK")
end

-- mining productivity research
do
  local pm = model.create_project("mining")
  local mn = model.add_node(pm, { type = "recipe", recipe = "mine:iron-ore", parent = pm.root, fixed = false })
  local sk = model.add_node(pm, { type = "output", item = "item/iron-ore", parent = pm.root, fixed = true, value = 2 })
  model.add_link(pm, mn.id, "item/iron-ore", sk.id, "in")
  solver.solve_all(pm)
  approx(pm.results.nodes[mn.id].x, 4, "4 drills without research")
  game.forces.player.mining_drill_productivity_bonus = 0.2
  handlers.on_research_finished({ research = { force = game.forces.player } })
  approx(pm.results.nodes[mn.id].x, 2 / (0.5 * 1.2), "fewer drills with +20%")
  mn.prod = 10 -- modules on top
  solver.solve_all(pm)
  approx(pm.results.nodes[mn.id].x, 2 / (0.5 * 1.3), "research + manual bonus add up")
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = false, tags = { fm = "use_research" } } })
  approx(pm.results.nodes[mn.id].x, 2 / (0.5 * 1.1), "research switched off")
  handlers.on_gui_checked_state_changed({ player_index = 1, element = { valid = true, state = true, tags = { fm = "use_research" } } })
  -- assemblers are not affected
  local ga = model.add_node(pm, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = pm.root, fixed = true, value = 1 })
  solver.solve_all(pm)
  approx(pm.results.nodes[ga.id].outs["item/iron-gear-wheel"].produced, 1.5, "recipes unaffected")
  local saved_p = ps.project
  ps.project, ps.factory = pm.id, pm.root
  ps.selection = { [mn.id] = true }
  gui.refresh_inspector(player, ps)
  ps.project, ps.factory = saved_p, storage.projects[saved_p] and storage.projects[saved_p].root
  game.forces.player.mining_drill_productivity_bonus = 0
  print("mining research OK")
end

-- wireless links inside a factory
do
  local pw = model.create_project("wireless")
  local F = model.add_node(pw, { type = "factory", parent = pw.root })
  local G = model.add_node(pw, { type = "factory", parent = pw.root })
  local saved_p, saved_f = ps.project, ps.factory
  local prod = model.add_node(pw, { type = "recipe", recipe = "iron-gear-wheel", machine = "assembling-machine-2", parent = F.id, fixed = false })
  local wo = model.add_node(pw, { type = "wout", parent = F.id, channel = 7 })
  local wi = model.add_node(pw, { type = "win", parent = F.id, channel = 7 })
  local user = model.add_node(pw, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = F.id, fixed = true, value = 1 }) -- 1.5 gears/s
  -- link like the GUI does, so the wireless output takes the item
  ps.project, ps.factory = pw.id, F.id
  local function connect(a, ap, ad, b, bp, bd)
    local pa = model.find_port(pw, a, ap, ad)
    local pb = model.find_port(pw, b, bp, bd)
    if a.type == "wout" or a.type == "win" then if not a.item then a.item = pb.item end end
    if b.type == "wout" or b.type == "win" then if not b.item then b.item = pa.item end end
    return model.add_link(pw, a.id, ap, b.id, bp)
  end
  connect(prod, "item/iron-gear-wheel", "out", wo, "in", "in")
  solver.solve_all(pw)
  assert(wi.item == "item/iron-gear-wheel", "wireless input took the item of its channel")
  model.add_link(pw, wi.id, "out", user.id, "item/iron-gear-wheel")
  solver.solve_all(pw)
  approx(pw.results.nodes[user.id].ins["item/iron-gear-wheel"].received, 1.5, "consumer fed without a wire")
  approx(pw.results.nodes[prod.id].x, 1.5 / 1.5, "producer pulled through the channel")
  -- another channel: nothing arrives
  wi.channel = 8
  solver.solve_all(pw)
  approx(pw.results.nodes[user.id].ins["item/iron-gear-wheel"].received, 0, "other channel: nothing")
  wi.channel = 7
  -- the same channel in another factory is not connected
  local wi2 = model.add_node(pw, { type = "win", parent = G.id, channel = 7, item = "item/iron-gear-wheel" })
  local user2 = model.add_node(pw, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = G.id, fixed = true, value = 1 })
  model.add_link(pw, wi2.id, "out", user2.id, "item/iron-gear-wheel")
  solver.solve_all(pw)
  approx(pw.results.nodes[user2.id].ins["item/iron-gear-wheel"].received, 0, "channels do not cross factories")
  approx(pw.results.nodes[user.id].ins["item/iron-gear-wheel"].received, 1.5, "own factory still fed")
  -- a second input on the channel shares
  local wi3 = model.add_node(pw, { type = "win", parent = F.id, channel = 7 })
  local user3 = model.add_node(pw, { type = "recipe", recipe = "gear-user", machine = "assembling-machine-2", parent = F.id, fixed = true, value = 2 })
  solver.solve_all(pw)
  model.add_link(pw, wi3.id, "out", user3.id, "item/iron-gear-wheel")
  solver.solve_all(pw)
  approx(pw.results.nodes[prod.id].x, (1.5 + 3) / 1.5, "producer feeds both inputs")
  approx(pw.results.nodes[user3.id].ins["item/iron-gear-wheel"].received, 3, "second input fed")
  -- GUI bits
  gui.refresh_all(player, ps)
  for _, id in pairs({ wo.id, wi.id }) do ps.selection = { [id] = true } gui.refresh_inspector(player, ps) end
  render.draw_factory(pw, F.id)
  handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "add_wout" } }, button = 1 })
  local newest
  for _, n in pairs(pw.nodes) do if n.type == "wout" and n.parent == F.id and n.id ~= wo.id then newest = n end end
  assert(newest and newest.channel == 1, "new wireless output gets a free channel, got " .. tostring(newest and newest.channel))
  handlers.on_gui_text_changed({ player_index = 1, element = { valid = true, text = "7", tags = { fm = "set_channel", node = newest.id } } })
  assert(newest.channel == 7, "channel edited")
  ps.project, ps.factory = saved_p, saved_f
  print("wireless OK")
end

-- fuel for burner furnaces
do
  local p7 = model.create_project("fuel")
  local fn = model.add_node(p7, { type = "recipe", recipe = "iron-plate", machine = "stone-furnace", parent = p7.root, fixed = true, value = 10 })
  solver.solve(p7)
  local coal = p7.results.nodes[fn.id].ins["item/coal"]
  assert(coal, "furnace has a coal input")
  approx(coal.need, 10 * 90000 / 4e6, "coal per second for 10 furnaces")
  local sum = solver.summary(p7, p7.root)
  approx(sum.missing["item/coal"], 10 * 90000 / 4e6, "coal shows up as import")
  approx(sum.power, 0, "burner furnaces use no electricity")
  fn.fuel = "wood"
  solver.solve(p7)
  approx(p7.results.nodes[fn.id].ins["item/wood"].need, 10 * 90000 / 2e6, "wood instead")
  fn.machine = "electric-furnace"
  solver.solve(p7)
  assert(p7.results.nodes[fn.id].ins["item/wood"] == nil, "electric furnace has no fuel input")
  print("fuel OK")
end

-- settings window + defaults
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "open_settings" } }, button = 1 })
assert(player.gui.screen.fm_settings, "settings window")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_default_machine", key = "crafting", name = "assembling-machine-1" } }, button = 1 })
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_default_belt", name = "fast-transport-belt" } }, button = 1 })
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "set_default_inserter", name = "inserter" } }, button = 1 })
local g3 = model.add_node(p3, { type = "recipe", recipe = "iron-gear-wheel", parent = p3.root })
assert(g3.machine == "assembling-machine-1", "new node uses default machine")
local thr = p3.results.nodes[g1.id].outs["item/iron-gear-wheel"].produced
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "apply_defaults" } }, button = 1 })
assert(g1.machine == "assembling-machine-1", "apply defaults")
approx(p3.results.nodes[g1.id].outs["item/iron-gear-wheel"].produced, thr, "fixed throughput kept")
approx(g1.value, 15, "machines scaled 10 * 0.75/0.5")
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "button", tags = { fm = "close_settings" } }, button = 1 })
assert(not player.gui.screen.fm_settings)
print("settings OK")
ps.project, ps.factory = project.id, project.root

-- delete project, close
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "delete_project" } }, button = 1 })
handlers.on_gui_click({ player_index = 1, element = { valid = true, name = "b", type = "sprite-button", tags = { fm = "close" } }, button = 1 })
assert(not gui.is_open(player), "closed")
handlers.on_lua_shortcut({ player_index = 1, prototype_name = "fm-shortcut" })
assert(gui.is_open(player), "reopened")
handlers.config()
print("render objects alive:", rendering.count())
print("ALL TESTS PASSED")
