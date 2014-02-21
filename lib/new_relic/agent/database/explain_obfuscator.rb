# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/database'

module NewRelic
  module Agent
    module Database
      class ExplainObfuscator
        include ObfuscationHelpers

        def obfuscate(query, explain)
          literals = find_literals(query)
          puts literals
          literals.each do |literal|
            explain.gsub!(literal, '?')
          end
          explain
        end
      end
    end
  end
end
