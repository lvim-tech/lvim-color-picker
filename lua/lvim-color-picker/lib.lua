-- lvim-color-picker.lib: the pure parse / convert / format core — the foundation all three tools
-- (picker, converter, highlighter) build on. No editor state, no side effects: colors are plain
-- `{ r, g, b, a }` tables (r/g/b in 0..255, a in 0..1 or nil), and every function is a total
-- function of its arguments, so the whole module is unit-testable headless. RGB⇄HSL round-trips
-- through the standard formulas; formatting emits each supported syntax, preserving alpha when set.
--
---@module "lvim-color-picker.lib"

local M = {}

---@class LvimColor
---@field r integer  0..255
---@field g integer  0..255
---@field b integer  0..255
---@field a number?  0..1 (nil = opaque, no alpha channel)

-- ── clamps / rounding ──────────────────────────────────────────────────────--

---@param x number
---@param lo number
---@param hi number
---@return number
local function clamp(x, lo, hi)
    if x < lo then
        return lo
    end
    if x > hi then
        return hi
    end
    return x
end

---@param x number
---@return integer
local function round(x)
    return math.floor(x + 0.5)
end

-- ── RGB ⇄ HSL ──────────────────────────────────────────────────────────────--

--- Convert RGB (0..255) to HSL — h in 0..360, s/l in 0..1.
---@param r integer
---@param g integer
---@param b integer
---@return number, number, number
function M.rgb_to_hsl(r, g, b)
    local rf, gf, bf = r / 255, g / 255, b / 255
    local max, min = math.max(rf, gf, bf), math.min(rf, gf, bf)
    local h, s, l = 0, 0, (max + min) / 2
    local d = max - min
    if d ~= 0 then
        s = d / (1 - math.abs(2 * l - 1))
        if max == rf then
            h = ((gf - bf) / d) % 6
        elseif max == gf then
            h = (bf - rf) / d + 2
        else
            h = (rf - gf) / d + 4
        end
        h = h * 60
    end
    if h < 0 then
        h = h + 360
    end
    return h, s, l
end

--- Convert HSL (h 0..360, s/l 0..1) to RGB (0..255).
---@param h number
---@param s number
---@param l number
---@return integer, integer, integer
function M.hsl_to_rgb(h, s, l)
    h = h % 360
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = l - c / 2
    local rf, gf, bf = 0, 0, 0
    if h < 60 then
        rf, gf, bf = c, x, 0
    elseif h < 120 then
        rf, gf, bf = x, c, 0
    elseif h < 180 then
        rf, gf, bf = 0, c, x
    elseif h < 240 then
        rf, gf, bf = 0, x, c
    elseif h < 300 then
        rf, gf, bf = x, 0, c
    else
        rf, gf, bf = c, 0, x
    end
    return round((rf + m) * 255), round((gf + m) * 255), round((bf + m) * 255)
end

--- Perceptual luminance (0..1) of a color — used to pick a readable fg over a swatch.
---@param color LvimColor
---@return number
function M.luminance(color)
    return (0.299 * color.r + 0.587 * color.g + 0.114 * color.b) / 255
end

-- ── RGB ⇄ CMYK ─────────────────────────────────────────────────────────────--

--- Convert RGB (0..255) to CMYK, each channel 0..1.
---@param r integer
---@param g integer
---@param b integer
---@return number, number, number, number
function M.rgb_to_cmyk(r, g, b)
    local rf, gf, bf = r / 255, g / 255, b / 255
    local k = 1 - math.max(rf, gf, bf)
    if k >= 1 then
        return 0, 0, 0, 1
    end
    return (1 - rf - k) / (1 - k), (1 - gf - k) / (1 - k), (1 - bf - k) / (1 - k), k
end

--- Convert CMYK (each 0..1) to RGB (0..255).
---@param c number
---@param m number
---@param y number
---@param k number
---@return integer, integer, integer
function M.cmyk_to_rgb(c, m, y, k)
    return round(255 * (1 - c) * (1 - k)), round(255 * (1 - m) * (1 - k)), round(255 * (1 - y) * (1 - k))
end

-- ── format ──────────────────────────────────────────────────────────────────

