class Gateway

  def self.process(&block)
    if $config['thread']
      Thread.new do
        block.call
      end
    else
      block.call
    end
  end

  @@hooks = nil

  def self.load_hooks
    begin
      hooks = YAML.load_file 'hooks.yml'
      hooks['hooks'].each do |hook|
        if hook['channels']
          hook['channels'].flatten!
        end
      end
      @@hooks = hooks
    rescue => e
      if @@hooks
        puts "ERROR: Failed to parse hooks.yml, returning cached version: \"#{e.message}\""
        @@hooks
      else
        raise e
      end
    end
  end

  # Check whether the given hook should be checked based on the channel+server the message is from
  def self.channel_match(hook, channel, server)
    if hook['channels']
      # Skip this hook unless the channel matches
      matched = false
      hook['channels'].each do |check|
        c, s = check.split '@'
        if s == server and (c == '' || c == channel)
          matched = true
        end
      end
      matched
    else
      # No channel restrictions means always match
      true
    end
  end    

  def self.text_match(hook, text)
    return false if hook['match'].nil? || text.nil?
    match = hook['match']
    if m=/^\/(.+)\/i$/.match(match)
      match = m.captures[0]
      i = true
    else
      i = true # always do case insensitive matches
    end
    Regexp.new(match, i).match(text)
  end

  def self.selfignore(hook, is_bot)
    return hook['selfignore'] == true && is_bot
  end

  def self.send_to_hook(hook, timestamp, network, server, channel, author, type, content, match, modes=[])
    token = JWT.encode({
      :channel => channel.uid,
      :exp => (Time.now.to_i + 60*5)  # webhook URLs are valid for 5 minutes
    }, $base_config['secret'], 'HS256')

    response_url = "#{$config['api']['base_url']}/message/#{URI.encode_www_form_component(token)}"

    params = {
      type: type,
      timestamp: timestamp,
      network: network,
      server: server,
      channel: channel.to_hash,
      author: author.to_hash,
      content: content,
      match: match ? match.captures : nil,
      modes: modes,
      response_url: response_url
    }

    # jj params

    response = HTTParty.post hook['url'], {
      body: params.to_json,
      headers: {
        'Authorization' => "Bearer #{hook['token']}",
        'Content-type' => 'application/json'
      }
    }

    if $config['verbose']
      puts "Sent to web hook: #{hook['url']}"
      puts "HTTP response code: #{response.code}"
      puts "Response body:\n---"
      puts response.parsed_response
      puts "---"
    end

    response
  end

  def self.enhance_profile(hook, user_info)
    response = HTTParty.post hook['url'], {
      body: user_info.to_hash.to_json,
      headers: {
        'Authorization' => "Bearer #{hook['token']}",
        'Content-type' => 'application/json'
      }
    }
    puts "Got response from profile service"
    puts response.parsed_response

    data = response.parsed_response
    if data.class == Hash
      ['username','name','photo','url','tz'].each do |key|
        user_info[key.to_sym] = data[key] if data[key]
      end
      if data['pronouns']
        ['nominative','oblique','possessive'].each do |key|
          user_info.pronouns[key.to_sym] = data['pronouns'][key] if data['pronouns'][key]
        end
      end
    end

    user_info
  end

  def self.load_tokens
    YAML.load_file('tokens.yml')['tokens']
  end

  # Check whether the given token has access to post to this channel and network
  def self.token_match(token, channel, server)
    tokens = self.load_tokens
    tokens.each do |data|

      next if data['token'] != token

      # If the user does not specify a channel, "channel" will be nil so there must only be one channel defined for this token
      if channel.nil? 
        if data['channels'] && data['channels'].length == 1
          c,s = data['channels'].first.split '@'
          if s == $server
            return c
          end
        else
          if data['channels'].nil? || data['channels'].length == 0
            return channel
          else
            return false;
          end
        end
      end

      if data['channels'].nil?
        return channel
      end

      # Otherwise, check that the channel matches one of the defined channel+servers defined
      data['channels'].each do |tmp|
        c,s = tmp.split '@'
        if s == server
          if c == '' || c == channel
            return channel
          end
        end
      end

    end
    false
  end

end
