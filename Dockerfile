##
## Dockerfile
##
## Application deployed beneath /srv
##
## Database at /srv/db.db
##
## Config at /srv/lib/conf/Config.pm
##
##
## Build:
##
##    docker build -t dhcp.io:1 .
##
## Launch:
##
##    docker-compose -d up
##
##

# Base image
FROM debian:buster

# Install dependencies
RUN apt-get update --quiet

# Perl/Other dependencies
RUN apt-get install --yes make libhtml-template-perl libcgi-application-perl libtie-ixhash-perl libdata-uuid-libuuid-perl libdbi-perl libdbd-sqlite3-perl libhtml-template-perl libjson-perl libredis-perl perl-modules lighttpd libcgi-session-perl libnet-dns-perl libxml-simple-perl libwww-perl libcrypt-blowfish-perl libcrypt-eksblowfish-perl libtest-pod-perl libtest-strict-perl libtest-www-mechanize-cgiapp-perl libnet-smtp-ssl-perl

# Ensure /root is writable for the tests
RUN chmod -R 777 /root

# Create a working directory
WORKDIR /srv

# Copy the source into it
COPY . .

# Build the templates
RUN perl ./bin/generate-templates

# Expose the port
EXPOSE 2000

# Start our server, after fixing permissions.
CMD [ "/srv/bin/docker-start" ]
