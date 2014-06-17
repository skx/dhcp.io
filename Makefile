#
#  Utility Makefile for working with the DHCP.io repository.
#



#
#  Reformat/pretty-print our perl source
#
tidy:
	perltidy $$(find . -iname '*.pm' -o -iname '*.t') bin/*


#
#  Generate concatenates CSS
#
css: htdocs/css/style.css htdocs/css/tabs.css
	cat htdocs/css/style.css htdocs/css/tabs.css > htdocs/css/s.css
	if ( test -e /usr/share/pyshared/slimmer/slimmer.py ); then python /usr/share/pyshared/slimmer/slimmer.py htdocs/css/s.css css --output=htdocs/css/s.css.min ; mv htdocs/css/s.css.min htdocs/css/s.css ; fi


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
	rm access.log error.log *.pyc htdocs/css/s.css || true

#
#  Launch the application on the local host - for test-purposes.
#
local:
	@which lighttpd >/dev/null 2>/dev/null || ( echo  "lighttpd doesn't seem to be installed" ; false )
	@echo "Launching lighttpd on http://localhost:2000/"
	lighttpd -f conf/lighttpd.conf -D
