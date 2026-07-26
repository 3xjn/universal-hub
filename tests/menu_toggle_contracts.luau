local MenuToggle = require("../modules/MenuToggle")

Enum = {
    KeyCode = {
        RightShift = "RightShift",
        F = "F",
    },
}

local focusedTextBox
local userInputService = {
    GetFocusedTextBox = function()
        return focusedTextBox
    end,
}

local rightShift = { KeyCode = Enum.KeyCode.RightShift }

assert(
    MenuToggle.shouldToggle(rightShift, false, userInputService) == true,
    "RightShift should toggle the menu during normal gameplay"
)
assert(
    MenuToggle.shouldToggle({ KeyCode = Enum.KeyCode.F }, false, userInputService) == false,
    "Only RightShift should toggle the menu"
)
assert(
    MenuToggle.shouldToggle(rightShift, true, userInputService) == false,
    "Processed input should not toggle the menu"
)

focusedTextBox = {}
assert(
    MenuToggle.shouldToggle(rightShift, false, userInputService) == false,
    "RightShift must not toggle the menu while chat or another TextBox is focused"
)

print("menu-toggle-contracts-ok")
