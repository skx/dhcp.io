#
#  Utility Makefile for working with the DHCP.io repository.
#



#
#  Reformat/pretty-print our perl source
#
tidy:
	perltidy $$(find . -iname '*.pm' -o -iname '*.t') bin/*


#
#  Run the test-suite
#
test:
	prove --shuffle t/*


#
#  Clean backup files.
#
clean:
	find . -name '*.bak' -delete
	rm access.log error.log *.pyc || true

#
#  Launch the application on the local host - for test-purposes.
#
local:
	@which lighttpd >/dev/null 2>/dev/null || ( echo  "lighttpd doesn't seem to be installed" ; false )
	@echo "Launching lighttpd on http://localhost:2000/"
	lighttpd -f conf/lighttpd.conf -D
