module NewRelic::LanguageSupport  
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
