local M = {}

---@param opts {rust_fast_dir: string?}?
function M.setup(opts)
  opts = opts or {}
  local rust_fast_dir = opts.rust_fast_dir or "/tmp/rust_fast_dir"

  ---@param msg string
  ---@return nil
  local function log_err(msg)
    vim.schedule(function() return vim.notify(msg, vim.log.levels.ERROR) end)
  end

  ---@param msg string
  ---@return nil
  local function log_info(msg)
    vim.schedule(function() return vim.notify(msg, vim.log.levels.INFO) end)
  end

  ---@param bufnr integer
  ---@param exception_string string
  local function sync(bufnr, exception_string)
    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    local dest_file_path = (rust_fast_dir .. "/" .. exception_string)
    local dest_file = io.open(dest_file_path, "w")
    if dest_file == nil then
      log_err("Can't open " .. dest_file_path)
      return
    end
    dest_file:write(content)
    dest_file:close()
  end

  --- This function is copied from https://stackoverflow.com/a/40195356/24919919
  local function exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok then
      if code == 13 then return true end
    end
    return ok, err
  end

  ---@param path string
  ---@return string[]
  local function make_path(path)
    local ret = {}

    if #path > 0 and path:sub(1, 1) == "/" then table.insert(ret, "/") end

    local cur = ""
    for character in path:gmatch "." do
      if character == "/" then
        if cur ~= "" then table.insert(ret, cur) end
        cur = ""
      else
        cur = cur .. character
      end
    end

    if cur ~= "" then table.insert(ret, cur) end

    return ret
  end

  ---@param path string[]
  ---@return string
  local function unpath(path)
    local ret = table.concat(path, "/")
    --- HACK: Remove double slashes (e.g. //var/tmp...)
    if path[1] == "/" then ret = ret:sub(2, #ret) end
    return ret
  end

  ---@param path string[]
  ---@return { new: string[], popped: string }
  local function remove_highest(path)
    local popped = table.remove(path, 1)
    return { new = path, popped = popped }
  end

  ---@param path string[]
  ---@return string | nil
  local function highest_dir(path)
    if #path == 0 then return end
    return path[1]
  end

  ---@param long string[]
  ---@param short string[]
  ---@return string[]
  local function function_that_does_a_thing(long, short)
    local ret = {}
    local index = #short + 1
    while index <= #long do
      table.insert(ret, long[index])
      index = index + 1
    end
    return ret
  end

  ---@param src string[]
  ---@param dest string[]
  ---@param except string[]
  ---@return boolean done
  local function symlink_cur(src, dest, except)
    local is_file = #except == 1
    local fs = vim.loop.fs_scandir(unpath(src))
    if fs == nil then
      log_err("Error when opening " .. unpath(src))
      return true
    end

    local forbidden_file = highest_dir(except)
    if forbidden_file == nil then return true end

    while true do
      local name = vim.loop.fs_scandir_next(fs)
      if name == nil then break end
      if name ~= forbidden_file then
        vim.loop.fs_symlink(unpath(src) .. "/" .. name, unpath(dest) .. "/" .. name)
      else
        if not is_file then
          local path = unpath(dest) .. "/" .. forbidden_file
          if not exists(path) then vim.fn.mkdir(path) end
        end
      end
    end

    return is_file
  end

  ---@param src string[]
  ---@param dest string[]
  ---@param except string[]
  ---@return nil
  local function symlink_dir(src, dest, except)
    while true do
      local done = symlink_cur(src, dest, except)
      if done then break end

      local ret = remove_highest(except)
      except = ret.new

      table.insert(src, #src + 1, ret.popped)
      table.insert(dest, #dest + 1, ret.popped)
    end
  end

  if not exists(rust_fast_dir) then vim.fn.mkdir(rust_fast_dir, "p") end

  vim.api.nvim_create_autocmd({ "VimEnter" }, {
    callback = function()
      local buffer_path = vim.fn.expand "%:p"
      if buffer_path:match "%.rs$" ~= nil then
        local cargo_root = vim.fn.fnamemodify(buffer_path, ":h")
        while vim.loop.fs_stat(cargo_root .. "/Cargo.toml") == nil do
          local res = vim.loop.fs_realpath(cargo_root .. "/..")
          if res == nil then
            log_err "Couldn't find cargo root directory."
            return
          end
          cargo_root = res
        end
        if not buffer_path:match(cargo_root .. "/src/.*") then
          log_err("Not in src dir (" .. buffer_path .. " not in " .. cargo_root .. "/src)")
        end

        local cargo_root_path = make_path(cargo_root)
        local rust_fast_path = make_path(rust_fast_dir)
        local exception = function_that_does_a_thing(make_path(buffer_path), cargo_root_path)
        local pseudo_file = (unpath(rust_fast_path) .. unpath(exception))

        symlink_dir(cargo_root_path, rust_fast_path, exception)

        vim.cmd.bd(vim.api.nvim_get_current_buf())
        vim.cmd.e(pseudo_file)

        vim.api.nvim_buf_attach(0, false, {
          on_lines = function() vim.cmd.w() end,
        })
      end
    end,
  })
end

return M
