-- Flow solver.
-- Every non-factory node has a scalar x:
--   recipe: number of machines, input/output: items per second.
-- Factory nodes are transparent: links to their ports are rerouted to the inner input/output nodes.
-- Fixed nodes keep their x. Auto nodes are pulled by downstream demand; if nothing downstream
-- demands anything, they consume everything that is pushed into them.
local model = require("scripts.model")

local S = {}

local EPS = 1e-9

local function canon(project, node_id, port)
  local n = project.nodes[node_id]
  local guard = 0
  while n and n.type == "factory" and guard < 64 do
    guard = guard + 1
    local kind, cid = port:match("^([io]):(%d+)$")
    if not kind then return nil end
    cid = tonumber(cid)
    n = project.nodes[cid]
    if not n or n.parent ~= node_id then return nil end
    node_id = cid
    port = (kind == "i") and "in" or "out"
  end
  if not n then return nil end
  return node_id, port
end
S.canon = canon

function S.solve(project)
  local nodes = {}   -- id -> solver node
  for id, n in pairs(project.nodes) do
    if n.type ~= "factory" then
      local ins, outs = model.node_ports(project, n)
      local sn = { id = id, node = n, ins = {}, outs = {}, in_links = {}, out_links = {}, x = 0, state = "idle" }
      for _, p in pairs(ins) do sn.ins[p.key] = p.per_x end
      for _, p in pairs(outs) do sn.outs[p.key] = p.per_x end
      nodes[id] = sn
    end
  end

  local links = {}
  for lid, l in pairs(project.links) do
    local fn, fp = canon(project, l.from.node, l.from.port)
    local tn, tp = canon(project, l.to.node, l.to.port)
    if fn and tn and nodes[fn] and nodes[tn] and nodes[fn].outs[fp] and nodes[tn].ins[tp] then
      local sl = { id = lid, fn = fn, fp = fp, tn = tn, tp = tp, demand = 0, flow = 0, push = false }
      links[#links + 1] = sl
      local a, b = nodes[fn], nodes[tn]
      a.out_links[fp] = a.out_links[fp] or {}
      table.insert(a.out_links[fp], sl)
      b.in_links[tp] = b.in_links[tp] or {}
      table.insert(b.in_links[tp], sl)
    end
  end

  -- modes
  for _, sn in pairs(nodes) do
    local n = sn.node
    local fixed = false
    if n.type == "gen" then
      fixed = true
    elseif n.type == "recipe" then
      fixed = n.fixed
    elseif n.type == "input" then
      fixed = n.fixed and not sn.in_links["in"]
    elseif n.type == "output" then
      fixed = n.fixed and not sn.out_links["out"]
    end
    sn.fixed = fixed
    if fixed then
      sn.x = math.max(0, n.value or 0)
      sn.state = "fixed"
    end
    sn.has_in = next(sn.in_links) ~= nil
    if n.auto then sn.state = "push" end
    -- an OUT block inside a factory gets only what is left after the other consumers
    if n.type == "output" and n.parent ~= project.root then sn.low = true end
  end

  -- priority splitters: an overflow output that is linked makes the splitter take everything offered
  for _, sn in pairs(nodes) do
    local n = sn.node
    if n.type == "psplit" then
      sn.psplit = true
      sn.absorb = n.overflow ~= nil and sn.out_links["s" .. n.overflow] ~= nil
    end
  end

  local received = {} -- [node][port] = amount

  local iterations = 0
  for it = 1, 300 do
    iterations = it
    -- 0. pass-through blocks (IN/OUT/splitter) also take leftovers when something behind them takes
    --    leftovers (e.g. an automatic surplus output one level up), so surplus deep inside nested
    --    factories can travel out.
    for _, sn in pairs(nodes) do
      local t = sn.node.type
      if (t == "input" or t == "output" or t == "split") and sn.has_in then
        local ab = false
        for _, ls in pairs(sn.out_links) do
          for _, l in pairs(ls) do
            local c = nodes[l.tn]
            if c.state == "push" or c.absorb then ab = true end
          end
        end
        sn.absorb = ab
      end
    end
    -- 1. link demand from consumers
    for _, l in pairs(links) do
      local c = nodes[l.tn]
      if c.state == "push" then
        l.push = true
        l.demand = 0
      else
        l.push = false
        l.demand = c.x * c.ins[l.tp] / #c.in_links[l.tp]
      end
    end
    -- 2. flows from producers
    for _, sn in pairs(nodes) do
      if sn.psplit then
        -- priority: fill outputs in order, leftovers to the overflow output (or to push consumers)
        local rin = (received[sn.id] or {})["in"]
        local avail = sn.has_in and (rin or 0) or sn.x
        local rem = avail
        local pushers = {}
        for _, sid in pairs(sn.node.slots) do
          local ls = sn.out_links["s" .. sid]
          if ls then
            local d = 0
            for _, l in pairs(ls) do
              if l.push then pushers[#pushers + 1] = l else d = d + l.demand end
            end
            local give = math.min(d, rem)
            for _, l in pairs(ls) do
              if not l.push then l.flow = (d > 0) and (l.demand * give / d) or 0 end
            end
            rem = rem - give
          end
        end
        for _, l in pairs(pushers) do l.flow = 0 end
        local ovf = sn.node.overflow and sn.out_links["s" .. sn.node.overflow]
        if rem > 1e-12 and ovf then
          for _, l in pairs(ovf) do l.flow = l.flow + rem / #ovf end
          rem = 0
        elseif rem > 1e-12 and #pushers > 0 then
          for _, l in pairs(pushers) do l.flow = rem / #pushers end
          rem = 0
        end
        sn.leftover = rem
      else
        for port, ls in pairs(sn.out_links) do
          local avail = sn.x * sn.outs[port]
          -- pass-through blocks can only pass on what they actually receive
          local t = sn.node.type
          if (t == "input" or t == "output" or t == "split") and sn.has_in then
            local got = ((received[sn.id] or {})["in"]) or 0
            if sn.absorb then avail = got else avail = math.min(avail, got) end
          end
          -- three priorities: ordinary consumers, then factory outputs (OUT blocks inside a factory),
          -- then whatever just takes the rest (push / absorbing consumers)
          local pull, low, nabs = 0, 0, 0
          for _, l in pairs(ls) do
            if l.push then
              nabs = nabs + 1
            elseif nodes[l.tn].low then
              low = low + l.demand
            else
              pull = pull + l.demand
            end
            if not l.push and nodes[l.tn].absorb then nabs = nabs + 1 end
          end
          local ratio = (pull > avail and pull > 0) and (avail / pull) or 1
          local rem = math.max(0, avail - pull)
          local lratio = (low > rem and low > 0) and (rem / low) or 1
          rem = math.max(0, rem - low)
          for _, l in pairs(ls) do
            if l.push then
              l.flow = rem / nabs
            else
              l.flow = l.demand * (nodes[l.tn].low and lratio or ratio)
              if nodes[l.tn].absorb then l.flow = l.flow + rem / nabs end
            end
          end
        end
      end
    end
    -- 3. received
    received = {}
    -- flows through pass-through blocks lag one round behind, so they count for convergence too
    local delta = 0
    for _, l in pairs(links) do
      received[l.tn] = received[l.tn] or {}
      received[l.tn][l.tp] = (received[l.tn][l.tp] or 0) + l.flow
      local d = math.abs(l.flow - (l.prev_flow or 0)) / math.max(1, math.abs(l.flow))
      if d > delta then delta = d end
      l.prev_flow = l.flow
    end
    -- 4. update auto nodes
    for _, sn in pairs(nodes) do
      if sn.node.auto then
        -- automatic surplus output: only passes on what is left over, never asks for more
        local got = ((received[sn.id] or {})["in"]) or 0
        local d = math.abs(got - sn.x) / math.max(1, math.abs(got))
        if sn.state ~= "push" then d = math.max(d, 1) end
        delta = math.max(delta, d)
        sn.x, sn.state = got, "push"
      elseif not sn.fixed then
        local xp = 0
        for port, ls in pairs(sn.out_links) do
          local d = 0
          for _, l in pairs(ls) do if not l.push then d = d + l.demand end end
          local per = sn.outs[port]
          if per > 0 then
            if sn.psplit then xp = xp + d / per else xp = math.max(xp, d / per) end
          end
        end
        local nx, nstate
        if xp > EPS then
          nx, nstate = xp, "pull"
        elseif sn.has_in then
          local xs = math.huge
          for port, _ in pairs(sn.in_links) do
            local per = sn.ins[port]
            if per > 0 then
              xs = math.min(xs, ((received[sn.id] or {})[port] or 0) / per)
            end
          end
          if xs == math.huge then xs = 0 end
          nx, nstate = xs, "push"
        else
          nx, nstate = 0, "idle"
        end
        local d = math.abs(nx - sn.x) / math.max(1, math.abs(nx))
        if nstate ~= sn.state then d = math.max(d, 1) end
        delta = math.max(delta, d)
        sn.x, sn.state = nx, nstate
      end
    end
    if delta < 1e-10 and it > 2 then break end
  end

  -- results
  local res = { nodes = {}, links = {}, iterations = iterations }
  for id, sn in pairs(nodes) do
    local r = { x = sn.x, state = sn.state, ins = {}, outs = {} }
    if sn.psplit then
      -- a priority splitter passes what it receives; its outputs show what each one gets
      r.x = sn.has_in and (((received[id] or {})["in"]) or 0) or sn.x
      r.leftover = sn.leftover or 0
    end
    for port, per in pairs(sn.ins) do
      local need = sn.x * per
      local linked = sn.in_links[port] ~= nil
      local got = (received[id] or {})[port] or 0
      r.ins[port] = { need = need, received = got, linked = linked }
    end
    for port, per in pairs(sn.outs) do
      local produced = sn.x * per
      local delivered = 0
      local linked = sn.out_links[port] ~= nil
      for _, l in pairs(sn.out_links[port] or {}) do delivered = delivered + l.flow end
      if sn.psplit then produced = delivered end
      r.outs[port] = { produced = produced, delivered = delivered, linked = linked }
    end
    if sn.psplit and (r.leftover or 0) > 1e-9 then
      -- leftovers with nowhere to go show up on the lowest-priority output
      local last = sn.node.slots[#sn.node.slots]
      local o = last and r.outs["s" .. last]
      if o then o.produced = o.produced + r.leftover end
    end
    res.nodes[id] = r
  end
  for _, l in pairs(links) do
    res.links[l.id] = { flow = l.flow, demand = l.demand, push = l.push }
  end
  -- factory ports
  for id, n in pairs(project.nodes) do
    if n.type == "factory" then
      local r = { ins = {}, outs = {} }
      for _, c in pairs(model.children(project, id)) do
        local cr = res.nodes[c.id]
        if cr then
          if c.type == "input" then
            r.ins["i:" .. c.id] = { need = cr.x, received = cr.ins["in"].received, linked = cr.ins["in"].linked, child = c.id }
          elseif c.type == "output" then
            local demand = 0
            for _, l in pairs((nodes[c.id] and nodes[c.id].out_links["out"]) or {}) do
              if not l.push then demand = demand + l.demand end
            end
            -- what really comes out: what the OUT block receives inside (or its own rate if nothing is linked inside)
            local through = cr.x
            if cr.ins["in"].linked then
              through = (nodes[c.id] and nodes[c.id].absorb) and cr.ins["in"].received or math.min(cr.x, cr.ins["in"].received)
            end
            r.outs["o:" .. c.id] = { produced = through, delivered = cr.outs["out"].delivered, linked = cr.outs["out"].linked, child = c.id,
              extra = c.auto and 0 or S.extra_into(nodes, res, c.id), demand = demand, auto = c.auto }
          end
        end
      end
      res.nodes[id] = r
    end
  end
  S.power(project, res)
  project.results = res
  return res
end

-------------------------------------------------------------------------------
-- Electricity: consumers in each factory are fed first by the power plants of that factory,
-- what is missing goes up to the plants of the outer factory, and so on.
-------------------------------------------------------------------------------
local function nearest_factory(project, n)
  return n.parent
end

function S.power(project, res)
  local depth = {}
  local function get_depth(id)
    if depth[id] then return depth[id] end
    local n = project.nodes[id]
    local d = (n and n.parent) and (get_depth(n.parent) + 1) or 0
    depth[id] = d
    return d
  end
  local direct = {}   -- factory id -> demand (W) of its own recipes
  local pool = {}     -- factory id -> capacity (W) of its power plants
  local plant_cap = {} -- plant id -> capacity
  for id, n in pairs(project.nodes) do
    local r = res.nodes[id]
    if n.type == "recipe" and r then
      local _, m = model.recipe_rates(n)
      local w = 0
      if m and m.electric then w = m.power * r.x end
      r.power = w
      if w > 0 and n.parent then direct[n.parent] = (direct[n.parent] or 0) + w end
    elseif n.type == "gen" and r then
      local g = model.gen_info(n.entity)
      local cap = 0
      if g and g.power > 0 then
        local sat = 1
        for port, need in pairs(r.ins) do
          if need.need > 1e-12 then sat = math.min(sat, need.received / need.need) end
        end
        cap = g.power * (n.value or 0) * math.max(0, sat)
        r.sat = sat
      end
      r.power_cap = cap
      -- the plant this generator belongs to (nearest ancestor marked as plant)
      local p = n.parent
      while p and project.nodes[p] and not project.nodes[p].plant do p = project.nodes[p].parent end
      if p and project.nodes[p] then
        plant_cap[p] = (plant_cap[p] or 0) + cap
      end
    end
  end
  for pid, cap in pairs(plant_cap) do
    local owner = project.nodes[pid].parent or pid
    pool[owner] = (pool[owner] or 0) + cap
  end
  -- bottom-up over factories
  local facs = {}
  for id, n in pairs(project.nodes) do
    if n.type == "factory" then facs[#facs + 1] = id end
  end
  table.sort(facs, function(a, b) return get_depth(a) > get_depth(b) end)
  local unmet, total_need, used = {}, {}, {}
  for _, fid in pairs(facs) do
    local need = direct[fid] or 0
    local from_children = 0
    local subtree = direct[fid] or 0
    for _, c in pairs(model.children(project, fid)) do
      if c.type == "factory" then
        from_children = from_children + (unmet[c.id] or 0)
        subtree = subtree + (total_need[c.id] or 0)
      end
    end
    local want = need + from_children
    local cap = pool[fid] or 0
    local u = math.min(want, cap)
    used[fid] = u
    unmet[fid] = want - u
    total_need[fid] = subtree
    local r = res.nodes[fid]
    if r then
      r.power = { need = subtree, own = need, cap = cap, used = u, unmet = want - u, load = cap > 0 and u / cap or 0 }
    end
  end
  for pid, cap in pairs(plant_cap) do
    local owner = project.nodes[pid].parent or pid
    local r = res.nodes[pid]
    local o = res.nodes[owner] and res.nodes[owner].power
    if r and r.power then
      r.power.plant_cap = cap
      r.power.plant_load = o and o.load or 0
    end
  end
  res.power_deficit = unmet[project.root] or 0
end

-------------------------------------------------------------------------------
-- Surplus that could flow into a node: unused production of everything feeding it,
-- looking through pass-through nodes (inputs/outputs of factories, splitters).
-------------------------------------------------------------------------------
local PASS = { input = true, output = true, split = true }
function S.extra_into(nodes, res, id, seen)
  seen = seen or {}
  if seen[id] then return 0 end
  seen[id] = true
  local sn = nodes[id]
  if not sn then return 0 end
  local total = 0
  for _, ls in pairs(sn.in_links) do
    for _, l in pairs(ls) do
      local up = nodes[l.fn]
      local r = res.nodes[l.fn]
      if up and r then
        local nlinks = #up.out_links[l.fp]
        local o = r.outs[l.fp]
        if o then total = total + math.max(0, o.produced - o.delivered) / nlinks end
        if up.psplit then
          -- leftovers of a priority splitter
          total = total + 0
        elseif PASS[up.node.type] then
          local nouts = 0
          for _, ol in pairs(up.out_links) do nouts = nouts + #ol end
          total = total + S.extra_into(nodes, res, l.fn, seen) / math.max(1, nouts)
        end
      end
    end
  end
  return total
end

-------------------------------------------------------------------------------
-- Automatic surplus outputs of factories ("auto_outputs" switch)
-- Returns true when something changed (the project must be solved again).
-------------------------------------------------------------------------------
local AUTO_EPS = 1e-6
function S.sync_auto_outputs(project)
  local res = project.results
  if not res then return false end
  local changed = false
  for fid, f in pairs(project.nodes) do
    if f.type == "factory" then
      local kids = model.children(project, fid)
      local autos = {}
      for _, c in pairs(kids) do
        if c.auto then autos[c.item or "?"] = c end
      end
      if not f.auto_outputs then
        -- switched off: keep linked auto outputs as ordinary outputs, drop the rest
        for _, c in pairs(autos) do
          local linked = false
          for _, l in pairs(project.links) do
            if l.from.node == fid and l.from.port == "o:" .. c.id then linked = true end
          end
          if linked then
            c.auto = nil
            for _, l in pairs(project.links) do
              if l.to.node == c.id then l.auto = nil end
            end
          else
            model.delete_node(project, c)
          end
          changed = true
        end
      else
        -- surplus per item on the direct children (flow into auto outputs does not count as used)
        local surplus, ports = {}, {}
        for _, c in pairs(kids) do
          if c.type == "recipe" or c.type == "psplit" or c.type == "factory" then
            local r = res.nodes[c.id]
            local _, outs = model.node_ports(project, c)
            for _, p in pairs(outs) do
              local o = r and r.outs[p.key]
              if o and p.item then
                local used = 0
                for _, l in pairs(project.links) do
                  if l.from.node == c.id and l.from.port == p.key then
                    local t = project.nodes[l.to.node]
                    if not (t and t.auto) then used = used + ((res.links[l.id] or {}).flow or 0) end
                  end
                end
                local extra = o.produced - used
                if c.type == "factory" then extra = math.max(0, extra) + (o.extra or 0) end
                if f.auto_outputs_unlinked then
                  -- only ports that are not linked to anything
                  for _, l in pairs(project.links) do
                    if l.from.node == c.id and l.from.port == p.key and not (project.nodes[l.to.node] or {}).auto then extra = 0 break end
                  end
                end
                ports[p.item] = ports[p.item] or {}
                table.insert(ports[p.item], { node = c.id, port = p.key, extra = extra })
                if extra > AUTO_EPS then surplus[p.item] = (surplus[p.item] or 0) + extra end
              end
            end
          end
        end
        -- create outputs for new surplus items and wire every producing port to them
        for item, _ in pairs(surplus) do
          local a = autos[item]
          if not a then
            a = model.add_node(project, { type = "output", item = item, parent = fid, fixed = false, auto = true, x = 0, y = 100000 })
            autos[item] = a
            changed = true
          end
          for _, pp in pairs(ports[item]) do
            if pp.extra > AUTO_EPS then
              local exists = false
              for _, l in pairs(project.links) do
                if l.from.node == pp.node and l.from.port == pp.port and l.to.node == a.id then exists = true end
              end
              if not exists then
                local l = model.add_link(project, pp.node, pp.port, a.id, "in")
                if l then l.auto = true changed = true end
              end
            end
          end
        end
        -- outputs whose surplus is gone disappear unless something outside is still linked to them
        for item, a in pairs(autos) do
          if not surplus[item] then
            local linked = false
            for _, l in pairs(project.links) do
              if l.from.node == fid and l.from.port == "o:" .. a.id then linked = true end
            end
            if not linked then
              model.delete_node(project, a)
              changed = true
            end
          end
        end
      end
    end
  end
  return changed
end

function S.solve_all(project)
  local res = S.solve(project)
  for _ = 1, 4 do
    if not S.sync_auto_outputs(project) then break end
    res = S.solve(project)
  end
  return res
end

-------------------------------------------------------------------------------
-- Summary of a factory subtree
-------------------------------------------------------------------------------
function S.summary(project, factory_id)
  local res = project.results or S.solve(project)
  local sum = { inputs = {}, outputs = {}, missing = {}, surplus = {}, machines = {}, power = 0 }
  local function add(t, k, v) t[k] = (t[k] or 0) + v end
  for id, n in pairs(project.nodes) do
    if n.type ~= "factory" and (n.parent == factory_id or model.is_ancestor(project, factory_id, n)) then
      local r = res.nodes[id]
      if r then
        if n.type == "recipe" then
          local def, m = model.recipe_rates(n)
          if m then
            local e = sum.machines[m.name] or { count = 0, ceil = 0 }
            e.count = e.count + r.x
            e.ceil = e.ceil + math.ceil(r.x - 1e-6)
            sum.machines[m.name] = e
            if m.electric then sum.power = sum.power + m.power * r.x end
          end
          local ins = model.node_ports(project, n)
          for _, p in pairs(ins) do
            local pr = r.ins[p.key]
            if pr and not pr.linked and pr.need > EPS then add(sum.missing, p.item, pr.need) end
          end
        end
        if n.type ~= "output" or n.parent ~= factory_id then
          for _, p in pairs(select(2, model.node_ports(project, n))) do
            local pr = r.outs[p.key]
            if pr and n.type == "recipe" then
              local extra = pr.produced - pr.delivered
              if extra > 1e-7 then add(sum.surplus, p.item, extra) end
            end
          end
        end
        if n.parent == factory_id then
          if n.type == "input" then add(sum.inputs, n.item or "?", r.x) end
          if n.type == "output" then add(sum.outputs, n.item or "?", r.x) end
        end
      end
    end
  end
  local fr = res.nodes[factory_id]
  if fr and fr.power then
    sum.power_need = fr.power.need
    sum.power_cap = fr.power.cap
    sum.power_unmet = fr.power.unmet
  end
  return sum
end

return S
