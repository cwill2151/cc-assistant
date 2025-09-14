require("/initenv").init_env()

local config = require("assistant.config")
local comm = require("assistant.comm")
local me = require("assistant.meSystem")
local meTools = require("assistant.tools.meTools")
local providerModule

local systemPrompt = "You are a system administrator named Jarvis who manages a whole facility. Keep your responses filled with personality. Never use markdown and no asterisks. ONLY use ascii characters, no emojis or special characters."
local messageHistory = {}
local maxHistoryLength = 65536

local loadedConfig = config.loadConfig()
local provider, model, apiKey, apiUrl = config.getProvider(loadedConfig)
providerModule = require("assistant.providers." .. provider.base).new(loadedConfig, model, apiKey, apiUrl)
local generationConfig = config.getModelParams(loadedConfig, model)
print(loadedConfig.assistant_name .. " has been initialized. Provider: " .. provider.name .. ", Model: " .. model.name)

local function removeOldLogs()
    local logPath = "/logs"
    if not fs.exists(logPath) then
        fs.makeDir(logPath)
    end
    local files = fs.list(logPath)
    for _, file in ipairs(files) do
        if file:find("tool_log") then
            local file_time = file:match("%d+") or 0
            if os.epoch("utc") - tonumber(file_time) > 1024 then
                fs.delete(logPath .. "/" .. file)
            end
        end
    end
end

local function constructSystemPrompt()
    local meSystemItems = me.getItems()
    local meSystemFluids = me.getFluids()
    local meSystemGases = me.getGases()
    local meSystemProperties = me.getProperties()
    local energyStorageInfo = me.getEnergyInfo()

    local toolsDescription = ""
    for _, tool in ipairs(meTools) do
        toolsDescription = toolsDescription .. string.format([[
%s - %s
  Parameters: %s
  Example: %s
]], tool.name, tool.description, textutils.serializeJSON(tool.parameters), tool.example)
    end

    local systemInstructions = string.format([[
You are Jarvis, a helpful AI assistant managing a facility's ME (Matter Energy) system.
Keep responses short, concise, and filled with personality. Use ONLY ASCII characters, NEVER use unicode emojis or special characters.

CURRENT SYSTEM STATUS:
Items: %s
Fluids: %s
Gases: %s
Properties: %s
Energy: %s

TOOL CALLING:
When you need to perform an action, use this XML format:
<tool>
<name>function_name</name>
<args>JSON_ARGUMENTS</args>
</tool>

You can call multiple tools in one response. After tools execute, you'll receive their results and should provide a human-friendly summary to the user.

AVAILABLE TOOLS:
%s

IMPORTANT GUIDELINES:
- Always confirm destructive operations (like crafting) with the user first
- Use exact item/fluid/gas names including mod identifiers (e.g., "minecraft:iron_ingot")
- When importing without a specified amount, use 99999 to import all
- Remember deepslate ore variants are different items
- For tiered items without specified tier, suggest the highest available
- mB = millibuckets, FE = Forge Energy, EU = Energy Units (GregTech)
- Do not try to give information about stuff you don't know, for example a tool call says item x isn't available, do not try to tell how to make it if you don't have actual information from tools.

EXAMPLE INTERACTIONS:

User: "How much iron do we have?"
Let me check the iron inventory for you. We currently have X iron ingots in storage.

User: "Import all cobblestone from the chest above"
I'll import all available cobblestone from the chest above.
<tool>
<name>import_item</name>
<args>{"items": [{"name": "minecraft:cobblestone", "count": 99999}], "direction": "up"}</args>
</tool>

User: "Craft 64 pistons"
I can craft 64 pistons for you. This will use iron ingots, cobblestone, redstone, and wood planks. Should I proceed?
[After confirmation]
<tool>
<name>craft_items</name>
<args>{"items": [{"name": "minecraft:piston", "count": 64}]}</args>
</tool>

User: "Export a stack of diamonds to the south"
<tool>
<name>export_item</name>
<args>{"items": [{"name": "minecraft:diamond", "count": 64}], "direction": "south"}</args>
</tool>

Remember: Be helpful, efficient, and always explain what you're doing in a friendly way!
]], meSystemItems, meSystemFluids, meSystemGases, meSystemProperties, energyStorageInfo, toolsDescription)

    return systemInstructions
end