--- Format a color into one of the supported syntaxes: "hex" (#rrggbb / #rrggbbaa),
--- "rgb" (rgb()/rgba()), "hsl" (hsl()/hsla()). Alpha is emitted only when present.
---@param color LvimColor
---@param syntax "hex"|"rgb"|"hsl"|"cmyk"
---@return string
function M.format(color, syntax)
    local r = round(clamp(color.r, 0, 255))
    local g = round(clamp(color.g, 0, 255))
    local b = round(clamp(color.b, 0, 255))
    local a = color.a
    if syntax == "rgb" then
        if a then
            return ("rgba(%d, %d, %d, %s)"):format(r, g, b, ("%.2f"):format(a):gsub("%.?0+$", ""))
        end
        return ("rgb(%d, %d, %d)"):format(r, g, b)
    elseif syntax == "hsl" then
        local h, s, l = M.rgb_to_hsl(r, g, b)
        if a then
            return ("hsla(%d, %d%%, %d%%, %s)"):format(
                round(h),
                round(s * 100),
                round(l * 100),
                ("%.2f"):format(a):gsub("%.?0+$", "")
            )
        end
        return ("hsl(%d, %d%%, %d%%)"):format(round(h), round(s * 100), round(l * 100))
    elseif syntax == "cmyk" then
        -- CMYK is a subtractive, alpha-less model — the alpha channel is dropped
        local c, m, y, k = M.rgb_to_cmyk(r, g, b)
        return ("cmyk(%d%%, %d%%, %d%%, %d%%)"):format(round(c * 100), round(m * 100), round(y * 100), round(k * 100))
    end
    -- hex
    if a then
        return ("#%02x%02x%02x%02x"):format(r, g, b, round(clamp(a, 0, 1) * 255))
    end
    return ("#%02x%02x%02x"):format(r, g, b)
end

-- ── parse ────────────────────────────────────────────────────────────────────

--- Parse a hex body (without `#`/`0x`): 3, 4, 6 or 8 hex digits → color, or nil.
---@param hex string
---@return LvimColor|nil
local function parse_hex_body(hex)
    local n = #hex
    if not hex:match("^%x+$") then
        return nil
    end
    if n == 3 or n == 4 then
        local r = tonumber(hex:sub(1, 1):rep(2), 16)
        local g = tonumber(hex:sub(2, 2):rep(2), 16)
        local b = tonumber(hex:sub(3, 3):rep(2), 16)
        local a = n == 4 and tonumber(hex:sub(4, 4):rep(2), 16) / 255 or nil
        return { r = r, g = g, b = b, a = a }
    elseif n == 6 or n == 8 then
        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        local a = n == 8 and tonumber(hex:sub(7, 8), 16) / 255 or nil
        return { r = r, g = g, b = b, a = a }
    end
    return nil
end

--- Split the inside of a `func(...)` on commas or whitespace, trimmed.
---@param body string
---@return string[]
local function split_args(body)
    local out = {}
    for tok in body:gmatch("[^,%s]+") do
        out[#out + 1] = tok
    end
    return out
end

--- Parse the argument list of an rgb()/rgba() into a color, or nil.
---@param body string
---@return LvimColor|nil
local function parse_rgb_body(body)
    local a = split_args(body)
    if #a < 3 then
        return nil
    end
    local r, g, b = tonumber(a[1]), tonumber(a[2]), tonumber(a[3])
    if not (r and g and b) then
        return nil
    end
    return {
        r = round(clamp(r, 0, 255)),
        g = round(clamp(g, 0, 255)),
        b = round(clamp(b, 0, 255)),
        a = a[4] and tonumber((a[4]:gsub("%%", ""))),
    }
end

--- Parse the argument list of an hsl()/hsla() into a color, or nil.
---@param body string
---@return LvimColor|nil
local function parse_hsl_body(body)
    local a = split_args(body)
    if #a < 3 then
        return nil
    end
    local h = tonumber((a[1]:gsub("deg", "")))
    local s = tonumber((a[2]:gsub("%%", "")))
    local l = tonumber((a[3]:gsub("%%", "")))
    if not (h and s and l) then
        return nil
    end
    local r, g, b = M.hsl_to_rgb(h, s / 100, l / 100)
    return { r = r, g = g, b = b, a = a[4] and tonumber((a[4]:gsub("%%", ""))) }
end

--- Parse the argument list of a cmyk() into a color, or nil (CMYK carries no alpha).
---@param body string
---@return LvimColor|nil
local function parse_cmyk_body(body)
    local a = split_args(body)
    if #a < 4 then
        return nil
    end
    local c = tonumber((a[1]:gsub("%%", "")))
    local m = tonumber((a[2]:gsub("%%", "")))
    local y = tonumber((a[3]:gsub("%%", "")))
    local k = tonumber((a[4]:gsub("%%", "")))
    if not (c and m and y and k) then
        return nil
    end
    local r, g, b = M.cmyk_to_rgb(c / 100, m / 100, y / 100, k / 100)
    return { r = r, g = g, b = b }
end

--- Every color occurrence in `line`, as `{ color, s, e }` with 0-based byte span [s, e). Named
--- colors are matched only when `named` is true (they collide with ordinary words). Overlapping
--- matches keep the earliest, longest.
---@param line string
---@param named? boolean
---@return { color: LvimColor, s: integer, e: integer }[]
function M.parse_all(line, named)
    local hits = {}
    local function add(s1, e1, color)
        if color then
            hits[#hits + 1] = { color = color, s = s1 - 1, e = e1 }
        end
    end
    -- #hex (8/6/4/3), longest first via a greedy run then validate
    do
        local init = 1
        while true do
            local s1, e1, body = line:find("#(%x+)", init)
            if not s1 then
                break
            end
            local take = #body
            take = (take >= 8 and 8) or (take >= 6 and 6) or (take >= 4 and 4) or (take >= 3 and 3) or 0
            if take > 0 then
                add(s1, s1 + take, parse_hex_body(body:sub(1, take)))
            end
            init = e1 + 1
        end
    end
    -- 0xRRGGBB
    do
        local init = 1
        while true do
            local s1, e1, body = line:find("0x(%x%x%x%x%x%x)", init)
            if not s1 then
                break
            end
            add(s1, e1, parse_hex_body(body))
            init = e1 + 1
        end
    end
    -- rgb()/rgba() and hsl()/hsla()
    for _, spec in ipairs({
        { "rgba?%b()", parse_rgb_body },
        { "hsla?%b()", parse_hsl_body },
        { "cmyk%b()", parse_cmyk_body },
    }) do
        local init = 1
        while true do
            local s1, e1 = line:find(spec[1], init)
            if not s1 then
                break
            end
            local whole = line:sub(s1, e1)
            add(s1, e1, spec[2](whole:match("%((.*)%)")))
            init = e1 + 1
        end
    end
    -- named
    if named then
        local init = 1
        while true do
            local s1, e1, word = line:find("(%a+)", init)
            if not s1 then
                break
            end
            local hex = M.NAMED[word:lower()]
            if hex then
                add(s1, e1, parse_hex_body(hex))
            end
            init = e1 + 1
        end
    end
    table.sort(hits, function(x, y)
        if x.s ~= y.s then
            return x.s < y.s
        end
        return x.e > y.e
    end)
    local out, last_e = {}, -1
    for _, h in ipairs(hits) do
        if h.s >= last_e then
            out[#out + 1] = h
            last_e = h.e
        end
    end
    return out
end

--- The color occurrence containing (or nearest after) 0-based byte `col` on `line`, or nil — the
--- picker/converter seed and the replace target.
---@param line string
---@param col integer  0-based byte col
---@param named? boolean
---@return { color: LvimColor, s: integer, e: integer }|nil
function M.parse_at(line, col, named)
    local all = M.parse_all(line, named)
    local nearest
    for _, h in ipairs(all) do
        if col >= h.s and col < h.e then
            return h
        end
        if h.s >= col and not nearest then
            nearest = h
        end
    end
    return nearest or all[1]
end

--- Standard CSS named colors → 6-digit hex bodies (matched only when `named` is enabled).
---@type table<string, string>
M.NAMED = {
    black = "000000",
    white = "ffffff",
    red = "ff0000",
    green = "008000",
    lime = "00ff00",
    blue = "0000ff",
    yellow = "ffff00",
    cyan = "00ffff",
    aqua = "00ffff",
    magenta = "ff00ff",
    fuchsia = "ff00ff",
    silver = "c0c0c0",
    gray = "808080",
    grey = "808080",
    maroon = "800000",
    olive = "808000",
    purple = "800080",
    teal = "008080",
    navy = "000080",
    orange = "ffa500",
    pink = "ffc0cb",
    brown = "a52a2a",
    gold = "ffd700",
    coral = "ff7f50",
    salmon = "fa8072",
    khaki = "f0e68c",
    violet = "ee82ee",
    indigo = "4b0082",
    turquoise = "40e0d0",
    tomato = "ff6347",
    orchid = "da70d6",
    crimson = "dc143c",
    chocolate = "d2691e",
    tan = "d2b48c",
    beige = "f5f5dc",
    ivory = "fffff0",
    lavender = "e6e6fa",
    plum = "dda0dd",
    skyblue = "87ceeb",
    steelblue = "4682b4",
    royalblue = "4169e1",
    slateblue = "6a5acd",
    seagreen = "2e8b57",
    forestgreen = "228b22",
    darkgreen = "006400",
    limegreen = "32cd32",
    darkred = "8b0000",
    darkblue = "00008b",
    darkgray = "a9a9a9",
    darkgrey = "a9a9a9",
    lightgray = "d3d3d3",
    lightgrey = "d3d3d3",
    transparent = "00000000",
}

return M
