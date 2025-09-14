local meBridge = peripheral.find("meBridge")
if not meBridge then
    error("Error: Could not find ME Bridge peripheral.")
end

local function formatFE(num)
    local prefixes = {"FE", "KFE", "MFE", "GFE", "TFE", "PFE"}
    local i = 1
    while num >= 1000 and i < #prefixes do
        num = num / 1000
        i = i + 1
    end
    return string.format("%.0f %s", num, prefixes[i])
end

local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if success then
        return result, nil
    else
        return nil, tostring(result)
    end
end

local function getMeSystemItems()
    local items, err = safeCall(meBridge.listItems)
    if not items then
        return "Error retrieving items: " .. (err or "unknown error")
    end

    local itemDescriptions = {}
    for _, item in pairs(items) do
        local description
        if item.amount and item.amount > 0 then
            description = string.format("%s x%d", item.name, item.amount)
            if item.isCraftable then
                description = description .. " (craftable)"
            end
        else
            description = item.name .. " (pattern only)"
        end
        table.insert(itemDescriptions, description)
    end

    return #itemDescriptions > 0 and table.concat(itemDescriptions, ", ") or "No items in system"
end

local function getMeSystemFluids()
    local fluids, err = safeCall(meBridge.listFluid)
    if not fluids then
        return "Error retrieving fluids: " .. (err or "unknown error")
    end

    local fluidDescriptions = {}
    for _, fluid in pairs(fluids) do
        table.insert(fluidDescriptions, string.format("%s x%d mB", fluid.name, fluid.amount))
    end

    return #fluidDescriptions > 0 and table.concat(fluidDescriptions, ", ") or "No fluids in system"
end

local function getMeSystemGases()
    local gases, err = safeCall(meBridge.listGas)
    if not gases then
        return "Error retrieving gases: " .. (err or "unknown error")
    end

    local gasDescriptions = {}
    for _, gas in pairs(gases) do
        table.insert(gasDescriptions, string.format("%s x%d mB", gas.name, gas.amount))
    end

    return #gasDescriptions > 0 and table.concat(gasDescriptions, ", ") or "No gases in system"
end

local function getMeSystemProperties()
    local properties = {}

    local storageMetrics = {
        {"Total Item Storage", meBridge.getTotalItemStorage},
        {"Used Item Storage", meBridge.getUsedItemStorage},
        {"Available Item Storage", meBridge.getAvailableItemStorage},
        {"Total Fluid Storage", meBridge.getTotalFluidStorage},
        {"Used Fluid Storage", meBridge.getUsedFluidStorage},
        {"Available Fluid Storage", meBridge.getAvailableFluidStorage}
    }

    for _, metric in ipairs(storageMetrics) do
        local value = safeCall(metric[2])
        if value then
            table.insert(properties, string.format("%s: %d", metric[1], value))
        end
    end

    local cpus = safeCall(meBridge.getCraftingCPUs)
    if cpus then
        local cpuInfo = {}
        local busyCount = 0
        local availableCount = 0

        for i, cpu in ipairs(cpus) do
            if cpu.isBusy then
                busyCount = busyCount + 1
            else
                availableCount = availableCount + 1
            end

            local cpuName = cpu.name or ("CPU " .. i)
            local status = cpu.isBusy and "BUSY" or "Available"
            table.insert(cpuInfo, string.format("  %s: %s (Storage: %d, CoProc: %d)",
                cpuName, status, cpu.storage or 0, cpu.coProcessors or 0))
        end

        table.insert(properties, string.format("\nCrafting CPUs: %d available, %d busy",
            availableCount, busyCount))
        if #cpuInfo > 0 then
            table.insert(properties, table.concat(cpuInfo, "\n"))
        end
    end

    return table.concat(properties, "\n")
end

local function getEnergyStorageInfo()
    local energyInfo = {}
    local totalEnergy = 0
    local totalMaxEnergy = 0

    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType and string.find(pType, "induction") then
            local matrix = peripheral.wrap(name)
            if matrix and matrix.getEnergy and matrix.getMaxEnergy then
                local current = safeCall(matrix.getEnergy) or 0
                local max = safeCall(matrix.getMaxEnergy) or 0

                if current > 0 or max > 0 then
                    totalEnergy = totalEnergy + current
                    totalMaxEnergy = totalMaxEnergy + max

                    local matrixNum = string.match(name, "%d+$") or "?"
                    table.insert(energyInfo, string.format("Matrix %s: %s/%s (%.1f%%)",
                        matrixNum, formatFE(current), formatFE(max),
                        max > 0 and (current/max*100) or 0))
                end
            end
        end
    end

    if #energyInfo > 0 then
        local header = string.format("Total: %s/%s (%.1f%%)",
            formatFE(totalEnergy), formatFE(totalMaxEnergy),
            totalMaxEnergy > 0 and (totalEnergy/totalMaxEnergy*100) or 0)
        return header .. "\n" .. table.concat(energyInfo, "\n")
    else
        return "No energy storage detected"
    end
