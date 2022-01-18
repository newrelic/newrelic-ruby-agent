FROM ubuntu:20.04

RUN apt-get update \
      && desired_packages=' \
      autoconf \
      bison \
      build-essential \
      bzip2 \
      ca-certificates \
      coreutils \
      curl \
      dpkg-dev dpkg \
      g++ \
      gcc \
      git \
      imagemagick \
      libc6 \
      libc6-dev \
      libcurl4-openssl-dev \
      libdb-dev \
      libffi-dev \
      libgdbm6 \
      libgdbm-dev \
      libmemcached-tools \
      libmysqlclient-dev \
      libncurses5-dev \
      libreadline6-dev \
      libsasl2-dev \
      libsqlite3-dev \
      libssl-dev \
      libxml2-dev \
      libxslt-dev \
      libyaml-dev \
      lsof \
      make \
      openssl \
      ncurses-dev \
      openssl \
      patch \
      procps \
      rbenv \
      ruby-full \
      software-properties-common \
      sqlite3 \
      tar \
      telnet \
      vim \
      wget \
      zlib1g-dev \
      ' \
      && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $desired_packages

ENV APP_HOME=/usr/src/app
COPY . $APP_HOME

RUN adduser --gecos '' --disabled-password relic
RUN chown -R relic $APP_HOME

USER relic

ENV HOME /home/relic
ENV APP_HOME=/usr/src/app
ENV PATH $HOME/.rbenv/shims:$HOME/.rbenv/bin:$HOME/.rbenv/plugins/ruby-build/bin:$PATH
ENV RUBY_VERSION=2.7.5
ENV LANG=C.UTF-8

WORKDIR $APP_HOME
RUN test -e .ruby-version || echo $RUBY_VERSION > .ruby-version

RUN git clone git://github.com/sstephenson/rbenv.git ~/.rbenv
RUN git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build

RUN echo 'gem: --no-document' > ~/.gemrc

RUN rbenv install
RUN gem update --system
RUN gem update bundler
RUN bundle install

CMD [ "bundle", "exec", "rake" ]
