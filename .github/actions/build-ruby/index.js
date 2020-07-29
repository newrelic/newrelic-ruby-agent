const os = require('os')
const fs = require('fs')
const path = require('path')

const core = require('@actions/core')
const exec = require('@actions/exec')

// removes trailing newlines and linefeeds from the given text string
function chomp(text) {
  return text.replace(/(\n|\r)+$/, '')
}

// invokes the @actions/exec exec function with listeners to capture the 
// output stream as the return result.
async function execute(command) {
 try {
   let outputStr = ''

   const options = {}
   options.listeners = {
     stdout: (data) => { outputStr += data.toString() },
     stderr: (data) => { console.log(data.toString()) }
   }

   await exec.exec(command, [], options)

   return chomp(outputStr);

 } catch (error) {
   console.error(error.toString())
 }
}

// installs system dependencies needed to successfully build the ruby executables
// NOTE: Ubuntu specific!
async function installSystemDependencies() {
  core.startGroup(`Installing system dependencies`)

  const dependencyList = 'libyaml-dev libgdbm-dev libreadline-dev libncurses5-dev zlib1g-dev libffi-dev'

  console.log(`installing system dependencies ${dependencyList}`)

  await exec.exec('sudo apt-get update')
  await exec.exec(`sudo apt-get install -y --no-install-recommends ${dependencyList}`)

  core.endGroup()
}

// ruby-build is used to compile Ruby and it's various executables
// rbenv's ruby-build doesn't fully support EOL rubies (< 2.4 at time of this writing).
// setup-ruby also doesn't correctly build the older rubies with openssl support.
// long story short, openssl library for these older ruby need to be 1.0 variant.
async function installRubyBuild(rubyVersion) {
  core.startGroup(`Installing ruby-build`)

  const buildDir = `${process.env.HOME}/ruby-build`
  var repoPath

  // Rubies 2.0 ... 2.3 (these need OpenSSL 1.0 and eregon provides it for us)
  if (rubyVersion.match(/^2\.[0123]/)) {
    console.log('cloning eregon/ruby-build')
    repoPath = '--branch ruby23-openssl-linux https://github.com/eregon/ruby-build.git'

  // all the other Rubies
  } else {
    console.log('cloning rbenv/ruby-build')
    repoPath = 'https://github.com/rbenv/ruby-build.git'
  }

  await exec.exec(`git clone ${repoPath} ${buildDir}`)
  await exec.exec(`sudo ${buildDir}/install.sh && ruby-build --definitions`)

  core.endGroup()
}

// Add the environment variables needed to correctly build ruby and later run ruby tests.
// this function is invoked even if ruby is cached and compile step is skipped.
function setupRubyEnvironment() {

  // LANG environment must be set or Ruby will default external_encoding to US-ASCII i
  // instead of UTF-8 and this will fail many tests.
  core.exportVariable('LANG', 'C.UTF-8')

  // enable-shared prevents native extension gems from breaking if they're cached
  // independently of the ruby binaries
  core.exportVariable('RUBY_CONFIGURE_OPTS', '--enable-shared --disable-install-doc')

  // https://github.com/actions/virtual-environments/issues/267
  core.exportVariable('CPPFLAGS', '-DENABLE_PATH_CHECK=0')
}

// Shows some version love!
async function showVersions() {
  core.startGroup("Show Versions")

  await exec.exec('ruby', ['--version'])
  await exec.exec('ruby', ['-ropenssl', '-e', "puts OpenSSL::OPENSSL_LIBRARY_VERSION"])
  await exec.exec('gem', ['--version'])
  await exec.exec('bundle', ['--version'])

  core.endGroup()
}

// Just one place to define the ruby binaries path and that is here
// NOTE: the cache step in the workflow .yml file must match this path
function rubyPath(rubyVersion) {
  return `${process.env.HOME}/.rubies/ruby-${rubyVersion}`
}

// This "activates" our newly built ruby so it comes first in the path
function addRubyToPath(rubyVersion) {
  core.addPath(`${rubyPath(rubyVersion)}/bin`)
}

// kicks off the ruby build process.
async function buildRuby(rubyVersion) {
  core.startGroup(`Build Ruby ${rubyVersion}`)
  await exec.exec(`ruby-build --verbose ${rubyVersion} ${rubyPath(rubyVersion)}`) 
  core.endGroup()
}

// Older rubies come with Ruby gems 2.5.x and we need 3.0.6 minimum to 
// correctly install Bundler and do anything else within the multiverse test suite
async function upgradeRubyGems(rubyVersion) {
  core.startGroup(`Upgrade RubyGems`)

  await execute('gem --version').then(res => { gemVersionStr = res; });

  console.log(`Current RubyGems is "${gemVersionStr}"`)

  if (parseFloat(rubyVersion) < 2.7) {

    if (parseFloat(gemVersionStr) < 3.0) {
      console.log(`Ruby < 2.7, upgrading RubyGems from ${gemVersionStr}`)

      await exec.exec('gem', ['update', '--system', '3.0.6', '--force']).then(res => { exitCode = res });
      if (exitCode != 0) {
        await exec.exec('gem', ['install', 'rubygems-update', '-v', '<3'])
        await exec.exec('update_rubygems')
      };
      
    }
    else {
      console.log(`Ruby < 2.7, but RubyGems already at ${gemVersionStr}`)
    }
  } 

  else {
    console.log(`Ruby >= 2.7, keeping RubyGems at ${gemVersionStr}`)
  }

  await execute('which gem').then(res => { console.log("which gem: " + res) });
  await execute('gem --version').then(res => { console.log("New RubyGems is: " + res) });

  core.endGroup()
}

// install Bundler 1.17.3 (or thereabouts)
async function installBundler(rubyVersion) {
  core.startGroup(`Install bundler`)

  const bundlePath = `${rubyPath(rubyVersion)}/bin`

  if (!fs.existsSync(`${bundlePath}/bundle`)) {
    await exec.exec('sudo', ['gem', 'install', 'bundler', '-v', '~> 1', '--no-document', '--bindir', bundlePath])
  }

  core.endGroup()
}

// Will set up the Ruby environment so the desired Ruby binaries are used in the unit tests
// If Ruby hasn't been built and cached, yet, we also compile the Ruby binaries.
// 
// The binaries, once built, can be cached with the following in the workflow .yml file:
//
// - uses: actions/cache@v2
//   id: ruby-cache
//   with:
//     path: ~/.rubies/ruby-${{ matrix.ruby-version }}
//     key: ruby-cache-${{ matrix.ruby-version }}
//     restore-keys: |
//       ruby-cache-${{ matrix.ruby-version }}
//
async function main() {
  const rubyVersion = core.getInput('ruby-version')
  const rubyBinPath = `${rubyPath(rubyVersion)}/bin`

  try {
    setupRubyEnvironment()
    addRubyToPath(rubyVersion)
  } 
  catch (error) {
    core.setFailed(error.message)
    return
  }

  if (fs.existsSync(`${rubyBinPath}/ruby`)) {
    await showVersions()
    console.log("Ruby already built.  Skipping the build process!")
    return
  }

  try {
    await installRubyBuild(rubyVersion)
    await installSystemDependencies()
    await buildRuby(rubyVersion)
    await upgradeRubyGems(rubyVersion)
    await installBundler(rubyVersion)
    await showVersions()
  } 
  catch (error) {
    core.setFailed(error.message)
  }
}

main()
