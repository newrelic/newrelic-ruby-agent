# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'conditional_vendored_metric_parser'

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', 'test_helper'))
class NewRelic::MetricParser::MetricParserTest < Minitest::Test
  class ::AnApplicationClass
  end

  def test_metric_parser_does_not_instantiate_non_metric_parsing_classes
    assert NewRelic::MetricParser::MetricParser.for_metric_named('AnApplicationClass/Foo/Bar').
      is_a? NewRelic::MetricParser::MetricParser
  end

end
