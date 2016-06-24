require './lib/api'

class IRCAPI < API

  get '/' do
    "Connected to #{$config['irc']['server']} as #{$config['irc']['nick']}"
  end

  def self.send_message(channel, text)
    if channel[0] == '#'
      $client.Channel(channel).send text
    else
      $client.User(channel).send text
    end
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
              'Authorization' => "Bearer #{hook['token']}"
            }
          }

          if response.parsed_response.is_a? Hash
            puts response.parsed_response
            $gateway.send_to_slack channel: data.channel, text: response.parsed_response[:text]
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

IRCAPI.run!
