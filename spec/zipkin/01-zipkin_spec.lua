local helpers = require "spec.helpers"
local zipkin = require "kong.plugins.zipkin.zipkin"

local function mock_request(headers)
  local req = {}

  local headers_copy = {}

  for k, v in pairs(headers) do
    headers_copy[k] = v
  end

  function req.get_headers()
    return headers_copy
  end

  function req.set_header(name, value)
    headers_copy[name] = value
  end

  return req
end

local function process_request(headers, plugin_conf)
  local ctx = {}
  local req = mock_request(headers)
  zipkin.process_request(plugin_conf, req, ctx)
  return ctx, req
end

describe("zipkin core", function()

  describe("process_request", function()
    it("propagates the inbound B3 headers", function()

      local plugin_conf = {
        sample_once_every_n_requests = 1,
        simulate_server = false,
      }
      local headers = {
        ['X-B3-TraceId'] = '1234',
        ['X-B3-SpanId'] = '567'
      }

      local ctx, req = process_request(headers, plugin_conf)
)
      assert.equal(headers['X-B3-TraceId'], req.get_headers()['X-B3-TraceId'])
      assert.equal(headers['X-B3-SpanId'], req.get_headers()['X-B3-SpanId'])
    end)

    it("propagates the inbound B3 headers, including parent span ID", function()

      local plugin_conf = {
        sample_once_every_n_requests = 1,
        simulate_server = false,
      }
      local headers = {
        ['X-B3-TraceId'] = '1234',
        ['X-B3-SpanId'] = '567',
        ['X-B3-ParentSpanId'] = '980'
      }

      local ctx, req = process_request(headers, plugin_conf)

      assert.equal(headers['X-B3-TraceId'], req.get_headers()['X-B3-TraceId'])
      assert.equal(headers['X-B3-SpanId'], req.get_headers()['X-B3-SpanId'])
      assert.equal(headers['X-B3-ParentSpanId'], req.get_headers()['X-B3-ParentSpanId'])
    end)

    it("propagates new IDs when B3 headers are not supplied", function()

      local plugin_conf = {
        sample_once_every_n_requests = 1,
        simulate_server = false,
      }
      local headers = { }

      local ctx, req = process_request(headers, plugin_conf)

      assert.equal(ctx.zipkin_trace.trace_id, req.get_headers()['X-B3-TraceId'])
      assert.equal(ctx.zipkin_trace.span_id, req.get_headers()['X-B3-SpanId'])
    end)

  end)

end)
