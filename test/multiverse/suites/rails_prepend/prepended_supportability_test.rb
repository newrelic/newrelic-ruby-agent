# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require '../rails/app'

class PrependedSupportabilityMetricsTest < Minitest::Test
  include MultiverseHelpers

  def test_action_view_prepended_metrics
    assert_metrics_recorded({

      # haml prepends a module on ActionView::Base
      #
      "Supportability/PrependedModules/ActionView::Base" => metric_values_for(2),

      "Supportability/PrependedModules/ActionView::Template" => metric_values_for(1),
      "Supportability/PrependedModules/ActionView::Renderer" => metric_values_for(1)
    })
  end

  def test_action_contoller_prepended_metrics
    metrics = ["Supportability/PrependedModules/ActionController::Base"]
    metrics << "Supportability/PrependedModules/ActionController::API" if ::Rails::VERSION::MAJOR.to_i == 5
    assert_metrics_recorded(metrics.reduce({}) {|h,m| h[m] = metric_values_for(1); h})
  end

  if ::Rails::VERSION::MAJOR.to_i == 5
    def test_action_cable_prepended_metrics
      assert_metrics_recorded({
        "Supportability/PrependedModules/ActionCable::Engine" => metric_values_for(1),
        "Supportability/PrependedModules/ActionCable::RemoteConnections" => metric_values_for(1)
      })
    end

    def test_active_job_prepended_metrics
      assert_metrics_recorded({ "Supportability/PrependedModules/ActiveJob::Base" => metric_values_for(1) })
    end
  end

  def test_active_record_prepended_metrics

    # rails 5.0 prepends an anonymous module on to AR::Relation
    #
    val = 1
    val += 1 if ::Rails::VERSION::MAJOR.to_i == 5 and ::Rails::VERSION::MINOR.to_i == 0

    assert_metrics_recorded({
      "Supportability/PrependedModules/ActiveRecord::Base" => metric_values_for(1),
      "Supportability/PrependedModules/ActiveRecord::Relation" => metric_values_for(val)
    })
  end

  def metric_values_for val
    { call_count: 1,
      max_call_time: val,
      min_call_time: val,
      sum_of_squares: val**2.to_f,
      total_call_time: val.to_f,
      total_exclusive_time: val.to_f }
  end

end
