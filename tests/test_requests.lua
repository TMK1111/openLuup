
local t = require "luaunit"

-- openLuup.requests TESTS
--

local requests  = require "openLuup.requests"
luup      = require "openLuup.luup"
local json      = require "openLuup.json"

local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
local devNo = luup.create_device (devType)
luup.variable_set ("myService","name1", 42, devNo)     -- add a couple of variables
luup.variable_set ("myService","name2", 88, devNo)     -- add a couple of variables

TestRequests = {}     -- luup tests

function TestRequests:setUp ()
end

function TestRequests:tearDown ()
end

-- basics

function TestRequests:test_basic_types ()
  t.assertIsFunction (requests.action)
  t.assertIsFunction (requests.alive)
  t.assertIsFunction (requests.debug)
  t.assertIsFunction (requests.exit)
  t.assertIsFunction (requests.file)
  t.assertIsFunction (requests.iprequests)
  t.assertIsFunction (requests.invoke)
  t.assertIsFunction (requests.jobstatus)
  t.assertIsFunction (requests.live_energy_usage)
  t.assertIsFunction (requests.room)
  t.assertIsFunction (requests.sdata)
  t.assertIsFunction (requests.status) 
  t.assertIsFunction (requests.status2) 
  t.assertIsFunction (requests.user_data) 
  t.assertIsFunction (requests.user_data2)
  t.assertIsFunction (requests.variableget) 
  t.assertIsFunction (requests.variableset)
  -- check functional identities 
  t.assertEquals (requests.status, requests.status2)
  t.assertEquals (requests.user_data, requests.user_data2)
end  

function TestRequests:test_action ()
end

function TestRequests:test_action_device_0 ()
-- eg:  /data_request?id=action&output_format=json&DeviceNum=0&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=SetHouseMode&Mode=2
  local parameters = {
    DeviceNum = "0", 
    serviceId = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",
    action= "SetHouseMode",
    Mode="2",
  }
  local response, mime = requests.action ("action", parameters, "json")
  t.assertIsString (response)
  t.assertEquals (response, '{"u:SetHouseModeResponse":{"OK":"OK"}}')
  local ok = json.decode (response)
  t.assertEquals (ok["u:SetHouseModeResponse"].OK, "OK")
end

function TestRequests:test_alive ()
  local x = requests.alive ()
  t.assertEquals (x, "OK")
end

function TestRequests:test_debug ()
  luup.debugON = false
  local d1 = luup.debugON
  local x = requests.debug ()
  local d2 = luup.debugON
  t.assertEquals (d1, not d2)
  local x = requests.debug ()
  local d3 = luup.debugON
  t.assertEquals (d3, not d2)
end

function TestRequests:test_exit ()
end

function TestRequests:test_file ()
end

function TestRequests:test_iprequests ()
end

function TestRequests:test_invoke ()
end

function TestRequests:test_jobstatus ()
end

function TestRequests:test_live_energy_usage ()
end

function TestRequests:test_sdata ()
  local jsdata = requests.sdata ()
  local sdata, msg = json.decode (jsdata)
  t.assertIsNil (msg)
  t.assertIsTable (sdata)
  t.assertEquals (sdata.full, 1)
  t.assertIsString (sdata.serial_number)
  
  -- test content of device table  
  t.assertIsTable (sdata.devices)
  local d = sdata.devices[1]
  t.assertIsString (d.name)
  t.assertIsString (d.altid)
  t.assertEquals (d.id, 1)
  t.assertIsNumber (d.category)
  t.assertIsNumber (d.subcategory)
  t.assertIsNumber (d.room)
--  t.assertIsNumber (d.device_num_parent)    -- possibly missing
end

function TestRequests:test_status ()
  local format
  local parameters = {}
  local jstatus = requests.status ("status", parameters, format)
  local status, msg = json.decode (jstatus)
  t.assertIsNil (msg)
  t.assertIsTable (status)
end

function TestRequests:test_user_data ()
  local format
  local parameters = {}
  local juser = requests.user_data ("user_data", parameters, format)
  local user, msg = json.decode (juser)
  t.assertIsNil (msg)
  t.assertIsTable (user)
  
  -- now ask again, specifying data version
  local dv = user.DataVersion
  t.assertIsNumber (dv)
  parameters.DataVersion = tostring(dv)
  local juser2 = requests.user_data ("user_data", parameters, format)
--  t.assertEquals (juser2, "NO CHANGES")   -- should be a plain text return
  
  -- test content of device table  
  t.assertIsTable (user.devices)
  local d = user.devices[1]
  t.assertIsString (d.device_type)
  t.assertIsNumber (d.category_num)
  t.assertIsString (d.invisible)
  t.assertIsString (d.name)
  t.assertIsString (d.room)
  t.assertIsTable (d.states)
  t.assertIsNumber (d.time_created)
end

function TestRequests:test_variableget_set ()
  local srv = "myService"
  local val = "42"
  local var = "foo"
  local parameters = {serviceId=srv, DeviceNum="1", Variable=var, Value=val}
  requests.variableset ('variableset', parameters)
  parameters.Value= nil
  local value = requests.variableget ('variableget', parameters)
  t.assertEquals (value, val)
  local v = luup.variable_get (srv, var, 1)
  t.assertEquals (value, v)
end

