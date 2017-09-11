# Kong Zipkin Plugin

This is a plugin for the [Kong](https://getkong.org/) API gateway to integrate with the [Zipkin](http://zipkin.io/) distributed tracing system.  It allows for some degree of Zipkin instrumentation of connections between systems where one or both ends can't be directly instrumented.

*This is proof of concept code, not production ready*

## Scenarios

### Simulate Server

    --------    ------    --------
    |client| -> |Kong| -> |server|
    --------    ------    --------
       |           |
       V           V
    --------    --------
    |Zipkin|    |Zipkin|
    --------    --------

Server cannot be instrumented, so Kong impersonates the server to Zipkin, continuing the trace propagated from the client in [B3 headers](https://github.com/openzipkin/b3-propagation)

### Simulate Client

    --------    ------    --------
    |client| -> |Kong| -> |server|
    --------    ------    --------
                  |           |
                  V           V
                --------    --------
                |Zipkin|    |Zipkin|
                --------    --------

Client cannot be instrumented, so Kong impersonates the client to Zipkin, initiating a new trace and propagating the B3 headers to the server

### Simulate Client and server

    --------    ------    --------
    |client| -> |Kong| -> |server|
    --------    ------    --------
                  |           
                  V           
                --------
                |Zipkin|
                --------

Neither client nor server can be instrumented, so Kong impersonates both ends of the communication to Zipkin

## Usage

1. Requires Kong and Zipkin instances to exist
2. Install the plugin on Kong:

    Obtain plugin:

    `$ git clone git@github.com:sfhardman/kong-plugin-zipkin.git /opt/plugins/kong-plugin-zipkin`
    
    Edit kong.conf:

        lua_package_path = /opt/plugins/kong-plugin-zipkin/?.lua;;

        custom_plugins = zipkin

    Restart Kong
3. Add the plugin to an API:

        $ curl -i -X POST \
          --url http://localhost:8001/apis/ \
          --data 'name=example-api' \
          --data 'hosts=example.com' \
          --data 'upstream_url=http://httpbin.org'

        $ curl -i -X POST \
          --url http://localhost:8001/apis/example-api/plugins/ \
          --data 'name=zipkin' \
          --data 'config.zipkin_url=http://10.0.0.99:9411' \
          --data 'config.sample_once_every_n_requests=1' \
          --data 'config.simulate_server=false'

        # a Kong restart appears to be needed here to cause the plugin to register

        $ curl -i -X GET \
          --url http://localhost:8000/headers \
          --header 'Host: example.com'

        HTTP/1.1 200 OK
        ...

         {
           "headers": {
             "Accept": "*/*",
             "Connection": "close",
             "Host": "httpbin.org",
             "User-Agent": "curl/7.47.0",
             "X-B3-Sampled": "true",
             "X-B3-Spanid": "cf7fffa067b446fe",
             "X-B3-Traceid": "c14cad40e0e24232b94a2a25db2a0ca9"
           }
         }

## Parameters

* zipkin_url: Base URL of the Zipkin instance (protocol://host:port)
* sample_once_every_n_requests: Causes the plugin to sample the request at this frequency.  Set to zero to never sample.  Set to one to always sample.  Regardless of this setting the plugin will always sample if it receives B3 headers indicating the caller is sampling (X-B3-Sampled == 1 or X-B3-Flags == 1)
* simulate_server: Tells the plugin to impersonate the server which will process the request (Kong upstream_url).  Note that Kong will impersonate the client automatically if it is sampling and there are no B3 headers from the client

## Limitations
* Uses Zipkin REST API, not gRPC
* Kong random number generator seeding does not work correctly when running with KONG_LUA_CODE_CACHE=false, and this results in all generated trace / span ID's being the same.  To workaround for development uncomment the randomseed line in handler.lua (function plugin:access)
* Only millisecond precision timing, not microsecond as preferred by Zipkin
