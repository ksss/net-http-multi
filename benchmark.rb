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
  ensure
    yield m
  end
end

url = "http://127.0.0.1:4567"
uri = URI.parse(url)

[:Sync, :IO, :Thread].each do |sym|
  klass = Net::HTTP::Multi.const_get(sym)

  req = Net::HTTP::Post.new(uri)
  req.form_data = {params: 'abc'}

  reses = nil
  timeout = 1
  t = Time.now
  ret = nil
  GC.start
  Runner.new(klass: klass, req: req, timeout: timeout).run do |m|
    ret = m
  end
  GC.start

  if ret.reses.all?{|i| i.body == 'CREATED'}
    puts "#{klass}: #{ret.reses.length/timeout}res/sec, time: #{Time.now - t}s"
  else
    puts "#{klass}: request:NG, #{ret.reses.length/timeout}res/sec, time: #{Time.now - t}s"
  end
  puts "ps -o rss=: #{`ps -o rss= -p #{Process.pid}`.to_i}"
  puts "memsize_of_all: #{ObjectSpace.memsize_of_all}"
end
