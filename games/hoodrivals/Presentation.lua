local Presentation = {}

function Presentation.mount(host)
    host:aim()
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:section("Combat", "aim", "AIM", 64)
    host:option("aim", 1, "silentAim", "Silent Aim")
    host:option("aim", 2, "triggerBot", "Trigger Bot")
    host:option("aim", 3, "rapidFire", "Rapid Fire")
    host:option("aim", 4, "autoReload", "Auto Reload")
    host:option("aim", 5, "fastReload", "Fast Reload")
    if type(host.slider) == "function" then
        host:slider("aim", "rapidFireDelay", "Delay", {
            min = 10,
            max = 200,
            step = 5,
            unit = "ms",
            parent = "rapidFire",
        })
    end

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
end

return Presentation
