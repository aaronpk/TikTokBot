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
      # puts "Hook did not send back a hash:"
      # puts response.inspect
    end
  end

  def self.handle_response(channel, response)
    if response['action'] == 'join'
      $client.join(channel)
      "joining #{channel}"
    elsif response['action'] == 'leave'
      $client.part(channel)
      "leaving #{channel}"
    elsif response['topic']
      $client.Channel(channel).topic = response['topic']
      "setting topic for #{channel}"
    elsif response['content']
      IRCAPI.send_message channel, response['content']
      handle_message true, channel, {nick: $config['irc']['nick'], user: $config['irc']['username'], realname: $config['irc']['username']}, response['content']
      "sent"
    else
      "error"
    end
  end

end

def chat_author_from_irc_user(user)
  Bot::Author.new({
    uid: user[:nick],
    nickname: user[:nick],
    username: user[:user],
    name: user[:realname],
  })
end

def user_hash_from_irc_user(user)
  {
    nick: user.nick,
    user: user.data[:user],
    realname: user.data[:realname]
  }
end

def fetch_user_info(hooks, channel, user)
  # Enhance the author info
  # TODO: expire the cache
  if $nicks[user[:nick]].nil?
    user_info = chat_author_from_irc_user user

    hooks['profile_data'].each do |hook|
      next if !Gateway.channel_match(hook, channel, $config['irc']['server'])
      user_info = Gateway.enhance_profile hook, user_info
    end

    $nicks[user[:nick]] = user_info
  end
end

def chat_channel_from_name(channel)
  if $channels[channel].nil?
    $channels[channel] = Bot::Channel.new({
      uid: channel,
      name: channel
    })
  else
    $channels[channel]
  end
end

def handle_event(event, data, text=nil)
  channel = data.channel.name

  hooks = Gateway.load_hooks

  chat_channel_from_name channel
  fetch_user_info hooks, channel, user_hash_from_irc_user(data.user)

  hooks['hooks'].each do |hook|
    next if !Gateway.channel_match(hook, channel, $config['irc']['server'])

    if hook['match'].nil? && !hook['events'].nil? && hook['events'].include?(event)
      Gateway.process do
        IRCAPI.send_to_hook hook, event, channel, data.user.nick, text, nil
      end
    end
  end
end

def handle_message(is_bot, channel, user, text)
  chat_channel_from_name channel

  hooks = Gateway.load_hooks

  fetch_user_info hooks, channel, user

  command = "message"

  hooks['hooks'].each do |hook|
    next if !Gateway.channel_match(hook, channel, $config['irc']['server'])
    next if Gateway.selfignore hook, is_bot

    if match=Gateway.text_match(hook, text)
      puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
      # puts match.captures.inspect

      # Post to the hook URL in a separate thread
      Gateway.process do
        IRCAPI.send_to_hook hook, 'message', channel, user[:nick], text, match
      end

    end
  end
end

$channels = {}
$nicks = {}

$client = Cinch::Bot.new do
  configure do |c|
    c.server = $config['irc']['host']
    c.port = $config['irc']['port']
    c.password = $config['irc']['password']
    if $config['irc']['ssl']
      c.ssl.use = true
    end
    c.nick = $config['irc']['nick']
    c.user = $config['irc']['username']
    c.channels = $config['irc']['channels']
  end

  on :message do |data, nick|
    channel = data.channel ? data.channel.name : data.user.nick

    # IRC "/me" lines end up coming through as PRIVMSG "\u0001ACTION waves\u0001"
    if match = data.message.match(/\u0001ACTION (.+)\u0001/)
      text = "/me #{match[1]}"
    else
      text = data.message
    end

    is_bot = data.user.nick == $config['irc']['nick']
    handle_message is_bot, channel, user_hash_from_irc_user(data.user), text
  end

  on :invite do |data, nick|
    $client.join(data.channel)
  end

  on :topic do |data|
    handle_event 'topic', data, data.message
  end

  on :part do |data|
    handle_event 'leave', data
  end

  on :join do |data|
    handle_event 'join', data
  end

end

Thread.new do
  $client.start
end

IRCAPI.run!
