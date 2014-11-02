#! /usr/bin/env ruby

require 'timeout'
require 'objspace'
require './multi'

class Runner
  def initialize(klass:, req:, timeout:)
    @klass = klass
    @req = req
    @timeout = timeout
  end

  def run
    i = 0
    m = nil
    reqs = [@req] * 1000
    timeout(@timeout){
      m = @klass.new(reqs)
      m.run
    }
  rescue Timeout::Error
    if m.respond_to?(:threads)
      m.threads.each{|t| t.kill}
      m.threads.each{|t| t.join}
      m.master.kill
      m.master.join
    end
  ensure
    yield m
    sleep 1
  end
end

url = "http://127.0.0.1:4567"
uri = URI.parse(url)

GC.start
puts "ps -o rss=: #{`ps -o rss= -p #{Process.pid}`.to_i}"
puts "memsize_of_all: #{ObjectSpace.memsize_of_all}"
puts ""

[:Epoll, :Select, :Sync, :Thread].each do |sym|
  klass = Net::HTTP::Multi.const_get(sym)

  req = Net::HTTP::Post.new(uri)
  req.form_data = {params: 'abc'}

  timeout = 1
  t = Time.now
  ret = nil
  GC.start
  Runner.new(klass: klass, req: req, timeout: timeout).run do |m|
    ret = m.dup
  end
  GC.start
  name = klass.name.split(/::/).last
  if ret.reses.all?{|i| i.body == 'CREATED'}
    puts "#{name} #{ret.req_send.length/timeout}req/sec"
    puts "#{name} #{ret.reses.length/timeout}res/sec"
  else
    puts "#{name}: request:NG"
  end
  puts "ps -o rss=: #{`ps -o rss= -p #{Process.pid}`.to_i}"
  puts "memsize_of_all: #{ObjectSpace.memsize_of_all}"
end
