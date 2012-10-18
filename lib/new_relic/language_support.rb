module NewRelic::LanguageSupport
  extend self

  module Control
    def self.included(base)
      # need to use syck rather than psych when possible
      if defined?(::YAML::ENGINE)
        if !NewRelic::LanguageSupport.using_engine?('jruby') &&
            (NewRelic::LanguageSupport.using_version?('1.9.1') ||
             NewRelic::LanguageSupport.using_version?('1.9.2'))
          base.class_eval do
            def load_newrelic_yml(*args)
              yamler = ::YAML::ENGINE.yamler
              ::YAML::ENGINE.yamler = 'syck'
              val = super
              ::YAML::ENGINE.yamler = yamler
              val
            end
          end
        end
      end
    end
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

  def using_version?(version)
    numbers = version.split('.')
    numbers == ::RUBY_VERSION.split('.')[0, numbers.size]
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
end
