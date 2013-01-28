#!/bin/bash -e

SCRATH_DIR=./agent-tests_tmp
#git pull git@github.com:newrelic/ruby_agent-tests.git

#echo $PWD 
script_dirname=`dirname $0`
#echo $script_dirname
#echo $0

# make sure that we're in the project root
script_dirname=`dirname $0`
cd "$script_dirname/../../"



if [ -x $SCRATH_DIR ] ; then
	echo "found tmp, deleting"
	rm -fr $SCRATH_DIR
fi 

mkdir $SCRATH_DIR
cd $SCRATH_DIR

git clone --depth=1 git@github.com:newrelic/ruby_agent-tests.git ruby_agent-tests
git clone --depth=1 git@github.com:newrelic/rpm_contrib.git rpm_contrib

if [ -x ../../Ruby_Agent ] ; then
	ln -s ../../Ruby_Agent ./ruby_agent
else 
	echo "*********** Ruby_Agent can't be found ***********"
	exit 1
fi

#exit 0

cd ruby_agent-tests
./ci_run.sh 

#echo "creating tmp dir"
#mkdir tmp
#echo "cd'ing to tmp"
# cd tmp
# echo $PWD


# exit 0
#env
#ls -al /home/hudson/.rvm/bin
# source ~/.rvm/scripts/rvm
#rvm 1.9.2
#ruby -v

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
