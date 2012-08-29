#!/bin/bash

# print commands in this script as they're invoked
#set -x
# fail if any command fails
set -e

. "$HOME/.rvm/scripts/rvm"

#rvm 1.9.3


if [ "x$BUILD_NUMBER" == "x" ]; then
  echo '$BUILD_NUMBER is undefined'
  echo 'setting $BUILD_NUMBER to alpha'
  BUILD_NUMBER=alpha
fi

SHA1=`git log --pretty=format:'%h' -n 1`
echo "building gem for commit $SHA1"

if [[ `gem list jeweler | grep [j]eweler | wc -l` -eq 1 ]]; then
  echo "detected jeweler. skipping install"
else
  gem install jeweler --no-ri --no-rdoc
fi

# setup a gems directory as a work area for artifacts
rm -rf gems/
mkdir gems

# an identifier including the hudson build number and the git sha1

# FIXME: don't include the $SHA1 since some of our builds systems are confused
# by this.
#BUILD_ID="$SHA1.$BUILD_NUMBER" #.$SHA1
BUILD_ID="$BUILD_NUMBER" #.$SHA1

# rewrite the version file, setting the patch identifier to include the
# BUILD_ID
perl -p -i -e "s#BUILD *= *.*\$#BUILD = '$BUILD_ID'#" lib/new_relic/version.rb

# generate the gemspec
rake gemspec

# build the gem
gem build *.gemspec

# move artifacts to the gems directory
cp *.gemspec gems/
mv *.gem gems/

cd gems

# create a tarfile including the gem and the gemspec
gem_version=`ls *.gem | sed 's/\.gem$//' | sed 's/newrelic_rpm-//'`
tar czvf newrelic_rpm_agent-${gem_version}.tar.gz *
