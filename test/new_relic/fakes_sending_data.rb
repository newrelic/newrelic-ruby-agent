module NewRelic
  module FakesSendingData
    def calls_for(method)
      @agent_data. \
        select { |d| d.action == method }. \
        map { |d| d.body }
    end

    # Unpeel the inner layers of encoding applied by the JSON marshaller.
    # I'm sorry.
    def unpack_inner_blobs(req)
      body = req.body
      if req.format == :json
        case req.action
        when 'profile_data' then
          body[0][4] = unpack(body[0][4])
        when 'sql_trace_data' then
          body[0][0][9] = unpack(body[0][0][9])
        when 'transaction_sample_data' then
          body[4] = unpack(body[4])
        end
      end
      body
    end

    def unpack(blob)
      JSON.load(Zlib::Inflate.inflate(Base64.decode64(blob)))
    end
  end
end
