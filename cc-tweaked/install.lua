-- MineOS CC installer | CC:Tweaked | Minecraft 1.20.1
-- Downloads a pinned upstream MineOS revision and installs the CC adapter.

local UPSTREAM = "f47c7fcf29e65f0ac27363dde3f79dae7c24395b"
local UPSTREAM_API = "https://api.github.com/repos/IgorTimofeev/MineOS/git/commits/" .. UPSTREAM
local UPSTREAM_RAW = "https://raw.githubusercontent.com/IgorTimofeev/MineOS/" .. UPSTREAM .. "/"
local PORT_RAW = "https://raw.githubusercontent.com/Frez7373/MineOS/main/"

local function say(s) print(tostring(s or "")) end
local function safeWrite(s) if term and term.write then term.write(tostring(s or "")) else write(tostring(s or "")) end end
local function get(url, binary)
  if not http or not http.get then return nil, "HTTP API отключён" end
  local ok, h, reason = pcall(http.get, url, { ["User-Agent"] = "MineOS-CC-Installer" }, binary == true)
  if not ok then return nil, tostring(h) end
  if not h then return nil, tostring(reason or "HTTP error") end
  local code = 200
  if h.getResponseCode then
    local good, value = pcall(h.getResponseCode)
    if good and type(value) == "number" then code = value end
  end
  local good, data = pcall(h.readAll)
  pcall(h.close)
  if not good then return nil, tostring(data) end
  if code < 200 or code >= 300 then return nil, "HTTP " .. code .. ": " .. tostring(data):sub(1, 160) end
  return data
end

local function encodePath(path)
  return (path:gsub("([^%w%-%._~/])", function(c) return string.format("%%%02X", c:byte()) end))
end

local function writeFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h, err = fs.open(path, "wb")
  if not h then return false, err end
  local ok, reason = pcall(h.write, data)
  pcall(h.close)
  if not ok then return false, reason end
  return true
end

local function readFile(path)
  local h, err = fs.open(path, "r")
  if not h then return nil, err end
  local data = h.readAll()
  h.close()
  return data
end

local function patchOnce(source, old, new, label)
  local a, b = source:find(old, 1, true)
  if not a then return nil, "Не найден патч: " .. label end
  if source:find(old, b + 1, true) then return nil, "Повторяющийся патч: " .. label end
  return source:sub(1, a - 1) .. new .. source:sub(b + 1)
end

local function applyPatches()
  local source, err = readFile("/OS.lua")
  if not source then return false, "OS.lua: " .. tostring(err) end
  local old = '\tfunction(signalType, componentAddress, componentType)\n\t\tif (signalType == "component_added" or signalType == "component_removed") and componentType == "screen" then'
  local new = '\tfunction(signalType, componentAddress, componentType)\n'
    .. '\t\tif signalType == "system" and componentAddress == "terminalResize" then\n'
    .. '\t\t\tlocal width, height = component.invoke(GPUAddress, "getResolution")\n'
    .. '\t\t\tscreen.setResolution(width, height)\n'
    .. '\t\t\tworkspace.width, workspace.height = width, height\n'
    .. '\t\t\tif system.getUser() then\n'
    .. '\t\t\t\tsystem.updateWorkspace()\n'
    .. '\t\t\t\tsystem.updateDesktop()\n'
    .. '\t\t\tend\n'
    .. '\t\t\tworkspace:draw()\n'
    .. '\t\tend\n\n'
    .. '\t\tif (signalType == "component_added" or signalType == "component_removed") and componentType == "screen" then'
  local patched, why = patchOnce(source, old, new, "изменение размера терминала")
  if not patched then return false, why end
  local ok, whyWrite = writeFile("/OS.lua", patched)
  if not ok then return false, tostring(whyWrite) end

  local sys, sysErr = readFile("/Libraries/System.lua")
  if not sys then return false, "Libraries/System.lua: " .. tostring(sysErr) end
  local newSys, langErr = patchOnce(sys, 'localizationLanguage = "English",', 'localizationLanguage = "Russian",', "русский язык по умолчанию")
  if not newSys then return false, langErr end
  local saved, saveErr = writeFile("/Libraries/System.lua", newSys)
  if not saved then return false, tostring(saveErr) end
  return true
end

