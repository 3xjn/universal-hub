local HttpService = game:GetService("HttpService")
local requestFunction = assert(request, "Universal Hub requires request")
local response = requestFunction({
    Url = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/loader.lua?cacheBust="
        .. HttpService:GenerateGUID(false),
    Method = "GET",
    Headers = {
        ["Cache-Control"] = "no-cache",
    },
})
local status = response.StatusCode or response.Status
assert(
    type(response.Body) == "string"
        and response.Success ~= false
        and (status == nil or status == 200),
    ("Universal Hub loader request failed (%s)"):format(tostring(status or "unknown"))
)
local chunk, compileError = loadstring(response.Body, "universal-hub/loader.lua")
return assert(chunk, compileError)()
