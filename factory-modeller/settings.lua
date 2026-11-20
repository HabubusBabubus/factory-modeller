data:extend({
  {
    type = "bool-setting", name = "fm-camera-ui-scale", setting_type = "runtime-per-user",
    default_value = true, order = "b",
  },
  {
    type = "double-setting", name = "fm-text-scale", setting_type = "runtime-global",
    default_value = 1.0, minimum_value = 0.5, maximum_value = 3.0, order = "c",
  },
  {
    type = "double-setting", name = "fm-min-zoom", setting_type = "runtime-per-user",
    default_value = 0.3, minimum_value = 0.05, maximum_value = 1, order = "d",
  },
  {
    type = "bool-setting", name = "fm-show-top-button", setting_type = "runtime-per-user",
    default_value = true, order = "0",
  },
})
