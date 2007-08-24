$:.unshift '/Users/cirne/dev/rubystuff/Seldon/Agent'
$:.unshift '/Users/cirne/dev/rubystuff/Seldon/Common'

# don't use the agent if we're running a rake task, like unit tests or the like.
require 'seldon/agent'

