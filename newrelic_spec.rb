# Specs not currently implemented.  Unit tests may only run when this is installed
# as a plugin in a Rails application.
require File.dirname(__FILE__) + '/spec_helper'

describe "newrelic" do
  it "should do nothing" do
    true.should == true
  end
end