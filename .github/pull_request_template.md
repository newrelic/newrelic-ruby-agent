_Before contributing, please read our [contributing guidelines](https://github.com/newrelic/newrelic-ruby-agent/blob/main/CONTRIBUTING.md) and [code of conduct](https://github.com/newrelic/.github/blob/master/CODE_OF_CONDUCT.md)._

# Overview
Describe the changes present in the pull request

Submitter Checklist:
- [ ] Include a link to the related GitHub issue, if applicable
- [ ] Include a security review link, if applicable

# Testing
The agent includes a suite of unit and functional tests which should be used to
verify your changes don't break existing functionality. These tests will run with 
GitHub Actions when a pull request is made. More details on running the tests locally can be found 
[here for our unit tests](https://github.com/newrelic/newrelic-ruby-agent/blob/main/test/README.md), 
and [here for our functional tests](https://github.com/newrelic/newrelic-ruby-agent/blob/main/test/multiverse/README.md).
For most contributions it is strongly recommended to add additional tests which
exercise your changes. 

# Reviewer Checklist
- [ ] Perform code review
- [ ] Add performance label
- [ ] Perform appropriate level of performance testing
- [ ] Confirm all checks passed
- [ ] Add version label prior to acceptance
