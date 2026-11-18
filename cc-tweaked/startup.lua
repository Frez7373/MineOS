-- MineOS for CC:Tweaked (Minecraft 1.20.1)
-- Compatibility layer for the original OpenComputers-based MineOS.
-- Copyright (c) MineOS authors. CC:Tweaked port adapter.

local ROOT = "/"

-- Prefer a connected colour monitor, otherwise use the computer terminal.
if peripheral and term and peripheral.find then
  local monitor = peripheral.find("monitor")
  if monitor then
    if monitor.setTextScale then pcall(monitor.setTextScale, 0.5) end
    pcall(term.redirect, monitor)
  end
end

if term and term.setCursorBlink then pcall(term.setCursorBlink, false) end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil, a
end

-- OpenComputers' checkArg helper.
if not _G.checkArg then
  function checkArg(n, value, ...)
    local expected = {...}
    for i = 1, #expected do
      if type(value) == expected[i] then return end
    end
    error(("bad argument #%d (%s expected, got %s)"):format(n, table.concat(expected, " or "), type(value)), 3)
  end
end

-- Unicode helpers. CC:Tweaked uses UTF-8 text, while MineOS expects an
-- OpenComputers-style unicode API.
local function utf8CodepointAt(s, position)
  local b1 = s:byte(position)
  if not b1 then return nil end
  if b1 < 0x80 then return b1, position + 1 end
  local b2, b3, b4 = s:byte(position + 1, position + 3)
  if b1 < 0xE0 and b2 then
    return (b1 - 0xC0) * 0x40 + (b2 - 0x80), position + 2
  elseif b1 < 0xF0 and b2 and b3 then
    return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), position + 3
  elseif b2 and b3 and b4 then
    return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), position + 4
  end
  return b1, position + 1
end

local function utf8Length(s)
  local n, i = 0, 1
  while i <= #s do
    local _, nextI = utf8CodepointAt(s, i)
    i = nextI or (i + 1)
    n = n + 1
  end
  return n
end

local function utf8Offset(s, wanted)
  local length = utf8Length(s)
  if wanted < 0 then wanted = length + wanted + 1 end
  if wanted <= 1 then return 1 end
  if wanted > length + 1 then return #s + 1 end
  local n, i = 1, 1
  while i <= #s do
    if n == wanted then return i end
    local _, nextI = utf8CodepointAt(s, i)
    i, n = nextI or (i + 1), n + 1
  end
  return #s + 1
end

local function utf8Sub(s, first, last)
  local length = utf8Length(s)
  first = first or 1
  last = last or -1
  if first < 0 then first = length + first + 1 end
  if last < 0 then last = length + last + 1 end
  if first < 1 then first = 1 end
  if last > length then last = length end
  if first > last or first > length then return "" end
  local byteFirst = utf8Offset(s, first)
  local byteLast = utf8Offset(s, last + 1) - 1
  return s:sub(byteFirst, byteLast)
end

local function utf8Encode(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
  end
  if code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
  end
  return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + (math.floor(code / 0x1000) % 0x40), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
end

local upperCyrillic = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
local lowerCyrillic = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local upperMap, lowerMap = {}, {}
for i = 1, utf8Length(upperCyrillic) do
  upperMap[utf8Sub(upperCyrillic, i, i)] = utf8Sub(lowerCyrillic, i, i)
  lowerMap[utf8Sub(lowerCyrillic, i, i)] = utf8Sub(upperCyrillic, i, i)
end

_G.unicode = {
  len = utf8Length,
  sub = utf8Sub,
  wlen = utf8Length,
  char = utf8Encode,
  lower = function(s) return (s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c) return upperMap[c] or c:lower() end)) end,
  upper = function(s) return (s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c) return lowerMap[c] or c:upper() end)) end,
}

