#!/usr/bin/env python

from __future__ import with_statement

import os
import sys
import subprocess
import time

try:
    from fabric.api import *
    from fabric.contrib.console import confirm
except ImportError:
    print ("""The 'fabric' package is currently not installed. You can install it by typing:\n
sudo apt-get install fabric
""")
    sys.exit()



#
#  Username and hostname to ssh to.
#
env.hosts = ['www.steve.org.uk:2222']
env.user = 's-dhcp'





def test():
    """
    Run the test suite, against the local system.
    """
    with settings(warn_only=True):
        result = local('make test', capture=True)
    if result.failed and not confirm("Tests failed. Continue anyway?"):
        abort("Aborting at user request.")



def test_remote():
    """
    Run the test suite against the remote installation.
    """

    with cd("~/current/"):
        run( "make test")




def deploy():
    """
    Deploy the application, after running the test suite successfully.
    """

    #
    #  Run the test suite.
    #
    #test()

    #
    #  Setup our release identifier.
    #
    env.release = time.strftime('%Y%m%d%H%M%S')


    #
    #  Create a tar-file and upload it
    #
    local('git archive --format=tar master | gzip > %(release)s.tar.gz' % env)
    run( "mkdir ~/releases/ || true")
    put('%(release)s.tar.gz' % env, '~/releases/' % env)

    #
    #  Remove the local copy.
    #
    local('rm %(release)s.tar.gz' % env)

    #
    #  Untar the remote version
    #
    run( "mkdir ~/releases/%(release)s && cd ~/releases/%(release)s && tar zxf ../%(release)s.tar.gz" % env )

    #
    #  Now symlink in the current release
    #
    run( "rm -f ~/current || true " )
    run( "ln -s ~/releases/%(release)s ~/current" % env )

    #
    #  Install the local Config.pm file.
    #
    if os.path.isfile("lib/DHCP/Config.pm"):
        put( "lib/DHCP/Config.pm", "~/current/lib/DHCP" )


    #
    #  Upload our CSS files.  These should be minified if pyslimmer is
    # installed.
    #
    local( "make css" )
    put( "htdocs/css/s.css", "~/current/htdocs/css/s.css" )

    local( "make js" )
    put( "htdocs/js/j.js", "~/current/htdocs/js/j.js" )

    #
    #  And restart
    #
    run( "kill -9 $(cat lighttpd.pid)" )







#
#  This is our entry point.
#
if __name__ == '__main__':

    if len(sys.argv) > 1:
        #
        #  If we got an argument then invoke fabric with it.
        #
        subprocess.call(['fab', '-f', __file__] + sys.argv[1:])
    else:
        #
        #  Otherwise list our targets.
        #
        subprocess.call(['fab', '-f', __file__, '--list'])

