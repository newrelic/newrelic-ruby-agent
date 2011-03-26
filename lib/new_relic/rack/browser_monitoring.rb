require 'rack'

module NewRelic::Rack
  class BrowserMonitoring

    def initialize(app, options = {})
      @app = app
    end
      
    # method required by Rack interface
    def call(env)
      call! env
    end

    # thread safe version using shallow copy of env
    def call!(env)
      @env = env.dup
      status, @headers, response = @app.call(@env)
      if should_instrument?(@headers, status) && (browser_header != "")
        response = Rack::Response.new(autoinstrument_source(response), status, @headers)
        response.finish
      else
        [status, @headers, response]
      end
    end
    
    def should_instrument?(headers, status)
      status == 200 && headers["Content-Type"] && headers["Content-Type"].include?("text/html")
    end

    def autoinstrument_source(response)      
#      start = Time.now

      source = ""
      response.each {|f| source << f}

      body_start = source.index("<body")
      body_close = source.rindex("</body>")
      
      if body_start && body_close
        footer = browser_footer
        header = browser_header

        head_open = source.index("<head")

        if head_open
          head_close = source.index(">", head_open)
          
          head_pos = head_close + 1
        else
          # put the header right above body start
          head_pos = body_start
        end
        
        source = source[0..(head_pos-1)] + header + source[head_pos..(body_close-1)] + footer + source[body_close..source.length]
        
        @headers['Content-Length'] = source.length.to_s if @headers['Content-Length'] 
        
#        puts "Total time to parse (ms): #{(Time.now - start) * 1000}"
      end

      source
    end
        
    def browser_header
      NewRelic::Agent.browser_timing_header
    end
    
    def browser_footer
      NewRelic::Agent.browser_timing_footer
    end
  end
end
