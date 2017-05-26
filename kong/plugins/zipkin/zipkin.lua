local utils = require "kong.tools.utils"
local cjson = require "cjson"
local log = ngx.log

local ERROR = ngx.ERR
local DEBUG = ngx.DEBUG

local _M = {}

local function inject(req, zipkin_trace)
  req.set_header("X-B3-TraceId", zipkin_trace.trace_id)
  req.set_header("X-B3-SpanId", zipkin_trace.span_id)
  req.set_header("X-B3-Sampled", tostring(zipkin_trace.sampled))
  if zipkin_trace.parent_span_id then
    req.set_header("X-B3-ParentSpanId", tostring(zipkin_trace.parent_span_id))
  end
end

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local function random_sample(plugin_conf)
  return plugin_conf.sample
end

local function random_string(length)
  if length > 32 then
    log(ERROR, "maximum random_string length exceeded", length)
    -- not sure how to propagate the error....
    return nil
  end
  return string.sub(utils.random_string(), 1, length)
end

function _M.process_request(plugin_conf, req, ctx)
  local headers = req.get_headers()
  local sampled = (headers['X-B3-Sampled'] and (headers['X-B3-Sampled'] == 1))
    or (headers['X-B3-Flags'] and (headers['X-B3-Flags'] == 1))

  sampled = sampled or random_sample(plugin_conf)

  local zipkin_trace = nil

  if headers['X-B3-TraceId'] and headers['X-B3-SpanId'] and headers['X-B3-ParentSpanId'] then
    zipkin_trace = {
      trace_id = headers['X-B3-TraceId'],
      span_id = headers['X-B3-SpanId'],
      parent_span_id = headers['X-B3-ParentSpanId'],
      simulate_client = false,
      simulate_server = plugin_conf.simulate_server,
      sampled = sampled
    }
  elseif sampled then
    zipkin_trace = {
      trace_id = random_string(32),
      span_id = random_string(16),
      simulate_client = true,
      simulate_server = plugin_conf.simulate_server,
      sampled = sampled
    }
  end

  if sampled and not plugin_conf.simulate_server then
    inject(req, zipkin_trace)
  end

  ctx.zipkin_trace = zipkin_trace

  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, dump(plugin_conf))
  ngx.log(ngx.DEBUG, ">>>>")
  -- ngx.log(ngx.DEBUG, dump(req.get_headers()))
  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, dump(zipkin_trace))
  ngx.log(ngx.DEBUG, ">>>>")


end

function _M.flush_trace(plugin_conf, req, ctx, status)
  local zipkin_trace = ctx.zipkin_trace
  local headers = req.get_headers()

  if (not zipkin_trace) or (not zipkin_trace.sampled)
    or not (zipkin_trace.simulate_client or zipkin_trace.simulate_server) then
    return
  end

  -- cjson will try to use scientific format, which we don't want
  local start_time = string.format("%.f", math.floor(1000000 * ngx.req.start_time()))
  local end_time = string.format("%.f", math.floor(1000000 * ngx.now()))

  local duration = math.floor(1000000 * (ngx.now() - ngx.req.start_time()))

  local formatted_trace = {
    id = zipkin_trace.span_id,
    parentId = zipkin_trace.parent_span_id,
    traceId = zipkin_trace.trace_id,
    timestamp = end_time,
    name = ngx.var.request_uri,
    duration = duration,
    annotations = {}
  }

  if zipkin_trace.simulate_client then

    local client_endpoint = {
      serviceName = headers["x-consumer-username"] or ngx.var.remote_addr,
      ipv4 = ngx.var.remote_addr,
      port = ngx.var.remote_port,
    }
    -- client send
    table.insert(formatted_trace.annotations, {
      value = 'cs',
      timestamp = start_time,
      endpoint = client_endpoint
    })
    -- client receive
    table.insert(formatted_trace.annotations, {
      value = 'cr',
      timestamp = end_time,
      endpoint = client_endpoint
    })
  end

  if zipkin_trace.simulate_server then

    local server_endpoint = {
      serviceName = ctx.api.upstream_url
    }
    -- server receive
    table.insert(formatted_trace.annotations, {
      value = 'sr',
      timestamp = start_time,
      endpoint = server_endpoint
    })
    -- server send
    table.insert(formatted_trace.annotations, {
      value = 'ss',
      timestamp = end_time,
      endpoint = server_endpoint
    })
  end

  local encoded_trace = cjson.encode(formatted_trace)

  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, dump(encoded_trace))
  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, dump(ctx))
  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, ">>>>")
  ngx.log(ngx.DEBUG, dump(req.get_headers()))
  ngx.log(ngx.DEBUG, ">>>>")


end

return _M
