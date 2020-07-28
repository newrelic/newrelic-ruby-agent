const os = require('os')
const fs = require('fs')
const path = require('path')

const core = require('@actions/core')
const github = require('@actions/github')
const exec = require('@actions/exec')

function execute(command) {
  return new Promise(function(resolve, reject) {
    exec.exec(command, function(error, standardOutput, standardError) {
      if (error) {
        reject()
        return
      }

      if (standardError) {
        reject(standardError)
        return
      }

      resolve(standardOutput)
    })
  })
}

async function execRuby(command) {
  try {
    const result = await execute(`ruby ${command}`)
    console.log(`executing Ruby returns: ${result}`)
    return result
  } 
  catch (error) {
    errorStr = error.toString()
    console.error(errorStr)
    core.setFailed(errorStr)
  }  
}

async function installSystemDependencies() {
  core.startGroup(`Installing system dependencies`)

  const dependencyList = 'libyaml-dev libgdbm-dev libreadline-dev libncurses5-dev libcurl-dev zlib1g-dev libffi-dev'

  console.log(`installing system dependencies ${dependencyList}`)

  await exec.exec('sudo apt-get update')
  await exec.exec('sudo apt-get install -y --no-install-recommends ${dependencyList}')

  core.endGroup()
}

async function installRubyBuild(rubyVersion) {
  core.startGroup(`Installing ruby-build`)

  const buildDir = `${process.env.HOME}/ruby-build`

  if (rubyVersion.match(/^2\.[012]/)) {
    console.log('cloning eregon/ruby-build')
    const repoPath = '--branch ruby23-openssl-linux https://github.com/eregon/ruby-build.git'
  } else {
    console.log('cloning rbenv/ruby-build')
    const repoPath = 'https://github.com/rbenv/ruby-build.git'
  }

  await exec.exec(`git clone ${repoPath} ${buildDir}`)
  await exec.exec(`sudo ${buildDir}/install.sh && ruby-build --definitions`)

  core.endGroup()
}

function setupBuildEnvironment() {
  core.exportVariable('RUBY_CONFIGURE_OPTS', '--enable-shared --disable-install-doc')
  // https://github.com/actions/virtual-environments/issues/267
  core.exportVariable('CPPFLAGS', '-DENABLE_PATH_CHECK=0')
}

function addRubyToPath(rubyVersion) {
  core.addPath(`~/.rubies/ruby-${rubyVersion}/bin`)
}

async function buildRuby(rubyVersion) {
  core.startGroup(`Build Ruby ${rubyVersion}`)
  await exec.exec(`ruby-build --verbose ${rubyVersion} ~/.rubies/ruby-${rubyVersion}`) 
  core.endGroup()
}

async function getGemVersion() {
  await execRuby("Gem::VERSION")
}

async function upgradeRubyGems() {
  core.startGroup(`Upgrade RubyGems`)

  const gemVersionStr = await getGemVersion()

  if (parseFloat(rubyVersion) < 2.7) {

    if (parseFloat(gemVersionStr) < 3.0) {
      console.log(`Ruby < 2.7, upgrading RubyGems from ${gemVersionStr}`)
      await exec.exec("gem update --system 3.0.6 --force || (gem i rubygems-update -v '<3' && update_rubygems)")
    }
    else {
      console.log(`Ruby < 2.7, but RubyGems already at ${gemVersionStr}`)
    }
  } 

  else {
    console.log(`Ruby >= 2.7, keeping RubyGems at ${gemVersionStr}`)
  }

  core.endGroup()
}

async function installBundler(rubyVersion) {
  core.startGroup(`Install bundler`)

  const bundlePath = `~/.rubies/ruby-${rubyVersion}/bin`

  if (!fs.existsSync(`${bundlePath}/bundle`)) {
    await exec.exec(`sudo gem install bundler -v '~> 1' --no-document -​-bindir ${bundlePath}`)
  }

  core.endGroup()
}

async function buildThatRuby() {
  const rubyVersion = core.getInput('ruby-version')

  try {
    setupBuildEnvironment()
    addRubyToPath(rubyVersion)

    await installRubyBuild(rubyVersion)
    await installSystemDependencies()
    await buildRuby(rubyVersion)
    await upgradeRubyGems(rubyVersion)
    await installBundler(rubyVersion)

  }
  catch (error) {
    core.setFailed(error.message)
  }
}

buildThatRuby()
