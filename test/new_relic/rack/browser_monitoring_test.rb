require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/browser_monitoring'

ENV['RACK_ENV'] = 'test'

class BrowserMonitoringTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    @doc ||= <<-EOL
<html>
  <head>
    <title>im a title</title>
    <meta some-crap="1"/>
    <script>
      junk
    </script>
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"/>
  </head>
  <body>im some body text</body>
</html>
EOL
    mock_app = lambda { |env| [200, {}, @doc] }
    NewRelic::Rack::BrowserMonitoring.new(mock_app)
  end

  def setup
    NewRelic::Agent.stubs(:browser_timing_header) \
      .returns("<script>header</script>")
    NewRelic::Agent.stubs(:browser_timing_footer) \
      .returns("<script>footer</script>")

    # this version of rack/test doesn't let us play with http headers
    NewRelic::Rack::BrowserMonitoring.any_instance \
      .stubs(:should_instrument?).returns(true)
  end
  
  def test_should_only_instrument_successfull_html_requests
    NewRelic::Rack::BrowserMonitoring.any_instance.unstub(:should_instrument?)

    assert app.should_instrument?(200, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(500, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(200, {'Content-Type' => 'text/xml'})
  end

  def test_insert_timing_header_right_after_last_meta_tag_in_head
    get '/'
    
    assert(last_response.body.include?("chrome=1\"/>#{NewRelic::Agent.browser_timing_header}"), last_response.body)
  end

  def test_insert_timing_header_right_after_open_head_if_no_meta_tags
    @doc = <<-EOL
<html>
  <head>
    <title>im a title</title>
    <script>
      junk
    </script>
  </head>
  <body>im some body text</body>
</html>
EOL
    get '/'
    
    assert(last_response.body.include?("head>#{NewRelic::Agent.browser_timing_header}"), last_response.body)
    @doc = nil
  end

  def test_insert_timing_footer_right_before_html_body_close
    get '/'
    
    assert(last_response.body.include?("#{NewRelic::Agent.browser_timing_footer}</body>"), last_response.body)
  end
end
