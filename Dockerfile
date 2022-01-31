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
      default-jdk \
      dpkg-dev dpkg \
      g++ \
      gcc \
      git \
      imagemagick \
      iproute2 \
      iputils-ping \
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
      net-tools \
      ncurses-dev \
      openssl \
      patch \
      procps \
      ruby-full \
      software-properties-common \
      sqlite3 \
      sudo \
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
RUN echo 'relic ALL=(ALL) NOPASSWD:/usr/bin/apt' >> /etc/sudoers
RUN chown -R relic $APP_HOME

USER relic

# TODO: enable for multi-ruby testing
# # Ruby < 2.4 requires OpenSSL v1.0 - place it at ~/openssl1.0 to avoid conflicting with the system OpenSSL
# WORKDIR /tmp
# RUN wget -O openssl.tar.gz https://www.openssl.org/source/openssl-1.0.2l.tar.gz \
#     && tar xzf openssl.tar.gz \
#     && cd openssl* \
#     && ./config --prefix=/home/relic/openssl1.0 --openssldir=/home/relic/openssl1.0 shared zlib \
#     && make \
#     && make install \
#     && rm -rf ~/openssl1.0/certs/ \
#     && ln -s /etc/ssl/certs ~/openssl1.0/certs

ENV HOME /home/relic
ENV APP_HOME=/usr/src/app
ENV LANG=C.UTF-8

ENV PATH $HOME/.rbenv/shims:$HOME/.rbenv/bin:$HOME/.rbenv/plugins/ruby-build/bin:$PATH
ENV DEFAULT_RUBY=2.7.5

WORKDIR $APP_HOME

RUN git clone git://github.com/sstephenson/rbenv.git ~/.rbenv
RUN git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build

RUN echo 'colorscheme default' > ~/.vimrc
RUN echo 'gem: --no-document' > ~/.gemrc

# TODO: disable for multi-ruby testing
RUN $HOME/.rbenv/bin/rbenv install $DEFAULT_RUBY \
    && export RBENV_VERSION=$RUBY_VERSION \
    && $HOME/.rbenv/bin/rbenv global $DEFAULT_RUBY \
    && gem update --system \
    && gem update bundler \
    && bundle install \
    && gem install bundler:1.17.3

# TODO: re-enable for multi-ruby testing
# This script will install all CI supported Rubies (can take an hour to complete)
# RUN ruby test/script/ruby_installer.rb

CMD [ "bundle", "exec", "rake" ]
