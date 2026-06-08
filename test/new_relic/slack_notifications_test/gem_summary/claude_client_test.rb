# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# HTTParty is only installed by the slack_notifications_tests CI job, not bundled with
# the main test suite. This check ensures these tests run in that job but are skipped
# when the test file is picked up by the glob pattern during regular test runs.
begin
  require 'httparty'
rescue LoadError
  nil
end

if defined?(HTTParty)
  # TODO: MAJOR VERSION - Remove this version constraint when we update the
  # minitest version in the gemspec
  gem 'minitest', '5.3.3'
  require 'minitest/autorun'
  require_relative '../../../../.github/workflows/scripts/slack_notifications/gem_summary/claude_client'

  class ClaudeClientTests < Minitest::Test
    def setup
      @original_key = ENV.delete('ANTHROPIC_API_KEY')
      @original_endpoint = ENV.delete('CLAUDE_API_ENDPOINT')
    end

    def teardown
      ENV['ANTHROPIC_API_KEY'] = @original_key if @original_key
      ENV['CLAUDE_API_ENDPOINT'] = @original_endpoint if @original_endpoint
    end

    def with_credentials
      ENV['ANTHROPIC_API_KEY'] = 'test-key'
      ENV['CLAUDE_API_ENDPOINT'] = 'http://test/v1/messages'
      yield
    end

    def successful_response(text = 'summary')
      response = Minitest::Mock.new
      response.expect(:code, 200)
      response.expect(:body, JSON.dump('content' => [{'text' => text}]))
      response
    end

    def response_with_code(code)
      response = Minitest::Mock.new
      response.expect(:code, code)
      response
    end

    def response_with_body(body)
      response = Minitest::Mock.new
      response.expect(:code, 200)
      response.expect(:body, body)
      response
    end

    def test_send_message_returns_nil_when_credentials_missing
      capture_io do
        assert_nil GemSummary::ClaudeClient.new.send_message('prompt')
      end
    end

    def test_send_message_returns_text_on_200
      with_credentials do
        HTTParty.stub(:post, successful_response('hello world')) do
          assert_equal 'hello world', GemSummary::ClaudeClient.new.send_message('prompt')
        end
      end
    end

    def test_send_message_returns_nil_on_non_200_response
      with_credentials do
        HTTParty.stub(:post, response_with_code(401)) do
          assert_nil GemSummary::ClaudeClient.new.send_message('prompt')
        end
      end
    end

    def test_send_message_returns_nil_on_unexpected_response_shape
      with_credentials do
        HTTParty.stub(:post, response_with_body(JSON.dump('error' => 'rate limited'))) do
          assert_nil GemSummary::ClaudeClient.new.send_message('prompt')
        end
      end
    end

    def test_send_message_posts_request_with_expected_body_and_headers
      captured_url = nil
      captured_options = nil
      stubbed_post = lambda do |url, options|
        captured_url = url
        captured_options = options
        successful_response('ok')
      end

      with_credentials do
        HTTParty.stub(:post, stubbed_post) do
          GemSummary::ClaudeClient.new.send_message('hello prompt')
        end
      end

      assert_equal 'http://test/v1/messages', captured_url
      assert_equal 'application/json', captured_options[:headers]['Content-Type']
      assert_equal 'Bearer test-key', captured_options[:headers]['Authorization']

      body = JSON.parse(captured_options[:body])

      assert_equal GemSummary::ClaudeClient::MODEL, body['model']
      assert_equal GemSummary::ClaudeClient::MAX_TOKENS, body['max_tokens']
      assert_equal [{'role' => 'user', 'content' => 'hello prompt'}], body['messages']
    end

    def test_send_message_retries_once_on_exception
      call_count = 0
      stubbed_post = lambda do |*_args, **_kwargs|
        call_count += 1
        raise StandardError, 'boom' if call_count == 1

        successful_response('recovered')
      end

      with_credentials do
        client = GemSummary::ClaudeClient.new
        capture_io do
          client.stub(:sleep, nil) do
            HTTParty.stub(:post, stubbed_post) do
              assert_equal 'recovered', client.send_message('prompt')
            end
          end
        end
      end

      assert_equal 2, call_count
    end

    def test_send_message_returns_nil_after_retry_exhausted
      call_count = 0
      stubbed_post = lambda do |*_args, **_kwargs|
        call_count += 1
        raise StandardError, 'boom'
      end

      with_credentials do
        client = GemSummary::ClaudeClient.new
        capture_io do
          client.stub(:sleep, nil) do
            HTTParty.stub(:post, stubbed_post) do
              assert_nil client.send_message('prompt')
            end
          end
        end
      end

      assert_equal GemSummary::ClaudeClient::MAX_RETRIES + 1, call_count
    end
  end
end
