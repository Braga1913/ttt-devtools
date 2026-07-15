local ttt = require("ttt")
local editor = require("ttt.editor")
local sys = require("ttt.system")

local plugin_dir = ttt.plugin_dir()

-- Build output buffer
local build_lines = {}
local build_panel = nil
local build_scroll = 0

local function build_log(line)
  table.insert(build_lines, line)
  if #build_lines > 500 then
    table.remove(build_lines, 1)
  end
  build_scroll = 0
  if build_panel then
    build_panel:redraw()
  end
end

local function build_clear()
  build_lines = {}
  table.insert(build_lines, "--- Build started ---")
  build_scroll = 0
  if build_panel then
    build_panel:redraw()
  end
end

-- Config
local actions = {
  { id = "switch-header", title = "DevTools: Switch Header/Source", script = "scripts/switch-header.sh" },
}

local build_config = {
  generator = "Ninja Multi-Config",
  buildType = "Debug",
  buildDir = "build",
  extraArgs = "",
}

local function file_exists(path)
  local result = sys.exec("bash", { "-c", "test -f '" .. path .. "'" })
  return result and result.exit_code == 0
end

local function find_project_root(file_path)
  if not file_path or file_path == "" then return nil end
  local dir = file_path:match("^(.+)/[^/]+$")
  if not dir then return nil end
  local markers = { "CMakeLists.txt", "Makefile", ".git", "compile_commands.json", "Cargo.toml", "package.json" }
  local search = dir
  for _ = 1, 30 do
    for _, marker in ipairs(markers) do
      if file_exists(search .. "/" .. marker) then
        return search
      end
    end
    local parent = search:match("^(.+)/[^/]+$")
    if not parent or parent == search then break end
    search = parent
  end
  return dir
end

-- Create Implementation feature
local function find_source_file(header_path)
  local base = header_path:match("^(.+)%.h$") or header_path:match("^(.+)%.hpp$")
  if not base then return nil end
  local extensions = { ".cpp", ".cc", ".cxx" }
  for _, ext in ipairs(extensions) do
    local source = base .. ext
    if file_exists(source) then
      return source
    end
  end
  return base .. ".cpp"
end

