const core = require('@actions/core');
const github = require('@actions/github');
const exec = require('@actions/exec');

// const { exec } = require("child_process");


try {
  const rubyVersion = core.getInput('ruby-version');
  console.log(`Using ${rubyVersion}`);
  
  exec.exec("/usr/bin/ruby ./.github/actions/experiment/index.rb", (error, stdout, stderr) => {
    if (error) {
        core.setFailed(error.message);
        return;
    }
    if (stderr) {
        core.setFailed(stderr);
        return;
    }
    output = $stdout;
    console.log(output);
    core.setOutput("results", "it works");
  });

  // // Get the JSON webhook payload for the event that triggered the workflow
  // const payload = JSON.stringify(github.context.payload, undefined, 2)
  // console.log(`The event payload: ${payload}`);
} catch (error) {
  core.setFailed(error.message);
}