const os = require('os')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

const core = require('@actions/core')
const exec = require('@actions/exec')
const cache = require('@actions/cache')
const io = require('@actions/io')

async function main() {
  try {
    const mysql55Path = '/usr/local/mysql1138'
    exec.exec(`wget https://github.com/mysql/mysql-server/archive/refs/tags/mysql-5.5.63.tar.gz \
               && tar xzf mysql-5.5.63.tar.gz \
               && cd mysql-server-mysql-5.5.63/ \
               && cmake . -DCMAKE_INSTALL_PREFIX=${mysql55Path} \
               -DMYSQL_DATADIR=${mysql55Path}/data \
               -DDOWNLOAD_BOOST=1 \
               -DWITH_BOOST=/tmp/boost \
               -DWITH_SSL=bundled \
               && make \
               && make install \
               && cd .. \
               && rm -rf mysql-5.5.63.tar.gz mysql-server-mysql-5.5.63`)

    exec.exec(`ls -l ${mysql55Path}`)
  }
  catch (error) {
    core.setFailed(`Action failed with error ${error}`)
  }
}

main()
