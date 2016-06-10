<?php

// header('Content-type: application/json');
// echo json_encode($params);

class Message {
  public $network;
  public $server;
  public $channel;
  public $timestamp;
  public $type;
  public $user;
  public $nick;
  public $text;
  private $_response_url;

  public function __construct($params) {
    $this->network = $params['network'];
    $this->server = $params['server'];
    $this->channel = $params['channel'];
    $this->timestamp = $params['timestamp'];
    $this->type = $params['type'];
    $this->user = $params['user'];
    $this->nick = $params['nick'];
    $this->text = $params['text'];
    $this->_response_url = $params['response_url'];
  }

  public function reply($message) {
    $params = [
      'text' => $message
    ];
    $ch = curl_init($this->_response_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($params));
    $response = curl_exec($ch);
    echo $response."\n";
  }
}

$msg = new Message($_POST);


if(preg_match('/^@?([a-zA-Z0-9_-]*[a-zA-Z]+[a-zA-Z0-9_]*)(\+\+|--)/', $msg->text, $match) > 0) {
  if($msg->nick == $match[1]) {
    $msg->reply('You can\'t karma yourself!');
    // if(!has_spoken_since('nokarma-'.$msg->nick, 180))
    //   speak('nokarma-'.$msg->nick, 'You can\'t karma yourself!');
  } else {
    $msg->reply("Matched '".$match[1]."' karma");

    // $K = new KarmaBot();

    // $match[1] = trim($match[1], '-_');

    // // Don't allow people to give karma to a single person more than once in an hour
    // if(spoken_count('karma-'.$nick.'-to-'.$match[1], rand(20,40)) == 0) {
    // // Rate limit all karmas, never give out more than 5 karmas in 3 minutes
    // if(spoken_count('gavekarma', 6) > 3) {
    //   if(!has_spoken_since('toomuchkarma', 2))
    //     speak('toomuchkarma', 'too much karma!');

    // } elseif(spoken_count('gavekarma', 1) > 2) {
    //   if(!has_spoken_since('toomuchkarma10', 1))
    //     speak('toomuchkarma10', 'slow down!');
    // } else {

    //   if($match[2] == '++')
    //     $karma = $K->incr($match[1]);
    //   else
    //     $karma = $K->decr($match[1]);

    //   $N->Send($match[1] . ' has ' . $karma . ' karma');
    //   no_speak('gavekarma');
    //   no_speak('karma-'.$nick.'-to-'.$match[1]);
    // }
  }
  die();
}

$msg->reply("Nothing matched");
