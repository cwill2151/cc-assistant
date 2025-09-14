local commonConfig = require("common.config")

local loadConfig = commonConfig.loadConfig
local saveConfig = commonConfig.saveConfig
local trim = commonConfig.trim

local function findModelByName(provider, modelNamePartial)
    local modelNamePartialLower = modelNamePartial:lower()
    for _, model in ipairs(provider.models) do
        if trim(model.name:lower()) == trim(modelNamePartialLower) then
            return model
        end
    end
    return nil
end

local function getProvider(config)
    local selectedProviderName = config.selected_provider
    local modelNamePartial = config.selected_model

    local provider = nil
    for _, p in ipairs(config.providers) do
        if p.name == selectedProviderName then
            provider = p
            break
        end
    end

    if not provider then
        error("Provider '" .. selectedProviderName .. "' not found in configuration.")
    end

    local model = findModelByName(provider, modelNamePartial)
    if not model then
        error("Model matching '" .. modelNamePartial .. "' not found in provider '" .. selectedProviderName .. "'.")
    end

    local apiKey = config[selectedProviderName .. "_Key"]
    local apiBase = config[selectedProviderName .. "_Base"]

    return provider, model, apiKey, apiBase
end

local function getModelParams(config, model)
    if model and model.params == "default" then
        return config.default_params
    elseif model and model.params then
        return textutils.combine(config.default_params, model.params)
    else
        return config.default_params
    end
end

local function handleProviderCommand(message, config, comm)
    local parts = {}
    for part in string.gmatch(message, "[^%s]+") do
        table.insert(parts, part)
    end

    if #parts >= 3 then
        local newProvider = parts[2]
        local newModel = table.concat(parts, " ", 3)

        local exactProviders = {}
        for _, p in ipairs(config.providers) do
            if p.name:lower() == newProvider:lower() then
                table.insert(exactProviders, p)
            end
        end

        local provider
        if #exactProviders == 1 then
            provider = exactProviders[1]
        elseif #exactProviders > 1 then
            comm.sendMessage("Error: Multiple providers exactly named '" .. newProvider .. "' (case-insensitive) found")
            return
        else
            local partialProviders = {}
            for _, p in ipairs(config.providers) do
                if string.find(p.name:lower(), newProvider:lower(), 1, true) then
                    table.insert(partialProviders, p)
                end
            end
            if #partialProviders == 0 then
                comm.sendMessage("Error: Provider matching '" .. newProvider .. "' not found")
                return
            elseif #partialProviders > 1 then
                comm.sendMessage("Error: Multiple providers matching '" .. newProvider .. "' found")
                return
            end
            provider = partialProviders[1]
        end

        local exactModels = {}
        for _, m in ipairs(provider.models) do
            if m.name:lower() == newModel:lower() then
                table.insert(exactModels, m)
            end
        end

        local model
        if #exactModels == 1 then
            model = exactModels[1]
        elseif #exactModels > 1 then
            comm.sendMessage("Error: Multiple models exactly named '" .. newModel .. "' found in provider '" .. provider.name .. "'")
            return
        else
            local partialModels = {}
            for _, m in ipairs(provider.models) do
                if string.find(m.name:lower(), newModel:lower(), 1, true) then
                    table.insert(partialModels, m)
                end
            end
            if #partialModels == 0 then
                comm.sendMessage("Error: Model matching '" .. newModel .. "' not found in provider '" .. provider.name .. "'")
                return
            elseif #partialModels > 1 then
                comm.sendMessage("Error: Multiple models matching '" .. newModel .. "' found in provider '" .. provider.name .. "'")
                return
            end
            model = partialModels[1]
        end

        local configFile = commonConfig.getConfigPath()
        local file = fs.open(configFile, "r")
        if file then
            local lines = {}
            while true do
                local line = file.readLine()
                if line == nil then
                    break
                end
                table.insert(lines, line)
            end
            file.close()

            for i, line in ipairs(lines) do
                if line:find('"selected_provider"') then
                    lines[i] = '    "selected_provider": "' .. provider.name .. '",'
                elseif line:find('"selected_model"') then
                    lines[i] = '    "selected_model": "' .. model.name .. '",'
                end
            end

            local fileW = fs.open(configFile, "w")
            if fileW then
                for _, line in ipairs(lines) do
                    fileW.writeLine(line)
                end
                fileW.close()
                comm.sendMessage("Provider set to " .. provider.name .. " and model set to " .. model.name)
            else
                comm.sendMessage("Error: Could not write to config.json")
            end
        else
            comm.sendMessage("Error: Could not open config.json for reading")
        end

    else
        comm.sendMessage("Error: Invalid !provider command format. Usage: !provider <provider_name> <model_name>")
        return
    end
end

local function listProviders(config, comm)
    local providerNames = {}
    for _, p in ipairs(config.providers) do
        table.insert(providerNames, p.name)
    end
    comm.sendMessage("Available providers: " .. table.concat(providerNames, ", "))
end

local function listModels(config, comm)
    local matchingProviders = {}
    for _, p in ipairs(config.providers) do
        if string.find(p.name:lower(), providerName:lower()) then
            table.insert(matchingProviders, p)
        end
    end

    if #matchingProviders == 0 then
        comm.sendMessage("Error: Provider matching '" .. providerName .. "' not found")
        return
    elseif #matchingProviders > 1 then
        comm.sendMessage("Error: Multiple providers matching '" .. providerName .. "' found")
        return
    end

    local provider = matchingProviders[1]
    local modelNames = {}
    for _, m in ipairs(provider.models) do
        table.insert(modelNames, m.name)
    end
    comm.sendMessage("Models for " .. provider.name .. ": " .. table.concat(modelNames, ", "))
end

return {
    loadConfig = loadConfig,
    saveConfig = saveConfig,
    
    getProvider = getProvider,
    getModelParams = getModelParams,
    handleProviderCommand = handleProviderCommand,
    listProviders = listProviders,
    listModels = listModels
}
