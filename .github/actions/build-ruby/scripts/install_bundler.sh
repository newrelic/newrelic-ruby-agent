
#!/bin/bash
#
# our testing kicks off > 180 travis "builds" so let's use a local gemstash
# mirror for all of our rubygems needs if we are in our internal testing env

set -ev
sudo gem install bundler -v '~> 1' --no-document -​-bindir $BUNDLE_PATH

