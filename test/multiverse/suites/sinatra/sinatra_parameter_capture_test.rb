# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SinatraParameterCaptureTestApp < Sinatra::Base
  post "/capture_test" do
    "capture test"
  end

  post '/files' do
    "file uploaded"
  end
end


class SinatraParameterCaptureTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    SinatraParameterCaptureTestApp
  end

  def app_name
    app.to_s
  end

  def test_request_params_are_captured_for_transaction_events
    with_config(:'attributes.include' => 'request.parameters.*',
                :'attributes.exclude' => ['request.*', 'response.*']) do
      params = {
        :foo => "bar",
        :bar => "baz"
      }
      post '/capture_test', params
    end

    expected = {
      "request.parameters.foo" => "bar",
      "request.parameters.bar" => "baz"
    }

    actual = agent_attributes_for_single_event_posted_without_ignored_attributes

    assert_equal(expected, actual)
  end

  def test_file_upload_params_are_filtered
    with_config(:capture_params => true) do
      params = {
        :title => "blah",
        :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
      }
      post '/files', params

      expected = {
        "request.parameters.title" => "blah",
        "request.parameters.file" => "[FILE]"
      }

      assert_equal(expected, last_transaction_trace_request_params)
    end
  end

  def test_request_and_response_attributes_recorded_as_agent_attributes
    post '/capture_test'

    expected = {
      "response.headers.contentLength" => last_response.content_length.to_i,
      "response.headers.contentType" => last_response.content_type,
      "request.headers.contentLength" => last_request.content_length.to_i,
      "request.headers.contentType" => last_request.content_type,
      "request.headers.host" => last_request.host,
      "request.method" => last_request.request_method
    }
    actual = agent_attributes_for_single_event_posted_without_ignored_attributes

    assert_equal(expected, actual)
  end
end
