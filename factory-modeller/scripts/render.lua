-- Drawing the graph onto the hidden canvas surface with LuaRendering.
local model = require("scripts.model")

local R = {}

R.SURFACE = "fm-canvas"
R.NODE_W = 8
R.FACTORY_W = 12
R.HEADER_H = 1.5
R.ROW_H = 1
R.PORT_R = 0.28

local COLORS = {
  body = { 0.13, 0.13, 0.15, 0.97 },
  shadow = { 0, 0, 0, 0.45 },
  border = { 0.35, 0.35, 0.4, 1 },
  recipe = { 0.78, 0.47, 0.13, 1 },
  mining = { 0.55, 0.42, 0.25, 1 },
  input = { 0.2, 0.6, 0.3, 1 },
  output = { 0.65, 0.25, 0.3, 1 },
  factory = { 0.22, 0.42, 0.75, 1 },
  split = { 0.5, 0.3, 0.7, 1 },
  psplit = { 0.62, 0.22, 0.55, 1 },
  gen = { 0.75, 0.62, 0.12, 1 },
  wout = { 0.12, 0.55, 0.55, 1 },
  win = { 0.12, 0.55, 0.55, 1 },
  plant = { 0.7, 0.5, 0.1, 1 },
  text = { 0.95, 0.95, 0.95, 1 },
  dim = { 0.65, 0.65, 0.7, 1 },
  ok = { 0.35, 0.85, 0.4, 1 },
  bad = { 1, 0.3, 0.25, 1 },
  warn = { 1, 0.8, 0.2, 1 },
  idle = { 0.55, 0.55, 0.6, 1 },
  select = { 1, 0.85, 0.2, 1 },
  built = { 0.3, 0.9, 0.35, 1 },
  pending = { 0.3, 0.8, 1, 1 },
}
R.COLORS = COLORS
-- colours a link can be painted in (sprite shown in the palette, colour)
R.LINK_COLORS = {
  { name = "red", sprite = "virtual-signal/signal-red", color = { r = 0.95, g = 0.3, b = 0.3 } },
  { name = "yellow", sprite = "virtual-signal/signal-yellow", color = { r = 1, g = 0.9, b = 0.25 } },
  { name = "green", sprite = "virtual-signal/signal-green", color = { r = 0.35, g = 0.85, b = 0.4 } },
  { name = "cyan", sprite = "virtual-signal/signal-cyan", color = { r = 0.3, g = 0.9, b = 0.95 } },
  { name = "blue", sprite = "virtual-signal/signal-blue", color = { r = 0.35, g = 0.55, b = 1 } },
  { name = "pink", sprite = "virtual-signal/signal-pink", color = { r = 1, g = 0.45, b = 0.85 } },
  { name = "white", sprite = "virtual-signal/signal-white", color = { r = 0.95, g = 0.95, b = 0.95 } },
  { name = "grey", sprite = "virtual-signal/signal-grey", color = { r = 0.55, g = 0.55, b = 0.6 } },
}


function R.get_surface()
  local s = game.surfaces[R.SURFACE]
  if not s then
    s = game.create_surface(R.SURFACE)
    s.generate_with_lab_tiles = true
    s.always_day = true
    s.freeze_daytime = true
    s.show_clouds = false
    for _, f in pairs(game.forces) do
      f.set_surface_hidden(s, true)
    end
  end
  return s
end

local function text_scale()
  local s = settings.global["fm-text-scale"]
  return s and s.value or 1
end

function R.unit()
  local u = model.settings().unit or "minute"
  return u == "second" and 1 or 60, u == "second" and "/s" or "/m"
end

function R.fmt(v)
  local mul = R.unit()
  v = (v or 0) * mul
  local a = math.abs(v)
  local s
  if a >= 10000 then s = string.format("%.0f", v)
  elseif a >= 100 then s = string.format("%.1f", v)
  elseif a >= 1 then s = string.format("%.2f", v)
  elseif a < 1e-9 then s = "0"
  else s = string.format("%.3f", v) end
  if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
  return s
end

function R.fmt_num(v)
  local s = string.format("%.2f", v or 0)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

function R.fmt_power(w)
  if w >= 1e9 then return string.format("%.2f GW", w / 1e9) end
  if w >= 1e6 then return string.format("%.2f MW", w / 1e6) end
  if w >= 1e3 then return string.format("%.1f kW", w / 1e3) end
  return string.format("%.0f W", w)
end

-- belts needed for a flow of `item` (items/s) on link l; nil for fluids
function R.belts_for(l, item, flow)
  local t = model.split_key(item)
  if t ~= "item" then return nil end
  local b = (l.belt and model.belt(l.belt)) or model.default_belt()
  if not b then return nil end
  return flow / b.rate, b
end

-------------------------------------------------------------------------------
-- Layout (positions are relative to the factory region origin)
-------------------------------------------------------------------------------
R.WIRELESS_R = 0.32 -- radius of the small wireless circle (about a port)

