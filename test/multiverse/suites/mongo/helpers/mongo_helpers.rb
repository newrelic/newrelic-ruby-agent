module NewRelic
  module MongoHelpers
    def mongo_logger
      if ENV["VERBOSE"]
        Mongo::Logger.Logger
      else
        filename = File.join(`pwd`.chomp, 'log', 'mongo_test.log')
        Logger.new(filename)
      end
    end
  end
end