# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'logger'

$: << File.expand_path(File.dirname(__FILE__))

require 'performance/result'
require 'performance/runner'
require 'performance/test_case'
require 'performance/timer'
require 'performance/instrumentor'
require 'performance/console_reporter'
require 'performance/json_reporter'
require 'performance/hako_client'
require 'performance/hako_reporter'

module Performance
  def self.logger
    log_path = ENV['LOG'] || $stderr
    @logger ||= Logger.new(log_path)
  end

  def self.log_path=(path)
    @logger = Logger.new(path)
  end
end
