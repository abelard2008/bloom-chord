require "rubygems"
require "bud"
require "./chordUtility"

class ChordRing
  include Bud
  include ChordUtility

  # contants 
  SUCCESSORS = 4
  JOINRETRIES = 4
  JOINPERIOD = 5
  STABILIZEDPERIOD = 5
  FINGERFIXPERIOD = 10
  MISSEDPINGS = 3
  PINGPERIOD = 2
  MAXNUM = 18446744073709551616 # 2**64
  FAILUREPEROID = 1
  MAXFINGER  = 159

  attr_accessor :myID
  attr_accessor :joinRetries
#  attr_accessor :succCounts
  attr_accessor :ldmkAddr

  def initialize(myID, ldmkAddr, opts={ })
    @myID = myID
    @ldmkAddr = ldmkAddr
    @joinRetries = 0
    super opts
  end

  state do
    channel :joinReq, [:@ldmkAddr, :nodeID, :nodeAddr, :eventNo,:ruleName]
    channel :lookupReq, [:@dest, :reqKey, :reqAddr, :eventNo, :ruleName]
    channel :lookup1, [:@dest, :reqKey, :reqAddr,:ruleName]
    channel :lookupResults, [:@dest, :reqKey, :succID, :succAddr, :eventNo, :ruleName]
    channel :prec_ask, [:@dest, :srcAddr, :asker]
    channel :prec_ans, [:@dest, :precID, :precAddr, :ansAddr, :asker]
    channel :succ_ask, [:@dest,:srcAddr, :asker]
    channel :succ_ans, [:@dest, :succID, :succAddr, :asker]
    channel :precSend, [:@dest, :precID, :precAddr,:ruleName]
    channel :pingReq, [:@dest, :srcAddr, :eventNo, :ruleName]
    channel :pingResp, [:@dest, :srcAddr, :eventNo, :ruleName]

#    table :pendingPing, [:myAddr, :linkAddr, :eventNo, :timeStamp]
    table :precursor, [] => [:myAddr, :precID,:precAddr]
    table :landmark, [] => [:myAddr, :ldmkAddr, :ruleName]
    table :identifier, [] => [:myAddr, :myID, :ruleName]
    table :bestSucc, [] => [:myAddr, :succID, :succAddr]
    table :nextFingerFix, [] => [:myAddr, :entryNo]
    table :eagerFinger, [] => [:myAddr, :start, :btwnID,:btwnAddr]

    table :successor, [:myAddr,:succID,:succAddr]
    table :uniqueFinger, [:myAddr, :btwnAddr, :ruleName]
    table :finger, [:myAddr, :start] => [:btwnID,:btwnAddr]
    table :joinT, [:myAddr, :eventNo]
    table :fFix, [:myAddr, :index, :eventNo]

    scratch :fingerCount, [:tbName, :cnt]
    scratch :nextFingerFixCount, [:tbName, :cnt]
    scratch :fFixCount,[:cnt]
    scratch :joinTCount, [:cnt]
    scratch :succCount, [:cnt]
    scratch :fFixEvent, [:myAddr, :index, :eventNo]
    scratch :stabilizeEvent, [:myAddr]
    scratch :joinEvent, [:myAddr, :times, :eventNo]
    scratch :newSuccEvent, [:myAddr]
    scratch :bestSuccDist, [:myAddr, :minDist]
    scratch :succDist,[:myAddr, :allDist]
    scratch :lookupDist, [:myAddr, :reqKey, :reqAddr, :eventNo, :allDist]
    scratch :bestLookupDist, [:myAddr, :reqKey, :reqAddr, :eventNo, :minDist]
    scratch :forwardLookupT, [:myAddr, :reqKey, :reqAddr, :btwnAddr, :eventNo, :allBtwnID]
    scratch :forwardLookup, [:myAddr, :reqKey, :reqAddr, :btwnAddr, :eventNo, :minBtwnID]
    scratch :nodeFailure, [:myAddr, :linkAddr, :eventNo, :timeStamp]
    scratch :evictSucc, [:myAddr]
    scratch :maxSuccDist,[:myAddr, :maxDist]
    scratch :deleteSucc, [:myAddr, :succID, :succAddr]

    #debug
    scratch :uniqueFingerC, [:cnt]

    periodic :failurePeroid, FAILUREPEROID
    periodic :joinPeriod, JOINPERIOD
    periodic :stabPeriod, STABILIZEDPERIOD
    periodic :pingPeriod, PINGPERIOD
    periodic :fingerFixPeriod, FINGERFIXPERIOD
  end

  bootstrap do
    # Preexisting state. My landmark and myself. 
    identifier <= [[ip_port,@myID, "identifier"]]
    landmark <= [[ip_port, @ldmkAddr, "landmark"]]
