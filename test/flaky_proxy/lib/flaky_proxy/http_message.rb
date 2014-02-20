# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'http/parser'
require 'webrick'

module FlakyProxy
  MAXBUF = 10 * 4096 # 40KB

  class HttpMessage
    def self.read_from(io)
      msg = self.new
      msg.read(io)
      msg
    end

    attr_reader :raw_data

    def initialize
      @parser = Http::Parser.new
      @raw_data = ''
      @complete = false
      @parser.on_message_complete = proc do |env|
        @complete = true
      end
    end

    def request_url
      @parser.request_url if complete?
    end

    def request_path
      @parser.request_path if complete?
    end

    def <<(data)
      @raw_data << data
      @parser << data
    end

    def read(io)
      loop do
        return if complete? || io.closed?
        ready = select([io])
        if ready && ready.first.include?(io)
          if io.eof?
            return
          else
            self << io.readpartial(MAXBUF)
          end
        end
      end
    rescue Errno::ECONNRESET
      FlakyProxy::Logger.warn("Connection reset by peer when reading from #{io}")
    end

    def complete?
      @complete
    end

    def relay_to(io)
      io.write(@raw_data)
    end
  end

  class Request < HttpMessage
    def request_method
      @parser.http_method
    end
  end

  class Response < HttpMessage
    def self.build(options={})
      defaults = {
        :status => 200,
        :headers => {},
        :body => ''
      }
      options = defaults.merge(options)
      status_line = build_status_line(options[:status])
      headers = build_headers(options[:body], options[:headers])

      rsp = self.new
      rsp << status_line
      rsp << headers
      rsp << "\r\n"
      rsp << options[:body]
      rsp
    end

    def self.build_status_line(status)
      status_text = WEBrick::HTTPStatus::StatusMessage[status]
      "HTTP/1.1 #{status} #{status_text}\r\n"
    end

    def self.build_headers(body, headers)
      default_headers = {
        'Content-Length' => body.bytesize
      }
      headers = default_headers.merge(headers)
      headers.map do |key, value|
        "#{key}: #{value}\r\n"
      end.join
    end
  end
end