function R.layout(project, node)
  if node.type == "wout" or node.type == "win" then
    -- a small circle centred on (x + 0.5, y): its port sits on the whole-tile row y
    local cx, cy = node.x + 0.5, node.y
    local L = { x = node.x, y = node.y - 0.5, w = 1, h = 1, ins = {}, outs = {}, cx = cx, cy = cy, compact = true }
    if node.type == "wout" then
      L.ins[1] = { key = "in", item = node.item, x = cx - R.WIRELESS_R, y = cy }
    else
      L.outs[1] = { key = "out", item = node.item, x = cx + R.WIRELESS_R, y = cy }
    end
    return L
  end
  local ins, outs = model.visible_ports(project, node)
  local w = node.type == "factory" and R.FACTORY_W or R.NODE_W
  if node.type == "input" or node.type == "output" or node.type == "split" then w = 6 end
  if node.type == "psplit" or node.type == "gen" then w = 8 end
  local rows = math.max(#ins, #outs, 1)
  local h = R.HEADER_H + rows * R.ROW_H + 0.5
  local L = { x = node.x, y = node.y, w = w, h = h, ins = {}, outs = {} }
  for i, p in pairs(ins) do
    L.ins[#L.ins + 1] = { key = p.key, item = p.item, x = node.x, y = node.y + R.HEADER_H + (i - 0.5) * R.ROW_H }
  end
  for i, p in pairs(outs) do
    L.outs[#L.outs + 1] = { key = p.key, item = p.item, x = node.x + w, y = node.y + R.HEADER_H + (i - 0.5) * R.ROW_H }
  end
  return L
end

function R.port_pos(project, node, key, dir)
  local L = R.layout(project, node)
  for _, p in pairs(dir == "in" and L.ins or L.outs) do
    if p.key == key then return p end
  end
  return nil
end

-- up/down arrows on factory ports (only when there are 2+ ports on that side)
function R.port_arrows(project, node, L)
  local list = {}
  if node.type == "psplit" then
    L = L or R.layout(project, node)
    local n = #node.slots
    if n < 2 then return list end
    for i, lp in pairs(L.outs) do
      local sid = node.slots[i]
      list[#list + 1] = { x = L.x + 3.7, y = lp.y, dir = -1, slot = sid, io = "out", enabled = i > 1 }
      list[#list + 1] = { x = L.x + 4.3, y = lp.y, dir = 1, slot = sid, io = "out", enabled = i < n }
    end
    return list
  end
  if node.type ~= "factory" then return list end
  L = L or R.layout(project, node)
  local ins, outs = model.node_ports(project, node)
  local function add(ports, layout_ports, io, x_up, x_down)
    if #ports < 2 then return end
    for i, lp in pairs(layout_ports) do
      local child = ports[i] and ports[i].child
      list[#list + 1] = { x = x_up, y = lp.y, dir = -1, child = child, io = io, enabled = i > 1 }
      list[#list + 1] = { x = x_down, y = lp.y, dir = 1, child = child, io = io, enabled = i < #ports }
    end
  end
  add(ins, L.ins, "in", L.x + 4.9, L.x + 5.5)
  add(outs, L.outs, "out", L.x + L.w - 5.5, L.x + L.w - 4.9)
  return list
end

function R.hit_arrow(project, node, pos)
  for _, a in pairs(R.port_arrows(project, node)) do
    if a.enabled and math.abs(pos.x - a.x) <= 0.3 and math.abs(pos.y - a.y) <= 0.35 then return a end
  end
  return nil
end

local function bezier(a, b)
  local pts = {}
  local dx = math.max(2, math.abs(b.x - a.x) * 0.5)
  local c1 = { x = a.x + dx, y = a.y }
  local c2 = { x = b.x - dx, y = b.y }
  local n = 16
  for i = 0, n do
    local t = i / n
    local u = 1 - t
    pts[#pts + 1] = {
      x = u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x,
      y = u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y,
    }
  end
  return pts
end
R.bezier = bezier

-- Path of a link through its anchors. Returns a list of "gaps" (one polyline per stretch
-- between consecutive control points: port -> anchor 1 -> ... -> port).
local function hermite(p0, p1, t0, t1, n, out)
  for i = 1, n do
    local t = i / n
    local t2, t3 = t * t, t * t * t
    local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
    out[#out + 1] = {
      x = h00 * p0.x + h10 * t0.x + h01 * p1.x + h11 * t1.x,
      y = h00 * p0.y + h10 * t0.y + h01 * p1.y + h11 * t1.y,
    }
  end
end

function R.link_gaps(project, link)
  local a = project.nodes[link.from.node]
  local b = project.nodes[link.to.node]
  if not a or not b then return nil end
  local pa = R.port_pos(project, a, link.from.port, "out")
  local pb = R.port_pos(project, b, link.to.port, "in")
  if not pa or not pb then return nil end
  local ctrl = { { x = pa.x, y = pa.y } }
  for _, p in pairs(link.points or {}) do ctrl[#ctrl + 1] = { x = p.x, y = p.y } end
  ctrl[#ctrl + 1] = { x = pb.x, y = pb.y }
  local gaps = {}
  local style = model.settings().link_style or "spline"
  if style == "ortho" then
    for i = 1, #ctrl - 1 do
      local p, q = ctrl[i], ctrl[i + 1]
      local g = { { x = p.x, y = p.y } }
      if i == #ctrl - 1 then
        -- into the port: horizontal, vertical, horizontal
        local mx = (p.x + q.x) / 2
        if i == 1 and q.x < p.x + 1 then mx = p.x + 1 end
        if i > 1 then mx = (p.x + q.x) / 2 end
        g[#g + 1] = { x = mx, y = p.y }
        g[#g + 1] = { x = mx, y = q.y }
      else
        g[#g + 1] = { x = q.x, y = p.y }
      end
      g[#g + 1] = { x = q.x, y = q.y }
      gaps[#gaps + 1] = g
    end
  else
    local n = #ctrl
    local tangents = {}
    for i = 1, n do
      if i == 1 or i == n then
        local other = (i == 1) and ctrl[2] or ctrl[n - 1]
        local k = 3 * math.max(2, math.abs(other.x - ctrl[i].x) * 0.5)
        if n > 2 then k = math.max(2, math.abs(other.x - ctrl[i].x)) end
        tangents[i] = { x = k, y = 0 }
      else
        tangents[i] = { x = (ctrl[i + 1].x - ctrl[i - 1].x) * 0.5, y = (ctrl[i + 1].y - ctrl[i - 1].y) * 0.5 }
      end
    end
    local steps = (n == 2) and 16 or 12
    for i = 1, n - 1 do
      local g = { { x = ctrl[i].x, y = ctrl[i].y } }
      hermite(ctrl[i], ctrl[i + 1], tangents[i], tangents[i + 1], steps, g)
      gaps[#gaps + 1] = g
    end
  end
  return gaps
end

function R.link_points(project, link)
  local gaps = R.link_gaps(project, link)
  if not gaps then return nil end
  local pts = {}
  for gi, g in pairs(gaps) do
    for i, p in pairs(g) do
      if not (gi > 1 and i == 1) then pts[#pts + 1] = p end
    end
  end
  return pts
end

-- point halfway along a polyline
function R.polyline_mid(pts)
  local total = 0
  for i = 1, #pts - 1 do total = total + math.sqrt((pts[i + 1].x - pts[i].x) ^ 2 + (pts[i + 1].y - pts[i].y) ^ 2) end
  local half, acc = total / 2, 0
  for i = 1, #pts - 1 do
    local d = math.sqrt((pts[i + 1].x - pts[i].x) ^ 2 + (pts[i + 1].y - pts[i].y) ^ 2)
    if acc + d >= half and d > 0 then
      local t = (half - acc) / d
      return { x = pts[i].x + (pts[i + 1].x - pts[i].x) * t, y = pts[i].y + (pts[i + 1].y - pts[i].y) * t }
    end
    acc = acc + d
  end
  return pts[1]
end

R.LABEL_HALF_W = 2.6
R.LABEL_HALF_H = 0.32

-- point at fraction t (0..1) of a polyline's length
function R.polyline_at(pts, t)
  local total = 0
  for i = 1, #pts - 1 do total = total + math.sqrt((pts[i + 1].x - pts[i].x) ^ 2 + (pts[i + 1].y - pts[i].y) ^ 2) end
  local target, acc = total * math.max(0, math.min(1, t)), 0
  for i = 1, #pts - 1 do
    local d = math.sqrt((pts[i + 1].x - pts[i].x) ^ 2 + (pts[i + 1].y - pts[i].y) ^ 2)
    if acc + d >= target and d > 0 then
      local k = (target - acc) / d
      return { x = pts[i].x + (pts[i + 1].x - pts[i].x) * k, y = pts[i].y + (pts[i + 1].y - pts[i].y) * k }
    end
    acc = acc + d
  end
  return pts[#pts]
end

-- fraction (0..1) of the polyline length closest to pos
function R.polyline_project(pts, pos)
  local total, lens = 0, {}
  for i = 1, #pts - 1 do
    lens[i] = math.sqrt((pts[i + 1].x - pts[i].x) ^ 2 + (pts[i + 1].y - pts[i].y) ^ 2)
    total = total + lens[i]
  end
  if total <= 0 then return 0.5 end
  local best, bestd, acc = 0.5, math.huge, 0
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local len2 = dx * dx + dy * dy
    local k = 0
    if len2 > 0 then k = math.max(0, math.min(1, ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / len2)) end
    local cx, cy = a.x + k * dx, a.y + k * dy
    local d = (pos.x - cx) ^ 2 + (pos.y - cy) ^ 2
    if d < bestd then best, bestd = (acc + k * lens[i]) / total, d end
    acc = acc + lens[i]
  end
  return best
end

-- where the info label of a link sits.
-- "free" mode: path middle + the user's offset; "along" mode: a point along the path.
function R.label_pos(project, link, pts)
  pts = pts or R.link_points(project, link)
  if not pts then return nil end
  local mid = R.polyline_mid(pts)
  if (model.settings().label_mode or "free") == "along" then
    if link.label_t then
      local p = R.polyline_at(pts, link.label_t)
      return p, p
    end
    return mid, mid
  end
  local off = link.label_off
  if off then return { x = mid.x + off.x, y = mid.y + off.y }, mid end
  return mid, mid
end

-- Snap an anchor so its segment becomes straight: align with the ports and the neighbouring points.
function R.snap_anchor(project, link, idx, pos, tol)
  local a = project.nodes[link.from.node]
  local b = project.nodes[link.to.node]
  local pa = a and R.port_pos(project, a, link.from.port, "out")
  local pb = b and R.port_pos(project, b, link.to.port, "in")
  local ys, xs = {}, {}
  if pa then ys[#ys + 1] = pa.y end
  if pb then ys[#ys + 1] = pb.y end
  local pts = link.points or {}
  local prev = pts[idx - 1] or pa
  local nxt = pts[idx + 1] or pb
  for _, q in pairs({ prev, nxt }) do
    if q then
      ys[#ys + 1] = q.y
      xs[#xs + 1] = q.x
    end
  end
  local x, y = pos.x, pos.y
  local bx, by = tol, tol
  for _, v in pairs(xs) do
    if math.abs(v - pos.x) < bx then x, bx = v, math.abs(v - pos.x) end
  end
  for _, v in pairs(ys) do
    if math.abs(v - pos.y) < by then y, by = v, math.abs(v - pos.y) end
  end
  return x, y
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
local function clear_list(list)
  if not list then return end
  for _, id in pairs(list) do
    local o = rendering.get_object_by_id(id)
    if o and o.valid then o.destroy() end
  end
end

function R.clear_factory(project, factory_id)
  project.render = project.render or {}
  clear_list(project.render[factory_id])
  project.render[factory_id] = nil
end

function R.clear_project(project)
  for fid, list in pairs(project.render or {}) do clear_list(list) end
  project.render = {}
  for _, list in pairs(project.bg or {}) do clear_list(list) end
  project.bg = {}
end

local function port_color(r, dir)
  if not r then return COLORS.idle end
  if dir == "in" then
    if not r.linked then return r.need > 1e-9 and COLORS.dim or COLORS.idle end
    if r.received + 1e-7 < r.need * (1 - 1e-6) then return COLORS.bad end
    return COLORS.ok
  else
    if not r.linked then return r.produced > 1e-9 and COLORS.dim or COLORS.idle end
    if r.produced - r.delivered > 1e-7 then return COLORS.warn end
    return COLORS.ok
  end
end

-- Compact wireless block: a small circle with an arrow and the channel label.
-- Output: arrow points INTO the circle, label on the right. Input: arrow points OUT of it, label on the left.
function R.draw_wireless(project, n, L, r, keep, P, text, sprite)
  local surface = R.get_surface()
  local cx, cy, rad = L.cx, L.cy, R.WIRELESS_R
  local others = model.wireless_on(project, n.parent, n.channel, n.type == "wout" and "win" or "wout")
  local paired = false
  for _, o in pairs(others) do if o.item == n.item then paired = true end end
  local col = paired and COLORS.wout or COLORS.bad
  -- status of the flow through it
  local pr = (n.type == "wout") and (r.ins or {})["in"] or (r.outs or {})["out"]
  keep(rendering.draw_circle({ surface = surface, target = P(cx, cy), radius = rad + 0.06, color = { 0, 0, 0, 0.6 }, filled = true }))
  keep(rendering.draw_circle({ surface = surface, target = P(cx, cy), radius = rad, color = col, filled = true }))
  -- arrow (a small triangle pointing right) in the circle
  local h = rad * 0.55
  local ax = cx + ((n.type == "wout") and -0.04 or 0.04)
  keep(rendering.draw_polygon({ surface = surface, color = { 1, 1, 1, 0.95 },
    vertices = { P(ax - h * 0.8, cy - h), P(ax - h * 0.8, cy + h), P(ax + h, cy) } }))
  -- a short stem on the side of the link, so it reads "into" or "out of" the circle
  if n.type == "wout" then
    keep(rendering.draw_line({ surface = surface, from = P(cx - rad - 0.25, cy), to = P(cx - rad, cy), color = col, width = 3 }))
  else
    keep(rendering.draw_line({ surface = surface, from = P(cx + rad, cy), to = P(cx + rad + 0.25, cy), color = col, width = 3 }))
  end
  local icon = (n.item and model.key_valid(n.item)) and (model.rich(n.item) .. " ") or ""
  local label = icon .. "#" .. tostring(n.channel or 0)
  if pr then label = label .. "  " .. R.fmt(n.type == "wout" and (pr.received or 0) or (pr.produced or 0)) end
  if not paired then label = "[color=1,0.4,0.3]" .. label .. "[/color]" end
  if n.type == "wout" then
    text(label, cx + rad + 0.2, cy, COLORS.text, 0.85, "left", true)
  else
    text(label, cx - rad - 0.2, cy, COLORS.text, 0.85, "right", true)
  end
end

local function sprite_ok(path)
  return path and helpers.is_valid_sprite_path(path)
end

-- Our own canvas background (dark + grid), drawn once per factory region on the ground layer.
-- It does not depend on map chunks, so the canvas never shows black areas, even while the game is paused.
R.BG_EXTENT = 600
function R.ensure_background(project, factory_id)
  project.bg = project.bg or {}
  local list = project.bg[factory_id]
  if list and list[1] then
    local o = rendering.get_object_by_id(list[1])
    if o and o.valid then return end
  end
  local fnode = project.nodes[factory_id]
  if not fnode then return end
  local surface = R.get_surface()
  local off = model.region_offset(fnode.region)
  local E = R.BG_EXTENT
  local ids = {}
  local o = rendering.draw_rectangle({ surface = surface, left_top = { x = off.x - E, y = off.y - E }, right_bottom = { x = off.x + E, y = off.y + E },
    color = { 0.1, 0.1, 0.11, 1 }, filled = true, draw_on_ground = true })
  ids[#ids + 1] = o.id
  for v = -E, E, 5 do
    local major = (v % 25 == 0)
    local c = major and { 0.17, 0.17, 0.19, 1 } or { 0.13, 0.13, 0.145, 1 }
    ids[#ids + 1] = rendering.draw_line({ surface = surface, from = { x = off.x + v, y = off.y - E }, to = { x = off.x + v, y = off.y + E }, color = c, width = 1, draw_on_ground = true }).id
    ids[#ids + 1] = rendering.draw_line({ surface = surface, from = { x = off.x - E, y = off.y + v }, to = { x = off.x + E, y = off.y + v }, color = c, width = 1, draw_on_ground = true }).id
  end
  project.bg[factory_id] = ids
end

function R.clear_background(project)
  for _, list in pairs(project.bg or {}) do clear_list(list) end
  project.bg = {}
end

function R.draw_factory(project, factory_id)
  R.clear_factory(project, factory_id)
  local fnode = project.nodes[factory_id]
  if not fnode then return end
  R.ensure_background(project, factory_id)
  local surface = R.get_surface()
  local off = model.region_offset(fnode.region)
  local ids = {}
  local ts = text_scale()
  local res = project.results or { nodes = {}, links = {} }

  local function P(x, y) return { x = off.x + x, y = off.y + y } end
  local function keep(o) ids[#ids + 1] = o.id end
  local function rect(x1, y1, x2, y2, color, filled, width)
    keep(rendering.draw_rectangle({ surface = surface, left_top = P(x1, y1), right_bottom = P(x2, y2), color = color, filled = filled, width = width or 1 }))
  end
  local function text(str, x, y, color, scale, align, rich)
    keep(rendering.draw_text({
      surface = surface, target = P(x, y), text = str, color = color or COLORS.text, scale = (scale or 1) * ts,
      alignment = align or "left", vertical_alignment = "middle", use_rich_text = rich or false,
    }))
  end
  local function sprite(path, x, y, scale)
    if sprite_ok(path) then
      keep(rendering.draw_sprite({ surface = surface, sprite = path, target = P(x, y), x_scale = scale, y_scale = scale }))
    end
  end

  -- links first (below nodes); their labels are drawn after all lines so they sit above every line
  local labels = {}
  for _, l in pairs(model.visible_links(project, factory_id)) do
    local pts = R.link_points(project, l)
    if pts then
      local lr = res.links[l.id]
      local short = lr and not lr.push and lr.flow + 1e-7 < lr.demand * (1 - 1e-6)
      local color = COLORS.ok
      if not lr then color = COLORS.idle
      elseif short then color = COLORS.bad
      elseif lr.flow < 1e-9 then color = COLORS.idle end
      if l.color then
        color = { l.color.r, l.color.g, l.color.b, 1 }
        if short then
          -- keep the warning visible on coloured links: thin red line on top
          for i = 1, #pts - 1 do
            labels[#labels + 1] = { line = { pts[i], pts[i + 1] } }
          end
        end
      end
      for i = 1, #pts - 1 do
        keep(rendering.draw_line({ surface = surface, from = P(pts[i].x, pts[i].y), to = P(pts[i + 1].x, pts[i + 1].y), color = color, width = 3 }))
      end
      local mid, path_mid = R.label_pos(project, l, pts)
      if l.label_off and (math.abs(l.label_off.x) > 0.5 or math.abs(l.label_off.y) > 0.5) then
        keep(rendering.draw_line({ surface = surface, from = P(path_mid.x, path_mid.y), to = P(mid.x, mid.y), color = { 0.6, 0.6, 0.6, 0.6 }, width = 1, dash_length = 0.2, gap_length = 0.15 }))
      end
      for _, ap in pairs(l.points or {}) do
        keep(rendering.draw_rectangle({ surface = surface, left_top = P(ap.x - 0.18, ap.y - 0.18), right_bottom = P(ap.x + 0.18, ap.y + 0.18), color = color, filled = true }))
      end
      local from_node = project.nodes[l.from.node]
      local port = from_node and model.find_port(project, from_node, l.from.port, "out")
      local flow = lr and lr.flow or 0
      local label = (port and model.rich(port.item) or "") .. " " .. R.fmt(flow)
      if lr and not lr.push and lr.flow + 1e-7 < lr.demand * (1 - 1e-6) then
        label = label .. " [color=1,0.4,0.3]/ " .. R.fmt(lr.demand) .. "[/color]"
      end
      local belts, belt = nil, nil
      if port and port.item then belts, belt = R.belts_for(l, port.item, flow) end
      local half = R.LABEL_HALF_W
      if belts then
        label = label .. "  " .. R.fmt_num(belts) .. "×[entity=" .. belt.name .. "]"
      end
      labels[#labels + 1] = { mid = mid, half = half, label = label }
    end
  end
  for _, lb in pairs(labels) do
    if lb.line then
      local a, b = lb.line[1], lb.line[2]
      keep(rendering.draw_line({ surface = surface, from = P(a.x, a.y), to = P(b.x, b.y), color = COLORS.bad, width = 1, dash_length = 0.3, gap_length = 0.2 }))
    end
  end
  for _, lb in pairs(labels) do
    if lb.mid then
      rect(lb.mid.x - lb.half, lb.mid.y - R.LABEL_HALF_H, lb.mid.x + lb.half, lb.mid.y + R.LABEL_HALF_H, { 0, 0, 0, 0.8 }, true)
      text(lb.label, lb.mid.x, lb.mid.y, COLORS.text, 0.8, "center", true)
    end
  end

  for _, n in pairs(model.visible_children(project, factory_id)) do
    local L = R.layout(project, n)
    local r = res.nodes[n.id] or { ins = {}, outs = {}, x = 0 }
    if L.compact then
      R.draw_wireless(project, n, L, r, keep, P, text, sprite)
    else
    local x1, y1, x2, y2 = L.x, L.y, L.x + L.w, L.y + L.h
    rect(x1 + 0.15, y1 + 0.15, x2 + 0.15, y2 + 0.15, COLORS.shadow, true)
    rect(x1, y1, x2, y2, COLORS.body, true)
    local hc = COLORS[n.type] or COLORS.recipe
    local def
    if n.type == "recipe" then
      def = model.get_def(n.recipe)
      if def and def.kind == "mining" then hc = COLORS.mining end
    end
    if n.type == "factory" and n.plant then hc = COLORS.plant end
    rect(x1, y1, x2, y1 + R.HEADER_H, hc, true)
    rect(x1, y1, x2, y2, COLORS.border, false, 1)
    if n.built then
      -- already built in the world: green outline
      rect(x1 - 0.06, y1 - 0.06, x2 + 0.06, y2 + 0.06, COLORS.built, false, 4)
    end

    local hy = y1 + R.HEADER_H / 2
    if n.type == "recipe" then
      if def then
        sprite(def.sprite, x1 + 0.75, hy, 0.5)
        text(def.localised_name, x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      else
        text({ "fm.r-missing", tostring(n.recipe) }, x1, y1 - 0.45, COLORS.bad, 0.8, "left")
      end
      if n.machine then sprite("entity/" .. n.machine, x2 - 2.7, hy, 0.45) end
      if (r.power or 0) > 0 then
        text("[item=small-electric-pole] " .. R.fmt_power(r.power), x2, y2 + 0.45, COLORS.dim, 0.7, "right", true)
      end
      local cnt = "×" .. R.fmt_num(r.x or 0)
      text(cnt, x2 - 0.2, hy, n.fixed and COLORS.warn or COLORS.text, 1.15, "right")
      if n.fixed then text({ "fm.r-fixed" }, x1 + 1.5, hy, COLORS.warn, 0.7, "left") end
    elseif n.type == "input" or n.type == "output" then
      local label = n.type == "input" and "IN" or "OUT"
      text(label, x1 + 0.25, hy, COLORS.text, 1.0, "left")
      if n.item and model.key_valid(n.item) then
        sprite(n.item, x1 + 2.2, hy, 0.5)
        text(model.key_name(n.item), x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      else
        text({ "fm.r-set-item" }, x1, y1 - 0.45, COLORS.bad, 0.8, "left")
      end
      text(R.fmt(r.x or 0), x2 - 0.2, hy, n.fixed and COLORS.warn or COLORS.text, 1.0, "right")
    elseif n.type == "wout" or n.type == "win" then
      text({ n.type == "wout" and "fm.r-wout" or "fm.r-win" }, x1 + 0.25, hy, COLORS.text, 0.9, "left")
      text("#" .. tostring(n.channel or 0), x2 - 0.2, hy, COLORS.warn, 1.15, "right")
      if n.item and model.key_valid(n.item) then
        sprite(n.item, x2 - 1.6, hy, 0.45)
      else
        text({ "fm.r-split-hint" }, x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      end
      -- how many partners on the channel
      local other = model.wireless_on(project, n.parent, n.channel, n.type == "wout" and "win" or "wout")
      if #other == 0 then
        text({ "fm.r-wireless-none" }, x1, y2 + 0.45, COLORS.bad, 0.7, "left")
      else
        text({ "fm.r-wireless-n", #other }, x1, y2 + 0.45, COLORS.dim, 0.7, "left")
      end
    elseif n.type == "gen" then
      if n.entity and prototypes.entity[n.entity] then
        sprite("entity/" .. n.entity, x1 + 0.75, hy, 0.5)
        text(prototypes.entity[n.entity].localised_name, x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      end
      text("×" .. R.fmt_num(n.value or 0), x2 - 0.2, hy, COLORS.warn, 1.15, "right")
      local g = model.gen_info(n.entity)
      if g and g.power > 0 then
        local col = (r.sat or 1) < 0.999 and "[color=1,0.4,0.3]" or "[color=1,0.85,0.3]"
        text(col .. "[item=small-electric-pole] " .. R.fmt_power(r.power_cap or 0) .. "[/color]", x2, y2 + 0.45, COLORS.text, 0.75, "right", true)
      end
    elseif n.type == "psplit" then
      text({ "fm.r-psplit" }, x1 + 0.25, hy, COLORS.text, 0.9, "left")
      if n.item and model.key_valid(n.item) then
        sprite(n.item, x2 - 0.75, hy, 0.5)
      else
        text({ "fm.r-split-hint" }, x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      end
      if (r.leftover or 0) > 1e-7 then
        text({ "", "[color=1,0.85,0.3]+", R.fmt(r.leftover), "[/color]" }, x2 - 1.4, hy, COLORS.text, 0.8, "right", true)
      end
    elseif n.type == "split" then
      text({ "fm.r-split" }, x1 + 0.25, hy, COLORS.text, 0.9, "left")
      if n.item and model.key_valid(n.item) then
        sprite(n.item, x2 - 0.75, hy, 0.5)
      else
        text({ "fm.r-split-hint" }, x1, y1 - 0.45, COLORS.dim, 0.8, "left")
      end
    elseif n.type == "factory" then
      text("[entity=assembling-machine-3] " .. (n.name or "Factory"), x1 + 0.25, hy, COLORS.text, 1.0, "left", true)
      text({ "fm.r-dbl-open" }, x1, y2 + 0.45, COLORS.dim, 0.7, "left")
      local pw = r.power
      if pw and (pw.need > 0 or (pw.plant_cap or 0) > 0) then
        local parts = { "" }
        if n.plant then
          parts[#parts + 1] = { "fm.r-plant", R.fmt_power(pw.plant_cap or 0), string.format("%.0f", (pw.plant_load or 0) * 100) }
        else
          parts[#parts + 1] = "[item=small-electric-pole] " .. R.fmt_power(pw.need)
          if pw.unmet > 1 then
            parts[#parts + 1] = (n.id == project.root or not n.parent) and { "fm.r-power-short", R.fmt_power(pw.unmet) } or { "fm.r-power-outer", R.fmt_power(pw.unmet) }
          end
        end
        text(parts, x2, y2 + 0.45, COLORS.text, 0.75, "right", true)
      end
    end

    for _, a in pairs(R.port_arrows(project, n, L)) do
      local h = 0.2
      local verts
      if a.dir < 0 then
        verts = { P(a.x - h, a.y + h * 0.8), P(a.x + h, a.y + h * 0.8), P(a.x, a.y - h) }
      else
        verts = { P(a.x - h, a.y - h * 0.8), P(a.x + h, a.y - h * 0.8), P(a.x, a.y + h) }
      end
      keep(rendering.draw_polygon({ surface = surface, vertices = verts, color = a.enabled and { 0.9, 0.9, 0.9, 1 } or { 0.35, 0.35, 0.4, 1 } }))
    end
    for _, p in pairs(L.ins) do
      local pr = r.ins[p.key]
      keep(rendering.draw_circle({ surface = surface, target = P(p.x, p.y), radius = R.PORT_R, color = port_color(pr, "in"), filled = true }))
      local s = model.rich(p.item) .. " " .. R.fmt(pr and pr.need or 0)
      if pr and pr.linked and pr.received + 1e-7 < pr.need * (1 - 1e-6) then
        s = s .. " [color=1,0.4,0.3](" .. R.fmt(pr.received) .. ")[/color]"
      end
      text(s, p.x + 0.45, p.y, COLORS.text, 0.85, "left", true)
    end
    for _, p in pairs(L.outs) do
      local pr = r.outs[p.key]
      local pc = port_color(pr, "out")
      if n.type == "factory" and pr and (pr.extra or 0) > 1e-7 then pc = COLORS.warn end
      if n.type == "factory" and pr and pr.linked then
        if pr.produced < 1e-9 then pc = COLORS.idle
        elseif pr.produced + 1e-7 < (pr.demand or 0) * (1 - 1e-6) then pc = COLORS.bad end
      end
      keep(rendering.draw_circle({ surface = surface, target = P(p.x, p.y), radius = R.PORT_R, color = pc, filled = true }))
      local s = R.fmt(pr and pr.produced or 0) .. " " .. model.rich(p.item)
      local extra = 0
      if pr then
        extra = pr.produced - pr.delivered
        if n.type == "factory" then extra = math.max(extra, 0) + (pr.extra or 0) end
      end
      if pr and (pr.linked or n.type == "factory") and extra > 1e-7 then
        s = "[color=1,0.85,0.3](+" .. R.fmt(extra) .. ")[/color] " .. s
      end
      if n.type == "factory" and pr and pr.auto then
        s = "[color=0.6,0.6,0.65]" .. "auto[/color] " .. s
        if pr.linked and pr.produced + 1e-7 < (pr.demand or 0) * (1 - 1e-6) then
          s = "[color=1,0.4,0.3]" .. R.fmt(pr.demand) .. " ![/color] " .. s
        end
      end
      if n.type == "psplit" then
        local i, sid = 0, nil
        for k, v in pairs(n.slots) do if "s" .. v == p.key then i, sid = k, v end end
        s = s .. " #" .. i .. (sid == n.overflow and "[color=1,0.85,0.3]*[/color]" or "")
      end
      text(s, p.x - 0.45, p.y, COLORS.text, 0.85, "right", true)
    end
    end
  end
  project.render[factory_id] = ids
end

-- Per-player overlay: selection, pending link
function R.draw_overlay(player, pstate, project, factory_id)
  if pstate.overlay then clear_list(pstate.overlay) end
  pstate.overlay = {}
  if not project or not factory_id then return end
  local fnode = project.nodes[factory_id]
  if not fnode then return end
  local surface = R.get_surface()
  local off = model.region_offset(fnode.region)
  local function P(x, y) return { x = off.x + x, y = off.y + y } end
  local function keep(o) pstate.overlay[#pstate.overlay + 1] = o.id end
  for id, _ in pairs(pstate.selection or {}) do
    local n = project.nodes[id]
    if n and n.parent == factory_id then
      local L = R.layout(project, n)
      keep(rendering.draw_rectangle({ surface = surface, left_top = P(L.x - 0.12, L.y - 0.12), right_bottom = P(L.x + L.w + 0.12, L.y + L.h + 0.12), color = COLORS.select, width = 3, players = { player } }))
    end
  end
  if pstate.selected_link then
    local l = project.links[pstate.selected_link]
    local pts = l and R.link_points(project, l)
    if pts then
      for i = 1, #pts - 1 do
        keep(rendering.draw_line({ surface = surface, from = P(pts[i].x, pts[i].y), to = P(pts[i + 1].x, pts[i + 1].y), color = COLORS.select, width = 6, players = { player } }))
      end
    end
  end
  local sa = pstate.selected_anchor
  if sa then
    local l = project.links[sa.link]
    local ap = l and l.points and l.points[sa.idx]
    if ap then
      keep(rendering.draw_rectangle({ surface = surface, left_top = P(ap.x - 0.3, ap.y - 0.3), right_bottom = P(ap.x + 0.3, ap.y + 0.3), color = COLORS.select, width = 3, players = { player } }))
    end
  end
  local pl = pstate.pending_link
  if pl then
    local n = project.nodes[pl.node]
    local pp = n and R.port_pos(project, n, pl.port, pl.dir)
    if pp then
      keep(rendering.draw_circle({ surface = surface, target = P(pp.x, pp.y), radius = R.PORT_R + 0.25, color = COLORS.pending, width = 4, filled = false, players = { player } }))
      keep(rendering.draw_text({ surface = surface, target = P(pp.x, pp.y - 0.7), text = { "fm.r-pending" }, color = COLORS.pending, scale = 0.8 * text_scale(), alignment = "center", vertical_alignment = "middle", players = { player } }))
    end
  end
  local cal = pstate.calibrating
  if cal then
    local n = #cal.clicks + 1
    for i, sgn in pairs({ -1, 1 }) do
      local t = { x = cal.center.x + sgn * cal.d, y = cal.center.y + sgn * cal.d }
      local col = (i == n) and { 1, 0.2, 1, 1 } or { 0.5, 0.5, 0.5, 0.8 }
      if i >= n then
        keep(rendering.draw_line({ surface = surface, from = P(t.x - 1, t.y), to = P(t.x + 1, t.y), color = col, width = 2, players = { player } }))
        keep(rendering.draw_line({ surface = surface, from = P(t.x, t.y - 1), to = P(t.x, t.y + 1), color = col, width = 2, players = { player } }))
        keep(rendering.draw_circle({ surface = surface, target = P(t.x, t.y), radius = 0.5, color = col, width = 2, filled = false, players = { player } }))
      end
      if i == n then
        keep(rendering.draw_text({ surface = surface, target = P(t.x, t.y + 1.3), text = { "fm.r-calib", i }, color = col, scale = 1.2 * text_scale(), alignment = "center", vertical_alignment = "middle", players = { player } }))
      end
    end
  end
  if pstate.marker then
    keep(rendering.draw_circle({ surface = surface, target = pstate.marker, radius = 0.15, color = { 1, 0, 1, 1 }, filled = true, players = { player }, time_to_live = 60 }))
  end
end

function R.clear_overlay(pstate)
  if pstate.overlay then clear_list(pstate.overlay) end
  pstate.overlay = nil
end

-------------------------------------------------------------------------------
-- Hit testing (local coordinates)
-------------------------------------------------------------------------------
local function seg_dist(px, py, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  local t = 0
  if len2 > 0 then t = math.max(0, math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / len2)) end
  local cx, cy = a.x + t * dx, a.y + t * dy
  return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

function R.hit_test(project, factory_id, pos)
  local kids = model.visible_children(project, factory_id)
  -- ports
  for i = #kids, 1, -1 do
    local n = kids[i]
    local L = R.layout(project, n)
    for _, dir in pairs({ "in", "out" }) do
      for _, p in pairs(dir == "in" and L.ins or L.outs) do
        local d = math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2)
        if d <= R.PORT_R + 0.3 then
          return { kind = "port", node = n.id, port = p.key, dir = dir, item = p.item }
        end
      end
    end
  end
  -- nodes (topmost = last drawn)
  for i = #kids, 1, -1 do
    local n = kids[i]
    local L = R.layout(project, n)
    if pos.x >= L.x and pos.x <= L.x + L.w and pos.y >= L.y and pos.y <= L.y + L.h then
      return { kind = "node", node = n.id }
    end
  end
  -- links
  local best, bestd = nil, 0.35
  for _, l in pairs(model.visible_links(project, factory_id)) do
    local pts = R.link_points(project, l)
    if pts then
      for i = 1, #pts - 1 do
        local d = seg_dist(pos.x, pos.y, pts[i], pts[i + 1])
        if d < bestd then best, bestd = l, d end
      end
      local mid = R.label_pos(project, l, pts)
      if math.abs(pos.x - mid.x) <= R.LABEL_HALF_W and math.abs(pos.y - mid.y) <= R.LABEL_HALF_H then best, bestd = l, 0 end
    end
  end
  if best then return { kind = "link", link = best.id } end
  return nil
end

-- index (in link.points) where a new anchor at pos should go, and distance to the link
function R.anchor_insert_index(project, link, pos)
  local gaps = R.link_gaps(project, link)
  if not gaps then return nil end
  local best, bestd = nil, math.huge
  for gi, g in pairs(gaps) do
    for i = 1, #g - 1 do
      local d = seg_dist(pos.x, pos.y, g[i], g[i + 1])
      if d < bestd then best, bestd = gi, d end
    end
  end
  return best, bestd
end

function R.nearest_link(project, factory_id, pos, maxd)
  local best, bestd = nil, maxd or 0.5
  for _, l in pairs(model.visible_links(project, factory_id)) do
    local _, d = R.anchor_insert_index(project, l, pos)
    if d and d < bestd then best, bestd = l, d end
  end
  return best
end

function R.nodes_in_rect(project, factory_id, a, b)
  local x1, x2 = math.min(a.x, b.x), math.max(a.x, b.x)
  local y1, y2 = math.min(a.y, b.y), math.max(a.y, b.y)
  local list = {}
  for _, n in pairs(model.visible_children(project, factory_id)) do
    local L = R.layout(project, n)
    if L.x + L.w >= x1 and L.x <= x2 and L.y + L.h >= y1 and L.y <= y2 then list[#list + 1] = n end
  end
  return list
end

function R.bounds(project, factory_id)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, n in pairs(model.visible_children(project, factory_id)) do
    local L = R.layout(project, n)
    x1, y1 = math.min(x1, L.x), math.min(y1, L.y - 1)
    x2, y2 = math.max(x2, L.x + L.w), math.max(y2, L.y + L.h + 1)
  end
  if x1 == math.huge then return nil end
  return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

return R
