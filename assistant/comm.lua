local configModule = require("assistant.config")
local config = configModule.loadConfig()
local assistantName = config.assistant_name
local chatBoxEnabled = config.communication.chat_box
local discordEnabled = config.communication.discord
local webhookURL = config.communication.webhook_url

local chatBox = peripheral.find("chatBox")
if not chatBoxEnabled or chatBox == nil then
    print("Chat box is not enabled or not found.")
    chatBoxEnabled = false
end

local function sendToDiscord(message)
    if not discordEnabled or not webhookURL then
        return false, "Discord is not enabled or webhook URL is not configured"
    end
    
    local payload = {
        content = message,
        username = assistantName,
        avatar_url = nil
    }
    
    local jsonPayload = textutils.serializeJSON(payload)
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "ComputerCraft/Assistant"
    }
    
    local response, err = http.post({
        url = webhookURL,
        body = jsonPayload,
        headers = headers,
        timeout = 10
    })
    
    if response then
        local responseCode = response.getResponseCode()
        local responseBody = response.readAll()
        response.close()
        
        if responseCode == 204 or responseCode == 200 then
            return true
        else
            print("Discord webhook failed with code: " .. responseCode)
            print("Response: " .. (responseBody or "empty"))
            return false, "Discord webhook failed with code: " .. responseCode
        end
    else
        print("Failed to send to Discord: " .. (err or "unknown error"))
        return false, err
    end
end

local function stripUnicode(s)
    return (tostring(s):gsub("[\128-\255]", ""))
end

local function sendMessage(message)
    message = stripUnicode(message)
    if chatBoxEnabled then
        chatBox.sendMessage(message, assistantName, "[]", "&b")
    end
    if discordEnabled then
        sendToDiscord(message)
    end
end

return {
    sendMessage = sendMessage,
}