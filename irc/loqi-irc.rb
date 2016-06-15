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
    c.server = $config['irc']['host']
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
      next if !Gateway.channel_match(hook, data.channel.name, $config['irc']['server'])

      if match=Gateway.text_match(hook, data.message)
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
        puts match.captures.inspect

        # Post to the hook URL in a separate thread
        Thread.new do
          params = {
            network: 'irc',
            server: $config['irc']['server'],
            channel: data.channel.name,
            timestamp: Time.now.to_f,
            type: data.command,
            user: data.user,
            nick: data.user.nick,
            text: data.message,
            match: match.captures,
            response_url: "http://localhost:#{$config['api']['port']}/message?channel=#{URI.encode_www_form_component(data.channel.name)}"
          }

          #puts "Posting to #{hook['url']}"
          jj params

          response = HTTParty.post hook['url'], {
            body: params,
            headers: {
              'Authorization' => "Bearer #{$config['webhook_token']}"
            }
          }
              puts response.inspect
          if response.parsed_response.is_a? Hash
            puts response.parsed_response
            $gateway.send_to_irc({channel: data.channel.name}.merge response.parsed_response)
          else
            if !response.parsed_response.nil?
              puts response.inspect
            end
          end

        end

      end
    end

  end
end

Thread.new do
  $client.start
end

API.run!

