# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# define special constant so DefaultSource.framework can return :test
module NewRelic; TEST = true; end unless defined? NewRelic::TEST

ENV['RAILS_ENV'] = 'test'

agent_test_path = File.expand_path('../../../test', __FILE__)
$LOAD_PATH << agent_test_path

require 'rubygems'
require 'rake'

# gem "minitest"

require 'minitest/autorun'
require 'mocha/setup'

require 'newrelic_rpm'
require 'new_relic/infinite_tracing'

Dir[File.expand_path('../support/*', __FILE__)].each {|f| require f.sub(/.*test\//,'')}

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper

