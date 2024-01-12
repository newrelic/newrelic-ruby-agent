# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Base64
    extend self

    def encode64(bin)
      [bin].pack('m')
    end

    def decode64(str)
      str.unpack1('m')
    end

    def strict_encode64(bin)
      [bin].pack('m0')
    end

    def strict_decode64(str)
      str.unpack1('m0')
    end
  end
end
