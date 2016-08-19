require "socket"

module Kafka

  # Opens sockets in a non-blocking fashion, ensuring that we're not stalling
  # for long periods of time.
  #
  # It's possible to set timeouts for connecting to the server, for reading data,
  # and for writing data. Whenever a timeout is exceeded, Errno::ETIMEDOUT is
  # raised.
  #
  class SSLSocketWithTimeout

    # Opens a socket.
    #
    # @param host [String]
    # @param port [Integer]
    # @param connect_timeout [Integer] the connection timeout, in seconds.
    # @param timeout [Integer] the read and write timeout, in seconds.
    # @param ssl_context [OpenSSL::SSL::SSLContext] which SSLContext the ssl connection should use
    # @raise [Errno::ETIMEDOUT] if the timeout is exceeded.
    def initialize(host, port, options={})
      connect_timeout = options[:connect_timeout]
      timeout = options[:timeout]
      ssl_context = options[:ssl_context]

      addr = Socket.getaddrinfo(host, nil)
      sockaddr = Socket.pack_sockaddr_in(port, addr[0][3])

      @timeout = timeout

      @tcp_socket = Socket.new(Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0)
      @tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # first initiate the TCP socket
      begin
        # Initiate the socket connection in the background. If it doesn't fail 
        # immediately it will raise an IO::WaitWritable (Errno::EINPROGRESS) 
        # indicating the connection is in progress.
        @tcp_socket.connect_nonblock(sockaddr)
      rescue IO::WaitWritable
        # IO.select will block until the socket is writable or the timeout
        # is exceeded, whichever comes first.
        unless IO.select(nil, [@tcp_socket], nil, connect_timeout)
          # IO.select returns nil when the socket is not ready before timeout 
          # seconds have elapsed
          @tcp_socket.close
          raise Errno::ETIMEDOUT
        end

        begin
          # Verify there is now a good connection.
          @tcp_socket.connect_nonblock(sockaddr)
        rescue Errno::EISCONN
          # The socket is connected, we're good!
        end
      end

      # once that's connected, we can start initiating the ssl socket
      @ssl_socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, ssl_context)

      begin
        # Initiate the socket connection in the background. If it doesn't fail 
        # immediately it will raise an IO::WaitWritable (Errno::EINPROGRESS) 
        # indicating the connection is in progress.
        # Unlike waiting for a tcp socket to connect, you can't time out ssl socket
        # connections during the connect phase properly, because IO.select only partially works.
        # Instead, you have to retry.
        @ssl_socket.connect_nonblock
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK, IO::WaitReadable
        IO.select([@ssl_socket])
        retry
      rescue IO::WaitWritable
        IO.select(nil, [@ssl_socket])
        retry
      end
    end

    # Reads bytes from the socket, possible with a timeout.
    #
    # @param num_bytes [Integer] the number of bytes to read.
    # @raise [Errno::ETIMEDOUT] if the timeout is exceeded.
    # @return [String] the data that was read from the socket.
    def read(num_bytes)
      buffer = ''
      until buffer.length >= num_bytes
        begin
          # unlike plain tcp sockets, ssl sockets don't support IO.select
          # properly.
          # Instead, timeouts happen on a per read basis, and we have to
          # catch exceptions from read_nonblock, and gradually build up
          # our read buffer.
          buffer << @ssl_socket.read_nonblock(num_bytes - buffer.length)
        rescue IO::WaitReadable
          unless IO.select([@ssl_socket], nil, nil, @timeout)
            raise Errno::ETIMEDOUT
          end
          retry
        rescue IO::WaitWritable
          unless IO.select(nil, [@ssl_socket], nil, @timeout)
            raise Errno::ETIMEDOUT
          end
          retry
        end
      end
      buffer
    end

    # Writes bytes to the socket, possible with a timeout.
    #
    # @param bytes [String] the data that should be written to the socket.
    # @raise [Errno::ETIMEDOUT] if the timeout is exceeded.
    # @return [Integer] the number of bytes written.
    def write(bytes)
      loop do
        written = 0
        begin
          # unlike plain tcp sockets, ssl sockets don't support IO.select
          # properly.
          # Instead, timeouts happen on a per write basis, and we have to
          # catch exceptions from write_nonblock, and gradually build up
          # our write buffer.
          written += @ssl_socket.write_nonblock(bytes)
        rescue Errno::EFAULT => error
            raise error
        rescue OpenSSL::SSL::SSLError, Errno::EAGAIN, Errno::EWOULDBLOCK, IO::WaitWritable => error
          if error.is_a?(OpenSSL::SSL::SSLError) && error.message == 'write would block'
            if IO.select(nil, [@ssl_socket], nil, @timeout)
              retry
            else
              raise Errno::ETIMEDOUT
            end
          else
            raise error
          end
        end

        # Fast, common case.
        break if written == bytes.size

        # This takes advantage of the fact that most ruby implementations
        # have Copy-On-Write strings. Thusly why requesting a subrange
        # of data, we actually don't copy data because the new string
        # simply references a subrange of the original.
        bytes = bytes[written, bytes.size]
      end
    end

    def close
      @tcp_socket.close
      @ssl_socket.close
    end

    def closed?
      @tcp_socket.closed? || @ssl_socket.closed?
    end

    def set_encoding(encoding)
      @tcp_socket.set_encoding(encoding)
    end
  end
end