-- CC:Tweaked event/key compatibility.
local keyCodes = {}
local keyNames = {
  enter = 28, numPadEnter = 28, backspace = 14, tab = 15, space = 57,
  left = 203, right = 205, up = 200, down = 208,
  home = 199, ["end"] = 207, delete = 211, insert = 210,
  leftShift = 42, rightShift = 54, leftCtrl = 29, rightCtrl = 157,
  leftAlt = 56, rightAlt = 184, escape = 1,
  minus = 12, equals = 13, leftBracket = 26, rightBracket = 27,
  semicolon = 39, apostrophe = 40, comma = 51, period = 52, slash = 53,
}
local letterCodes = {a=30,b=48,c=46,d=32,e=18,f=33,g=34,h=35,i=23,j=36,k=37,l=38,m=50,n=49,o=24,p=25,q=16,r=19,s=31,t=20,u=22,v=47,w=17,x=45,y=21,z=44}
local digitCodes = { ["1"]=2,["2"]=3,["3"]=4,["4"]=5,["5"]=6,["6"]=7,["7"]=8,["8"]=9,["9"]=10,["0"]=11 }
if _G.keys then
  for name, code in pairs(keyNames) do
    if keys[name] then keyCodes[keys[name]] = code end
  end
  for name, code in pairs(letterCodes) do
    if keys[name] then keyCodes[keys[name]] = code end
  end
  for name, code in pairs(digitCodes) do
    if keys[name] then keyCodes[keys[name]] = code end
  end
end

local keyboardAddress, screenAddress = "cc_keyboard", "cc_screen"
local bootEpoch = os.epoch and os.epoch("utc") or 0
local internalTimers = {}
local function translateEvent(raw)
  local name = raw[1]
  if name == "key" then
    return "key_down", keyboardAddress, 0, keyCodes[raw[2]] or raw[2], nil
  elseif name == "key_up" then
    return "key_up", keyboardAddress, 0, keyCodes[raw[2]] or raw[2], nil
  elseif name == "char" then
    local cp = utf8CodepointAt(raw[2] or "", 1) or 0
    return "key_down", keyboardAddress, cp, 0, nil
  elseif name == "mouse_click" then
    return "touch", screenAddress, raw[3], raw[4], raw[2], nil
  elseif name == "mouse_drag" then
    return "drag", screenAddress, raw[3], raw[4], raw[2], nil
  elseif name == "mouse_up" then
    return "drop", screenAddress, raw[3], raw[4], raw[2], nil
  elseif name == "mouse_scroll" then
    return "scroll", screenAddress, raw[3], raw[4], raw[2], nil
  elseif name == "monitor_touch" then
    return "touch", screenAddress, raw[2], raw[3], 1, nil
  elseif name == "paste" then
    return "clipboard", keyboardAddress, raw[2]
  elseif name == "rednet_message" and raw[4] == "mineos" then
    local payload = type(raw[3]) == "table" and raw[3] or { raw[3] }
    return "modem_message", "ccmodem", tostring(raw[2]), 1488, 0, table.unpack(payload)
  elseif name == "term_resize" then
    return "system", "terminalResize"
  end
  return table.unpack(raw)
end

_G.computer = {}
function computer.uptime()
  if os.epoch then return math.max(0, (os.epoch("utc") - bootEpoch) / 1000) end
  return os.clock()
end
function computer.pushSignal(name, ...)
  if type(name) == "string" then os.queueEvent(name, ...) end
end
function computer.pullSignal(timeout)
  if timeout and timeout <= 0 then return nil end
  local timerId
  if type(timeout) == "number" and timeout < math.huge then
    timerId = os.startTimer(math.max(timeout, 0.01))
    internalTimers[timerId] = true
  end
  while true do
    local e = {os.pullEventRaw()}
    if e[1] == "timer" and internalTimers[e[2]] then
      internalTimers[e[2]] = nil
      if timerId == e[2] then return nil end
    else
      return translateEvent(e)
    end
  end
end
function computer.shutdown(reboot)
  if reboot then os.reboot() else os.shutdown() end
end
function computer.getArchitecture() return "Lua 5.2" end
function computer.totalMemory() return 8 * 1024 * 1024 end
function computer.freeMemory()
  local used = 0
  if collectgarbage then
    local ok, value = pcall(collectgarbage, "count")
    if ok and type(value) == "number" then used = value * 1024 end
  end
  return math.max(0, computer.totalMemory() - used)
