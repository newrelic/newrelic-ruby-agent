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
        if should_instrument?(@headers, status)
          response = Rack::Response.new(
            autoinstrument_source(response.respond_to?(:body) ? response.body : response),
            status,
            @headers
          )
          response.finish
          response.to_a
        else
          [status, @headers, response]
        end
      end
      
      def should_instrument?(headers, status)
        status == 200 && headers["Content-Type"] && headers["Content-Type"].include?("text/html")
      end


    def autoinstrument_source(source)
      start = Time.now
      body_start = source.index("<body")
      body_close = source.rindex("</body>")
      
      if body_start && body_close
        footer = browser_footer
        header = browser_header

        # FIXME bail if the header or footer is empty

        head_close = source[0..body_start].rindex("</head>")
        if head_close
          head_pos = head_close
        else
          head_pos = body_start
        end
#        puts "BROWSER TAGS INJECTED: Total time to parse: #{Time.now - start}"
        
        if @headers['Content-Length']
          @headers['Content-Length'] = (header.length + footer.length + @headers['Content-Length'].to_i).to_s
        end
        return source[0..(head_pos-1)] + header + source[head_pos..(body_close-1)] + footer + source[body_close..source.length]
      end
#      puts "total time to parse: #{Time.now - start}"
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