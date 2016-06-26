# module Events

#   class Event
#     @type = nil
#     attr_accessor :type
#   end

#   class Message < Event
#     @type = 'message'
#   end

#   class Join < Event
#     @type = 'join'
#   end

#   class Quit < Event
#     @type = 'quit'
#   end

#   class Invite < Event
#     @type = 'invite'
#   end

#   class Nick < Event
#     @type = 'nick'
#   end

#   class Topic < Event
#     @type = 'topic'
#   end

# end

module Bot

  class ChatObject
    @data = {}
    attr_accessor :data

    def initialize(data)
      @data = data
    end

    def method_missing(m, *args)
      if m.match /\=$/
        if m == '[]='.to_sym
          @data[args[0]] = args[1]
        else
          @data[m.to_s.chomp('=').to_sym] = args[0]
        end
      else
        @data[m]
      end
    end
  end

  class Author < ChatObject
    def initialize(data)
      super data
      @data[:pronouns] = Pronouns.new(data[:pronouns] || {})
    end

    def to_hash
      data = {
        uid: @data[:uid],
        nickname: @data[:nickname],
        username: @data[:username],
        name: @data[:name],
        photo: @data[:photo],
        url: @data[:url],
        tz: @data[:tz],
        pronouns: @data[:pronouns].to_hash
      }
      data
    end
  end

  class Channel < ChatObject
    def to_hash
      {
        uid: @data[:uid],
        name: @data[:name],
      }
    end
  end

  class Pronouns < ChatObject
    def to_hash
      {
        nominative: @data[:nominative],
        oblique: @data[:oblique],
        possessive: @data[:possessive],
      }
    end
  end

end