end
function computer.energy() return 100 end
function computer.maxEnergy() return 100 end
function computer.beep(frequency, duration)
  if peripheral and peripheral.find then
    local speaker = peripheral.find("speaker")
    if speaker and speaker.playNote then pcall(speaker.playNote, "pling", 1, 12) end
  end
end
function computer.tmpAddress() return "ccfs" end
function computer.getBootAddress() return "ccfs" end
function computer.setBootAddress() return true end
function computer.getDeviceInfo() return {} end

-- Map CC's 16-colour palette to/from the 24-bit colours used by MineOS.
local colourEntries = {
  {0x111111, "black"}, {0xF2B233, "orange"}, {0xE57FD8, "magenta"}, {0x99B2F2, "lightBlue"},
  {0xDEDE6C, "yellow"}, {0x7FCC19, "lime"}, {0xF2B2CC, "pink"}, {0x4C4C4C, "gray"},
  {0x999999, "lightGray"}, {0x4C99B2, "cyan"}, {0xB266E5, "purple"}, {0x3366CC, "blue"},
  {0x7F664C, "brown"}, {0x57A64E, "green"}, {0xCC4C4C, "red"}, {0xF0F0F0, "white"},
}
local colourMask = {}
for i = 1, #colourEntries do
  local entry = colourEntries[i]
  entry[3] = (_G.colors and colors[entry[2]]) or 1
  colourMask[entry[2]] = entry[3]
end
local function toColourMask(rgb)
  rgb = tonumber(rgb) or 0
  local r = math.floor(rgb / 65536) % 256
  local g = math.floor(rgb / 256) % 256
  local b = rgb % 256
  local best, bestDistance = colourEntries[1][3], math.huge
  for i = 1, #colourEntries do
    local entry = colourEntries[i]
    local rr = math.floor(entry[1] / 65536) % 256
    local gg = math.floor(entry[1] / 256) % 256
    local bb = entry[1] % 256
    local distance = (r - rr)^2 + (g - gg)^2 + (b - bb)^2
    if distance < bestDistance then best, bestDistance = entry[3], distance end
  end
  return best
end