end

local functionHandlers = {
    export_item = function(args)
        if not args.items or #args.items == 0 then
            return {error = "No items specified"}
        end
        if not args.direction then
            return {error = "No direction specified"}
        end

        local results = {}
        local totalExported = 0

        for _, item in ipairs(args.items) do
            local exported, err = meBridge.exportItem(item, args.direction)
            if err then
                table.insert(results, string.format("Failed: %s - %s", item.name, err))
            else
                totalExported = totalExported + (exported or 0)
                table.insert(results, string.format("Exported %d x %s", exported or 0, item.name))
            end
        end

        return {
            success = totalExported > 0,
            total_exported = totalExported,
            details = results
        }
    end,

    import_item = function(args)
        if not args.items or #args.items == 0 then
            return {error = "No items specified"}
        end
        if not args.direction then
            return {error = "No direction specified"}
        end

        local results = {}
        local totalImported = 0

        for _, item in ipairs(args.items) do
            local imported, err = meBridge.importItem(item, args.direction)
            if err then
                table.insert(results, string.format("Failed: %s - %s", item.name, err))
            else
                totalImported = totalImported + (imported or 0)
                table.insert(results, string.format("Imported %d x %s", imported or 0, item.name))
            end
        end

        return {
            success = totalImported > 0,
            total_imported = totalImported,
            details = results
        }
    end,

    is_crafting = function(args)
        if not args.item then
            return {error = "No item specified"}
        end

        local crafting, err = meBridge.isItemCrafting(args.item, args.crafting_cpu)
        if err then
            return {error = tostring(err)}
        end

        return {
            success = true,
            is_crafting = crafting,
            item = args.item.name,
            cpu = args.crafting_cpu
        }
    end,

    get_pattern_ingredients = function(args)
        if not args.item then
            return {error = "No item specified"}
        end

        local result, err = meBridge.getPatternIngredients(args.item, true, false)
        if not result then
            return {error = tostring(err or "Pattern not found")}
        end

        local ingredients = {}
        for _, group in ipairs(result.ingredients or {}) do
            for _, ing in ipairs(group) do
                table.insert(ingredients, {
                    name = ing.name,
                    amount = ing.amount or 1
                })
            end
        end

        local affordable, missing = meBridge.isCraftAffordable(args.item)

        return {
            success = true,
            item = args.item.name,
            affordable = affordable,
            ingredients = ingredients,
            missing = type(missing) == "table" and missing or nil
        }
    end,

    is_craft_affordable = function(args)
        if not args.item then
            return {error = "No item specified"}
        end

        local affordable, missing = meBridge.isCraftAffordable(args.item, args.amount or 1)

        return {
            success = true,
            item = args.item.name,
            affordable = affordable,
            missing = type(missing) == "table" and missing or nil
        }
    end,

    craft_items = function(args)
        if not args.items or #args.items == 0 then
            return {error = "No items specified"}
        end

        local results = {}
        local successCount = 0
        local allMissing = {}

        for _, item in ipairs(args.items) do
            local affordable, missing = meBridge.isCraftAffordable(item, item.count or 1)

            if affordable then
                local success, err = meBridge.craftItem(item, item.crafting_cpu)
                if err then
                    table.insert(results, string.format("Failed: %s - %s", item.name, err))
                else
                    successCount = successCount + 1
                    local cpuMsg = item.crafting_cpu and (" on " .. item.crafting_cpu) or ""
                    table.insert(results, string.format("Started: %s x%d%s",
                        item.name, item.count or 1, cpuMsg))
                end
            else
                table.insert(results, string.format("Cannot afford: %s", item.name))
                if type(missing) == "table" then
                    for _, m in ipairs(missing) do
                        table.insert(allMissing, string.format("%s x%d", m.name, m.amount))
                    end
                end
            end
        end

        return {
            success = successCount > 0,
            crafted = successCount,
            failed = #args.items - successCount,
            details = results,
            missing = #allMissing > 0 and allMissing or nil
        }
    end
}

local function handleMeFunctionCalls(functionName, functionArgs)
    local handler = functionHandlers[functionName]
    if handler then
        local success, result = pcall(handler, functionArgs)
        if success then
            return textutils.serializeJSON(result)
        else
            return textutils.serializeJSON({error = "Function failed: " .. tostring(result)})
        end
    else
        return textutils.serializeJSON({error = "Unknown function: " .. functionName})
    end
end

return {
    getItems = getMeSystemItems,
    getFluids = getMeSystemFluids,
    getGases = getMeSystemGases,
    getProperties = getMeSystemProperties,
    getEnergyInfo = getEnergyStorageInfo,
    handleFunctionCall = handleMeFunctionCalls,
    bridge = meBridge
}
