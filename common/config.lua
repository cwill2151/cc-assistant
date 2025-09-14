local function loadConfig(configFile)
    local file = fs.open(configFile, "r")
    if file then
        local content = file.readAll()
        file.close()
        local config, err = textutils.unserializeJSON(content)
        if config then
            return config
        else
            error("Error parsing config.json: " .. tostring(err))
        end
    else
        error("Error opening config.json")
    end
end

local function saveConfig(config, configFile)
    local file = fs.open(configFile, "w")
    if file then
        local jsonContent = textutils.serializeJSON(config)
        file.write(jsonContent)
        file.close()
        return true
    else
        return false, "Error opening config.json for writing"
    end
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function getScriptRelative(path)
    return fs.combine(fs.getDir(shell.getRunningProgram()), path)
end

return {
    loadConfig = loadConfig,
    saveConfig = saveConfig,
    trim = trim,
    getScriptRelative = getScriptRelative
}