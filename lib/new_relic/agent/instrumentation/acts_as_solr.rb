if defined?(ActsAsSolr)
  
  module NewRelic
    module Instrumentation
      module ActsAsSolrInstrumentation
        module ParserMethodsInstrumentation
          def parse_query_with_newrelic(*args)
            self.class.trace_execution_scoped(["Solr/ActsAsSolr/query"]) do
              t0 = Time.now.to_f
              begin
                parse_query_without_newrelic(*args)
              ensure
                NewRelic::Agent.instance.transaction_sampler.notice_nosql(args.first.inspect, Time.now.to_f - t0) rescue nil
              end
            end
            
          end
        end
      end
    end
  end

  module ActsAsSolr
    module ParserMethods
      include NewRelic::Instrumentation::ActsAsSolrInstrumentation::ParserMethodsInstrumentation
      alias :parse_query_without_newrelic :parse_query
      alias :parse_query :parse_query_with_newrelic
    end

    module ClassMethods
      add_method_tracer :find_by_solr, 'Solr/ActsAsSolr/find_by_solr'
    end
  end
end

