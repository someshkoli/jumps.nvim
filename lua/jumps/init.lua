local M = {}

-- Default configuration
local default_config = {
  -- Keymap to open the jump picker (set to nil by default, user must configure)
  keymap = nil,
  -- Keymaps for navigating filtered jumps (set to nil by default, user must configure)
  keymap_back = nil,
  keymap_forward = nil,
  -- Telescope picker options
  telescope = {
    layout_strategy = 'horizontal',
    layout_config = {
      width = 0.9,
      height = 0.9,
    },
  },
}

-- Plugin state
local config = {}
local jump_history_position = 0  -- Current position in filtered jump history

-- Check if a filepath is within the current root directory
local function is_in_root_directory(filepath)
  local root_dir = vim.fn.getcwd()

  -- Normalize paths to handle symlinks and relative paths
  local normalized_filepath = vim.fn.fnamemodify(filepath, ':p')
  local normalized_root = vim.fn.fnamemodify(root_dir, ':p')

  -- Ensure root directory ends with separator for proper prefix matching
  if not normalized_root:match('/$') then
    normalized_root = normalized_root .. '/'
  end

  -- Check if filepath starts with root directory
  return normalized_filepath:sub(1, #normalized_root) == normalized_root
end

-- Get filtered jumplist with only cross-file jumps
local function get_filtered_jumplist()
  local jumplist = vim.fn.getjumplist()
  local jumps = jumplist[1]
  local current_pos = jumplist[2]
  local current_file = vim.fn.expand('%:p')

  local filtered = {}
  local seen_files = {}

  -- Iterate through jumplist in reverse to get most recent first
  for i = #jumps, 1, -1 do
    local jump = jumps[i]
    local bufnr = jump.bufnr

    -- Skip invalid buffers
    if vim.api.nvim_buf_is_valid(bufnr) then
      local filepath = vim.api.nvim_buf_get_name(bufnr)

      -- Only include if it's a different file, we haven't seen it yet, and it's in the root directory
      if filepath ~= '' and filepath ~= current_file and not seen_files[filepath] and is_in_root_directory(filepath) then
        seen_files[filepath] = true

        table.insert(filtered, {
          bufnr = bufnr,
          filepath = filepath,
          filename = vim.fn.fnamemodify(filepath, ':t'),
          lnum = jump.lnum,
          col = jump.col,
          -- Store original index for potential future use
          original_idx = i,
        })
      end
    end
  end

  return filtered
end

-- Navigate backward in filtered jump history
function M.jump_back()
  local jumps = get_filtered_jumplist()

  if #jumps == 0 then
    vim.notify('No cross-file jumps found in current root directory', vim.log.levels.INFO)
    return
  end

  -- Move position forward (since list is in reverse chronological order)
  jump_history_position = jump_history_position + 1

  if jump_history_position > #jumps then
    jump_history_position = #jumps
    vim.notify('Already at oldest jump', vim.log.levels.INFO)
    return
  end

  local jump = jumps[jump_history_position]
  vim.cmd('buffer ' .. jump.bufnr)
  vim.api.nvim_win_set_cursor(0, { jump.lnum, jump.col })
  vim.cmd('normal! zz')

  vim.notify(string.format('Jump %d/%d: %s:%d', jump_history_position, #jumps, jump.filename, jump.lnum), vim.log.levels.INFO)
end

-- Navigate forward in filtered jump history
function M.jump_forward()
  local jumps = get_filtered_jumplist()

  if #jumps == 0 then
    vim.notify('No cross-file jumps found in current root directory', vim.log.levels.INFO)
    return
  end

  -- Move position backward (since list is in reverse chronological order)
  jump_history_position = jump_history_position - 1

  if jump_history_position < 1 then
    jump_history_position = 1
    vim.notify('Already at newest jump', vim.log.levels.INFO)
    return
  end

  local jump = jumps[jump_history_position]
  vim.cmd('buffer ' .. jump.bufnr)
  vim.api.nvim_win_set_cursor(0, { jump.lnum, jump.col })
  vim.cmd('normal! zz')

  vim.notify(string.format('Jump %d/%d: %s:%d', jump_history_position, #jumps, jump.filename, jump.lnum), vim.log.levels.INFO)
end

-- Debug function to inspect jumplist
function M.debug()
  local jumplist = vim.fn.getjumplist()
  local jumps = jumplist[1]
  local current_pos = jumplist[2]
  local current_file = vim.fn.expand('%:p')
  local root_dir = vim.fn.getcwd()

  print('=== Jumplist Debug ===')
  print('Root directory: ' .. root_dir)
  print('Total jumps: ' .. #jumps)
  print('Current position: ' .. current_pos)
  print('Current file: ' .. current_file)
  print('\nAll jumps:')

  for i, jump in ipairs(jumps) do
    local bufnr = jump.bufnr
    local valid = vim.api.nvim_buf_is_valid(bufnr)
    local filepath = valid and vim.api.nvim_buf_get_name(bufnr) or '<invalid>'
    local is_current = filepath == current_file
    local in_root = valid and filepath ~= '' and is_in_root_directory(filepath)

    print(string.format(
      '[%d] buf:%d valid:%s file:%s same_file:%s in_root:%s lnum:%d col:%d',
      i, bufnr, tostring(valid), filepath, tostring(is_current), tostring(in_root), jump.lnum, jump.col
    ))
  end

  local filtered = get_filtered_jumplist()
  print('\n=== Filtered Results ===')
  print('Cross-file jumps found: ' .. #filtered)
  for i, entry in ipairs(filtered) do
    print(string.format('[%d] %s:%d:%d', i, entry.filename, entry.lnum, entry.col))
  end
end

-- Open telescope picker with filtered jumplist
function M.show()
  local has_telescope, telescope = pcall(require, 'telescope')
  if not has_telescope then
    vim.notify('Telescope.nvim is required for jumps.nvim', vim.log.levels.ERROR)
    return
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local entry_display = require('telescope.pickers.entry_display')
  local previewers = require('telescope.previewers')

  local jumps = get_filtered_jumplist()

  if #jumps == 0 then
    vim.notify('No cross-file jumps found in current root directory', vim.log.levels.INFO)
    return
  end

  -- Create displayer for nice formatting
  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 30 },  -- filename
      { width = 6 },   -- line:col
      { remaining = true },  -- file path
    },
  })

  local make_display = function(entry)
    return displayer({
      { entry.value.filename, 'TelescopeResultsIdentifier' },
      { string.format('%d:%d', entry.value.lnum, entry.value.col), 'TelescopeResultsLineNr' },
      { entry.value.filepath, 'TelescopeResultsComment' },
    })
  end

  pickers.new(config.telescope or {}, {
    prompt_title = 'Cross-File Jumps',
    finder = finders.new_table({
      results = jumps,
      entry_maker = function(entry)
        return {
          value = entry,
          display = make_display,
          ordinal = entry.filepath .. ' ' .. entry.filename,
          filename = entry.filepath,
          lnum = entry.lnum,
          col = entry.col,
          bufnr = entry.bufnr,
        }
      end,
    }),
    previewer = previewers.new_buffer_previewer({
      title = 'Jump Location Preview',
      get_buffer_by_name = function(_, entry)
        return entry.filename
      end,
      define_preview = function(self, entry, status)
        local bufnr = self.state.bufnr
        local winid = self.state.winid

        if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
          return
        end

        conf.buffer_previewer_maker(entry.filename, bufnr, {
          bufname = self.state.bufname,
          winid = winid,
          callback = function(buf)
            -- Enable line numbers
            vim.wo[winid].number = true

            -- Validate line and column numbers
            local line_count = vim.api.nvim_buf_line_count(buf)
            local target_line = math.min(entry.lnum, line_count)
            target_line = math.max(1, target_line)

            -- Get the target line content to validate column
            local line_content = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ''
            local target_col = math.min(entry.col, #line_content)
            target_col = math.max(0, target_col)

            -- Set cursor to validated position
            pcall(vim.api.nvim_win_set_cursor, winid, { target_line, target_col })

            -- Center the view
            pcall(vim.api.nvim_win_call, winid, function()
              vim.cmd('normal! zz')
            end)

            -- Highlight the target line if valid
            if target_line <= line_count then
              local ns_id = vim.api.nvim_create_namespace('jumps_preview_highlight')
              vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
              pcall(vim.api.nvim_buf_add_highlight,
                buf,
                ns_id,
                'Visual',
                target_line - 1,
                0,
                -1
              )
            end
          end,
        })
      end,
    }),
    sorter = conf.generic_sorter(config.telescope or {}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Jump to the selected location
        vim.cmd('buffer ' .. selection.bufnr)
        vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col })

        -- Center the view
        vim.cmd('normal! zz')
      end)
      return true
    end,
  }):find()
end

-- Setup function called by user in their config
function M.setup(user_config)
  config = vim.tbl_deep_extend('force', default_config, user_config or {})

  -- Create user commands
  vim.api.nvim_create_user_command('Jumps', function()
    M.show()
  end, { desc = 'Show cross-file jumplist in Telescope' })

  vim.api.nvim_create_user_command('JumpsDebug', function()
    M.debug()
  end, { desc = 'Debug jumplist filtering' })

  vim.api.nvim_create_user_command('JumpsBack', function()
    M.jump_back()
  end, { desc = 'Jump backward in filtered history' })

  vim.api.nvim_create_user_command('JumpsForward', function()
    M.jump_forward()
  end, { desc = 'Jump forward in filtered history' })

  -- Set up default keymap if provided
  if config.keymap then
    vim.keymap.set('n', config.keymap, M.show, {
      desc = 'Open cross-file jumplist',
      silent = true,
    })
  end

  -- Set up navigation keymaps if provided
  if config.keymap_back then
    vim.keymap.set('n', config.keymap_back, M.jump_back, {
      desc = 'Jump backward in filtered history',
      silent = true,
    })
  end

  if config.keymap_forward then
    vim.keymap.set('n', config.keymap_forward, M.jump_forward, {
      desc = 'Jump forward in filtered history',
      silent = true,
    })
  end
end

return M
