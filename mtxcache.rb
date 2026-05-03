#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

CACHE_VERSION = 2

# fields subby never reads but mkvmerge happily inlines per-track. codec_private_data
# can be megabytes for SSA subtitle tracks (script header + styles). strip them before
# caching to keep subby_cache.json lean.
CACHE_STRIP_TRACK_PROPS = %w[codec_private_data codec_private_length].freeze

def cache_strip_bloat(json)
  return json unless json.is_a?(Hash) && json['tracks'].is_a?(Array)
  slim = json.dup
  slim['tracks'] = json['tracks'].map do |t|
    next t unless t.is_a?(Hash) && t['properties'].is_a?(Hash)
    props = t['properties'].reject { |k, _| CACHE_STRIP_TRACK_PROPS.include?(k) }
    t.merge('properties' => props)
  end
  slim
end

def cache_load(path)
  return { 'version' => CACHE_VERSION, 'entries' => {} } unless File.exist?(path)
  data = JSON.parse(File.read(path, encoding: 'utf-8'))
  if data.is_a?(Hash) && data['version'] == CACHE_VERSION && data['entries'].is_a?(Hash)
    data
  elsif data.is_a?(Hash) && data['entries'].is_a?(Hash)
    # version bump: silently rebuild
    { 'version' => CACHE_VERSION, 'entries' => {} }
  else
    puts "WARNING: cache malformed, starting fresh: #{path}"
    { 'version' => CACHE_VERSION, 'entries' => {} }
  end
rescue JSON::ParserError, SystemCallError => e
  puts "WARNING: cache load failed (#{e.class}: #{e.message}), starting fresh"
  { 'version' => CACHE_VERSION, 'entries' => {} }
end

def cache_get(cache, file)
  entry = cache['entries'][file]
  return nil unless entry
  stat = File.stat(file)
  return nil unless entry['mtime'] == stat.mtime.to_f && entry['size'] == stat.size
  entry['json']
rescue SystemCallError
  nil
end

def cache_put(cache, file, json, stat = nil)
  # caller can pass a pre-identify stat to avoid TOCTOU: if the file is replaced
  # during identify, we store the pre-identify mtime/size so the next run's stat
  # mismatches and re-identifies.
  stat ||= File.stat(file)
  cache['entries'][file] = {
    'mtime' => stat.mtime.to_f,
    'size' => stat.size,
    'json' => cache_strip_bloat(json),
  }
  $cache_dirty = true
rescue SystemCallError
  # file vanished between identify and stat: skip caching
end

def cache_invalidate(cache, file)
  $cache_dirty = true if cache['entries'].delete(file)
end

def cache_save(cache, path)
  File.write(path, JSON.dump(cache), encoding: 'utf-8')
  puts "cache saved: #{path} (#{cache['entries'].length} entries)"
rescue SystemCallError => e
  puts "WARNING: cache save failed (#{e.class}: #{e.message}): #{path}"
end