#    landmark <= [[ip_port, @ldmkAddr, "landmark"]]

    # All nodes start with the nil predecessor 
    precursor <= [[ip_port, "NIL", "NIL"]]
#    successor <= [[ip_port, @myID, ip_port]]
    # Finger fixing starts with the 0th entry 
    nextFingerFix <= [[ip_port, 0]]
    eagerFinger <= [[ip_port, "NIL","NIL","NIL"]]
  end
 
    # Churn Handling
  bloom :churn do
    # Insert in entries after a delay. Change join. 
    
    # new node create 3 joining events 
    joinEvent <= (joinPeriod*identifier).pairs do |j, i| 
      @joinRetries += 1
      if @joinRetries  < JOINRETRIES 
        puts "c1 joinEvent [#{i.myAddr}, #{@joinRetries-1}]"
        [i.myAddr, @joinRetries - 1, rand(MAXNUM)]
      end
    end

    joinT <= joinEvent {|j| [j.myAddr, j.eventNo]} #c2

    # new node sends join request accord to landmark
    joinReq <~ (joinEvent*landmark*identifier).combos do |j, l, i| 
      [l.ldmkAddr, i.myID, i.myAddr, j.eventNo, "c3"] if l.ldmkAddr != i.myAddr 
    end

    # new node uses itself as its successor
    successor <= (joinEvent*landmark*identifier).combos do |j, l, i|
      if l.ldmkAddr == i.myAddr 
        puts "c4 successor [#{i.myAddr}, #{i.myID}, #{i.myAddr}]"
        [i.myAddr, i.myID, i.myAddr] 
      end
    end

    # create a lookup inside one node 
    lookupReq <~ joinReq {|j| [j.ldmkAddr, j.nodeID, j.nodeAddr, j.eventNo, "c5"]}

    # add another node to one node's successor
    successor <= (joinT*lookupResults).pairs do |j, l|
      if j.eventNo == l.eventNo
        puts "c6 successor [#{l.dest}, #{l.succID}, #{l.succAddr}]"
        [l.dest, l.succID, l.succAddr]
      end
    end
  end # churn handling

  # lookups
  bloom :lookups do
    lookupResults <~ (identifier*lookupReq*bestSucc).combos do |i, l, b | 
      puts "#{l.ruleName} (#{l.reqKey.to_i}, #{i.myID.to_i}, #{b.succID.to_i}) #{rangeOC(l.reqKey.to_i, i.myID.to_i, b.succID.to_i)}"
      [l.reqAddr, l.reqKey, b.succID, b.succAddr, l.eventNo, "l1"] if
        rangeOC(l.reqKey.to_i, i.myID.to_i, b.succID.to_i)
    end
    
    lookupDist <= (identifier*lookupReq*finger).combos do |i, l, f|
      if rangeOO(f.btwnID.to_i, i.myID.to_i, l.reqKey.to_i)
        puts "l2 lookupDist [#{i.myAddr}, #{l.reqKey}, #{l.reqAddr}, #{l.reqKey.to_i - f.btwnID.to_i - 1}]"
      [i.myAddr, l.reqKey, l.reqAddr, l.eventNo, l.reqKey.to_i - f.btwnID.to_i - 1] 
      end
    end

    bestLookupDist <= lookupDist.argmin([:myAddr, :reqKey, :reqAddr, :eventNo], :allDist) #l3
    
    forwardLookupT <= (identifier*bestLookupDist*finger).combos do |i, b, f|
      if b.minDist = (b.reqKey.to_i - f.btwnID.to_i - 1) and
            rangeOO(f.btwnID.to_i, i.myID.to_i, b.reqKey.to_i)
        puts "l3 forwardLookupT [#{i.myAddr}, #{b.reqKey}, #{b.reqAddr}, #{f.btwnAddr}, #{f.btwnID}] "
        [i.myAddr, b.reqKey, b.reqAddr, f.btwnAddr, b.eventNo, f.btwnID] 
      end
    end
    
    
    forwardLookup <= forwardLookupT.argmin([:myAddr, :reqKey, :reqAddr, :btwnAddr, :eventNo], :allBtwnID)
   
    lookupReq <~ forwardLookup do |f| 
      if f.btwnAddr != "NIL"
        puts "l4 lookupReq [#{f.btwnAddr}, #{f.reqKey}, #{f.reqAddr}] "
        [f.btwnAddr, f.reqKey, f.reqAddr, f.eventNo, "l4"] 
      end
    end
  end

  # Finger fixing
  bloom :fingerFixing do

    fFix <= (fingerFixPeriod*nextFingerFix).pairs do |f,n|
      puts "f1 fFix [#{n.myAddr}, #{n.entryNo}]"
      [n.myAddr, n.entryNo, rand(MAXNUM)]
    end

    fFixEvent <= (fingerFixPeriod*fFix).rights do |f|
      puts "f2 fFixEvent [#{f.myAddr}, #{f.index}]"
      [f.myAddr, f.index, f.eventNo]
    end

    # lookup with (2**i + myID) in nearest successor
    lookupReq <~ (fFixEvent*identifier).pairs do |f, i|
     kk = (0x1 << f.index.to_i) + i.myID.to_i
      [f.myAddr, kk, i.myAddr, f.eventNo, "f3"]
    end

    # add near successors into finger with f4 and f5
    eagerFinger <+- (fFix*lookupResults*eagerFinger).pairs do |f, l, e|
      if f.eventNo == l.eventNo and (e.btwnAddr == "NIL" || e.start.to_i == MAXFINGER)
        puts "f4 eagerFinger [#{f.myAddr}, #{f.index}, #{l.succID}, #{l.succAddr}]"
        [f.myAddr, f.index, l.succID, l.succAddr]
      end
    end

    finger <+- eagerFinger do |e|
      if e.btwnAddr != "NIL"
        puts "f5 finger [#{e.myAddr}, #{e.start}, #{e.btwnID}, #{e.btwnAddr}]"
        [e.myAddr, e.start, e.btwnID, e.btwnAddr]
      end
    end
    
    # add nodes with identy K:= (2**i + myID) in (myID, succID) into finger, 
    # where succID is the real node's ID (not virtual node)
    eagerFinger <+- (identifier*eagerFinger).pairs do |i, e|
      if e.start.to_i == MAXFINGER || e.btwnAddr == "NIL"
        puts "f6 eagerFinger do nothing"
      else
        ii = e.start.to_i + 1
        kk = (0x1 << ii) + i.myID.to_i
        if rangeOO(kk, i.myID.to_i, e.btwnID.to_i) and e.btwnAddr != i.myAddr
          puts "f6 eagerFinger [#{i.myAddr}, #{ii}, #{e.btwnID}, #{e.btwnAddr}]"
          [i.myAddr, ii, e.btwnID, e.btwnAddr]
        end
      end
    end

    fFix <- (fFix*eagerFinger).pairs do |f,e|
      if e.start.to_i > 0 and (f.index.to_i == e.start.to_i - 1)
        puts "f7 deleting fFix [#{f.myAddr}, #{f.index}]"
        [f.myAddr,f.index]
      end
    end

    fFixCount <= fFix.group([], count) do |g|
      puts "fFix count is #{g[0]}"
      [g[0]]
    end

    fFix <- (fFix*fFixCount).pairs do |x, f|
      if f.cnt == MAXFINGER
        x
      end
    end

    nextFingerFix <+- eagerFinger do |e|
      if e.start.to_i == MAXFINGER || e.myAddr == e.btwnAddr
        puts "f8 nextFingerFix [#{e.myAddr}, 0]"
        [e.myAddr, 0]
      end
    end
    
    nextFingerFix <+- (identifier*eagerFinger).pairs do |i, e|
      if e.btwnAddr != "NIL"
        ii = e.start.to_i + 1
        kk = (0x1 << ii) + i.myID.to_i
        if rangeOO(kk, e.btwnID.to_i, i.myID.to_i) and e.btwnAddr != i.myAddr
          puts "f9 nextFingerFix [#{i.myAddr}, #{ii}, #{e.btwnID}, #{e.btwnAddr}]"
          [i.myAddr, ii]
        end
      end
    end

    uniqueFinger <= finger do |f|
