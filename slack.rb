require './lib/api'

class SlackAPI < API

  get '/' do
    if $client.self
      "Connected to #{$client.team.name} as #{$client.self.name}"
    else
      "Not Connected"
    end
  end

end

Slack.configure do |config|
  config.token = $config['slack_token']
end

$users = {}
$nicks = {}
$channels = {}

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

    hooks = Gateway.load_hooks

    hooks['hooks'].each do |hook|

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
      end

      # First check if there is a channel restriction on the hook
      next if $channels[data.channel].nil? || !Gateway.channel_match(hook, $channels[data.channel].name, "#{$client.team.domain}.slack.com")

      # Check if the text matched
      if match=Gateway.text_match(hook, data.text)
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"
        puts match.captures.inspect

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

        # Post to the hook URL in a separate thread
        Thread.new do
          params = {
            network: 'slack',
            server: "#{$client.team.domain}.slack.com",
            channel: ($channels[data.channel] ? $channels[data.channel].name : data.channel),
            timestamp: data.ts,
            type: data.type,
            user: data.user,
            nick: ($users[data.user] ? $users[data.user].name : data.user),
            text: text,
            match: match.captures,
            response_url: "http://localhost:#{$config['api']['port']}/message?channel=#{URI.encode_www_form_component(data.channel)}"
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
            $gateway.send_to_slack({channel: data.channel}.merge response.parsed_response)
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

