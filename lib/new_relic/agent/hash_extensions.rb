# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HashExtensions
      module_function

      # recurses through hashes and arrays and stringifies keys
      def stringify_keys_in_object(object)
        case object
        when Hash
          object.inject({}) do |memo, (k, v)|
            memo[k.to_s] = stringify_keys_in_object(v)
            memo
          end
        when Array
          object.map {|o| stringify_keys_in_object(o)}
        else
          object
        end
      end
    end
  end
end