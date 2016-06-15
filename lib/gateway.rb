class Gateway

  def send_to_slack(params)
    $client.message channel: (params[:channel] || params['channel']), text: (params[:text] || params['text'])
  end

  def send_to_irc(params)
    if params[:channel] || params['channel']
      channel = params[:channel] || params['channel']
      $client.Channel(channel).send (params[:text] || params['text'])
    elsif params[:user] || params['user']
      user = params[:user] || params['user']
      $client.User(user).send (params[:text] || params['text'])
    end
  end

  def self.load_hooks
    YAML.load_file 'hooks.yml'
  end

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
    Regexp.new(hook['match']).match(text)
  end    

end
