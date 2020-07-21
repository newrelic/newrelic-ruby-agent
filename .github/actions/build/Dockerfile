FROM ubuntu:14.04

ENV DEBIAN_FRONTEND=noninteractive

RUN ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && \
  apt-get update && \
  apt-get install --no-install-recommends -y \
    build-essential \
    tzdata \
    curl \
    wget \
    openssl \
    zlib1g-dev \
    libpq-dev \
    git-core \
    libxml2-dev \
    libc6-dev 

RUN apt-get install --no-install-recommends -y \
    mysql-server \
    redis-server \
    rabbitmq-server \
    memcached 

RUN service rabbitmq-server start

RUN wget http://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p648.tar.gz && \
    tar xvfz ruby-2.0.0-p648.tar.gz && \
    cd ruby-2.0.0-p648 && \
    ./configure --disable-install-rdoc && make && make install

RUN gem install bundler -v 1.17.3 --no-document
RUN bundle install
