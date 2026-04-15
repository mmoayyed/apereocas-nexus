#!/usr/bin/env bash

heroku login
heroku stack:set container -a apereocas-nexus
heroku container:login
heroku container:push web -a apereocas-nexus
heroku container:release web -a apereocas-nexus