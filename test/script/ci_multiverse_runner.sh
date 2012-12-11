#!/bin/bash -e

export PATH=$PATH:$HOME/bin

echo $HOME
echo $PATH
#ls $HOME/bin



if [ "x$RUBY" == "x" ] ; then
  export RUBY=1.9.3
fi

echo "Tests will be run using $RUBY"
#uname -a

SCRATH_DIR=./multiverse_tmp
script_dirname=`dirname $0`

# make sure that we're in the project root
cd "$script_dirname/../../"

#pwd 

if [ -x $SCRATH_DIR ] ; then
  echo "found tmp, deleting"
  rm -fr $SCRATH_DIR
fi

mkdir $SCRATH_DIR
cd $SCRATH_DIR

#pwd 
if [[ $JOB_NAME =~ "Pangalactic" ]] ; then 
  AGENT_LOCATION="../../../../../../Ruby_Agent"
else
  AGENT_LOCATION="../../Ruby_Agent"
fi

git clone --depth=1 git@github.com:newrelic/multiverse.git multiverse
git clone --depth=1 git@github.com:newrelic/rpm_contrib.git rpm_contrib

echo "Looking for Ruby Agent at $AGENT_LOCATION"
#ls -l ../../../../../../
#ls -l /home/hudson/workspace/

if [ -x $AGENT_LOCATION ] ; then
  ln -s $AGENT_LOCATION ./ruby_agent
else
  echo "*********** Ruby_Agent not found ***********"
  exit 1
fi

cd multiverse
#./ci_run.sh

#pwd
#ls -l ../

eval "$(rbenv init -)" || true
rbenv shell $RUBY
script/runner
