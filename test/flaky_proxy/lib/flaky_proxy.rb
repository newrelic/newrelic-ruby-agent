$: << File.expand_path(File.dirname(__FILE__))

require 'logger'

require 'flaky_proxy/server'
require 'flaky_proxy/connection'
require 'flaky_proxy/http_message'
require 'flaky_proxy/rule'
require 'flaky_proxy/rule_set'
require 'flaky_proxy/proxy'

module FlakyProxy
  @logger = Logger.new($stderr)

  def self.log
    @logger
  end
end
