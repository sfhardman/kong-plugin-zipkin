local Errors = require "kong.dao.errors"

return {
  no_consumer = false, -- this plugin is available on APIs as well as on Consumers,
  fields = {
    -- Describe your plugin's configuration's schema here.
    zipkin_url = { required = true, type = "url" },
    sample = { type = "boolean", default = false },
    sample_once_every = { type = "number", default = 1000 },
    simulate_server = { type = "boolean", default = false },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if (plugin_t.sample_once_every <= 0) then
      return false, Errors.schema "sample_once_every must be greater than zero. To disable sampling set sample = false"
    end
    return true
  end
}
