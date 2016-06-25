require './lib/api'

class IRCAPI < API

  get '/' do
    "Connected to #{$config['irc']['server']} as #{$config['irc']['nick']}"
  end

  def self.send_message(channel, content)
    if channel[0] == '#'
      result = $client.Channel(channel).send content
    else
      result = $client.User(channel).send content
    end
    "sent"
  end

  def self.handle_message(hook, channel, data, match, command, text)
    response = Gateway.send_to_hook hook,
      'irc',
      $config['irc']['server'],
      channel,
      channel,
      Time.now.to_f,
      command,
      data.user,
      data.user.nick,
      text,
      match

    puts "==================="
    puts response.parsed_response.inspect
    puts "==================="

    if response.parsed_response.is_a? Hash
      IRCAPI.send_message channel, response.parsed_response['content']
    else
      puts "Hook response was not JSON"
      if !response.parsed_response.nil?
        puts response.inspect
      end
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
    channel = data.channel ? data.channel.name : data.user.nick

    command = "message"

    # IRC "/me" lines end up coming through as PRIVMSG "\u0001ACTION waves\u0001"
    if match = data.message.match(/\u0001ACTION (.+)\u0001/)
      text = "/me #{match[1]}"
    else
      text = data.message
    end

    hooks = Gateway.load_hooks
    hooks['hooks'].each do |hook|
      next if !Gateway.channel_match(hook, channel, $config['irc']['server'])

      if match=Gateway.text_match(hook, text)
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
        puts match.captures.inspect

        # Post to the hook URL in a separate thread
        if $config['thread']
          Thread.new do 
            IRCAPI.handle_message hook, channel, data, match, command, text
          end
        else
          IRCAPI.handle_message hook, channel, data, match, command, text
        end

      end
    end

  end

  on :invite do |data, nick|
    puts "INVITE:"
    puts data.inspect
  end

  on :topic do |data|
    puts "TOPIC:"
    puts data.inspect
  end

  on :connect do |data, user|
    puts "CONNECT:"
    puts data.inspect
  end

  on :online do |data, user|
    puts "ONLINE:"
    puts data.inspect
  end

  on :offline do |data, user|
    puts "OFFLINE:"
    puts data.inspect
  end

end

Thread.new do
  $client.start
end

IRCAPI.run!
