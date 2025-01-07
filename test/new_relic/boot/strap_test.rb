# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

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
    assert_equal ['newrelic_rpm', PhonyBundler::DEFAULT_GEM_NAME], required_gems,
      "Expected to see 'newrelic_rpm' required. Only saw #{required_gems}"
  end

  def test_check_for_require
    opn = $PROGRAM_NAME

    $PROGRAM_NAME = bootstrap_file

    assert_raises(RuntimeError, 'meant to be required, not invoked') do
      NRBundlerPatcher.check_for_require
    end
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

      assert_raises(RuntimeError, 'class Bundler::Runtime not defined!') do
        NRBundlerPatcher.check_for_bundler
      end
    end
  ensure
    Bundler.send(:const_set, :Runtime, oruntime)
  end

  def test_check_for_bundler_method_not_defined
    skip_unless_minitest5_or_above

    NRBundlerPatcher.stub :require_bundler, nil do
      Bundler::Runtime.stub :method_defined?, false, [:require] do
        assert_raises(RuntimeError, "doesn't offer Bundler::Runtime#require") do
          NRBundlerPatcher.check_for_bundler
        end
      end
    end
  end

  def test_require_bundler
    skip_unless_minitest5_or_above

    NRBundlerPatcher.stub :require, proc { |_gem| raise LoadError }, ['bundler'] do
      assert_raises(RuntimeError, 'could not be required') do
        NRBundlerPatcher.check_for_bundler
      end
    end
  end

  private

  # Load the bootstrap file and anticipate the `warn` call
  def require_bootstrap
    msg = ''
    loaded = nil
    Kernel.stub :warn, proc { |m| msg = m } do
      loaded = require_relative '../../../lib/boot/strap'
    end

    return unless loaded

    assert_match(/New Relic entrypoint/, msg,
      'Expected the initial requiring of boot/strap to generate a warning')
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
    @bootstrap_file ||= File.expand_path('../../../../lib/boot/strap.rb', __FILE__)
  end
end
