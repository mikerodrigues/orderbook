require 'rake/testtask'
require 'bundler'
require_relative './lib/orderbook/version.rb'

task :build do
  begin
    puts 'building gem...'
    `gem build orderbook.gemspec`
  rescue
    puts 'build failed.'
  end
end

task :install do
  begin
    puts 'installing gem...'
    `gem install --local orderbook`
  rescue
    puts 'install failed.'
  end
end

task :console do
  require 'rubygems'
  require 'pry'
  ARGV.clear
  PRY.start
end

task default: %w(build install)

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/tc*.rb']
  t.verbose = true
end
