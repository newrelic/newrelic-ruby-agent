FROM rubydata/minimal-notebook

USER root
RUN mkdir -p /charty && chown root:users /charty

WORKDIR /charty


RUN gem install charty
RUN gem install matplotlib


COPY create_graphs.rb /charty/create_graphs.rb
COPY ./inputs/ /charty/inputs

RUN chown -R root:root /charty



ENTRYPOINT ["ruby", "/charty/create_graphs.rb"]
