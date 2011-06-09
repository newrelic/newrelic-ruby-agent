require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/browser_monitoring'

ENV['RACK_ENV'] = 'test'

class BrowserMonitoringTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    doc = <<-EOL
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
    mock_app = lambda { |env| [200, {}, doc] }
    NewRelic::Rack::BrowserMonitoring.new(mock_app)
  end
  
  def test_should_only_instrument_successfull_html_requests
    assert app.should_instrument?(200, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(500, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(200, {'Content-Type' => 'text/xml'})
  end

  def test_insert_timing_header_right_after_html_head_open
    get '/'
    assert(last_response.body.include?("<head>#{NewRelic::Agent.browser_timing_header}"))

  end

  def test_insert_timing_footer_right_before_html_body_close
    get '/'
    assert(last_response.body.include?("#{NewRelic::Agent.browser_timing_footer}</body>"))
  end
end
