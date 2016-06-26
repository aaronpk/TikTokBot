class API < Sinatra::Base
  configure do
    set :threaded, false
    set :bind, $config['api']['host']
    set :port, $config['api']['port']
  end

  # Send a message to a channel
  # 
  # Authorization: Bearer token
  # Parameters:
  # - content
  # - channel (optional)
  post '/message' do
    if request.env['HTTP_AUTHORIZATION'].nil?
      return "missing access token"
    end

    # Access control
    if match=/Bearer (.+)/.match(request.env['HTTP_AUTHORIZATION'])
      token = match.captures[0]

      allowed = Gateway.token_match token, params[:channel], $server

      if allowed
        self.class.handle_response params[:channel], params
      else
        "not allowed"
      end
    else
      "invalid access token"
    end
  end

  # Post a message in response to a web hook
  # The token encodes the channel that this message is sent to
  #
  # Parameters:
  # - content
  post '/message/:token' do
    puts params.inspect

    if params[:token].nil?
      return "missing token"
    end

    # Verify the token and extract the channel
    begin
      token = JWT.decode params[:token], $base_config['secret'], 'HS256'

      channel = token[0]['channel']

      self.class.handle_response channel, params
    rescue JWT::ExpiredSignature
      "url expired"
    end
  end
end
