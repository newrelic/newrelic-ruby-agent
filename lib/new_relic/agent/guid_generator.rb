# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module GuidGenerator
      HEX_DIGITS = (0..15).map { |i| i.to_s(16) }

      module_function

      # This method intentionally does not use SecureRandom, because it relies
      # on urandom, which raises an exception in MRI when the interpreter runs
      # out of allocated file descriptors.
      # The guids generated by this method may not be _secure_, but they are
      # random enough for our purposes.
      def generate_guid(length = 16)
        guid = ''
        length.times do |_a|
          guid << HEX_DIGITS[rand(16)]
        end
        guid
      end
    end
  end
end
