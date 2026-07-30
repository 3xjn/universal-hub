local CopyPlan = require("../games/town/CopyPlan")

local function fixture(count, options)
    options = options or {}
    return {
        context = {
            destination = {
                ownerName = "Local",
                ownerUserId = 1,
                plotName = "LocalBuildArea",
            },
            gameId = 1718755273,
            localUserId = 1,
            placeId = 4991214437,
            source = {
                ownerName = "Source",
                ownerUserId = 2,
                plotName = "SourceBuildArea",
            },
        },
        groups = options.groups or {},
        baseParts = count + (options.unsupported or 0),
        totalDescendants = count + (options.unsupported or 0) + (options.nonParts or 0),
        iterParts = function(emit)
            for index = 1, count do
                emit({
                    className = options.className or "Part",
                    id = ("part-%06d"):format(index),
                    markerBearing = index <= (options.markerBearing or 0),
                    operations = { "resize" },
                    type = options.partType or "Normal",
                })
            end
        end,
        unsupported = options.unsupported or 0,
        unsupportedClasses = options.unsupportedClasses or {},
    }
end

local function compile(count, options)
    local chunkSizes = {}
    local plan = CopyPlan.compile(fixture(count, options), {
        onChunk = function(chunk)
            table.insert(chunkSizes, #chunk.records)
        end,
    })
    local maximumChunk = 0
    for _, size in ipairs(chunkSizes) do
        maximumChunk = math.max(maximumChunk, size)
    end
    return plan, maximumChunk
end

for _, count in ipairs({ 2000, 2001, 18791, 25000 }) do
    local plan, maximumChunk = compile(count)
    assert(plan.supported == count, ("Town plan must retain all %d supported parts"):format(count))
    assert(plan.truncated == nil, "Town plan must never expose a truncated successful plan")
    assert(maximumChunk <= 256 and plan.peakBuffer <= 256, "Town planning buffers must stay bounded")
end

local large = compile(18791)
assert(large.work.seeds == 1)
assert(large.work.cloneCalls == 45)
assert(large.work.phases.resize.records == 18791)
assert(large.work.phases.resize.batches == 147)
assert(large.requestSizing.clone == 513)
assert(large.requestSizing.preferredBatch == 128)
assert(large.requestSizing.provenApiLimits == false)
assert(large.totalDescendants == 18791 and large.baseParts == 18791)

local marked = compile(10, {
    markerBearing = 4,
    nonParts = 7,
    unsupported = 2,
})
assert(marked.totalDescendants == 19 and marked.baseParts == 12 and marked.markerBearing == 4)

local mixed = CopyPlan.compile({
    context = fixture(1).context,
    groups = {
        { id = "group-1", name = "Model", partIds = { "part-1" } },
    },
    parts = {
        { className = "Part", id = "part-1", operations = { "resize", "color" }, type = "Normal" },
        { className = "WedgePart", id = "part-2", operations = { "resize" }, type = "Wedge" },
        { className = "Seat", id = "part-3", operations = { "resize" }, type = "Seat" },
    },
    unsupported = 2,
    unsupportedClasses = { MeshPart = 2 },
})
assert(mixed.supported == 3 and mixed.unsupported == 2)
assert(mixed.supportedClasses.Part == 1)
assert(mixed.supportedClasses.WedgePart == 1)
assert(mixed.supportedClasses.Seat == 1)
assert(mixed.groups == 1)
assert(mixed.work.phases.color.records == 1)

local sameMixed = CopyPlan.compile({
    context = fixture(1).context,
    groups = {
        { name = "Model", partIds = { "part-1" }, id = "group-1" },
    },
    parts = {
        { operations = { "resize", "color" }, type = "Normal", id = "part-1", className = "Part" },
        { operations = { "resize" }, type = "Wedge", id = "part-2", className = "WedgePart" },
        { operations = { "resize" }, type = "Seat", id = "part-3", className = "Seat" },
    },
    unsupportedClasses = { MeshPart = 2 },
    unsupported = 2,
})
assert(mixed.fingerprint == sameMixed.fingerprint, "Plan fingerprints must be deterministic")

for _, forbidden in ipairs({
    { maxParts = 2000 },
    { limit = 2000 },
}) do
    local succeeded = pcall(CopyPlan.compile, fixture(10), forbidden)
    assert(not succeeded, "CopyPlan must reject cap/truncation options")
end

print("town-copy-plan-contracts-ok")
