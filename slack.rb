require './lib/api'

class SlackAPI < API

  get '/' do
    if $client.self
      "Connected to #{$client.team.name} as #{$client.self.name}"
    else
      "Not Connected"
    end
  end

  def self.send_message(channel, content)
    # Look up the channel name in the mapping table, and convert to channel ID if present
    if !$channel_names[channel].nil?
      channel = $channel_names[channel]
    elsif !['G','D','C'].include?(channel[0])
      return "unknown channel"
    end

    result = $client.message channel: channel, text: content
    puts "======= sent to Slack ======="
    puts result.inspect

    "sent"
  end

  def self.handle_message(hook, data, match, text)
    response = Gateway.send_to_hook hook,
      'slack',
      "#{$client.team.domain}.slack.com",
      ($channels[data.channel] ? $channels[data.channel].name : data.channel),
      data.channel,
      data.ts,
      data.type,
      data.user,
      ($users[data.user] ? $users[data.user].name : data.user),
      text,
      match

    if response.parsed_response.is_a? Hash
      puts response.parsed_response
      SlackAPI.send_message data.channel, response.parsed_response['content']
    else
      if !response.parsed_response.nil?
        puts response.inspect
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
    puts "================="
    puts data.inspect

    # Map Slack IDs to names used in configs and things
    if $channels[data.channel].nil?
      # The channel might actually be a group ID or DM ID
      if data.channel[0] == "G"
        puts "Fetching group info: #{data.channel}"
        $channels[data.channel] = $client.web_client.groups_info(channel: data.channel).group
        $channels[data.channel].name = "##{$channels[data.channel].name}"
      elsif data.channel[0] == "D"
        $channels[data.channel] = $client.web_client.users_info(user: data.user).user
        puts "Private message from #{$channels[data.channel].name}"
      elsif data.channel[0] == "C"
        puts "Fetching channel info: #{data.channel}"
        $channels[data.channel] = $client.web_client.channels_info(channel: data.channel).channel
        $channels[data.channel].name = "##{$channels[data.channel].name}"
      end
      $channel_names[$channels[data.channel].name] = data.channel
    end

    if $users[data.user].nil?
      puts "Fetching account info: #{data.user}"
      $users[data.user] = $client.web_client.users_info(user: data.user).user
      $nicks[$users[data.user].name] = $users[data.user]
    end

    # If the message is a normal message, then there might be occurrences of "<@xxxxxxxx>" in the text, which need to get replaced
    text = data.text
    text.gsub!(/<@([A-Z0-9]+)>/i) do |match|
      if $users[$1]
        "<@#{$1}|#{$users[$1].user.name}>"
      else
        # Look up user info and store for later
        info = $client.web_client.users_info(user: $1)
        if info
          $users[$1] = info
          "<@#{$1}|#{$users[$1].user.name}>"
        else
          match
        end
      end
    end

    # Now unescape the rest of the message
    text = Slack::Messages::Formatting.unescape(text)

    hooks = Gateway.load_hooks
    hooks['hooks'].each do |hook|

      # First check if there is a channel restriction on the hook
      next if $channels[data.channel].nil? || !Gateway.channel_match(hook, $channels[data.channel].name, $server)

      # Check if the text matched
      if match=Gateway.text_match(hook, text)
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
        puts match.captures.inspect

        # Post to the hook URL in a separate thread
        if $config['thread']
          Thread.new do
            SlackAPI.handle_message hook, data, match, text
          end
        else
          SlackAPI.handle_message hook, data, match, text
        end

      end
    end
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

