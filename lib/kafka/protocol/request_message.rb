module Kafka
  module Protocol
    class RequestMessage
      API_VERSION = 0

      def initialize(options={})
        api_key = options[:api_key]
        api_version = options[:api_version] || API_VERSION
        correlation_id = options[:correlation_id]
        client_id = options[:client_id]
        request = options[:request]

        @api_key = api_key
        @api_version = api_version
        @correlation_id = correlation_id
        @client_id = client_id
        @request = request
      end

      def encode(encoder)
        encoder.write_int16(@api_key)
        encoder.write_int16(@api_version)
        encoder.write_int32(@correlation_id)
        encoder.write_string(@client_id)

        @request.encode(encoder)
      end
    end
  end
end
