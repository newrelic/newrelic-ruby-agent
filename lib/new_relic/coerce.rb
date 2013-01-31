module NewRelic
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
