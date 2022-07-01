local Job = require "plenary.job"

path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"

local path_join = require('bobrown101.plugin-utils').path_join;

local buffer_find_root_dir =
    require('bobrown101.plugin-utils').buffer_find_root_dir;

local is_dir = require('bobrown101.plugin-utils').is_dir;

function split_string(s, delimiter)
    result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match);
    end
    return result;
end

function remove_prefix_from_string(s, p)
    return (s:sub(0, #p) == p) and s:sub(#p + 1) or s
end

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

        -- Search ripgrep for all en.lyaml files in root_dir
        Job:new({
            command = 'rg',
            args = {'--files', root_dir, "-g", "en.lyaml"},
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
                            local translationKeyValuePair = split_string(v,
                                                                         " = ")
                            local label =
                                remove_prefix_from_string(
                                    translationKeyValuePair[1], "en.")

                            if (label ~= "" and not str:match "^#") then -- filter out empty lines and comment lines
                                -- strip off the "en." from the beginning of every key
                                table.insert(items, {
                                    label = label,
                                    documentation = {
                                        kind = "markdown",
                                        value = translationKeyValuePair[2]
                                    }
                                })
                            end
                        end

                        callback {items = items, isIncomplete = false}
                        self.cache[bufnr] = items
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