local function run()
  if term then
    pcall(term.setBackgroundColor, colors.black)
    pcall(term.setTextColor, colors.white)
    pcall(term.clear)
    pcall(term.setCursorPos, 1, 1)
  end
  say("========================================")
  say("          MINEOS CC INSTALLER")
  say("       CC:Tweaked / Minecraft 1.20.1")
  say("========================================")
  say("Установщик скачает оригинальную MineOS,")
  say("добавит адаптер CC:Tweaked и русский язык.")
  say("Нужен HTTP API и доступ к GitHub.")
  say("Рекомендуется новый компьютер.")
  say("")
  say("Продолжить установку? Введи Y:")
  local answer = (read() or ""):lower()
  if answer ~= "y" and answer ~= "yes" and answer ~= "д" and answer ~= "да" then say("Отменено."); return end

  say("Получаю список файлов MineOS...")
  local commitBody, err = get(UPSTREAM_API, false)
  if not commitBody then error(err, 0) end
  local commit = textutils.unserializeJSON(commitBody)
  if not commit or not commit.tree or not commit.tree.sha then error("GitHub не вернул SHA дерева.", 0) end
  local treeURL = "https://api.github.com/repos/IgorTimofeev/MineOS/git/trees/" .. commit.tree.sha .. "?recursive=1"
  local treeBody, treeErr = get(treeURL, false)
  if not treeBody then error(treeErr, 0) end
  local tree = textutils.unserializeJSON(treeBody)
  if not tree or type(tree.tree) ~= "table" or tree.truncated then error("Не удалось получить полный список файлов.", 0) end

  local files, bytes = {}, 0
  for _, entry in ipairs(tree.tree) do
    if entry.type == "blob" and type(entry.path) == "string" then
      files[#files + 1] = entry
      bytes = bytes + (tonumber(entry.size) or 0)
    end
  end
  table.sort(files, function(a, b) return a.path < b.path end)
  say("Файлов: " .. #files .. ", размер: " .. math.ceil(bytes / 1024) .. " KiB")

  local startup, startupErr = get(PORT_RAW .. "cc-tweaked/startup.lua", true)
  if not startup then error("Не удалось скачать CC-адаптер: " .. tostring(startupErr), 0) end
  local docs, docsErr = get(PORT_RAW .. "README.md", true)
  if not docs then error("Не удалось скачать README: " .. tostring(docsErr), 0) end

  local backup = "/MineOS-CC-backup-" .. tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000))
  local backupBytes = 0
  for _, entry in ipairs(files) do
    local p = "/" .. entry.path
    if fs.exists(p) and not fs.isDir(p) then backupBytes = backupBytes + (fs.getSize(p) or 0) end
  end
  for _, p in ipairs({"/startup.lua", "/MineOS-CC-README.txt"}) do
    if fs.exists(p) and not fs.isDir(p) then backupBytes = backupBytes + (fs.getSize(p) or 0) end
  end
  local free = fs.getFreeSpace and fs.getFreeSpace("/") or nil
  local required = bytes + #startup + #docs + backupBytes + 65536
  if type(free) == "number" and free < required then
    error("Мало места: нужно около " .. math.ceil(required / 1024) .. " KiB, свободно " .. math.floor(free / 1024) .. " KiB.", 0)
  end

  say("Устанавливаю файлы. Резервная копия: " .. backup)
  for i, entry in ipairs(files) do
    local path = "/" .. entry.path
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    if fs.exists(path) and not fs.isDir(path) then
      local backupPath = backup .. path
      local backupDir = fs.getDir(backupPath)
      if backupDir ~= "" and not fs.exists(backupDir) then fs.makeDir(backupDir) end
      if not fs.exists(backupPath) then
        local copied, copyErr = pcall(fs.copy, path, backupPath)
        if not copied then error("Не удалось сделать копию " .. path .. ": " .. tostring(copyErr), 0) end
      end
    end
    local data, downloadErr = get(UPSTREAM_RAW .. encodePath(entry.path), true)
    if not data then error("Загрузка " .. entry.path .. ": " .. tostring(downloadErr), 0) end
    local saved, writeErr = writeFile(path, data)
    if not saved then error("Запись " .. path .. ": " .. tostring(writeErr), 0) end
    if i == 1 or i % 10 == 0 or i == #files then
      safeWrite("\r[" .. i .. "/" .. #files .. "] " .. entry.path .. string.rep(" ", 8))
    end
  end
  say("")

  for _, path in ipairs({"/startup.lua", "/MineOS-CC-README.txt"}) do
    if fs.exists(path) and not fs.isDir(path) then
      local target = backup .. path
      local dir = fs.getDir(target)
      if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
      if not fs.exists(target) then pcall(fs.copy, path, target) end
    end
  end
  local ok, why = writeFile("/startup.lua", startup)
  if not ok then error("Запись startup.lua: " .. tostring(why), 0) end
  local docsOK, docsWhy = writeFile("/MineOS-CC-README.txt", docs)
  if not docsOK then error("Запись README: " .. tostring(docsWhy), 0) end

  say("Применяю патчи CC:Tweaked...")
  local patched, patchErr = applyPatches()
  if not patched then error(patchErr, 0) end
  say("")
  say("MineOS CC успешно установлена!")
  say("Резервная копия: " .. backup)
  say("Перезагрузить компьютер? Введи Y:")
  local reboot = (read() or ""):lower()
  if reboot == "y" or reboot == "yes" or reboot == "д" or reboot == "да" then os.reboot() end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  say("")
  say("ОШИБКА УСТАНОВКИ:")
  say(err)
  say("Нажми Enter для выхода.")
  read()
end
