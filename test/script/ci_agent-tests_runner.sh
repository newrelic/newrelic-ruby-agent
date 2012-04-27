#!/bin/bash -e


#git pull git@github.com:newrelic/ruby_agent-tests.git

echo $PWD 

exit 0

if [ -x tmp ] ; then
	echo "found tmp, deleting"
	rm -fr tmp
fi 

#echo "creating tmp dir"
#mkdir tmp
#echo "cd'ing to tmp"
# cd tmp
# echo $PWD


# exit 0
#env
#ls -al /home/hudson/.rvm/bin
# source ~/.rvm/scripts/rvm
# rvm 1.9.2
# ruby -v

# rvm --force gemset delete ruby_agent-tests

# rvm gemset create ruby_agent-tests

# rvm gemset use ruby_agent-tests
# gem install bundler
# bundle update
# bundle

##
# bundle exec ruby fake_collector.rb
# bundle exec ruby sinatra_metric_explosion_test.rb

########
# clear out gemset for next test set
#

# cd rails3viewfedex
# rvm --force gemset delete ruby_agent-tests

# rvm gemset create ruby_agent-tests

# rvm gemset use ruby_agent-tests

# gem install bundler
# bundle update
# bundle
# bundle exec ruby view_instrumentation_test.rb
#exit 0
