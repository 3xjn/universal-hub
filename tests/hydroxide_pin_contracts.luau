local fs = require("@lune/fs")
local process = require("@lune/process")

local oldPath = assert(process.env.OLD_TARGETING_PATH, "OLD_TARGETING_PATH is required")
local newPath = assert(process.env.NEW_TARGETING_PATH, "NEW_TARGETING_PATH is required")
local oldSource = fs.readFile(oldPath)
local newSource = fs.readFile(newPath)

local function replaceOnce(source, needle, replacement)
    local first, last = source:find(needle, 1, true)
    assert(first, "Published Targeting delta is missing an expected seam")
    assert(not source:find(needle, last + 1, true), "Published Targeting delta duplicated an expected seam")
    return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local ignoreHelper = [[local function getRaycastIgnore(localPlayer, options)
    local ignored = {}
    local seen = {}

    local function add(instance)
        if instance and not seen[instance] then
            seen[instance] = true
            table.insert(ignored, instance)
        end
    end

    add(localPlayer.Character)
    if options and options.raycastIgnore then
        for _index, instance in pairs(options.raycastIgnore) do
            add(instance)
        end
    end

    return ignored
end

]]

assert(not oldSource:find("getRaycastIgnore", 1, true))
assert(not oldSource:find("options.raycastIgnore", 1, true))
assert(newSource:find(ignoreHelper, 1, true), "New immutable pin must merge caller raycast exclusions")

local normalized = replaceOnce(newSource, ignoreHelper, "")
normalized = replaceOnce(
    normalized,
    "local function getVisibleAim(localPlayer, character, options)",
    "local function getVisibleAim(localPlayer, character)"
)
normalized = replaceOnce(
    normalized,
    "raycastParams.FilterDescendantsInstances = getRaycastIgnore(localPlayer, options)",
    "raycastParams.FilterDescendantsInstances = localPlayer.Character and { localPlayer.Character } or {}"
)
normalized = replaceOnce(
    normalized,
    "local aim, bodyParts = getVisibleAim(localPlayer, character, options)",
    "local aim, bodyParts = getVisibleAim(localPlayer, character)"
)
assert(
    normalized == oldSource,
    "Published Targeting pin must change only raycastIgnore merge and option threading"
)

local nearestObservation = assert(
    newSource:match("function targeting%.nearestObservation.-\n    end"),
    "Published Targeting must retain nearestObservation"
)
assert(
    not nearestObservation:find("Raycast", 1, true)
        and not nearestObservation:find("GetVisibleAim", 1, true),
    "nearestObservation must remain a selection-only no-raycast path"
)

local hubSource = fs.readFile("hub.lua")
assert(hubSource:find("cb1e184c27ffc7639b26cefd55e7f25978b9dcf7", 1, true))
assert(not hubSource:find("8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7", 1, true))
for _, forbidden in ipairs({
    "modules/Drawing.lua",
    "modules/DrawingControls.lua",
    "modules/Remote.lua",
    "hydroxide/init.lua",
}) do
    assert(not hubSource:find(forbidden, 1, true), "Hydroxide pin must not expand into " .. forbidden)
end

print("hydroxide-pin-source-contracts-ok")
