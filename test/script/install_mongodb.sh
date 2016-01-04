#!/bin/bash

wget http://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGODB}.tgz -O /tmp/mongodb.tgz
mkdir -p /tmp/mongodb/data
tar -xvf /tmp/mongodb.tgz -C /tmp/mongodb
/tmp/mongodb/mongodb-linux-x86_64-${MONGODB}/bin/mongod --dbpath /tmp/mongodb/data --bind_ip 127.0.0.1 --noauth &> /dev/null &