#      puts "f10 uniqueFinger [#{f.myAddr}, #{f.btwnAddr}]"
      [f.myAddr, f.btwnAddr, "f10 uniqueFinger"]
    end

    uniqueFingerC <= uniqueFinger.group([], count) do |g|
      puts "uniqueFinger count #{g[0]}"
    end
  end  # Finger fixing


  # neighbor selection
  bloom :neighbor do
    newSuccEvent <= successor { |s| [s.myAddr] } # n0
  
    newSuccEvent <= deleteSucc {|d| [s.myAddr]} #n2
    
    # bestSuccDist must be minimal distance between one node and its successors, and the
    # minimal distance should be minial positive one when all values of distance are 
    # positive, or one part is positive and another is negative, and else, minimal 
    # distance should be minimal negative one when all is negative. For instance, 
    # there are three nodes 100, 200 and 300, for node 100, its 
    # s.succID.to_i - i.myID.to_i - 1 are -1, 99 and 199, so BestSuccDist 
    # is 99 (node 200), for node 200, they are 99, -101, -1, so 99 (node 300) 
    # is BestSuccDist, for node 300, they are -201, -101, -1, so -1 (node 100) 
    # is BestSuccDist
    temp :succDistP  <= (identifier*successor*newSuccEvent).combos do |i, s, n|
      dd = s.succID.to_i - i.myID.to_i - 1
      if dd >= 0
        puts "n11 succDistP Plus [#{i.myAddr}, #{s.succID.to_i - i.myID.to_i - 1}]"
        [i.myAddr, dd]
      end
    end
    
    temp :succDistM  <= (identifier*successor*newSuccEvent).combos do |i, s, n|
      dd = s.succID.to_i - i.myID.to_i - 1
      if dd < 0
        puts "n12 succDistM Minus [#{i.myAddr}, #{s.succID.to_i - i.myID.to_i - 1}]"
        [i.myAddr, dd]
      end
    end
    
    succDist <= succDistP do |p|
      if !(succDistP.none?)
        puts "n13 succDist plus not empty"
        [p[0],p[1]]
      end
    end
    
    succDist <= succDistM do |m|
      if succDistP.none?
        puts "n14 succDist plus empty"
        [m[0],m[1]]
      end
    end

    bestSuccDist <= succDist.argmin([:myAddr], :allDist) #n1

    bestSucc <+- (successor*bestSuccDist*identifier).combos do |s, b, i|
      #puts "minDist #{b.minDist}  #{(s.succID.to_i - i.myID.to_i - 1)}"
      if b.minDist == (s.succID.to_i - i.myID.to_i - 1)
        puts "n3 bestSucc [#{i.myAddr}, #{s.succID}, #{s.succAddr}] "
        [i.myAddr, s.succID, s.succAddr] 
      end
    end
    
    finger <+- bestSucc do |b| 
      puts "n4 finger [#{b.myAddr}, 0, #{b.succID}, #{b.succAddr}]"
      [b.myAddr, 0, b.succID, b.succAddr]
    end
  end #neighbor selection

  # successor eviction
  bloom :succEvict do
    succCount <= (newSuccEvent*successor).rights.group([], count)  #s1
    
    evictSucc <= (succCount*identifier).pairs do |s,i|
      if s.cnt.to_i > SUCCESSORS
        puts "s2 evicSucc #{s.cnt} [#{i.myAddr}]"
        [i.myAddr]
      end
    end

    
    maxSuccDist <= (succDist*evictSucc).lefts.argmax([:myAddr], :allDist) # s3

    # delete node whose distance from one node is negative
    successor <- (succDistM*identifier*successor*evictSucc).combos do |sm, i, s, m|
      if !succDistP.none? and sm[1] == (s.succID.to_i - i.myID.to_i - 1)
        puts "s44 delete max successor [#{s.myAddr}, #{s.succID}, #{s.succAddr}]"
        s
      end
    end

    successor <- (identifier*successor*maxSuccDist).combos do |i, s, m|
      if (succDistP.none? || succDistM.none?) and
          m.maxDist == (s.succID.to_i - i.myID.to_i - 1)
        puts "s4 delete max successor [#{s.myAddr}, #{s.succID}, #{s.succAddr}]"
        s
      end
    end
  end # successor evict

  # stabilization
  bloom :stabilize do
    stabilizeEvent <= (identifier*stabPeriod).pairs { |i,s| [i.myAddr]} # sb0

    prec_ask <~ (stabilizeEvent*bestSucc).combos do |st,b| 
      [b.succAddr,ip_port, "bestSucc"] 
    end
    
    # 
    prec_ans <~ (prec_ask*precursor).pairs do |a,p| 
      [a.srcAddr,  p.precID, p.precAddr, p.myAddr, a.asker]  if 
        p.precAddr != "NIL" and a.asker == "bestSucc"
    end

    successor <= (prec_ans*bestSucc*identifier).combos do |p, b, i|
      if rangeOO(p.precID.to_i, i.myID.to_i, b.succID.to_i) and 
          p.ansAddr == b.succAddr and p.asker == "bestSucc"
        puts "sb1 successor #{Time.now.strftime("%I:%M:%S.%9N")} [#{b.myAddr}, #{p.precID}, #{p.precAddr}] "
        [b.myAddr, p.precID, p.precAddr] 
      end
    end

    succ_ask <~ (stabilizeEvent*successor).pairs {|st,s| 
      [s.succAddr,ip_port, "successor"] }
  
    succ_ans <~ (succ_ask*successor).pairs do |a,s| 
      [a.srcAddr, s.succID, s.succAddr, a.asker] if a.asker == "successor"
    end
    
    # 
    successor <= (successor*succ_ans).pairs do |s, sa|
      #puts "sb2: #{sa.asker}  #{sa.succID}  #{s.succID}"
      if sa.asker == "successor" #and sa.succID != s.succID
        puts "sb2 successor [#{s.myAddr}, #{sa.succID}, #{sa.succAddr}]"
        [s.myAddr, sa.succID, sa.succAddr]
      end
    end

    # succCOUNT <= successor.group(nil, count)
    prec_ask <~ (stabilizeEvent*successor).pairs {|st,s| 
      puts "prec_ask? #{s.myAddr} [#{s.succAddr},#{ip_port}, successor]  "
      [s.succAddr,ip_port, "successor"] }
   
    prec_ans <~ (prec_ask*precursor).pairs do |a,p| 
      [a.srcAddr,  p.precID, p.precAddr, p.myAddr, a.asker] if a.asker == "successor"
    end
    
    precSend <~ (prec_ans*successor*identifier).combos do |p,s,i|
      puts "sb31 precSend #{p.precAddr} #{s.succAddr} #{p.ansAddr}"
      if ((p.precAddr == "NIL") || 
          (rangeOO(i.myID.to_i, p.precID.to_i, s.succID.to_i))) and
          (i.myAddr != s.succAddr) and (s.succAddr == p.ansAddr)
        puts "sb32 precSend #{p.precAddr} #{s.succAddr} #{p.ansAddr}"
        [s.succAddr, i.myID, i.myAddr, "precSend"]
      end
    end
    
    precursor <+- precSend do |p| 
      puts "sb3 precursor #{Time.now.strftime("%I:%M:%S.%9N")} [#{p.dest}, #{p.precID} #{p.precAddr}]"
      [p.dest, p.precID, p.precAddr]
    end
  end # stabilization

  # monitor the channels
  bloom :monitor do
    stdio <~ joinReq {|m| ["joinReq received: #{m.inspect}"]}
    stdio <~ lookupReq {|m| ["lookupReq received: #{m.inspect}"]}
