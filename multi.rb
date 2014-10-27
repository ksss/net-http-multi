#! /usr/bin/env ruby

require 'socket'
require 'uri'
require 'net/http'
require 'thread'

module Net
  class HTTP
    attr_reader :socket, :curr_http_version

    module Multi
      class Base
        attr_accessor :reses

        def initialize(reqs)
          @reqs = reqs
          @reses = []
        end
      end

      class Sync < Base
        def run
          @reses = []
          @reqs.each do |req|
            @reses << HTTP.start(req.uri.host, req.uri.port) do |http|
              http.request req
            end
          end
          self
        end
      end

      class IO < Base
        class Break < StandardError; end
        class Pair < Struct.new(:http, :req); end

        def write(req)
          http = HTTP.new(req.uri.host, req.uri.port)
          http.send :connect

          # socket.write
          req.exec http.socket, http.curr_http_version, req.path
          Pair.new(http, req)
        end

        def run
          http_req_pairs = @reqs.shift(64).map do |req|
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

      class Thread < Base
        def initialize(reqs, concurrency=16)
          super reqs
          @concurrency = concurrency
        end

        def run
          q = Queue.new
          master = ::Thread.start {
            @reqs.each do |req|
              q.push req
            end
          }
          threads = Array.new(@concurrency) do
            ::Thread.start {
              loop do
                break if q.size == 0
                req = q.pop
                res = HTTP.new(req.uri.host, req.uri.port).start do |http|
                  http.request req
                end
                @reses << res
              end
            }
          end

          threads.each do |t|
            t.join
          end
          master.join
          self
        end
      end
    end
  end
end
