# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic::LanguageSupport
  extend self

  RUBY_VERSION_192 = '1.9.2'.freeze

  # need to use syck rather than psych when possible
  def needs_syck?
    !NewRelic::LanguageSupport.using_engine?('jruby') &&
         NewRelic::LanguageSupport.using_version?('1.9.2')
  end

  @@forkable = nil
  def can_fork?
    # this is expensive to check, so we should only check once
    return @@forkable if @@forkable != nil

    if Process.respond_to?(:fork)
      # if this is not 1.9.2 or higher, we have to make sure
      @@forkable = ::RUBY_VERSION < '1.9.2' ? test_forkability : true
    else
      @@forkable = false
    end

    @@forkable
  end

  def using_engine?(engine)
    if defined?(::RUBY_ENGINE)
      ::RUBY_ENGINE == engine
    else
      engine == 'ruby'
    end
  end

  def broken_gc?
    NewRelic::LanguageSupport.using_version?('1.8.7') &&
      RUBY_PATCHLEVEL < 348 &&
      !NewRelic::LanguageSupport.using_engine?('jruby') &&
      !NewRelic::LanguageSupport.using_engine?('rbx')
  end

  def with_disabled_gc
    if defined?(::GC) && ::GC.respond_to?(:disable)
      val = nil
      begin
        ::GC.disable
        val = yield
      ensure
        ::GC.enable
      end
      val
    else
      yield
    end
  end

  def with_cautious_gc
    if broken_gc?
      with_disabled_gc { yield }
    else
      yield
    end
  end

  def gc_profiler_usable?
    if defined?(::GC::Profiler) && !jruby?
      true
    else
      false
    end
  end

  def gc_profiler_enabled?
    if gc_profiler_usable? && ::GC::Profiler.enabled? && !::NewRelic::Agent.config[:disable_gc_profiler]
      true
    else
      false
    end
  end

  def object_space_usable?
    if defined?(::JRuby) && JRuby.respond_to?(:runtime)
      JRuby.runtime.is_object_space_enabled
    elsif defined?(::ObjectSpace) && !rubinius?
      true
    else
      false
    end
  end

  if ::RUBY_VERSION >= RUBY_VERSION_192
    def uniq_accepts_block?; true; end
  else
    def uniq_accepts_block?; false; end
  end

  def jruby?
    defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
  end

  def rubinius?
    defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
  end

  def ree?
    defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /Ruby Enterprise Edition/
  end

  def using_version?(version)
    numbers = version.split('.')
    numbers == ::RUBY_VERSION.split('.')[0, numbers.size]
  end

  def supports_string_encodings?
    RUBY_VERSION >= '1.9.0'
  end

  def constantize(const_name)
    const_name.to_s.sub(/\A::/,'').split('::').inject(Object) do |namespace, name|
      begin
        result = namespace.const_get(name)

        # const_get looks up the inheritence chain, so if it's a class
        # in the constant make sure we found the one in our namespace.
        #
        # Can't help if the constant isn't a class...
        if result.is_a?(Module)
          expected_name = "#{namespace}::#{name}".gsub(/^Object::/, "")
          return unless expected_name == result.to_s
        end

        result
      rescue NameError
        nil
      end
    end
  end

  def test_forkability
    child = Process.fork { exit! }
    # calling wait here doesn't seem like it should necessary, but it seems to
    # resolve some weird edge cases with resque forking.
    Process.wait child
    true
  rescue NotImplementedError
    false
  end

  def bundled_gem?(gem_name)
    defined?(Bundler) && Bundler.rubygems.all_specs.map(&:name).include?(gem_name)
  rescue => e
    ::NewRelic::Agent.logger.info("Could not determine if third party #{gem_name} gem is installed", e)
    false
  end
end
