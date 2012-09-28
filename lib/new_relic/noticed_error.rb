# This class encapsulates an error that was noticed by New Relic in a managed app.
class NewRelic::NoticedError
  extend NewRelic::CollectionHelper
  attr_accessor :path, :timestamp, :params, :exception_class, :message
  attr_reader :exception_id

  def initialize(path, data, exception, timestamp = Time.now)
    @exception_id = exception.object_id
    @path = path
    @params = NewRelic::NoticedError.normalize_params(data)

    @exception_class = exception.is_a?(Exception) ? exception.class.name : 'Error'

    if exception.respond_to?('original_exception')
      @message = exception.original_exception.message.to_s
    else
      @message = (exception || '<no message>').to_s
    end

    # clamp long messages to 4k so that we don't send a lot of
    # overhead across the wire
    @message = @message[0..4095] if @message.length > 4096
    
    # obfuscate error message if necessary
    if NewRelic::Agent.config[:high_security]
      @message = NewRelic::Agent::Database.obfuscate_sql(@message)
    end
    
    @timestamp = timestamp
  end

  def ==(other)
    if other.respond_to?(:exception_id)
      @exception_id == other.exception_id
    else
      false
    end
  end
end
