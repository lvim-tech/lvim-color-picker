-- lvim-color-picker.config: the live configuration table for the three tools (picker / converter /
-- highlighter). setup() merges user overrides into THIS table in place, so every
-- require("lvim-color-picker.config") reader sees the effective values (the highlighter reads its
-- style/auto list live so the control center can flip them without a restart).
--
---@module "lvim-color-picker.config"

---@class LvimColorPickerPicker
---@field mode   "rgb"|"hsl"|"cmyk"       Which sliders the panel opens with (`m` cycles rgb→hsl→cmyk)
---@field output "hex"|"rgb"|"hsl"|"cmyk" The output syntax the panel inserts/yanks in (`o` cycles it)
---@field alpha  "auto"|boolean    "auto"/true = show the A slider (auto emits alpha only when < 1 or the source had it; true always emits); false = no A slider

---@class LvimColorPickerHighlighter
---@field auto  string[]           Filetypes the inline highlighter auto-enables in
---@field style "bg"|"fg"|"virtual" How a color literal is painted (background / foreground / a chip before it)
---@field named boolean            Match CSS named colors (off outside css/scss/html is safest — they collide with words)

---@class LvimColorPickerConfig
---@field picker        LvimColorPickerPicker
---@field highlighter   LvimColorPickerHighlighter
---@field convert_cycle ("hex"|"rgb"|"hsl")[]  The order the converter rotates a literal through

---@type LvimColorPickerConfig
return {
    -- The slider panel: which channels it opens with, what syntax it inserts, and whether the alpha
    -- slider appears (auto = only when the seeded color carried an alpha channel).
    picker = {
        mode = "rgb",
        output = "hex",
        alpha = "auto",
    },
    -- The inline highlighter: a decoration provider paints color literals in the visible lines. `bg`
    -- tints the literal's background (fg auto-chosen for contrast), `fg` colors the text, `virtual`
    -- shows a swatch chip before it. Named-color matching is off by default (collides with words).
    highlighter = {
        auto = { "css", "scss", "sass", "less", "html", "conf", "lua" },
        style = "bg",
        named = false,
        -- The swatch glyph the `virtual` style paints before the literal (Nerd Font). Trailing space = gap.
        chip_icon = "󰝤 ",
    },
    -- The converter rotation: `:LvimColorPicker convert` rewrites the literal under the cursor in the
    -- NEXT syntax of this list, wrapping around.
    convert_cycle = { "hex", "rgb", "hsl" },
}
