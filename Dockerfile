# -----------------------------------------------------------------------------
# docker-minecraft
#
# Builds a basic docker image that can run a Minecraft server
# (http://minecraft.net/).
# -----------------------------------------------------------------------------

# Base image is the latest LTS version of Ubuntu
FROM   ubuntu:22.04

# Make sure we don't get notifications we can't answer during building.
ENV DEBIAN_FRONTEND noninteractive

ENV DISCORD_TOKEN ''
ENV MINECRAFT_CHANNEL ''
ENV CLIENT_ID ''

# Download and install everything from the repos.
RUN apt-get -y update && \
    apt-get -y upgrade; apt-get -y install software-properties-common curl ruby-full build-essential wget unzip openjdk-8-jre-headless && \
    gem install bundler && \
    apt-get clean

# Install deps
ADD    ./scripts/Gemfile /Gemfile
ADD    ./scripts/Gemfile.lock /Gemfile.lock

RUN    gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)" && bundle install -j4

# Load in all of our config files.
ADD    ./scripts/start /start
ADD    ./scripts/main.rb /main.rb
ADD    ./scripts/emodata.json /emodata.json

# Fix all permissions
RUN    chmod +x /start

# 25565 is for minecraft
EXPOSE 25565

# 25001 for kontrol panel
EXPOSE 25001

# /data contains static files and database
VOLUME ["/data"]

ADD    ./scripts/server.properties /data/server.properties

ENV MOTD "Ruby's OceanBlock Server"
ENV LEVEL default
ENV JVM_OPTS "-Xms4096m -Xmx6144m"

# /start runs it.
CMD    ["bundle", "exec", "ruby", "main.rb"]
