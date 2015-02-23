# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module FormattingHelpers
    def self.format_duration(d)
      if d < 0.001
        ds = d * 1000 * 1000
        unit = "µs"
      elsif d < 1.0
        ds = d * 1000
        unit = "ms"
      else
        ds = d
        unit = "s"
      end

      sprintf("%.2f %s", ds, unit)
    end
  end
end