-- ============================================================================
-- WORKSPACE GROUPS: every monitor owns its own row of workspaces.
--
-- Monitors are numbered left to right (then top to bottom). Monitor k owns the
-- workspace ids k*10+1 … k*10+10, so "workspace 3" means id 3 on the first
-- monitor and id 13 on the second. Waybar shows each monitor's row as circles.
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

-- First workspace id minus one of the group that belongs to `monitor`.
local function base_of(monitor)
    for index, m in ipairs(sorted_monitors()) do
        if monitor and m.name == monitor.name then
            return (index - 1) * GROUP_SIZE
        end
    end
    return 0
end

local function focused_monitor()
    return hl.get_active_monitor()
end

-- Position (1-10) of the focused workspace inside its group.
local function current_slot()
    local monitor = focused_monitor()
    local ws = monitor and monitor.active_workspace
    if not ws or not ws.id or ws.id < 1 then
        return 1
    end
    return ((ws.id - 1) % GROUP_SIZE) + 1
end

-- Bind every group to its monitor so a workspace never opens on the wrong
-- screen; the first `persistent` ones exist even when empty (the circles).
-- Called at start and whenever monitors change; old rules are switched off.
local rules = {}

function M.apply_rules()
    for _, rule in ipairs(rules) do
        rule:set_enabled(false)
    end
    rules = {}
    for index, m in ipairs(sorted_monitors()) do
        local base = (index - 1) * GROUP_SIZE
        for slot = 1, GROUP_SIZE do
            table.insert(rules, hl.workspace_rule({
                workspace  = tostring(base + slot),
                monitor    = m.name,
                default    = slot == 1,
                persistent = slot <= M.settings.persistent,
            }))
        end
    end
end

-- Switch to workspace `slot` (1-10): on the focused monitor, or on all
-- monitors in "all" mode (the focused monitor last, so it keeps the focus).
function M.go(slot)
    local focused = focused_monitor()
    if M.settings.mode == "all" then
        for index, m in ipairs(sorted_monitors()) do
            if not focused or m.name ~= focused.name then
                hl.dispatch(hl.dsp.focus({ workspace = (index - 1) * GROUP_SIZE + slot }))
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

aco_workspaces = M
return M
