all: bits

bits:
	echo "run bits\nexit" | xps -nw system.xmp
	echo -e '\a'

clean:
	echo "run clean\nexit" | xps -nw system.xmp
	rm -f *.log
	rm -f system.log.bak platgen.opt system_incl.make system.make XpsGuiSessionLock
	rm -f etc/bitgen.ut
	rm -rf blockdiagram __xps

