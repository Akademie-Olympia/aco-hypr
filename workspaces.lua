-- ============================================================================
-- WORKSPACE GROUPS: every monitor owns its own row of workspaces.
--
-- Group k is the workspace ids k*10+1 … k*10+10. A monitor keeps the group
-- of the workspace it shows, so rearranging monitors never mixes rows; a
-- monitor that is plugged in gets the lowest free group (at start: left to
-- right, so the first monitor has 1-10, the second 11-20). "Workspace 3"
-- therefore means id 3 on one monitor and id 13 on the next. Waybar shows each
-- monitor's row as circles.
--
-- Settings in ~/.config/aco/workspaces.conf (written by the settings hub):
--   mode       = monitor   Super+N switches only the focused monitor (default)
--              | all       Super+N switches every monitor to its workspace N
--   persistent = 5         circles that always exist per monitor (0-10)
--
-- Loaded by hyprland.lua; returns the functions the key bindings use. They are
-- also exported as the global `aco_workspaces` so Waybar and scripts can call
-- them through `hyprctl eval 'aco_workspaces.step(1)'`.
-- ============================================================================

local M = {}

local GROUP_SIZE = 10
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local settings_file = config_home .. "/aco/workspaces.conf"

-- Read "key = value" lines; unknown keys are ignored, bad values fall back.
local function read_settings()
    local settings = { mode = "monitor", persistent = 5 }
    local file = io.open(settings_file, "r")
    if not file then
        return settings
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(%S+)%s*$")
        if key == "mode" and (value == "monitor" or value == "all") then
            settings.mode = value
        elseif key == "persistent" and tonumber(value) then
            settings.persistent = math.max(0, math.min(GROUP_SIZE, math.floor(tonumber(value))))
        end
    end
    file:close()
    return settings
end

M.settings = read_settings()

-- Enabled, non-mirrored monitors from left to right, then top to bottom.
local function sorted_monitors()
    local monitors = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.enabled ~= false and not m.is_mirror then
            table.insert(monitors, m)
        end
    end
    table.sort(monitors, function(a, b)
        if (a.x or 0) ~= (b.x or 0) then
            return (a.x or 0) < (b.x or 0)
        end
        return (a.y or 0) < (b.y or 0)
    end)
    return monitors
end

-- Group of a workspace id (0 for 1-10, 1 for 11-20, …).
local function group_of(id)
    return math.floor((id - 1) / GROUP_SIZE)
end

-- The normal (not special) workspace a monitor shows, if any.
local function shown_id(monitor)
    local ws = monitor and monitor.active_workspace
    if ws and ws.id and ws.id > 0 and not ws.special then
        return ws.id
    end
end

-- Group per monitor name, decided in apply_rules().
local assigned = {}

-- First workspace id minus one of the group that belongs to `monitor`.
local function base_of(monitor)
    if not monitor then
        return 0
    end
    local id = shown_id(monitor)
    if id then
        return group_of(id) * GROUP_SIZE
    end
    return (assigned[monitor.name] or 0) * GROUP_SIZE
end

local function focused_monitor()
    return hl.get_active_monitor()
end

-- Position (1-10) of the focused workspace inside its group.
local function current_slot()
    local id = shown_id(focused_monitor())
    if not id then
        return 1
    end
    return ((id - 1) % GROUP_SIZE) + 1
end

-- Give every monitor a group and bind the group's workspaces to it, so they
-- never open on the wrong screen; the first `persistent` ones exist even when
-- empty (the circles). A monitor keeps the group it shows; monitors without
-- one (just plugged in, or sharing a group at start) get the lowest free group
-- and switch to its first workspace. Workspaces of a group that wandered to
-- another monitor (after unplugging) move back to their owner. Called at start
-- and whenever monitors come or go; old rules are switched off.
local rules = {}