#    stdio <~ lookup1.inspected #{|m| ["lookup1 received: #{m.inspect}"]}
    
    stdio <~ lookupResults {|m| ["lookupResults received: #{m.inspect}"]}
    stdio <~ prec_ask {|m| ["prec_ask received: #{m.inspect}"]}
    stdio <~ prec_ans {|m| ["prec_ans received: #{m.inspect}"]}
    stdio <~ succ_ask {|m| ["succ_ask received: #{m.inspect}"]}
    stdio <~ succ_ans {|m| ["succ_ans received: #{m.inspect}"]}
    stdio <~ precSend {|m| ["PrecSend received: #{m.inspect}"]}
#    stdio <~ succCOUNT.inspected
    stdio <~ uniqueFinger.inspected

    joinTCount <= joinT.group([], count) do |g|
      puts "join count #{g[0]}"
    end



    fingerCount <= finger.group([], count) do |g|
      puts "fingerCount #{g[0]}"
    end
    nextFingerFixCount <= nextFingerFix.group([], count) do |g|
      puts "nextFingerFixCount #{g[0]}"
    end
  end # monitor the channels

end


myAddr = (ARGV.length == 3) ? ARGV[0] : "parameter input error"

ip,port = myAddr.split(":")
puts "Node address: #{ip}:#{port} "
stRing = ChordRing.new(ARGV[1], ARGV[2],:ip => ip, :port => port.to_i)
puts "ip: #{stRing.ip_port}"

