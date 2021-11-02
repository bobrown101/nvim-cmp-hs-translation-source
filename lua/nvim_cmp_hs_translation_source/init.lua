local Job = require "plenary.job"

path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"

function path_join(...) return table.concat(vim.tbl_flatten({...}), path_sep) end

-- Asumes filepath is a file.
local function dirname(filepath)
    local is_changed = false
    local result = filepath:gsub(path_sep .. "([^" .. path_sep .. "]+)$",
                                 function()
        is_changed = true
        return ""
    end)
    return result, is_changed
end

-- Ascend the buffer's path until we find the rootdir.
-- is_root_path is a function which returns bool
function buffer_find_root_dir(bufnr, is_root_path)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if vim.fn.filereadable(bufname) == 0 then return nil end
    local dir = bufname
    -- Just in case our algo is buggy, don't infinite loop.
    for _ = 1, 100 do
        local did_change
        dir, did_change = dirname(dir)
        if is_root_path(dir, bufname) then return dir, bufname end
        -- If we can't ascend further, then stop looking.
        if not did_change then return nil end
    end
end

function is_dir(filename)
    local stat = vim.loop.fs_stat(filename)
    return stat and stat.type == "directory" or false
end

function split_string(s, delimiter)
    result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match);
    end
    return result;
end

function remove_language_prefix(s) return s:gsub("en.", "") end

local source = {}

source.new = function()
    local self = setmetatable({cache = {}}, {__index = source})
    return self
end

source.complete = function(self, _, callback)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Only generate this map once per session. Might want to add an invalidate flag somewhere eventually
    if not self.cache[bufnr] then
        -- Try to find the project root of the current file via a git directory
        -- .git
        local root_dir = buffer_find_root_dir(bufnr, function(dir)
            return is_dir(path_join(dir, '.git'))
        end)
        -- We couldn't find a root directory, so ignore this file.
        if not root_dir then callback {items = {}, isIncomplete = false} end

        -- Search ripgrep for all files
        Job:new({
            command = 'rg',
            args = {'--files', root_dir},
            on_exit = function(job)
                local all_files = job:result()
                -- from within all files, search for any en.lyaml files
                Job:new({
                    command = 'rg',
                    args = {'en.lyaml'},
                    writer = all_files,
                    on_exit = function(job)
                        local lyaml_files_for_current_project = job:result()
                        local args = {}
                        table.insert(args, "ea")
                        table.insert(args, '. as $item ireduce ({}; . * $item )')
                        for k, v in ipairs(lyaml_files_for_current_project) do
                            table.insert(args, v)
                        end
                        table.insert(args, "-o")
                        table.insert(args, "p")

                        -- merge together all en.lyaml files and output the aggregate in the format of
                        -- this.is.a.key = This is the translation
                        Job:new({
                            command = "yq",
                            args = args,
                            on_exit = function(job)
                                local unparsed_results = job:result()
                                local items = {}
                                -- map over every key/translation line
                                for k, v in ipairs(unparsed_results) do
                                    -- separate each line into a key/translation via the ` = ` between then
                                    local translationKeyValuePair =
                                        split_string(v, " = ")

                                    -- strip off the "en." from the beginning of every key
                                    table.insert(items, {
                                        label = remove_language_prefix(
                                            translationKeyValuePair[1]),
                                        documentation = {
                                            kind = "markdown",
                                            value = translationKeyValuePair[2]
                                        }
                                    })
                                end

                                callback {items = items, isIncomplete = false}
                                self.cache[bufnr] = items
                            end
                        }):start()
                    end
                }):start()
            end
        }):start()
    else
        callback {items = self.cache[bufnr], isIncomplete = false}
    end
end

source.get_trigger_characters = function() return {'"'} end

source.is_available = function() return true end

local M = {}

function M.setup()
    require("cmp").register_source("nvim_cmp_hs_translation_source",
                                   source.new())
end

return M