function M.apply_rules()
    local monitors = sorted_monitors()
    local used, pending = {}, {}
    assigned = {}
    for _, m in ipairs(monitors) do
        local id = shown_id(m)
        if id and not used[group_of(id)] then
            assigned[m.name] = group_of(id)
            used[group_of(id)] = true
        else
            table.insert(pending, m)
        end
    end
    for _, m in ipairs(pending) do
        local group = 0
        while used[group] do
            group = group + 1
        end
        assigned[m.name] = group
        used[group] = true
    end

    for _, rule in ipairs(rules) do
        rule:set_enabled(false)
    end
    rules = {}
    for _, m in ipairs(monitors) do
        local base = assigned[m.name] * GROUP_SIZE
        for slot = 1, GROUP_SIZE do
            table.insert(rules, hl.workspace_rule({
                workspace  = tostring(base + slot),
                monitor    = m.name,
                default    = slot == 1,
                persistent = slot <= M.settings.persistent,
            }))
        end
    end

    local owner = {}
    for name, group in pairs(assigned) do
        owner[group] = name
    end
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        local name = ws.id and ws.id > 0 and owner[group_of(ws.id)]
        if name and ws.monitor and ws.monitor.name ~= name then
            hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = name }))
        end
    end

    -- Monitors that got a new group show its first workspace; focus returns.
    local focused = focused_monitor()
    for _, m in ipairs(pending) do
        hl.dispatch(hl.dsp.focus({ workspace = assigned[m.name] * GROUP_SIZE + 1 }))
    end
    if #pending > 0 and focused then
        hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
    end
end

-- Switch to workspace `slot` (1-10): on the focused monitor, or on all
-- monitors in "all" mode (the focused monitor last, so it keeps the focus).
function M.go(slot)
    local focused = focused_monitor()
    if M.settings.mode == "all" then
        for _, m in ipairs(sorted_monitors()) do
            if not focused or m.name ~= focused.name then
                hl.dispatch(hl.dsp.focus({ workspace = base_of(m) + slot }))
            end
        end
    end
    hl.dispatch(hl.dsp.focus({ workspace = base_of(focused) + slot }))
end

-- Move the active window to workspace `slot` of its own monitor and follow it.
function M.move(slot)
    hl.dispatch(hl.dsp.window.move({ workspace = base_of(focused_monitor()) + slot }))
end

-- Next/previous workspace (step = +1/-1) within the group, without wrapping
-- past the last circle that exists, so scrolling never spawns new ones.
local function last_used_slot()
    local monitor = focused_monitor()
    local base = base_of(monitor)
    local last = math.max(M.settings.persistent, current_slot())
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        if ws.id and ws.id > base and ws.id <= base + GROUP_SIZE and (ws.windows or 0) > 0 then
            last = math.max(last, ws.id - base)
        end
    end
    return last
end

function M.step(step)
    local target = current_slot() + step
    if target < 1 or target > last_used_slot() then
        return
    end
    M.go(target)
end

function M.move_step(step)
    local target = current_slot() + step
    if target >= 1 and target <= GROUP_SIZE then
        M.move(target)
    end
end

-- First workspace of the group without windows.
local function first_empty_slot()
    local base = base_of(focused_monitor())
    local used = {}
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        if ws.id and (ws.windows or 0) > 0 then
            used[ws.id] = true
        end
    end
    for slot = 1, GROUP_SIZE do
        if not used[base + slot] then
            return slot
        end
    end
end

function M.go_empty()
    local slot = first_empty_slot()
    if slot then
        M.go(slot)
    end
end

function M.move_empty()
    local slot = first_empty_slot()
    if slot then
        M.move(slot)
    end
end

-- Switch only if the workspace already has windows or is a persistent circle.
function M.go_existing(slot)
    local id = base_of(focused_monitor()) + slot
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        if ws.id == id then
            M.go(slot)
            return
        end
    end
end

-- Swap the whole rows of the focused monitor and the next one (left to
-- right): every workspace of each group moves to the other monitor, then the
-- groups are re-bound, so Super+N keeps meaning "this monitor".
function M.swap_with_next_monitor()
    local monitors = sorted_monitors()
    local focused = focused_monitor()
    if #monitors < 2 or not focused then
        return
    end
    local index = 1
    for i, m in ipairs(monitors) do
        if m.name == focused.name then
            index = i
        end
    end
    local other = monitors[(index % #monitors) + 1]
    local mine, theirs = group_of(base_of(focused) + 1), group_of(base_of(other) + 1)
    local target = { [mine] = other.name, [theirs] = focused.name }
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        local name = ws.id and ws.id > 0 and target[group_of(ws.id)]
        if name then
            hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = name }))
        end
    end
    M.apply_rules()
end

aco_workspaces = M
return M
