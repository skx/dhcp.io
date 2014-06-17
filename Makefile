#
#  Utility Makefile for working with the DHCP.io repository.
#



#
#  Reformat/pretty-print our perl source
#
tidy:
	perltidy $$(find . -iname '*.pm' -o -iname '*.t') bin/*


#
#  Generate minified CSS
#
css: htdocs/css/style.css htdocs/css/tabs.css
	cat htdocs/css/style.css htdocs/css/tabs.css > htdocs/css/s.css
	if ( test -e /usr/share/pyshared/slimmer/slimmer.py ); then python /usr/share/pyshared/slimmer/slimmer.py htdocs/css/s.css css --output=htdocs/css/s.css.min ; mv htdocs/css/s.css.min htdocs/css/s.css ; fi


#
#  Generate minified JS
#
js: htdocs/js/login.js htdocs/js/tabs.js
	cat htdocs/js/login.js htdocs/js/tabs.js > htdocs/js/j.js
	if ( test -e /usr/share/pyshared/slimmer/slimmer.py ); then python /usr/share/pyshared/slimmer/slimmer.py htdocs/js/j.js js --output=htdocs/js/j.js.min ; mv htdocs/js/j.js.min htdocs/js/j.js ; fi



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
	rm access.log error.log *.pyc htdocs/css/s.css htdocs/js/j.js || true


#
#  Launch the application on the local host - for test-purposes.
#
local:
	@which lighttpd >/dev/null 2>/dev/null || ( echo  "lighttpd doesn't seem to be installed" ; false )
	@echo "Launching lighttpd on http://localhost:2000/"
	lighttpd -f conf/lighttpd.conf -D


deploy:
	fab deploy
