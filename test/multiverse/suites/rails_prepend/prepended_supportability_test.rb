# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require '../rails/app'

class PrependedSupportabilityMetricsTest < Minitest::Test
  include MultiverseHelpers

  def test_action_view_prepended_metrics
    assert_metrics_recorded({

      # these values are different because haml prepends a module on
      # ActionView::Base as well.
      #
      "Supportability/PrependedModules/ActionView::Base" => {
        call_count: 1,
        max_call_time: 2,
        min_call_time: 2,
        sum_of_squares: 4.0,
        total_call_time: 2.0,
        total_exclusive_time: 2.0
      },

      "Supportability/PrependedModules/ActionView::Template" => {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      },
      "Supportability/PrependedModules/ActionView::Renderer" => {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      }
    })
  end

  def test_action_contoller_prepended_metrics
    metrics = ["Supportability/PrependedModules/ActionController::Base"]
    metrics << "Supportability/PrependedModules/ActionController::API" if ::Rails::VERSION::MAJOR.to_i == 5
    assert_metrics_recorded(metrics.reduce({}) do |h,m|
      h[m] = {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      }
      h
    end)
  end

  if ::Rails::VERSION::MAJOR.to_i == 5
    def test_action_cable_prepended_metrics
      assert_metrics_recorded({
        "Supportability/PrependedModules/ActionCable::Engine" => {
          call_count: 1,
          max_call_time: 1,
          min_call_time: 1,
          sum_of_squares: 1.0,
          total_call_time: 1.0,
          total_exclusive_time: 1.0
        },
        "Supportability/PrependedModules/ActionCable::RemoteConnections" => {
          call_count: 1,
          max_call_time: 1,
          min_call_time: 1,
          sum_of_squares: 1.0,
          total_call_time: 1.0,
          total_exclusive_time: 1.0
        }
      })
    end

    def test_active_job_prepended_metrics
      assert_metrics_recorded({
        "Supportability/PrependedModules/ActiveJob::Base" => {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      }
      })
    end
  end

  def test_active_record_prepended_metrics
    assert_metrics_recorded({
      "Supportability/PrependedModules/ActiveRecord::Base" => {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      },
      "Supportability/PrependedModules/ActiveRecord::Relation" => {
        call_count: 1,
        max_call_time: 1,
        min_call_time: 1,
        sum_of_squares: 1.0,
        total_call_time: 1.0,
        total_exclusive_time: 1.0
      }
    })
  end

end
