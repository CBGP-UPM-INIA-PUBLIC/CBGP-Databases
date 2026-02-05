FROM ruby:3.2.4

# Set environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:UTF-8 \
    LC_ALL=C.UTF-8

RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv
# Install system dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    nano \
    libxml++2.6-dev \
    libraptor2-0 \
    libxslt1-dev \
    locales \
    software-properties-common \
    cron && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install specific Bundler version and set up application directory
RUN gem update --system --silent && \
    gem install bundler:2.6.4 --no-document && \
    mkdir -p /server

WORKDIR /server

# Copy Gemfile, Gemfile.lock, and .gemspec to support gemspec directive
COPY Gemfile Gemfile.lock* *.gemspec /server/
RUN bundle config set --local without 'development test' && \
    bundle install --jobs=4 --retry=3

# Copy the rest of the application
COPY . /server

# Set entrypoint
ENTRYPOINT ["sh", "/server/entrypoint.sh"]
