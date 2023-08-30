# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

class SidekiqArgsFiltrationTest < Minitest::Test
  include SidekiqTestHelpers

  ARGUMENTS = [{'username' => 'JBond007',
                'color' => 'silver',
                'record' => true,
                'items' => %w[stag thistle peat],
                'price_map' => {'apple' => 0.75, 'banana' => 0.50, 'pear' => 0.99}},
    'When I thought I heard myself say no',
    false].freeze

  def setup
    cache_var = :@nr_attribute_options
    if NewRelic::Agent::Instrumentation::Sidekiq::Server.instance_variables.include?(cache_var)
      NewRelic::Agent::Instrumentation::Sidekiq::Server.remove_instance_variable(cache_var)
    end
  end

  def test_by_default_no_args_are_captured
    captured_args = run_job_and_get_attributes(*ARGUMENTS)

    assert_empty captured_args, "Didn't expect to capture any attributes for the Sidekiq job, " +
      "captured: #{captured_args}"
  end

  def test_all_args_are_captured
    expected = flatten(ARGUMENTS)
    with_config(:'attributes.include' => 'job.sidekiq.args.*') do
      captured_args = run_job_and_get_attributes(*ARGUMENTS)

      assert_equal expected, captured_args, "Expected all args to be captured. Wanted:\n\n#{expected}\n\n" +
        "Got:\n\n#{captured_args}\n\n"
    end
  end

  def test_only_included_args_are_captured
    included = ['price_map']
    expected = flatten([{included.first => ARGUMENTS.first[included.first]}])
    with_config(:'attributes.include' => 'job.sidekiq.args.*',
      :'sidekiq.args.include' => included) do
      captured_args = run_job_and_get_attributes(*ARGUMENTS)

      assert_equal expected, captured_args, "Expected only '#{included}' args to be captured. " +
        "Wanted:\n\n#{expected}\n\nGot:\n\n#{captured_args}\n\n"
    end
  end

  def test_excluded_args_are_not_captured
    excluded = ['username']
    without_excluded = ARGUMENTS.dup
    without_excluded.first.delete(excluded.first)
    expected = flatten(without_excluded)
    with_config(:'attributes.include' => 'job.sidekiq.args.*',
      :'sidekiq.args.exclude' => excluded) do
      captured_args = run_job_and_get_attributes(*ARGUMENTS)

      assert_equal expected, captured_args, "Expected '#{excluded}' to be excluded from capture. " +
        "Wanted:\n\n#{expected}\n\nGot:\n\n#{captured_args}\n\n"
    end
  end

  def test_include_and_exclude_cascaded
    included = ['price_map']
    excluded = %w[apple pear]
    hash = {included.first => ARGUMENTS.first[included.first].dup}
    # TODO: OLD RUBIES - Requires 3.0
    #       Hash#except would be better here, requires Ruby v3+
    excluded.each { |exclude| hash[included.first].delete(exclude) }
    expected = flatten([hash])
    with_config(:'attributes.include' => 'job.sidekiq.args.*',
      :'sidekiq.args.include' => included,
      :'sidekiq.args.exclude' => excluded) do
      captured_args = run_job_and_get_attributes(*ARGUMENTS)

      assert_equal expected, captured_args, "Used included='#{included}', excluded='#{excluded}'. " +
        "Wanted:\n\n#{expected}\n\nGot:\n\n#{captured_args}\n\n"
    end
  end

  def test_arcane_pattern_usage
    # no booleans, nothing with numbers, no *.name except unitname, anything ending in 't', a string with I, I, and y, y
    excluded = ['^true|false$', '\d+', '(?!<unit)name$', 't$', 'I.*I.*y.*.y']
    expected = flatten([{'color' => 'silver', 'items' => %w[stag thistle]}])
    with_config(:'attributes.include' => 'job.sidekiq.args.*',
      :'sidekiq.args.exclude' => excluded) do
      captured_args = run_job_and_get_attributes(*ARGUMENTS)

      assert_equal expected, captured_args, "Used excluded='#{excluded}'. " +
        "Wanted:\n\n#{expected}\n\nGot:\n\n#{captured_args}\n\n"
    end
  end
end
