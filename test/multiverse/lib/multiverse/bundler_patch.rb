# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler'

# Bundler is deprecating with_clean_env, but we need Bundler 1.x and 2.x, depending
# on our Ruby environment.  This patch allows us to take advantage of the new
# #with_unbundled_env in the interim. 
# NOTE: remove this monkey patch once Bundler 1.x is no longer needed in any environment.

unless Bundler.respond_to?(:with_unbundled_env)
  module Bundler
    def self.with_unbundled_env &block
      Bundler.with_clean_env &block
    end
  end
end
