module NewRelic::LanguageSupport
  module DataSerialization
    def self.included(base)
      # need to disable GC during marshal load in 1.8.7
      if ::RUBY_VERSION == '1.8.7'
        base.class_eval do
          def self.load(*args)
            GC.disable
            val = super
            GC.enable
            val
          end
        end
      end
    end
  end
  
  module Control
    def self.included(base)
      # need to use syck rather than psych when possible
      if defined?(::YAML::ENGINE)
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
  
  module SynchronizedHash
    def self.included(base)
      # need to lock iteration of stats hash in 1.9.x
      if ::RUBY_VERSION.split('.')[0,2] == ['1','9']
        base.class_eval do
          def each(*args, &block)
            sync_synchronize(:SH) { super }
          end
        end
      end
    end
  end
end
