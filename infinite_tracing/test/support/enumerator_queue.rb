# An EnumeratorQueue wraps a Queue to yield the items added to it.
class EnumeratorQueue
  extend Forwardable
  def_delegators :@queue, :push, :empty?

  def initialize
    @queue = Queue.new
  end

  def preload items
    Array(items).each{ |item| @queue.push item }
    self   
  end

  def each_item
    return enum_for(:each_item) unless block_given?
    loop do
      value = @queue.pop
      break if value.nil?
      fail value if value.is_a? Exception
      yield value
    end
  end
end
