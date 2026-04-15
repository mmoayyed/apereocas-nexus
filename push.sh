#!/bin/sh
set -eu

heroku container:push web -a apereocas-nexus
heroku container:release web -a apereocas-nexus
heroku logs --tail -a apereocas-nexus