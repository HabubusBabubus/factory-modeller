local function press(name, key, alt)
  return {
    type = "custom-input", name = name, key_sequence = key,
    alternative_key_sequence = alt, consuming = "none", action = "lua",
  }
end

data:extend({
  { type = "custom-input", name = "fm-toggle", key_sequence = "CONTROL + SHIFT + F", consuming = "game-only", action = "lua", order = "a" },
  press("fm-wheel-up", "mouse-wheel-up"),
  press("fm-wheel-down", "mouse-wheel-down"),
  press("fm-delete", "DELETE"),
  press("fm-middle", "mouse-button-3"),
  press("fm-dbg-press", "mouse-button-1"),
  press("fm-dbg-release", "mouse-button-2"),
  press("fm-pan-left", "LEFT"),
  press("fm-pan-right", "RIGHT"),
  press("fm-pan-up", "UP"),
  press("fm-pan-down", "DOWN"),
  {
    type = "shortcut",
    name = "fm-shortcut",
    action = "lua",
    toggleable = true,
    associated_control_input = "fm-toggle",
    icon = "__base__/graphics/icons/assembling-machine-2.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/assembling-machine-2.png",
    small_icon_size = 64,
    order = "f[factory-modeller]",
  },
})
