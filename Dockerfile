FROM docker:latest as runtime
LABEL "repository"="https://github.com/sharpninja/Publish-Docker-Github-Action"
LABEL "maintainer"="Sharp Ninja (original by Lars Gohr)"

RUN apk update \
  && apk upgrade \
  && apk add --no-cache git

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# FROM runtime as testEnv
# RUN apk add --no-cache coreutils bats
# ADD test.bats /test.bats
# ADD mock.sh /usr/local/bin/docker
# ADD mock.sh /usr/bin/date
# RUN /test.bats

# FROM runtime
