# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)

require 'new_relic/agent/attribute_filter'
require 'new_relic/agent/span_attribute_filter'

module NewRelic
  module Agent
    class SpanAttributeFilterTest < Minitest::Test
      def test_span_attributes_include_exclude
        filter_with_config :'span.attributes.include' => ['request.headers.contentType'],
                           :'span.attributes.exclude' => ['request.headers.*'] do |filter|


          assert filter.permits? 'request.headers.contentType'
          refute filter.permits? 'request.headers.accept'
        end
      end

      def test_global_attribute_include_exclude
        filter_with_config :'attributes.include' => ['request.headers.contentType'],
                           :'attributes.exclude' => ['request.headers.*'] do |filter|


          assert filter.permits? 'request.headers.contentType'
          refute filter.permits? 'request.headers.accept'
        end
      end

      def test_results_are_cached
        filter_with_config :'attributes.include' => ['request.headers.contentType'],
                           :'attributes.exclude' => ['request.headers.*'] do |filter|


          filter.permits? 'request.headers.contentType'
          filter.permits? 'request.headers.accept'

          cache = filter.instance_variable_get :@cache

          assert cache.key? 'request.headers.contentType'
          assert cache.key? 'request.headers.accept'
        end
      end

      private

      def filter_with_config(config = {})
        with_config(config) do
          attribute_filter = AttributeFilter.new(NewRelic::Agent.config)
          span_attribute_filter = SpanAttributeFilter.new(attribute_filter)
          yield span_attribute_filter
        end
      end
    end
  end
end

