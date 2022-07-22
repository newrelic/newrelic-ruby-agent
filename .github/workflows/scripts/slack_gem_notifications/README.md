# Slack Gem Notifications

An internal tool for alerting the Ruby agent team of Ruby gem version updates. 

## Description

This script runs every 24 hours via GitHub Actions and uses the RubyGems API to see if gems were updated during that time. A slack alert is sent to the Ruby agent team's notification channel when an update is found. This alert contains the updated gem name, the gem's previous and latest version, and how to view more information on the update.

## Helpful Information

### Adding or Removing Gems

The `gem_notifications.yml` file contains a list of gems that are checked for updates. Gems can be added or removed from this list to adjust notifications.

### Slack Dependency

This project uses the internal Ruby Gem Updates slackbot to post notifications. This bot only posts to authorized slack channels, which can be managed on the Ruby Gem Updates configuration page.

## Relevant Project Files

* `.github/workflows/scripts/slack_gem_notifications/notifications_script.rb`
* `.github/workflows/scripts/slack_gem_notifications/notifications_methods.rb`
* `.github/workflows/gem_notifications.yml`
* `test/new_relic/gem_notifications_tests.rb`
