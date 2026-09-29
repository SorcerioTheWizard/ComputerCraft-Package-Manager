-- CCPM UI
--
-- Prints colored messages and asks questions, with a capture mode so specs can check what the user would see.

-- MARK: Constants
local YES_ANSWERS = { y = true, yes = true }
local NO_ANSWERS = { n = true, no = true }

-- MARK: State
---@type { lines: { text: string, kind: string }[], answer: boolean }|nil
local capture = nil

-- MARK: Private Functions
--- Prints a line in a color when the screen supports it.
---@param text string The text.
---@param kind string What kind of message it is, which picks the color.
local function emit(text, kind)
    if capture then
        capture.lines[#capture.lines + 1] = { text = text, kind = kind }
        return
    end

    -- Pick a color the screen can show
    local colorsByKind = { info = colors.white, success = colors.green, warn = colors.yellow, error = colors.red, muted = colors.lightGray }
    local color = colorsByKind[kind] or colors.white
    if not term.isColor() and color ~= colors.white and color ~= colors.lightGray then
        color = colors.white
    end

    -- Print it
    local previous = term.getTextColor()
    term.setTextColor(color)
    print(text)
    term.setTextColor(previous)
end

-- MARK: Functions
local ui = {}

--- Prints a normal message.
---@param text string The message.
function ui.info(text)
    emit(text, "info")
end

--- Prints a message about something that worked.
---@param text string The message.
function ui.success(text)
    emit(text, "success")
end

--- Prints a warning.
---@param text string The message.
function ui.warn(text)
    emit(text, "warn")
end

--- Prints an error.
---@param text string The message.
function ui.error(text)
    emit(text, "error")
end

--- Prints a less important message.
---@param text string The message.
function ui.muted(text)
    emit(text, "muted")
end

--- Prints many lines, pausing each screenful so none scroll away.
---@param lines string[] The lines.
function ui.page(lines)
    if capture then
        for _, line in ipairs(lines) do
            emit(line, "info")
        end
        return
    end

    textutils.pagedPrint(table.concat(lines, "\n"))
end

--- Asks a yes or no question.
---@param question string The question, without the `[Y/n]` hint.
---@return boolean yes If the user answered yes.
function ui.confirm(question)
    if capture then
        emit(question .. " [Y/n] " .. (capture.answer and "y" or "n"), "info")
        return capture.answer
    end

    -- Ask until the answer is clear, treating an empty answer as yes
    while true do
        write(question .. " [Y/n] ")
        local answer = (read() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if answer == "" or YES_ANSWERS[answer] then
            return true
        elseif NO_ANSWERS[answer] then
            return false
        end
    end
end

--- Starts capturing output instead of printing it, for specs.
---@param answer boolean|nil How to answer questions, defaulting to yes.
function ui.startCapture(answer)
    capture = { lines = {}, answer = answer ~= false }
end

--- Stops capturing output.
---@return { text: string, kind: string }[] lines The captured lines.
function ui.stopCapture()
    local lines = capture and capture.lines or {}
    capture = nil

    return lines
end

return ui
