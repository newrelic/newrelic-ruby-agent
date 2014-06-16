# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser'

module NewRelic
  module MetricParser
    class Middleware < MetricParser
      ALL  = 'Middleware/all'.freeze
      RACK = 'Rack'.freeze

      def ui_name(value_fn=nil,options={})
        if metric_name == ALL
          "Middleware"
        else
          "#{segments[2]}\##{segments[3]}"
        end
      end

      def is_middleware?
        true
      end

      def controller_name
        segments[2]
      end

      def action_name
        segments[3]
      end
    end
  end
end
