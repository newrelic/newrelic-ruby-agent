# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{newrelic_rpm}
  s.version = "2.8.9"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Bill Kayser"]
  s.date = %q{2009-04-17}
  s.default_executable = %q{newrelic_cmd}
  s.description = %q{New Relic Ruby Performance Monitoring Agent}
  s.email = %q{bkayser@newrelic.com}
  s.executables = ["newrelic_cmd"]
  s.extra_rdoc_files = ["README", "LICENSE"]
  s.files = ["install.rb", "LICENSE", "README", "newrelic.yml", "Rakefile", "lib/new_relic", "lib/new_relic/agent", "lib/new_relic/agent/agent.rb", "lib/new_relic/agent/chained_call.rb", "lib/new_relic/agent/collection_helper.rb", "lib/new_relic/agent/error_collector.rb", "lib/new_relic/agent/instrumentation", "lib/new_relic/agent/instrumentation/active_merchant.rb", "lib/new_relic/agent/instrumentation/active_record_instrumentation.rb", "lib/new_relic/agent/instrumentation/controller_instrumentation.rb", "lib/new_relic/agent/instrumentation/data_mapper.rb", "lib/new_relic/agent/instrumentation/dispatcher_instrumentation.rb", "lib/new_relic/agent/instrumentation/memcache.rb", "lib/new_relic/agent/instrumentation/merb", "lib/new_relic/agent/instrumentation/merb/controller.rb", "lib/new_relic/agent/instrumentation/merb/dispatcher.rb", "lib/new_relic/agent/instrumentation/merb/errors.rb", "lib/new_relic/agent/instrumentation/rails", "lib/new_relic/agent/instrumentation/rails/action_controller.rb", "lib/new_relic/agent/instrumentation/rails/action_web_service.rb", "lib/new_relic/agent/instrumentation/rails/dispatcher.rb", "lib/new_relic/agent/instrumentation/rails/errors.rb", "lib/new_relic/agent/instrumentation/rails/rails.rb", "lib/new_relic/agent/method_tracer.rb", "lib/new_relic/agent/patch_const_missing.rb", "lib/new_relic/agent/samplers", "lib/new_relic/agent/samplers/cpu.rb", "lib/new_relic/agent/samplers/memory.rb", "lib/new_relic/agent/samplers/mongrel.rb", "lib/new_relic/agent/stats_engine.rb", "lib/new_relic/agent/synchronize.rb", "lib/new_relic/agent/transaction_sampler.rb", "lib/new_relic/agent/worker_loop.rb", "lib/new_relic/agent.rb", "lib/new_relic/commands", "lib/new_relic/commands/deployments.rb", "lib/new_relic/commands/new_relic_commands.rb", "lib/new_relic/config", "lib/new_relic/config/merb.rb", "lib/new_relic/config/rails.rb", "lib/new_relic/config/ruby.rb", "lib/new_relic/config.rb", "lib/new_relic/local_environment.rb", "lib/new_relic/merbtasks.rb", "lib/new_relic/metric_data.rb", "lib/new_relic/metric_spec.rb", "lib/new_relic/metrics.rb", "lib/new_relic/noticed_error.rb", "lib/new_relic/recipes.rb", "lib/new_relic/shim_agent.rb", "lib/new_relic/stats.rb", "lib/new_relic/transaction_analysis.rb", "lib/new_relic/transaction_sample.rb", "lib/new_relic/version.rb", "lib/new_relic_api.rb", "lib/newrelic_rpm.rb", "lib/tasks", "lib/tasks/agent_tests.rake", "lib/tasks/all.rb", "lib/tasks/install.rake", "bin/newrelic_cmd", "recipes/newrelic.rb", "test/config", "test/config/newrelic.yml", "test/config/test_config.rb", "test/new_relic", "test/new_relic/agent", "test/new_relic/agent/agent_test_controller.rb", "test/new_relic/agent/mock_ar_connection.rb", "test/new_relic/agent/mock_scope_listener.rb", "test/new_relic/agent/model_fixture.rb", "test/new_relic/agent/tc_active_record.rb", "test/new_relic/agent/tc_agent.rb", "test/new_relic/agent/tc_collection_helper.rb", "test/new_relic/agent/tc_controller.rb", "test/new_relic/agent/tc_dispatcher_instrumentation.rb", "test/new_relic/agent/tc_error_collector.rb", "test/new_relic/agent/tc_method_tracer.rb", "test/new_relic/agent/tc_stats_engine.rb", "test/new_relic/agent/tc_synchronize.rb", "test/new_relic/agent/tc_transaction_sample.rb", "test/new_relic/agent/tc_transaction_sample_builder.rb", "test/new_relic/agent/tc_transaction_sampler.rb", "test/new_relic/agent/tc_worker_loop.rb", "test/new_relic/agent/testable_agent.rb", "test/new_relic/tc_config.rb", "test/new_relic/tc_deployments_api.rb", "test/new_relic/tc_environment.rb", "test/new_relic/tc_metric_spec.rb", "test/new_relic/tc_shim_agent.rb", "test/new_relic/tc_stats.rb", "test/test_helper.rb", "test/ui", "test/ui/tc_newrelic_helper.rb", "ui/controllers", "ui/controllers/newrelic_controller.rb", "ui/helpers", "ui/helpers/google_pie_chart.rb", "ui/helpers/newrelic_helper.rb", "ui/views", "ui/views/layouts", "ui/views/layouts/newrelic_default.rhtml", "ui/views/newrelic", "ui/views/newrelic/_explain_plans.rhtml", "ui/views/newrelic/_sample.rhtml", "ui/views/newrelic/_segment.rhtml", "ui/views/newrelic/_segment_row.rhtml", "ui/views/newrelic/_show_sample_detail.rhtml", "ui/views/newrelic/_show_sample_sql.rhtml", "ui/views/newrelic/_show_sample_summary.rhtml", "ui/views/newrelic/_sql_row.rhtml", "ui/views/newrelic/_stack_trace.rhtml", "ui/views/newrelic/_table.rhtml", "ui/views/newrelic/explain_sql.rhtml", "ui/views/newrelic/images", "ui/views/newrelic/images/arrow-close.png", "ui/views/newrelic/images/arrow-open.png", "ui/views/newrelic/images/blue_bar.gif", "ui/views/newrelic/images/gray_bar.gif", "ui/views/newrelic/index.rhtml", "ui/views/newrelic/javascript", "ui/views/newrelic/javascript/transaction_sample.js", "ui/views/newrelic/sample_not_found.rhtml", "ui/views/newrelic/show_sample.rhtml", "ui/views/newrelic/show_source.rhtml", "ui/views/newrelic/stylesheets", "ui/views/newrelic/stylesheets/style.css"]
  s.has_rdoc = true
  s.homepage = %q{http://www.newrelic.com}
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{newrelic}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{New Relic Ruby Performance Monitoring Agent}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
