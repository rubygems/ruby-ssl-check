require 'uri'
require 'net/http'

begin
  require 'openssl'
rescue LoadError
  abort "Oh no! Your Ruby doesn't have OpenSSL, so it can't connect to rubygems.org. " \
    "You'll need to recompile or reinstall Ruby with OpenSSL support and try again."
end

begin
  # Some versions of Ruby need this require to do HTTPS
  require 'net/https'
  # Try for RubyGems version
  require 'rubygems'
  # Try for Bundler version
  require 'bundler'
rescue LoadError
end

ruby_version = RUBY_VERSION.dup
ruby_version << "p#{RUBY_PATCHLEVEL}" if defined?(RUBY_PATCHLEVEL)
ruby_version << " (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION})"
ruby_version << " [#{RUBY_PLATFORM}]"

puts "Here's your Ruby and OpenSSL environment:"
puts
puts "Ruby:           %s" % ruby_version
puts "RubyGems:       %s" % Gem::VERSION if defined?(Gem::VERSION)
puts "Bundler:        %s" % Bundler::VERSION if defined?(Bundler::VERSION)
puts "Compiled with:  %s" % OpenSSL::OPENSSL_VERSION
puts "Loaded version: %s" % OpenSSL::OPENSSL_LIBRARY_VERSION
puts "SSL_CERT_FILE:  %s" % OpenSSL::X509::DEFAULT_CERT_FILE
puts "SSL_CERT_DIR:   %s" % OpenSSL::X509::DEFAULT_CERT_DIR
puts
puts "With that out of the way, let's see if you can connect to rubygems.org..."
puts

# Check for a successful connection
begin
  uri = URI("https://rubygems.org")

  # TODO RM
  uri = URI("https://localhost")

  Net::HTTP.new(uri.host, uri.port).tap do |http|
    http.use_ssl = true

    # TODO RM simulation of future TLS deprecation
    http.ssl_version = :TLSv1
    # TODO RM simulation of certificate being valid
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  end.start
rescue => error
  puts "Unfortunately, this Ruby can't connect to rubygems.org. 😡"

  case error.message
  # Check for certificate errors
  when /certificate verify failed/
    abort "Your Ruby can't connect to rubygems.org because you are missing the certificate " \
      "files OpenSSL needs to verify you are connecting to the genuine rubygems.org servers."
  # Check for TLS version errors
  when /read server hello A/
    abort "Your Ruby can't connect to rubygems.org because your version of OpenSSL is too old. " \
      "You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL."
  end
end

# We were able to connect, but perhaps this Ruby will have trouble when we require TLSv1.2
unless OpenSSL::SSL::SSLContext::METHODS.include?(:TLSv1_2)
  abort "Although your Ruby can connect to rubygems.org today, you need to upgrade OpenSSL to " \
    "continue using rubygems.org after January 2018."
end

# Whoa, it seems like it's working!
puts "Hooray! This Ruby can connect to rubygems.org. You are all set to use Bundler and RubyGems. 👌"
exit 0
