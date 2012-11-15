require 'resolv'

class NoDnsResolv < Test::Unit::TestCase
  def test_should_no_resolva_da_host
    Resolv.class_eval do

      # def self.getaddress(host)
      #   raise "Resolv.getaddress called when it shouldn't have been!"
      # end

      if RUBY_VERSION == '1.9.2'
        class_variable_set(:@@getaddress_called,false)
      else
        @@getaddress_called = false
      end

      def self.getaddress(host)
        @@getaddress_called = true
        puts "address for #{host} requested"
        "127.0.0.1"
      end

      def self.getaddress_called?
        @@getaddress_called
      end
    end

    # assert_nothing_raised do
       require 'newrelic_rpm'
    # end

    assert(!Resolv.getaddress_called?,
          'called Resolv.getaddress when we should not have')
  end
end
