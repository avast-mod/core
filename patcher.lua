--[[
      .:       .::         .::            .:: ::    .::
     .: ::      .::       .::           .::    .::  .::
    .:  .::      .::     .::     .::     .::      .:.: .:
   .::   .::      .::   .::    .::  .::    .::      .::
  .:::::: .::      .:: .::    .::   .::       .::   .::
 .::       .::      .::::     .::   .:: .::    .::  .::
.::         .::      .::        .:: .:::  .:: ::     .::

AVaSt - https://github.com/avast-mod

release builds of godot dont keep script call stacks, so error reports only showed
the one line that failed. this turns call stack tracking on before the game even starts
(skipped if debug.call_stacks is off in the settings)

also adds demo.gd as the AVaStDemo autoload. in the demo cores mod.gd cant compile, an
autoload doesnt care about that so the demo notice still shows up even if the api broke too
]]

if GDPatch.get_config_option(nil, "debug", "call_stacks") ~= false then
  GDPatch.patch_project_settings(function(settings)
    table.insert(settings, { "debug/settings/gdscript/always_track_call_stacks", true })
    return settings
  end)
end

GDPatch.patch_project_settings(function(settings)
  table.insert(settings, { "autoload/AVaStDemo", "*res://gdpatch/mods/avast_core/demo.gd" })
  return settings
end)
