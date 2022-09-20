local Utils = require("ide.utils")
local Base = require("ide.ui.lib.base")

local Input = Utils.class(Base.Component)

function Input:init(label, value, options)
    options = options or { }

    self._label = label or ""
    self._value = value
    self._format = options.format or "%s"
    self._icon = options.icon or ""
    self:_update_width()

    Base.Component.init(self, options)
end

function Input:_update_width()
    local w = 0

    if self._label then
        w = #self._label
    end

    if self._value then
        w = w + string.format(self._format, self._value)
    end

    self.width = w
end

function Input:set_value(v)
    self._value = v
end

function Input:get_value()
    return self._value
end

function Input:render(_)
    local s = ""

    if self._icon then
        s = self._icon .. " "
    end

    s = s .. self._label .. " "

    if self._value ~= nil then
        s = s .. string.format(self._format, self._value)
    end

    return s
end

function Input:on_click(_)
end

function Input:on_doubleclick(e)
    self:on_event(e)
end

function Input:on_event(e)
    vim.ui.input(self._label, function(choice)
        self._value = choice
        e.update()
    end)
end

return Input
