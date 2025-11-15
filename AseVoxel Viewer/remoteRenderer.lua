-- RemoteRenderer.lua
-- Aseprite-native WebSocket client helper for remote voxel rendering.
-- Uses Aseprite's built-in WebSocket() API to send the model to a Node.js server
-- and receive a rendered PNG (binary or base64 text).

local RemoteRenderer = {}

-- Defaults (Aseprite supports ws://)
local DEFAULT_URL = "ws://127.0.0.1:9000"

-- State
local _enabled = true
local _url = DEFAULT_URL
local _ws = nil
local _connected = false
local _status = "idle"
local _lastError = nil
local _inflight = false

-- Pending response from server
local _pendingReady = false
local _pending = nil -- { kind = "text"|"binary", data = string }

-- Minimal JSON
local function escape_str(s)
  s = s:gsub('\\', '\\\\'):gsub('"', '\\"')
  s = s:gsub('\b', '\\b'):gsub('\f', '\\f'):gsub('\n', '\\n')
       :gsub('\r', '\\r'):gsub('\t', '\\t')
  return s
end
local function is_array(t)
  if type(t) ~= "table" then return false end
  local maxk = 0
  for k,_ in pairs(t) do if type(k) ~= "number" then return false end if k > maxk then maxk = k end end
  return true
end
local function json_encode(v)
  local tv = type(v)
  if tv == "nil" then return "null"
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "number" then return tostring(v)
  elseif tv == "string" then return '"'..escape_str(v)..'"'
  elseif tv == "table" then
    if is_array(v) then
      local parts = {}
      for i=1,#v do parts[#parts+1] = json_encode(v[i]) end
      return "["..table.concat(parts,",").."]"
    else
      local parts = {}
      for k,val in pairs(v) do parts[#parts+1] = '"'..escape_str(tostring(k))..'":'..json_encode(val) end
      return "{"..table.concat(parts,",").."}"
    end
  end
  return "null"
end

-- Base64 decode
local function b64_decode(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  data = data:gsub('[^'..b..'=]', '')
  return (data:gsub('.', function(x)
    if x == '=' then return '' end
    local r,f = '', (b:find(x)-1)
    for i=6,1,-1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
    return r
  end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
    if #x ~= 8 then return '' end
    local c = 0
    for i=1,8 do c = c + (x:sub(i,i)=='1' and 2^(8-i) or 0) end
    return string.char(c)
  end))
end

-- File helpers
local function write_bytes_to_file(path, bytes)
  local f, err = io.open(path, "wb"); if not f then return nil, err end
  f:write(bytes); f:close(); return true
end
local function make_temp_dir()
  local base = app.fs.userConfigPath or "."
  local dir = app.fs.joinPath(base, "AseVoxelRemote")
  if not app.fs.isDirectory(dir) then pcall(function() app.fs.makeDirectory(dir) end) end
  return dir
end
local function load_png_as_image(path)
  local spr = nil
  local ok, err = pcall(function() spr = Sprite{ fromFile = path } end)
  if not ok or not spr then return nil, "Failed to open PNG as Sprite: "..tostring(err) end
  local img = nil
  pcall(function() if spr.cels and #spr.cels >= 1 then img = spr.cels[1].image:clone() end end)
  pcall(function() app.activeSprite = spr; app.command.CloseFile() end)
  if not img then return nil, "No image data in loaded PNG" end
  return img
end

-- Yielding wait helper: lets Aseprite dispatch ws events
local function pump(ms)
  -- ms in milliseconds; fall back to refresh if app.wait not available
  if app and app.wait then pcall(function() app.wait(ms or 10) end)
  else pcall(function() app.refresh() end) end
end
local function spin_wait_until(pred, timeout_sec)
  local t0 = os.clock()
  while (os.clock() - t0) < (timeout_sec or 5) do
    if pred() then return true end
    pump(10)
  end
  return false
end

-- WebSocket callbacks
local function handleMessage(mt, data)
  if mt == WebSocketMessageType.OPEN then
    _connected = true
    _status = "connected"
    _lastError = nil
    -- print("[RemoteRenderer] OPEN")

  elseif mt == WebSocketMessageType.CLOSE then
    _connected = false
    _status = "closed"
    -- print("[RemoteRenderer] CLOSE")

  elseif mt == WebSocketMessageType.TEXT then
    if _inflight and not _pendingReady then
      _pending = { kind = "text", data = data or "" }
      _pendingReady = true
    end

  elseif mt == WebSocketMessageType.BINARY then
    if _inflight and not _pendingReady then
      _pending = { kind = "binary", data = data or "" }
      _pendingReady = true
    end

  elseif mt == WebSocketMessageType.PING then
    -- ignore
  elseif mt == WebSocketMessageType.PONG then
    -- ignore
  elseif mt == WebSocketMessageType.FRAGMENT then
    -- ignore
  end
end

local function ensure_socket()
  if _ws ~= nil then return end
  _ws = WebSocket{
    onreceive = handleMessage,
    url = _url,
    deflate = false,
    minreconnectwait = 0.5,
    maxreconnectwait = 2.0
  }
  _status = "created"
end

local function ensure_connected(timeout_sec)
  ensure_socket()
  if _connected then return true end
  _status = "connecting"
  local ok, err = pcall(function() _ws:connect() end)
  if not ok then
    _lastError = "connect() failed: " .. tostring(err)
    _status = "error"
    return false
  end
  -- Wait longer and yield UI so OPEN can fire
  local connected = spin_wait_until(function() return _connected end, timeout_sec or 10)
  if not connected then
    _lastError = "timeout connecting to " .. tostring(_url)
    _status = "timeout"
  end
  return connected
end

-- Public API
function RemoteRenderer.enable(v) _enabled = not not v end
function RemoteRenderer.isEnabled() return _enabled end
function RemoteRenderer.setUrl(u)
  if type(u) == "string" and u ~= "" then
    _url = u
    if _ws then pcall(function() _ws:close() end) end
    _ws = nil; _connected = false; _status = "idle"
  end
end
function RemoteRenderer.getStatus()
  return { enabled=_enabled, connected=_connected, status=_status, lastError=_lastError, url=_url }
end
function RemoteRenderer.reconnect()
  if _ws then pcall(function() _ws:close() end) end
  _ws = nil; _connected = false; _status = "reconnecting"; _lastError = nil
  local ok = ensure_connected(10)
  if not ok then return false, _lastError end
  return true
end

-- Core render call
-- voxelsFlat: array of arrays [x,y,z,r,g,b,a]
-- options: rotation, width, height, scale, backgroundColor, orthographic, depthFactor, shading, lighting, outline
function RemoteRenderer.render(voxelsFlat, options)
  if not _enabled then return nil, "Remote renderer disabled" end
  if _inflight then return nil, "Remote renderer busy" end

  local ok = ensure_connected(10)
  if not ok then return nil, _lastError or "Cannot connect" end

  -- Build payload (also include objects for compatibility)
  local voxelsObjects = {}
  for i = 1, #voxelsFlat do
    local v = voxelsFlat[i]
    voxelsObjects[#voxelsObjects+1] = {
      x = v[1], y = v[2], z = v[3],
      color = { r = v[4], g = v[5], b = v[6], a = v[7] }
    }
  end
  local payload = { voxelsFlat = voxelsFlat, voxels = voxelsObjects, options = options or {} }
  local payload_str = json_encode(payload)

  -- Prepare receive state
  _inflight = true
  _pending = nil
  _pendingReady = false

  -- Send
  local sentOk, sendErr = pcall(function() _ws:sendText(payload_str) end)
  if not sentOk then
    _inflight = false
    _status = "error"
    _lastError = "sendText failed: " .. tostring(sendErr)
    return nil, _lastError
  end

  -- Optionally ping to keep alive while waiting
  pcall(function() _ws:sendPing("r") end)

  -- Wait for reply (TEXT base64 or BINARY png)
  local got = spin_wait_until(function() return _pendingReady end, 15)
  if not got then
    _inflight = false
    _lastError = "Timed out waiting for render response"
    _status = "timeout"
    return nil, _lastError
  end

  local resp = _pending
  _pending = nil
  _pendingReady = false
  _inflight = false

  local png_bytes = nil
  if not resp then
    _lastError = "Empty response"
    return nil, _lastError
  end

  if resp.kind == "text" then
    if resp.data == "error" then
      _lastError = "Server returned error"
      return nil, _lastError
    end
    png_bytes = b64_decode(resp.data or "")
  elseif resp.kind == "binary" then
    png_bytes = resp.data or ""
  else
    _lastError = "Unknown response kind"
    return nil, _lastError
  end

  if not png_bytes or #png_bytes == 0 then
    _lastError = "No image data"
    return nil, _lastError
  end

  local dir = make_temp_dir()
  local path = app.fs.joinPath(dir, "remote_render.png")
  local wok, werr = write_bytes_to_file(path, png_bytes)
  if not wok then
    _lastError = "Failed to write PNG: "..tostring(werr)
    return nil, _lastError
  end

  local img, lerr = load_png_as_image(path)
  if not img then
    _lastError = lerr or "Failed to load PNG"
    return nil, _lastError
  end

  _status = "ok"
  return img
end

local nativeBridge = nil
pcall(function() nativeBridge = require("nativeBridge") end)

-- Attempt to render using native bridge (if available).
-- model: array of voxels { x,y,z, color={r,g,b,a} }
-- params: table with width,height, rotations, scale, orthogonal, shadingMode, lighting, fxStack, backgroundColor, etc.
-- _metrics: optional table to record backend info
function RemoteRenderer.nativeRender(model, params, _metrics)
  if not nativeBridge or not nativeBridge.isAvailable or not nativeBridge.isAvailable() then
    return nil, "native not available"
  end
  if not model or #model == 0 then return nil, "empty model" end

  -- Build flat voxel list [x,y,z,r,g,b,a]
  local flat = {}
  for i,v in ipairs(model) do
    local c = v.color or {}
    flat[i] = {
      v.x or 0, v.y or 0, v.z or 0,
      math.max(0, math.min(255, c.r or c.red or 255)),
      math.max(0, math.min(255, c.g or c.green or 255)),
      math.max(0, math.min(255, c.b or c.blue or 255)),
      math.max(0, math.min(255, c.a or c.alpha or 255))
    }
  end

  local bg = params and params.backgroundColor
  local xRot = params and (params.xRotation or params.rotationX) or 0
  local yRot = params and (params.yRotation or params.rotationY) or 0
  local zRot = params and (params.zRotation or params.rotationZ) or 0
  local scale = params and (params.scale or params.zoom or 1) or 1

  local nativeParams = {
    width  = (params and params.width) or 200,
    height = (params and params.height) or 200,
    xRotation = xRot, yRotation = yRot, zRotation = zRot,
    scale = scale,
    orthogonal = params and (params.orthogonal or params.orthogonalView) or false,
    basicShadeIntensity = params and (params.basicShadeIntensity or 50) or 50,
    basicLightIntensity = params and (params.basicLightIntensity or 50) or 50,
    fovDegrees = params and (params.fovDegrees or params.fov) or nil,
    perspectiveScaleRef = params and (params.perspectiveScaleRef or "middle") or "middle",
    backgroundColor = bg and {
      r = bg.red or bg.r, g = bg.green or bg.g, b = bg.blue or bg.b, a = bg.alpha or bg.a
    } or {r=0,g=0,b=0,a=0}
  }

  -- Inject lighting for Dynamic mode
  if params and params.shadingMode == "Dynamic" and params.lighting then
    local lc = params.lighting.lightColor
    -- lc may be an Aseprite Color or a simple table; normalize
    local lr = (lc and (lc.red or lc.r)) or 255
    local lg = (lc and (lc.green or lc.g)) or 255
    local lb = (lc and (lc.blue or lc.b)) or 255
    nativeParams.lighting = {
      pitch    = params.lighting.pitch or 0,
      yaw      = params.lighting.yaw or 0,
      diffuse  = params.lighting.diffuse or 60,
      diameter = params.lighting.diameter or 100,
      ambient  = params.lighting.ambient or 30,
      rimEnabled = params.lighting.rimEnabled and true or false,
      lightColor = { r = lr, g = lg, b = lb }
    }
  end

  -- Call appropriate native renderer
  local nativeResult
  if params and params.shadingMode == "Stack" and nativeBridge.renderStack then
    nativeParams.fxStack = params.fxStack
    nativeResult = nativeBridge.renderStack(flat, nativeParams)
  elseif params and params.shadingMode == "Dynamic" and nativeBridge.renderDynamic then
    nativeResult = nativeBridge.renderDynamic(flat, nativeParams)
  else
    nativeResult = nativeBridge.renderBasic(flat, nativeParams)
  end

  if nativeResult and nativeResult.pixels then
    local w = nativeResult.width
    local h = nativeResult.height
    local bytes = nativeResult.pixels
    local expected = w * h * 4
    if #bytes == expected then
      local img = Image(w, h, ColorMode.RGB)
      local idx = 1
      for y=0,h-1 do
        for x=0,w-1 do
          local r = string.byte(bytes, idx    )
          local g = string.byte(bytes, idx + 1)
          local b = string.byte(bytes, idx + 2)
          local a = string.byte(bytes, idx + 3)
          idx = idx + 4
          img:putPixel(x, y, app.pixelColor.rgba(r,g,b,a))
        end
      end
      if _metrics then
        if params and params.shadingMode == "Stack" then
          _metrics.backend = "native-stack"
        elseif params and params.shadingMode == "Dynamic" then
          _metrics.backend = "native-dynamic"
        else
          _metrics.backend = "native-basic"
        end
      end
      return img
    else
      print("[asevoxel-native] native buffer mismatch (fallback)")
    end
  end

  return nil, "native failed"
end

return RemoteRenderer