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
    $nicks_cache = {}
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

  def self.send_to_hook(hook, type, channel, nick, content, match, modes=[])
    response = Gateway.send_to_hook hook,
      Time.now.to_f,
      'irc',
      $config['irc']['server'],
      $channels[channel],
      $nicks[nick],
      type,
      content,
      match,
      modes
    if response.parsed_response.is_a? Hash
      self.handle_response channel, response.parsed_response
    else
      # puts "Hook did not send back a hash:"
      # puts response.inspect
    end
  end

  def self.handle_response(channel, response)
    if response['channel']
      channel = response['channel']
    end

    if response['action'] == 'join'
      $client.join(response['channel'])
      "joining #{channel}"
    elsif response['action'] == 'leave'
      $client.part(response['channel'])
      "leaving #{channel}"
    elsif response['topic']
      $client.Channel(channel).topic = response['topic']
      "setting topic for #{channel}"
    elsif response['action'] == 'voice'
      $client.Channel(channel).voice(response['nick'])
    elsif response['action'] == 'devoice'
      $client.Channel(channel).devoice(response['nick'])
    elsif response['action'] == 'kick'
      $client.Channel(channel).kick(response['nick'], response['reason'])
    elsif response['action'] == 'nick'
      $client.nick = response['nick']
    elsif response['content']
      IRCAPI.send_message channel, response['content']
      handle_message true, channel, {
        nick: $config['irc']['nick'],
        user: $config['irc']['username'],
        realname: $config['irc']['username']
      }, response['content']
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
    host: user[:host],
  })
end

def user_hash_from_irc_user(user)
  {
    nick: user.nick,
    user: user.data[:user],
    realname: user.data[:realname],
    host: user.host,
  }
end

def fetch_user_info(hooks, channel, user)
  # Enhance the author info
  # Refresh every 10 minutes
  if $nicks[user[:nick]].nil? || ($nicks_cache[user[:nick]] < (Time.now.to_i - 600))
    user_info = chat_author_from_irc_user user

    if !hooks['profile_data'].nil?
      hooks['profile_data'].each do |hook|
        next if !Gateway.channel_match(hook, channel, $config['irc']['server'])
        user_info = Gateway.enhance_profile hook, user_info
      end
    end

    $nicks[user[:nick]] = user_info
    $nicks_cache[user[:nick]] = Time.now.to_i
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

def handle_message(is_bot, reply_to, user, text, modes=[], channel=nil)
  channel = reply_to if channel.nil?
  
  chat_channel_from_name reply_to

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
        IRCAPI.send_to_hook hook, 'message', reply_to, user[:nick], text, match, modes
      end
    else
      #puts "did not match #{hook['match']}"
    end
  end
end

$channels = {}
$nicks = {}
$nicks_cache = {}

$client = Cinch::Bot.new do
  configure do |c|
    c.server = $config['irc']['host']
    c.port = $config['irc']['port']
    if $config['irc']['password']
      c.password = $config['irc']['password']
    end
    if $config['irc']['sasl']
      c.sasl.username = $config['irc']['nick']
      c.sasl.password = $config['irc']['sasl']
    end
    if $config['irc']['ssl']
      c.ssl.use = true
    end
    c.nick = $config['irc']['nick']
    c.user = $config['irc']['username']
    c.channels = $config['irc']['channels']
  end

  on :message do |data, nick|
    channel = data.channel ? data.channel.name : $config['irc']['nick']
    reply_to = data.channel ? data.channel.name : data.user.nick
    
    if channel != reply_to
	   puts "Received PM to #{channel} from #{reply_to}" 
    end

    # IRC "/me" lines end up coming through as PRIVMSG "\u0001ACTION waves\u0001"
    if match = data.message.match(/\u0001ACTION (.+)\u0001/)
      text = "/me #{match[1]}"
    else
      text = data.message
    end

    modes = []
    if data.channel
      modes << 'voice' if data.channel.voiced?(data.user)
      modes << 'op' if data.channel.opped?(data.user)
    end

    is_bot = data.user.nick == $config['irc']['nick']
    handle_message is_bot, reply_to, user_hash_from_irc_user(data.user), text, modes, channel
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

  #on :quit do |data|
  #  handle_event 'leave', data
  #end

  on :join do |data|
    handle_event 'join', data
  end

end

Thread.new do
  $client.start
end

IRCAPI.run!
