# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This is required to load in task definitions from merb
Dir.glob(File.join(File.dirname(__FILE__),'*.rake')) do |file|
  load file
end