local function calculateMessageLength(message)
    return (message and message.content) and string.len(message.content) or 0
end

local function trimMessageHistory(messageHistory, maxHistoryLength)
    local currentLength = 0
    local trimmedHistory = {}

    for i = #messageHistory, 1, -1 do
        local msg = messageHistory[i]

        if msg.role == "assistant" and i > 1 and messageHistory[i-1].role == "user" then
            local userMsg = messageHistory[i-1]
            local modelMsg = msg
            local pairLength = calculateMessageLength(userMsg) + calculateMessageLength(modelMsg)

            if currentLength + pairLength <= maxHistoryLength then
                table.insert(trimmedHistory, 1, modelMsg)
                table.insert(trimmedHistory, 1, userMsg)
                currentLength = currentLength + pairLength
                i = i - 1
            else
                break
            end
        end
    end

    return trimmedHistory
end

local function handle_tool_calls(tool_calls, tools)
    local tool_responses = {}
    for _, tool_call in ipairs(tool_calls) do
        local function_name = tool_call.name
        local function_args = tool_call.args
        print("Function: " .. function_name)
        print("Arguments: " .. textutils.serializeJSON(function_args))

        local function_response = me.handleFunctionCall(function_name, function_args)
        print("Response: " .. textutils.serializeJSON(function_response))

        table.insert(tool_responses, {
            role = "assistant",
            name = function_name,
            content = function_response,
        })
    end
    return tool_responses
end

while true do
    local event, username, message, uuid, isHidden = os.pullEvent("chat")
    removeOldLogs()

    if string.lower(string.sub(message, 1, 6)) == "jarvis" then
        local prompt = message
        print("Prompt: " .. prompt)

        table.insert(messageHistory, { role = "user", content = prompt })

        local fullSystemPrompt = constructSystemPrompt()
        local requestParams = {
            apiKey = apiKey,
            apiUrl = apiUrl,
            model = model,
            prompt = prompt,
            generationConfig = generationConfig,
            systemPrompt = fullSystemPrompt,
            history = messageHistory,
            meBridge = me.bridge,
            provider = provider,
            tools = meTools,
            handle_tool_calls = handle_tool_calls
        }

        local generatedText, err = providerModule:sendRequest(requestParams)

        if err then
            comm.sendMessage("Error: " .. err)
        else
            print("Generated text: " .. generatedText)
            comm.sendMessage(generatedText)
            table.insert(messageHistory, { role = "assistant", content = generatedText })
        end
    elseif string.sub(message, 1, 8) == "!history" then
        print("Received command from " .. username .. ": " .. message)
        local history = ""
        for i = #messageHistory, 1, -1 do
            local msg = messageHistory[i]
            if msg.role == "user" then
                history = history .. "User: " .. msg.content .. "\n"
            elseif msg.role == "assistant" then
                history = history .. "Model: " .. msg.content .. "\n"
            elseif msg.role == "tool" then
                history = history .. "Tool: " .. msg.content .. "\n"
            end
        end
        comm.sendMessage("Message History:\n" .. history)
    elseif string.sub(message, 1, 6) == "!clear" then
        print("Received command from " .. username .. ": " .. message)
        messageHistory = {}
        comm.sendMessage("Message history cleared.")
    elseif string.sub(message, 1, 10) == "!providers" then
        config.listProviders(loadedConfig, comm)
    elseif string.sub(message, 1, 9) == "!provider" then
        config.handleProviderCommand(message, loadedConfig, comm)
        loadedConfig = config.loadConfig()
        provider, model, apiKey, apiUrl = config.getProvider(loadedConfig)
        providerModule = require("providers." .. provider.base).new(loadedConfig, model, apiKey, apiUrl)
        generationConfig = config.getModelParams(loadedConfig, model)
    elseif string.sub(message, 1, 7) == "!models" then
        local parts = {}
        for part in string.gmatch(message, "[^%s]+") do
            table.insert(parts, part)
        end
        if #parts >= 2 then
            local providerName = table.concat(parts, " ", 2)
            config.listModels(loadedConfig, providerName, comm)
        else
            config.listModels(loadedConfig, provider.name, comm)
        end
    elseif string.sub(message, 1, 7) == "!config" then
        comm.sendMessage("Current provider: " .. provider.name .. ", Current model: " .. model.name)
    end
end
