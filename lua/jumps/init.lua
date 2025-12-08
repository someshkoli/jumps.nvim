local M = {}

local default_config = {
  keymap = nil,
  keymap_back = nil,
  keymap_forward = nil,
  telescope = {
    layout_strategy = 'horizontal',
    layout_config = {
      width = 0.9,
      height = 0.9,
    },
  },
}

local config = {}
local jump_history = {}  -- Our own jump history list
-- [[
-- {lnum, filepath, col, bufnr}
-- ]]
local jump_history_position = -1  -- Current position in our jump history (0 = most recent)
local jump_history_top = -1  -- Topmost element position in jump history
local is_navigating = false  -- Flag to prevent recording during navigation

local function file_in_current_project(filepath)
  local root_dir = vim.fn.getcwd()

  local normalized_filepath = vim.fn.fnamemodify(filepath, ':p')
  local normalized_root = vim.fn.fnamemodify(root_dir, ':p')

  if not normalized_root:match('/$') then
    normalized_root = normalized_root .. '/'
  end

  return normalized_filepath:sub(1, #normalized_root) == normalized_root
end

local function history_element_equal(first, second)
    if first.file == second.file and
            first.lnum == second.lnum and
            first.col == second.col then
        return true
    end

    return false
end

local function record_jump(filepath, lnum, col, bufnr)
    if not file_in_current_project(filepath) then
        return
    end

    table.insert(jump_history, {
        filepath = filepath,
        lnum = lnum,
        col = col,
        bufnr = bufnr,
        filename = ""
    })
    jump_history_top = jump_history_top + 1
    jump_history_position = jump_history_position + 1
end

local function record_branched_jump(filepath, lnum, col, bufnr)
    if not file_in_current_project(filepath) then
        return
    end

    -- ensure branch jump index out of bound
    if jump_history_top >= #jump_history then
        vim.api.nvim_echo({{"Error: Branch jump index out of bounds"}}, false, {})
        return
    end


    jump_history[jump_history_top] = {
        filepath = filepath,
        lnum =lnum,
        col = col,
        bufnr =bufnr,
        filename = ""
    }
end

local function set_current_buffer(jump_history_element)
    vim.api.nvim_set_current_buf(jump_history_element.bufnr)
    vim.api.nvim_win_set_cursor(0, { jump_history_element.lnum, jump_history_element.col })
end

function M.jump_back()
    if jump_history_position == 0 then
        vim.api.nvim_echo({{"No further history records available to go backward"}}, false, {})
        return
    end

    jump_history_position = jump_history_position - 1

    if jump_history_position < jump_history_top then
        is_navigating = true
    else
        is_navigating = false
    end

    local current_buffer = jump_history[jump_history_position]

    set_current_buffer(current_buffer)
end

function M.jump_forward()
    if jump_history_position >= jump_history_top then
        vim.api.nvim_echo({{"No further history records available to go forward"}}, false, {})
        return
    end

    jump_history_position = jump_history_position + 1

    if jump_history_position < jump_history_top then
        is_navigating = true
    else
        is_navigating = false
    end

    local current_buffer = jump_history[jump_history_position]

    set_current_buffer(current_buffer)
end

function M.debug()
  vim.print(string.format("=== Jump History Debug ==="))
  vim.print(string.format("jump_history_position: %d", jump_history_position))
  vim.print(string.format("jump_history_top: %d", jump_history_top))
  vim.print(string.format("is_navigating: %s", is_navigating))
  vim.print(string.format("jump_history length: %d", #jump_history))
  vim.print("")
  vim.print("=== Jump History Contents ===")
  for i, entry in ipairs(jump_history) do
    local marker = ""
    if i == jump_history_position + 1 then
      marker = " <-- current position"
    elseif i == jump_history_top + 1 then
      marker = " <-- top"
    end
    vim.print(string.format("[%d] %s:%d:%d (buf:%d)%s",
      i, entry.filepath, entry.lnum, entry.col, entry.bufnr, marker))
  end
  vim.print("=== End Debug ===")
  vim.cmd(":messages")
end

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

  -- Build the display list from our jump history
  local jumps = jump_history
  local current_index = 1
  local added_current_separately = false


  -- Create displayer for nice formatting
  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 1 },   -- current marker
      { width = 30 },  -- filename
      { width = 6 },   -- line:col
      { remaining = true },  -- file path
    },
  })

  local make_display = function(entry)
    local marker = entry.value.is_current and '>' or ' '
    local marker_hl = entry.value.is_current and 'TelescopeSelectionCaret' or 'TelescopeResultsIdentifier'

    return displayer({
      { marker, marker_hl },
      { entry.value.filename, 'TelescopeResultsIdentifier' },
      { string.format('%d:%d', entry.value.lnum, entry.value.col), 'TelescopeResultsLineNr' },
      { entry.value.filepath, 'TelescopeResultsComment' },
    })
  end

  pickers.new(config.telescope or {}, {
    prompt_title = 'Jump History',
    default_selection_index = current_index,
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

        -- Set navigating flag to prevent recording during Telescope jump
        is_navigating = true

        actions.close(prompt_bufnr)

        -- Jump to the selected location
        vim.cmd('buffer ' .. selection.bufnr)
        vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col })

        -- Center the view
        vim.cmd('normal! zz')

        -- Reset navigating flag after a brief delay to ensure all autocmds fire
        vim.schedule(function()
          is_navigating = false
        end)
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
    vim.keymap.set('n', '<leader>rp', ':Lazy reload jumps<CR>', {
      desc = 'Reload jumps plugin',
      silent = true,
    })

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

  local augroup = vim.api.nvim_create_augroup('JumpsNvim', { clear = true })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = augroup,
    callback = function(args)
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local lnum = cursor_pos[1]
        local col = cursor_pos[2]

        if #jump_history == 0 and args.file ~= '' then
            record_jump(args.file, lnum, col, args.buf)
        end
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = augroup,
    callback = function(args)
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local lnum = cursor_pos[1]
        local col = cursor_pos[2]
        -- local filename = args.file:

        if args.file == '' then
            return
        end

        if is_navigating then
            if not history_element_equal(
                {filepath = args.file,lnum = lnum, bufnr = args.buf, col = col},
                -- possible array out of bound exception here, check if jump histor position + 1 is available or not
                jump_history[jump_history_position + 1]
            ) then
                jump_history_top = jump_history_position + 1
                record_branched_jump(args.file, lnum, col, args.buf)
                is_navigating = false
            end
            jump_history_position = jump_history_position + 1
            return
        end

        vim.print("triggered")

        record_jump(args.file, lnum, col, args.buf)
    end,
  })
end

return M
