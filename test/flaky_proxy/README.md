## flaky_proxy

`flaky_proxy` helps you simulate failures in an HTTP service in a configurable
way, without modifying the underlying service.

## Usage

```
flaky_proxy -l 8888 -t 8081 rules
```

Where `rules` is a file with the following content:

```
match /foo/ { close }

match /bar/ do
  close
  pass
end

match /baz/ do
  respond :status => 503
  respond :body => '{ "error": "bad things happened" }'
  pass
end

match /slowdown/ do
  delay 10
end
```

This will instruct `flaky_proxy` to listen for incoming connections on port
8888, and forward HTTP requests recieved on this port on to the server running
on localhost on port 8081.

Incoming requests will be evaluated against the match rules specified in the
`rules` file that you pass to `flaky_proxy`. Each call to `match` takes a Regexp
and a block.

The Regexp is evaluated against the URL on the incoming request to
determine whether the rule matches a given request. Each request will be handled
by the *first* matching rule (or the default rule if no matches are found).

The block passed to `match` should contain a sequence of *actions* for handling
matching requests. Actions will be applied in sequence (the first matching
request will get the first action, the second will get the second, and so on).
Once all of the actions have been evaluated, the final action in the block will
continue to be used.

The `rules` file will be watched for changes automatically, and the rules will
be potentially reloaded each time the proxy accepts a new connection.

If the `rules` file is omitted, the all requests will be transparently proxied to the backend server. 

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

## Caveats

* Totally single-threaded and non-evented, therefore cannot handle multiple client connections at once.
* Errors introduced in the rules file will likely the process to crash instead of just printing an error.
* Almost certainly doesn't handle string encodings correctly
