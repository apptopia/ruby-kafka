module Kafka
  module Protocol
    class SyncGroupRequest
      def initialize(options={})
        group_id = options[:group_id]
        generation_id = options[:generation_id]
        member_id = options[:member_id]
        group_assignment = options[:group_assignment] || {}

        @group_id = group_id
        @generation_id = generation_id
        @member_id = member_id
        @group_assignment = group_assignment
      end

      def api_key
        14
      end

      def response_class
        SyncGroupResponse
      end

      def encode(encoder)
        encoder.write_string(@group_id)
        encoder.write_int32(@generation_id)
        encoder.write_string(@member_id)

        encoder.write_array(@group_assignment) do |member_id, member_assignment|
          encoder.write_string(member_id)
          encoder.write_bytes(Encoder.encode_with(member_assignment))
        end
      end
    end
  end
end
