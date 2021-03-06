require 'thread'
require 'websocket'
require 'socket'
require 'openssl'
require 'uri'
require "ws_client/version"

module WsClient
  def self.connect(url, options={})
    client = ::WsClient::Client.new
    yield client if block_given?
    client.connect url, options
    return client
  end

  class Client
    attr_reader :url, :handshake, :message_queue, :connect_options

    MS_2 = (1/500.0)
    FRAME_SIZE = 2048

    def initialize
      @message_queue = ::Queue.new
    end

    def connect(url = nil, options={})
      return if open?

      @connect_options = options
      @connect_url = @url = url || @connect_url || @url

      raise "No URL to connect to" if url.nil?

      uri = URI.parse url
      @socket = TCPSocket.new(uri.host, uri.port || (uri.scheme == 'wss' ? 443 : 80))
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      if ['https', 'wss'].include?(uri.scheme)
        ssl_context = options[:ssl_context] || begin
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = options[:ssl_version] || 'SSLv23'
        ctx.verify_mode = options[:verify_mode] || OpenSSL::SSL::VERIFY_NONE #use VERIFY_PEER for verification
        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths
        ctx.cert_store = cert_store
        ctx
        end

        # Keep a handle to the TCPSocket, because the SSLSocket will not clean it up for us.
        @tcp_socket = @socket
        @socket = ::OpenSSL::SSL::SSLSocket.new(@tcp_socket, ssl_context)
        @socket.connect
      end

      @closed = false

      handshake
    rescue OpenSSL::SSL::SSLError, EOFError
      # Re-use the socket cleanup logic if we have a connect failure.
      close
      raise
    end

    def reconnect
      connect(nil)
    end

    # Returns all responses that have been accepted
    def send_data_and_wait(data, timeout = MS_2, opt = { :type => :text })
      response_data = []
      write_data(data, opt)
      pull_next_message_off_of_socket(@socket, timeout)

      if message_queue.length > 0
        message_queue.length.times do
          response_data << message_queue.pop
        end
      end

      response_data
    end
    alias_method :send_data, :send_data_and_wait

    def close
      return if @closed

      write_data nil, :type => :close rescue nil
    ensure
      @closed = true
      @socket.close if @socket
      @tcp_socket.close if @tcp_socket
      @socket = nil
      @tcp_socket = nil
    end

    def closed?
      !open?
    end

    def open?
      @handshake && @handshake.finished? && !@closed
    end

    private

    def handshake
      @handshake = ::WebSocket::Handshake::Client.new :url => url, :headers => @connect_options[:headers]
      @handshaked = false
      @socket.write @handshake.to_s

      while !@handshaked
        begin
          read_sockets, _, _ = IO.select([@socket], nil, nil, 10)

          if read_sockets && read_sockets[0]
            @handshake << @socket.read_nonblock(FRAME_SIZE)

            if @socket.respond_to?(:pending) # SSLSocket
              @handshake << @socket.read(@socket.pending) while @socket.pending > 0
            end

            @handshaked = @handshake.finished?
          end
        rescue IO::WaitReadable
          retry
        rescue IO::WaitWritable
          IO.select(nil, [socket])
          retry
        end
      end
    end

    def pull_next_message_off_of_socket(socket, timeout = 10, last_frame = nil)
      read_sockets, _, _ = IO.select([socket], nil, nil, timeout)

      if read_sockets && read_sockets[0]
        frame = last_frame || ::WebSocket::Frame::Incoming::Client.new

        begin
          frame << socket.read_nonblock(FRAME_SIZE)

          if socket.respond_to?(:pending)
            frame << socket.read(socket.pending) while socket.pending > 0
          end

          if msg = frame.next
            case msg.type
            when :ping
              send_data_and_wait(msg.data, 10, :type => :pong)
            else
              message_queue << msg
            end

            pull_next_message_off_of_socket(socket, MS_2) # 2ms penalty for new frames
          else
            pull_next_message_off_of_socket(socket, timeout, frame)
          end
        rescue IO::WaitReadable
          IO.select([socket])
          retry
        rescue IO::WaitWritable
          IO.select(nil, [socket])
          retry
        rescue => e
          close
          raise
        end
      end
    end

    def write_data(data, opt)
      frame = ::WebSocket::Frame::Outgoing::Client.new(:data => data, :type => opt[:type], :version => @handshake.version)
      frame_str = frame.to_s

      loop do
        break if frame_str.empty? || @closed

        begin
          num_bytes_written = @socket.write_nonblock(frame_str)
          frame_str = frame_str[num_bytes_written..-1]
        rescue IO::WaitReadable
          IO.select([@socket]) # OpenSSL needs to read internally
          retry
        rescue IO::WaitWritable, Errno::EINTR
          IO.select(nil, [@socket])
          retry
        rescue => e
          close
          raise
        end
      end
    end
  end
end
