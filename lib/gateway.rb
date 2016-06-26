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

  def self.load_hooks
    YAML.load_file 'hooks.yml'
  end

  # Check whether the given hook should be checked based on the channel+server the message is from
  def self.channel_match(hook, channel, server)
    if hook['channels']
      # Skip this hook unless the channel matches
      matched = false
      hook['channels'].each do |check|
        c, s = check.split '@'
        if s == server and c == channel
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
    Regexp.new(hook['match']).match(text)
  end

  def self.send_to_hook(hook, timestamp, network, server, channel, author, type, content, match)
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
      response_url: response_url
    }

    jj params

    HTTParty.post hook['url'], {
      body: params.to_json,
      headers: {
        'Authorization' => "Bearer #{hook['token']}",
        'Content-type' => 'application/json'
      }
    }
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
        if data['channels'].length == 1
          c,s = data['channels'].first.split '@'
          if s == $server
            return c
          end
        else
          if data['channels'].length == 0
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
