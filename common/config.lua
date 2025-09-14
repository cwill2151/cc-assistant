local CONFIG_PATH = "/config/config.json"

local function getConfigPath()
    return CONFIG_PATH
end

local function loadConfig()
    local path = getConfigPath()
    if not fs.exists(path) then
        error("Config file not found at " .. path)
    end
    local file = fs.open(path, "r")
    if not file then
        error("Error opening " .. path)
    end
    local content = file.readAll()
    file.close()
    local config, err = textutils.unserializeJSON(content)
    if not config then
        error("Error parsing config.json: " .. tostring(err))
    end
    return config
end

local function saveConfig(config)
    local path = getConfigPath()
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(path, "w")
    if not file then
        return false, "Error opening " .. path .. " for writing"
    end
    file.write(textutils.serializeJSON(config))
    file.close()
    return true
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

return {
    getConfigPath = getConfigPath,
    loadConfig = loadConfig,
    saveConfig = saveConfig,
    trim = trim
}