stRing.run_fg

=begin
  # Ping Nodes
  bloom :pingNode do
    pendingPing <= (pingPeriod*successor).rights do |s|
      if s.myAddr != s.succAddr 
        rd = rand(MAXNUM)
        puts "pp1 pendingPing [#{s.myAddr}, #{s.succAddr}, #{rd}, #{Time.now.to_f}]"
        [s.myAddr, s.succAddr, rd, Time.now.to_f]
      end
    end

    pendingPing <= (pingPeriod*precursor).rights do |prec|
      if prec.myAddr != prec.precAddr and prec.precAddr != "NIL" 
        rd = rand(MAXNUM)
        puts "pp1 pendingPing [#{prec.myAddr}, #{prec.precAddr}, #{rd}, #{Time.now.to_f}]"
        [prec.myAddr, prec.precAddr, rd, Time.now.to_f]
      end
    end

    pendingPing <= (pingPeriod*uniqueFinger).rights do |u|
      if u.myAddr != u.btwnAddr
        rd = rand(MAXNUM)
        puts "pp1 pendingPing [#{u.myAddr}, #{u.btwnAddr}, #{rd}, #{Time.now.to_f}]"
        [u.myAddr, u.btwnAddr, rd, Time.now.to_f]
      end
    end
    
    pingReq <~ (pingPeriod*pendingPing).rights do |p| # pp5
