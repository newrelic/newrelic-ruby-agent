FROM ubuntu:20.04

# Install packages with apt for building CRubies, running JRuby, for performing
# all Rails environment and multiverse tests, and for using Docker as a
# development environment
RUN apt-get update \
      && desired_packages=' \
      autoconf \
      bison \
      build-essential \
      bzip2 \
      ca-certificates \
      cmake \
      coreutils \
      curl \
      default-jdk \
      dpkg \
      dpkg-dev \
      g++ \
      gcc \
      git \
      gnupg \
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
      pkg-config \
      procps \
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

# Set env vars, mostly for Ruby's sake
ENV LANG=C.UTF-8
ENV CPPFLAGS='-DENABLE_PATH_CHECK=0'
ENV BUNDLE_RETRY=1
ENV BUNDLE_JOBS=4
ENV JRUBY_OPTS=--dev
ENV SERIALIZE=1
ENV BLOCK_PATH=/usr/local/antonius-block

###
### BEGIN Ruby 2.2 and 2.3 hacks
###
###       Older software packages are installed where older Rubies can leverage
###       them when asked to, but newer Rubies won't discover them.
###

RUN mkdir $BLOCK_PATH

# Install OpenSSL v1.0 from source
RUN wget -O openssl.tar.gz https://www.openssl.org/source/openssl-1.0.2l.tar.gz \
    && tar xzf openssl.tar.gz \
    && cd openssl* \
    && ./config --prefix=$BLOCK_PATH/openssl1.0 --openssldir=$BLOCK_PATH/openssl1.0 shared zlib \
    && make \
    && make install \
    && cd .. \
    && rm -rf openssl* \
    && rm -rf $BLOCK_PATH/openssl1.0/certs/ \
    && ln -s /etc/ssl/certs $BLOCK_PATH/openssl1.0/certs

# Install MySQL 5.5 from source (it ships bundled with OpenSSL 1.0)
RUN wget https://github.com/mysql/mysql-server/archive/refs/tags/mysql-5.5.63.tar.gz \
    && tar xzf mysql-5.5.63.tar.gz \
    && cd mysql-server-mysql-5.5.63/ \
    && cmake . -DCMAKE_INSTALL_PREFIX=$BLOCK_PATH/mysql5.5 \
    -DMYSQL_DATADIR=$BLOCK_PATH/mysql5.5/data \
    -DDOWNLOAD_BOOST=1 \
    -DWITH_BOOST=/tmp/boost \
    -DWITH_SSL=bundled \
    && make \
    && make install \
    && cd .. \
    && rm -rf mysql*

# Install Curl 7 from source
RUN wget https://github.com/curl/curl/releases/download/curl-7_81_0/curl-7.81.0.tar.bz2 \
    && tar xjf curl-7.81.0.tar.bz2 \
    && cd curl-7.81.0 \
    && env PKG_CONFIG_PATH=$BLOCK_PATH/openssl1.0/lib/pkgconfig ./configure --prefix=$BLOCK_PATH/curl7_openssl1.0 --with-openssl \
    && make \
    && make install \
    && cd .. \
    && rm -rf curl*

###
### END Ruby 2.2 and 2.3 hacks
###

# Helper scripts and just enough shared content needed to know which rubies to install
RUN mkdir -p $HOME/.docker/lib
COPY .docker/bin /root/.docker/bin
COPY ./test/helpers/ruby_rails_mappings.rb /root/.docker/lib/
COPY .github/workflows/ci.yml /root/.docker/lib/

# Grab ruby-build
RUN mkdir -p ruby-build \
    && wget -O ruby-build.tar.gz https://github.com/rbenv/ruby-build/archive/refs/tags/v20220125.tar.gz \
    && tar xzf ruby-build.tar.gz -C ruby-build --strip-components=1 \
    && cd ruby-build \
    && ./install.sh \
    && cd .. \
    && rm -rf ruby-build*

# Create a set_ruby shell function for setting the current version to use
RUN echo '\
\n\
function set_ruby() {\n\
  local version="$1"\n\
  if [ "$version" == "" ]; then\n\
    echo "Usage: set_ruby <RUBY VERSION>"\n\
  elif ! [[ $version = jruby* ]]; then\n\
    version="ruby-$version"\n\
  fi\n\
  export PATH="$HOME/.rubies/$version/bin:$PATH"\n\
  unset version\n\
}\n\
alias setruby=set_ruby \
' >> /root/.bashrc

# Install all CI tested Rubies
# NOTE: to install just one Ruby, pass that Ruby's version:
#       example: ruby_installer.rb 3.1.0
RUN $HOME/.docker/bin/ruby_installer.rb

RUN mv $HOME/.docker/bin/test* /usr/local/bin && rm -rf $HOME/.docker

# Leave the work dir set to the volume mount that Docker Compose will use
WORKDIR /app

# Use bash for debugging the build process - expect Doker Compose otherwise
CMD [ "bash" ]
