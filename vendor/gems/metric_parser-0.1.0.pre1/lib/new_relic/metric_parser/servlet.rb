# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser/java'
class NewRelic::MetricParser::Servlet < NewRelic::MetricParser::Java

  def call_rate_suffix
    'cpm'
  end
end
