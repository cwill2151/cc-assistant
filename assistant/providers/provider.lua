local provider = {}
provider.__index = provider

function provider.new(config, model, apiKey, apiUrl)
    local self = setmetatable({}, provider)
    self.config = config
    self.model = model
    self.apiKey = apiKey
    self.apiUrl = apiUrl
    return self
end

function provider:sendRequest(requestParams)
    error("sendRequest not implemented for this provider.")
end

return provider