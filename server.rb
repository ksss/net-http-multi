#! /usr/bin/env ruby

require 'sinatra'

get '/' do
  sleep 0.01
  'OK'
end

post '/' do
  sleep 0.01
  'CREATED'
end
