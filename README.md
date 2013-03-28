bloom-chord
===========

This Chord is implemented based on [BUD][bud], paper [Chord][chord]
and [P2][p2]'s [example Chord][example-chord] are main
references. 

How to run bloom-chord
-----------------------------------
	./runchord.sh
	ruby test_chord.rb 127.0.0.1:88888 127.0.0.1:1111

The first command will run 8 instances with different ports
and generate 8 log files about communitating message to each other , 
the second will test the Chord ring with different ID, of
course you can delete any one statnce to test ring's
integrity.



[bud]: http://www.bloom-lang.net/bud/
[chord]:
http://pdos.csail.mit.edu/papers/chord:sigcomm01/chord_sigcomm.pdf
[chord]: http://pdos.csail.mit.edu/papers/chord:sigcomm01/chord_sigcomm.pdf
[example-chord]: http://p2.berkeley.intel-research.net/downloads/p2-0.8.tar.gz
