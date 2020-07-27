const core = require('@actions/core');
const github = require('@actions/github');
const exec = require('@actions/exec');

async function run() {
  try {
    const rubyVersion = core.getInput('ruby-version');
    console.log(`Using ${rubyVersion}`);
    
    await exec.exec("ruby ./.github/actions/experiment/index.rb", (error, stdout, stderr) => {
      if (error) {
          core.setFailed(error.message);
          return;
      }
      if (stderr) {
          core.setFailed(stderr);
          return;
      }
    });

    output = $stdout;
    console.log(output);
    core.setOutput('results', output);

  } catch (error) {
    core.setFailed(error.message);
  }
}

run()
