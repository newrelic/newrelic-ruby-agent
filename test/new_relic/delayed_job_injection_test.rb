require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
module NewRelic
  class DelayedJobInstrumentationTest < Test::Unit::TestCase
    def test_skip_logging_if_no_logger_found
      Object.const_set('Delayed', Module.new)
      ::Delayed.const_set('Worker', true)
      
      NewRelic::Agent.stubs(:logger).raises(NoMethodError,
                                            'tempoarily not allowed')
      NewRelic::Agent.stubs(:respond_to?).with(:logger).returns(false)
      
      DependencyDetection.detect!
    end
  end
end
