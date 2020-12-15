# New Relic Infinite Tracing for Ruby Agent Release Notes #

  ## v6.15.0
  * Adds data from the agents connect response `request_headers_map` to the metadata for the connection to the infinite trace observer.
  
  ## v6.12.0

  * Implements restarting gRPC stream when server responds with OK response and no error.

  ## v6.11.0

  * Initial Release!
  * Implements gRPC protocol for communicating with Trace Observers