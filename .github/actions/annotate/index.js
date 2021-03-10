const fs = require('fs')
const core = require('@actions/core')
const command = require('@actions/core/lib/command')

async function main() {
  const workspacePath = process.env.GITHUB_WORKSPACE
  const errorFilename = `${workspacePath}/errors.txt`

  try {
    if (fs.existsSync(errorFilename)) {
      fs.readFile(errorFilename, 'utf8', (error, lines) => { 
        if (error) { 
          core.info(`Failed to read ${errorFilename}.  Check focused job views for error details!`) 
        } else {
          lines.split("\n").forEach(function(line, index, arr) {
            command.issueCommand('error', undefined, line)
          })
        }
      })     
    }
    else {
      core.info(`No ${errorFilename} present.  Skipping!`)
    }
  } 
  catch (error) {
    core.setFailed(`Action failed with error ${error}`)
  }

}

main()
