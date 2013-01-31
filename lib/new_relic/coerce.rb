module NewRelic
  # We really don't want to send bad values to the collector, and it doesn't
  # accept types like Rational that have occasionally slipped into our data.
  #
  # These methods are intended to safely coerce things into the form we want,
  # to provide documentation of expected types on to_collector_array methods,
  # and to log failures if totally invalid data gets into outgoing data
  class Coerce
    def self.int(value, context="")
      Integer(value)
    rescue => e
      NewRelic::Agent.logger.warn("Unable to convert value '#{value}' to int in context '#{context}'", e)
      0
    end

    def self.float(value, context="")
      Float(value)
    rescue => e
      NewRelic::Agent.logger.warn("Unable to convert value '#{value}' to float in context '#{context}'", e)
      0.0
    end

    def self.string(value, context="")
      String(value)
    rescue => e
      NewRelic::Agent.logger.warn("Unable to convert value of type '#{value.class}' to string in context '#{context}'", e)
      ""
    end
  end
end
