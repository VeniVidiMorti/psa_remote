#!/bin/sh
# Called by the desktop for mymacsdk:// links with the port and the link as arguments.
# Passes the query of the OAuth redirect (code, scope, state) on to the local server.
exec xdg-open "http://localhost:$1/callback?${2#*\?}"
