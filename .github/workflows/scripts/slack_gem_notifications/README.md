# Slack Notifications

An internal tool for alerting the Ruby agent team of gem version updates and Ruby CVEs. 

## Description

This script runs every 24 hours via GitHub Actions and sends notifications for 1) gem version updates and 2) Ruby security vulnerabilities.

Gem Version Updates
The RubyGems API is used to see if gems were updated during that time. A slack alert is sent to the Ruby agent team's notification channel when an update is found. This alert contains the updated gem name, the gem's previous and latest version, and how to view more information on the update.

Ruby CVE Updates
An XML feed from rubysec.com reports updates on Ruby CVEs. When a vulnerability is found, a slack alert is sent to the Ruby agent team's notification channel. This alert contains the security alert and related rubysec.com link.
## Helpful Information

### Adding or Removing Gem Version Updates

The `gem_notifications.yml` file contains a list of gems that are checked for updates. Gems can be added or removed from this list to adjust notifications.

### Slack Dependency

This project uses the internal Ruby Gem Updates slackbot to post notifications. This bot only posts to authorized slack channels, which can be managed on the Ruby Gem Updates configuration page.

## Relevant Project Files

Gem Version Updates
* `.github/workflows/scripts/slack_gem_notifications/notifications_script.rb`
* `.github/workflows/scripts/slack_gem_notifications/notifications_methods.rb`

Ruby CVE Updates
* `.github/workflows/scripts/slack_gem_notifications/cve_methods.rb`
* `.github/workflows/scripts/slack_gem_notifications/cve_script.rb`

Shared
* `.github/workflows/gem_notifications.yml`
* `test/new_relic/gem_notifications_tests.rb`
