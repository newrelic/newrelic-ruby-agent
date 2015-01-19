# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::LocalEnvironmentTest < Minitest::Test

  def teardown
    NewRelic::Control.reset
  end

  def test_passenger
    with_constant_defined(:PhusionPassenger, Module.new) do
      NewRelic::Agent.reset_config
      e = NewRelic::LocalEnvironment.new
      assert_equal :passenger, e.discovered_dispatcher
      assert_equal :passenger, NewRelic::Agent.config[:dispatcher]

      with_config(:app_name => 'myapp') do
        e = NewRelic::LocalEnvironment.new
        assert_equal :passenger, e.discovered_dispatcher
      end
    end
  end

  def test_not_resque
    combinations = [["notrake", "resque:work",    { "QUEUE" => "*" } ],
                    ["rake",    "notresque:work", { "QUEUE" => "*" } ],
                    ["rake",    "resque:work",    { "BBQ"   => "*" } ]]

    combinations.each do |settings|
      with_resque(*settings) do
        refute_resque(settings)
      end
    end
  end

  def test_resque
    combinations = [["rake", "resque:work", { "QUEUE"  => "*" }],
                    ["rake", "resque:work", { "QUEUES" => "*" }]]

    combinations.each do |settings|
      with_resque(*settings) do
        assert_resque(settings)
      end
    end
  end

  def test_not_resque_pool
    combinations = [["notresque-pool", nil],
                    ["rake", "notresque:pool"]]

    combinations.each do |settings|
      with_resque_pool(*settings) do
        refute_resque(settings)
      end
    end
  end

  def test_resque_pool
    combinations = [["resque-pool", nil],
                    ["rake", "resque:pool"]]

    combinations.each do |settings|
      with_resque_pool(*settings) do
        assert_resque(settings)
      end
    end
  end

  def with_resque(basename, *args)
    env  = {}
    env  = args.last if args.last.is_a?(Hash)
    argv = args[0..-1]

    with_constant_defined(:Resque) do
      with_environment(env) do
        with_argv(argv) do
          File.stubs(:basename).returns(basename)
          yield
        end
      end
    end
  end

  def with_resque_pool(basename, *args)
    with_resque(basename, *args) do
      with_constant_defined(:'Resque::Pool') do
        yield
      end
    end
  end

  def assert_resque(settings)
    e = NewRelic::LocalEnvironment.new
    assert_equal :resque, e.discovered_dispatcher, settings.inspect
  end

  def refute_resque(settings)
    e = NewRelic::LocalEnvironment.new
    refute_equal :resque, e.discovered_dispatcher, settings.inspect
  end
end
