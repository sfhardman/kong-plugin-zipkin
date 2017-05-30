local Errors = require "kong.dao.errors"

return {
  no_consumer = false, -- this plugin is available on APIs as well as on Consumers,
  fields = {
    -- Describe your plugin's configuration's schema here.
    zipkin_url = { required = true, type = "url" },
    sample_once_every_n_requests = { type = "number", default = 1000 },
    simulate_server = { type = "boolean", default = false },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if (plugin_t.sample_once_every_n_requests < 0) then
      return false, Errors.schema "sample_once_every must be greater than or equal to zero. To disable sampling set sample_once_every = 0"
    end
    return true
  end
}
