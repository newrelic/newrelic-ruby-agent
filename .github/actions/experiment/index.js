const core = require('@actions/core');
const github = require('@actions/github');
const exec = require('@actions/exec');

function run() {
  try {
    const rubyVersion = core.getInput('ruby-version');
    console.log(`Using ${rubyVersion}`);
    
    runner = exec.exec("ruby ./.github/actions/experiment/index.rb", (error, stdout, stderr) => {
      if (error) {
          core.setFailed(error.message);
          return;
      }
      if (stderr) {
          core.setFailed(stderr);
          return;
      }
      output = `${stdout}`
      return output;
    });

    runner.stdout.on('message', function(message) { 
      console.log(message); 
      core.setOutput('results', message);
    });
    
    runner.stderr.on('message', function(message) { 
      console.log(message); 
      core.setFailed(message);
    });


  } catch (error) {
    core.setFailed(error.message);
  }
}

run()
