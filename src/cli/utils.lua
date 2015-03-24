--[[
Kong CLI utilities
 - Colorization
 - Logging
 - Disk I/O utils
 - nginx path/initialization
]]

local utils = require "kong.tools.utils"
local Object = require "classic"
local ansicolors = require "ansicolors"
local constants = require "kong.constants"

--
-- Colors
--
local colors = {}
for _, v in ipairs({"red", "green", "yellow"}) do
  colors[v] = function(str) return ansicolors("%{"..v.."}"..str.."%{reset}") end
end

--
-- Logging
--
local Logger = Object:extend()

function Logger:new(silent)
  self.silent = silent
end

function Logger:log(str)
  if not self.silent then
    print(str)
  end
end

function Logger:success(str)
  self:log(colors.green("[SUCCESS] ")..str)
end

function Logger:warn(str)
  self:log(colors.yellow("[WARNING] ")..str)
end

function Logger:error(str)
  self:log(colors.red("[ERROR] ")..str)
end

function Logger:error_exit(str)
  self:error(str)
  os.exit(1)
end

local logger = Logger()

local function get_infos()
  return { name = constants.NAME, version = constants.VERSION }
end

--
-- NGINX
--
local function is_openresty(path_to_check)
  local cmd = tostring(path_to_check).." -v 2>&1"
  local handle = io.popen(cmd)
  local out = handle:read()
  handle:close()
  local matched = out:match("^nginx version: ngx_openresty/") or out:match("^nginx version: openresty/")
  if matched then
    return path_to_check
  end
end

local function find_nginx()
  local nginx_bin = "nginx"
  local nginx_search_paths = {
    "/usr/local/openresty/nginx/sbin/",
    "/usr/local/opt/openresty/bin/",
    "/usr/local/bin/",
    "/usr/sbin/",
    ""
  }

  for i = 1, #nginx_search_paths do
    local prefix = nginx_search_paths[i]
    local to_check = tostring(prefix)..tostring(nginx_bin)
    if is_openresty(to_check) then
      return to_check
    end
  end
end

local function prepare_nginx_working_dir(kong_config)
  if kong_config.send_anonymous_reports then
    kong_config.nginx = "error_log syslog:server=kong-hf.mashape.com:61828 error;\n"..kong_config.nginx
  end

  -- Create nginx folder if needed
  local _, err = utils.path:mkdir(utils.path:join(kong_config.nginx_working_dir, "logs"))
  if err then
    logger:error_exit(err)
  end
  os.execute("touch "..utils.path:join(kong_config.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..utils.path:join(kong_config.nginx_working_dir, "logs", "access.log"))

  -- Extract nginx config to nginx folder
  utils.write_to_file(utils.path:join(kong_config.nginx_working_dir, constants.CLI.NGINX_CONFIG), kong_config.nginx)

  return kong_config.nginx_working_dir
end

local function get_luarocks_config_dir()
  local cfg = require "luarocks.cfg"
  local lpath = require "luarocks.path"
  local search = require "luarocks.search"
  local infos = get_infos()

  local tree_map = {}
  local results = {}

  for _, tree in ipairs(cfg.rocks_trees) do
    local rocks_dir = lpath.rocks_dir(tree)
    tree_map[rocks_dir] = tree
    search.manifest_search(results, rocks_dir, search.make_query(infos.name:lower(), nil))
  end

  local version
  for k, _ in pairs(results.kong) do
    version = k
  end

  local repo = tree_map[results.kong[version][1].repo]
  return lpath.conf_dir(infos.name:lower(), infos.version, repo)
end

local function get_kong_config_path(args_config)
  -- Use the rock's config if no config at default location
  if not utils.file_exists(args_config) then
    local kong_rocks_conf = utils.path:join(get_luarocks_config_dir(), "kong.yml")
    logger:warn("No config at: "..args_config.." using default config instead.")
    args_config = kong_rocks_conf
  end

  -- Make sure the configuration file really exists
  if not utils.file_exists(args_config) then
    logger:warn("No config at: "..args_config)
    logger:error_exit("Could not find a configuration file.")
  end

  logger:log("Using config: "..args_config.."\n")

  -- TODO: validate configuration
  --[[local status, res = pcall(require, "kong.dao."..config.database..".factory")
    if not status then
      cutils.logger:error("Wrong config")
      os.exit(1)
    end]]

  return args_config
end

return {
  path = utils.path,
  colors = colors,
  logger = logger,

  get_infos = get_infos,
  find_nginx = find_nginx,
  is_openresty = is_openresty,
  read_file = utils.read_file,
  retrieve_files = retrieve_files,
  file_exists = utils.file_exists,
  write_to_file = utils.write_to_file,
  get_kong_config_path = get_kong_config_path,
  prepare_nginx_working_dir = prepare_nginx_working_dir,
  load_configuration_and_dao = utils.load_configuration_and_dao
}
