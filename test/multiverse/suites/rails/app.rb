require 'action_controller/railtie'

# Once and only once!
if !defined?(MyApp)

  ENV['NEW_RELIC_DISPATCHER'] = 'test'

  class MyApp < Rails::Application
    # We need a secret token for session, cookies, etc.
    config.active_support.deprecation = :log
    config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
  end
  MyApp.initialize!

  MyApp.routes.draw do
    get('/bad_route' => 'Test#controller_error',
        :constraints => lambda do |_|
          raise ActionController::RoutingError.new('this is an uncaught routing error')
        end)
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

    def raise_error
      raise 'this is an uncaught model error'
    end

    def errors
      obj = Object.new
      def obj.[](key)         [] end
      def obj.full_messages() [] end
      obj
    end
  end

  class ErrorController < ApplicationController
    include Rails.application.routes.url_helpers
    newrelic_ignore :only => :ignored_action

    def controller_error
      raise 'this is an uncaught controller error'
    end

    def view_error
      render :inline => "<% raise 'this is an uncaught view error' %>"
    end

    def model_error
      Foo.new.raise_error
    end

    def ignored_action
      raise 'this error should not be noticed'
    end

    def ignored_error
      raise IgnoredError.new('this error should not be noticed')
    end

    def server_ignored_error
      raise ServerIgnoredError.new('this is a server ignored error')
    end

    def noticed_error
      newrelic_notice_error(RuntimeError.new('this error should be noticed'))
      render :text => "Shoulda noticed an error"
    end
  end

  class QueueController < ApplicationController
    include Rails.application.routes.url_helpers

    def queued
      respond_to do |format|
        format.html { render :text => "<html><head></head><body>Queued</body></html>" }
      end
    end
  end

  ActionController::Base.view_paths = ['app/views']

  class ViewsController < ApplicationController
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
      # We need any old file that's around, preferrably with ERB embedding
      file = File.expand_path(File.join(File.dirname(__FILE__), "Envfile"))
      render :file => file, :content_type => 'text/plain', :layout => false
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

  class GcController < ApplicationController
    include Rails.application.routes.url_helpers
    def gc_action
      GC.disable

      long_string = "01234567" * 100_000
      long_string = nil
      another_long_string = "01234567" * 100_000

      start = Time.now
      GC.enable
      GC.start
      stop = Time.now

      @duration = stop.to_f - start.to_f

      render :text => @duration.to_s
    ensure
      GC.enable
    end
  end
end
