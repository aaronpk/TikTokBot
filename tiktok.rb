Bundler.require

if ARGV[0].nil?
  puts "Usage: ruby tiktok.rb {server}"
  exit 1
end

$base_config = YAML.load_file 'config.yml'

$server = ARGV[0]
$config = $base_config['servers'][$server]

if $config.nil?
  puts "Could not find config for #{$server}"
  exit 1
end

require './lib/init'

if $config['network'] == 'slack'
  require './slack'
elsif $config['network'] == 'irc'
  require './irc'
else
  puts "Network type not supported: #{$config['network']}"
  exit 1
end

