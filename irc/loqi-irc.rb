Bundler.require
require 'yaml'
require '../lib/gateway'

$config = YAML.load_file 'config.yml'

$gateway = Gateway.new

class API < Sinatra::Base
  configure do
    set :threaded, false
    set :bind, $config['api']['host']
    set :port, $config['api']['port']
  end

  get '/' do
    "Connected to #{$config['irc']['server']} as #{$config['irc']['nick']}"
  end

  post '/message' do
    puts params.inspect
    $gateway.send_to_irc params
    "sent"
  end
end


$client = Cinch::Bot.new do
  configure do |c|
    c.server = $config['irc']['server']
    c.port = $config['irc']['port']
    c.password = $config['irc']['password']
    c.nick = $config['irc']['nick']
    c.user = $config['irc']['username']
    c.channels = $config['irc']['channels']
  end

  on :message do |data, nick|
    puts "================="
    puts data.inspect

    hooks = Gateway.load_hooks

    hooks['hooks'].each do |hook|
      

    end
    
  end
end

Thread.new do
  $client.start
end

API.run!

