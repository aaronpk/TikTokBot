# TikTokBot

TikTokBot is a bot framework for Slack and IRC.


## Hooks

All the functionality of the bot is provided by external hooks. The core bot simply matches incoming messages against the hooks and dispatches the request to be handled by the hook.

### Defining Hooks

All hooks are defined in `hooks.yml`. This file is reloaded on every message to the bot, so you can make changes to the hooks without restarting the bot.

Hook entries consist of the following parameters:

* `match` - A regex that will be run against the incoming chat text. The hook will only run if the regex matches. You can define capture groups that will be passed to the hook as well.
* `url` - The full URL to post the incoming message to.
* `token` - If defined, this token will be sent as a bearer token to the hook URL.
* `channels` - An array of channels to scope this hook to. If none are defined, this hook will be matched against every channel on every server.

Channel entries include a server name and optionally a channel name. If no channel is defined, the hook will be matched for every message on the server.

Examples:

This hook will match every message in the #example room on the freenode server.

```
  match: ".*"
  url: "http://example.com/log"
  channels:
  - "#example@freenode"
```

This hook will match every message in the every room the bot is in on the freenode server.

```
  match: ".*"
  url: "http://example.com/log"
  channels:
  - "@freenode"
```



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
  "action": "part",
  "channel": "#example"
}
```

