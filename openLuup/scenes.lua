local ABOUT = {
  NAME          = "openLuup.scenes",
  VERSION       = "2017.01.15",
  DESCRIPTION   = "openLuup SCENES",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2016 AK Booer

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]
}

-- openLuup SCENES module

--
-- all scene-related functions 
-- see: http://wiki.micasaverde.com/index.php/Scene_Syntax for stored scene syntax
--
-- 2016.03.11   verify that scenes don't reference non-existent devices.  Thanks @delle
-- 2016.04.10   add 'running' flag for status and sdata "active" and "status" info.   Thanks @ronluna
-- 2016.04.20   make pause work
-- 2016.05.19   allow trigger data to be stored (for PLEG / RTS)
--              see: http://forum.micasaverde.com/index.php/topic,34476.msg282148.html#msg282148
-- 2016.10.29   add notes to timer jobs (changed to job.type)
-- 2016.11.01   add new_userdata_dataversion() to successful scene execution
-- 2016.11.18   add scene finisher type to final delay.

-- 2017.01.05   add lul_scene to the scope of the scene Lua (to contain the scene Id)
-- 2017.01.15   remove scene triggers which refer to missing devices (thanks @reneboer)
--              see: http://forum.micasaverde.com/index.php/topic,41249.msg306385.html#msg306385

local logs      = require "openLuup.logs"
local json      = require "openLuup.json"
local timers    = require "openLuup.timers"
local loader    = require "openLuup.loader"
local scheduler = require "openLuup.scheduler"    -- simply for adding notes to the timer jobs
local devutil   = require "openLuup.devices"      -- for new_userdata_dataversion

--  local logs
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end
local _log_altui_scene  = logs.altui_scene

logs.banner (ABOUT)   -- for version control

--[[

Whilst 'actions' and 'timers' are straight-forward, the 'trigger' functionality of Luup is severely flawed, IMHO, through the close connection to UPnP service files and .json files.  

The goal would be to have an interface like HomeSeer, with extremely intuitive syntax to define triggers and conditions.  To support this at the openLuup engine level, all trigger conditions are handled through a standard initial luup.variable_watch call - so no new infrastructure is needed - to a handler which then evaulates the condition and, if true, continues to evaluate further states required for the scene to run.

Sept 2015 - ALTUI now provides this functionality through its own variable watch callback 
which then triggers scenes if some Lua boolean expression is true
ALTUI also provides a great editor interface with the blockly module.

Apr 2016 - AltUI now provides workflow too.

--]]

---
--- utilities
--

-- single environment for all scenes and startup code
local scene_environment = loader.shared_environment

local function load_lua_code (lua, id)
  local scene_lua, error_msg, code
  if lua then
    local scene_name = "scene_" .. id
    local wrapper = table.concat ({"function ", scene_name, " (lul_scene)", lua, "end"}, '\n')  -- 2017.01.05
    local name = "scene_" .. id .. "_lua"
    code, error_msg = loader.compile_lua (wrapper, name, scene_environment) -- load, compile, instantiate
    scene_lua = (code or {}) [scene_name]
  end
  return scene_lua, error_msg
end

local function verify_all()
  for _,s in pairs(luup.scenes) do
    s.verify()
  end
end

-- run all the actions in one delay group
local function group_runner (actions)
  for _, a in ipairs (actions) do
    local args = {}
    for _, arg in pairs(a.arguments) do   -- fix parameters handling.  Thanks @delle !
      args[arg.name] = arg.value
    end
    luup.call_action (a.service, a.action, args, tonumber (a.device))
  end

end

-- return true if scene can run in current house mode
local function runs_in_current_mode (scene)
  local modeStatus = scene.modeStatus
  local currentMode = luup.attr_get "Mode"
  return (modeStatus == "0") or modeStatus:match (currentMode)
end



-- scene.create() - returns compiled scene object given json string containing group / timers / lua / ...
local function create (scene_json)
  local scene, lua_code, luup_scene
  
  local function scene_finisher (started)         -- called at end of scene
    if scene.last_run == started then 
      luup_scene.running = false                  -- clear running flag only if we set it
    end
  end
  
  local function scene_runner (t, next_time)              -- called by timer, trigger, or manual run
    if not runs_in_current_mode (scene) then 
      _log (scene.name .. " does not run in current House Mode")
      return 
    end
    if luup_scene.paused then 
      _log (scene.name .. " is currently paused")
      return 
    end
    if t and tonumber (t.enabled) ~= 1  then 
      _log "timer disabled"
      return 
    end   -- timer or trigger disabled
    local ok = not lua_code or lua_code (scene.id)    -- 2017.01.05
    if ok ~= false then
      scene.last_run = os.time()                -- scene run time
      luup_scene.running = true
      devutil.new_userdata_dataversion ()               -- 2016.11.01
      local runner = "command"
      if t then
        t.last_run = scene.last_run             -- timer or trigger specific run time
        t.next_run = next_time                  -- only non-nil for timers
        runner = (t.name ~= '' and t.name) or '?'
      end
      local msg = ("scene %d, %s, initiated by %s"): format (scene.id, scene.name, runner)
      _log (msg, "luup.scenes")
      _log_altui_scene (scene)                  -- log for altUI to see
      local max_delay = 0
      local label = "scene#" .. scene.id
      for _, group in ipairs (scene.groups) do  -- schedule the various delay groups
        local delay = tonumber (group.delay) or 0
        if delay > max_delay then max_delay = delay end
        timers.call_delay (group_runner, delay, group.actions, label .. "group delay")
      end
      timers.call_delay (scene_finisher, max_delay + 30, scene.last_run, 
        label .. " finisher")    -- say we're finished
    end
  end
  
  local function scene_stopper ()
    -- TODO: cancel timers on scene delete, etc..?
