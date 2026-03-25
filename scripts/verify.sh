#!/usr/bin/env bash
# Sanity check: gemspec layout and require path load with declared dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f Gemfile ]; then
  bundle check >/dev/null 2>&1 || bundle install
  bundle exec ruby -e "require 'dragdropdo_sdk'; raise 'version missing' unless defined?(D3RubyClient::VERSION) && D3RubyClient::VERSION"
else
  ruby -I lib -e "require 'dragdropdo_sdk'"
fi
echo "Ruby gem load: OK"
