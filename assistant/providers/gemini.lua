local config = require("assistant.config")
local me = require("assistant.meSystem")
local baseProvider = require("assistant.providers.provider")
local comm = require("assistant.comm")

local gemini = {}
setmetatable(gemini, { __index = baseProvider })

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

function gemini.new(config, model, apiKey, apiUrl)
    local self = baseProvider.new(config, model, apiKey, apiUrl)
    setmetatable(self, {__index = gemini})
    return self
end

function gemini:sendRequest(requestParams)
    local requestUrl = self.apiUrl .. "/models/" .. self.model.name .. ":generateContent?key=" .. self.apiKey
    print("Requesting from " .. requestUrl)
    local systemInstructions = requestParams.systemPrompt

    local function buildRequestBody(history, systemInstructions)
        local body = {
            contents = {},
            generationConfig = {
                temperature = requestParams.generationConfig.temperature,
                maxOutputTokens = requestParams.generationConfig.max_tokens,
                topP = requestParams.generationConfig.top_p,
                topK = requestParams.generationConfig.top_k,
            }
        }

        if systemInstructions and systemInstructions ~= "" then
            body.systemInstruction = {
                parts = { { text = systemInstructions } }
            }
        end

        for _, msg in ipairs(history) do
            local role = msg.role
            if role == "assistant" then role = "model" end
            if role == "tool" then role = "tool" end
            table.insert(body.contents, { role = role, parts = { { text = msg.content } } })
        end
        return body
    end

    local function extractFunctionCalls(response_output)
        local function_calls = {}
        for func_call_json in string.gmatch(response_output, "__FN_CALL__({.-})__FN_CALL__") do
            table.insert(function_calls, textutils.unserializeJSON(func_call_json))
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
                role = "tool",
                name = function_name,
                content = textutils.serializeJSON(function_response),
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

        if parsedResponse and parsedResponse.candidates and parsedResponse.candidates[1] then
            local response_output = parsedResponse.candidates[1].content.parts[1].text
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
                 local tool_call_message_for_history = "__TOOL_START__\n"
                for i, func_call_data in ipairs(function_calls) do
                    tool_call_message_for_history = tool_call_message_for_history .. "__FN_CALL__" .. textutils.serializeJSON(func_call_data) .. "__FN_CALL__"
                    if i < #function_calls then
                        tool_call_message_for_history = tool_call_message_for_history .. "\n"
                    end
                end
                tool_call_message_for_history = tool_call_message_for_history .. "\n__TOOL_END__"

                table.insert(requestParams.history, { role = "assistant", content = tool_call_message_for_history })

                local tool_responses = handle_tool_calls(function_calls, requestParams.tools)

                for _, tool_response in ipairs(tool_responses) do
                   table.insert(requestParams.history, tool_response)
                end

                return buildRequestBody(requestParams.history, systemInstructions), nil
            else
                return nil, string.gsub(response_output, "__FN_CALL__{.-}__FN_CALL__", "")
            end
        else
             print(textutils.serialize(parsedResponse))
            return nil, "Unexpected response format from Gemini API."
        end
    end

    local function makeApiRequest(body, stream)
        local headers = {
            ["Content-Type"] = "application/json",
        }
        local jsonBody = textutils.serializeJSON(body)
        local requestUrlParams = ""
        if stream then
          requestUrlParams = requestUrlParams .. "&alt=sse"
        end

        local ok, err = http.request {
            url = requestUrl..requestUrlParams,
            body = jsonBody,
            headers = headers,
            method = "POST",
            timeout = 300,
        }
        if not ok then
            return nil, err
        end

        while true do
            local event, url, response, reason, responseCode = os.pullEvent()
            if url == (requestUrl..requestUrlParams) then
                if event == "http_success" or event == "http_failure" then
                    local logPath = config.getScriptRelative("logs")
                    if not fs.exists(logPath) then fs.makeDir(logPath) end
                    local file = fs.open(config.getScriptRelative("logs/tool_log" .. os.epoch("utc") .. ".lua"), "w")
                    file.write("Request made to " .. (requestUrl..requestUrlParams) .. "\n")
                    file.write("Request body: " .. jsonBody .. "\n")
                    file.close()
                    return event == "http_success", { response = response, reason = reason, responseCode = responseCode }
                end
            end
        end
    end

    local initialRequestBody = buildRequestBody(requestParams.history, systemInstructions)
    local success, responseOrError = makeApiRequest(initialRequestBody, false)

    while true do
        if success then
            local newBody, content = handleResponse(true, responseOrError.response, responseOrError.reason, responseOrError.responseCode)
            if newBody then
               success, responseOrError = makeApiRequest(newBody, false)
            else
                return content, nil
            end
        elseif type(responseOrError) == "table" and (responseOrError.reason == "Too Many Requests" or responseOrError.reason == "Service Unavailable") then
            local retryDelay = 5
            print("Model failed with '" .. responseOrError.reason .. "'. Retrying in " .. retryDelay .. " seconds...")
            comm.sendMessage("Model failed. Retrying in " .. retryDelay .. " seconds...")
            os.sleep(retryDelay)
            success, responseOrError = makeApiRequest(initialRequestBody, false)
        elseif type(responseOrError) == "string" then
            return nil, responseOrError
        else
            return nil, "Unknown error occurred during API request"
        end
    end
end

return gemini