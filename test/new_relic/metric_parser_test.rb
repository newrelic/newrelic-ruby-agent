require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))

class MyMetric
  attr_reader :name
  
  def initialize(metric_name)
    @name = metric_name
    self.extend NewRelic::MetricParser
  end
end

class MetricParserTest < Test::Unit::TestCase

  def test_memcache
    m = "MemCache/read"
    m.extend NewRelic::MetricParser
    assert_equal "MemCache read", m.developer_name
  end
  def test_string
    %w[Controller/posts/index View/posts/index WebService/posts Custom/posts Unrecognized/posts XX/posts].each do | name |
      name.extend NewRelic::MetricParser
      assert_equal "posts", name.segments[1]
    end
    m = "View/something/Rendering"
    m.extend NewRelic::MetricParser
    assert_equal m, m.name
    assert m.is_view?
    assert !m.is_controller?
  end

  def test_view__short
    i = NewRelic::MetricParser.parse("View/.rhtml Processing")
    assert_equal "ERB compilation", i.developer_name
  end
  def test_controller
    ["controller", "Controller/1/2/3","Controller//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert m.is_controller?
      assert !m.is_view?
      assert !m.is_database?
      assert !m.is_web_service?
    end
    
    ["Controller+1/2/3","Lew//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert !m.is_controller?
    end
  end
  
  def test_controller_cpu
    ["Controller/1/2/3","Controller//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert m.is_controller?
      assert !m.is_view?
      assert !m.is_database?
      assert !m.is_web_service?
    end
    
    ["ControllerCPU/1/2/3","ControllerCPU//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert m.is_controller_cpu?
      assert !m.is_view?
      assert !m.is_controller?
      assert !m.is_database?
      assert !m.is_web_service?
      
      assert_not_nil m.base_metric_name
      assert m.base_metric_name.starts_with?('Controller/')
    end
    
  end
  
  def test_web_service
    ["WebService/x/Controller/", "WebService","WebService/1/2/3","WebService//!!#!//"].each do |metric_name|
      m = MyMetric.new(metric_name)
      
      assert !m.is_controller?
      assert !m.is_view?
      assert !m.is_database?
      assert m.is_web_service?
    end
    
    ["Web/Service","WEBService+1/2/3","Lew//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert !m.is_web_service?, metric_name
    end
  end
  
  def test_database
    ["ActiveRecord","ActiveRecord/1/2/3","ActiveRecord//!!#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert !m.is_view?
      assert !m.is_controller?
      assert m.is_active_record?, "#{metric_name}: #{m.category}"
      assert !m.is_web_service?
    end
    
    ["ActiveRecordxx","ActiveRecord+1/2/3","ActiveRecord#!//"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert !m.is_database?
    end
  end
  def test_view
    %w[View/posts/post/Rendering View/admin/users/view/Partial View/ERB/Compile].each do | name |
      m = MyMetric.new(name)
      assert !m.is_database?
      assert !m.is_controller?
      assert !m.is_web_service?
      assert !m.is_error?
      assert m.is_view?
    end
  end
  def test_view__render
    m = NewRelic::MetricParser.parse "View/blogs/show.html.erb/Rendering"
    
    short_name = "show.html.erb Template"
    long_name = "blogs/show.html.erb Template"
    assert_equal short_name, m.pie_chart_label
    assert_equal long_name, m.developer_name
    assert_equal short_name, m.pie_chart_label
    assert_equal "blogs/show.html.erb Template", m.controller_name
    assert_equal "show", m.action_name
    assert_equal "/blogs/show.html.erb", m.url
  end
  def test_view__partial
    m = "View/admin/users/view.html.erb/Partial"
    m.extend NewRelic::MetricParser
    m.pie_chart_label
    assert_equal "view.html.erb Partial", m.pie_chart_label
    assert_equal "admin/users/view.html.erb Partial", m.developer_name
    assert_equal "admin/users/view.html.erb Partial", m.controller_name
    assert_equal "view", m.action_name
    assert_equal "/admin/users/view.html.erb", m.url
  end
  def test_view__rhtml
    m = "View/admin/users/view.rhtml/Rendering"
    m.extend NewRelic::MetricParser
    m.pie_chart_label
    assert_equal "view.rhtml Template", m.pie_chart_label
    assert_equal "admin/users/view.rhtml Template", m.developer_name
    assert_equal "admin/users/view.rhtml Template", m.controller_name
    assert_equal "view", m.action_name
    assert_equal "/admin/users/view.rhtml", m.url
  end
  def test_error
    ["Errors","Errors/Type/MyType","Errors/Controller/MyController/"].each do | metric_name |
      m = MyMetric.new(metric_name)
      
      assert !m.is_database?
      assert !m.is_controller?
      assert !m.is_web_service?
      assert !m.is_view?
      assert m.is_error?
    end
    
    m = MyMetric.new("Errors/Type/MyType")
    assert_equal m.short_name, 'MyType'
  end
end
