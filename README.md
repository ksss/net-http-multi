Net::HTTP::Multi
===

Multi http request classes.

## Net::HTTP::Multi::Sync

very simple sync loop request.

(socket write ordering : true)

## Net::HTTP::Multi::IO

multi io async request using by `IO.select`

(socket write ordering : true)

## Net::HTTP::Multi::Thread

multi async request using by Thread

(socket write ordering : false)

# Usage

```ruby
require './multi'

uri = URI.parse('http://www.example.com')

# All initialize params expect to Array of Net::HTTPRequest
reqs = []
reqs << Net::HTTP::Post.new(uri).tap{|i| i.form_data = {params: 'example'}}
reqs << Net::HTTP::Get.new(uri)

# you can choice algorithm Sync or IO or Thread
m = Net::HTTP::Multi::IO.new(reqs)
# if you choice IO algorithm,
# you send requests this order.
# sock.write(post) -> sock.write(get) -> IO.select -> sock.read(?) -> sock.read(?)
m.run
# all response is collected in reses property (Array of Net::HTTPResponse)
p m.reses #=> [#<Net::HTTPOK 200 OK readbody=true>,#<Net::HTTPOK 200 OK readbody=true>]
```


# Benchmark

```
$ ruby server.rb
```

and other process

```
$ ruby benchmark.rb
```

```
ps -o rss=: 23368
memsize_of_all: 8427273

Epoll 447req/sec
Epoll 319res/sec
ps -o rss=: 23616
memsize_of_all: 8695473
Select 437req/sec
Select 309res/sec
ps -o rss=: 23616
memsize_of_all: 8687011
Sync 63req/sec
Sync 63res/sec
ps -o rss=: 23616
memsize_of_all: 8494221
Thread 333req/sec
Thread 317res/sec
ps -o rss=: 29040
memsize_of_all: 26547714
```
