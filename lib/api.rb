class API < Sinatra::Base
  configure do
    set :threaded, false
    set :bind, $config['api']['host']
    set :port, $config['api']['port']
  end

  post '/message' do
    puts params.inspect
    $gateway.send_to_slack params
    "sent"
  end
end
