-- Graphical terminal module for Phoenix
if not PHOENIX_VERSION then error("This file must be loaded as a kernel module.") end

-- WARNING: Render crashes are lethal and will 100% kill the computer
local loadBDF = (function()
    -- require() this file, returns function to load from string
    -- characters will be located at font.chars[ch] in output
    -- bitmap rows may not be as wide as the entire character,
    --  but the bitmap will be the same height as the character

    local function string_split_word(text)
        local spat, epat, buf, quoted = [=[^(['"])]=], [=[(['"])$]=]
        local retval = {}
        for str in text:gmatch("%S+") do
            local squoted = str:match(spat)
            local equoted = str:match(epat)
            local escaped = str:match([=[(\*)['"]$]=])
            if squoted and not quoted and not equoted then
                buf, quoted = str, squoted
            elseif buf and equoted == quoted and #escaped % 2 == 0 then
                str, buf, quoted = buf .. ' ' .. str, nil, nil
            elseif buf then
                buf = buf .. ' ' .. str
            end
            if not buf then local a = str:gsub(spat,""):gsub(epat,"") table.insert(retval, a) end
        end
        return retval
    end

    local function foreach(func, ...)
        local retval = {}
        for k,v in pairs({...}) do retval[k] = func(v) end
        return table.unpack(retval)
    end

    local function parseValue(str) 
        local ok, res = pcall(load("return " .. string.gsub(str, "`", "")))
        if not ok then return str else return res end
    end

    local function parseLine(str)
        local tok = string_split_word(str)
        return table.remove(tok, 1), foreach(parseValue, table.unpack(tok))
    end

    local propertymap = {
        FOUNDRY = "foundry",
        FAMILY_NAME = "family",
        WEIGHT_NAME = "weight",
        SLANT = "slant",
        SETWIDTH_NAME = "weight_name",
        ADD_STYLE_NAME = "add_style_name",
        PIXEL_SIZE = "pixels",
        POINT_SIZE = "points",
        SPACING = "spacing",
        AVERAGE_WIDTH = "average_width",
        FONT_NAME = "name",
        FACE_NAME = "face_name",
        COPYRIGHT = "copyright",
        FONT_VERSION = "version",
        FONT_ASCENT = "ascent",
        FONT_DESCENT = "descent",
        UNDERLINE_POSITION = "underline_position",
        UNDERLINE_THICKNESS = "underline_thickness",
        X_HEIGHT = "height_x",
        CAP_HEIGHT = "height_cap",
        RAW_ASCENT = "raw_ascent",
        RAW_DESCENT = "raw_descent",
        NORM_SPACE = "normal_space",
        RELATIVE_WEIGHT = "relative_weight",
        RELATIVE_SETWIDTH = "relative_setwidth",
        FIGURE_WIDTH = "figure_width",
        AVG_LOWERCASE_WIDTH = "average_lower_width",
        AVG_UPPERCASE_WIDTH = "average_upper_width"
    }

    local function ffs(value)
        if value == 0 then return 0 end
        local pos = 0;
        while bit32.band(value, 1) == 0 do
            value = bit32.rshift(value, 1);
            pos = pos + 1
        end
        return pos
    end

    local function readBDFFont(str)
        local retval = {comments = {}, resolution = {}, superscript = {}, subscript = {}, charset = {}, chars = {}}
        local mode = 0
        local ch
        local charname
        local chl = 1
        for line in str:gmatch("[^\n]+") do
            local values = {parseLine(line)}
            local key = table.remove(values, 1)
            if mode == 0 then
                if (key ~= "STARTFONT" or values[1] ~= 2.1) then
                    error("Attempted to load invalid BDF font", 2)
                else mode = 1 end
            elseif mode == 1 then
                if key == "FONT" then retval.id = values[1]
                elseif key == "SIZE" then retval.size = {px = values[1], x_dpi = values[2], y_dpi = values[3]}
                elseif key == "FONTBOUNDINGBOX" then retval.bounds = {x = values[3], y = values[4], width = values[1], height = values[2]}
                elseif key == "COMMENT" then table.insert(retval.comments, values[1])
                elseif key == "ENDFONT" then return retval
                elseif key == "STARTCHAR" then 
                    mode = 3
                    charname = values[1]
                elseif key == "STARTPROPERTIES" then mode = 2 end
            elseif mode == 2 then
                if propertymap[key] ~= nil then retval[propertymap[key]] = values[1]
                elseif key == "RESOLUTION_X" then retval.resolution.x = values[1]
                elseif key == "RESOLUTION_Y" then retval.resolution.y = values[1]
                elseif key == "CHARSET_REGISTRY" then retval.charset.registry = values[1]
                elseif key == "CHARSET_ENCODING" then retval.charset.encoding = values[1]
                elseif key == "FONTNAME_REGISTRY" then retval.charset.fontname_registry = values[1]
                elseif key == "CHARSET_COLLECTIONS" then retval.charset.collections = string_split_word(values[1])
                elseif key == "SUPERSCRIPT_X" then retval.superscript.x = values[1]
                elseif key == "SUPERSCRIPT_Y" then retval.superscript.y = values[1]
                elseif key == "SUPERSCRIPT_SIZE" then retval.superscript.size = values[1]
                elseif key == "SUBSCRIPT_X" then retval.subscript.x = values[1]
                elseif key == "SUBSCRIPT_Y" then retval.subscript.y = values[1]
                elseif key == "SUBSCRIPT_SIZE" then retval.subscript.size = values[1]
                elseif key == "ENDPROPERTIES" then mode = 1 end
            elseif mode == 3 then
                if ch ~= nil then
                    if charname ~= nil then
                        retval.chars[ch].name = charname
                        charname = nil
                    end
                    if key == "SWIDTH" then retval.chars[ch].scalable_width = {x = values[1], y = values[2]}
                    elseif key == "DWIDTH" then retval.chars[ch].device_width = {x = values[1], y = values[2]}
                    elseif key == "BBX" then 
                        retval.chars[ch].bounds = {x = values[3], y = values[4], width = values[1], height = values[2]}
                        retval.chars[ch].bitmap = {}
                        for y = 1, values[2] do retval.chars[ch].bitmap[y] = {} end
                    elseif key == "BITMAP" then 
                        mode = 4 
                    end
                elseif key == "ENCODING" then 
                    ch = values[1] <= 255 and string.char(values[1]) or values[1]
                    retval.chars[ch] = {}
                end
            elseif mode == 4 then
                if key == "ENDCHAR" then 
                    ch = nil
                    chl = 1
                    mode = 1 
                else
                    local num = tonumber("0x" .. key)
                    --if type(num) ~= "number" then print("Bad number: 0x" .. num) end
                    local l = {}
                    local w = math.ceil(math.floor(math.log(num) / math.log(2)) / 8) * 8
                    for i = ffs(num) or 0, w do l[w-i+1] = bit32.band(bit32.rshift(num, i-1), 1) == 1 end
                    retval.chars[ch].bitmap[chl] = l
                    chl = chl + 1
                end
            end
        end
        return retval
    end

    return readBDFFont
end)()

if term.setGraphicsMode == nil then error("This requires CraftOS-PC v1.2 or later.") end

local font, gfxMode
local nativeTerm = term
local oldSetGfx, oldGetGfx = term.setGraphicsMode, term.getGraphicsMode
local nativeWidth, nativeHeight = term.getSize()
nativeWidth = nativeWidth * 6
nativeHeight = nativeHeight * 9

local function log2(num) return math.floor(math.log10(num) / math.log10(2)) end

local function drawChar(x, y, ch, fg, bg, transparent)
    x=x-1
    y=y-1
    if x * font.bounds.width > nativeWidth or y * font.bounds.height > nativeHeight or x < 0 or y < 0 then return end
    local fch = font.chars[ch]
    if fch == nil then fch = font.chars[' '] end
    if transparent then
        local heightDiff = (font.bounds.height + font.bounds.y) - fch.bounds.height + font.bounds.y - fch.bounds.y
        for i,t in pairs(fch.bitmap) do if i <= font.bounds.height then for j,a in pairs(t) do if j <= font.bounds.width and a then 
            nativeTerm.setPixel(x*font.bounds.width+j-1, y*font.bounds.height+i+heightDiff-1, gfxMode == 2 and fg or log2(fg))
        end end end end
    else
        local pixelTable = {}
        for i = 1, font.bounds.height do pixelTable[i] = string.char(bg):rep(font.bounds.width) end
        local starty = (font.bounds.height - fch.bounds.height) - fch.bounds.y + font.bounds.y
        for i = 1, fch.bounds.height do
            if fch.bitmap[i] then
                pixelTable[i+starty] = string.char(bg):rep(fch.bounds.x)
                for j = 1, font.bounds.width-fch.bounds.x do
                    pixelTable[i+starty] = pixelTable[i+starty] .. string.char(fch.bitmap[i][j] and fg or bg)
                end
            end
        end
        local ypos = y*font.bounds.height+font.bounds.y
        while ypos < 0 do
            table.remove(pixelTable, 1)
            ypos=ypos+1
        end
        nativeTerm.drawPixels(x*font.bounds.width, ypos, pixelTable)
    end
end

local file = filesystem.open(KERNEL, "/etc/termfont.bdf", "r")
if file == nil then error("Could not find font!") end
font = loadBDF(file.readAll())
file.close()

local backgroundColor = 15
local textColor = 0
local cursorX = 1
local cursorY = 1
local cursorBlink = true -- soon(tm)
local cursorShouldBlink = true
local cursorTimer = os.startTimer(0.4)
local width = math.floor(nativeWidth / font.bounds.width)
local height = math.floor(nativeHeight / font.bounds.height)
gfxMode = 0

local termBuffer = {}
local colorBuffer = {}
for i = 1, height do 
    termBuffer[i] = {}
    colorBuffer[i] = {}
    for j = 1, width do
        termBuffer[i][j] = " "
        colorBuffer[i][j] = {textColor, backgroundColor}
    end
end

local lastcx, lastcy = 1, 1
local function redrawCursor()
    if lastcx <= width and lastcy <= height then drawChar(lastcx, lastcy, termBuffer[lastcy][lastcx], colorBuffer[lastcy][lastcx][1], colorBuffer[lastcy][lastcx][2], false) end
    if cursorX <= width and cursorY <= height and cursorBlink and cursorShouldBlink then drawChar(cursorX, cursorY, '_', 0, 15, true) end
    lastcx, lastcy = cursorX, cursorY
end

local termObject = setmetatable({
    write = function(text)
        if cursorY > height or cursorX > width then return end
        for c in text:gmatch(".") do
            termBuffer[cursorY][cursorX] = c
            colorBuffer[cursorY][cursorX] = {textColor, backgroundColor}
            drawChar(cursorX, cursorY, c, textColor, backgroundColor, false)
            cursorX = cursorX + 1
            if cursorX > width then break end
        end
        redrawCursor()
    end,
    blit = function(text, fg, bg)
        if #text ~= #fg or #fg ~= #bg then error("Arguments must be same length", 2) end
        if cursorY > height or cursorX > width then return end
        for i = 1, #text do
            textColor = (("0123456789abcdef"):find(fg:sub(i, i)) or (textColor + 1)) - 1
            backgroundColor = (("0123456789abcdef"):find(bg:sub(i, i)) or (backgroundColor + 1)) - 1
            termBuffer[cursorY][cursorX] = text:sub(i, i)
            colorBuffer[cursorY][cursorX] = {textColor, backgroundColor}
            drawChar(cursorX, cursorY, text:sub(i, i), textColor, backgroundColor, false)
            cursorX = cursorX + 1
            if cursorX > width then break end
        end
        redrawCursor()
    end,
    clear = function()
        for i = 1, height do 
            termBuffer[i] = {}
            colorBuffer[i] = {}
            for j = 1, width do
                termBuffer[i][j] = " "
                colorBuffer[i][j] = {textColor, backgroundColor}
                drawChar(j, i, " ", textColor, backgroundColor, false)
            end
        end
        redrawCursor()
    end,
    clearLine = function()
        if cursorY > height then return end
        for j = 1, width do
            termBuffer[cursorY][j] = " "
            colorBuffer[cursorY][j] = {textColor, backgroundColor}
            drawChar(j, cursorY, " ", textColor, backgroundColor, false)
        end
        redrawCursor()
    end,
    getCursorPos = function() return cursorX, cursorY end,
    setCursorPos = function(x, y) cursorX, cursorY = x, y end,
    getCursorBlink = function() return cursorShouldBlink end,
    setCursorBlink = function(b) cursorShouldBlink = b; redrawCursor() end,
    isColor = function() return true end,
    isColour = function() return true end,
    getSize = function() return width, height end,
    scroll = function(n)
        for _ = 1, n do
            table.remove(termBuffer, 1)
            table.remove(colorBuffer, 1)
            local tr, cr = {}, {}
            for j = 1, width do
                tr[j] = " "
                cr[j] = {textColor, backgroundColor}
            end
            table.insert(termBuffer, tr)
            table.insert(colorBuffer, cr)
        end
        local screen = nativeTerm.getPixels(0, n * font.bounds.height, nativeWidth, nativeHeight - (n * font.bounds.height), true)
        nativeTerm.drawPixels(0, 0, screen)
        nativeTerm.drawPixels(0, nativeHeight - (n * font.bounds.height), 2^backgroundColor, nativeWidth, n * font.bounds.height)
        --for y = 1, height do for x = 1, width do drawChar(x, y, termBuffer[y][x], colorBuffer[y][x][1], colorBuffer[y][x][2], false) end end
        redrawCursor()
    end,
    setTextColor = function(c) textColor = log2(c) end,
    setTextColour = function(c) textColor = log2(c) end,
    getTextColor = function() return bit.blshift(1, textColor) end,
    getTextColour = function() return bit.blshift(1, textColor) end,
    setBackgroundColor = function(c) backgroundColor = log2(c) end,
    setBackgroundColour = function(c) backgroundColor = log2(c) end,
    getBackgroundColor = function() return bit.blshift(1, backgroundColor) end,
    getBackgroundColour = function() return bit.blshift(1, backgroundColor) end,
}, {__index = nativeTerm})

term.setGraphicsMode(1)
term.clear()
_G.term = termObject
for _, v in pairs(TTY) do v.term = term end
term.setGraphicsMode = function(mode)
    gfxMode = mode
    term.clear()
    if gfxMode == 2 then oldSetGfx(2) else oldSetGfx(1) end
    if gfxMode == 0 then for y = 1, height do for x = 1, width do drawChar(x, y, termBuffer[y][x], colorBuffer[y][x][1], colorBuffer[y][x][2], false) end end end
end
term.getGraphicsMode = function() return gfxMode end

eventHooks.term_resize[#eventHooks.term_resize+1] = function()
    local oldw, oldh = width, height
    nativeWidth, nativeHeight = nativeTerm.getSize()
    nativeWidth = nativeWidth * 6
    nativeHeight = nativeHeight * 9
    width = math.floor(nativeWidth / font.bounds.width)
    height = math.floor(nativeHeight / font.bounds.height)
    if height > oldh then
        for i = oldh+1, height do
            termBuffer[i] = {}
            colorBuffer[i] = {}
            for j = 1, oldw do
                termBuffer[i][j] = ' '
                colorBuffer[i][j] = {textColor, backgroundColor}
            end
        end
    elseif height < oldh then
        for i = height+1, oldh do
            termBuffer[i] = nil
            colorBuffer[i] = nil
        end
    end
    if width > oldw then
        for i = 1, height do for j = oldw+1, width do
            termBuffer[i][j] = ' '
            colorBuffer[i][j] = {textColor, backgroundColor}
        end end
    elseif width < oldw then
        for i = 1, height do for j = width+1, oldw do
            termBuffer[i][j] = nil
            colorBuffer[i][j] = nil
        end end
    end
end

eventHooks.timer[#eventHooks.timer+1] = function(ev)
    if ev[2] == cursorTimer then
        cursorBlink = not cursorBlink
        cursorTimer = os.startTimer(0.4)
        redrawCursor()
    end
end

for _, v in ipairs(TTY) do terminal.resize(v, width, height) end
terminal.redraw(currentTTY, true)
syslog.log({module = "gfxterm"}, "Successfully initialized graphics mode terminal")

return {
    unload = function()
        term.setGraphicsMode = oldSetGfx
        term.getGraphicsMode = oldGetGfx
        _G.term = nativeTerm
        term.setGraphicsMode(0)
    end
}