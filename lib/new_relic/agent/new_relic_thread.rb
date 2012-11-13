class NewRelicThread < Thread
  def initialize(label)
    self[:newrelic_label] = label
    super
  end

  def self.is_new_relic?(thread)
    thread.key?(:newrelic_label) 
  end
end
