# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser/spring'
class NewRelic::MetricParser::SpringView < NewRelic::MetricParser::Spring
  def component_type
    "View"
  end
end
