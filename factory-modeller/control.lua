local model = require("scripts.model")
local solver = require("scripts.solver")
local render = require("scripts.render")
local gui = require("scripts.gui")
local mod_gui = require("mod-gui")

-------------------------------------------------------------------------------
-- State helpers
-------------------------------------------------------------------------------
local function pstate_of(player)
  storage.players = storage.players or {}
  local ps = storage.players[player.index]
  if not ps then
    ps = { selection = {}, views = {} }
    storage.players[player.index] = ps
  end
  ps.selection = ps.selection or {}
  if ps.block_input == nil then ps.block_input = true end
  return ps
end

local function ensure_project(ps)
  local project = ps.project and storage.projects[ps.project]
  if not project then
    local first
    for id, _ in pairs(storage.projects) do
      if not first or id < first then first = id end
    end
    project = first and storage.projects[first] or model.create_project()
    ps.project = project.id
    ps.factory = project.root
  end
  if not ps.factory or not project.nodes[ps.factory] or project.nodes[ps.factory].type ~= "factory" then
    ps.factory = project.root
  end
  return project
end

local function viewers_of(project)
  local list = {}
  for idx, ps in pairs(storage.players) do
    local p = game.get_player(idx)
    if p and p.valid and ps.project == project.id and gui.is_open(p) then list[#list + 1] = { player = p, ps = ps } end
  end
  return list
end

-- Re-solve the project and redraw what is visible.
local function update(project, opts)
  opts = opts or {}
  solver.solve_all(project)
  local drawn = {}
  for _, v in pairs(viewers_of(project)) do
    if not drawn[v.ps.factory] then
      render.draw_factory(project, v.ps.factory)
      drawn[v.ps.factory] = true
    end
    render.draw_overlay(v.player, v.ps, project, v.ps.factory)
    gui.refresh_handles(v.player, v.ps)
    gui.refresh_summary(v.player, v.ps)
    if not opts.keep_inspector or v.player.index ~= opts.keep_inspector then
      gui.refresh_inspector(v.player, v.ps)
    end
  end
  -- drop drawings of factories nobody is looking at
  for fid, _ in pairs(project.render or {}) do
    if not drawn[fid] then render.clear_factory(project, fid) end
  end
end

local function overlay(player, ps)
  local project = storage.projects[ps.project]
  render.draw_overlay(player, ps, project, ps.factory)
end

-------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------
-- Keep keyboard/mouse from reaching the character while the window is open:
-- switch to remote view (like the map). WASD/zoom then move the hidden map behind the window.
local function block_input(player, ps)
  if ps.block_input == false or ps.entered_remote then return end
  if player.controller_type ~= defines.controllers.character then return end
  ps.switching = true
  local ok = pcall(player.set_controller, { type = defines.controllers.remote, position = player.position, surface = player.surface })
  ps.switching = nil
  if ok and player.controller_type == defines.controllers.remote then ps.entered_remote = true end
end

local function unblock_input(player, ps)
  if not ps.entered_remote then return end
  ps.entered_remote = nil
  if player.controller_type == defines.controllers.remote then
    ps.switching = true
    pcall(player.exit_remote_view)
    ps.switching = nil
  end
end

local function set_pause(ps, paused)
  local ok = pcall(function() game.tick_paused = paused end)
  if ok then ps.paused_by_us = paused or nil end
end

local function open(player)
  local ps = pstate_of(player)
  local project = ensure_project(ps)
  if not gui.is_open(player) then
    block_input(player, ps)
    if ps.auto_pause and not game.tick_paused then set_pause(ps, true) end
  end
  gui.build(player, ps)
  player.set_shortcut_toggled("fm-shortcut", true)
  update(project)
end

local function close(player)
  local ps = pstate_of(player)
  gui.destroy(player)
  render.clear_overlay(ps)
  ps.pending_link, ps.press, ps.drag, ps.pan = nil, nil, nil, nil
  player.set_shortcut_toggled("fm-shortcut", false)
  unblock_input(player, ps)
  if ps.paused_by_us and game.tick_paused then set_pause(ps, false) end
  ps.paused_by_us = nil
  local project = storage.projects[ps.project]
  if project then update(project) end
end

local function toggle(player)
  if gui.is_open(player) then close(player) else open(player) end
end

local function switch_factory(player, ps, project, fid)
  if not project.nodes[fid] or project.nodes[fid].type ~= "factory" then return end
  ps.factory = fid
  ps.selection, ps.selected_link, ps.pending_link = {}, nil, nil
  gui.close_popup(player)
  gui.refresh_top(player, ps)
  gui.apply_view(player, ps)
  update(project)
end

-------------------------------------------------------------------------------
-- Coordinates
-------------------------------------------------------------------------------
local function local_pos(player, ps, loc)
  return gui.to_local(player, ps, loc)
end

-- blocks snap to whole tiles: with 1-tile port rows every port then sits on a whole tile too
local function snap(v) return math.floor(v + 0.5) end

-------------------------------------------------------------------------------
-- Node creation helpers
-------------------------------------------------------------------------------
local function view_center(ps)
  local v = gui.get_view(ps)
  return v.x - 3, v.y - 2
end

local function select_only(ps, id)
  ps.selection = {}
  if id then ps.selection[id] = true end
  ps.selected_link = nil
  ps.selected_anchor = nil
end

local function try_link(project, a, b)
  -- a, b: { node, port, dir, item }
  if a.node == b.node or a.dir == b.dir then return nil end
  local from, to = a, b
  if a.dir == "in" then from, to = b, a end
  local n1, n2 = project.nodes[from.node], project.nodes[to.node]
  if not n1 or not n2 or n1.parent ~= n2.parent then return nil end
  -- a splitter without an item takes the item of the first link
  local ADOPT = { split = true, psplit = true, wout = true, win = true }
  if ADOPT[n1.type] and not n1.item and to.item then n1.item = to.item from.item = to.item end
  if ADOPT[n2.type] and not n2.item and from.item then n2.item = from.item to.item = from.item end
  if from.item == nil or from.item ~= to.item then return nil end
  return model.add_link(project, from.node, from.port, to.node, to.port)
end

-- channel for a new wireless block: outputs get a free channel; inputs pick the channel of an
-- output carrying the same item (or the newest output), else 1
local function default_channel(project, factory_id, kind, item)
  if kind == "wout" then return model.free_channel(project, factory_id) end
  local best
  for _, n in pairs(project.nodes) do
    if n.parent == factory_id and n.type == "wout" then
      if item and n.item == item then
        if not best or best.item ~= item or n.id > best.id then best = n end
      elseif not best or (best.item ~= item and n.id > best.id) then
        best = n
      end
    end
  end
  return best and best.channel or 1
end

-- Create a node at local position pos, optionally connected to a pending port.
local function create_from_choice(player, ps, project, choice, pos, port)
  local node
  local x, y = snap(pos.x), snap(pos.y)
  if choice.kind == "recipe" then
    node = model.add_node(project, { type = "recipe", recipe = choice.recipe, parent = ps.factory, x = x, y = y, fixed = port == nil })
  elseif choice.kind == "split" or choice.kind == "psplit" then
    node = model.add_node(project, { type = choice.kind, item = choice.item, parent = ps.factory, x = x, y = y })
  elseif choice.kind == "wout" or choice.kind == "win" then
    node = model.add_node(project, { type = choice.kind, item = choice.item, parent = ps.factory, x = x, y = y,
      channel = default_channel(project, ps.factory, choice.kind, choice.item) })
  elseif choice.kind == "input" or choice.kind == "output" then
    -- an OUT block inside a factory starts in auto mode: it passes on whatever is left over
    node = model.add_node(project, { type = choice.kind, item = choice.item, parent = ps.factory, x = x, y = y,
      fixed = (port == nil and choice.kind == "output" and ps.factory == project.root) })
  end
  if not node then return end
  if port then
    -- position so that the node sits on the proper side
    if port.dir == "out" then node.x = x else node.x = x - render.layout(project, node).w end
    local ins, outs = model.visible_ports(project, node)
    local list = port.dir == "out" and ins or outs
    for _, p in pairs(list) do
      if p.item == port.item then
        try_link(project, port, { node = node.id, port = p.key, dir = port.dir == "out" and "in" or "out", item = p.item })
        break
      end
    end
  end
  select_only(ps, node.id)
  return node
end

local function open_port_picker(player, ps, project, port, loc, pos)
  local entries = {}
  local recipes = port.dir == "out" and model.recipes_consuming(port.item) or model.recipes_producing(port.item)
  local ctx = { port = port, pos = pos }
  ps.popup_ctx = ctx
  for _, rname in pairs(recipes) do
    local def = model.get_def(rname)
    if def then
      entries[#entries + 1] = { sprite = def.sprite, tooltip = def.localised_name, tags = { fm = "pick", kind = "recipe", recipe = rname } }
    end
  end
  local io = port.dir == "out" and "output" or "input"
  table.insert(entries, 1, {
    sprite = "utility/" .. (io == "input" and "import" or "export"),
    tooltip = { "fm." .. (io == "input" and "pick-input" or "pick-output") },
    tags = { fm = "pick", kind = io, item = port.item },
  })
  if not helpers.is_valid_sprite_path(entries[1].sprite) then entries[1].sprite = "utility/add" end
  -- wireless: from an output port send it away, into an input port receive it
  table.insert(entries, 2, { sprite = (port.dir == "out") and "item/radar" or "item/constant-combinator",
    tooltip = { (port.dir == "out") and "fm.pick-wout" or "fm.pick-win" }, tags = { fm = "pick", kind = (port.dir == "out") and "wout" or "win", item = port.item } })
  if not helpers.is_valid_sprite_path(entries[2].sprite) then entries[2].sprite = "utility/add" end
  if prototypes.entity["splitter"] then
    table.insert(entries, 3, { sprite = "entity/splitter", tooltip = { "fm.pick-split" }, tags = { fm = "pick", kind = "split", item = port.item } })
    local ps_sprite = prototypes.entity["fast-splitter"] and "entity/fast-splitter" or "entity/splitter"
    table.insert(entries, 4, { sprite = ps_sprite, tooltip = { "fm.pick-psplit" }, tags = { fm = "pick", kind = "psplit", item = port.item } })
  end
  gui.popup(player, loc, { "fm.picker-title", model.rich(port.item) }, entries, true)
end

local function open_node_menu(player, ps, project, node, loc)
  local entries = {}
  if node.type == "factory" then
    entries[#entries + 1] = { caption = { "fm.open" }, tags = { fm = "goto_factory", factory = node.id } }
    entries[#entries + 1] = { caption = { "fm.ungroup" }, tags = { fm = "ungroup", node = node.id } }
  end
  if node.type ~= "factory" then
    entries[#entries + 1] = { caption = node.fixed and { "fm.make-auto" } or { "fm.make-fixed" }, tags = { fm = "toggle_fixed", node = node.id } }
  end
  entries[#entries + 1] = { caption = { "fm.duplicate" }, tags = { fm = "duplicate_sel" } }
  entries[#entries + 1] = { caption = { "fm.delete" }, tags = { fm = "delete_sel" } }
  gui.popup(player, loc, nil, entries, false)
end

-------------------------------------------------------------------------------
-- Canvas interaction
-------------------------------------------------------------------------------
local function canvas_click(player, ps, project, pos, loc, e, forced_hit, from_handle)
  local hit = forced_hit or render.hit_test(project, ps.factory, pos)
  if hit and hit.kind == "node" and not forced_hit then
    local n = project.nodes[hit.node]
    local a = n and (n.type == "factory" or n.type == "psplit") and render.hit_arrow(project, n, pos)
    if a then
      local ok
      if n.type == "psplit" then ok = model.move_slot(n, a.slot, a.dir) else ok = model.move_port(project, n.id, a.child, a.dir) end
      if ok then update(project) end
      return
    end
  end
  gui.close_popup(player)
  local pl = ps.pending_link
  -- the wireless circle is its own port: clicking it while a link is pending connects to it
  if pl and hit and hit.kind == "node" then
    local wn = project.nodes[hit.node]
    if wn and (wn.type == "wout" or wn.type == "win") then
      local L = render.layout(project, wn)
      local p = (wn.type == "wout") and L.ins[1] or L.outs[1]
      hit = { kind = "port", node = wn.id, port = p.key, dir = (wn.type == "wout") and "in" or "out", item = wn.item or pl.item }
    end
  end
  if pl then
    ps.pending_link = nil
    if hit and hit.kind == "port" then
      local l = try_link(project, pl, hit)
      if l then update(project) return end
      if not (hit.node == pl.node and hit.port == pl.port) then
        ps.pending_link = hit -- start a new link from this port instead
      end
      overlay(player, ps)
      return
    elseif not hit then
      open_port_picker(player, ps, project, pl, loc, pos)
      overlay(player, ps)
      return
    end
  end
  if hit and hit.kind == "port" then
    ps.pending_link = hit
    overlay(player, ps)
    return
  end
  if hit and hit.kind == "node" then
    local last = ps.last_click
    if last and last.node == hit.node and game.ticks_played - last.tick <= 25 then
      ps.last_click = nil
      local n = project.nodes[hit.node]
      if n and n.type == "factory" then
        switch_factory(player, ps, project, n.id)
        return
      end
    else
      ps.last_click = { node = hit.node, tick = game.ticks_played }
    end
    if e.shift or e.control then
      ps.selected_link = nil
      if ps.selection[hit.node] then ps.selection[hit.node] = nil else ps.selection[hit.node] = true end
    else
      -- pressing an already selected block keeps the selection, so several blocks can be dragged together
      if not ps.selection[hit.node] then select_only(ps, hit.node) end
    end
  elseif hit and hit.kind == "link" then
    select_only(ps, nil)
    ps.selected_link = hit.link
  else
    if e.control and next(ps.selection) then
      -- move selection so that its top-left lands at the cursor
      local minx, miny = math.huge, math.huge
      for id, _ in pairs(ps.selection) do
        local n = project.nodes[id]
        if n then minx, miny = math.min(minx, n.x), math.min(miny, n.y) end
      end
      for id, _ in pairs(ps.selection) do
        local n = project.nodes[id]
        if n then n.x, n.y = snap(n.x - minx + pos.x), snap(n.y - miny + pos.y) end
      end
      update(project)
      return
    end
    select_only(ps, nil)
  end
  overlay(player, ps)
  gui.refresh_inspector(player, ps)
end

local function on_canvas_gui_click(e, player)
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project then return end
  local loc = e.cursor_display_location
  if ps.calibrating then
    ps.press = nil
    local cal = ps.calibrating
    if e.button ~= defines.mouse_button_type.left then
      ps.calibrating = nil
      overlay(player, ps)
      return
    end
    cal.clicks[#cal.clicks + 1] = { x = loc.x, y = loc.y }
    if #cal.clicks >= 2 then
      local a, b = cal.clicks[1], cal.clicks[2]
      local dx, dy = b.x - a.x, b.y - a.y
      if dx > 4 and dy > 4 then
        local pptx, ppty = dx / (2 * cal.d), dy / (2 * cal.d)
        -- screen position of the camera centre = point A + d tiles (A sits d tiles up-left of the centre)
        local x0 = a.x + cal.d * pptx
        local y0 = a.y + cal.d * ppty
        ps.calib = {
          kx = pptx / cal.zoom, ky = ppty / cal.zoom,
          ox = x0 - (ps.cam_px.x + ps.cam_px.w / 2), oy = y0 - (ps.cam_px.y + ps.cam_px.h / 2),
        }
        player.print({ "fm.calib-done" })
      else
        player.print({ "fm.calib-fail" })
      end
      ps.calibrating = nil
    end
    overlay(player, ps)
    return
  end
  local pos = local_pos(player, ps, loc)
  if not pos then return end
  if e.button == defines.mouse_button_type.right then
    ps.press = nil
    ps.pending_link = nil
    local hit = render.hit_test(project, ps.factory, pos)
    gui.close_popup(player)
    if hit and hit.kind == "link" then
      project.links[hit.link] = nil
      if ps.selected_link == hit.link then ps.selected_link = nil end
      update(project)
    elseif hit and (hit.kind == "node" or hit.kind == "port") then
      if not ps.selection[hit.node] then select_only(ps, hit.node) end
      overlay(player, ps)
      gui.refresh_inspector(player, ps)
      open_node_menu(player, ps, project, project.nodes[hit.node], loc)
    else
      overlay(player, ps)
    end
    return
  end
  if e.button ~= defines.mouse_button_type.left then return end
  canvas_click(player, ps, project, pos, loc, e)
end

-- put the canvas layer back to its home position.
-- Never call this while the layer itself may be held by the mouse.
local function reset_layer(player, ps)
  local layer = player.gui.screen.fm_layer
  if layer and ps.layer_origin then
    local l = layer.location
    if l and (l.x ~= ps.layer_origin.x or l.y ~= ps.layer_origin.y) then
      layer.location = ps.layer_origin
    end
    l = layer.location
    ps.layer_last = { x = l.x, y = l.y }
  end
end

-- click on a node's drag handle
local function on_handle_click(e, player, node_id)
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project or not project.nodes[node_id] then return end
  if ps.calibrating then return on_canvas_gui_click(e, player) end
  -- note: the game sends this "click" when the mouse button goes DOWN on a draggable element,
  -- so the handle under the mouse must not be re-created here or the drag is cancelled
  reset_layer(player, ps)
  local loc = e.cursor_display_location
  local pos = local_pos(player, ps, loc)
  if not pos then return end
  if e.button == defines.mouse_button_type.right then
    ps.pending_link = nil
    gui.close_popup(player)
    if not ps.selection[node_id] then select_only(ps, node_id) end
    overlay(player, ps)
    gui.refresh_inspector(player, ps)
    open_node_menu(player, ps, project, project.nodes[node_id], loc)
    return
  end
  if e.button ~= defines.mouse_button_type.left then return end
  -- up/down arrows on a factory's ports
  local node = project.nodes[node_id]
  if node.type == "factory" or node.type == "psplit" then
    local a = render.hit_arrow(project, node, pos)
    if a then
      local ok
      if node.type == "psplit" then ok = model.move_slot(node, a.slot, a.dir) else ok = model.move_port(project, node_id, a.child, a.dir) end
      if ok then update(project) end
      return
    end
  end
  canvas_click(player, ps, project, pos, loc, e, { kind = "node", node = node_id }, true)
end

-- native GUI dragging of the layer (pan) or of a node handle (move)
local function dbg(player, ps, ...)
  if ps and ps.debug then
    player.print({ "", "[FM] ", ... })
    log({ "", "[FM] ", ... })
  end
end

local function on_location_changed(e)
  local el = e.element
  if not el or not el.valid then return end
  do
    local p = game.get_player(e.player_index)
    local l = el.location
    if p then dbg(p, storage.players[e.player_index], "location_changed ", el.name or "?", " -> ", l and (l.x .. "," .. l.y) or "nil", " tick ", game.tick, "/", game.ticks_played) end
  end
  local tags = el.tags
  if not tags or not (tags.fm == "canvas" or tags.fm == "handle" or tags.fm == "anchor" or tags.fm == "label") then return end
  local player = game.get_player(e.player_index)
  if not player or not gui.is_open(player) then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project or not ps.cam_px then return end
  local loc = el.location
  if tags.fm == "anchor" or tags.fm == "label" then
    local l = project.links[tags.link]
    if not l then return end
    local key = tags.fm == "anchor" and ("a" .. l.id .. "_" .. tags.idx) or ("l" .. l.id)
    local off = ps.handle_off and ps.handle_off[key]
    if not off then return end
    local lp = local_pos(player, ps, loc)
    local tx, ty = lp.x - off.x, lp.y - off.y
    if tags.fm == "anchor" then
      local ap = l.points and l.points[tags.idx]
      if not ap then return end
      -- quarter-tile grid, then straighten: align with ports / neighbouring points if close
      local tol = 10 / (gui.ppt(player, gui.get_view(ps).zoom))
      tx, ty = render.snap_anchor(project, l, tags.idx, { x = snap(tx * 2) / 2, y = snap(ty * 2) / 2 }, math.max(tol, 0.3))
      if tx == ap.x and ty == ap.y then return end
      ap.x, ap.y = tx, ty
      ps.selection, ps.selected_link = {}, nil
      ps.selected_anchor = { link = l.id, idx = tags.idx }
    else
      local pts = render.link_points(project, l)
      if not pts then return end
      if (model.settings().label_mode or "free") == "along" then
        -- slide along the link
        local t = render.polyline_project(pts, { x = tx, y = ty })
        if l.label_t and math.abs(l.label_t - t) < 1e-4 then return end
        l.label_t = t
      else
        local mid = render.polyline_mid(pts)
        local ox, oy = snap(tx - mid.x), snap(ty - mid.y)
        if l.label_off and l.label_off.x == ox and l.label_off.y == oy then return end
        l.label_off = { x = ox, y = oy }
      end
      ps.selection, ps.selected_anchor = {}, nil
      ps.selected_link = l.id
    end
    ps.drag_skip = key
    update(project)
    ps.drag_skip = nil
    return
  end
  if tags.fm == "canvas" then
    -- incremental: only the movement since the previous event pans the view
    local last = ps.layer_last or { x = ps.cam_px.x, y = ps.cam_px.y }
    local dx, dy = loc.x - last.x, loc.y - last.y
    ps.layer_last = { x = loc.x, y = loc.y }
    if dx == 0 and dy == 0 then return end
    local v = gui.get_view(ps)
    local pptx, ppty = gui.ppt(player, v.zoom)
    v.x = v.x - dx / pptx
    v.y = v.y - dy / ppty
    gui.apply_view(player, ps) -- also re-creates the block handles above the layer
    return
  end
  local id = tags.node
  local n = project.nodes[id]
  local off = ps.handle_off and ps.handle_off[id]
  if not n or not off then return end
  -- the handle's corner moved to loc; the block's corner follows
  local lp = local_pos(player, ps, loc)
  local nx, ny = snap(lp.x - off.x), snap(lp.y - off.y)
  local dx, dy = nx - n.x, ny - n.y
  if dx == 0 and dy == 0 then return end
  if not ps.selection[id] then
    select_only(ps, id)
  end
  local ids = {}
  for sid, _ in pairs(ps.selection) do
    local sn = project.nodes[sid]
    if sn and sn.parent == n.parent then ids[sid] = true end
  end
  model.move_nodes(project, ids, dx, dy)
  for mid, _ in pairs(ids) do
    local mn = project.nodes[mid]
    if mn then mn.x, mn.y = snap(mn.x), snap(mn.y) end
  end
  ps.drag_skip = id -- keep the handle that is under the mouse
  update(project)
  ps.drag_skip = nil
end

local function on_wheel(e, dir)
  local player = game.get_player(e.player_index)
  if not player or not gui.is_open(player) then return end
  local el = e.element
  if not (el and el.valid) then return end
  local ft = el.tags and el.tags.fm
  if not (el.name == "fm_canvas" or ft == "canvas" or ft == "handle") then return end
  local ps = pstate_of(player)
  local before = local_pos(player, ps, e.cursor_display_location)
  reset_layer(player, ps)
  if not before then return end
  local v = gui.get_view(ps)
  local nz = v.zoom * (dir > 0 and 1.2 or 1 / 1.2)
  nz = math.max(gui.min_zoom(player), math.min(4, nz))
  local k = v.zoom / nz
  v.x = before.x - (before.x - v.x) * k
  v.y = before.y - (before.y - v.y) * k
  v.zoom = nz
  gui.apply_view(player, ps)
end

-------------------------------------------------------------------------------
-- GUI actions
-------------------------------------------------------------------------------
local function delete_selection(player, ps, project)
  local sa = ps.selected_anchor
  if sa then
    local l = project.links[sa.link]
    if l and l.points then table.remove(l.points, sa.idx) end
    ps.selected_anchor = nil
    update(project)
    return
  end
  if ps.selected_link then
    project.links[ps.selected_link] = nil
    ps.selected_link = nil
  end
  for id, _ in pairs(ps.selection) do
    local n = project.nodes[id]
    if n then model.delete_node(project, n) end
  end
  ps.selection = {}
  update(project)
end

local function selected_nodes(ps, project)
  local list = {}
  for id, _ in pairs(ps.selection) do
    local n = project.nodes[id]
    if n and n.parent == ps.factory then list[#list + 1] = n end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local actions = {}

actions.close = function(player) close(player) end
actions.toggle_window = function(player) toggle(player) end
actions.close_popup = function(player) gui.close_popup(player) end
actions.fit = function(player, ps) gui.fit(player, ps) end

actions.calibrate = function(player, ps, project)
  local _, _, _, cam = gui.elements(player)
  if not cam or not ps.cam_px then return end
  ps.pending_link, ps.press = nil, nil
  local v = gui.get_view(ps)
  local pptx = gui.ppt(player, v.zoom)
  local d = 0.25 * math.min(ps.cam_px.w, ps.cam_px.h) / pptx
  ps.calibrating = { d = d, zoom = v.zoom, clicks = {}, center = { x = v.x, y = v.y } }
  overlay(player, ps)
end

actions.calib_reset = function(player, ps)
  ps.calib = nil
  ps.calibrating = nil
  overlay(player, ps)
  player.print({ "fm.calib-reset" })
end

actions.new_project = function(player, ps)
  local project = model.create_project()
  ps.project, ps.factory = project.id, project.root
  ps.selection = {}
  for _, p in pairs(game.connected_players) do if gui.is_open(p) then gui.refresh_top(p, pstate_of(p)) end end
  gui.refresh_all(player, ps)
  update(project)
end

actions.delete_project = function(player, ps, project)
  render.clear_project(project)
  model.delete_project(project)
  ps.project = nil
  local np = ensure_project(ps)
  for _, p in pairs(game.connected_players) do
    local ops = pstate_of(p)
    if gui.is_open(p) then
      if ops.project == project.id then ops.project = nil ensure_project(ops) end
      gui.refresh_all(p, ops)
    end
  end
  update(np)
end

actions.goto_factory = function(player, ps, project, e)
  switch_factory(player, ps, project, e.tags.factory)
end

actions.add_psplit = function(player, ps, project)
  local x, y = view_center(ps)
  local n = model.add_node(project, { type = "psplit", parent = ps.factory, x = snap(x), y = snap(y) })
  select_only(ps, n.id)
  update(project)
end

actions.psplit_count = function(player, ps, project, e)
  local n = project.nodes[e.tags.node]
  if not n then return end
  local want = #n.slots + e.tags.delta
  if not model.set_slot_count(project, n, want) then
    player.print({ "fm.psplit-min", model.min_slots(project, n) })
    return
  end
  update(project)
end

actions.add_plant = function(player, ps, project)
  local x, y = view_center(ps)
  local n = model.add_node(project, { type = "factory", parent = ps.factory, x = snap(x), y = snap(y), plant = true })
  n.name = (player.locale and player.locale:sub(1, 2) == "ru") and "Электростанция" or "Power plant"
  select_only(ps, n.id)
  update(project)
end

local function add_wireless(player, ps, project, kind)
  local x, y = view_center(ps)
  local n = model.add_node(project, { type = kind, parent = ps.factory, x = snap(x), y = snap(y),
    channel = default_channel(project, ps.factory, kind, nil) })
  select_only(ps, n.id)
  update(project)
end
actions.add_wout = function(player, ps, project) add_wireless(player, ps, project, "wout") end
actions.add_win = function(player, ps, project) add_wireless(player, ps, project, "win") end

actions.add_split = function(player, ps, project)
  local x, y = view_center(ps)
  local n = model.add_node(project, { type = "split", parent = ps.factory, x = snap(x), y = snap(y) })
  select_only(ps, n.id)
  update(project)
end

local function update_all()
  for _, project in pairs(storage.projects) do update(project) end
  for _, p in pairs(game.connected_players) do
    if gui.is_open(p) then
      local ops = pstate_of(p)
      gui.refresh_top(p, ops)
      gui.refresh_summary(p, ops)
      gui.refresh_inspector(p, ops)
      if p.gui.screen.fm_settings then gui.settings_window(p, ops) end
    end
  end
end

actions.toggle_pause = function(player, ps)
  set_pause(ps, not game.tick_paused)
  for _, p in pairs(game.connected_players) do
    if gui.is_open(p) then gui.refresh_top(p, pstate_of(p), true) end
  end
end

actions.toggle_unit = function(player, ps, project)
  local st = model.settings()
  st.unit = (st.unit == "second") and "minute" or "second"
  update_all()
end

actions.open_settings = function(player, ps)
  if player.gui.screen.fm_settings then
    player.gui.screen.fm_settings.destroy()
  else
    gui.settings_window(player, ps)
  end
end

actions.close_settings = function(player)
  if player.gui.screen.fm_settings then player.gui.screen.fm_settings.destroy() end
end

actions.set_default_belt = function(player, ps, project, e)
  model.settings().belt = e.tags.name
  update_all()
end

actions.set_default_fuel = function(player, ps, project, e)
  model.settings().fuel = e.tags.name
  update_all()
end

actions.set_fuel = function(player, ps, project, e)
  local n = project.nodes[e.tags.node]
  if not n then return end
  n.fuel = e.tags.fuel
  update(project)
end

actions.set_default_inserter = function(player, ps, project, e)
  model.settings().inserter = e.tags.name
  update_all()
end

actions.set_default_machine = function(player, ps, project, e)
  model.settings().machines[e.tags.key] = e.tags.name
  update_all()
end

actions.apply_defaults = function(player, ps, project)
  for _, n in pairs(project.nodes) do
    if n.type == "recipe" then
      local def = model.get_def(n.recipe)
      local want = def and model.default_machine(def)
      if want and want ~= n.machine then
        local _, _, before = model.recipe_rates(n)
        n.machine = want
        local _, _, after = model.recipe_rates(n)
        if n.fixed and before and after and after > 0 then n.value = n.value * before / after end
      end
    end
  end
  for _, l in pairs(project.links) do l.belt = nil end
  update_all()
  player.print({ "fm.defaults-applied" })
end

actions.reset_anchors = function(player, ps, project, e)
  local l = project.links[e.tags.link]
  if l then l.points = nil end
  ps.selected_anchor = nil
  update(project)
end

actions.set_link_color = function(player, ps, project, e)
  local l = project.links[e.tags.link]
  if not l then return end
  l.color = nil
  for _, c in pairs(render.LINK_COLORS) do
    if c.name == e.tags.color then l.color = { r = c.color.r, g = c.color.g, b = c.color.b } end
  end
  update(project)
end

actions.reset_label = function(player, ps, project, e)
  local l = project.links[e.tags.link]
  if l then l.label_off, l.label_t = nil, nil end
  update(project)
end

actions.set_link_belt = function(player, ps, project, e)
  local l = project.links[e.tags.link]
  if not l then return end
  l.belt = e.tags.name -- nil = default
  update(project)
end

actions.add_factory = function(player, ps, project)
  local x, y = view_center(ps)
  local n = model.add_node(project, { type = "factory", parent = ps.factory, x = snap(x), y = snap(y) })
  select_only(ps, n.id)
  update(project)
end

actions.group = function(player, ps, project)
  local nodes = selected_nodes(ps, project)
  if #nodes == 0 then return end
  local g = model.group(project, nodes, ps.factory)
  select_only(ps, g.id)
  update(project)
end

actions.ungroup = function(player, ps, project, e)
  local id = e.tags.node
  local g = project.nodes[id]
  if not g then return end
  gui.close_popup(player)
  local moved = model.ungroup(project, g)
  ps.selection = {}
  for _, n in pairs(moved) do ps.selection[n.id] = true end
  -- anybody standing inside the removed factory goes up
  for _, p in pairs(game.connected_players) do
    local ops = pstate_of(p)
    if ops.project == project.id and not project.nodes[ops.factory] then
      ops.factory = project.root
      if gui.is_open(p) then gui.refresh_top(p, ops) gui.apply_view(p, ops) end
    end
  end
  update(project)
end

actions.duplicate_sel = function(player, ps, project)
  gui.close_popup(player)
  local nodes = selected_nodes(ps, project)
  if #nodes == 0 then return end
  local created = model.duplicate(project, nodes, 2, 2)
  ps.selection = {}
  for _, n in pairs(created) do ps.selection[n.id] = true end
  update(project)
end

actions.delete_sel = function(player, ps, project)
  gui.close_popup(player)
  delete_selection(player, ps, project)
end

actions.delete_link = function(player, ps, project, e)
  project.links[e.tags.link] = nil
  ps.selected_link = nil
  update(project)
end

actions.set_machine = function(player, ps, project, e)
  local n = project.nodes[e.tags.node]
  if not n then return end
  -- keep throughput when switching machines in fixed mode
  local _, _, before = model.recipe_rates(n)
  n.machine = e.tags.machine
  local _, _, after = model.recipe_rates(n)
  if n.fixed and before and after and after > 0 then n.value = n.value * before / after end
  -- a fuel input disappears when switching to an electric machine
  for id, l in pairs(project.links) do
    if l.to.node == n.id and not model.find_port(project, n, l.to.port, "in") then project.links[id] = nil end
  end
  update(project)
end

actions.toggle_fixed = function(player, ps, project, e)
  gui.close_popup(player)
  local n = project.nodes[e.tags.node]
  if not n then return end
  local r = project.results and project.results.nodes[n.id]
  n.fixed = not n.fixed
  if n.fixed and r then n.value = r.x end
  update(project)
end

actions.pick = function(player, ps, project, e)
  local ctx = ps.popup_ctx
  gui.close_popup(player)
  ps.popup_ctx = nil
  if not ctx then return end
  local t = e.tags
  create_from_choice(player, ps, project, { kind = t.kind, recipe = t.recipe, item = t.item }, ctx.pos, ctx.port)
  update(project)
end

local function on_gui_click(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local el = e.element
  if not el or not el.valid then return end
  if storage.players[e.player_index] and storage.players[e.player_index].debug then
    local par = el.parent
    dbg(player, storage.players[e.player_index], "click ", el.name or el.type, " in ", par and (par.name or par.type) or "-", " button ", e.button,
      " at ", e.cursor_display_location.x, ",", e.cursor_display_location.y)
  end
  local tags = el.tags
  local name = tags and tags.fm
  if el.name == "fm_canvas" or name == "canvas" then
    local ps = pstate_of(player)
    -- the layer gets this at mouse-DOWN and may be dragged right after: don't move it now
    if el.name == "fm_canvas" then reset_layer(player, ps) end
    local loc = e.cursor_display_location
    local cp = ps.cam_px
    if cp and (loc.x < cp.x or loc.y < cp.y or loc.x > cp.x + cp.w or loc.y > cp.y + cp.h) then return end
    on_canvas_gui_click(e, player)
    -- pressing the layer may bring it in front: put panels and block handles back on top
    if gui.is_open(player) then
      gui.raise_panels(player)
      gui.refresh_handles(player, ps)
    end
    return
  end
  if name == "handle" then
    on_handle_click(e, player, tags.node)
    return
  end
  if name == "anchor" or name == "label" then
    local ps = pstate_of(player)
    local project = storage.projects[ps.project]
    local l = project and project.links[tags.link]
    if not l then return end
    if ps.calibrating then return on_canvas_gui_click(e, player) end
    reset_layer(player, ps)
    -- a port under the label wins (short links put their label over the ports)
    local pos = local_pos(player, ps, e.cursor_display_location)
    local hit = pos and render.hit_test(project, ps.factory, pos)
    if hit and hit.kind == "port" then return on_canvas_gui_click(e, player) end
    gui.close_popup(player)
    if e.button == defines.mouse_button_type.right then
      if name == "anchor" then
        if l.points then table.remove(l.points, tags.idx) end
        ps.selected_anchor = nil
      else
        project.links[l.id] = nil
        ps.selected_link = nil
      end
      update(project)
      return
    end
    if e.button ~= defines.mouse_button_type.left then return end
    ps.selection, ps.pending_link = {}, nil
    if name == "anchor" then
      ps.selected_link = nil
      ps.selected_anchor = { link = l.id, idx = tags.idx }
    else
      ps.selected_anchor = nil
      ps.selected_link = l.id
    end
    overlay(player, ps)
    gui.refresh_inspector(player, ps)
    return
  end
  if gui.is_open(player) then reset_layer(player, pstate_of(player)) end
  if not name or not actions[name] then return end
  if el.type == "choose-elem-button" or el.type == "drop-down" or el.type == "textfield" or el.type == "switch" then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project and name ~= "close" and name ~= "new_project" and name ~= "toggle_window" then return end
  -- snapshot: the clicked element may be destroyed by the action (popups)
  local ev = { tags = tags, button = e.button, shift = e.shift, control = e.control, cursor_display_location = e.cursor_display_location }
  actions[name](player, ps, project, ev)
end

-------------------------------------------------------------------------------
-- Element changes
-------------------------------------------------------------------------------
local function on_elem_changed(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags or not el.tags.fm then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project then return end
  local t = el.tags
  local value = el.elem_value
  if t.fm == "add_gen" then
    if not value then return end
    el.elem_value = nil
    if not model.gen_info(value) then return end
    local x, y = view_center(ps)
    local node = model.add_node(project, { type = "gen", entity = value, parent = ps.factory, x = snap(x), y = snap(y), value = 1 })
    select_only(ps, node.id)
    update(project)
    return
  end
  if t.fm == "add_recipe" or t.fm == "add_mining" or t.fm == "add_io" then
    if not value then return end
    el.elem_value = nil
    local x, y = view_center(ps)
    local node
    if t.fm == "add_recipe" then
      node = model.add_node(project, { type = "recipe", recipe = value, parent = ps.factory, x = snap(x), y = snap(y), fixed = true })
    elseif t.fm == "add_mining" then
      node = model.add_node(project, { type = "recipe", recipe = "mine:" .. value, parent = ps.factory, x = snap(x), y = snap(y), fixed = true })
    else
      node = model.add_node(project, { type = t.io, item = t.t .. "/" .. value, parent = ps.factory, x = snap(x), y = snap(y),
        fixed = (t.io == "output" and ps.factory == project.root) })
    end
    select_only(ps, node.id)
    update(project)
  elseif t.fm == "set_recipe" or t.fm == "set_mining" then
    local n = project.nodes[t.node]
    if not n or not value then return end
    n.recipe = (t.fm == "set_mining") and ("mine:" .. value) or value
    local def = model.get_def(n.recipe)
    if not model.get_machine(def, n.machine) then n.machine = model.default_machine(def) end
    -- drop links that no longer fit
    for id, l in pairs(project.links) do
      if (l.from.node == n.id and not model.find_port(project, n, l.from.port, "out"))
        or (l.to.node == n.id and not model.find_port(project, n, l.to.port, "in")) then
        project.links[id] = nil
      end
    end
    update(project)
  elseif t.fm == "set_item" then
    local n = project.nodes[t.node]
    if not n or not value then return end
    n.item = t.t .. "/" .. value
    for id, l in pairs(project.links) do
      if l.from.node == n.id or l.to.node == n.id
        or (n.parent and (l.to.port == "i:" .. n.id or l.from.port == "o:" .. n.id)) then
        project.links[id] = nil
      end
    end
    update(project)
  end
end

local function parse(el)
  local v = tonumber(el.text)
  if not v or v ~= v or v < 0 then return nil end
  return v
end

local function on_text_changed(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags or not el.tags.fm then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project then return end
  local t = el.tags
  if t.fm == "rename_project" then
    if el.text ~= "" then
      project.name = el.text
      local root = project.nodes[project.root]
      if root then root.name = el.text end
      for _, p in pairs(game.connected_players) do
        if gui.is_open(p) then gui.refresh_top(p, pstate_of(p), p == player) end
      end
    end
    return
  end
  if t.fm == "set_channel" then
    local n = project.nodes[t.node]
    local v = tonumber(el.text)
    if n and v and v >= 0 then
      n.channel = math.floor(v)
      if n.type == "win" then
        -- take the item of the new channel unless links already fix it
        local linked = false
        for _, l in pairs(project.links) do if l.from.node == n.id then linked = true end end
        if not linked then n.item = nil end
      end
      update(project, { keep_inspector = player.index })
    end
    return
  end
  if t.fm == "psplit_count_set" then
    local n = project.nodes[t.node]
    local v = tonumber(el.text)
    if n and v and v >= 1 then
      if model.set_slot_count(project, n, v) then
        update(project, { keep_inspector = player.index })
      end
    end
    return
  end
  if t.fm == "rename_factory" then
    local n = project.nodes[t.node]
    if n then
      n.name = el.text
      update(project, { keep_inspector = player.index })
      gui.refresh_top(player, ps)
    end
    return
  end
  local n = project.nodes[t.node or -1]
  if not n then return end
  local v = parse(el)
  if not v then return end
  local mul = render.unit()
  if t.fm == "set_value" then
    n.fixed, n.value = true, v
  elseif t.fm == "set_target" then
    if t.per and t.per > 0 then n.fixed, n.value = true, (v / mul) / t.per end
  elseif t.fm == "set_speed" then
    n.speed = v
  elseif t.fm == "set_prod" then
    n.prod = v
  elseif t.fm == "set_rate" then
    n.fixed, n.value = true, v / mul
  else
    return
  end
  update(project, { keep_inspector = player.index })
end

local function on_confirmed(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags or not el.tags.fm then return end
  local ps = pstate_of(player)
  if el.tags.fm == "psplit_count_set" then
    local project = storage.projects[ps.project]
    local n = project and project.nodes[el.tags.node]
    local v = tonumber(el.text)
    if n and v and math.floor(v) ~= #n.slots and not model.set_slot_count(project, n, v) then
      player.print({ "fm.psplit-min", model.min_slots(project, n) })
    end
  end
  if storage.projects[ps.project] then gui.refresh_inspector(player, ps) end
end

local function on_switch(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags or el.tags.fm ~= "set_fixed" then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  local n = project and project.nodes[el.tags.node]
  if not n then return end
  local r = project.results and project.results.nodes[n.id]
  n.fixed = el.switch_state == "right"
  if n.fixed and r and r.x > 0 then n.value = r.x end
  update(project)
end

local function on_selection(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags then return end
  if el.tags.fm == "psplit_overflow" then
    local ps = pstate_of(player)
    local project = storage.projects[ps.project]
    local n = project and project.nodes[el.tags.node]
    if not n then return end
    local idx = el.selected_index
    n.overflow = (idx and idx > 1) and n.slots[idx - 1] or nil
    update(project)
    return
  end
  if el.tags.fm ~= "select_project" then return end
  local ps = pstate_of(player)
  local id = el.tags.ids and el.tags.ids[el.selected_index]
  if not id or not storage.projects[id] then return end
  ps.project = id
  ps.factory = storage.projects[id].root
  ps.selection, ps.selected_link, ps.pending_link = {}, nil, nil
  gui.refresh_all(player, ps)
  update(storage.projects[id])
end

script.on_event({ "fm-dbg-press", "fm-dbg-release" }, function(e)
  local ps = storage.players and storage.players[e.player_index]
  if not ps or not ps.debug then return end
  local player = game.get_player(e.player_index)
  local el = e.element
  local name = el and el.valid and (el.name ~= "" and el.name or el.type) or "-"
  local par = el and el.valid and el.parent
  dbg(player, ps, e.input_name, " on ", name, " in ", par and (par.name ~= "" and par.name or par.type) or "-", " in_gui ", tostring(e.in_gui),
    " at ", e.cursor_display_location.x, ",", e.cursor_display_location.y, " tick ", game.tick, "/", game.ticks_played)
end)

-- middle mouse button on a link: add an anchor there
script.on_event("fm-middle", function(e)
  local player = game.get_player(e.player_index)
  if not player or not gui.is_open(player) then return end
  local el = e.element
  if not (el and el.valid) then return end
  local ft = el.tags and el.tags.fm
  if not (el.name == "fm_canvas" or ft == "canvas" or ft == "handle" or ft == "label" or ft == "anchor") then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if not project then return end
  local pos = local_pos(player, ps, e.cursor_display_location)
  if not pos then return end
  local l
  if ft == "label" then l = project.links[el.tags.link] end
  l = l or render.nearest_link(project, ps.factory, pos, 0.6)
  if not l then return end
  local gap = render.anchor_insert_index(project, l, pos)
  if not gap then return end
  l.points = l.points or {}
  table.insert(l.points, gap, { x = snap(pos.x * 2) / 2, y = snap(pos.y * 2) / 2 })
  local tol = 10 / (gui.ppt(player, gui.get_view(ps).zoom))
  local sx, sy = render.snap_anchor(project, l, gap, l.points[gap], math.max(tol, 0.3))
  l.points[gap].x, l.points[gap].y = sx, sy
  ps.selection, ps.selected_link = {}, nil
  ps.selected_anchor = { link = l.id, idx = gap }
  update(project)
end)

-------------------------------------------------------------------------------
-- /fm-debug: visible block handles + event log in chat
-------------------------------------------------------------------------------
commands.add_command("fm-debug", { "fm.debug-help" }, function(cmd)
  local player = cmd.player_index and game.get_player(cmd.player_index)
  if not player then return end
  local ps = pstate_of(player)
  ps.debug = not ps.debug
  player.print({ "", "[FM] debug ", ps.debug and "ON" or "OFF" })
  if ps.debug then
    local res = player.display_resolution
    player.print({ "", "[FM] resolution ", res.width, "x", res.height, " scale ", player.display_scale,
      " controller ", player.controller_type, " paused ", tostring(game.tick_paused) })
    if ps.cam_px then
      player.print({ "", "[FM] canvas px ", ps.cam_px.x, ",", ps.cam_px.y, " ", ps.cam_px.w, "x", ps.cam_px.h })
    end
    if ps.calib then
      player.print({ "", "[FM] calib kx ", string.format("%.2f", ps.calib.kx), " ky ", string.format("%.2f", ps.calib.ky),
        " ox ", string.format("%.1f", ps.calib.ox), " oy ", string.format("%.1f", ps.calib.oy) })
    end
    local layer = player.gui.screen.fm_layer
    if layer then player.print({ "", "[FM] layer at ", layer.location.x, ",", layer.location.y }) end
    local count = 0
    for _, ch in pairs(player.gui.screen.children) do
      if ch.name and ch.name:sub(1, 5) == "fm_h_" then
        count = count + 1
        if count <= 3 then
          player.print({ "", "[FM] handle ", ch.name, " at ", ch.location.x, ",", ch.location.y, " size ", ch.style.minimal_width or "?", "x", ch.style.minimal_height or "?" })
        end
      end
    end
    player.print({ "", "[FM] handles: ", count })
  end
  if gui.is_open(player) then gui.refresh_handles(player, ps) end
end)

-------------------------------------------------------------------------------
-- Top-left button (like Helmod)
-------------------------------------------------------------------------------
local function update_top_button(player)
  local flow = mod_gui.get_button_flow(player)
  local show = settings.get_player_settings(player)["fm-show-top-button"].value
  local b = flow.fm_top_button
  if show and not b then
    flow.add({
      type = "sprite-button", name = "fm_top_button", style = mod_gui.button_style,
      sprite = "entity/assembling-machine-2", tooltip = { "fm.top-button-tt" }, tags = { fm = "toggle_window" },
    })
  elseif not show and b then
    b.destroy()
    -- remove the shared container if nobody else uses it
    local frame = player.gui.top.mod_gui_top_frame
    if frame and frame.mod_gui_inner_frame and #frame.mod_gui_inner_frame.children == 0 then frame.destroy() end
  end
end

local function update_all_top_buttons()
  for _, p in pairs(game.players) do update_top_button(p) end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
local function setup()
  model.init_storage()
  render.get_surface()
end

script.on_init(function()
  setup()
  update_all_top_buttons()
end)

script.on_event(defines.events.on_player_created, function(e)
  local p = game.get_player(e.player_index)
  if p then update_top_button(p) end
end)

script.on_configuration_changed(function()
  setup()
  update_all_top_buttons()
  for _, p in pairs(game.players) do
    if gui.is_open(p) then gui.destroy(p) end
    p.set_shortcut_toggled("fm-shortcut", false)
  end
  for idx, ps in pairs(storage.players) do
    ps.overlay = nil ps.press = nil ps.pan = nil ps.drag = nil
    local p = game.get_player(idx)
    if p then unblock_input(p, ps) end
    if ps.paused_by_us then game.tick_paused = false ps.paused_by_us = nil end
  end
  rendering.clear("factory-modeller")
  for _, project in pairs(storage.projects) do
    project.render = {}
    project.bg = {}
    for _, n in pairs(project.nodes) do
      n.x, n.y = math.floor((n.x or 0) + 0.5), math.floor((n.y or 0) + 0.5)
    end
    -- drop nodes whose prototypes are gone
    for _, n in pairs(project.nodes) do
      if n.type == "recipe" then
        local def = model.get_def(n.recipe)
        if def and not model.get_machine(def, n.machine) then n.machine = model.default_machine(def) end
      end
    end
    solver.solve_all(project)
  end
end)

-- research changes mining productivity: recalculate everything
local function on_research_changed(e)
  if e.research and e.research.force and e.research.force.name ~= "player" then return end
  for _, project in pairs(storage.projects or {}) do update(project) end
end
script.on_event({ defines.events.on_research_finished, defines.events.on_research_reversed }, on_research_changed)

script.on_event(defines.events.on_force_created, function(e)
  local s = game.surfaces[render.SURFACE]
  if s then e.force.set_surface_hidden(s, true) end
end)

script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name ~= "fm-shortcut" then return end
  local player = game.get_player(e.player_index)
  if player then toggle(player) end
end)

script.on_event("fm-toggle", function(e)
  local player = game.get_player(e.player_index)
  if player then toggle(player) end
end)

script.on_event(defines.events.on_gui_location_changed, on_location_changed)
script.on_event("fm-wheel-up", function(e) on_wheel(e, 1) end)
script.on_event({ "fm-pan-left", "fm-pan-right", "fm-pan-up", "fm-pan-down" }, function(e)
  local player = game.get_player(e.player_index)
  if not player or not gui.is_open(player) then return end
  if e.element and e.element.valid and e.element.type == "textfield" then return end
  local ps = pstate_of(player)
  if not ps.cam_px then return end
  local d = ({ ["fm-pan-left"] = { -1, 0 }, ["fm-pan-right"] = { 1, 0 }, ["fm-pan-up"] = { 0, -1 }, ["fm-pan-down"] = { 0, 1 } })[e.input_name]
  local project = storage.projects[ps.project]
  if project and next(ps.selection) then
    -- move the selected blocks by one tile
    local ids = {}
    for id, _ in pairs(ps.selection) do
      local n = project.nodes[id]
      if n and n.parent == ps.factory then ids[id] = true end
    end
    model.move_nodes(project, ids, d[1], d[2])
    update(project)
    return
  end
  local v = gui.get_view(ps)
  local step = 0.25 * ps.cam_px.w / gui.ppt(player, v.zoom)
  v.x, v.y = v.x + d[1] * step, v.y + d[2] * step
  gui.apply_view(player, ps)
end)
script.on_event("fm-wheel-down", function(e) on_wheel(e, -1) end)
script.on_event("fm-delete", function(e)
  local player = game.get_player(e.player_index)
  if not player or not gui.is_open(player) then return end
  -- don't steal Delete from text fields
  if e.element and e.element.valid and e.element.type == "textfield" then return end
  local ps = pstate_of(player)
  local project = storage.projects[ps.project]
  if project then delete_selection(player, ps, project) end
end)

script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_elem_changed, on_elem_changed)
script.on_event(defines.events.on_gui_text_changed, on_text_changed)
script.on_event(defines.events.on_gui_confirmed, on_confirmed)
script.on_event(defines.events.on_gui_switch_state_changed, on_switch)
script.on_event(defines.events.on_gui_selection_state_changed, on_selection)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local player = game.get_player(e.player_index)
  local el = e.element
  if not player or not el.valid or not el.tags then return end
  local ps = pstate_of(player)
  if el.tags.fm == "use_research" then
    model.settings().use_research = el.state
    for _, project in pairs(storage.projects) do update(project) end
    for _, p in pairs(game.connected_players) do
      if p.gui.screen.fm_settings then gui.settings_window(p, pstate_of(p)) end
    end
    return
  end
  if el.tags.fm == "is_plant" then
    local project = storage.projects[ps.project]
    local n = project and project.nodes[el.tags.node]
    if n then
      n.plant = el.state or nil
      update(project)
    end
    return
  end
  if el.tags.fm == "auto_outputs_unlinked" then
    local project = storage.projects[ps.project]
    local n = project and project.nodes[el.tags.node]
    if n then
      n.auto_outputs_unlinked = el.state or nil
      update(project)
    end
    return
  end
  if el.tags.fm == "auto_outputs" then
    local project = storage.projects[ps.project]
    local n = project and project.nodes[el.tags.node]
    if n then
      n.auto_outputs = el.state or nil
      update(project)
    end
    return
  end
  if el.tags.fm == "label_mode" then
    model.settings().label_mode = el.tags.mode
    for _, project in pairs(storage.projects) do update(project) end
    for _, p in pairs(game.connected_players) do
      if p.gui.screen.fm_settings then gui.settings_window(p, pstate_of(p)) end
    end
    return
  end
  if el.tags.fm == "link_style" then
    model.settings().link_style = el.tags.style
    for _, project in pairs(storage.projects) do update(project) end
    for _, p in pairs(game.connected_players) do
      if p.gui.screen.fm_settings then gui.settings_window(p, pstate_of(p)) end
    end
    return
  end
  if el.tags.fm == "auto_pause" then
    ps.auto_pause = el.state
  elseif el.tags.fm == "block_input" then
    ps.block_input = el.state
    if el.state then block_input(player, ps) else unblock_input(player, ps) end
    local top = player.gui.screen.fm_top
    if top then player.opened = top end
  end
end)

-- leaving remote view by hand (e.g. map key) closes the window so input is never half-blocked
script.on_event(defines.events.on_player_controller_changed, function(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local ps = pstate_of(player)
  if ps.switching or not ps.entered_remote then return end
  if player.controller_type ~= defines.controllers.remote then
    ps.entered_remote = nil
    if gui.is_open(player) then close(player) end
  end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  if e.element and e.element.valid and e.element.name == "fm_top" then
    if pstate_of(player).switching then return end
    close(player)
  end
end)

local function rebuild(e)
  local player = game.get_player(e.player_index)
  if player and gui.is_open(player) then open(player) end
end
script.on_event(defines.events.on_player_display_resolution_changed, rebuild)
script.on_event(defines.events.on_player_display_scale_changed, rebuild)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting == "fm-show-top-button" and e.player_index then
    local p = game.get_player(e.player_index)
    if p then update_top_button(p) end
    return
  end
  if e.setting == "fm-text-scale" then
    for _, project in pairs(storage.projects) do update(project) end
    for _, p in pairs(game.connected_players) do
      if gui.is_open(p) then gui.refresh_all(p, pstate_of(p)) end
    end
  end
end)

script.on_event(defines.events.on_player_removed, function(e)
  local ps = storage.players[e.player_index]
  if ps then render.clear_overlay(ps) end
  storage.players[e.player_index] = nil
end)

script.on_event(defines.events.on_player_left_game, function(e)
  local player = game.get_player(e.player_index)
  if player and gui.is_open(player) then close(player) end
end)
