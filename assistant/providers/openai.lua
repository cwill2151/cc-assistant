local config = require("assistant.config")
local me = require("assistant.meSystem")
local baseProvider = require("assistant.providers.provider")
local comm = require("assistant.comm")

local openai = {}
setmetatable(openai, { __index = baseProvider })

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

function openai.new(config, model, apiKey, apiUrl)
    local self = baseProvider.new(config, model, apiKey, apiUrl)
    setmetatable(self, {__index = openai})
    return self
end

function openai:sendRequest(requestParams)
    local requestUrl = self.apiUrl .. "/chat/completions"
    print("Requesting from " .. requestUrl)
    local systemInstructions = requestParams.systemPrompt

    local function buildRequestBody(history)
        local body = {
            model = self.model.name,
            messages = { { role = "system", content = systemInstructions } },
            temperature = requestParams.generationConfig.temperature,
            max_tokens = requestParams.generationConfig.max_tokens,
            stream = false
        }
        for _, msg in ipairs(history) do
            table.insert(body.messages, msg)
        end
        return body
    end

    local function extractFunctionCalls(response_output)
        local function_calls = {}
        for tool_content in string.gmatch(response_output, "<tool>(.-)</tool>") do
            local name = string.match(tool_content, "<name>(.-)</name>")
            local args_json = string.match(tool_content, "<args>(.-)</args>")

            if name and args_json then
                local args = textutils.unserializeJSON(args_json)
                if args then
                    table.insert(function_calls, {
                        name = name,
                        args = args
                    })
                end
            end
        end
        return function_calls
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

    local function handleResponse(success, response, reason, responseCode)
        if not success then
            local responseBody = response and response.readAll()
            print("HTTP request failed: " .. tostring(reason))
            if responseBody then
                print("Response body: " .. responseBody)
            end
            return nil, "HTTP request failed: " .. tostring(reason)
        end

        local body = response.readAll()
        response.close()

        if not body then
            return nil, "Empty response body."
        end

        local parsedResponse, pos, err = textutils.unserializeJSON(body)
        if not parsedResponse then
            print("Failed to parse JSON response at position: " .. tostring(pos))
            return nil, "Failed to parse JSON response: " .. tostring(err) .. tostring(body)
        end

        if parsedResponse and parsedResponse.choices and parsedResponse.choices[1] then
            local response_output = parsedResponse.choices[1].message.content
            local think_text = string.match(response_output, "<think>(.-)</think>")

            if think_text then
                local file = fs.open(config.getScriptRelative("./logs/think_output" .. os.epoch("utc") .. ".txt"), "w")
                if file then
                    file.write(think_text)
                    file.close()
                else
                    error("Unable to open file for writing")
                end
            end

            response_output = trim(string.gsub(response_output, "<think>.-</think>", ""))
            local function_calls = extractFunctionCalls(response_output)

            if #function_calls > 0 then
                table.insert(requestParams.history, { role = "assistant", content = response_output })

                local tool_responses = handle_tool_calls(function_calls, requestParams.tools)
                for _, tool_response in ipairs(tool_responses) do
                    table.insert(requestParams.history, tool_response)
                end

                return buildRequestBody(requestParams.history), nil
            else
                local clean_output = string.gsub(response_output, "<tool>.-</tool>", "")
                return nil, trim(clean_output)
            end
        else
            print(textutils.serialize(parsedResponse))
            return nil, "Unexpected response format from API."
        end
    end

    local function makeApiRequest(body)
        local headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. self.apiKey
        }
        local jsonBody = textutils.serializeJSON(body)
        local ok, err = http.request {
            url = requestUrl,
            body = jsonBody,
            headers = headers,
            method = "POST",
            timeout = 60
        }
        if not ok then
            return nil, err
        end

        while true do
            local event, url, response, reason, responseCode = os.pullEvent()
            if url == requestUrl then
                if event == "http_success" or event == "http_failure" then
                    local logPath = config.getScriptRelative("logs")
                    if not fs.exists(logPath) then fs.makeDir(logPath) end
                    local file = fs.open(config.getScriptRelative("logs/tool_log" .. os.epoch("utc") .. ".lua"), "w")
                    file.write("Request made to " .. requestUrl .. "\n")
                    file.write("Request body: " .. jsonBody .. "\n")
                    file.close()
                    return event == "http_success", { response = response, reason = reason, responseCode = responseCode }
                end
            end
        end
    end

    local initialRequestBody = buildRequestBody(requestParams.history)
    local success, responseOrError = makeApiRequest(initialRequestBody)
    while true do
        if success then
            local newBody, content = handleResponse(true, responseOrError.response, responseOrError.reason, responseOrError.responseCode)
            if newBody then
                success, responseOrError = makeApiRequest(newBody)
            else
                return content, nil
            end
        elseif type(responseOrError) == "table" and (responseOrError.reason == "Too Many Requests" or responseOrError.reason == "Service Unavailable") then
            local retryDelay = 5
            print("Model failed with '" .. responseOrError.reason .. "'. Retrying in " .. retryDelay .. " seconds...")
            comm.sendMessage("Model failed. Retrying in " .. retryDelay .. " seconds...")
            os.sleep(retryDelay)
            success, responseOrError = makeApiRequest(initialRequestBody)
        elseif type(responseOrError) == "string" then
            return nil, responseOrError
        else
            return nil, "Unknown error occurred during API request"
        end
    end
end

return openai
