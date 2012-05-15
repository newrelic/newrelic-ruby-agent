#!/bin/bash -e

SCRATH_DIR=./multiverse_tmp
script_dirname=`dirname $0`

# make sure that we're in the project root
cd "$script_dirname/../../"

if [ -x $SCRATH_DIR ] ; then
	echo "found tmp, deleting"
	rm -fr $SCRATH_DIR
fi

mkdir $SCRATH_DIR
cd $SCRATH_DIR

git clone --depth=1 git@github.com:newrelic/multiverse.git multiverse
git clone --depth=1 git@github.com:newrelic/rpm_contrib.git rpm_contrib

if [ -x ../../Ruby_Agent ] ; then
	ln -s ../../Ruby_Agent ./ruby_agent
else
	echo "*********** Ruby_Agent can't be found ***********"
	exit 1
fi

cd multiverse
#./ci_run.sh

pwd

