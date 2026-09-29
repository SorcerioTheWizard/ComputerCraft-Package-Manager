-- CCPM UI
--
-- Prints colored, word wrapped, and paged text and asks questions, with a capture mode so specs can check what the user would see.

-- Internal to CCPM: this module knows nothing about packages, so it can be split into its own package later.

-- MARK: Constants
local YES_ANSWERS = { y = true, yes = true }
local NO_ANSWERS = { n = true, no = true }
local MORE_PROMPT = "Press any key for more"
local CAPTURE_WIDTH = 1000
local MIN_WRAP_WIDTH = 16

-- Colors for each role, on advanced computers and on standard computers, which only show grays
local ROLES = {
    text = { colors.white, colors.white },
    name = { colors.yellow, colors.white },
    dim = { colors.lightGray, colors.lightGray },
    faint = { colors.gray, colors.gray },
    good = { colors.lime, colors.white },
    bad = { colors.red, colors.white },
    caution = { colors.orange, colors.white },
}

-- MARK: Types
---@alias Role "text"|"name"|"dim"|"faint"|"good"|"bad"|"caution"

---@alias Segment { [1]: string, [2]: Role|nil }

-- MARK: State
---@type { lines: { text: string }[], answer: boolean, width: integer }|nil
local capture = nil

-- Lines printed since the pager last paused, or `nil` when not paging
---@type integer|nil
local pagedLines = nil

-- MARK: Private Functions
--- Gets how many characters fit on a line.
---@return integer width The width.
local function screenWidth()
    if capture then
        return capture.width
    end

    return (term.getSize())
end

--- Picks the color of a role that the screen can show.
---@param role Role The role.
---@return integer color The color.
local function colorOf(role)
    local choices = ROLES[role] or ROLES.text
    return term.isColor() and choices[1] or choices[2]
end

--- Pauses before a line that would scroll unread text off the screen.
local function pageBreak()
    if not pagedLines then
        return
    end

    local _, height = term.getSize()
    if pagedLines < height - 1 then
        return
    end

    -- Wait for a key, then remove the prompt
    local previous = term.getTextColor()
    term.setTextColor(colorOf("dim"))
    write(MORE_PROMPT)
    term.setTextColor(previous)
    os.pullEvent("key")
    local _, y = term.getCursorPos()
    term.clearLine()
    term.setCursorPos(1, y)
    pagedLines = 0
end

