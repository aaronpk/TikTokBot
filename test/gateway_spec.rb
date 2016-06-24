require_relative './init'

$server = 'example'

class TestGateway < Gateway

  def self.load_tokens
    [
      {
        'token' => 'a'
      },
      {
        'token' => 'b',
        'channels' => [
          '#test@example',
          '#foo@example'
        ]
      },
      {
        'token' => 'c',
        'channels' => [
          '#test@example',
        ]
      },
      {
        'token' => 'd',
        'channels' => [
          '@example'
        ]
      }
    ]
  end

end

describe TestGateway do

  it 'rejects invalid tokens' do
    TestGateway.token_match('z', '#test', 'example').must_equal false
  end

  it 'accepts wildcard token for any channel and server' do
    TestGateway.token_match('a', '#test', 'example').must_equal '#test'
    TestGateway.token_match('a', '#foo', 'example').must_equal '#foo'
    TestGateway.token_match('a', '#foo', 'bar').must_equal '#foo'
  end

  it 'accepts valid token with a valid channel' do
    TestGateway.token_match('b', '#test', 'example').must_equal '#test'
    TestGateway.token_match('b', '#foo', 'example').must_equal '#foo'
  end

  it 'rejects valid token for invalid channel' do
    TestGateway.token_match('b', '#bar', 'example').must_equal false
    TestGateway.token_match('c', '#bar', 'example').must_equal false
  end

  it 'rejects valid token for wrong server' do
    TestGateway.token_match('b', '#bar', 'wrong').must_equal false
    TestGateway.token_match('c', '#bar', 'wrong').must_equal false
    TestGateway.token_match('d', '#foo', 'wrong').must_equal false
  end

  it 'accepts empty channel for a token valid for only a single channel' do
    TestGateway.token_match('c', nil, 'example').must_equal '#test'
  end

  it 'accepts valid token for any channel on a server' do
    TestGateway.token_match('d', '#test', 'example').must_equal '#test'
    TestGateway.token_match('d', '#foo', 'example').must_equal '#foo'
  end

end
