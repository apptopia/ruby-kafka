module Kafka
  module Protocol
    class MessageSet
      attr_reader :messages

      def initialize(options={})
        messages = options[:messages] || []

        @messages = messages
      end

      def size
        @messages.size
      end

      def ==(other)
        messages == other.messages
      end

      def encode(encoder)
        # Messages in a message set are *not* encoded as an array. Rather,
        # they are written in sequence.
        @messages.each do |message|
          message.encode(encoder)
        end
      end

      def self.decode(decoder)
        fetched_messages = []

        until decoder.eof?
          begin
            message = Message.decode(decoder)

            if message.compressed?
              wrapped_message_set = message.decompress
              fetched_messages.concat(wrapped_message_set.messages)
            else
              fetched_messages << message
            end
          rescue EOFError
            # We tried to decode a partial message; just skip it.
          end
        end

        new(messages: fetched_messages)
      end
    end
  end
end