local function parse_declaration(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" then return nil end
  if not trimmed:match(";%s*$") and not trimmed:match(";%s*$") then return nil end
  local is_virtual = trimmed:match("^virtual%s+") ~= nil
  if is_virtual then
    trimmed = trimmed:gsub("^virtual%s+", "")
  end
  local is_static = trimmed:match("^static%s+") ~= nil
  if is_static then
    trimmed = trimmed:gsub("^static%s+", "")
  end
  local is_inline = trimmed:match("^inline%s+") ~= nil
  if is_inline then
    trimmed = trimmed:gsub("^inline%s+", "")
  end
  trimmed = trimmed:match("^(.-)%s*;%s*$")
  if not trimmed then return nil end
  local is_default = trimmed:match("%s*=%s*default%s*$") ~= nil
  if is_default then return nil end
  local is_pure_virtual = trimmed:match("%s*=%s*0%s*$") ~= nil
  if is_pure_virtual then
    trimmed = trimmed:gsub("%s*=%s*0%s*$", "")
  end
  trimmed = trimmed:gsub("%s*override%s*$", "")
  trimmed = trimmed:gsub("%s*final%s*$", "")
  local return_type, rest = trimmed:match("^(.-)%s+([%w~_]+%s*%(.*)")
  if not return_type or return_type == "" then
    local ctor_dtor = trimmed:match("^([%w_~]+)%s*%((.*)")
    if ctor_dtor then
      local params = trimmed:match("^[%w_~]+%s*%((.*)")
      if not params then params = "" end
      return {
        is_constructor = true,
        class_name = ctor_dtor,
        params = "(" .. params,
        is_virtual = is_virtual,
        is_pure_virtual = is_pure_virtual,
      }
    end
    return nil
  end
  local func_name, params = rest:match("^([%w_~]+)%s*%((.*)")
  if not func_name then return nil end
  return {
    return_type = return_type,
    func_name = func_name,
    params = "(" .. params,
    is_virtual = is_virtual,
    is_pure_virtual = is_pure_virtual,
  }
end

local function generate_definition(decl, class_name)
  if decl.is_constructor then
    return class_name .. "::" .. class_name .. decl.params .. "\n{\n}"
  end
  if decl.is_destructor then
    return class_name .. "::~" .. class_name .. decl.params .. "\n{\n}"
  end
  local qualifiers = ""
  if decl.is_virtual then
    qualifiers = qualifiers .. " virtual"
  end
  local func_def = decl.return_type .. " " .. class_name .. "::" .. decl.func_name .. decl.params
  func_def = func_def .. "\n{\n}"
  return func_def
end

local function find_insert_point(lines)
  local last_include = 0
  for i, line in ipairs(lines) do
    if line:match("^%s*#include") then
      last_include = i
    end
  end
  if last_include > 0 then
    return last_include + 1
  end
  return #lines + 1
end

local function create_implementation()
  local file_path = ""
  local ok = pcall(function() file_path = editor.file_path() end)
  if not ok or not file_path or file_path == "" then
    ttt.notify("Create Implementation: no active file", "warn")
    return
  end
  local is_header = file_path:match("%.h$") or file_path:match("%.hpp$")
  if not is_header then
    ttt.notify("Create Implementation: not a header file", "warn")
    return
  end
  local line = editor.current_line()
  if not line or line == "" then
    ttt.notify("Create Implementation: no line at cursor", "warn")
    return
  end
  local decl = parse_declaration(line)
  if not decl then
    ttt.notify("Create Implementation: not a function declaration", "warn")
    return
  end
  local source_path = find_source_file(file_path)
  if not source_path then
    ttt.notify("Create Implementation: could not determine source file", "warn")
    return
  end
  local header_name = file_path:match("([^/]+)$")
  local source_lines = {}
  if file_exists(source_path) then
    local content = sys.exec("cat", { source_path })
    if content and content.exit_code == 0 then
      for line in (content.stdout or ""):gmatch("[^\n]+") do
        table.insert(source_lines, line)
      end
    end
  else
    table.insert(source_lines, '#include "' .. header_name .. '"')
  end
  local header_path_pattern = file_path:match("([^/]+)$")
  local has_include = false
  for _, line in ipairs(source_lines) do
    if line:match("#include.*" .. header_path_pattern:gsub("%.", "%%.")) then
      has_include = true
      break
    end
  end
  if not has_include then
    table.insert(source_lines, 1, '#include "' .. header_name .. '"')
  end
  local class_name = file_path:match("([^/]+)%.h$") or file_path:match("([^/]+)%.hpp$")
  local definition = generate_definition(decl, class_name)
  local insert_point = find_insert_point(source_lines)
  local def_lines = {}
  for def_line in definition:gmatch("[^\n]+") do
    table.insert(def_lines, def_line)
  end
  for i, def_line in ipairs(def_lines) do
    table.insert(source_lines, insert_point + i - 1, def_line)
  end
  local content = table.concat(source_lines, "\n") .. "\n"
  local tmp_file = "/tmp/create_impl_" .. os.time() .. ".cpp"
  local hex = ""
  for i = 1, #content do
    hex = hex .. string.format("%02x", string.byte(content, i))
  end
  sys.exec("bash", { "-c", "echo '" .. hex .. "' | xxd -r -p > " .. tmp_file })
  sys.exec("cp", { tmp_file, source_path })
  os.remove(tmp_file)
  ttt.notify("Created implementation in " .. source_path, "info")
  ttt.open_file(source_path)
end

local function run_script(script, args, result_handler)
  local script_args = { script }
  for _, a in ipairs(args) do
    table.insert(script_args, a)
  end
  sys.exec_async("bash", script_args, function(result)
    local stdout = (result.stdout or ""):gsub("%s+$", "")
    local stderr = (result.stderr or ""):gsub("%s+$", "")
    if stdout ~= "" then
      for line in stdout:gmatch("[^\n]+") do
        build_log(line)
      end
    end
    if stderr ~= "" then
      for line in stderr:gmatch("[^\n]+") do
        build_log(line)
      end
    end
    if result.exit_code == 0 then
      build_log("--- Build succeeded ---")
    else
      build_log("--- Build failed (exit " .. result.exit_code .. ") ---")
    end
    if result_handler then
      result_handler(stdout, stderr, result.exit_code)
    end
  end)
end

local function get_file_and_root()
  local file_path = ""
  local ok = pcall(function() file_path = editor.file_path() end)
  if not ok or not file_path or file_path == "" then
    ttt.notify("DevTools: no active file", "warn")
    return nil, nil
  end
  local root = find_project_root(file_path) or ""
  if root == "" then
    ttt.notify("DevTools: no project root found for " .. file_path, "warn")
  end
  return file_path, root
end

local commands = {}

-- Switch header/source
for _, action in ipairs(actions) do
  local cmd_id = "devtools." .. action.id
  local captured_action = action
  table.insert(commands, {
    id = cmd_id,
    title = action.title,
    handler = function()
      local file_path, project_root = get_file_and_root()
      if not file_path then return end
      local script = plugin_dir .. "/" .. captured_action.script
      sys.exec_async("bash", { script, file_path, project_root }, function(result)
        if result.exit_code == 0 then
          local target = (result.stdout or ""):gsub("%s+$", ""):match("^(.+)$")
          if target and target ~= file_path then
            ttt.open_file(target)
          else
            ttt.notify("No matching header/source found", "warn")
          end
        else
          ttt.notify("Switch failed", "error")
        end
      end)
    end,
  })
end

-- Create implementation command
table.insert(commands, {
  id = "devtools.create-implementation",
  title = "DevTools: Create Implementation",
  handler = create_implementation,
})

-- Build profiles
local profiles = {
  { id = "linux-debug", label = "Linux Debug", generator = "Ninja Multi-Config", buildType = "Debug", buildDir = "build/linux-debug" },
  { id = "linux-release", label = "Linux Release", generator = "Ninja Multi-Config", buildType = "Release", buildDir = "build/linux-release" },
  { id = "windows-debug", label = "Windows Debug", generator = "Ninja Multi-Config", buildType = "Debug", buildDir = "build/windows-debug" },
  { id = "windows-release", label = "Windows Release", generator = "Ninja Multi-Config", buildType = "Release", buildDir = "build/windows-release" },
  { id = "custom", label = "Custom (current config)", generator = nil, buildType = nil, buildDir = nil },
}

local function apply_profile(profile)
  if profile.generator then build_config.generator = profile.generator end
  if profile.buildType then build_config.buildType = profile.buildType end
  if profile.buildDir then build_config.buildDir = profile.buildDir end
  ttt.notify("Profile: " .. profile.label .. " (" .. build_config.generator .. " " .. build_config.buildType .. ")", "info")
end

-- Build profile drawer
table.insert(commands, {
  id = "devtools.configure-build",
  title = "DevTools: Configure Build Profile",
  handler = function()
    ttt.open_drawer({
      width = 45,
      min_width = 30,
      side = "right",
      render = function(panel)
        panel:title("Build Configuration")
        panel:label({ text = "Current: " .. build_config.generator .. " " .. build_config.buildType, style = "default" })
        panel:label({ text = "Build Dir: " .. build_config.buildDir, style = "muted" })
        panel:divider()
        panel:label({ text = "Quick Profiles", style = "muted" })
        local items = {}
        for _, p in ipairs(profiles) do
          local badge = ""
          if p.buildType == build_config.buildType and (p.buildDir == build_config.buildDir or not p.buildDir) then
            badge = "active"
          end
          table.insert(items, { id = p.id, label = p.label, badge = badge })
        end
        panel:list({
          items = items,
          on_select = function(node)
            for _, p in ipairs(profiles) do
              if p.id == node.id then
                apply_profile(p)
                panel:redraw()
                break
              end
            end
          end,
        })
        panel:divider()
        panel:label({ text = "Settings", style = "muted" })
        panel:keyvalue({
          { key = "Generator", value = build_config.generator },
          { key = "Build Type", value = build_config.buildType },
          { key = "Build Dir", value = build_config.buildDir },
          { key = "Extra Args", value = build_config.extraArgs ~= "" and build_config.extraArgs or "(none)" },
        })
      end,
    })
  end,
})

-- Profile switch commands
for _, profile in ipairs(profiles) do
  local captured = profile
  table.insert(commands, {
    id = "devtools.profile-" .. profile.id,
    title = "DevTools: Profile - " .. profile.label,
    handler = function()
      apply_profile(captured)
    end,
  })
end

-- Build commands
local build_actions = {
  { id = "build-configure-profile", title = "DevTools: Configure (Current Profile)", script = "scripts/build-configure.sh" },
  { id = "build-compile-profile", title = "DevTools: Build (Current Profile)", script = "scripts/build-compile.sh" },
  { id = "build-clean-profile", title = "DevTools: Clean (Current Profile)", script = "scripts/build-clean.sh" },
  { id = "build-run-profile", title = "DevTools: Run (Current Profile)", script = "scripts/build-run.sh" },
}

for _, action in ipairs(build_actions) do
  local cmd_id = "devtools." .. action.id
  local captured_action = action
  table.insert(commands, {
    id = cmd_id,
    title = action.title,
    handler = function()
      local file_path, project_root = get_file_and_root()
      if not file_path then return end
      build_clear()
      local script = plugin_dir .. "/" .. captured_action.script
      run_script(script, { file_path, project_root }, function(stdout, stderr, exit_code)
        if exit_code == 0 then
          ttt.notify("Build succeeded", "info")
        else
          ttt.notify("Build failed (exit " .. exit_code .. ")", "error")
        end
      end)
    end,
  })
end

-- Clear build output command
table.insert(commands, {
  id = "devtools.build-clear",
  title = "DevTools: Clear Build Output",
  handler = function()
    build_lines = {}
    if build_panel then
      build_panel:redraw()
    end
    ttt.notify("Build output cleared", "info")
  end,
})

-- Copy build output command
table.insert(commands, {
  id = "devtools.build-copy",
  title = "DevTools: Copy Build Output",
  handler = function()
    if #build_lines == 0 then
      ttt.notify("No build output to copy", "warn")
      return
    end
    local text = table.concat(build_lines, "\n")
    -- encode as hex to avoid shell escaping issues
    local hex = ""
    for i = 1, #text do
      hex = hex .. string.format("%02x", string.byte(text, i))
    end
    local cmd = "echo '" .. hex .. "' | xxd -r -p | wl-copy 2>/dev/null || echo '" .. hex .. "' | xxd -r -p | xclip -selection clipboard 2>/dev/null"
    local result = sys.exec("bash", {"-c", cmd})
    if result and result.exit_code == 0 then
      ttt.notify("Build output copied to clipboard (" .. #build_lines .. " lines)", "info")
    else
      ttt.notify("Copy failed (no clipboard tool found?)", "error")
    end
  end,
})

local function build_render(panel)
  build_panel = panel
  if #build_lines == 0 then
    panel:label({ text = "No build output yet.", style = "muted" })
    return
  end
  local _, h = panel:size()
  local visible = h - 2
  if visible < 1 then visible = 1 end
  local total = #build_lines
  -- clamp scroll offset (0 = bottom, negative = scrolled up)
  local max_scroll = math.max(0, total - visible)
  if -build_scroll > max_scroll then
    build_scroll = -max_scroll
  end
  local start = total + build_scroll - visible + 1
  if start < 1 then start = 1 end
  if build_scroll ~= 0 then
    panel:label({ text = "(scrolled up, " .. (-build_scroll) .. " lines)  PgUp/PgDn to scroll", style = "muted" })
  end
  for i = start, math.min(start + visible - 1, total) do
    local line = build_lines[i]
    local style = "default"
    if line:match("^--- Build failed") then
      style = "error"
    elseif line:match("^--- Build succeeded") then
      style = "info"
    elseif line:match("^--- Build started") then
      style = "muted"
    end
    panel:label({ text = line, style = style })
  end
end

local function build_on_event(ev)
  if ev.type == "mouse" then
    if ev.button == "wheel_up" then
      build_scroll = math.max(build_scroll - 3, -math.max(0, #build_lines - 10))
      build_panel:redraw()
      return true
    elseif ev.button == "wheel_down" then
      build_scroll = math.min(build_scroll + 3, 0)
      build_panel:redraw()
      return true
    end
  elseif ev.type == "key" then
    local _, h = build_panel:size()
    local visible = h - 2
    if visible < 1 then visible = 1 end
    if ev.key == "PgUp" then
      build_scroll = math.max(build_scroll - visible, -math.max(0, #build_lines - 10))
      if build_panel then build_panel:redraw() end
      return true
    elseif ev.key == "PgDn" then
      build_scroll = math.min(build_scroll + visible, 0)
      if build_panel then build_panel:redraw() end
      return true
    elseif ev.key == "Up" then
      build_scroll = math.max(build_scroll - 1, -math.max(0, #build_lines - 10))
      if build_panel then build_panel:redraw() end
      return true
    elseif ev.key == "Down" then
      build_scroll = math.min(build_scroll + 1, 0)
      if build_panel then build_panel:redraw() end
      return true
    end
  end
  return false
end

ttt.register({
  commands = commands,
  bottom = {
    title = "Build",
    render = build_render,
    on_event = build_on_event,
  },
})

ttt.log("devtools: loaded with " .. #commands .. " commands")
