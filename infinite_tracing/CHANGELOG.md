# New Relic Infinite Tracing for Ruby Agent Release Notes #

  ## v9.12.0

  * Pin google-protobuf dependency to < 4.0 due to compatibility issues with version 4+.

  ## v8.9.0

  * **Bugfix: Infinite Tracing hung on connection restart**

    Previously, when using infinite tracing, the agent would intermittently encounter a deadlock when attempting to restart the infinite tracing connection. This bug would prevent the agent from sending all data types, including non-infinite-tracing-related data. This change reworks how we restart infinite tracing to prevent potential deadlocks.

  ## v7.0.0
  * Bugfix: Fixes an intermittent bug where the agent was unable to start when infinite tracing was enabled. 

  ## v6.15.0
  * Adds data from the agents connect response `request_headers_map` to the metadata for the connection to the infinite trace observer.
  
  ## v6.12.0

  * Implements restarting gRPC stream when server responds with OK response and no error.

  ## v6.11.0

  * Initial Release!
  * Implements gRPC protocol for communicating with Trace Observers