#      puts "pp5 pingReq [#{p.linkAddr}, #{p.myAddr}, #{p.eventNo}]"
      [p.linkAddr, p.myAddr, p.eventNo]
    end

    pingResp <~ pingReq do |p| # pp4
      [p.srcAddr, p.dest, p.eventNo]
    end

    pendingPing <- (pingResp*pendingPing).pairs(:srcAddr => :linkAddr, :eventNo => :eventNo) do |pr,pp| 
      puts "pp6 pendPing [#{pp.myAddr}, #{pp.linkAddr}, #{pp.eventNo}, #{pp.timeStamp}]"
      [pp.myAddr, pp.linkAddr, pp.eventNo, pp.timeStamp]
    end
  end # ping nodes

  # Failure Detection
  bloom :failureDet do
    
    nodeFailure <= (failurePeroid*pendingPing).rights do |p|
      tt = Time.now.to_f
      dd = tt - p.timeStamp
      if dd > 7
        puts "cm1 nodeFailure [#{p.myAddr}, #{p.linkAddr}, #{p.eventNo}, #{dd}]"
        [p.myAddr, p.linkAddr, p.eventNo, dd]
      end
    end

    pendingPing <- (nodeFailure*pendingPing).pairs(:linkAddr => :linkAddr, :eventNo => :eventNo) do |n, pp| 
      puts "cm1a delete pendingPing [#{pp.myAddr}, #{pp.linkAddr}, #{pp.eventNo}, #{pp.timeStamp}]"
      [pp.myAddr, pp.linkAddr, pp.eventNo, pp.timeStamp]
    end

    deleteSucc <= (nodeFailure*successor).pairs(:linkAddr => :succAddr) do |n, s| 
      puts "cm2a deleteSucc [#{s.myAddr}, #{s.succID}, #{s.succAddr}]"
      [s.myAddr, s.succID, s.succAddr]
    end

    successor <- deleteSucc do |d|
      puts "cm2b delete successor [#{d.myAddr}, #{d.succID}, #{d.succAddr}]"
      [d.myAddr, d.succID, d.succAddr]
    end

    precursor <+- (nodeFailure*precursor).pairs(:linkAddr => :precAddr) do |n, p|
      puts "cm3 precursor [#{p.myAddr}, NIL, NIL]"
      [p.myAddr, "NIL", "NIL"]
    end

    finger <- (nodeFailure*finger).pairs(:linkAddr => :btwnAddr) do |n, f|
      puts "cm4 delete finger [#{f.myAddr}, #{f.start}, #{f.btwnID}, #{f.btwnAddr}]"
      [f.myAddr, f.start, f.btwnID, f.btwnAddr]
    end
    
    uniqueFinger <- (nodeFailure*uniqueFinger).pairs(:linkAddr => :btwnAddr) do |n, u|
      puts "cm6 delete uniqueFinger [#{u.myAddr}, #{u.btwnAddr}]"
      [u.myAddr, u.btwnAddr]
    end
  end # Failure Detection

=end
=begin

=end
