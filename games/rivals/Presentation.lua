local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            views = {
                { id = "preview", label = "Preview" },
                { id = "colors", label = "ESP Colors" },
            },
            preview = { kind = "character" },
        })
    end
    host:aim()
    host:rate("aimSmoothness", "Aim Smoothness")
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        treatment = "style",
        options = {
            {
                label = "Classic",
                value = "limn",
                when = { worldRenderer = "limn" },
                patch = { { "worldRenderer", "limn" } },
            },
            {
                label = "Highlights",
                value = "native",
                when = { worldRenderer = "native" },
                patch = { { "worldRenderer", "native" } },
            },
        },
    })

    host:segmented("Combat", {
        id = "aimMode",
        label = "Aim Type",
        emphasis = "prominent",
        related = {
            { id = "humanAim", kind = "toggle", label = "Aim Assist", when = "camera" },
            {
                id = "aimAssistStrength",
                kind = "slider",
                label = "Strength",
                max = 100,
                min = 0,
                parent = "humanAim",
                step = 1,
                unit = "%",
                when = "camera",
            },
            {
                id = "flickProjectiles",
                kind = "toggle",
                label = "Flick Projectiles",
                when = "camera",
            },
        },
        options = {
            {
                label = "Off",
                value = "off",
                when = { silentAim = false, shotAim = false },
                patch = { { "silentAim", false }, { "shotAim", false } },
            },
            {
                label = "Camera",
                value = "camera",
                when = { silentAim = true, shotAim = false },
                patch = { { "shotAim", false }, { "silentAim", true } },
            },
            {
                label = "Silent",
                value = "silent",
                when = { shotAim = true },
                patch = { { "silentAim", false }, { "shotAim", true } },
            },
        },
    })

    host:section("Combat", "trigger", "Trigger Bot", 64)
    host:option("trigger", 1, "triggerBot", "Trigger Bot")
    if type(host.slider) == "function" then
        host:slider("trigger", "triggerDelay", "Delay", {
            min = 0,
            max = 250,
            step = 1,
            unit = "ms",
            parent = "triggerBot",
        })
    end
    host:option("trigger", 3, "quickReload", "Quick Reload")
    host:option("trigger", 4, "meleeReach", "Melee Reach")
    if type(host.slider) == "function" then
        host:slider("trigger", "meleeReachScale", "Reach", {
            min = 100,
            max = 300,
            step = 5,
            unit = "%",
            parent = "meleeReach",
        })
    end
    host:option("trigger", 5, "skipDeflect", "Katana Stop")
    host:option("trigger", 5, "autoDeflect", "Auto Katana")
    host:option("trigger", 6, "alwaysScoped", "Always Scoped")

    host:section("Rage", "rage", "RAGE", 70)
    host:option("rage", 1, "teleportBehind", "Warp")
    host:option("rage", 2, "rapidFire", "Rapid Fire")
    if type(host.slider) == "function" then
        host:slider("rage", "fireRate", "Fire Rate", {
            min = 100,
            max = 1000,
            step = 5,
            unit = "%",
            parent = "rapidFire",
        })
    end

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "bhop", "Bunny Hop")
    host:option("movement", 2, "infiniteJump", "Infinite Jump")
    host:option("movement", 3, "wallNoclip", "Wall Noclip")
    host:option("movement", 4, "redLightSafety", "Red Light Safety")

    host:section("Tools", "taskFarming", "TASK FARMING", 70)
    if type(host.keybind) == "function" then
        host:keybind("taskFarming", "taskAutomationEmergencyKey", "Emergency Stop", "End")
    end
    host:option("taskFarming", 1, "taskAutomationEnabled", "Task Farming")

    host:section("Tools", "world", "WORLD", 70)
    host:option("world", 1, "autoPickup", "Auto Pickup")

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "chamsExcludeAccessories", "Ignore Accessories", "chams", {
        setting = "worldRenderer",
        equals = "native",
    })
    host:option("visuals", 2, "chamsPerPart", "Part Highlights", "chams", {
        setting = "worldRenderer",
        equals = "native",
    })
    host:option("visuals", 3, "names", "Names")
    host:option("visuals", 3, "health", "Health")
    host:option("visuals", 4, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
    host:option("visuals", 4, "noFlash", "No Flash")
    host:option("visuals", 5, "noSmoke", "No Smoke")
    host:option("visuals", 6, "unlockAllSkins", "Unlock All Cosmetics")
    host:option("visuals", 7, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
