require "kafka/broker"

module Kafka
  class BrokerPool
    def initialize(options={})
      connection_builder = options[:connection_builder]
      logger = options[:logger]

      @logger = logger
      @connection_builder = connection_builder
      @brokers = {}
    end

    def connect(host, port, options={})
      node_id = options[:node_id]

      return @brokers.fetch(node_id) if @brokers.key?(node_id)

      broker = Broker.new(
        connection: @connection_builder.build_connection(host, port),
        node_id: node_id,
        logger: @logger,
      )

      @brokers[node_id] = broker unless node_id.nil?

      broker
    end

    def close
      @brokers.each do |id, broker|
        @logger.info "Disconnecting broker #{id}"
        broker.disconnect
      end
    end
  end
end