-- Native CC filesystem adapter. File handles are buffered in memory to provide
-- the seek/read/write interface expected by the original MineOS filesystem.
local fsHandles = {}
local function cleanPath(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("^/+", "")
  path = path:gsub("/+", "/")
  if path == "" then return "/" end
  return "/" .. path
end

local filesystemProxy = { address = "ccfs", type = "filesystem", slot = 0 }
function filesystemProxy.getLabel() return (os.getComputerLabel and os.getComputerLabel()) or ("CC Computer " .. tostring(os.getComputerID and os.getComputerID() or 0)) end
function filesystemProxy.setLabel(label)
  if os.setComputerLabel then os.setComputerLabel(tostring(label)); return true end
  return false, "Computer labels are not supported"
end
function filesystemProxy.isReadOnly(path)
  if fs.isReadOnly then return fs.isReadOnly(cleanPath(path or "/")) end
  return false
end
function filesystemProxy.exists(path) return fs.exists(cleanPath(path)) end
function filesystemProxy.size(path)
  local p = cleanPath(path)
  if fs.isDir(p) then return 0 end
  return fs.getSize(p)
end
function filesystemProxy.isDirectory(path) return fs.isDir(cleanPath(path)) end
function filesystemProxy.makeDirectory(path)
  fs.makeDir(cleanPath(path)); return true
end
function filesystemProxy.lastModified(path)
  local attrs = fs.attributes and fs.attributes(cleanPath(path))
  local modified = attrs and attrs.modified
  -- CC:Tweaked fs.attributes timestamps are already milliseconds since epoch.
  return modified or os.epoch("utc")
end
function filesystemProxy.remove(path) fs.delete(cleanPath(path)); return true end
function filesystemProxy.rename(fromPath, toPath) fs.move(cleanPath(fromPath), cleanPath(toPath)); return true end
function filesystemProxy.list(path)
  local p = cleanPath(path)
  local entries = fs.list(p)
  for i = 1, #entries do
    local child = fs.combine(p, entries[i])
    if fs.isDir(child) then entries[i] = entries[i] .. "/" end
  end
  return entries
end
function filesystemProxy.spaceUsed()
  local capacity = fs.getCapacity and fs.getCapacity("/")
  local free = fs.getFreeSpace and fs.getFreeSpace("/")
  if type(capacity) ~= "number" then capacity = 1073741824 end
  if type(free) ~= "number" then free = capacity end
  return math.max(0, capacity - free)
end
function filesystemProxy.spaceTotal()
  local capacity = fs.getCapacity and fs.getCapacity("/")
  return type(capacity) == "number" and capacity or 1073741824
end
function filesystemProxy.open(path, mode)
  local p = cleanPath(path)
  mode = mode or "r"
  local data = ""
  if mode == "r" or mode == "rb" or mode == "a" or mode == "ab" then
    if not fs.exists(p) or fs.isDir(p) then return nil, "No such file" end
    local native = fs.open(p, "r")
    if not native then return nil, "Could not open file" end
    data = native.readAll() or ""
    native.close()
  elseif mode ~= "w" and mode ~= "wb" then
    return nil, "Unsupported mode: " .. tostring(mode)
  end
  local stream = { path = p, mode = mode, data = data, position = (mode == "a" or mode == "ab") and (#data) or 0, closed = false }
  fsHandles[stream] = true
  return stream
end
function filesystemProxy.read(stream, count)
  if not fsHandles[stream] or stream.closed then return nil, "Bad file handle" end
  count = tonumber(count) or 1
  if count == math.huge then count = #stream.data - stream.position end
  count = math.max(0, math.floor(count))
  if count == 0 then return "" end
  if stream.position >= #stream.data then return nil end
  local chunk = stream.data:sub(stream.position + 1, stream.position + count)
  stream.position = stream.position + #chunk
  if chunk == "" then return nil end
  return chunk
end
function filesystemProxy.write(stream, data)
  if not fsHandles[stream] or stream.closed then return false, "Bad file handle" end
  if stream.mode == "r" or stream.mode == "rb" then return false, "File is not open for writing" end
  data = tostring(data or "")
  local before = stream.data:sub(1, stream.position)
  local afterStart = stream.position + #data + 1
  local after = stream.data:sub(afterStart)
  stream.data = before .. data .. after
  stream.position = stream.position + #data
  return true
end
function filesystemProxy.seek(stream, whence, offset)
  if not fsHandles[stream] or stream.closed then return nil, "Bad file handle" end
  offset = tonumber(offset) or 0
  local base = 0
  if whence == "cur" then base = stream.position elseif whence == "end" then base = #stream.data end
  local position = math.max(0, math.min(#stream.data, base + offset))
  stream.position = position
  return position
end
function filesystemProxy.close(stream)
  if not fsHandles[stream] or stream.closed then return true end
  if stream.mode ~= "r" and stream.mode ~= "rb" then
    local native, reason = fs.open(stream.path, "w")
    if not native then return false, reason or "Could not save file" end
    native.write(stream.data)
    native.close()
  end
  stream.closed = true
  fsHandles[stream] = nil
  return true
end

-- Simple HTTP-backed OpenComputers internet component.
local internetProxy = { address = "ccinternet", type = "internet" }
function internetProxy.request(url, postData, headers, method)
  if not http then return nil, "HTTP API is disabled" end
  local response, reason
  local verb = (method or (postData and "POST" or "GET")):upper()
  if verb == "POST" or postData ~= nil then
    response, reason = http.post(url, postData or "", headers or {}, true)
  else
    response, reason = http.get(url, headers or {}, true)
  end
  if not response then return nil, reason or "HTTP request failed" end
  local body = response.readAll() or ""
  response.close()
  local handle = { data = body, position = 1, closed = false }
  function handle.read(count)
    if handle.closed then return nil end
    count = tonumber(count) or #handle.data
    if count == math.huge then count = #handle.data end
    if handle.position > #handle.data then return nil end
    local part = handle.data:sub(handle.position, handle.position + math.max(0, count) - 1)
    handle.position = handle.position + #part
    return part ~= "" and part or nil
  end
  function handle.close() handle.closed = true; return true end
  return handle
end

-- A terminal-backed GPU with a 16-colour palette.
local currentForeground, currentBackground = 0xFFFFFF, 0x000000
local buffer, bufferWidth, bufferHeight = {}, 0, 0
local function getTerminalSize() return term.getSize() end
local function resetBuffer()
  bufferWidth, bufferHeight = getTerminalSize()
  buffer = {}
  for y = 1, bufferHeight do
    buffer[y] = {}
    for x = 1, bufferWidth do
      buffer[y][x] = { currentBackground, currentForeground, " " }
    end
  end
end
local function ensureBuffer()
  local w, h = getTerminalSize()
  if w ~= bufferWidth or h ~= bufferHeight then resetBuffer() end
end
resetBuffer()

local gpuProxy = { address = "ccgpu", type = "gpu", slot = 0 }
function gpuProxy.bind(address)
  ensureBuffer()
  return true
end
function gpuProxy.getScreen() return screenAddress end
function gpuProxy.getResolution() ensureBuffer(); return bufferWidth, bufferHeight end
function gpuProxy.maxResolution() return gpuProxy.getResolution() end
function gpuProxy.setResolution() ensureBuffer(); return true end
function gpuProxy.getDepth() return 4 end
function gpuProxy.maxDepth() return 4 end
function gpuProxy.setDepth() return true end
function gpuProxy.setForeground(rgb)
  local previous = currentForeground
  currentForeground = tonumber(rgb) or currentForeground
  return previous
end
function gpuProxy.setBackground(rgb)
  local previous = currentBackground
  currentBackground = tonumber(rgb) or currentBackground
  return previous
end
function gpuProxy.set(x, y, value)
  ensureBuffer()
  x, y, value = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1), tostring(value or "")
  if y < 1 or y > bufferHeight or x > bufferWidth then return false end
  if x < 1 then value = unicode.sub(value, 2 - x, -1); x = 1 end
  local available = bufferWidth - x + 1
  -- Avoid terminal auto-scroll when a write reaches the bottom-right cell.
  if y == bufferHeight and x + available - 1 == bufferWidth then available = math.max(0, available - 1) end
  if unicode.len(value) > available then value = unicode.sub(value, 1, available) end
  if value == "" then return true end
  local oldFg, oldBg = term.getTextColor(), term.getBackgroundColor()
  term.setTextColor(toColourMask(currentForeground))
  term.setBackgroundColor(toColourMask(currentBackground))
  term.setCursorPos(x, y)
  term.write(value)
  local col = x
  for i = 1, unicode.len(value) do
    if col <= bufferWidth then
      buffer[y][col] = { currentBackground, currentForeground, unicode.sub(value, i, i) }
      col = col + 1
    end
  end
  term.setTextColor(oldFg)
  term.setBackgroundColor(oldBg)
  return true
end
function gpuProxy.fill(x, y, width, height, char)
  ensureBuffer()
  x, y = math.floor(x or 1), math.floor(y or 1)
  width, height = math.floor(width or 0), math.floor(height or 0)
  char = tostring(char or " ")
  if x < 1 then width, x = width - 1 + x, 1 end
  if y < 1 then height, y = height - 1 + y, 1 end
  width = math.min(width, bufferWidth - x + 1)
  height = math.min(height, bufferHeight - y + 1)
  if width <= 0 or height <= 0 then return true end
  local line = string.rep(char, width)
  for row = y, y + height - 1 do gpuProxy.set(x, row, line) end
  return true
end
function gpuProxy.get(x, y)
  ensureBuffer()
  x, y = math.floor(x or 1), math.floor(y or 1)
  if x < 1 or y < 1 or x > bufferWidth or y > bufferHeight then return 0, 0, " " end
  local cell = buffer[y][x]
  return cell[1], cell[2], cell[3]
end

local screenProxy = { address = screenAddress, type = "screen", slot = 0 }
function screenProxy.getAspectRatio() return 2, 1 end

local eepromProxy = { address = "cceeprom", type = "eeprom", slot = 0 }
function eepromProxy.getData() return "ccfs" end
function eepromProxy.setData() return true end

-- Optional peripheral inventory for MineOS components.
local function findModem()
  if peripheral and peripheral.find then return peripheral.find("modem") end
  return nil
end
local nativeModem, modemSide = findModem()
local modemProxy = nil
if nativeModem and rednet then
  modemProxy = { address = "ccmodem", type = "modem", slot = 0 }
  function modemProxy.open()
    if modemSide then pcall(rednet.open, modemSide); return true end
    return false, "No modem side"
  end
  function modemProxy.close()
    if modemSide then pcall(rednet.close, modemSide); return true end
    return false
  end
  function modemProxy.send(address, channel, ...)
    local target = tonumber(address) or address
    return rednet.send(target, {...}, "mineos")
  end
  function modemProxy.broadcast(channel, ...)
    return rednet.broadcast({...}, "mineos")
  end
  function modemProxy.isWireless()
    if nativeModem.isWireless then return nativeModem.isWireless() end
    return false
  end
  function modemProxy.setStrength()
    return false, "Signal strength is controlled by CC:Tweaked"
  end
  function modemProxy.maxPacketSize() return 8192 end
end

_G.component = {}
local available = {
  gpu = "ccgpu", screen = "cc_screen", filesystem = "ccfs", eeprom = "cceeprom",
}
if http then available.internet = "ccinternet" end
if modemProxy then available.modem = "ccmodem" end
function component.list(filter)
  local result = {}
  for kind, address in pairs(available) do
    if not filter or filter == kind then result[#result + 1] = { address, kind } end
  end
  table.sort(result, function(a, b) return a[2] < b[2] end)
  local i = 0
  return function()
    i = i + 1
    if result[i] then return result[i][1], result[i][2] end
  end
end
function component.proxy(address)
  if type(address) == "table" then return address end
  if address == "ccgpu" then return gpuProxy end
  if address == "cc_screen" then return screenProxy end
  if address == "ccfs" then return filesystemProxy end
  if address == "cceeprom" then return eepromProxy end
  if address == "ccinternet" then return internetProxy end
  if address == "ccmodem" and modemProxy then return modemProxy end
  return nil, "No such component: " .. tostring(address)
end
function component.invoke(address, method, ...)
  local proxy, reason = component.proxy(address)
  if not proxy then return nil, reason end
  local fn = proxy[method]
  if type(fn) ~= "function" then return nil, "No such method: " .. tostring(method) end
  return fn(...)
end
function component.get(kind)
  local address = component.list(kind)()
  if address then return component.proxy(address) end
  return nil, "component with type \"" .. tostring(kind) .. "\" is not available"
end
function component.isAvailable(kind) return component.list(kind)() ~= nil end
setmetatable(component, { __index = function(_, key)
  local proxy, reason = component.get(key)
  if proxy then return proxy end
  error(reason, 2)
end })

-- Start the original MineOS kernel.
local file, reason = fs.open("/OS.lua", "r")
if not file then
  term.clear()
  term.setCursorPos(1, 1)
  print("MineOS CC: не найден /OS.lua")
  print(tostring(reason))
  print("Распакуйте содержимое архива в корень компьютера.")
  return
end
local source = file.readAll()
file.close()
local chunk, loadError = load(source, "@/OS.lua", "t", _G)
if not chunk then error(loadError, 0) end
local ok, result = xpcall(chunk, debug.traceback)
if not ok then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("MineOS CC — ошибка запуска")
  term.setTextColor(colors.white)
  print(result)
  print("Нажмите любую клавишу для перезагрузки.")
  os.pullEventRaw("key")
  os.reboot()
end