--- Prints one line made of colored runs.
---@param runs Segment[] The runs.
local function emit(runs)
    if capture then
        local parts = {}
        for i, run in ipairs(runs) do
            parts[i] = run[1]
        end
        capture.lines[#capture.lines + 1] = { text = table.concat(parts) }
        return
    end

    -- Write each run in its color
    pageBreak()
    local previous = term.getTextColor()
    for _, run in ipairs(runs) do
        term.setTextColor(colorOf(run[2] or "text"))
        write(run[1])
    end
    term.setTextColor(previous)
    print()
    if pagedLines then
        pagedLines = pagedLines + 1
    end
end

--- Splits segments into words and the spaces between them, keeping each piece's role.
---@param segments Segment[] The segments.
---@return { text: string, role: Role, space: boolean }[] tokens The pieces in order.
local function tokenize(segments)
    local tokens = {}
    for _, segment in ipairs(segments) do
        local role = segment[2] or "text"
        for space, word in segment[1]:gmatch("(%s*)(%S*)") do
            if space ~= "" then
                tokens[#tokens + 1] = { text = space, role = role, space = true }
            end
            if word ~= "" then
                tokens[#tokens + 1] = { text = word, role = role, space = false }
            end
        end
    end

    return tokens
end

-- MARK: Functions
local ui = {}

--- Prints colored text, wrapping it at word boundaries with an indent on every line after the first.
---@param segments Segment[] The text, as `{ text, role }` pairs.
---@param indent integer|nil How far to indent wrapped lines, defaulting to none.
---@param maxLines integer|nil The most lines to print, ending the last one with `...` when text is cut off.
function ui.line(segments, indent, maxLines)
    indent = indent or 0
    local width = screenWidth()
    local lines = {}
    local runs, used, hasWord, pendingSpace = {}, 0, false, nil

    -- Start a wrapped line at the indent
    local function wrapLine()
        lines[#lines + 1] = runs
        runs = { { string.rep(" ", indent) } }
        used, hasWord, pendingSpace = indent, false, nil
    end

    for _, token in ipairs(tokenize(segments)) do
        if token.space then
            -- Keep leading spaces on the first line, and hold others until a word follows
            if used == 0 and not hasWord and #runs == 0 then
                runs[#runs + 1] = { token.text, token.role }
                used = used + #token.text
            else
                pendingSpace = token
            end
        else
            -- Wrap before a word that does not fit, unless it could never fit and there is room to start splitting it here
            local spaceWidth = pendingSpace and #pendingSpace.text or 0
            local fits = used + spaceWidth + #token.text <= width
            local splitsHere = #token.text > width - indent and used + spaceWidth < width
            if hasWord and not fits and not splitsHere then
                wrapLine()
                spaceWidth = 0
                pendingSpace = nil
            end
            if pendingSpace then
                runs[#runs + 1] = { pendingSpace.text, pendingSpace.role }
                used = used + spaceWidth
                pendingSpace = nil
            end

            -- Split words longer than a whole line
            local text = token.text
            while used + #text > width and width - used > 0 do
                runs[#runs + 1] = { text:sub(1, width - used), token.role }
                text = text:sub(width - used + 1)
                wrapLine()
            end
            runs[#runs + 1] = { text, token.role }
            used = used + #text
            hasWord = true
        end
    end
    lines[#lines + 1] = runs

    -- Cut off extra lines, marking the last one kept
    if maxLines and #lines > maxLines then
        lines = { table.unpack(lines, 1, maxLines) }
        local last = lines[maxLines]
        local length = 0
        for _, run in ipairs(last) do
            length = length + #run[1]
        end
        local tail = last[#last]
        local keep = math.max(#tail[1] - math.max(length + 3 - width, 0), 0)
        last[#last] = { tail[1]:sub(1, keep):gsub("%s+$", "") .. "...", tail[2] }
    end
    for _, line in ipairs(lines) do
        emit(line)
    end
end

--- Prints plain text in one role, wrapping it.
---@param text string The text.
---@param role Role|nil The role, defaulting to plain text.
---@param indent integer|nil How far to indent wrapped lines.
function ui.say(text, role, indent)
    ui.line({ { text, role } }, indent)
end

--- Prints an empty line.
function ui.blank()
    emit({})
end

--- Prints a message about something that worked.
---@param text string The message.
function ui.success(text)
    ui.say(text, "good")
end

--- Prints a warning, labeled so it reads on screens without color.
---@param text string The message.
function ui.warn(text)
    ui.line({ { "Warning: ", "caution" }, { text } }, 2)
end

--- Prints an error, labeled so it reads on screens without color.
---@param text string The message.
function ui.error(text)
    ui.line({ { "Error: ", "bad" }, { text } }, 2)
end

--- Prints less important text.
---@param text string The text.
function ui.note(text)
    ui.say(text, "dim")
end

--- Prints rows as aligned columns; the last column wraps under itself.
---@param rows Segment[][] The rows, each a list of cells.
---@param indent integer|nil How far to indent every row.
function ui.table(rows, indent)
    indent = indent or 0

    -- Size every column but the last to its widest cell
    local widths = {}
    for _, row in ipairs(rows) do
        for column = 1, #row - 1 do
            widths[column] = math.max(widths[column] or 0, #row[column][1])
        end
    end

    -- Print each row with padded cells
    for _, row in ipairs(rows) do
        local segments = { { string.rep(" ", indent) } }
        local offset = indent
        for column, cell in ipairs(row) do
            segments[#segments + 1] = cell
            if column < #row then
                local padding = widths[column] - #cell[1] + 2
                segments[#segments + 1] = { string.rep(" ", padding) }
                offset = offset + widths[column] + 2
            end
        end
        -- Fall back to a short indent when the last column would start too far right to be readable
        ui.line(segments, offset <= screenWidth() - MIN_WRAP_WIDTH and offset or indent + 2)
    end
end

--- Runs a function whose output pauses at every screenful, like a pager.
---@param fn function The function printing the output.
function ui.paged(fn)
    local previous = pagedLines
    pagedLines = 0
    local ok, err = pcall(fn)
    pagedLines = previous
    if not ok then
        error(err, 0)
    end
end

--- Asks a yes or no question.
---@param question string The question, without the `[Y/n]` hint.
---@return boolean yes If the user answered yes.
function ui.confirm(question)
    if capture then
        emit({ { question .. " [Y/n] " .. (capture.answer and "y" or "n") } })
        return capture.answer
    end

    -- Ask until the answer is clear, treating an empty answer as yes
    while true do
        local previous = term.getTextColor()
        term.setTextColor(colorOf("text"))
        write(question .. " ")
        term.setTextColor(colorOf("dim"))
        write("[Y/n] ")
        term.setTextColor(previous)
        local answer = (read() or ""):lower():match("^%s*(.-)%s*$")
        if pagedLines then
            pagedLines = 0
        end
        if answer == "" or YES_ANSWERS[answer] then
            return true
        elseif NO_ANSWERS[answer] then
            return false
        end
    end
end

--- Starts capturing output instead of printing it, for specs.
---@param answer boolean|nil How to answer questions, defaulting to yes.
---@param width integer|nil How wide lines may be before wrapping, defaulting to wide enough never to wrap.
function ui.startCapture(answer, width)
    capture = { lines = {}, answer = answer ~= false, width = width or CAPTURE_WIDTH }
end

--- Stops capturing output.
---@return { text: string }[] lines The captured lines.
function ui.stopCapture()
    local lines = capture and capture.lines or {}
    capture = nil

    return lines
end

return ui
