local zipkin = require "kong.plugins.zipkin.zipkin"
local utils = require "kong.tools.utils"

local log = ngx.log

local ERROR = ngx.ERR
local DEBUG = ngx.DEBUG

-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.

-- assert(ngx.get_phase() == "timer", "The world is coming to an end!")


-- load the base plugin object and create a subclass
local plugin = require("kong.plugins.base_plugin"):extend()

-- constructor
function plugin:new()
  plugin.super.new(self, "zipkin")
end

---[[ runs in the 'access_by_lua_block'
function plugin:access(plugin_conf)
  math.randomseed()
  plugin.super.access(self)
  zipkin.process_request(plugin_conf, ngx.req, ngx.ctx)

end --]]

local function timer_callback(premature, plugin_conf, trace)
  ngx.log(ngx.DEBUG, 'timer')
  if premature then
    ngx.log(ngx.DEBUG, 'premature')
    -- Kong is shutting down, don't worry about posting trace
    return
  end

  if not trace then
    ngx.log(ngx.DEBUG, 'not trace')
    -- not sampling, nothing to do
    return
  end

  zipkin.send_trace(plugin_conf, trace)

end

---[[ runs in the 'log_by_lua_block'
function plugin:log(plugin_conf)
  plugin.super.access(self)

  local trace = zipkin.prepare_trace(plugin_conf, ngx.req, ngx.ctx, ngx.status)

  -- Doing the expensive work in a timer callback
  -- See https://github.com/openresty/lua-nginx-module/#cosockets-not-available-everywhere

  ngx.log(ngx.DEBUG, 'set timer')

  local ok, err = ngx.timer.at(0, timer_callback, plugin_conf, trace)
  if not ok then
      ngx.log(ngx.ERR, "failed to create the timer: ", err)
      return
  end

end --]]


-- fine to execute this after everything else
-- and don't want to waste time executing it for unauthenticated requests
plugin.PRIORITY = 1

-- return our plugin object
return plugin
