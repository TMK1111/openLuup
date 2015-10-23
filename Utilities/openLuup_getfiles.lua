-- getfiles
--
-- copy relevant files from remote Vera
--
-- 2015-10-11   @akbooer
--

local luup = require "openLuup/luup"
local url  = require "socket.url"

local code = [[

local function get_dir (dir)
  local x = io.popen ("ls -1 " .. dir)
  if x then
    local y = x:read "*a"
    x:close ()
    return y
  end
end

local function put_dir (file, text)
  local f = io.open (file, 'w')
  if f then
    f:write (text)
    f: close ()
  end
end

local d = get_dir "%s"
if d then 
  put_dir ("/www/directory.txt", d)
end

]]

print "openLuup_getfiles - utility to get device and icon files from remote Vera"

io.write "Remote Vera IP: "
local ip = io.read ()

local function get_directory (path)
  local template = "http://%s:3480/data_request?id=action" ..
                    "&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1" ..
                    "&action=RunLua&Code=%s"
  local request = template:format (ip, url.escape (code: format(path)))

  local status, info = luup.inet.wget (request)
  assert (status == 0, "error creating remote directory listing")

  status, info = luup.inet.wget ("http://" .. ip .. "/directory.txt")
  assert (status == 0, "error reading remote directory listing")
  return info
end

local function get_files_from (path, dest, url_prefix)
  dest = dest or '.'
  url_prefix = url_prefix or ":3480/"
  local info = get_directory (path)
  for x in info: gmatch "%C+" do
    local status
    local fname = x:gsub ("%.lzo",'')   -- remove unwanted extension for compressed files
    status, info = luup.inet.wget ("http://" .. ip .. url_prefix .. fname)
    if status == 0 then
      print (#info, fname)
      
      local f = io.open (dest .. '/' .. fname, 'w')
      f:write (info)
      f:close ()
    else
      print ("error", fname, info)
    end
  end
end

-- device, service, lua, json, files...
os.execute "mkdir -p files"
get_files_from ("/etc/cmh-ludl/", "files", ":3480/")
get_files_from ("/etc/cmh-lu/", "files", ":3480/")

-- icons
os.execute "mkdir -p icons"
get_files_from ("/www/cmh/skins/default/img/devices/device_states/", 
  "icons", "/cmh/skins/default/img/devices/device_states/")   -- UI7
--get_files_from ("/www/cmh/skins/default/icons/", "icons", "/cmh/skins/default/icons/")   -- UI5




