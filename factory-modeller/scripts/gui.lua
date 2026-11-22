-- Window panels: top bar, left toolbox + summary, right inspector, canvas camera, popups.
local model = require("scripts.model")
local solver = require("scripts.solver")
local render = require("scripts.render")

local G = {}

G.TOP_H = 46
-- below this the camera switches to map (chart) rendering, where the canvas is black
G.MIN_ZOOM = 0.3
function G.min_zoom(player)
  local st = settings.get_player_settings(player)["fm-min-zoom"]
  return st and st.value or G.MIN_ZOOM
end
G.LEFT_W = 290
G.RIGHT_W = 330

local function R_fmt_raw(v)
  local s = string.format("%.4f", v or 0)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

local function T(key, ...) return { "fm." .. key, ... } end

local function screen(player) return player.gui.screen end

function G.elements(player)
  local s = screen(player)
  return s.fm_top, s.fm_left, s.fm_right, s.fm_canvas
end

function G.is_open(player)
  return screen(player).fm_top ~= nil
end

local function act(name, extra)
  local t = { fm = name }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function rate_unit_caption()
  local _, suffix = render.unit()
  return suffix
end

-------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------
function G.destroy(player)
  local s = screen(player)
  for _, name in pairs({ "fm_top", "fm_left", "fm_right", "fm_canvas", "fm_layer", "fm_popup", "fm_settings" }) do
    if s[name] then s[name].destroy() end
  end
  G.clear_handles(player)
end

function G.build(player, pstate)
  G.destroy(player)
  local s = screen(player)
  local res = player.display_resolution
  local sc = player.display_scale
  local m = 0 -- cover the whole screen (the map view used to block game input stays hidden behind)
  local W = res.width - 2 * m
  local H = res.height - 2 * m
  local top_px = math.floor(G.TOP_H * sc)
  local left_px = math.floor(G.LEFT_W * sc)
  local right_px = math.floor(G.RIGHT_W * sc)

  -- top bar
  local top = s.add({ type = "frame", name = "fm_top", direction = "horizontal" })
  top.location = { m, m }
  top.style.width = W / sc
  top.style.height = G.TOP_H
  top.style.top_padding = 6
  top.style.bottom_padding = 6
  local frame_top = top
  top = frame_top.add({ type = "flow", name = "bar", direction = "horizontal" })
  top.style.vertical_align = "center"
  top.style.horizontal_spacing = 8
  top.style.horizontally_stretchable = true
  local title = top.add({ type = "label", caption = T("title"), style = "frame_title" })
  title.ignored_by_interaction = true
  top.add({ type = "line", direction = "vertical" })
  top.add({ type = "drop-down", name = "fm_projects", tags = act("select_project") })
  top.add({ type = "sprite-button", sprite = "utility/add", style = "tool_button", tooltip = T("new-project"), tags = act("new_project") })
  top.add({ type = "textfield", name = "fm_project_name", tooltip = T("rename-project"), tags = act("rename_project") }).style.width = 160
  top.add({ type = "sprite-button", sprite = "utility/trash", style = "tool_button_red", tooltip = T("delete-project"), tags = act("delete_project") })
  top.add({ type = "line", direction = "vertical" })
  top.add({ type = "flow", name = "fm_crumbs", direction = "horizontal" }).style.vertical_align = "center"
  local filler = top.add({ type = "empty-widget" })
  filler.style.horizontally_stretchable = true
  top.add({ type = "button", name = "fm_pause", caption = "", tooltip = T("pause-tt"), tags = act("toggle_pause") })
  top.add({ type = "checkbox", name = "fm_auto_pause", state = pstate.auto_pause or false, caption = T("auto-pause"), tooltip = T("auto-pause-tt"), tags = act("auto_pause") })
  top.add({ type = "line", direction = "vertical" })
  top.add({ type = "button", name = "fm_unit", caption = "", tooltip = T("unit-tt"), tags = act("toggle_unit") })
  top.add({ type = "button", caption = T("settings"), tooltip = T("settings-tt"), tags = act("open_settings") })
  top.add({ type = "button", caption = T("calibrate"), tooltip = T("calibrate-tt"), tags = act("calibrate") })
  top.add({ type = "sprite-button", sprite = "utility/reset", style = "tool_button", tooltip = T("calib-reset-tt"), tags = act("calib_reset") })
  top.add({ type = "button", caption = T("fit"), tooltip = T("fit-tt"), tags = act("fit") })
  top.add({ type = "sprite-button", sprite = "utility/close", style = "close_button", tooltip = T("close"), tags = act("close") })

  -- left panel
  local panel_h = (H - top_px) / sc
  local left = s.add({ type = "frame", name = "fm_left", direction = "vertical" })
  left.location = { m, m + top_px }
  left.style.width = G.LEFT_W
  left.style.height = panel_h
  local lsp = left.add({ type = "scroll-pane", name = "scroll", direction = "vertical" })
  lsp.style.vertically_stretchable = true
  lsp.style.horizontally_stretchable = true

  local function section(parent, caption)
    local l = parent.add({ type = "label", caption = caption, style = "caption_label" })
    l.style.top_margin = 6
    return l
  end

  section(lsp, T("add"))
  local add_t = lsp.add({ type = "table", column_count = 2 })
  add_t.style.horizontal_spacing = 8
  add_t.style.vertical_spacing = 4
  add_t.add({ type = "choose-elem-button", elem_type = "recipe", elem_filters = { { filter = "hidden", invert = true } }, tags = act("add_recipe"), tooltip = T("add-recipe-tt") })
  add_t.add({ type = "label", caption = T("add-recipe") })
  add_t.add({ type = "choose-elem-button", elem_type = "entity", elem_filters = { { filter = "type", type = "resource" } }, tags = act("add_mining"), tooltip = T("add-mining-tt") })
  add_t.add({ type = "label", caption = T("add-mining") })
  local io_flow = lsp.add({ type = "flow", direction = "horizontal" })
  io_flow.add({ type = "choose-elem-button", elem_type = "item", tags = act("add_io", { io = "input", t = "item" }), tooltip = T("add-input-item") })
  io_flow.add({ type = "choose-elem-button", elem_type = "fluid", tags = act("add_io", { io = "input", t = "fluid" }), tooltip = T("add-input-fluid") })
  io_flow.add({ type = "label", caption = T("add-input") }).style.width = 60
  local io_flow2 = lsp.add({ type = "flow", direction = "horizontal" })
  io_flow2.add({ type = "choose-elem-button", elem_type = "item", tags = act("add_io", { io = "output", t = "item" }), tooltip = T("add-output-item") })
  io_flow2.add({ type = "choose-elem-button", elem_type = "fluid", tags = act("add_io", { io = "output", t = "fluid" }), tooltip = T("add-output-fluid") })
  io_flow2.add({ type = "label", caption = T("add-output") })
  local af = lsp.add({ type = "flow", direction = "horizontal" })
  af.add({ type = "button", caption = T("add-split"), tooltip = T("add-split-tt"), tags = act("add_split") })
  lsp.add({ type = "button", caption = T("add-psplit"), tooltip = T("add-psplit-tt"), tags = act("add_psplit") }).style.horizontally_stretchable = true
  local wf = lsp.add({ type = "flow", direction = "horizontal" })
  wf.add({ type = "button", caption = T("add-wout"), tooltip = T("add-wireless-tt"), tags = act("add_wout") })
  wf.add({ type = "button", caption = T("add-win"), tooltip = T("add-wireless-tt"), tags = act("add_win") })
  local pf = lsp.add({ type = "flow", direction = "horizontal" })
  pf.style.vertical_align = "center"
  pf.add({ type = "button", caption = T("add-plant"), tooltip = T("add-plant-tt"), tags = act("add_plant") })
  pf.add({ type = "choose-elem-button", elem_type = "entity", tooltip = T("add-gen-tt"), tags = act("add_gen"),
    elem_filters = { { filter = "type", type = "generator" }, { filter = "type", type = "boiler" }, { filter = "type", type = "solar-panel" }, { filter = "type", type = "offshore-pump" } } })
  pf.add({ type = "label", caption = T("add-gen") })
  af.add({ type = "button", caption = T("add-factory"), tooltip = T("add-factory-tt"), tags = act("add_factory") })

  section(lsp, T("selection"))
  local sel = lsp.add({ type = "flow", direction = "horizontal" })
  sel.add({ type = "button", caption = T("group"), tooltip = T("group-tt"), tags = act("group") })
  sel.add({ type = "button", caption = T("duplicate"), tags = act("duplicate_sel") })
  sel.add({ type = "sprite-button", sprite = "utility/trash", style = "tool_button_red", tooltip = T("delete-sel"), tags = act("delete_sel") })

  section(lsp, T("summary"))
  lsp.add({ type = "flow", name = "fm_summary", direction = "vertical" })

  section(lsp, T("help"))
  local help = lsp.add({ type = "label", caption = T("help-text") })
  help.style.single_line = false
  help.style.width = G.LEFT_W - 30

  -- right panel (inspector)
  local right = s.add({ type = "frame", name = "fm_right", direction = "vertical" })
  right.location = { m + W - right_px, m + top_px }
  right.style.width = G.RIGHT_W
  right.style.height = panel_h
  right.add({ type = "label", caption = T("inspector"), style = "caption_label" })
  local rsp = right.add({ type = "scroll-pane", name = "scroll", direction = "vertical" })
  rsp.style.vertically_stretchable = true
  rsp.style.horizontally_stretchable = true

  -- canvas
  local project = storage.projects[pstate.project]
  local fnode = project and project.nodes[pstate.factory]
  local view = G.get_view(pstate)
  local off = model.region_offset(fnode and fnode.region or 1)
  local cam = s.add({
    type = "camera", name = "fm_canvas",
    position = { off.x + view.x, off.y + view.y },
    surface_index = render.get_surface().index,
    zoom = view.zoom,
  })
  local cam_x, cam_y = m + left_px, m + top_px
  local cam_w, cam_h = W - left_px - right_px, H - top_px
  cam.location = { cam_x, cam_y }
  cam.style.width = cam_w / sc
  cam.style.height = cam_h / sc
  pstate.cam_px = { x = cam_x, y = cam_y, w = cam_w, h = cam_h }
  pstate.panned, pstate.dragged_node, pstate.pan_tick = nil, nil, nil

  -- invisible draggable layer under the blocks: receives clicks and pans the view when dragged.
  -- It is much larger than the canvas so it can drift while dragging without leaving gaps;
  -- the side panels are kept above it.
  local margin = math.max(cam_w, cam_h)
  pstate.layer_origin = { x = cam_x - margin, y = cam_y - margin }
  pstate.layer_last = { x = pstate.layer_origin.x, y = pstate.layer_origin.y }
  local layer = s.add({ type = "frame", name = "fm_layer", style = "invisible_frame", tags = act("canvas") })
  layer.location = pstate.layer_origin
  layer.style.width = (cam_w + 2 * margin) / sc
  layer.style.height = (cam_h + 2 * margin) / sc
  local grip = layer.add({ type = "empty-widget", name = "grip", tags = act("canvas") })
  grip.style.width = (cam_w + 2 * margin) / sc
  grip.style.height = (cam_h + 2 * margin) / sc
  grip.drag_target = layer
  G.raise_panels(player)

  player.opened = frame_top
  G.refresh_all(player, pstate)
