require "action_controller/railtie"
require "rails/test_unit/railtie"
require 'rails/test_help'
require 'test/unit'

# BEGIN RAILS APP

ActionController::Base.view_paths = ['app/views']

class MyApp < Rails::Application
  # We need a secret token for session, cookies, etc.
  config.active_support.deprecation = :log
  config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
  config.after_initialize do
    NewRelic::Agent.manual_start
  end
end
MyApp.initialize!

MyApp.routes.draw do
  match '/:controller(/:action(/:id))'
end

class ApplicationController < ActionController::Base; end

# a basic active model compliant model we can render
class Foo
  extend ActiveModel::Naming
  def to_model
    self
  end

  def valid?()      true end
  def new_record?() true end
  def destroyed?()  true end

  def errors
    obj = Object.new
    def obj.[](key)         [] end
    def obj.full_messages() [] end
    obj
  end
end
class TestController < ApplicationController
  include Rails.application.routes.url_helpers
  def template_render_with_3_partial_renders
    render 'index'
  end

  def deep_partial_render
    render 'deep_partial'
  end

  def text_render
    render :text => "Yay"
  end

  def json_render
    render :json => {"a" => "b"}
  end

  def xml_render
    render :xml => {"a" => "b"}
  end

  def js_render
    render :js => 'alert("this is js");'
  end

  def file_render
    render :file => File.expand_path(__FILE__), :content_type => 'text/plain', :layout => false
  end

  def nothing_render
    render :nothing => true
  end

  def inline_render
    render :inline => "<% Time.now %><p><%= Time.now %></p>"
  end

  def haml_render
    render 'haml_view'
  end

  def no_template
    render []
  end

  def collection_render
    render((1..3).map{|x| Foo.new })
  end

  # proc rendering isn't available in rails 3 but you can do nonsense like this
  # and assign an enumerable object to the response body.
  def proc_render
    streamer = Class.new
    def each
      10_000.times do |i|
        yield "This is line #{i}\n"
      end
    end
    self.response_body = streamer.new
  end

  def raise_render
    raise "this is an uncaught RuntimeError"
  end
end

# END RAILS APP


class TestControllerTest < ActionController::TestCase
  tests TestController
  def setup
    @controller = TestController.new
  end
end

# SANITY TESTS - Make sure nothing raises errors,
# unless it's supposed to
class SanityTest < TestControllerTest

  # assert we can call any of these renders with no errors
  # (except the one that does raise an error)
  (TestController.action_methods - ["raise_render"]).each do |method|
    test "should not raise errors on GET to #{method.inspect}" do
      get method.dup
    end

    test "should not raise errors on POST to #{method.inspect}" do
      post method.dup
    end
  end

  test "should allow an uncaught exception to propogate" do
    assert_raise RuntimeError do
      get :raise_render
    end
  end
end

# A controller action that renders 1 template and the same partial 3 times
class NormalishRenderTest < TestControllerTest
  test "should count all the template and partial segments" do
    get :template_render_with_3_partial_renders
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last
    assert_equal 5, sample.count_segments, "should be a node for the controller action, the template, and 3 partials (5)"
  end

  test "should have 3 segments with the metric name 'View/test/_a_partial.html.erb/Partial'" do
    get :template_render_with_3_partial_renders
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last

    partial_segments = sample.root_segment.called_segments.first.called_segments.first.called_segments
    assert_equal 3, partial_segments.size, "sanity check"

    assert_equal ['View/test/_a_partial.html.erb/Partial'], partial_segments.map(&:metric_name).uniq
  end
end

class TextRenderTest < TestControllerTest
  # it doesn't seem worth it to get consistent behavior here.
  if Rails::VERSION::MINOR.to_i == 0
    test "should not instrument rendering of text" do
      get :text_render
      sample = NewRelic::Agent.agent.transaction_sampler.samples.last
      assert_equal [], sample.root_segment.called_segments.first.called_segments
    end
  else
    test "should create a metric for the rendered text" do
      get :text_render
      sample = NewRelic::Agent.agent.transaction_sampler.samples.last
      text_segment = sample.root_segment.called_segments.first.called_segments.first
      assert_equal 'View/text template/Rendering', text_segment.metric_name
    end
  end
end

class InlineTemplateRenderTest < TestControllerTest
  test "should create a metric for the rendered inline template" do
    get :inline_render
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/inline template/Rendering', text_segment.metric_name
  end
end

class HamlRenderTest < TestControllerTest
  test "should create a metric for the rendered haml template" do
    get :haml_render
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/test/haml_view.html.haml/Rendering', text_segment.metric_name
  end
end

class MissingTemplateTest < TestControllerTest
  # Rails 3.0 has different behavior for rendering an empty array.  We're okay with this.
  if Rails::VERSION::MINOR.to_i == 0
    test "should create an proper metric when the template is unknown" do
      get :no_template
      sample = NewRelic::Agent.agent.transaction_sampler.samples.last
      text_segment = sample.root_segment.called_segments.first.called_segments.first
      assert_nil text_segment
    end
  else
    test "should create an proper metric when the template is unknown" do
      get :no_template
      sample = NewRelic::Agent.agent.transaction_sampler.samples.last
      text_segment = sample.root_segment.called_segments.first.called_segments.first
      assert_equal 'View/(unknown)/Partial', text_segment.metric_name
    end
  end
end

class CollectionTemplateTest < TestControllerTest
  test "should create a proper metric when we render a collection" do
    get :collection_render
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal "View/foos/_foo.html.haml/Partial", text_segment.metric_name
  end
end

class UninstrumentedRendersTest < TestControllerTest
  [:js_render, :xml_render, :proc_render, :json_render ].each do |action|
    test "should not instrument rendering of #{action.inspect}" do
      get action
      sample = NewRelic::Agent.agent.transaction_sampler.samples.last
      assert_equal [], sample.root_segment.called_segments.first.called_segments
    end
  end
end

class FileRenderTest < TestControllerTest
  test "should create a metric for rendered file that does not include the filename so it doesn't metric explode" do
    get :file_render
    sample = NewRelic::Agent.agent.transaction_sampler.samples.last
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/file/Rendering', text_segment.metric_name
  end
end

