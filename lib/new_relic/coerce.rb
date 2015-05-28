# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  # We really don't want to send bad values to the collector, and it doesn't
  # accept types like Rational that have occasionally slipped into our data.
  #
  # These methods are intended to safely coerce things into the form we want,
  # to provide documentation of expected types on to_collector_array methods,
  # and to log failures if totally invalid data gets into outgoing data
  module Coerce
    module_function

    def int(value, context=nil)
      Integer(value)
    rescue => error
      log_failure(value, Integer, context, error)
      0
    end

    def int_or_nil(value, context=nil)
      return nil if value.nil?
      Integer(value)
    rescue => error
      log_failure(value, Integer, context, error)
      nil
    end

    def float(value, context=nil)
      result = Float(value)
      raise "Value #{result.inspect} is not finite." unless result.finite?
      result
    rescue => error
      log_failure(value, Float, context, error)
      0.0
    end

    def string(value, context=nil)
      return value if value.nil?
      String(value)
    rescue => error
      log_failure(value.class, String, context, error)
      ""
    end

    def scalar(val)
      case val
      when String, Integer, TrueClass, FalseClass, NilClass
        val
      when Float
        if val.finite?
          val
        else
          nil
        end
      when Symbol
        val.to_s
      else
        "#<#{val.class.to_s}>"
      end
    end

    def log_failure(value, type, context, error)
      msg = "Unable to convert '#{value}' to #{type}"
      msg += " in context '#{context}'" if context
      NewRelic::Agent.logger.warn(msg, error)
    end
  end
end
