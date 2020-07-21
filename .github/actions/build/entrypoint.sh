#!/bin/sh -l

ruby --version && ruby -ropenssl -e 'puts OpenSSL::OPENSSL_LIBRARY_VERSION'
