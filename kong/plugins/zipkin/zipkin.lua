local utils = require "kong.tools.utils"
local cjson = require "cjson"
local http = require('resty.http')

local zipkin_api_path = '/api/v1/spans'

local _M = {}

local function inject(req, zipkin_trace)
  req.set_header("X-B3-TraceId", zipkin_trace.trace_id)
  req.set_header("X-B3-SpanId", zipkin_trace.span_id)
  req.set_header("X-B3-Sampled", tostring(zipkin_trace.sampled))
  if zipkin_trace.parent_span_id then
    req.set_header("X-B3-ParentSpanId", tostring(zipkin_trace.parent_span_id))
  end
end

function dump(o)
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
  if plugin_conf.sample_once_every_n_requests == 0 then
    return false
  elseif plugin_conf.sample_once_every_n_requests == 1 then
    return true
  else
    return math.random(1, plugin_conf.sample_once_every_n_requests) == 1
  end
end

local function random_string_of_len(length)
  if length > 32 then
    ngx.log(ngx.ERROR, "maximum random_string_of_len length exceeded", length)
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

  if headers['X-B3-TraceId'] and headers['X-B3-SpanId'] then
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
      trace_id = random_string_of_len(32),
      span_id = random_string_of_len(16),
      simulate_client = true,
      simulate_server = plugin_conf.simulate_server,
      sampled = sampled
    }
  end

  if sampled and not plugin_conf.simulate_server then
    inject(req, zipkin_trace)
  end

  ctx.zipkin_trace = zipkin_trace

end

function _M.prepare_trace(plugin_conf, req, ctx, status)
  local zipkin_trace = ctx.zipkin_trace
  local headers = req.get_headers()

  if (not zipkin_trace) or (not zipkin_trace.sampled)
    or not (zipkin_trace.simulate_client or zipkin_trace.simulate_server) then
    return
  end

  ngx.update_time() -- update nginx cached timestamp
  local now = ngx.now()

  -- cjson will try to use scientific format, which we don't want
  local start_time = string.format("%.f", math.floor(1000000 * ngx.req.start_time()))
  local end_time = string.format("%.f", math.floor(1000000 * now))

  local duration = math.floor(1000000 * (now - ngx.req.start_time()))

  local formatted_trace = {
      {
      id = zipkin_trace.span_id,
      parentId = zipkin_trace.parent_span_id,
      traceId = zipkin_trace.trace_id,
      timestamp = start_time,
      name = ngx.var.request_uri,
      duration = duration,
      annotations = {}
    }
  }

  if zipkin_trace.simulate_client then

    local client_endpoint = {
      serviceName = headers["x-consumer-username"] or ngx.var.remote_addr,
      ipv4 = ngx.var.remote_addr,
      port = ngx.var.remote_port,
    }
    -- client send
    table.insert(formatted_trace[1].annotations, {
      value = 'cs',
      timestamp = start_time,
      endpoint = client_endpoint
    })
    -- client receive
    table.insert(formatted_trace[1].annotations, {
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
    table.insert(formatted_trace[1].annotations, {
      value = 'sr',
      timestamp = start_time,
      endpoint = server_endpoint
    })
    -- server send
    table.insert(formatted_trace[1].annotations, {
      value = 'ss',
      timestamp = end_time,
      endpoint = server_endpoint
    })
  end

  return formatted_trace

end

function _M.send_trace(plugin_conf, trace)
  ngx.log(ngx.DEBUG, 'sending trace')

  local encoded_trace = cjson.encode(trace)

  ngx.log(ngx.DEBUG, encoded_trace)

  local client = http.new()

  local res, err = client:request_uri(plugin_conf.zipkin_url .. zipkin_api_path,
    {
      method = "POST",
      body = encoded_trace,
      headers = {
        ["Content-Type"] = "application/json",
    }
  })
  if not res then
    ngx.log(ngx.ERR, err)
  elseif (res.status ~= 202) and (res.status ~= 200) then
    ngx.log(ngx.ERR, "Unexpected response from Zipkin: " .. res.status .. " - " .. res.reason .. ": " .. res.body)
  end
end

return _M
