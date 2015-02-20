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