end

-- keep the panels and windows above the canvas layer
function G.raise_panels(player)
  local s = screen(player)
  for _, name in pairs({ "fm_top", "fm_left", "fm_right", "fm_settings", "fm_popup" }) do
    if s[name] then s[name].bring_to_front() end
  end
end

-------------------------------------------------------------------------------
-- Views
-------------------------------------------------------------------------------
function G.get_view(pstate)
  pstate.views = pstate.views or {}
  local key = (pstate.project or 0) .. ":" .. (pstate.factory or 0)
  local v = pstate.views[key]
  if not v then
    v = { x = 10, y = 6, zoom = 0.75 }
    pstate.views[key] = v
  end
  return v
end

function G.apply_view(player, pstate)
  local _, _, _, cam = G.elements(player)
  if not cam then return end
  local project = storage.projects[pstate.project]
  local fnode = project and project.nodes[pstate.factory]
  if not fnode then return end
  local v = G.get_view(pstate)
  if v.zoom < G.min_zoom(player) then v.zoom = G.min_zoom(player) end
  local off = model.region_offset(fnode.region)
  cam.position = { off.x + v.x, off.y + v.y }
  cam.zoom = v.zoom
  -- make sure the visible area has (lab tile) chunks
  local ppt = G.ppt(player, v.zoom)
  local tiles = math.max(pstate.cam_px.w, pstate.cam_px.h) / ppt
  local radius = math.min(10, math.ceil(tiles / 64) + 1)
  render.get_surface().request_to_generate_chunks({ off.x + v.x, off.y + v.y }, radius)
  G.refresh_handles(player, pstate)
end

-- pixels per tile on the canvas (x, y); uses the player's calibration when present
-------------------------------------------------------------------------------
-- Screen <-> canvas (factory-local) coordinates
-------------------------------------------------------------------------------
local function mapping(player, pstate)
  local cam = screen(player).fm_canvas
  local project = storage.projects[pstate.project]
  if not cam or not project or not pstate.cam_px then return nil end
  local fnode = project.nodes[pstate.factory]
  if not fnode then return nil end
  local off = model.region_offset(fnode.region)
  local pptx, ppty = G.ppt(player, cam.zoom)
  local c = pstate.calib or {}
  local cp = cam.position
  return {
    cx = pstate.cam_px.x + pstate.cam_px.w / 2 + (c.ox or 0),
    cy = pstate.cam_px.y + pstate.cam_px.h / 2 + (c.oy or 0),
    vx = cp.x - off.x, vy = cp.y - off.y, pptx = pptx, ppty = ppty,
  }
