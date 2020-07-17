const fs = require('fs')
const os = require('os')
const camelCase = require('camelcase')

const LINE_MATCH = /^(\w+)=["']?([\w\s\.]+)["']?$/

function _lsbRelease() {
  const content = fs.readFileSync('/etc/lsb-release', 'utf8')

  const obj = {}

  content.split("\n").forEach(function(line) {
    const matches = line.match(LINE_MATCH)

    if (matches) {
      obj[camelCase(matches[1])] = matches[2]
    }
  })

  return obj
}

export function type() {
  const type = os.type()
  if (type == 'Linux') {
    try {
      const lsbRelease = _lsbRelease()
      return lsbRelease.distribId
    }
    catch { }
  }

  return type
}

export function version() {
  if (type() == 'Ubuntu') {
    return _lsbRelease().distribRelease
  }
}