--    for _,j in ipairs (jobs) do
--      scheduler.kill_job (j.
--    end
    -- disable all timers and triggers
    for _, t in ipairs (scene.timers or {}) do
      t.enabled = 0
    end
    for _, t in ipairs (scene.triggers or {}) do
      t.enabled = 0
    end
  end

  -- called if SOMEBODY changes ANY device variable in ANY service used in this scene's actions
  local function scene_watcher (...)
--    luup.log ("SCENE_WATCHER: " .. json.encode {
--              {scene=scene.id, name=scene.name}, ...})
    -- TODO: use this to clear scene 'running' flag
  end

  local function scene_rename (name, room)
    scene.name = name or scene.name
    scene.room = room or scene.room
    luup_scene.description = scene.name     -- luup is SO inconsistent with names!
    luup_scene.room_num = scene.room
  end

  local function user_table ()          -- used by user_data request
    return scene
  end

  -- delete any actions which refer to non-existent devices
  -- also, add listeners to the device AND service to watch for changes
  -- also, remove any triggers reltated to unkown devices
  local function verify ()
    local silent = true     -- don't log watch callbacks
    for _, g in ipairs (scene.groups or {}) do
      local actions = g.actions or {}
      local n = #actions 
      for i = n,1,-1 do       -- go backwards through list since it may be shortened in the process
        local a = actions[i]
        local dev = luup.devices[tonumber(a.device)]
        if dev then
          local name = "_scene" .. scene.id
          devutil.variable_watch (dev, scene_watcher, a.service, nil, name, silent) -- NB: ALL variables in service
        else
          table.remove (actions,i)
        end
      end      
    end
    -- triggers
    local triggers = scene.triggers or {}
    local n = #triggers
    for i = n,1,-1 do       -- go backwards through list since it may be shortened in the process
      local t = triggers[i]
      if not luup.devices[t.device] then
        table.remove (triggers, i)
      end
    end
  end

  --create ()
  local scn, err
  if type(scene_json) == "table" then         -- it's not actually JSON
    scn = scene_json                        -- ...assume it's Lua
  else
    scn, err = json.decode (scene_json)     -- or decode the JSON
  end
  if not scn then return nil, err end
  
  lua_code, err = load_lua_code (scn.lua, scn.id or (#luup.scenes + 1))   -- load the Lua
  if err then return nil, err end
  
--[[
  scene should be something like
    {
      id        = 42,
      name      = "title",
      room      = 3,
      groups    = {...},
      triggers  = {...},
      timers    = {...},
      lua       = "....",
      paused    = "0",        -- also this! "1" == paused
    }
    
    -- also notification_only = device_no,  which hides the scene ???
--]]

  scene = scn   -- there may be other data there than that which is possibly modified below...
  
  scene.Timestamp   = scn.Timestamp or os.time()   -- creation time stamp
  scene.favorite    = scn.favorite or false
  scene.groups      = scn.groups or {}
  scene.id          = tonumber (scn.id) or (#luup.scenes + 1)  -- given id or next one available
  scene.modeStatus  = scn.modeStatus or "0"          -- comma separated list of enabled modes ("0" = all)
  scene.paused      = scn.paused or "0"              -- 2016.04.30
  scene.room        = tonumber (scn.room) or 0       -- TODO: ensure room number valid
  scene.timers      = scn.timers or {}
  scene.triggers    = scn.triggers or {}             -- 2016.05.19
  
  verify()   -- check that non-existent devices are not referenced
  
  local meta = {
    -- variables
    running     = false,    -- set to true when run and reset 30 seconds after last action
    jobs        = {},       -- list of jobs that scene is running (ie. timers)
    -- methods
    rename      = scene_rename,
    run         = scene_runner,
    stop        = scene_stopper,
    user_table  = user_table,
    verify      = verify,
  }
  
  luup_scene = {
      description = scene.name,
      hidden = false,
      page = 0,           -- TODO: discover what page and remote are for
      paused = tonumber (scene.paused) == 1,     -- 2016.04.30 
      remote = 0,
      room_num = scene.room,
    }
  
  -- start the timers
  local recurring = true
  local jobs = meta.jobs
  local info = "job#%d :timer '%s' for scene [%d] %s"
  for _, t in ipairs (scene.timers or {}) do
    local _,_,j,_,due = timers.call_timer (scene_runner, t.type, t.time or t.interval, 
                          t.days_of_week or t.days_of_month, t, recurring)
    if j and scheduler.job_list[j] then
      local job = scheduler.job_list[j]
      local text = info: format (j, t.name or '?', scene.id or 0, scene.name or '?') -- 2016.10.29
      job.type = text
      t.next_run = due
      jobs[#jobs+1] = j           -- save the jobs we're running
    end
  end

-- luup.scenes contains all the scenes in the system as a table indexed by the scene number. 
  return setmetatable (luup_scene, {
      __index = meta, 
      __tostring = function () return json.encode (user_table()) or '?' end,
    })
end

---- export variables and methods

return {
    ABOUT = ABOUT,
    
    -- constants
    environment   = scene_environment,      -- to be shared with startup code
    -- variables
    -- methods
    create        = create,
    verify_all    = verify_all,
  }
