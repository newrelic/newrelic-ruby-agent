## flaky_proxy

`flaky_proxy` helps you simulate failures in an HTTP service in a configurable
way, without modifying the underlying service. Specifically, you can use it as a proxy in front of the collector in order to simulate bad network conditions and see how your agent responds.

## Usage

```
flaky_proxy -l 8888 -t 8081 <rules_file>
```

This tells `flaky_proxy` to listen on port 8888 for incoming connections, and
forward them on to port 8081 of localhost. If you'd like to specify the bind
host or target host, you can do that too:

```
flaky_proxy -l localhost:8888 -t collector.newrelic.com:80 <rules_file>
```

This example will instruct `flaky_proxy` to listen on port 8888 of localhost,
and forward data to port 80 of `collector.newrelic.com`.

### Rules file format

The `<rules_file>` file is a Ruby file written using a simple DSL, to tell the
tool how to handle incoming traffic. It consists of a series of `match`
expressions, each with an accompanying block to be executed in order to
determine how to deal with a matching HTTP request.

Each incoming HTTP request is evaluated against these match expressions, and the
first matching expression is chosen. Matching is done by matching the request
URL of incoming requests against a regular expression given as the first
argument to `match`.

In the body of the block passed to `match`, you may specify one of the following
actions:

* `pass` - pass the request through untouched to the target server
* `respond` - respond with a canned response, without talking to the target server
* `delay` - sleep for a specified number of seconds before passing the request through to the target server
* `close` - close the TCP connection without sending a response

Any incoming request that does not match any of the rules specified in your rules file will be treated as an implicit `pass`.

A few examples to make things more concrete:

Close the TCP connection without sending an HTTP response for any request with `foo` in the URL:

```
match /foo/ { close }
```

Respond with a 503 status code to 50% of incoming requests matching `metric_data`:

```
match /metric_data/ do |req|
  if rand > 0.5
    pass
  else
    respond :status => 503
  end
end
```

Respond with a 200 OK status code and a custom body to requests matching `get_agent_commands`:

```
match /get_agent_commands/ do |req|
  respond :body => '{ "error": "bad news" }'
end
```

Delay all requests matching `slowdown` by 10 seconds:

```
match /slowdown/ do
  delay 10
end
```

The rules file will be watched for changes automatically, and the rules will
be potentially reloaded each time the proxy accepts a new connection.

### Available Actions

#### pass

Pass the request on to the backend server without modification.

#### close

Close the TCP connection from the client before forwarding it on to the backend server.

#### respond(response_spec)

Respond to the client with a canned response, instead of forwarding the request on to the backend server. `response_spec` should be a `Hash` describing the canned response to be sent to the client. Recognized keys in the `response_spec` are:

* `:status` - A `Fixnum` with the HTTP status code. Default: 200.
* `:headers` - A `Hash` with response headers. Default: the `Content-Length` header will be automatically set based on the response body length.
* `:body` - A `String` containing the HTTP response body. Default = `''`.

#### delay(amount)

Delay for `amount` seconds before forwarding the request on to the backend server.

### Sequences

Sometimes it's useful to be able to easily express a sequence of actions to be
taken upon matching a particular rule. To facilitate this, `flaky_proxy`
supports defining actions using the `sequence` statement.

For example:

```
seq = sequence do
  pass
  respond :status => 503
  respond :status => 404
end

match /connect/, seq
```

This will cause the first request matching `connect` to be passed through to the
target server, the second to be responded to with a 503 status, and the third to
be responded to with a 404 status. Any subsequent requests will get the default
action of being passed through to the target server.

Note that the block passed to `sequence` is evaluated only once, when the rules
file is loaded, instead of once per request (as a block passed to `match` would
be).

## Caveats

* Entirely single-threaded and not evented, handles only one connection at a time
* Almost certainly doesn't handle string encodings correctly

## Bugs? Feature Requests?

Send 'em in! Find Ben Weintraub in the 'Ruby Agent Dev' room, or via email.