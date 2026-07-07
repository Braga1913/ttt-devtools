local ttt = require("ttt")
local sys = require("ttt.system")
local editor = require("ttt.editor")
local fs = require("ttt.fs")
local json = require("ttt.json")

local plugin_dir = ttt.plugin_dir()
local config_path = plugin_dir .. "/config.json"
local build_config_path = plugin_dir .. "/build-config.json"

local function load_json(path)
  local content = fs.read(path)
  if not content then return nil end
  local data, err = json.decode(content)
  if not data then
    ttt.log("error", "devtools: failed to parse " .. path .. ": " .. (err or ""))
    return nil
  end
  return data
end

local function save_json(path, data)
  local ok, err = pcall(function()
    fs.write(path, json.encode(data))
  end)
  if not ok then
    ttt.log("error", "devtools: failed to save " .. path .. ": " .. (err or ""))
  end
  return ok
end

local function load_config()
  return load_json(config_path)
end

local function load_build_config()
  return load_json(build_config_path) or {
    generator = "Ninja",
    buildType = "Debug",
    buildDir = "build",
    extraArgs = "",
    buildDirs = {},
  }
end

local function find_project_root(file_path)
  if not file_path or file_path == "" then return nil end
  local dir = file_path:match("^(.+)/[^/]+$")
  if not dir then return nil end
  local markers = { "CMakeLists.txt", "Makefile", ".git", "compile_commands.json", "Cargo.toml", "package.json" }
  local search = dir
  for _ = 1, 30 do
    for _, marker in ipairs(markers) do
      if fs.exists(search .. "/" .. marker) then
        return search
      end
    end
    local parent = search:match("^(.+)/[^/]+$")
    if not parent or parent == search then break end
    search = parent
  end
  return dir
end

local function run_script(script, args, result_handler)
  local all_args = {}
  for _, a in ipairs(args) do
    table.insert(all_args, a)
  end
  sys.exec_async("bash", { script, table.unpack(all_args) }, function(result)
    if result.exit_code == 0 then
      local output = (result.stdout or ""):gsub("%s+$", "")
      if output ~= "" then
        result_handler(output)
      else
        ttt.notify("Done", "info")
      end
    else
      local msg = (result.stderr or ""):gsub("%s+$", "")
      ttt.notify("Failed: " .. (msg ~= "" and msg or "exit " .. result.exit_code), "error")
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
  return file_path, find_project_root(file_path) or ""
end

-- Build config panel state
local build_config = load_build_config()

local commands = {}
local keybindings = {}

-- Register script-based actions from config.json
local cfg = load_config()
if cfg and cfg.actions then
  for _, action in ipairs(cfg.actions) do
    local cmd_id = "devtools." .. action.id
    local captured_action = action
    table.insert(commands, {
      id = cmd_id,
      title = action.title,
      handler = function()
        local file_path, project_root = get_file_and_root()
        if not file_path then return end
        local script = plugin_dir .. "/" .. captured_action.script
        run_script(script, { file_path, project_root }, function(output)
          if captured_action.id == "switch-header" then
            local target = output:match("^(.+)$")
            if target and target ~= file_path then
              ttt.open_file(target)
            else
              ttt.notify("No matching header/source found", "warn")
            end
          else
            ttt.notify(output, "info")
          end
        end)
      end,
    })
    if action.key then
      table.insert(keybindings, { key = action.key, command = cmd_id })
    end
  end
end

-- Build profile actions
local profiles = {
  { id = "linux-debug", label = "Linux Debug", generator = "Ninja", buildType = "Debug", buildDir = "build/linux-debug" },
  { id = "linux-release", label = "Linux Release", generator = "Ninja", buildType = "Release", buildDir = "build/linux-release" },
  { id = "windows-debug", label = "Windows Debug", generator = "Ninja", buildType = "Debug", buildDir = "build/windows-debug" },
  { id = "windows-release", label = "Windows Release", generator = "Ninja", buildType = "Release", buildDir = "build/windows-release" },
  { id = "custom", label = "Custom (current config)", generator = nil, buildType = nil, buildDir = nil },
}

local function apply_profile(profile)
  if profile.generator then build_config.generator = profile.generator end
  if profile.buildType then build_config.buildType = profile.buildType end
  if profile.buildDir then build_config.buildDir = profile.buildDir end
  save_json(build_config_path, build_config)
  ttt.notify("Profile: " .. profile.label .. " (" .. build_config.generator .. " " .. build_config.buildType .. ")", "info")
end

-- Configure build command
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
          table.insert(items, {
            id = p.id,
            label = p.label,
            badge = badge,
          })
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

-- Switch profile command
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

-- Build commands that pass profile info
local build_actions = {
  { id = "build-configure-profile", title = "DevTools: Configure (Current Profile)", key = "ctrl+k c", script = "scripts/build-configure.sh" },
  { id = "build-compile-profile", title = "DevTools: Build (Current Profile)", key = "ctrl+k b", script = "scripts/build-compile.sh" },
  { id = "build-clean-profile", title = "DevTools: Clean (Current Profile)", key = "ctrl+k x", script = "scripts/build-clean.sh" },
  { id = "build-run-profile", title = "DevTools: Run (Current Profile)", key = "ctrl+k r", script = "scripts/build-run.sh" },
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
      local script = plugin_dir .. "/" .. captured_action.script
      run_script(script, { file_path, project_root }, function(output)
        ttt.notify(output, "info")
      end)
    end,
  })
  if action.key then
    table.insert(keybindings, { key = action.key, command = cmd_id })
  end
end

ttt.register({
  commands = commands,
  keybindings = keybindings,
})

ttt.log("devtools: loaded with " .. #commands .. " commands and " .. #keybindings .. " keybindings")
