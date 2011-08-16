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
