$:.unshift '/Users/cirne/dev/rubystuff/Seldon/Agent'
$:.unshift '/Users/cirne/dev/rubystuff/Seldon/Common'

# don't use the agent if we're running a rake task, like unit tests or the like.
# TODO fix me.  must be a better way to determine that we are not running a test suite
unless $0.include?('rake') || $0.include?('irb')
  require 'seldon/agent'
end

