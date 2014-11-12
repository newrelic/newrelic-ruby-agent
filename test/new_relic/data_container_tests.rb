# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# To use this module to test your new data container, implement the following
# methods before including it:
#
# create_container -> create an instance of your data container class
# populate_container(container, n) -> populate the container with n items
#
# If your container can only hold a fixed number of data items, you can also
# implement #max_data_items to return the number of data items that it should be
# populated with for the purposes of testing.

module NewRelic
  module BasicDataContainerMethodTests
    def test_should_respond_to_required_methods
      c = create_container
      assert c.respond_to?(:harvest!)
      assert c.respond_to?(:reset!)
      assert c.respond_to?(:merge!)
    end
  end

  module BasicDataContainerTests
    include BasicDataContainerMethodTests

    def num_data_items
      self.respond_to?(:max_data_items) ? max_data_items : 5
    end

    def test_harvest_should_return_all_data_items
      c = create_container
      populate_container(c, num_data_items)
      results = c.harvest!
      assert_equal(num_data_items, results.size)
    end

    def test_calling_harvest_again_should_not_return_items_again
      c = create_container
      populate_container(c, num_data_items)

      c.harvest! # clears container
      results = c.harvest!
      assert_equal(0, results.size)
    end

    def test_calling_harvest_after_re_populating_works
      c = create_container
      populate_container(c, num_data_items)
      assert_equal(num_data_items, c.harvest!.size)

      populate_container(c, num_data_items)
      assert_equal(num_data_items, c.harvest!.size)
    end
  end

  module DataContainerTests
    include BasicDataContainerTests

    def test_reset_should_clear_stored_items
      c = create_container
      populate_container(c, 5)
      c.reset!
      assert_equal(0, c.harvest!.size)
    end

    def test_merge_should_re_integrate_items
      c = create_container
      populate_container(c, 5)
      c.merge!(c.harvest!)
      results = c.harvest!
      assert_equal(5, results.size)
    end
  end
end
