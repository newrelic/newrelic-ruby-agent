# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic::Agent::InfiniteTracing
  class ResponseHandlerTest < Minitest::Test

    def teardown
      reset_buffers_and_caches
    end

    def test_processes_simple_task
      worker = Worker.new "simple" do
        NewRelic::Agent.record_metric("Supportability/InfiniteTracing/Worker", 0.0)
      end
      assert_equal "run", worker.status
      worker.join
      assert_equal "idle", worker.status
      worker.stop
      assert_equal "stopped", worker.status

      assert "simple", worker.name
      assert_metrics_recorded "Supportability/InfiniteTracing/Worker"
    end

    def test_worker_handles_errors
      worker = Worker.new "error" do
        NewRelic::Agent.record_metric("Supportability/InfiniteTracing/Worker", 0.0)
        raise "Oops!"
        NewRelic::Agent.record_metric("Supportability/InfiniteTracing/Error", 0.0)
      end
      
      begin
        worker.join
      rescue => err
        assert_equal "Oops!", err.message
        assert worker.error
      end

      assert "error", worker.name
      assert_equal "error", worker.status
      assert_metrics_recorded "Supportability/InfiniteTracing/Worker"
      refute_metrics_recorded "Supportability/InfiniteTracing/Error"
    end
  end
end