module NewRelic
  module FakesSendingData
    def calls_for(method)
      @agent_data. \
        select { |d| d.action == method }. \
        map { |d| d.body }
    end
  end
end