end

function G.to_local(player, pstate, loc)
  local m = mapping(player, pstate)
  if not m then return nil end
  return { x = m.vx + (loc.x - m.cx) / m.pptx, y = m.vy + (loc.y - m.cy) / m.ppty }
end

function G.to_screen(player, pstate, p)
  local m = mapping(player, pstate)
  if not m then return nil end
  return { x = m.cx + (p.x - m.vx) * m.pptx, y = m.cy + (p.y - m.vy) * m.ppty }
end

-------------------------------------------------------------------------------
-- Drag handles: an invisible draggable frame over every node
-------------------------------------------------------------------------------
G.HANDLE_INSET = 0.6 -- tiles left free at both sides so the ports stay clickable

function G.clear_handles(player, keep_id)
  local s = screen(player)
  local names = {}
  for _, child in pairs(s.children) do
    if child.name and child.name:sub(1, 5) == "fm_h_" then names[#names + 1] = child end
  end
  for _, child in pairs(names) do
    if not (keep_id and child.name == "fm_h_" .. keep_id) then child.destroy() end
  end
end

function G.refresh_handles(player, pstate)
  local keep = pstate.drag_skip
  G.clear_handles(player, keep)
  pstate.handle_off = pstate.handle_off or {}
  if keep == nil then pstate.handle_off = {} end
  local project = storage.projects[pstate.project]
  local cp = pstate.cam_px
  if not project or not cp or not screen(player).fm_canvas then return end
  local sc = player.display_scale
  local s = screen(player)

  -- one draggable invisible frame over a local rectangle; ref = the point it moves
  local function add_handle(key, tags, lx1, ly1, lx2, ly2, ref)
    if tostring(key) == tostring(keep) then return end
    local a = G.to_screen(player, pstate, { x = lx1, y = ly1 })
    local b = G.to_screen(player, pstate, { x = lx2, y = ly2 })
    if not a or not b then return end
    local x1 = math.ceil(math.max(a.x, cp.x))
    local y1 = math.ceil(math.max(a.y, cp.y))
    local x2 = math.floor(math.min(b.x, cp.x + cp.w))
    local y2 = math.floor(math.min(b.y, cp.y + cp.h))
    if x2 - x1 < 6 or y2 - y1 < 6 then return end
    local f = s.add({ type = "frame", name = "fm_h_" .. key, style = "invisible_frame", tags = tags })
    f.location = { x1, y1 }
    f.style.width = (x2 - x1) / sc
    f.style.height = (y2 - y1) / sc
    local g = f.add({ type = "empty-widget", name = "grip", tags = tags, style = pstate.debug and "draggable_space" or nil })
    g.style.width = (x2 - x1) / sc
    g.style.height = (y2 - y1) / sc
    g.drag_target = f
    -- where the handle's corner sits relative to the point it moves (local tiles)
    local lp = G.to_local(player, pstate, { x = x1, y = y1 })
    pstate.handle_off[key] = { x = lp.x - ref.x, y = lp.y - ref.y }
  end

  for _, n in pairs(model.visible_children(project, pstate.factory)) do
    local L = render.layout(project, n)
    if L.compact then
      local rad = render.WIRELESS_R + 0.05
      add_handle(n.id, act("handle", { node = n.id }), L.cx - rad, L.cy - rad, L.cx + rad, L.cy + rad, n)
    else
      add_handle(n.id, act("handle", { node = n.id }), L.x + G.HANDLE_INSET, L.y, L.x + L.w - G.HANDLE_INSET, L.y + L.h, n)
    end
  end
  local links = model.visible_links(project, pstate.factory)
  for _, l in pairs(links) do
    local pts = render.link_points(project, l)
    if pts then
      local lp = render.label_pos(project, l, pts)
      add_handle("l" .. l.id, act("label", { link = l.id }), lp.x - render.LABEL_HALF_W, lp.y - render.LABEL_HALF_H,
        lp.x + render.LABEL_HALF_W, lp.y + render.LABEL_HALF_H, lp)
    end
  end
  for _, l in pairs(links) do
    for idx, ap in pairs(l.points or {}) do
      add_handle("a" .. l.id .. "_" .. idx, act("anchor", { link = l.id, idx = idx }), ap.x - 0.3, ap.y - 0.3, ap.x + 0.3, ap.y + 0.3, ap)
    end
  end
  if s.fm_settings then s.fm_settings.bring_to_front() end
  if s.fm_popup then s.fm_popup.bring_to_front() end
end

function G.ppt(player, zoom)
  local ps = storage.players and storage.players[player.index]
  local c = ps and ps.calib
  if c and c.kx and c.ky then return c.kx * zoom, c.ky * zoom end
  local use = settings.get_player_settings(player)["fm-camera-ui-scale"].value
  local v = 32 * zoom * (use and player.display_scale or 1)
  return v, v
end

function G.fit(player, pstate)
  local project = storage.projects[pstate.project]
  if not project or not pstate.cam_px then return end
  local b = render.bounds(project, pstate.factory)
  local v = G.get_view(pstate)
  if not b then
    v.x, v.y, v.zoom = 10, 6, 0.75
  else
    v.x, v.y = (b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2
    local w, h = b.x2 - b.x1 + 4, b.y2 - b.y1 + 4
    local ux, uy = G.ppt(player, 1)
    local z = math.min(pstate.cam_px.w / (w * ux), pstate.cam_px.h / (h * uy))
    v.zoom = math.max(G.min_zoom(player), math.min(2, z))
  end
  G.apply_view(player, pstate)
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
function G.refresh_all(player, pstate)
  G.refresh_top(player, pstate)
  G.refresh_summary(player, pstate)
  G.refresh_inspector(player, pstate)
  G.apply_view(player, pstate)
end

function G.refresh_top(player, pstate, keep_name)
  local frame_top = screen(player).fm_top
  if not frame_top then return end
  local top = frame_top.bar
  top.fm_unit.caption = (model.settings().unit == "second") and T("per-second") or T("per-minute")
  top.fm_pause.caption = game.tick_paused and T("resume") or T("pause")
  top.fm_pause.style = game.tick_paused and "red_button" or "button"
  local dd = top.fm_projects
  local items, sel = {}, 1
  local ids = {}
  for id, _ in pairs(storage.projects) do ids[#ids + 1] = id end
  table.sort(ids)
  for i, id in pairs(ids) do
    items[i] = storage.projects[id].name
    if id == pstate.project then sel = i end
  end
  dd.items = items
  dd.selected_index = sel
  dd.tags = act("select_project", { ids = ids })
  local project = storage.projects[pstate.project]
  if not keep_name then top.fm_project_name.text = project and project.name or "" end
  local crumbs = top.fm_crumbs
  crumbs.clear()
  if project then
    local path = model.factory_path(project, pstate.factory)
    for i, fid in pairs(path) do
      if i > 1 then crumbs.add({ type = "label", caption = "›" }) end
      local fn = project.nodes[fid]
      local name = (i == 1) and project.name or (fn and fn.name or "?")
      local b = crumbs.add({ type = "button", caption = name, tags = act("goto_factory", { factory = fid }) })
      b.enabled = (fid ~= pstate.factory)
      b.style.minimal_width = 40
    end
  end
end

local function rich_rows(parent, map, color)
  local keys = {}
  for k, _ in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  if #keys == 0 then
    parent.add({ type = "label", caption = "—" })
    return
  end
  local t = parent.add({ type = "table", column_count = 3 })
  for _, k in pairs(keys) do
    t.add({ type = "label", caption = model.rich(k) })
    local l = t.add({ type = "label", caption = render.fmt(map[k]) .. rate_unit_caption(), tooltip = model.key_name(k) })
    if color then l.style.font_color = color end
    t.add({ type = "label", caption = model.key_name(k) }).style.font_color = { 0.7, 0.7, 0.7 }
  end
end

function G.refresh_summary(player, pstate)
  local left = screen(player).fm_left
  if not left then return end
  local box = left.scroll.fm_summary
  box.clear()
  local project = storage.projects[pstate.project]
  if not project then return end
  local sum = solver.summary(project, pstate.factory)
  local function head(caption)
    local l = box.add({ type = "label", caption = caption, style = "bold_label" })
    l.style.top_margin = 4
  end
  head(T("sum-inputs"))
  rich_rows(box, sum.inputs)
  head(T("sum-outputs"))
  rich_rows(box, sum.outputs)
  head(T("sum-missing"))
  rich_rows(box, sum.missing, { 1, 0.6, 0.5 })
  head(T("sum-surplus"))
  rich_rows(box, sum.surplus, { 1, 0.85, 0.4 })
  head(T("sum-machines"))
  local names = {}
  for k, _ in pairs(sum.machines) do names[#names + 1] = k end
  table.sort(names)
  if #names == 0 then box.add({ type = "label", caption = "—" }) end
  for _, k in pairs(names) do
    local e = sum.machines[k]
    box.add({ type = "label", caption = "[entity=" .. k .. "] ×" .. render.fmt_num(e.count) .. "  (" .. e.ceil .. ")" })
  end
  head(T("sum-power"))
  box.add({ type = "label", caption = T("sum-power-need", render.fmt_power(sum.power_need or sum.power)) })
  if (sum.power_cap or 0) > 0 then
    box.add({ type = "label", caption = T("sum-power-cap", render.fmt_power(sum.power_cap)) })
  end
  if (sum.power_unmet or 0) > 1 then
    local l = box.add({ type = "label", caption = T("sum-power-unmet", render.fmt_power(sum.power_unmet)) })
    l.style.font_color = { 1, 0.45, 0.35 }
  end
end

-------------------------------------------------------------------------------
-- Inspector
-------------------------------------------------------------------------------
local function numfield(parent, value, tags, width)
  local f = parent.add({ type = "textfield", text = value, numeric = true, allow_decimal = true, allow_negative = false, tags = tags, lose_focus_on_confirm = true })
  f.style.width = width or 80
  return f
end

local function port_table(parent, project, node, res)
  local ins, outs = model.visible_ports(project, node)
  local r = res and res.nodes[node.id] or { ins = {}, outs = {} }
  if #ins > 0 then
    parent.add({ type = "label", caption = T("ins"), style = "bold_label" })
    local t = parent.add({ type = "table", column_count = 3 })
    for _, p in pairs(ins) do
      local pr = r.ins[p.key] or { need = 0, received = 0 }
      t.add({ type = "label", caption = model.rich(p.item), tooltip = model.key_name(p.item) })
      t.add({ type = "label", caption = render.fmt(pr.need) .. rate_unit_caption() })
      local st = t.add({ type = "label" })
      if not pr.linked then
        st.caption = T("import")
        st.style.font_color = { 0.7, 0.7, 0.7 }
      elseif pr.received + 1e-7 < pr.need * (1 - 1e-6) then
        st.caption = T("short", render.fmt(pr.need - pr.received))
        st.style.font_color = { 1, 0.4, 0.3 }
      else
        st.caption = "✔"
        st.style.font_color = { 0.4, 0.9, 0.4 }
      end
    end
  end
  if #outs > 0 then
    parent.add({ type = "label", caption = T("outs"), style = "bold_label" })
    local t = parent.add({ type = "table", column_count = 3 })
    for _, p in pairs(outs) do
      local pr = r.outs[p.key] or { produced = 0, delivered = 0 }
      t.add({ type = "label", caption = model.rich(p.item), tooltip = model.key_name(p.item) })
      t.add({ type = "label", caption = render.fmt(pr.produced) .. rate_unit_caption() })
      local st = t.add({ type = "label" })
      if not pr.linked then
        st.caption = T("export")
        st.style.font_color = { 0.7, 0.7, 0.7 }
      elseif pr.produced - pr.delivered > 1e-7 then
        st.caption = T("extra", render.fmt(pr.produced - pr.delivered))
        st.style.font_color = { 1, 0.85, 0.3 }
      else
        st.caption = "✔"
        st.style.font_color = { 0.4, 0.9, 0.4 }
      end
    end
  end
end

function G.refresh_inspector(player, pstate)
  local right = screen(player).fm_right
  if not right then return end
  local box = right.scroll
  box.clear()
  local project = storage.projects[pstate.project]
  if not project then return end
  local res = project.results
  local mul = render.unit()

  if pstate.selected_link then
    local l = project.links[pstate.selected_link]
    if l then
      local lr = res and res.links[l.id]
      box.add({ type = "label", caption = T("link"), style = "bold_label" })
      local from = project.nodes[l.from.node]
      local port = from and model.find_port(project, from, l.from.port, "out")
      if port then box.add({ type = "label", caption = model.rich(port.item), tooltip = model.key_name(port.item) }) end
      box.add({ type = "label", caption = T("flow", render.fmt(lr and lr.flow or 0) .. rate_unit_caption()) })
      if lr and not lr.push then
        box.add({ type = "label", caption = T("demand", render.fmt(lr.demand) .. rate_unit_caption()) })
      end
      if port and model.split_key(port.item) == "item" then
        local belts, belt = render.belts_for(l, port.item, lr and lr.flow or 0)
        if belts then
          box.add({ type = "label", caption = T("belts-needed", render.fmt_num(belts), "[entity=" .. belt.name .. "]", math.ceil(belts - 1e-6)), style = "bold_label" })
        end
        box.add({ type = "label", caption = T("belt-type") })
        local bt = box.add({ type = "table", column_count = 7 })
        local b0 = bt.add({ type = "sprite-button", sprite = "utility/reset", style = "slot_button", tooltip = T("belt-default"), toggled = (l.belt == nil), tags = act("set_link_belt", { link = l.id }) })
        b0.style.size = 36
        for _, b in pairs(model.get_belts()) do
          local btn = bt.add({ type = "sprite-button", sprite = "entity/" .. b.name, style = "slot_button",
            tooltip = { "", prototypes.entity[b.name].localised_name, "\n", T("belt-rate", render.fmt(b.rate) .. rate_unit_caption()) },
            toggled = (l.belt == b.name), tags = act("set_link_belt", { link = l.id, name = b.name }) })
          btn.style.size = 36
        end
      end
      box.add({ type = "label", caption = T("link-color") })
      local ct = box.add({ type = "table", column_count = 10 })
      local b0 = ct.add({ type = "sprite-button", sprite = "utility/reset", style = "slot_button", toggled = (l.color == nil), tooltip = T("link-color-auto"), tags = act("set_link_color", { link = l.id }) })
      b0.style.size = 32
      for _, c in pairs(render.LINK_COLORS) do
        local sp = helpers.is_valid_sprite_path(c.sprite) and c.sprite or "utility/add"
        local cur = l.color and math.abs(l.color.r - c.color.r) < 1e-6 and math.abs(l.color.g - c.color.g) < 1e-6 and math.abs(l.color.b - c.color.b) < 1e-6
        local b = ct.add({ type = "sprite-button", sprite = sp, style = "slot_button", toggled = cur or false, tooltip = T("color-" .. c.name), tags = act("set_link_color", { link = l.id, color = c.name }) })
        b.style.size = 32
      end
      local rf = box.add({ type = "flow", direction = "horizontal" })
      rf.add({ type = "button", caption = T("reset-anchors"), tooltip = T("reset-anchors-tt"), tags = act("reset_anchors", { link = l.id }) }).enabled = (l.points and #l.points > 0) or false
      rf.add({ type = "button", caption = T("reset-label"), tags = act("reset_label", { link = l.id }) }).enabled = (l.label_off ~= nil or l.label_t ~= nil)
      local hint = box.add({ type = "label", caption = T("anchor-hint") })
      hint.style.single_line = false
      hint.style.width = G.RIGHT_W - 30
      box.add({ type = "button", caption = T("delete-link"), style = "red_button", tags = act("delete_link", { link = l.id }) })
      return
    end
  end

  local count = 0
  local only
  for id, _ in pairs(pstate.selection or {}) do
    if project.nodes[id] then
      count = count + 1
      only = project.nodes[id]
    end
  end
  if count == 0 then
    local l = box.add({ type = "label", caption = T("nothing-selected") })
    l.style.single_line = false
    l.style.width = G.RIGHT_W - 30
    return
  end
  if count > 1 then
    box.add({ type = "label", caption = T("n-selected", count) })
    return
  end
  local node = only
  local r = res and res.nodes[node.id] or { x = 0 }

  local function row(caption)
    local f = box.add({ type = "flow", direction = "horizontal" })
    f.style.vertical_align = "center"
    if caption then f.add({ type = "label", caption = caption }).style.width = 120 end
    return f
  end

  if node.type == "recipe" then
    local def, mach = model.recipe_rates(node)
    local f = row()
    if def and def.kind == "mining" then
      f.add({ type = "choose-elem-button", elem_type = "entity", entity = def.resource, elem_filters = { { filter = "type", type = "resource" } }, tags = act("set_mining", { node = node.id }) })
    else
      f.add({ type = "choose-elem-button", elem_type = "recipe", recipe = def and node.recipe or nil, elem_filters = { { filter = "hidden", invert = true } }, tags = act("set_recipe", { node = node.id }) })
    end
    local nl = f.add({ type = "label", caption = def and def.localised_name or tostring(node.recipe), style = "bold_label" })
    nl.style.single_line = false
    nl.style.width = G.RIGHT_W - 80
    if def then
      box.add({ type = "label", caption = T("craft-time", render.fmt_num(def.energy)) })
    end

    box.add({ type = "label", caption = T("machine"), style = "bold_label" })
    local mf = box.add({ type = "table", column_count = 7 })
    for _, mm in pairs(model.get_machines(def)) do
      local b = mf.add({
        type = "sprite-button", sprite = "entity/" .. mm.name, style = "slot_button",
        tooltip = { "", prototypes.entity[mm.name].localised_name, "\n", T("speed", render.fmt_num(mm.speed)) },
        toggled = (mm.name == node.machine), tags = act("set_machine", { node = node.id, machine = mm.name }),
      })
      b.style.size = 36
    end

    local bc = box.add({ type = "checkbox", state = node.built or false, caption = T("built"), tooltip = T("built-tt"), tags = act("built", { node = node.id }) })
    bc.style.top_margin = 4

    local mode = row(T("mode"))
    mode.add({ type = "switch", left_label_caption = T("auto"), right_label_caption = T("fixed"), switch_state = node.fixed and "right" or "left", tags = act("set_fixed", { node = node.id }), left_label_tooltip = T("auto-tt"), right_label_tooltip = T("fixed-tt") })

    local mrow = row(T("machines"))
    numfield(mrow, node.fixed and R_fmt_raw(node.value) or R_fmt_raw(r.x or 0), act("set_value", { node = node.id }))
    mrow.add({ type = "label", caption = "= " .. math.ceil((r.x or 0) - 1e-6) .. " " }).style.font_color = { 0.7, 0.7, 0.7 }

    if def and def.main then
      local main_per
      for _, p in pairs(select(2, model.node_ports(project, node))) do
        if p.key == def.main then main_per = p.per_x end
      end
      if main_per and main_per > 0 then
        local rr = row(T("target-rate", model.rich(def.main), rate_unit_caption()))
        numfield(rr, R_fmt_raw((r.x or 0) * main_per * mul), act("set_target", { node = node.id, per = main_per }))
      end
    end

    local sp = row(T("speed-bonus"))
    numfield(sp, R_fmt_raw(node.speed or 0), act("set_speed", { node = node.id }), 60)
    sp.add({ type = "label", caption = "%" })
    local pp = row(T("prod-bonus"))
    numfield(pp, R_fmt_raw(node.prod or 0), act("set_prod", { node = node.id }), 60)
    pp.add({ type = "label", caption = "%" })
    if def and def.kind == "mining" then
      local rb = model.mining_research_bonus()
      local l = box.add({ type = "label", caption = model.settings().use_research == false and T("research-off") or T("research-bonus", string.format("%.0f", rb * 100)),
        tooltip = T("research-bonus-tt") })
      l.style.font_color = { 0.7, 0.85, 1 }
    end
    if mach and mach.burner then
      local fuels = model.fuels_for(mach.burner)
      local cur = model.node_fuel(node, mach)
      box.add({ type = "label", caption = T("fuel"), style = "bold_label" })
      local ft = box.add({ type = "table", column_count = 8 })
      for _, f in pairs(fuels) do
        local b = ft.add({ type = "sprite-button", sprite = "item/" .. f.name, style = "slot_button", toggled = (cur and cur.name == f.name) or false,
          tooltip = { "", prototypes.item[f.name].localised_name, "\n", (render.fmt_power(f.value):gsub("W", "J")) }, tags = act("set_fuel", { node = node.id, fuel = f.name }) })
        b.style.size = 36
      end
      if cur then
        local per = mach.power / (cur.value * (mach.burner.effectivity or 1))
        box.add({ type = "label", caption = T("fuel-use", "[item=" .. cur.name .. "]", render.fmt(per * (r.x or 0)) .. rate_unit_caption(), render.fmt(per) .. rate_unit_caption()) })
      end
    elseif mach then
      box.add({ type = "label", caption = T("power", render.fmt_power(r.power or (mach.power * (r.x or 0)))) })
    end
    port_table(box, project, node, res)
    -- inserters per machine
    local ins = model.default_inserter()
    local irate = model.inserter_rate(ins, player.force)
    if ins and irate and irate > 0 then
      local pins, pouts = model.node_ports(project, node)
      local parts = {}
      for _, list in pairs({ pins, pouts }) do
        for _, p in pairs(list) do
          if model.split_key(p.item) == "item" and p.per_x > 0 then
            parts[#parts + 1] = model.rich(p.item) .. " " .. math.ceil(p.per_x / irate - 1e-6)
          end
        end
      end
      if #parts > 0 then
        local il = box.add({ type = "label", caption = T("inserters", "[entity=" .. ins.name .. "]", table.concat(parts, "   ")), tooltip = T("inserters-tt", render.fmt(irate) .. rate_unit_caption()) })
        il.style.single_line = false
        il.style.width = G.RIGHT_W - 30
      end
    end
  elseif node.type == "wout" or node.type == "win" then
    box.add({ type = "label", caption = node.type == "wout" and T("wout-node") or T("win-node"), style = "bold_label" })
    local f = row(T("item"))
    local t, nm = model.split_key(node.item)
    f.add({ type = "choose-elem-button", elem_type = "item", item = (t == "item" and prototypes.item[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "item" }) })
    f.add({ type = "choose-elem-button", elem_type = "fluid", fluid = (t == "fluid" and prototypes.fluid[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "fluid" }) })
    local cr = row(T("channel"))
    local tf = cr.add({ type = "textfield", text = tostring(node.channel or 0), numeric = true, allow_decimal = false, allow_negative = false,
      tags = act("set_channel", { node = node.id }), lose_focus_on_confirm = true, tooltip = T("channel-tt") })
    tf.style.width = 70
    box.add({ type = "label", caption = T("current", render.fmt(r.x or 0) .. rate_unit_caption()) })
    local other_kind = node.type == "wout" and "win" or "wout"
    local others = model.wireless_on(project, node.parent, node.channel, other_kind)
    local same, wrong = 0, 0
    for _, o in pairs(others) do
      if o.item == node.item then same = same + 1 else wrong = wrong + 1 end
    end
    local l = box.add({ type = "label", caption = node.type == "wout" and T("wout-partners", same) or T("win-partners", same) })
    if same == 0 then l.style.font_color = { 1, 0.45, 0.35 } end
    if wrong > 0 then
      local w = box.add({ type = "label", caption = T("wireless-wrong-item", wrong) })
      w.style.font_color = { 1, 0.65, 0.3 }
    end
    local hint = box.add({ type = "label", caption = T("wireless-hint") })
    hint.style.single_line = false
    hint.style.width = G.RIGHT_W - 30
    port_table(box, project, node, res)
  elseif node.type == "gen" then
    local ep = node.entity and prototypes.entity[node.entity]
    local f = row()
    f.add({ type = "sprite-button", sprite = ep and ("entity/" .. node.entity) or "utility/add", style = "slot_button" })
    local nl = f.add({ type = "label", caption = ep and ep.localised_name or "?", style = "bold_label" })
    nl.style.single_line = false
    nl.style.width = G.RIGHT_W - 80
    local cr = row(T("gen-count"))
    numfield(cr, R_fmt_raw(node.value or 0), act("set_value", { node = node.id }))
    local g = model.gen_info(node.entity)
    if g then
      if g.power > 0 then
        box.add({ type = "label", caption = T("gen-cap", render.fmt_power(g.power), render.fmt_power(r.power_cap or 0)) })
        if g.kind == "solar" then box.add({ type = "label", caption = T("gen-solar") }).style.font_color = { 0.7, 0.7, 0.7 } end
        if (r.sat or 1) < 0.999 then
          local l = box.add({ type = "label", caption = T("gen-starved", string.format("%.0f", (r.sat or 0) * 100)) })
          l.style.font_color = { 1, 0.45, 0.35 }
        end
      end
      if g.burner then
        local fuels = model.fuels_for(g.burner)
        local cur = model.node_fuel(node, { burner = g.burner })
        box.add({ type = "label", caption = T("fuel"), style = "bold_label" })
        local ft = box.add({ type = "table", column_count = 8 })
        for _, fu in pairs(fuels) do
          local b = ft.add({ type = "sprite-button", sprite = "item/" .. fu.name, style = "slot_button", toggled = (cur and cur.name == fu.name) or false,
            tooltip = prototypes.item[fu.name].localised_name, tags = act("set_fuel", { node = node.id, fuel = fu.name }) })
          b.style.size = 36
        end
      end
    end
    port_table(box, project, node, res)
  elseif node.type == "psplit" then
    box.add({ type = "label", caption = T("psplit-node"), style = "bold_label" })
    local f = row(T("item"))
    local t, nm = model.split_key(node.item)
    f.add({ type = "choose-elem-button", elem_type = "item", item = (t == "item" and prototypes.item[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "item" }) })
    f.add({ type = "choose-elem-button", elem_type = "fluid", fluid = (t == "fluid" and prototypes.fluid[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "fluid" }) })
    local cr = row(T("psplit-count"))
    cr.add({ type = "button", caption = "-", style = "tool_button", tags = act("psplit_count", { node = node.id, delta = -1 }), tooltip = T("psplit-count-tt") })
    local tf = cr.add({ type = "textfield", text = tostring(#node.slots), numeric = true, allow_decimal = false, allow_negative = false, tags = act("psplit_count_set", { node = node.id }), lose_focus_on_confirm = true, tooltip = T("psplit-count-tt") })
    tf.style.width = 50
    cr.add({ type = "button", caption = "+", style = "tool_button", tags = act("psplit_count", { node = node.id, delta = 1 }) })
    local orow = row(T("psplit-overflow"))
    local items = { T("psplit-none") }
    local sel = 1
    for i, sid in pairs(node.slots) do
      items[#items + 1] = T("psplit-out", i)
      if sid == node.overflow then sel = i + 1 end
    end
    orow.add({ type = "drop-down", items = items, selected_index = sel, tags = act("psplit_overflow", { node = node.id }), tooltip = T("psplit-overflow-tt") })
    box.add({ type = "label", caption = T("current", render.fmt(r.x or 0) .. rate_unit_caption()) })
    if (r.leftover or 0) > 1e-7 then
      local l = box.add({ type = "label", caption = T("psplit-leftover", render.fmt(r.leftover) .. rate_unit_caption()) })
      l.style.font_color = { 1, 0.85, 0.3 }
    end
    local hint = box.add({ type = "label", caption = T("psplit-hint") })
    hint.style.single_line = false
    hint.style.width = G.RIGHT_W - 30
    port_table(box, project, node, res)
  elseif node.type == "split" then
    box.add({ type = "label", caption = T("split-node"), style = "bold_label" })
    local f = row(T("item"))
    local t, nm = model.split_key(node.item)
    f.add({ type = "choose-elem-button", elem_type = "item", item = (t == "item" and prototypes.item[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "item" }) })
    f.add({ type = "choose-elem-button", elem_type = "fluid", fluid = (t == "fluid" and prototypes.fluid[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "fluid" }) })
    box.add({ type = "label", caption = T("current", render.fmt(r.x or 0) .. rate_unit_caption()) })
    if node.item and t == "item" then
      local b = model.default_belt()
      if b then
        local n = (r.x or 0) / b.rate
        box.add({ type = "label", caption = T("belts-needed", render.fmt_num(n), "[entity=" .. b.name .. "]", math.ceil(n - 1e-6)) })
      end
    end
    local hint = box.add({ type = "label", caption = T("split-hint") })
    hint.style.single_line = false
    hint.style.width = G.RIGHT_W - 30
    port_table(box, project, node, res)
  elseif node.type == "input" or node.type == "output" then
    box.add({ type = "label", caption = node.type == "input" and T("input-node") or T("output-node"), style = "bold_label" })
    local f = row(T("item"))
    local t = model.split_key(node.item)
    local nm = select(2, model.split_key(node.item))
    f.add({ type = "choose-elem-button", elem_type = "item", item = (t == "item" and prototypes.item[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "item" }) })
    f.add({ type = "choose-elem-button", elem_type = "fluid", fluid = (t == "fluid" and prototypes.fluid[nm]) and nm or nil, tags = act("set_item", { node = node.id, t = "fluid" }) })
    local mode = row(T("mode"))
    mode.add({ type = "switch", left_label_caption = T("auto"), right_label_caption = T("fixed"), switch_state = node.fixed and "right" or "left", tags = act("set_fixed", { node = node.id }),
      left_label_tooltip = node.type == "input" and T("in-auto-tt") or T("out-auto-tt"), right_label_tooltip = node.type == "input" and T("in-fixed-tt") or T("out-fixed-tt") })
    local rr = row(T("rate", rate_unit_caption()))
    numfield(rr, R_fmt_raw((node.fixed and node.value or r.x or 0) * mul), act("set_rate", { node = node.id }))
    local cur = box.add({ type = "label", caption = T("current", render.fmt(r.x or 0) .. rate_unit_caption()) })
    cur.style.font_color = { 0.7, 0.7, 0.7 }
    if node.parent ~= project.root then
      local hint = box.add({ type = "label", caption = node.type == "input" and T("in-port-hint") or T("out-port-hint") })
      hint.style.single_line = false
      hint.style.width = G.RIGHT_W - 30
    end
  elseif node.type == "factory" then
    box.add({ type = "label", caption = T("factory"), style = "bold_label" })
    local f = row(T("name"))
    f.add({ type = "textfield", text = node.name or "", tags = act("rename_factory", { node = node.id }) }).style.width = 170
    local b = box.add({ type = "flow", direction = "horizontal" })
    b.add({ type = "button", caption = T("open"), tags = act("goto_factory", { factory = node.id }) })
    b.add({ type = "button", caption = T("ungroup"), tags = act("ungroup", { node = node.id }) })
    local pw = r.power
    if pw then
      if node.plant then
        box.add({ type = "label", caption = T("plant-info", render.fmt_power(pw.plant_cap or 0), string.format("%.0f", (pw.plant_load or 0) * 100)), style = "bold_label" })
      end
      box.add({ type = "label", caption = T("factory-power", render.fmt_power(pw.need), render.fmt_power(pw.cap)) })
      if pw.unmet > 1 then
        local l = box.add({ type = "label", caption = (node.parent and T("factory-power-outer", render.fmt_power(pw.unmet)) or T("sum-power-unmet", render.fmt_power(pw.unmet))) })
        l.style.font_color = { 1, 0.6, 0.35 }
      end
    end
    box.add({ type = "checkbox", state = node.built or false, caption = T("built-factory"), tooltip = T("built-factory-tt"), tags = act("built", { node = node.id }) })
    box.add({ type = "checkbox", state = node.plant or false, caption = T("is-plant"), tooltip = T("is-plant-tt"), tags = act("is_plant", { node = node.id }) })
    box.add({ type = "checkbox", state = node.auto_outputs or false, caption = T("auto-outputs"), tooltip = T("auto-outputs-tt"), tags = act("auto_outputs", { node = node.id }) })
    local cb2 = box.add({ type = "checkbox", state = node.auto_outputs_unlinked or false, caption = T("auto-outputs-unlinked"), tooltip = T("auto-outputs-unlinked-tt"), tags = act("auto_outputs_unlinked", { node = node.id }) })
    cb2.enabled = node.auto_outputs or false
    cb2.style.left_margin = 20
    port_table(box, project, node, res)
    local hint = box.add({ type = "label", caption = T("factory-hint") })
    hint.style.single_line = false
    hint.style.width = G.RIGHT_W - 30
  end

  local bf = box.add({ type = "flow", direction = "horizontal" })
  bf.style.top_margin = 8
  bf.add({ type = "button", caption = T("duplicate"), tags = act("duplicate_sel") })
  bf.add({ type = "button", caption = T("delete"), style = "red_button", tags = act("delete_sel") })
end

-------------------------------------------------------------------------------
-- Settings window
-------------------------------------------------------------------------------
local KNOWN_CATS = {
  ["advanced-crafting"] = true, ["centrifuging"] = true, ["chemistry"] = true, ["crafting"] = true,
  ["crafting-with-fluid"] = true, ["oil-processing"] = true, ["rocket-building"] = true, ["smelting"] = true,
  ["basic-fluid"] = true, ["basic-solid"] = true,
}

function G.settings_window(player, pstate)
  local s = screen(player)
  local old_loc
  if s.fm_settings then
    old_loc = s.fm_settings.location
    s.fm_settings.destroy()
  end
  local st = model.settings()
  local f = s.add({ type = "frame", name = "fm_settings", direction = "vertical" })
  local tb = f.add({ type = "flow", direction = "horizontal" })
  tb.add({ type = "label", caption = T("settings"), style = "frame_title" }).ignored_by_interaction = true
  local drag = tb.add({ type = "empty-widget", style = "draggable_space_header" })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = f
  tb.add({ type = "sprite-button", sprite = "utility/close", style = "close_button", tags = act("close_settings") })

  local sp = f.add({ type = "scroll-pane", direction = "vertical" })
  sp.style.maximal_height = 600
  sp.style.minimal_width = 460

  local function title(caption)
    local l = sp.add({ type = "label", caption = caption, style = "caption_label" })
    l.style.top_margin = 8
  end
  local function buttons(parent, list, current, action, extra_fn)
    local t = parent.add({ type = "table", column_count = 10 })
    for _, m in pairs(list) do
      local tags = act(action, { name = m.name })
      if extra_fn then extra_fn(tags) end
      local b = t.add({ type = "sprite-button", sprite = "entity/" .. m.name, style = "slot_button", toggled = (m.name == current),
        tooltip = { "", prototypes.entity[m.name].localised_name, m.tip and "\n" or "", m.tip or "" }, tags = tags })
      b.style.size = 36
    end
  end

  title(T("set-unit"))
  sp.add({ type = "button", caption = (st.unit == "second") and T("per-second") or T("per-minute"), tooltip = T("unit-tt"), tags = act("toggle_unit") })

  title(T("set-research"))
  sp.add({ type = "checkbox", state = st.use_research ~= false, caption = T("use-research", string.format("%.0f", model.mining_research_bonus() * 100)),
    tooltip = T("research-bonus-tt"), tags = act("use_research") })

  title(T("set-input"))
  sp.add({ type = "checkbox", state = pstate.block_input ~= false, caption = T("block-input"), tooltip = T("block-input-tt"), tags = act("block_input") })
  sp.add({ type = "checkbox", state = pstate.auto_pause or false, caption = T("auto-pause"), tooltip = T("auto-pause-tt"), tags = act("auto_pause") })

  title(T("set-links"))
  local lsf = sp.add({ type = "flow", direction = "horizontal" })
  lsf.add({ type = "radiobutton", state = (st.link_style or "spline") == "spline", caption = T("links-spline"), tags = act("link_style", { style = "spline" }) })
  lsf.add({ type = "radiobutton", state = st.link_style == "ortho", caption = T("links-ortho"), tags = act("link_style", { style = "ortho" }) })

  title(T("set-label-mode"))
  local lmf = sp.add({ type = "flow", direction = "horizontal" })
  lmf.add({ type = "radiobutton", state = (st.label_mode or "free") == "free", caption = T("label-free"), tooltip = T("label-free-tt"), tags = act("label_mode", { mode = "free" }) })
  lmf.add({ type = "radiobutton", state = st.label_mode == "along", caption = T("label-along"), tooltip = T("label-along-tt"), tags = act("label_mode", { mode = "along" }) })

  title(T("set-belt"))
  local belts = {}
  local db = model.default_belt()
  for _, b in pairs(model.get_belts()) do belts[#belts + 1] = { name = b.name, tip = T("belt-rate", render.fmt(b.rate) .. rate_unit_caption()) } end
  buttons(sp, belts, db and db.name, "set_default_belt")

  title(T("set-fuel"))
  local fl = {}
  local all = model.get_fuels()
  local dfuel = st.fuel or "coal"
  for _, f in pairs(all) do
    if f.categories["chemical"] or not next(f.categories) then fl[#fl + 1] = f end
  end
  if #fl == 0 then fl = all end
  local ftb = sp.add({ type = "table", column_count = 10 })
  for _, f in pairs(fl) do
    local b = ftb.add({ type = "sprite-button", sprite = "item/" .. f.name, style = "slot_button", toggled = (f.name == dfuel),
      tooltip = prototypes.item[f.name].localised_name, tags = act("set_default_fuel", { name = f.name }) })
    b.style.size = 36
  end

  title(T("set-inserter"))
  local insl = {}
  local di = model.default_inserter()
  for _, i in pairs(model.get_inserters()) do insl[#insl + 1] = { name = i.name, tip = T("belt-rate", render.fmt(model.inserter_rate(i, player.force)) .. rate_unit_caption()) } end
  buttons(sp, insl, di and di.name, "set_default_inserter")

  title(T("set-machines"))
  local tbl = sp.add({ type = "table", column_count = 2 })
  tbl.style.vertical_spacing = 4
  for _, c in pairs(model.all_categories()) do
    local list = model.machines_for(c.cat, c.kind)
    local key = model.category_key(c.cat, c.kind)
    -- the game has no translations for categories, so use our own names for the known ones
    local cap = KNOWN_CATS[c.cat] and T("cat-" .. c.cat) or (c.cat:gsub("-", " "):gsub("^%l", string.upper))
    local lab = tbl.add({ type = "label", caption = c.kind == "mining" and { "", "[img=utility/resource_editor_icon] ", cap } or cap, tooltip = c.cat })
    lab.style.width = 200
    lab.style.single_line = false
    local current = st.machines[key]
    if not current or not prototypes.entity[current] then
      current = list[math.min(#list, 2)] and list[math.min(#list, 2)].name
    end
    local mm = {}
    for _, m in pairs(list) do mm[#mm + 1] = { name = m.name, tip = T("speed", render.fmt_num(m.speed)) } end
    buttons(tbl, mm, current, "set_default_machine", function(tags) tags.key = key end)
  end

  local bottom = f.add({ type = "flow", direction = "horizontal" })
  bottom.style.top_margin = 8
  bottom.add({ type = "button", caption = T("apply-defaults"), tooltip = T("apply-defaults-tt"), tags = act("apply_defaults") })
  if old_loc then f.location = old_loc else f.force_auto_center() end
  f.bring_to_front()
end

-------------------------------------------------------------------------------
-- Popup (context menus / pickers) placed at the cursor
-------------------------------------------------------------------------------
function G.close_popup(player)
  local p = screen(player).fm_popup
  if p then p.destroy() end
end

-- entries: { {sprite=, caption=, tooltip=, tags=} ... }
function G.popup(player, loc, title, entries, as_grid)
  G.close_popup(player)
  local f = screen(player).add({ type = "frame", name = "fm_popup", direction = "vertical", caption = title })
  local res = player.display_resolution
  local x = math.min(loc.x, res.width - 380 * player.display_scale)
  local y = math.min(loc.y, res.height - 360 * player.display_scale)
  f.location = { math.max(0, x), math.max(0, y) }
  local sp = f.add({ type = "scroll-pane", direction = "vertical" })
  sp.style.maximal_height = 320
  if as_grid then
    local t = sp.add({ type = "table", column_count = 8 })
    for _, e in pairs(entries) do
      t.add({ type = "sprite-button", sprite = e.sprite, tooltip = e.tooltip, tags = e.tags, style = "slot_button" })
    end
  else
    for _, e in pairs(entries) do
      local b = sp.add({ type = "button", caption = e.caption, tooltip = e.tooltip, tags = e.tags })
      b.style.horizontally_stretchable = true
      b.style.horizontal_align = "left"
    end
  end
  f.add({ type = "button", caption = T("cancel"), tags = act("close_popup") }).style.horizontally_stretchable = true
  f.bring_to_front()
  return f
end

return G
