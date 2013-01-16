class TestingApp

  attr_accessor :response, :headers

  def initialize
    reset_headers
  end

  def reset_headers
    @headers = {'Content-Type' => 'text/html'}
  end

  def call(env)
    [200, headers, [response]]
  end

end
