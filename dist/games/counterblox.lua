return {
    buildId = [[610c86b0]],
    id = [[counterblox]],
    sources = {
        ["games/counterblox/Composition.lua"] = [[local Composition = {}

function Composition.bind(context)
    assert(type(context) == "table" and type(context.getAdapter) == "function")
    local function adapter()
        return context.getAdapter()
    end
    return {
        overlay = {
            getWeaponPreviewKey = function(state)
                local current = adapter()
                return current and current:weaponPreviewKey(state) or "counterblox-weapon-pending"
            end,
            getWeaponPreviewSubject = function(state)
                local current = adapter()
                return current and current:weaponPreviewSubject(state) or nil
            end,
            cycleGlove = function(direction)
                adapter():cycleGlove(direction)
            end,
            previousGlove = function()
                adapter():cycleGlove(-1)
            end,
            nextGlove = function()
                adapter():cycleGlove(1)
            end,
            cycleSkin = function(direction)
                adapter():cycleSkin(direction)
            end,
            previousSkin = function()
                adapter():cycleSkin(-1)
            end,
            nextSkin = function()
                adapter():cycleSkin(1)
            end,
            cycleCosmeticWeapon = function(direction)
                adapter():cycleCosmeticWeapon(direction)
            end,
            previousCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(-1)
            end,
            nextCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(1)
            end,
            resetSkin = function()
                adapter():resetSkin()
            end,
            resetGlove = function()
                adapter():resetGlove()
            end,
            setGloveWear = function(alpha)
                adapter():setGloveWear(alpha)
            end,
            setGloveColor = function(color)
                adapter():setGloveColor(color)
            end,
            setWear = function(alpha)
                adapter():setWear(alpha)
            end,
            toggleStatTrak = function()
                adapter():toggleStatTrak()
            end,
        },
    }
end

return Composition
]],
        ["games/counterblox/Presentation.lua"] = [[local Presentation = {}

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
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:section("Combat", "rage", "AIM", 64, true, 2)
    host:option("rage", 1, "silentAim", "Silent Aim")
    host:option("rage", 1, "wallbang", "Wallbang", "silentAim")
    host:option("rage", 2, "rapidFire", "Rapid Fire")
    host:option("rage", 3, "triggerBot", "Trigger Bot")
    host:option("rage", 3, "noSpread", "No Spread")
    host:option("rage", 4, "noRecoil", "No Recoil")
    host:option("rage", 4, "noWeaponSlow", "No Weapon Slow")

    host:section("Combat", "melee", "MELEE", 70, false, 2)
    host:option("melee", 1, "knifeAura", "Knife Aura")
    host:option("melee", 1, "microStep", "Micro Step", "knifeAura")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "spinBot", "Spin Bot")
    host:option("movement", 1, "bhop", "Bunny Hop")

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
    host:option("visuals", 4, "bombTimer", "Bomb Timer")
    host:option("visuals", 5, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
]],
    },
}
