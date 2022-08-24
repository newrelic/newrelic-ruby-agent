FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ Etc/UTC 

RUN apt-get update && apt-get install -y ca-certificates libc6-dev git curl autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev default-jre tzdata --no-install-recommends && rm -rf /var/lib/apt/lists/*

ENV JRUBY_VERSION 9.3.7.0
ENV JRUBY_SHA256 94a7a8b3beeac2253a8876e73adfac6bececb2b54d2ddfa68f245dc81967d0c1
RUN mkdir /opt/jruby \
  && curl -fSL https://repo1.maven.org/maven2/org/jruby/jruby-dist/${JRUBY_VERSION}/jruby-dist-${JRUBY_VERSION}-bin.tar.gz -o /tmp/jruby.tar.gz \
  && echo "$JRUBY_SHA256 /tmp/jruby.tar.gz" | sha256sum -c - \
  && tar -zx --strip-components=1 -f /tmp/jruby.tar.gz -C /opt/jruby \
  && rm /tmp/jruby.tar.gz \
  && update-alternatives --install /usr/local/bin/ruby ruby /opt/jruby/bin/jruby 1

ENV PATH /opt/jruby/bin:$PATH
ENV SERIALIZE 1

RUN mkdir -p /opt/jruby/etc \
	&& { \
		echo 'install: --no-document'; \
		echo 'update: --no-document'; \
	} >> /opt/jruby/etc/gemrc

CMD ["irb"]
