require 'socket'
require 'uri'
require 'net/http'
require 'thread'
require 'io/epoll'

module Net
  class HTTP
    attr_reader :socket, :curr_http_version

    module Multi
      class Base
        class Pair < Struct.new(:http, :req); end
        class Break < StandardError; end

        attr_accessor :req_send, :reses

        def initialize(reqs)
          @reqs = reqs
          @req_send = []
          @reses = []
        end

        def write(req)
          http = HTTP.new(req.uri.host, req.uri.port)
          # tcp socket open
          http.send :connect

          # socket write
          req.exec http.socket, http.curr_http_version, req.path
          @req_send << req
          Pair.new(http, req)
        end
      end

      class Sync < Base
        def run
          @reses = []
          @reqs.each do |req|
            @reses << HTTP.start(req.uri.host, req.uri.port) do |http|
              @req_send << req
              http.request req
            end
          end
          self
        end
      end

      class Select < Base
        def run
          http_req_pairs = @reqs.shift(128).map do |req|
            write(req)
          end

          sockets = http_req_pairs.map{|i| i.http.socket.io}
          begin
            while true
              ios = ::IO.select(sockets)

              if ios[0]
                ios[0].each do |tcp|
                  pair = http_req_pairs.find{|i| i.http.socket.io == tcp}
                  http, req = pair.http, pair.req

                  # socket read
                  begin
                    res = HTTPResponse.read_new(http.socket)
                    res.decode_content = req.decode_content
                  end while res.kind_of?(HTTPContinue)
                  res.uri = req.uri
                  res.reading_body(http.socket, req.response_body_permitted?) {}

                  @reses << res
                  http.socket.close

                  if @reqs.empty?
                    sockets.delete(http.socket.io)
                    raise Break if sockets.length == 0
                  else
                    new_pair = write(@reqs.shift)
                    http_req_pairs[http_req_pairs.index{|i| http == i.http}] = new_pair
                    sockets[sockets.index(http.socket.io)] = new_pair.http.socket.io
                  end
                end
              end
            end
          rescue Break
          end
          self
        end
      end

      class Epoll < Base
        def run
          http_req_pairs = @reqs.shift(128).map do |req|
            write(req)
          end

          epoll = ::IO::Epoll.create
          http_req_pairs.each{|i|
            epoll.add(i.http.socket.io, IO::Epoll::IN|IO::Epoll::ET)
          }
          catch do |tag|
            while true
              epoll.wait.each do |ev|
                pair = http_req_pairs.find{|i| i.http.socket.io == ev.data}
                http, req = pair.http, pair.req

                # socket read
                begin
                  res = HTTPResponse.read_new(http.socket)
                  res.decode_content = req.decode_content
                end while res.kind_of?(HTTPContinue)
                res.uri = req.uri
                res.reading_body(http.socket, req.response_body_permitted?) {}

                @reses << res

                epoll.del(ev.data)
                http.socket.close

                if @reqs.empty?
                  throw tag if epoll.events.length == 0
                else
                  new_pair = write(@reqs.shift)
                  http_req_pairs[http_req_pairs.index{|i| http == i.http}] = new_pair
                  epoll.add(new_pair.http.socket.io, IO::Epoll::IN|IO::Epoll::ET)
                end
              end
            end
          end
          self
        end
      end

      class Thread < Base
        attr_reader :threads, :master
        def initialize(reqs, concurrency=16)
          super reqs
          @concurrency = concurrency
          @master = nil
          @threads = []
        end

        def run
          q = Queue.new
          @master = ::Thread.start {
            @reqs.each do |req|
              q.push req
            end
          }
          @threads = Array.new(@concurrency) do
            ::Thread.start {
              loop do
                break if q.size == 0
                req = q.pop
                res = HTTP.new(req.uri.host, req.uri.port).start do |http|
                  @req_send << req
                  http.request req
                end
                @reses << res
              end
            }
          end

          @threads.each do |t|
            t.join
          end
          @master.join
          self
        end
      end
    end
  end
end
