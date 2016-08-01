# TikTokBot

TikTokBot is a bot framework for Slack and IRC.

## Configuration

There are three configuration files you'll need to set up.

* `config.yml` - Defines the IRC and Slack servers the bot will connect to, as well as the corresponding HTTP servers to set up.
 * `secret` - Defines the master secret used to encrypt JWT tokens.
 * `servers` - Configures the IRC and Slack servers. See `config.example.yml` for examples.
* `tokens.yml` - Defines the API tokens used to trigger the bot from external services. See `tokens.example.yml` for examples.
* `hooks.yml` - Defines the bot hooks that will trigger outgoing requests. See the section below, "Hooks" for details.

## Starting the Bot

Start an instance of the bot connecting to the server specified. The name used in this command corresponds with a `servers` entry in `config.yml`.

```bash
bundle exec ruby tiktok.rb example
```

## Hooks

All the functionality of the bot is provided by external hooks. The core bot simply matches incoming messages against the hooks and dispatches the request to be handled by the hook.

### Defining Hooks

All hooks are defined in `hooks.yml`. This file is reloaded on every message to the bot, so you can make changes to the hooks without restarting the bot.

Hook entries consist of the following parameters:

* `match` - A regex that will be run against the incoming chat text. The hook will only run if the regex matches. You can define capture groups that will be passed to the hook as well.
* `events` - If you want to match join/leave/topic events instead of text, include the events you are listening to in this property instead of specifying a `match` regex.
* `url` - The full URL to post the incoming message to.
* `token` - If defined, this token will be sent as a bearer token to the hook URL.
* `channels` - An array of channels to scope this hook to. If none are defined, this hook will be matched against every channel on every server.

Channel entries include a server name and optionally a channel name. If no channel is defined, the hook will be matched for every message on the server.

Examples:

This hook will match every message in the #example room on the freenode server.

```yaml
  match: ".*"
  url: "http://example.com/log"
  channels:
  - "#example@freenode"
```

This hook will match every message in the every room the bot is in on the freenode server.

```yaml
  match: ".*"
  url: "http://example.com/log"
  channels:
  - "@freenode"
```

Hooks can use regular expressions to match. By default matches are case sensitive. If you define the regex like the below, then it will use a case insensitive match. This is the only flag accepted.

```yaml
  match: /foo/i
```

The below hook will run for every join/part/topic event in the given channels.

```yaml
  events:
  - join
  - leave
  - topic
  url: "http://example.com/log"
  channels:
  - "#example@freenode"
```

Because this is YAML, you can define a list of common channel groups and re-use it for hooks. At the top of your file, define your list of channels as demonstrated below, then use it in a hook definition.

```yaml
group1: &GROUP1
- "#foo@freenode"
- "#bar@freenode"

hooks:

- match: "^ping$"
  channels: *GROUP1
  url: "http://localhost:8000/ping.php"

- match: "^pong$"
  channels: 
  - *GROUP1
  - "#pong@freenode"
  url: "http://localhost:8000/pong.php"
```

NOTE: Replies from hooks are *also* sent back through the hook matching flow, so be careful not to end up in an infinite loop! This allows you to use a global matching hook to log every event, or to trigger hooks from other hooks. Mainly you should make sure that if you have a broadly matching hook such as `.*` that it doesn't cause the bot to say anything.


## Profile Data

Similar to defining hooks that run when messages are received, you can also define hooks that are run every time a new user says something, in order to enhance their profile data from external sources. By default, the bot will use the available information to build a user profile (e.g. name, profile photo from Slack, but very little is available from IRC). If you define a `profile_data` hook, the hook will receive a payload when a user needs to be looked up.

### Request

The first time a Slack user appears, this object will be sent to the registered profile data hook:

```json
{
  "uid": "U0HV8XXXX",
  "nickname": "aaronpk",
  "username": "aaronpk",
  "name": "Aaron Parecki",
  "photo": "https://secure.gravatar.com/avatar/11954e59b49809173d48133ec4047fce.jpg?s=192&d=https%3A%2F%2Fa.slack-edge.com%2F7fa9%2Fimg%2Favatars%2Fava_0005-192.png",
  "url": null,
  "tz": "America/Los_Angeles",
  "pronouns": {
    "nominative": null,
    "oblique": null,
    "possessive": null
  }
}
```

The IRC example is much more barebones:

