--!strict
-- WeatherLab zone themes. A theme = island look and landforms, field pattern, border
-- look and biome dressing. Add a theme by adding a module here and an
-- entry below; any theme name without one falls back to Default.

local Beach = require(script.Beach)
local Canyon = require(script.Canyon)
local Default = require(script.Default)
local WLTypes = require(script.Parent.WLTypes)

type Theme = WLTypes.Theme

local Themes = {}

Themes.list = {
	Beach = Beach.theme,
	Canyon = Canyon.theme,
	Default = Default.theme,
} :: { [string]: Theme }

function Themes.get(name: string): Theme
	return Themes.list[name] or Themes.list.Default
end

return Themes
