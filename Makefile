#
#  Utility Makefile for working with the DHCP.io repository.
#



#
#  Reformat/pretty-print our perl source
#
tidy:
	perltidy $$(find . -name '*.pm')


#
#  Clean backup files.
#
clean:
	find . -name '*.bak' -delete


#
#  Launch the application on the local host - for test-purposes.
#
local:
	@which lighttpd >/dev/null 2>/dev/null || ( echo  "lighttpd doesn't seem to be installed" ; false )
	@echo "Launching lighttpd on http://localhost:2000/"
	lighttpd -f conf/lighttpd.conf -D


#
#  Deploy.
#
upload:
	rsync --exclude=logs/ --exclude=.git/ -vazr . s-dhcp@www.steve.org.uk:
