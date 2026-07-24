local Store = require("../modules/Store")

local store = Store.new({
    settings = {
        enabled = false,
        fov = 100,
    },
    status = "loading",
})
local emissions = {}
local unsubscribe = store:Subscribe(function(state)
    table.insert(emissions, {
        enabled = state.settings.enabled,
        status = state.status,
    })
end)

store:Patch({
    settings = {
        enabled = true,
    },
    status = "ready",
})

assert(store:Get().settings.enabled == true)
assert(store:Get().settings.fov == 100, "Nested patches must retain unrelated settings")
assert(#emissions == 2 and emissions[2].status == "ready")

unsubscribe()
store:Patch({ status = "ignored by old subscriber" })
assert(#emissions == 2, "Unsubscribed listeners must not receive updates")

store:Destroy()
store:Patch({ status = "stopped" })
assert(store:Get().status == "ignored by old subscriber", "Destroyed stores must reject patches")
print("store-contracts-ok")
