require "rubygems"
require "bud"

# ruby test_chord.rb 127.0.0.1:88888 127.0.0.1:1111
# Node address: 127.0.0.1 : 88888
# 127.0.0.1:88888   127.0.0.1:1111
# cnt is 30
# ["127.0.0.1:88888", 30, "127.0.0.1:1111", 2448879687529016159, nil]
# cnt is 178
# ["127.0.0.1:88888", 178, "127.0.0.1:3333", 11778342510740520996, nil]
# cnt is 299
# ["127.0.0.1:88888", 299, "127.0.0.1:2222", 6360608293957101674, nil]
# cnt is 321
# ["127.0.0.1:88888", 321, "127.0.0.1:4444", 17276053428677416473, nil]
# cnt is 433
# ["127.0.0.1:88888", 433, "127.0.0.1:6666", 11158912765186492587, nil]
# cnt is 599
# ["127.0.0.1:88888", 599, "127.0.0.1:5555", 18225634829280344212, nil]
# cnt is 616
# ["127.0.0.1:88888", 616, "127.0.0.1:7777", 2881550079865980548, nil]

class TestChord
  include Bud
  attr_accessor :nodeAddr
  attr_accessor :targetAddr
  attr_accessor :lookupKey

  def initialize(nodeAddr,targetAddr, opts={})
    @nodeAddr = nodeAddr
    @targetAddr = targetAddr
#    puts "#{@targetAddr}"
    super opts
  end

  state do
    table :ringNode, [:me, :target]
    channel :lookupReq, [:@lkupNode, :lkupKey, :requester, :eventNo, :ruleName]
    channel :lookupResults, [:@fdNode, :fdKey, :fdReqID, :fdReq, :eventNo, :ruleName]
    table :result,  [:fdNode, :fdKey, :fdReq, :eventNo, :ruleName]
    table :reqKey,[:reqValue]
  end

  bloom do

    lookupReq <~ (ringNode*reqKey).pairs {|r,q| [r.target, q.reqValue, r.me, rand(2**64), "lookup88888"]}
    result <= lookupResults {|r| [r.fdNode, r.fdKey, r.fdReq, r.eventNo]}

    stdio <~ result.inspected
  end
end



ip,port = ARGV[0].split(":")
puts "Node address: #{ip} : #{port}"


testChord = TestChord.new(ARGV[0],ARGV[1],:ip => ip, :port => port.to_i)

testChord.run_bg

testChord.sync_do{
  testChord.ringNode <= [[testChord.nodeAddr, testChord.targetAddr]]
}

puts "#{testChord.nodeAddr}   #{testChord.targetAddr}"
7.times {|i|
  sleep(1)
  cnt =  i*100 + rand(100)
  puts "cnt is #{cnt}"
  testChord.sync_do {
  testChord.reqKey <= [[cnt]]
  }
}

sleep(5)