```json
{
  "uid": "aaronpk",
  "nickname": "aaronpk",
  "username": "~aaronpk",
  "name": "Aaron Parecki",
  "photo": null,
  "url": null,
  "tz": null,
  "pronouns": {
    "nominative": null,
    "oblique": null,
    "possessive": null
  }
}
```


### Response

Return a JSON response with the same object you received with any of the information other than nickname or uid replaced. You can fill out the profile photo, URL, and pronouns for example.

```json
{
  "uid": "U0HV8XXXX",
  "nickname": "aaronpk",
  "username": "aaronpk",
  "name": "Aaron Parecki",
  "photo": "https://aaronparecki.com/images/aaronpk-128.jpg",
  "url": "http://aaronparecki.com",
  "tz": "US/Pacific",
  "pronouns": {
    "nominative": "he",
    "oblique": "him",
    "possessive": "his"
  }
}
```

This profile data will be sent in the `author` property of messages to the hooks.



## API

The bot has three ways of sending messages to a chat channel.


### External API

The bot exposes an external HTTP API. This API requires authentication, and the token you use may be scoped to a particular channel or server.

#### Authentication

Send the token in the `Authorization` header as a bearer token:

```
Authorization: Bearer xxxtokenxxx
```

You will get an error if you try to send to a channel that the token is not valid for. Tokens are defined in `tokens.yml` and may be scoped to one or more channels or servers.

Some example entries in `tokens.yml`:

This token can send to any channel on any server the bot is connected to:

```yaml
- token: 1111111
```

This token can send to only the specific channels on the specific servers:

```yaml
- token: 2222222
  channels:
  - "#indiewebcamp@freenode"
```

This token can send to any channel on the given server:

```yaml
- token: 3333333
  channels:
  - "@freenode"
```


### Response URL

Each message sent to a hook includes a `response_url` parameter which includes a token. Sending a POST to this URL will cause a reply to be sent to the channel the message originated from. No authentication is necessary for this request, and no channel parameter is required. The URL is only valid for a few minutes after you receive it, but can accept multiple requests to it, making it useful for posting progress updates for long-running tasks.


### Inline Responses

Instead of making an HTTP request, you can simply respond to the web hook with a JSON body corresponding to the API request you want to make.



## Sending Messages

Sending messages works the same way whether you're sending a reply to the HTTP hook or using the API.

If you are replying to the HTTP hook or sending to the `response_url`, then the response will be sent to the channel the message came from. In order to have an effect on other channels, you'll need to post to the external API.

In all cases, the `channel` parameter only applies for using the external API. The channel is implied for responses.


### Send a normal message to a channel or user

```json
{
  "channel": "#example",
  "content": "Hello World"
}
```

```json
{
  "channel": "aaronpk",
  "content": "Hello Aaron"
}
```

### Send a "me" message

```json
{
  "channel": "#example",
  "content": "/me waves"
}
```

### Join a Channel

```json
{
  "action": "join",
  "channel": "#example"
}
```

### Leave a Channel

```json
{
  "action": "leave",
  "channel": "#example"
}
```

### Set a channel topic

```json
{
  "channel": "#example",
  "topic": "New Topic"
}
```

### Typing indicator

For Slack, the bot can indicate it's typing a message. This only works when sent to the `response_url`. This should be sent no more than once every 3 seconds.

```json
{
  "action": "typing"
}
```

### Reactions 

For Slack, the bot can post reactions in response to a message. Provide the timestamp of the message to add the reaction to, and include the emoji name in a property named "emoji".

```json
{
  "channel": "#example",
  "action": "react",
  "timestamp": "1470083825.000020",
  "emoji": "smile"
}
```

### Slack Attachments

When sending messages to Slack, they can include "attachments". See the [Slack docs](https://api.slack.com/docs/message-attachments) for more information on adding attachments to messages. A simple example of adding an image preview is below.

```json
{
  "attachments": [
    {
      "fallback": "Fallback text",
      "title": "Title of attachment",
      "image_url": "http://example.com/photo.jpg"
    }
  ]
}
```

### Slack File Uploads

You can upload a file as a response to a webhook or via the bot API. The bot requires that the file to upload is accessible at a URL, and it will download it from the URL and upload it to Slack as a file upload. See the [Slack docs](https://api.slack.com/methods/files.upload) for more details on the parameters. A simple example of uploading a file is below.

```json
{
  "channel": "#example",
  "file": {
    "title": "Title of the file",
    "filename": "filename.jpg",
    "url": "http://example.com/photo.jpg"
  }
}
```
