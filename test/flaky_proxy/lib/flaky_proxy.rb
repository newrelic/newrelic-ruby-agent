# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

$: << File.expand_path(File.dirname(__FILE__))

require 'logger'

require 'flaky_proxy/server'
require 'flaky_proxy/connection'
require 'flaky_proxy/http_message'
require 'flaky_proxy/rule'
require 'flaky_proxy/rule_set'
require 'flaky_proxy/proxy'
require 'flaky_proxy/sequence'

module FlakyProxy
  @logger = Logger.new($stderr)

  def self.logger
    @logger
  end
end
