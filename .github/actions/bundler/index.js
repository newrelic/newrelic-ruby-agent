const cache = require('@actions/cache')
const core = require('@actions/core')
const crypto = require('crypto')
const exec = require('@actions/exec')
const fs = require('fs')
const io = require('@actions/io')

// entrypoint
export async function run() {
  const rubyVersion = core.getInput('ruby-version')
  try {
    await installEnvironmentBundlers(rubyVersion)
    await bundleInstall(rubyVersion)
  } catch (error) {
    core.setFailed(error.message)
  }
}

async function bundleInstall(rubyVersion) {
  const bundlerVersion = '_1.17.3_'
  core.startGroup('Bundle install')

  let prefixedVersion = `ruby-${rubyVersion}`
  if (rubyVersion.startsWith('jruby')) {
    prefixedVersion = rubyVersion
  }
  const filePath = `/root/.rubies/${prefixedVersion}/.bundle-cache`
  const workspacePath = process.env.GITHUB_WORKSPACE
  const keyHash = fileHash(`${process.env.GITHUB_WORKSPACE}/newrelic_rpm.gemspec`)
  const key = `v3-bundle-cache-${rubyVersion}-${keyHash}`
  core.info(`restore using ${key}`)

  let cachedKey = null
  try {
    cachedKey = await cache.restoreCache([filePath], key, [key])
  } catch(error) {
    if (error.name === cache.ValidationError.name) {
      throw error;
    } else {
      core.info(`[warning] There was an error restoring the Bundler cache ${error.message}`)
    }
  }

  await exec.exec('ruby_run', [rubyVersion, 'bundle', bundlerVersion, 'config', '--local', 'path', filePath])

  if (cachedKey) {
    await io.cp(`${filePath}/Gemfile.lock`, `${workspacePath}/Gemfile.lock`)
  }

  // run 'bundle install' whether the cache hit or missed, to always list the bundle's contents
  await exec.exec('ruby_run', [rubyVersion, 'bundle', bundlerVersion, 'install', '--jobs', '4'])

  if (cachedKey == null) {
    await io.cp(`${workspacePath}/Gemfile.lock`, `${filePath}/Gemfile.lock`)
    try {
      await cache.saveCache([filePath], key)
    }
    catch (error) {
      console.log('Failed to save cache' + error.toString())
    }
  }

  core.addPath(`/root/.rubies/${prefixedVersion}/bin`)

  core.endGroup()
}

// TODO: the various test/environments/*/.bundler-version files' contents could differ from v1.17.3
async function installEnvironmentBundlers(rubyVersion) {
  core.startGroup('Install environment Bundlers')
  await exec.exec('ruby_run', [rubyVersion, 'gem', 'install', 'bundler:1.17.3', '--no-document'])
  core.endGroup()
}

// fingerprints the given filename, returning hex string representation
function fileHash(filename) {
  let sum = crypto.createHash('md5')
  sum.update(fs.readFileSync(filename))
  return sum.digest('hex')
}

if (__filename.endsWith('index.js')) { run() }
