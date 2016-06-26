class SlackAPI < API

  get '/' do
    if $client.self
      "Connected to #{$client.team.name} as #{$client.self.name}"
    else
      "Not Connected"
    end
  end

  get '/cache' do
    {
      users: $users,
      nicks: $nicks,
      channels: $channels,
      channel_names: $channel_names
    }.to_json
  end

  post '/cache/expire' do
    $nicks = {}
    $users = {}
    $channels = {}
    $channel_names = {}
    "ok"
  end

  def self.send_message(channel, content)
    # Look up the channel name in the mapping table, and convert to channel ID if present
    if !$channel_names[channel].nil?
      channel = $channel_names[channel]
    elsif !['G','D','C'].include?(channel[0])
      return "unknown channel"
    end

    if match=content.match(/^\/me (.+)/)
      result = $client.web_client.chat_meMessage channel: channel, text: match[1]
    else
      result = $client.message channel: channel, text: content
    end

    result
  end

  def self.send_to_hook(hook, type, ts, channel, user, content, match)
    response = Gateway.send_to_hook hook,
      ts,
      'slack',
      $client.team.domain,
      $channels[channel],
      $users[user],
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
    if response['action'] == 'join'
      "not allowed"
    elsif response['action'] == 'leave'
      $client.web_client.channels_leave(name: channel)
      "not allowed"
    elsif response['action'] == 'typing'
      $client.typing channel: channel
    elsif response['topic']
      channel_id = $channel_names[channel]
      if channel_id
        $client.web_client.channels_setTopic(channel: channel_id, topic: response['topic'])
        "setting topic for #{channel}"
      else
        "unknown channel #{channel}"
      end
    elsif response['content']
      result = SlackAPI.send_message channel, response['content']
      return "#{result}: #{channel}" if result != true

      hooks = Gateway.load_hooks
      # TODO: the Slack API should be returning a timestamp, but the gem appears to only return "true" after sending a message
      fetch_user_info hooks, channel, $client.self.id
      handle_message hooks, Time.now.to_f, channel, $client.self.id, response['content']

      "sent"
    else
      "error"
    end
  end

end

def chat_author_from_slack_user_id(user_id)
  user = $client.web_client.users_info(user: user_id).user
  Bot::Author.new({
    uid: user_id,
    nickname: user.name,
    username: user.name,
    name: user.real_name,
    photo: user.profile.image_192,
    tz: user.tz,
  })
end

def chat_channel_from_slack_group_id(channel_id)
  channel = $client.web_client.groups_info(channel: channel_id).group
  Bot::Channel.new({
    uid: channel_id,
    name: "##{channel.name}"
  })
end

def chat_channel_from_slack_channel_id(channel_id)
  channel = $client.web_client.channels_info(channel: channel_id).channel
  Bot::Channel.new({
    uid: channel_id,
    name: "##{channel.name}"
  })
end

def chat_channel_from_slack_user_id(channel_id)
  user = $client.web_client.users_info(user: channel_id).user
  Bot::Channel.new({
    uid: channel_id,
    name: user.name
  })
end

def fetch_channel_info(channel, user)
  # Map Slack IDs to names used in configs and things
  if $channels[channel].nil?
    # The channel might actually be a group ID or DM ID
    if channel[0] == "G"
      puts "Fetching group info: #{data.channel}"
      $channels[channel] = chat_channel_from_slack_group_id channel
    elsif channel[0] == "D"
      $channels[channel] = chat_channel_from_slack_user_id user
      puts "Private message from #{$channels[channel].name}"
    elsif channel[0] == "C"
      puts "Fetching channel info: #{channel}"
      $channels[channel] = chat_channel_from_slack_channel_id channel
    end
    $channel_names[$channels[channel].name] = channel
  end
end

def fetch_user_info(hooks, channel, user)
  # TODO: expire the cache
  if $users[user].nil?
    puts "Fetching account info: #{user}"
    user_info = chat_author_from_slack_user_id user
    puts "Enhancing account info from hooks"

    hooks['profile_data'].each do |hook|
      next if $channels[channel].nil? || !Gateway.channel_match(hook, $channels[channel].name, $server)
      user_info = Gateway.enhance_profile hook, user_info
    end

    $users[user] = user_info
    $nicks[user_info.nickname] = user_info.uid
    puts user_info.inspect
  end
end

def handle_message(hooks, ts, channel, user, text)
  hooks['hooks'].each do |hook|
    # First check if there is a channel restriction on the hook
    next if $channels[channel].nil? || !Gateway.channel_match(hook, $channels[channel].name, $server)

    # Check if the text matched
    if match=Gateway.text_match(hook, text)
      puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"

      # Post to the hook URL in a separate thread
      Gateway.process do
        SlackAPI.send_to_hook hook, 'message', ts, channel, user, text, match
      end
    end
  end
end


Slack.configure do |config|
  config.token = $config['slack_token']
end

$users = {}
$nicks = {}
$channels = {}
$channel_names = {}

$client = Slack::RealTime::Client.new

$first = true

$client.on :hello do
  puts "Successfully connected, welcome '#{$client.self.name}' to the '#{$client.team.name}' team at https://#{$client.team.domain}.slack.com."
end

$client.on :message do |data|
  if $first
    $first = false
    next
  end

  if !data.hidden
    hooks = Gateway.load_hooks

    puts "================="
    puts data.inspect

    fetch_channel_info data.channel, data.user
    fetch_user_info hooks, data.channel, data.user

    # If the message is a normal message, then there might be occurrences of "<@xxxxxxxx>" in the text, which need to get replaced
    text = data.text
    text.gsub!(/<@([A-Z0-9]+)>/i) do |match|
      fetch_user_info hooks, data.channel, $1
      if $users[$1]
        "<@#{$1}|#{$users[$1].nickname}>"
      else
        match
      end
    end

    # Now unescape the rest of the message
    text = Slack::Messages::Formatting.unescape(text)

    if data.subtype && data.subtype == 'me_message'
      text = "/me #{text}"
    end

    handle_message hooks, data.ts, data.channel, data.user, text

  end
end

$client.on :close do |_data|
  puts "Client is about to disconnect"
end

$client.on :closed do |_data|
  puts "Client has disconnected successfully!"
end

# Start the Slack client
$client.start_async

# Start the HTTP API
SlackAPI.run!

