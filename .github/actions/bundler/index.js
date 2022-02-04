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
    await bundleInstall(rubyVersion)
  } catch (error) {
    core.setFailed(error.message)
  }
}

async function bundleInstall(rubyVersion) {
  core.startGroup('Bundle install')

  const filePath = `${process.env.HOME}/.rubies/ruby-${rubyVersion}/.bundle-cache`
  const workspacePath = process.env.GITHUB_WORKSPACE
  const keyHash = fileHash(`${process.env.GITHUB_WORKSPACE}/newrelic_rpm.gemspec`)
  const key = `v2-bundle-cache-${rubyVersion}-${keyHash}`
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

  if (cachedKey) {
    await io.cp(`${filePath}/Gemfile.lock`, `${workspacePath}/Gemfile.lock`)
  }

  // run 'bundle install' whether the cache hit or missed, to always list the bundle's contents
  await exec.exec('ruby_run', [rubyVersion, 'bundle', 'install', '--jobs', '4'])

  if (cachedKey == null) {
    await io.cp(`${workspacePath}/Gemfile.lock`, `${filePath}/Gemfile.lock`)
    try {
      await cache.saveCache([filePath], key)
    }
    catch (error) {
      console.log('Failed to save cache' + error.toString())
    }
  }

  core.endGroup()
}

// fingerprints the given filename, returning hex string representation
function fileHash(filename) {
  let sum = crypto.createHash('md5')
  sum.update(fs.readFileSync(filename))
  return sum.digest('hex')
}

if (__filename.endsWith('index.js')) { run() }
