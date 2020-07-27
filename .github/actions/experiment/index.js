const core = require('@actions/core');
const github = require('@actions/github');

// const { exec } = require("child_process");


try {
  const rubyVersion = core.getInput('ruby-version');
  console.log(`Using ${rubyVersion}`);
  
  await exec("/usr/bin/ruby ./.github/actions/experiment/index.rb", (error, stdout, stderr) => {
    if (error) {
        console.log(`error: ${error.message}`);
        return;
    }
    if (stderr) {
        console.log(`stderr: ${stderr}`);
        return;
    }
    output = $stdout;
    console.log(output);
    core.setOutput("output", output);
  });

  // Get the JSON webhook payload for the event that triggered the workflow
  const payload = JSON.stringify(github.context.payload, undefined, 2)
  console.log(`The event payload: ${payload}`);
} catch (error) {
  core.setFailed(error.message);
}

