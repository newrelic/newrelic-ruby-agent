# ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/developer_mode'

ENV['RACK_ENV'] = 'test'

class DeveloperModeTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include TransactionSampleTestHelper

  def app
    mock_app = lambda { |env| [500, {}, "Don't touch me!"] }
    NewRelic::Rack::DeveloperMode.new(mock_app)
  end

  def setup
    @test_config = { 'developer_mode' => true }
    NewRelic::Agent.config.apply_config(@test_config)
    @sampler = NewRelic::Agent::TransactionSampler.new
    run_sample_trace_on(@sampler, '/here')
    run_sample_trace_on(@sampler, '/there')
    run_sample_trace_on(@sampler, '/somewhere')
    NewRelic::Agent.instance.stubs(:transaction_sampler).returns(@sampler)
  end

  def teardown
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def test_index_displays_all_samples
    get '/newrelic'

    assert last_response.ok?
    assert last_response.body.include?('/here')
    assert last_response.body.include?('/there')
    assert last_response.body.include?('/somewhere')
  end

  def test_show_sample_summary_displays_sample_details
    get "/newrelic/show_sample_summary?id=#{@sampler.samples[0].sample_id}"

    assert last_response.ok?
    assert last_response.body.include?('/here')
    assert last_response.body.include?('SandwichesController')
    assert last_response.body.include?('index')
  end

  def test_explain_sql_displays_query_plan
    sample = @sampler.samples[0]
    sql_segment = sample.sql_segments[0]
    explain_results = NewRelic::Agent::Database.process_resultset(example_explain_as_hashes)

    NewRelic::TransactionSample::Segment.any_instance.expects(:explain_sql).returns(explain_results)
    get "/newrelic/explain_sql?id=#{sample.sample_id}&segment=#{sql_segment.segment_id}"

    assert last_response.ok?
    assert last_response.body.include?('PRIMARY')
    assert last_response.body.include?('Key Length')
    assert last_response.body.include?('Using index')
  end

  private

  def example_explain_as_hashes
    [{
      'Id' => '1',
      'Select Type' => 'SIMPLE',
      'Table' => 'sandwiches',
      'Type' => 'range',
      'Possible Keys' => 'PRIMARY',
      'Key' => 'PRIMARY',
      'Key Length' => '4',
      'Ref' => '',
      'Rows' => '1',
      'Extra' => 'Using index'
    }]
  end
end
