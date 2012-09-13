module NewRelic::Rack
  class ErrorCollector
    def initialize(app, options={})
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Exception => exception
      request = Rack::Request.new(env)
      NewRelic::Agent.instance.error_collector.notice_error(exception,
                                                :uri => request.path,
                                            :referer => request.referer,
                                     :request_params => request.params)
      raise exception
    end
  end
end
