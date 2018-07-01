#!/usr/bin/env ruby

if ARGV.include?("-h") || ARGV.include?("--help")
  puts "USAGE: check.rb [HOSTNAME] [TLS_VERSION] [VERIFY]"
  puts "  default: check.rb rubygems.org auto VERIFY_PEER"
  puts "  example: check.rb github.com TLSv1_2 VERIFY_NONE"
  exit 0
end

host = ARGV.shift || "rubygems.org"

require 'uri'
require 'net/http'

begin
  require 'openssl'
rescue LoadError
  abort "Oh no! Your Ruby doesn't have OpenSSL, so it can't connect to #{host}. " \
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

uri = URI("https://#{host}")
ssl_version = ARGV.shift
verify_mode = ARGV.any? ? OpenSSL::SSL.const_get(ARGV.shift) : OpenSSL::SSL::VERIFY_PEER

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
puts "With that out of the way, let's see if you can connect to #{host}..."
puts

def error_reason(error)
  case error.message
  when /certificate verify failed/
    "certificate verification"
  when /read server hello A/
    "SSL/TLS protocol version mismatch"
  when /tlsv1 alert protocol version/
    "requested TLS version is too old"
  else
    error.message
  end
end

begin
  Bundler::Fetcher.new(Bundler::Source::Rubygems::Remote.new(uri)).send(:connection).request(uri)
  bundler_status = "success ✅"
rescue => error
  bundler_status = "failed  ❌  (#{error_reason(error)})"
end
puts "Bundler connection to #{host}:       #{bundler_status}"

begin
  require 'rubygems/remote_fetcher'
  Gem::RemoteFetcher.fetcher.fetch_path(uri)
  rubygems_status = "success ✅"
rescue => error
  rubygems_status = "failed  ❌  (#{error_reason(error)})"
end
puts "RubyGems connection to #{host}:      #{rubygems_status}"

begin
  # Try to connect using HTTPS
  Net::HTTP.new(uri.host, uri.port).tap do |http|
    http.use_ssl = true
    http.ssl_version = ssl_version.to_sym if ssl_version
    http.verify_mode = verify_mode
  end.start

  puts "Ruby net/http connection to #{host}: success ✅"
  puts
rescue => error
  puts "Ruby net/http connection to #{host}: failed  ❌"
  puts
  puts "Unfortunately, this Ruby can't connect to #{host}. 😡"

  case error.message
  # Check for certificate errors
  when /certificate verify failed/
    abort "Your Ruby can't connect to #{host} because you are missing the certificate " \
      "files OpenSSL needs to verify you are connecting to the genuine #{host} servers."
  # Check for TLS version errors
  when /read server hello A/, /tlsv1 alert protocol version/
    abort "Your Ruby can't connect to #{host} because your version of OpenSSL is too old. " \
      "You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL."
  else
    puts "Even worse, we're not sure why. 😕"
    puts
    puts "Here's the full error information:"
    puts "#{error.class}: #{error.message}"
    puts "  " << error.backtrace.join("\n  ")
    puts
    puts "You might have more luck using Mislav's SSL doctor.rb script. You can get it here:"
    puts "https://github.com/mislav/ssl-tools/blob/8b3dec4/doctor.rb"
    puts "Read more about the script and how to use it in this blog post:"
    puts "https://mislav.net/2013/07/ruby-openssl/"
    abort
  end
end

guide_url = "http://ruby.to/ssl-check-failed"
if bundler_status =~ /success/ && rubygems_status =~ /success/
  # Whoa, it seems like it's working!
  puts "Hooray! This Ruby can connect to #{host}. You are all set to use Bundler and RubyGems. 👌"
elsif rubygems_status !~ /success/
  puts "It looks like Ruby and Bundler can connect to #{host}, but RubyGems itself cannot. You can likely solve this by manually downloading and installing a RubyGems update. Visit #{guide_url} for instructions on how to manually upgrade RubyGems. 💎"
elsif bundler_status !~ /success/
  puts "Although your Ruby installation and RubyGems can both connect to #{host}, Bundler is having trouble. The most likely way to fix this is to upgrade Bundler by running `gem install bundler`. Run this script again after doing that to make sure everything is all set. If you're still having trouble, check out the troubleshooting guide at #{guide_url} 📦"
else
  puts "For some reason, your Ruby installation can connect to #{host}, but neither RubyGems nor Bundler can. The most likely fix is to manually upgrade RubyGems by following the instructions at #{guide_url}. After you've done that, run `gem install bundler` to upgrade Bundler, and then run this script again to make sure everything worked. ❣️"
end

# We were able to connect, but perhaps this Ruby will have trouble when we require TLSv1.2
unless OpenSSL::SSL::SSLContext::METHODS.include?(:TLSv1_2)
  puts
  puts "WARNING: Although your Ruby can connect to #{host} today, your OpenSSL is very old! 👴"
  puts "WARNING: You will need to upgrade OpenSSL before January 2018 in order to keep using #{host}."
  abort
end

exit 0
