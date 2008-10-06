#!/usr/bin/ruby
module NewRelic::VERSION #:nodoc:
  MAJOR = 2
  MINOR = 5
  TINY  = 3
  STRING = [MAJOR, MINOR, TINY].join('.')
end

if __FILE__ == $0
  puts "NewRelic RPM Plugin Version: #{NewRelic::VERSION}"
  puts DATA.read
end

__END__
2008-10-06 version 2.5.3
  * fix error in transaction tracing causing traces not to show up
2008-09-30 version 2.5.2
  * fixes for postgres explain plan support
2008-09-09 version 2.5.1
  * bugfixes
2008-08-29 version 2.5.0
  * add agent support for rpm 1.1 features
  * Fix regression error with thin support
2008-08-27 version 2.4.3
  * added 'newrelic_ignore' controller class method with :except and :only options for finer grained control
    over the blocking of instrumentation in controllers.
  * bugfixes
2008-07-31 version 2.4.2
  * error reporting in early access
2008-07-30 version 2.4.1
  * bugfix: initializing developer mode
2008-07-29 version 2.4.0
  * Beta support for LiteSpeed and Passenger
2008-07-28 version 2.3.7
  * bugfixes
2008-07-28 version 2.3.6
  * bugfixes
2008-07-17 version 2.3.5
  * bugfixes: pie chart data, rails 1.1 compability
2008-07-11 version 2.3.4
  * bugfix
2008-07-10 version 2.3.3
  * bugfix for non-mysql databases
2008-07-07 version 2.3.2
  * bugfixes
  * Add enhancement for Transaction Traces early access feature
2008-06-26 version 2.3.1
  * bugfixes
2008-06-26 version 2.3.0
  + Add support for Transaction Traces early access feature
2008-06-13 version 2.2.2
  * bugfixes
2008-06-10 version 2.2.1
  + Add rails 2.1 support for Developer Mode
  + Changes to memory sampler: Add support for JRuby and fix Solaris support.  
  * Stop catching exceptions and start catching StandardError; other exception cleanup
  * Add protective exception catching to the stats engine
  * Improved support for thin domain sockets
  * Support JRuby environments
2008-05-22 version 2.1.6
  * bugfixes
2008-05-22 version 2.1.5
  * bugfixes
2008-05-14 version 2.1.4
  * bugfixes
2008-05-13 version 2.1.3
  * bugfixes
2008-05-08 version 2.1.2
  * bugfixes
2008-05-07 version 2.1.1
  * bugfixes
2008-04-25 version 2.1.0
  * release for private beta
