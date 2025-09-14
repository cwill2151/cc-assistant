---@diagnostic disable: undefined-global, undefined-field, lowercase-global

local args = {...}
local version = "1.0.0"
local repo = "cwill2151/cc-assistant"
local branch = "master"

local metadataUrl = nil
local metadata = nil

local function printUsage()
    print("ComputerCraft Multi-System Installer (ccmsi) v" .. version)
    print("")
    print("Usage:")
    print("  ccmsi <system>      - Install/update a system")
    print("  ccmsi list          - List available systems")
    print("  ccmsi update        - Update ccmsi itself")
    print("  ccmsi clean         - Remove all installed files")
    print("  ccmsi help          - Show this help")
    print("")
    print("Set metadata URL with:")
    print("  ccmsi seturl <url> - Set custom metadata URL")
end

local function printHeader(text)
    term.setTextColor(colors.lime)
    print("+---------------------------------------+")
    print("|" .. string.format("%39s", text) .. "|")
    print("+---------------------------------------+")
    term.setTextColor(colors.white)
end

local function log(message, color)
    term.setTextColor(color or colors.white)
    print("[ccmsi] " .. message)
    term.setTextColor(colors.white)
end

local function loadSettings()
    if fs.exists(".ccmsi_config") then
        local file = fs.open(".ccmsi_config", "r")
        local config = textutils.unserialize(file.readAll())
        file.close()
        return config
    end
    return {
        metadataUrl = string.format("https://raw.githubusercontent.com/%s/%s/systems.json", repo, branch)
    }
end

local function saveSettings(config)
    local file = fs.open(".ccmsi_config", "w")
    file.write(textutils.serialize(config))
    file.close()
end

local function fetchMetadata()
    local config = loadSettings()
    metadataUrl = config.metadataUrl
    
    log("Fetching metadata from: " .. metadataUrl, colors.gray)
    
    local response = http.get(metadataUrl)
    if not response then
        log("Failed to fetch metadata", colors.red)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    metadata = textutils.unserializeJSON(content)
    if not metadata then
        log("Failed to parse metadata", colors.red)
        return false
    end
    
    return true
end

local function fetchDirectoryListing(path)
    local apiUrl = string.format("https://api.github.com/repos/%s/contents/%s?ref=%s", repo, path, branch)
    log("Fetching directory listing for " .. path .. "...", colors.gray)
    
    local response = http.get(apiUrl)
    if not response then
        log("Failed to fetch directory listing for " .. path, colors.red)
        return nil
    end
    
    local content = response.readAll()
    response.close()
    
    local listing = textutils.unserializeJSON(content)
    if not listing then
        log("Failed to parse directory listing", colors.red)
        return nil
    end
    
    return listing
end

local function downloadFile(path, destination)
    local url = string.format("https://raw.githubusercontent.com/%s/%s/%s", repo, branch, path)
    log("Downloading " .. path .. "...", colors.gray)
    
    local response = http.get(url)
    if not response then
        log("Failed to download " .. path, colors.red)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local dir = fs.getDir(destination)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(destination, "w")
    if not file then
        log("Failed to write " .. destination, colors.red)
        return false
    end
    
    file.write(content)
    file.close()
    
    log("Downloaded " .. destination, colors.green)
    return true
end

local function downloadDirectory(sourcePath, destPath)
    if sourcePath:sub(-1) == "/" then
        sourcePath = sourcePath:sub(1, -2)
    end
    if destPath:sub(-1) == "/" then
        destPath = destPath:sub(1, -2)
    end
    
    local listing = fetchDirectoryListing(sourcePath)
    if not listing then
        return false
    end
    
    if not fs.exists(destPath) then
        fs.makeDir(destPath)
    end
    
    local success = true
    for _, item in ipairs(listing) do
        if item.type == "file" then
            local fileDest = fs.combine(destPath, item.name)
            if not downloadFile(item.path, fileDest) then
                success = false
            end
        elseif item.type == "dir" then
            local subDest = fs.combine(destPath, item.name)
            if not downloadDirectory(item.path, subDest) then
                success = false
            end
        end
    end
    
    return success
end

local function createStartupScript(systemName)
    local system = metadata.systems[systemName]
    if not system or not system.startup then
        return
    end
    
    local content = string.format([[
-- Auto-generated startup script for %s
shell.execute("%s.lua")
]], systemName, system.startup)
    
    local file = fs.open("startup.lua", "w")
    file.write(content)
    file.close()
    
    log("Created startup.lua for " .. systemName, colors.green)
