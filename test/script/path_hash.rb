#!/usr/bin/env ruby   
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'digest'

path = ARGV

def usage
  $stderr.puts "Usage: path_hash.rb '<app_name>;<txn_name>' ['<app_name>;<txn_name>'...]"
  exit
end

usage unless path.size > 0

path_hash = 0
path.each do |hop|
  app_name, transaction_name = hop.split(';')

  if !app_name || !transaction_name
    $stderr.puts ''
    $stderr.puts "Error: Malformed transaction identifier '#{hop}'."
    usage
  end

  identifier = "#{app_name};#{transaction_name}"
  md5sum = Digest::MD5.digest(identifier)
  low4_of_md5 = md5sum.unpack("@12N").first
  low31_of_md5 = low4_of_md5 & 0x7fffffff

  rotated_path_hash = ((path_hash << 1) | (path_hash >> 30)) & 0x7fffffff

  xor_result = rotated_path_hash ^ low31_of_md5

  puts '--'
  puts "A: txnIdentifier:       '#{identifier}'"
  puts "B: MD5(A):              #{Digest::MD5.hexdigest(identifier)}"
  puts "C: Low 4 bytes of B:    0x#{low4_of_md5.to_s(16).rjust(8, '0')} (0b#{low4_of_md5.to_s(2).rjust(32, '0')})"
  puts "D: Low 31 bits of C:    0x#{low31_of_md5.to_s(16).rjust(8, '0')} (0b#{low31_of_md5.to_s(2).rjust(32, '0')})"
  puts ''
  puts "E: Input path_hash:     0x#{path_hash.to_s(16).rjust(8, '0')} (0b#{path_hash.to_s(2).rjust(32, '0')})"
  puts "F: Rotated E:           0x#{rotated_path_hash.to_s(16).rjust(8, '0')} (0b#{rotated_path_hash.to_s(2).rjust(32, '0')})"
  puts ""
  puts "G: XOR(D, F):           0x#{xor_result.to_s(16).rjust(8, '0')} (0b#{xor_result.to_s(2).rjust(32, '0')})"
  puts '--'

  path_hash = xor_result
end

puts "Final result: 0x#{path_hash.to_s(16).rjust(8, '0')}"
