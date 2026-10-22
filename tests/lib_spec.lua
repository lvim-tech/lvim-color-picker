-- Colour conversions, where rounding decides whether a colour survives a round trip.
--
-- The picker converts between hex, rgb, hsl and cmyk as the user cycles syntaxes, so the property
-- that matters is that a colour comes BACK: rgb → hsl → rgb must return the same bytes, or
-- cycling the syntax twice would quietly drift the colour. The grey axis (saturation zero) and
-- pure black and white are where the formulas divide by zero if they are written carelessly.

local lib = require("lvim-color-picker.lib")

---@param r integer
---@param g integer
---@param b integer
---@return integer, integer, integer
local function round_trip(r, g, b)
    local h, s, l = lib.rgb_to_hsl(r, g, b)
    return lib.hsl_to_rgb(h, s, l)
end

describe("lvim-color-picker.lib.rgb_to_hsl")

it("reads the primaries' hues", function()
    local h = (lib.rgb_to_hsl(255, 0, 0))
    eq(0, math.floor(h + 0.5), "red is hue 0")
    h = (lib.rgb_to_hsl(0, 255, 0))
    eq(120, math.floor(h + 0.5), "green is 120")
    h = (lib.rgb_to_hsl(0, 0, 255))
    eq(240, math.floor(h + 0.5), "blue is 240")
end)

it("gives a grey no saturation and keeps its lightness", function()
    local _, s, l = lib.rgb_to_hsl(128, 128, 128)
    eq(0, s, "a grey has no hue to be saturated with")
    truthy(math.abs(l - 128 / 255) < 0.001, "lightness " .. l)
end)

it("handles black and white without dividing by zero", function()
    local h, s, l = lib.rgb_to_hsl(0, 0, 0)
    eq(0, h)
    eq(0, s)
    eq(0, l)
    h, s, l = lib.rgb_to_hsl(255, 255, 255)
    eq(0, s)
    eq(1, l)
end)

it("never answers with a negative hue", function()
    -- The magenta sector is where the formula goes negative before the wrap.
    for b = 0, 255, 17 do
        local h = (lib.rgb_to_hsl(255, 0, b))
        truthy(h >= 0 and h < 360.0001, ("hue %s for #ff00%02x"):format(h, b))
    end
end)

describe("lvim-color-picker.lib: the round trip")

it("brings a colour back through HSL unchanged", function()
    local cases = {
        { 255, 0, 0 },
        { 0, 255, 0 },
        { 0, 0, 255 },
        { 18, 39, 43 },
        { 94, 136, 136 },
        { 216, 179, 111 },
        { 1, 2, 3 },
        { 254, 253, 252 },
    }
    for _, c in ipairs(cases) do
        local r, g, b = round_trip(c[1], c[2], c[3])
        eq({ c[1], c[2], c[3] }, { r, g, b }, ("rgb(%d,%d,%d) came back as rgb(%d,%d,%d)"):format(c[1], c[2], c[3], r, g, b))
    end
end)

it("brings every grey back unchanged", function()
    for v = 0, 255, 5 do
        local r, g, b = round_trip(v, v, v)
        eq({ v, v, v }, { r, g, b }, "grey " .. v .. " came back as " .. r .. "," .. g .. "," .. b)
    end
end)

it("brings the whole hue circle back unchanged at full saturation", function()
    for h = 0, 359, 7 do
        local r, g, b = lib.hsl_to_rgb(h, 1, 0.5)
        local r2, g2, b2 = round_trip(r, g, b)
        eq({ r, g, b }, { r2, g2, b2 }, "hue " .. h)
    end
end)

describe("lvim-color-picker.lib.rgb_to_cmyk")

it("reads black as all key and white as none", function()
    local c, m, y, k = lib.rgb_to_cmyk(0, 0, 0)
    eq({ 0, 0, 0, 1 }, { c, m, y, k })
    c, m, y, k = lib.rgb_to_cmyk(255, 255, 255)
    eq({ 0, 0, 0, 0 }, { c, m, y, k })
end)

it("brings a colour back through CMYK", function()
    for _, case in ipairs({ { 255, 0, 0 }, { 0, 128, 255 }, { 18, 39, 43 }, { 200, 200, 200 } }) do
        local c, m, y, k = lib.rgb_to_cmyk(case[1], case[2], case[3])
        local r, g, b = lib.cmyk_to_rgb(c, m, y, k)
        eq(case, { r, g, b }, ("rgb(%d,%d,%d) came back as rgb(%d,%d,%d)"):format(case[1], case[2], case[3], r, g, b))
    end
end)

describe("lvim-color-picker.lib.luminance")

it("puts white at the top and black at the bottom", function()
    eq(0, lib.luminance({ r = 0, g = 0, b = 0 }))
    eq(1, lib.luminance({ r = 255, g = 255, b = 255 }))
end)

it("weighs green above red above blue, as the eye does", function()
    local green = lib.luminance({ r = 0, g = 255, b = 0 })
    local red = lib.luminance({ r = 255, g = 0, b = 0 })
    local blue = lib.luminance({ r = 0, g = 0, b = 255 })
    truthy(green > red and red > blue, ("green %s red %s blue %s"):format(green, red, blue))
end)

describe("lvim-color-picker.lib.format")

it("writes each syntax the way a stylesheet does", function()
    local color = { r = 18, g = 39, b = 43 }
    eq("rgb(18, 39, 43)", lib.format(color, "rgb"))
    truthy(lib.format(color, "hsl"):match("^hsl%(%d+, %d+%%, %d+%%%)$") ~= nil, lib.format(color, "hsl"))
    truthy(lib.format(color, "hex"):match("^#%x%x%x%x%x%x$") ~= nil, lib.format(color, "hex"))
end)

it("keeps an alpha channel where the syntax has one", function()
    local color = { r = 18, g = 39, b = 43, a = 0.5 }
    eq("rgba(18, 39, 43, 0.5)", lib.format(color, "rgb"))
    truthy(lib.format(color, "hsl"):find("hsla", 1, true) == 1, lib.format(color, "hsl"))
end)

it("drops the alpha for CMYK, which has no such channel", function()
    local out = lib.format({ r = 18, g = 39, b = 43, a = 0.5 }, "cmyk")
    truthy(out:find("0.5", 1, true) == nil, "the alpha leaked into " .. out)
end)

it("clamps a value that strayed outside the byte range", function()
    eq("rgb(0, 255, 7)", lib.format({ r = -20, g = 300, b = 7 }, "rgb"))
end)

describe("lvim-color-picker.lib.parse_all")

it("finds every colour in a line, with its bounds", function()
    local found = lib.parse_all("bg: #12272b; fg: rgb(94, 136, 136);", false)
    eq(2, #found, vim.inspect(found))
end)

it("finds nothing in a line with no colour", function()
    eq(0, #lib.parse_all("just some text", false))
end)
