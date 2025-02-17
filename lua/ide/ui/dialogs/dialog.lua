local Utils = require("ide.utils")
local Window = require("ide.ui.base.window")
local Model = require("ide.ui.base.model")

local Dialog = Utils.class(Window)

function Dialog:init(title, options)
    Window.init(self, options)

    self._dblclick = false
    self._extmarks = { }
    self._title = title

    self.model = Model({
        change = function(model, k, newvalue, oldvalue)
            self:on_model_changed(model, k, newvalue, oldvalue)
            self:render()
        end
    })

    self:_create_mapping()
end

function Dialog:set_components(components)
    local RESERVED_KEYS = {
        ["<2-LeftMouse>"] = true,
        ["<LeftRelease>"] = true,
        ["<ESC>"] = true,
        ["<CR>"] = true,
        ["<C-h>"] = true
    }

    local hidx, c, Components = 1, components, require("ide.ui.components")

    if self._title then
        c = vim.list_extend({
            Components.Label(self._title, {width = "100%", align = "center", foreground = "accent"}),
            Components.HLine(),
        }, components)

        hidx = 2
    end

    if self.winoptions.showhelp ~= false then
        table.insert(c, hidx, {
            Components.Label("Press '<C-h>' for Help", {width = "100%", align = "center", foreground = "secondary"})
        })
    end

    if not self.winoptions.height then
        self.winoptions.height = not vim.tbl_isempty(c) and #c or math.ceil(vim.o.lines * 0.75)
        self.bufoptions.height = self.winoptions.height
    end

    self._extmarks = { }
    self:unmap_all()
    self:clear()

    -- Map keys, if needed
    self.model:each_component(function(cc)
        if cc.key then
            if RESERVED_KEYS[cc.key] then
                error("Key '" .. cc.key .. "' is reserved")
            end

            self:map(cc.key, function() self:_event(cc, "event") end)
        end
    end, c)

    self.model:set_components(c)
end

function Dialog:accept()
    if not self.model:validate() then
        return
    end

    self:on_accept(self.model.data)

    if vim.is_callable(self._onaccept) then
        if self._onaccept(self.model.data, self) ~= false then
            self:close()
        end
    else
        self:close()
    end
end

function Dialog:popup(cb)
    if not self.hwin then
        self._onaccept = cb
    end

    self:show()
end

function Dialog:_find_component(row, col)
    row = row - 1
    col = col - 1

    for _, crow in ipairs(self.model:get_components()) do
        local cl = vim.tbl_islist(crow) and crow or {crow}

        for _, c in ipairs(cl) do
            local srow, scol = self:calc_row(c), self:calc_col(c)
            local erow, ecol = srow + self:calc_height(c), scol + self:calc_width(c)

            if (row >= srow and row < erow) and (col >= scol and col < ecol) then
                return c
            end
        end
    end

    return nil
end

function Dialog:_event_at(type, row, col)
    local c = self:_find_component(row, col)

    if c then
        self:_event(c, type, row, col)
    else
        self["on_" .. type](self)
    end
end

function Dialog:_event(c, type, row, col)
    self["on_" .. type](self)

    if not row or not col then
        local cursor = vim.api.nvim_win_get_cursor(self.hwin)
        row, col = cursor[1], cursor[1]
    end

    local e = {
        sender = self,
        row = row,
        col = col,

        update = function()
            if c.id then
                self.model.data[c.id] = c:get_value()
            end
        end
    }

    if vim.is_callable(c["on_" .. type]) then
        c["on_" .. type](c, e)
    end
end


function Dialog:_create_mapping()
    local function _send(t)
        local cursor = vim.api.nvim_win_get_cursor(self.hwin)
        self:_event_at(t, cursor[1], cursor[2])
    end

    self:map("<C-h>", function()
        if self.winoptions.showhelp ~= false then
            self:on_help()
        end
    end, {builtin = true})

    self:map("<ESC>", function()
        _send("escape")
    end, {builtin = true})

    self:map("<CR>", function()
        _send("event")
    end, {builtin = true})

    self:map("<LeftRelease>", function()
        if self._dblclick then
            self._dblclick = false
        else
            _send("click")
        end
    end, {builtin = true})

    self:map("<2-LeftMouse>", function()
        self._dblclick = true
        _send("doubleclick")
    end, {builtin = true})
end

function Dialog:render()
    local theme = self:get_theme()

    local function hl(h, t)
        if not h then
            return nil
        end

        if vim.startswith(h, "#") then
            return h
        end

        if type(t) ~= "table" then
            t = {t}
        end

        h = theme.get_color(h)
        local hln = vim.api.nvim_get_hl_by_name(h, true)

        for _, ct in ipairs(t) do
            if hln[ct] then
                return "#" .. bit.tohex(hln[ct], 6)
            end
        end
        error("Cannot find color '" .. h .. "'")
    end

    local UTF8 = require("ide.ui.utils.utf8")

    for _, c in ipairs(self.model:get_components()) do
        local d = c:render(self)

        if d then
            local rowidx = self:calc_row(c) + 1
            local row = self.data[rowidx]

            if row then
                local i, len = 0, UTF8.len(d)

                for col = self:calc_col(c), #row - 1 do
                    row[col + 1] = i < len and UTF8.char(d, i) or " "
                    i = i + 1
                end
            end
        end
    end

    local lines = { }

    for _, row in ipairs(self.data) do
        table.insert(lines, table.concat(row))
    end

    self:commit(function()
        vim.api.nvim_buf_set_lines(self.hbuf, 0, -1, false, lines)

        for i, c in ipairs(self.model:get_components()) do
            if c.foreground or c.background or c.bold then
                local n = ("highlight_nvide_%d"):format(i)

                vim.api.nvim_set_hl(self.hns, n, {
                    foreground = hl(c.foreground, {"foreground", "background"}),
                    background = hl(c.background, {"background", "foreground"}),
                    bold = c.bold or false
                })

                local start = self:calc_col(c)

                for r = 0, self:calc_height(c) - 1 do
                    vim.api.nvim_buf_add_highlight(self.hbuf, self.hns, n, c.row + r, start, start + self:calc_width(c))
                end
            end
        end
    end)
end

function Dialog:on_help()
    if not vim.tbl_isempty(self._extmarks) then
        for _, id in ipairs(self._extmarks) do
            vim.api.nvim_buf_del_extmark(self.hbuf, self.hns, id)
        end

        self._extmarks = { }
        return
    end

    for _, c in ipairs(self.model:get_components()) do
        if c.key then
            local row, col = self:calc_row(c), self:calc_col(c)

            table.insert(self._extmarks, vim.api.nvim_buf_set_extmark(self.hbuf, self.hns, row, col, {
                virt_text = {{c.key, "ErrorMsg"}},
                virt_text_pos = "overlay"
            }))
        end
    end
end

function Dialog:on_accept(model)
end

function Dialog:on_event()
end

function Dialog:on_click()
end

function Dialog:on_doubleclick()
end

function Dialog:on_escape()
    self:close()
end

function Dialog:on_model_changed(model, k, newvalue, oldvalue)
end

return Dialog
