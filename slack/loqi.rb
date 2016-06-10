Bundler.require
require 'yaml'

$config = YAML.load_file 'config.yml'

Slack.configure do |config|
  config.token = $config['slack_token']
end

$users = {}

$client = Slack::RealTime::Client.new

$first = true

class Bot

  def incoming(params)
    $client.message channel: params[:channel], text: (params[:text] || params['text'])
  end

end

class API < Sinatra::Base
  configure do
    set :threaded, false
  end

  get '/' do
    if $client.self
      "Connected to #{$client.team.name} as #{$client.self.name}"
    else
      "Not Connected"
    end
  end

  post '/message' do
    puts params.inspect
    $bot.incoming params
  end
end

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

    hooks = YAML.load_file 'hooks.yml'

    hooks['hooks'].each do |hook|
      if Regexp.new(hook['match']).match data.text
        puts "Matched hook: #{hook['match']} Posting to #{hook['url']}"

        if $users[data.user].nil?
          puts "Fetching account info: #{data.user}"
          $users[data.user] = $client.web_client.users_info(user: data.user)
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
            channel: data.channel,
            timestamp: data.ts,
            type: data.type,
            user: data.user,
            nick: $users[data.user].user.name,
            text: text,
            response_url: "http://localhost:4567/message?channel=#{data.channel}"
          }

          jj params

          response = HTTParty.post hook['url'], {
            body: params,
            headers: {
              'Authorization' => "Bearer #{$config['webhook_token']}"
            }
          }
          if response.parsed_response.is_a? Hash
            puts response.parsed_response
            $bot.incoming({channel: data.channel}.merge response.parsed_response)
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

$bot = Bot.new

$client.start_async

#t = Thread.new do
API.run!
#end
#t.join