end

local function checkRequirements(requirements)
    if not requirements then return true end
    
    for _, req in ipairs(requirements) do
        if req == "turtle" and not turtle then
            log("ERROR: This system requires a turtle", colors.red)
            return false
        else
            if not peripheral.find(req) then
                log("ERROR: Missing required peripheral: " .. req, colors.red)
                return false
            end
        end
    end
    
    return true
end

local function installSystem(systemName)
    if not metadata then
        if not fetchMetadata() then
            return false
        end
    end
    
    local system = metadata.systems[systemName]
    if not system then
        log("Unknown system: " .. systemName, colors.red)
        log("Use 'ccmsi list' to see available systems", colors.yellow)
        return false
    end
    
    printHeader("Installing " .. system.name)
    
    if not checkRequirements(system.requirements) then
        return false
    end
    
    local success = true
    
    if metadata.files then
        for _, file in ipairs(metadata.files) do
            if file.source:sub(-1) == "/" then
                if not downloadDirectory(file.source, file.destination) then
                    success = false
                end
            else
                if not downloadFile(file.source, file.destination) then
                    success = false
                end
            end
        end
    end
    
    if system.files then
        for _, file in ipairs(system.files) do
            if file.source:sub(-1) == "/" then
                if not downloadDirectory(file.source, file.destination) then
                    success = false
                end
            else
                if not downloadFile(file.source, file.destination) then
                    success = false
                end
            end
        end
    end
    
    if success then
        createStartupScript(systemName)
        log(system.name .. " installation complete!", colors.lime)
        print("")
        print("To start, run:")
        print("  " .. system.startup)
        print("")
        print("Or reboot to auto-start")
    else
        log("Installation failed - some files could not be downloaded", colors.red)
    end
    
    return success
end

local function listSystems()
    if not metadata then
        if not fetchMetadata() then
            return
        end
    end
    
    printHeader("Available Systems")
    print("")
    
    for name, system in pairs(metadata.systems) do
        term.setTextColor(colors.yellow)
        print(name .. " - " .. system.name)
        term.setTextColor(colors.gray)
        print("  " .. system.description)
        term.setTextColor(colors.white)
        print("")
    end
end

local function updateSelf()
    printHeader("Updating ccmsi")
    
    local updateUrl = string.format("https://raw.githubusercontent.com/%s/%s/ccmsi.lua", repo, branch)
    
    local response = http.get(updateUrl)
    if not response then
        log("Failed to download update", colors.red)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local file = fs.open("ccmsi_new.lua", "w")
    file.write(content)
    file.close()
    
    fs.delete("ccmsi.lua")
    fs.move("ccmsi_new.lua", "ccmsi.lua")
    
    log("ccmsi updated successfully!", colors.lime)
    print("Please run ccmsi again")
    return true
end

local function cleanInstallation()
    if not metadata then
        if not fetchMetadata() then
            return
        end
    end
    
    printHeader("Cleaning Installation")
    
    if metadata.cleanup then
        for _, dir in ipairs(metadata.cleanup.directories or {}) do
            if fs.exists(dir) then
                fs.delete(dir)
                log("Deleted directory: " .. dir, colors.yellow)
            end
        end
        
        for _, file in ipairs(metadata.cleanup.files or {}) do
            if fs.exists(file) then
                fs.delete(file)
                log("Deleted file: " .. file, colors.yellow)
            end
        end
        
        for _, pattern in ipairs(metadata.cleanup.patterns or {}) do
            local files = fs.list(".")
            for _, file in ipairs(files) do
                if file:match(pattern:gsub("*", ".*")) then
                    fs.delete(file)
                    log("Deleted file: " .. file, colors.yellow)
                end
            end
        end
    end
    
    log("Cleanup complete", colors.lime)
end

local function setMetadataUrl(url)
    local config = loadSettings()
    config.metadataUrl = url
    saveSettings(config)
    log("Metadata URL set to: " .. url, colors.green)
end

local function main()
    if #args == 0 then
        printUsage()
        return
    end
    
    local command = args[1]:lower()
    
    if command == "list" then
        listSystems()
    elseif command == "update" then
        updateSelf()
    elseif command == "clean" then
        cleanInstallation()
    elseif command == "help" then
        printUsage()
    elseif command == "seturl" and args[2] then
        setMetadataUrl(args[2])
    elseif command == "seturl" then
        log("Please provide a URL", colors.red)
    else
        cleanInstallation()
        installSystem(command)
    end
end

main()