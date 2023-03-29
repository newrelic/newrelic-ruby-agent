# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/parameter_filtering'

module NewRelic
  module Agent
    class ParameterFilteringTest < Minitest::Test
      def test_apply_filters_returns_params_when_rails_is_not_present
        undefine_constant(:"ActionDispatch::Http::ParameterFilter") do
          undefine_constant(:"ActiveSupport::ParameterFilter") do
            params = {'password' => 'mypass'}
            result = ParameterFiltering.apply_filters({}, params)

            assert_equal params, result
          end
        end
      end

      def test_apply_filters_replaces_file_uploads_with_placeholder
        env = {'CONTENT_TYPE' => 'multipart/form-data'}
        params = {
          :name => 'name',
          :file => {
            :filename => 'data.jpg',
            :tempfile => 'file_data'
          }
        }

        expected = {:name => 'name', :file => '[FILE]'}
        result = ParameterFiltering.apply_filters(env, params)

        assert_equal expected, result

        # argument should not be mutated
        assert_equal({:filename => 'data.jpg', :tempfile => 'file_data'}, params[:file])
      end

      def test_app_works_constant_not_set
        undefine_constant(:"NewRelic::Agent::ParameterFiltering::RAILS_FILTER_CLASS") do
          params = {rubysec: :cat}

          assert_equal params, ParameterFiltering.filter_using_rails(params, nil)
        end
      end
    end
  end
end
