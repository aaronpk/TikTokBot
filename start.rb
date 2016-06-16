Bundler.require
require './lib/init'

if ARGV[0].nil?
  puts "Usage: ruby start.rb {server}"
  exit 1
end

config_file = YAML.load_file 'config.yml'

$config = config_file[ARGV[0]]

if $config.nil?
  puts "Could not find config for #{ARGV[0]}"
  exit 1
end

if $config['network'] == 'slack'
  require './slack'
elsif $config['network'] == 'irc'
  require './irc'
else
  puts "Network type not supported: #{$config['network']}"
  exit 1
end

