# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  autoload :MetricParser, 'new_relic/metric_parser'
  module MetricParser
    class ActionMailer < NewRelic::MetricParser::MetricParser

      def is_action_mailer?; true; end

      def short_name
        "ActionMailer - #{segments[1]}"
      end

    end
  end
end
