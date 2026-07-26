local MenuToggle = {}

function MenuToggle.shouldToggle(input, gameProcessedEvent, userInputService)
    if not input or input.KeyCode ~= Enum.KeyCode.RightShift or gameProcessedEvent then
        return false
    end

    return not (
        userInputService
        and type(userInputService.GetFocusedTextBox) == "function"
        and userInputService:GetFocusedTextBox()
    )
end

return MenuToggle
