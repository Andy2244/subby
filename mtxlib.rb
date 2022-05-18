#!/usr/bin/env ruby
# frozen_string_literal: true

# version 2019-01-24-01

require 'json'
require 'tempfile'

def identify_file(file_name)
  Tempfile.create(%w[mkvmerge-arguments .json], nil, encoding: 'utf-8') do |file|
    file.puts JSON.dump(['--identification-format', 'json', '--identify', file_name])
    file.close

    return JSON.parse(`mkvmerge @#{file.path}`)
  end
end

def multiplex_file(arguments)
  Tempfile.create(%w[mkvmerge-arguments .json], nil, encoding: 'utf-8') do |file|
    file.puts JSON.dump(arguments)
    file.close

    system "mkvmerge @#{file.path}"
  end
end

def edit_file_properties(arguments)
  Tempfile.create(%w[mkvpropedit-arguments .json], nil, encoding: 'utf-8') do |file|
    file.puts JSON.dump(arguments)
    file.close

    system "mkvpropedit @#{file.path}"
  end
end
