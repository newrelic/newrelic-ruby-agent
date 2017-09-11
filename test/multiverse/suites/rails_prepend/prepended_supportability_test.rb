# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require '../rails/app'

class PrependedSupportabilityMetricsTest < Minitest::Test
  include MultiverseHelpers

  def test_action_view_prepended_metrics
    assert_metrics_recorded [
      "Supportability/PrependedModules/ActionView::Base",
      "Supportability/PrependedModules/ActionView::Template",
      "Supportability/PrependedModules/ActionView::Renderer"
    ]
  end

  def test_action_contoller_prepended_metrics
    metrics = ["Supportability/PrependedModules/ActionController::Base"]
    metrics << "Supportability/PrependedModules/ActionController::API" if ::Rails::VERSION::MAJOR.to_i == 5
    assert_metrics_recorded metrics
  end

  if ::Rails::VERSION::MAJOR.to_i == 5
    def test_action_cable_prepended_metrics
      assert_metrics_recorded [
        "Supportability/PrependedModules/ActionCable::Engine",
        "Supportability/PrependedModules/ActionCable::RemoteConnections"
      ]
    end

    def test_active_job_prepended_metrics
      assert_metrics_recorded [
        "Supportability/PrependedModules/ActiveJob::Base"
      ]
    end
  end

  def test_active_record_prepended_metrics
    assert_metrics_recorded [
      "Supportability/PrependedModules/ActiveRecord::Base",
      "Supportability/PrependedModules/ActiveRecord::Relation"
    ]
  end

end
