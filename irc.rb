class IRCAPI < API

  get '/' do
    "Connected to #{$config['irc']['server']} as #{$config['irc']['nick']}"
  end

  get '/cache' do
    {
      nicks: $nicks,
      channels: $channels
    }.to_json
  end

  post '/cache/expire' do
    $nicks = {}
    $channels = {}
    "ok"
  end

  def self.send_message(channel, content)
    if match=content.match(/^\/me (.+)/)
      if channel[0] == '#'
        result = $client.Channel(channel).action match[1]
      else
        result = $client.User(channel).action match[1]
      end
    else
      if channel[0] == '#'
        result = $client.Channel(channel).send content
      else
        result = $client.User(channel).send content
      end
    end

    "sent"
  end

  def self.send_to_hook(hook, type, channel, nick, content, match)
    response = Gateway.send_to_hook hook,
      Time.now.to_f,
      'irc',
      $config['irc']['server'],
      $channels[channel],
      $nicks[nick],
      type,
      content,
      match
    if response.parsed_response.is_a? Hash
      self.handle_response channel, response.parsed_response
    else
      puts "Hook did not send back a hash:"
      puts response.inspect
    end
  end

  def self.handle_response(channel, response)
    IRCAPI.send_message channel, response['content']
  end

end

def chat_author_from_irc_user(user)
  Bot::Author.new({
    uid: user.nick,
    nickname: user.nick,
    username: user.data[:user],
    name: user.data[:realname],
  })
end


$channels = {}
$nicks = {}

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

    if $channels[channel].nil?
      $channels[channel] = Bot::Channel.new({
        uid: channel,
        name: channel
      })
    end

    hooks = Gateway.load_hooks

    # Enhance the author info
    # TODO: expire the cache
    if $nicks[data.user.nick].nil?
      user_info = chat_author_from_irc_user data.user
      puts "Enhancing account info from hooks"

      hooks['profile_data'].each do |hook|
        next if !Gateway.channel_match(hook, channel, $config['irc']['server'])
        user_info = Gateway.enhance_profile hook, user_info
      end

      $nicks[data.user.nick] = user_info      
    end

    command = "message"

    # IRC "/me" lines end up coming through as PRIVMSG "\u0001ACTION waves\u0001"
    if match = data.message.match(/\u0001ACTION (.+)\u0001/)
      text = "/me #{match[1]}"
    else
      text = data.message
    end

    hooks['hooks'].each do |hook|
      next if !Gateway.channel_match(hook, channel, $config['irc']['server'])

      if match=Gateway.text_match(hook, text)
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
        puts match.captures.inspect

        # Post to the hook URL in a separate thread
        if $config['thread']
          Thread.new do 
            IRCAPI.send_to_hook hook, 'message', channel, data.user.nick, text, match
          end
        else
          IRCAPI.send_to_hook hook, 'message', channel, data.user.nick, text, match
        end

      end
    end

  end

  on :invite do |data, nick|
    $client.join(data.channel)
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
