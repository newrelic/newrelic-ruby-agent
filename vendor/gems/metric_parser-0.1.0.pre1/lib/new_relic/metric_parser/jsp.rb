# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class NewRelic::MetricParser::Jsp < NewRelic::MetricParser::MetricParser
  def is_view?; true; end
  def pie_chart_label
    short_name
  end

  def short_name
    segments[-1]
  end

  def controller_name
    file_name
  end

  def tooltip_name
    developer_name
  end

  def action_name
    file_name
  end

  def developer_name
    file_name
  end

  def url
    '/' + file_name
  end
  private
  def file_name
    segments[1..-1].join(NewRelic::MetricParser::MetricParser::SEPARATOR)
  end
end
