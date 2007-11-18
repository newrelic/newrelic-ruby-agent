require "test/unit"
require "seldon/metric_parser"

module Seldon
  class MyMetric
    include MetricParser
    attr_reader :name
    
    def initialize(metric_name)
      @name = metric_name
    end
  end
  
  class MetricParserTests < Test::Unit::TestCase
    def test_controller
      ["Controller/1/2/3","Controller//!!#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert m.is_controller?
        assert !m.is_database?
        assert !m.is_web_service?
      end
      
      ["controller","Controller+1/2/3","Lew//!!#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert !m.is_controller?
      end
    end

    def test_web_service
      ["WebService","WebService/1/2/3","WebService//!!#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert !m.is_controller?
        assert !m.is_database?
        assert m.is_web_service?
      end
      
      ["webService","WEBService+1/2/3","Lew//!!#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert !m.is_web_service?
      end
    end
    
    def test_database
      ["ActiveRecord","ActiveRecord/1/2/3","ActiveRecord//!!#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert !m.is_controller?
        assert m.is_database?
        assert !m.is_web_service?
      end
      
      ["ActiveRecordxx","ActiveRecord+1/2/3","ActiveRecord#!//"].each do | metric_name |
        m = MyMetric.new(metric_name)
        
        assert !m.is_database?
      end
    end
  end
end

