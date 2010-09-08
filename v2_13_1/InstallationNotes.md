
PLEASE NOTE:

Developer Mode is now a Rack middleware.

RPM Developer Mode is no longer available in Rails 2.1 and earlier.
However, starting in version 2.12 you can use Developer Mode in any
Rack based framework, in addition to Rails.  To install developer mode
in a non-Rails application, just add NewRelic::Rack::DeveloperMode to
your middleware stack.

If you are using JRuby, we recommend using at least version 1.4 or 
later because of issues with the implementation of the timeout library.

Refer to the README.md file for more information.
