# this class encapsulates an error that was noticed by RPM in a managed app.
# Unfortunately it was put in the agent in the global namespace early on and
# for backward compatibility it needs to remain here.
class NewRelic::NoticedError
  attr_accessor :path, :timestamp, :params, :exception_class, :message
  
  def initialize(path, data, exception)
    self.path = path
    self.params = data
    
    self.exception_class = exception.class.name
    
    if exception.respond_to?('original_exception')
      self.message = exception.original_exception.message.to_s
    else
      self.message = exception.message.to_s
    end
    
    # clamp long messages to 4k so that we don't send a lot of
    # overhead across the wire
    self.message = self.message[0..4096] if self.message.length > 4096

    self.timestamp = Time.now
  end
end
