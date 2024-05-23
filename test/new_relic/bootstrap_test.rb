# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class NewRelicBootstrapTest < Minitest::Test
  class PhonyBundler
    DEFAULT_GEM_NAME = 'tadpole'

    def require(*_groups)
      Kernel.require DEFAULT_GEM_NAME
    end
  end

  def setup
    require_bootstrap
    monkeypatch_phony_bundler
  end

  def test_the_overall_prepend_based_monkeypatch
    # Make sure that newrelic_rpm is required as a result of the patching
    required_gems = []
    Kernel.stub :require, proc { |gem| required_gems << gem } do
      PhonyBundler.new.require
    end

    assert_equal 2, required_gems.size, "Expected 2 gems to be required, saw #{required_gems.size}."
    assert_equal [PhonyBundler::DEFAULT_GEM_NAME, 'newrelic_rpm'], required_gems,
      "Expected to see 'newrelic_rpm' required. Only saw #{required_gems}"
  end

  def test_check_for_require
    opn = $PROGRAM_NAME

    $PROGRAM_NAME = bootstrap_file
    msg = ''
    NRBundlerPatcher.stub :warn_and_exit, proc { |m| msg = m } do
      NRBundlerPatcher.check_for_require
    end

    assert_match(/meant to be required, not invoked/, msg,
      'Expected check_for_require to complain when bootstrap is invoked directly')
  ensure
    $PROGRAM_NAME = opn
  end

  def test_check_for_rubyopt
    oro = ENV.fetch('RUBYOPT', nil)

    ENV['RUBYOPT'] = "-r #{bootstrap_file}"

    refute NRBundlerPatcher.check_for_rubyopt
  ensure
    ENV['RUBYOPT'] = oro if oro
  end

  def test_check_for_bundler_class_not_defined
    oruntime = Bundler.send(:const_get, :Runtime)

    NRBundlerPatcher.stub :require_bundler, nil do
      Bundler.send(:remove_const, :Runtime)

      msg = ''
      NRBundlerPatcher.stub :warn_and_exit, proc { |m| msg = m; Bundler.send(:const_set, :Runtime, oruntime) } do
        NRBundlerPatcher.check_for_bundler
      end

      assert_match(/class Bundler::Runtime not defined!/, msg,
        'Expected check_for_bundler to complain if Bundler::Runtime is not defined')
    end
  ensure
    Bundler.send(:const_set, :Runtime, oruntime)
  end

  def test_check_for_bundler_method_not_defined
    skip_unless_minitest5_or_above

    NRBundlerPatcher.stub :require_bundler, nil do
      Bundler::Runtime.stub :method_defined?, false, [:require] do
        msg = ''
        NRBundlerPatcher.stub :warn_and_exit, proc { |m| msg = m } do
          NRBundlerPatcher.check_for_bundler
        end

        assert_match(/doesn't offer Bundler::Runtime#require/, msg,
          'Expected check_for_bundler to complain if Bundler::Runtime#require is not defined')
      end
    end
  end

  def test_require_bundler
    skip_unless_minitest5_or_above

    NRBundlerPatcher.stub :require, proc { |_gem| raise LoadError }, ['bundler'] do
      msg = ''
      NRBundlerPatcher.stub :warn_and_exit, proc { |m| msg = m } do
        NRBundlerPatcher.check_for_bundler
      end

      assert_match(/could not be required/, msg,
        'Expected require_bundler to complain if Bundler could not be required')
    end
  end

  private

  # Load the bootstrap file and anticipate the `warn` and `exit` calls
  # with assertions
  def require_bootstrap
    assert_raises SystemExit do
      assert_output(/New Relic entrypoint/) do
        require_relative '../../lib/bootstrap'
      end
    end
  end

  # Have the patcher patch our phony Bundler instead of the real one
  def monkeypatch_phony_bundler
    NRBundlerPatcher.stub :check_for_require, nil do
      NRBundlerPatcher.stub :check_for_rubyopt, nil do
        NRBundlerPatcher.stub :check_for_bundler, nil do
          Bundler::Runtime.stub :prepend, proc { |mod| PhonyBundler.prepend(mod) } do
            NRBundlerPatcher.patch
          end
        end
      end
    end
  end

  def bootstrap_file
    @bootstrap_file ||= File.expand_path('../../../lib/bootstrap.rb', __FILE__)
  end
end