function TestRequests:test_variableget_set_0 ()
  local parameters = {DeviceNum="0", Variable="foo", Value="42"}
  requests.variableset ('variableset', parameters)
  parameters.Value= nil
  local value = requests.variableget ('variableset', parameters)
  t.assertEquals (value, "42")
  t.assertEquals (luup.attr_get "foo", value)
  -- and again with missing DeviceNum
  parameters = {Variable = "garp", Value = "pi"}
  requests.variableset ('variableset', parameters)
  parameters.Value= nil
  value = requests.variableget ('variableget', parameters)
  t.assertEquals (value, "pi")
  t.assertEquals (luup.attr_get "garp", value)
end

-- ROOMS

TestRoomRequests = {}

--Example: http://ip_address:3480/data_request?id=room&action=create&name=Kitchen
function TestRoomRequests:test_room_create ()
  local parameters = {action = "create", name = "test_room_name"}
  local n = #luup.rooms
  local r = requests.room ("room", parameters)
  local m = #luup.rooms
  t.assertEquals (m, n+1)
  t.assertEquals (r, "OK")
  t.assertEquals (luup.rooms[m], "test_room_name")
end

--Example: http://ip_address:3480/data_request?id=room&action=rename&room=5&name=Garage
function TestRoomRequests:test_room_rename ()
  requests.room ("room", {action = "create", name = "test_room_name"})
  local n = #luup.rooms
  local parameters = {action = "rename", room = tostring(n), name = "test_room_rename"}
  local r = requests.room ("room", parameters)
  t.assertEquals (r, "OK")
  t.assertEquals (luup.rooms[n], "test_room_rename")
end

--Example: http://ip_address:3480/data_request?id=room&action=delete&room=5
function TestRoomRequests:test_room_delete ()
  local n = #luup.rooms
  local parameters = {action = "delete", room = tostring(n)}
  local x = requests.room ("room", parameters)
  local m = #luup.rooms
  t.assertEquals (x, "OK")
  t.assertEquals (m, n-1)  
  t.assertIsNil (luup.rooms[n])
end

-- SCENES

local example_scene = {
  id = 42,
  name = "test_scene_name",
  room = 0,
  groups = {
    {
      delay = 0,
      actions = {
        {
          action = "ToggleState",
          arguments = {},
          device = "94",   -- why this is a string, I have NO idea
          service ="urn:micasaverde-com:serviceId:HaDevice1",
        },
      },
    },
  },
  timers = {
    {
      enabled = 1,
      id = 1,
      interval = "5m",        -- this is actually the "time" parameter in timer calls
      name = "Five minutes",
      type = 1,
    } , 
    {
      enabled = 1,
      id = 2,
      interval = "10",        -- this is actually the "time" parameter in timer calls
      name = "Ten Seconds",
      type = 1,
    } , 
  },
  lua =   -- this HAS to be a string for external tools to work.
  [[
    luup.log "hello from 'test_scene_name'"
  ]],   
}

TestSceneRequests = {}

local json_example_scene = json.encode (example_scene)

local function scene_count ()
  local n = 0
  for _ in pairs (luup.scenes) do n = n + 1 end
  return n
end

function TestSceneRequests:setUp ()
  local parameters = {action = "create", json = json_example_scene}
  local s = requests.scene ("scene", parameters)
  t.assertEquals (s, "OK")
end

--Example: http://ip_address:3480/data_request?id=scene&action=create&json=[valid json data]
function TestSceneRequests:test_scene_create ()
  -- all done in setUp ()
end

--Example: http://ip_address:3480/data_request?id=scene&action=rename&scene=5&name=Chandelier&room=Garage
function TestSceneRequests:test_scene_rename ()
  local n = scene_count()
  local new_name = "new test scene name " .. os.time()    -- ensure unique name
  local parameters = {action = "rename", scene = 42, name = new_name}
  local s = requests.scene ("scene", parameters)
  t.assertEquals (s, "OK")
  t.assertEquals (luup.scenes[42].name, new_name)
end

--Example: http://ip_address:3480/data_request?id=scene&action=delete&scene=5
function TestSceneRequests:test_scene_delete ()
  local parameters = {action = "delete", scene = 42}
  local s = requests.scene ("scene", parameters)
  t.assertIsNil (luup.scenes[42])
end

--Example: http://ip_address:3480/data_request?id=scene&action=list&scene=5
function TestSceneRequests:test_scene_list ()
  local parameters = {action = "list", scene = 42}
  local s = requests.scene ("scene", parameters)
  t.assertIsString (s)
  local lua, msg = json.decode (s)
  t.assertIsTable (lua)
  t.assertIsNil (msg)
  lua.Timestamp = nil             -- remove the creation timestamp
  lua.triggers = nil              -- remove triggers
  lua.modeStatus = nil            -- ditto
  lua.favorite = nil
  
  local s2 = json.encode (lua)    -- re-encode
  t.assertEquals (s2, json_example_scene)
end

-- now the same thing over again going through the whole HTTP client request / server response chain 
  local server = require "openLuup.server"
  server.add_callback_handlers (requests)       -- tell the HTTP server to use these callbacks

function TestSceneRequests:test_wget_scene_list ()
  local req = "http://127.0.0.1:2480/data_request?id=scene&action=list&scene=42"
  local ok,s = luup.inet.wget (req)
  t.assertEquals (ok, 0)
  t.assertIsString (s)
  local lua, msg = json.decode (s)
  t.assertIsTable (lua)
  t.assertIsNil (msg)
  lua.Timestamp = nil             -- remove the creation timestamp
  lua.triggers = nil              -- remove triggers
  lua.modeStatus = nil            -- ditto
  lua.favorite = nil
  
  local s2 = json.encode (lua)    -- re-encode
  t.assertEquals (s2, json_example_scene)
end

function TestSceneRequests:test_ ()
end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
