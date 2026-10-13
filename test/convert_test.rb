# frozen_string_literal: true
# SPDX-License-Identifier: AGPL-3.0-only

require 'open3'
require 'tmpdir'
require 'rbconfig'
require_relative '../lib/convert'

BIN = File.expand_path('../bin/convert', __dir__)

def assert(condition, message = 'Assertion failed')
  raise message unless condition
end

def check(name)
  yield
  puts "PASS #{name}"
end

def cli(*arguments, env: {})
  Open3.capture3(env, RbConfig.ruby, BIN, *arguments)
end

Dir.mktmpdir('empeira-convert-test') do |directory|
  input = File.join(directory, 'input.json')
  output = File.join(directory, 'output.yml')
  data = { 'server' => { 'host' => 'localhost', 'port' => 8080, 'enabled' => true, 'timeout' => 30.5 } }
  File.write(input, JSON.generate(data))

  check('JSON -> YAML') do
    stdout, stderr, status = cli('-i', input, '-o', output)
    assert(status.success?, stderr)
    assert(stdout.empty? && YAML.safe_load_file(output) == data)
  end

  check('XML -> JSON and XML output') do
    xml = '<settings mode="a&amp;b"><port>8080</port><host>a</host><host>b</host></settings>'
    parsed = Convert.read(xml, 'xml')
    expected = { 'settings' => { '@mode' => 'a&b', 'port' => '8080', 'host' => %w[a b] } }
    assert(JSON.parse(Convert.write(parsed, 'json')) == expected)
    assert(Convert.read(Convert.write(parsed, 'xml'), 'xml') == expected)
  end

  check('Hiera YAML -> XML and back') do
    hiera = { 'profile::server::port' => 8080, 'enabled' => true }
    yaml = File.join(directory, 'hiera.yaml')
    File.write(yaml, YAML.dump(hiera))
    stdout, stderr, status = cli('-i', yaml, '-t', 'XML')
    assert(status.success?, stderr)
    assert(Convert.read(stdout, 'xml') == { 'hiera' => hiera }, stdout)
    assert(stdout.include?('<hiera>'))
  end

  check('Properties -> YAML and Properties output') do
    source = "# comment\nhost=localhost\nport: 8080\nhello\\ world = a\\\n  b\nname=Gr\\u00fcße\n"
    parsed = Convert.read(source, 'properties')
    expected = { 'host' => 'localhost', 'port' => '8080', 'hello world' => 'ab', 'name' => 'Grüße' }
    assert(YAML.safe_load(Convert.write(parsed, 'yaml')) == expected)
    assert(Convert.read(Convert.write(parsed, 'properties'), 'properties') == expected)
  end

  check('YAML -> Puppet hash on stdout') do
    yaml = File.join(directory, 'settings.yaml')
    File.write(yaml, YAML.dump(data))
    stdout, stderr, status = cli('-i', yaml, '-t', 'puppet-hash')
    assert(status.success?, stderr)
    assert(PuppetHash.load(stdout) == data)
  end

  check('Puppet hash -> YAML') do
    puppet = "# data only\n{ 'name' => 'test', 'values' => [42, -2.5, true, undef,], }"
    expected = { 'name' => 'test', 'values' => [42, -2.5, true, nil] }
    assert(YAML.safe_load(Convert.write(Convert.read(puppet, 'puppet-hash'), 'yaml')) == expected)
    special = { 'text' => "quote '\" slash \\ dollar $x newline\n<% tag %>" }
    assert(PuppetHash.load(PuppetHash.dump(special)) == special)
  end

  check('Format detection, overrides and YAML default') do
    { '.yml' => 'yaml', '.yaml' => 'yaml', '.json' => 'json', '.xml' => 'xml',
      '.properties' => 'properties', '.pp' => 'puppet-hash' }.each do |extension, format|
      assert(Convert.format(extension) == format)
    end
    stdout, stderr, status = cli('-i', input)
    assert(status.success? && YAML.safe_load(stdout) == data, stderr)
    unknown = File.join(directory, 'data.txt')
    File.write(unknown, JSON.generate(data))
    stdout, stderr, status = cli('-i', unknown, '-f', 'json', '-o', output, '-t', 'json')
    assert(status.success? && stdout.empty? && JSON.parse(File.read(output)) == data, stderr)
    assert(File.executable?(BIN))
  end

  check('EPP types, defaults, nested values and escaping') do
    stdout, stderr, status = cli('template', '-i', input)
    assert(status.success?, stderr)
    ['String $server_host = "localhost"', 'Integer $server_port = 8080',
     'Boolean $server_enabled = true', 'Float $server_timeout = 30.5'].each do |declaration|
      assert(stdout.include?(declaration), declaration)
    end
    special = { 'text' => "quote '\" slash \\ dollar $x newline\n<% tag %>", 'a-b' => [1], 'a_b_0' => 2 }
    template = Convert.template(special, 'yaml')
    assert(template.include?('$a_b_0 = 1') && template.include?('$a_b_0_2 = 2'))
    assert(template.include?('\\u0025>') && template.include?('\\$x'))
    assert(Convert.template({ 'x' => nil }, 'yaml') == YAML.dump('x' => nil))
    assert(template.include?('"<%= $text %>"'))
    assert(!template.include?('regsubst('))
    assert(Convert.template({ 'glob' => '%{facts.os.name}' }, 'yaml').include?('"%{facts.os.name}"'))

    puppet = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |path| File.join(path, 'puppet') }.find { |path| File.executable?(path) && File.file?(path) }
    if puppet
      %w[yaml json xml properties puppet-hash].each do |format|
        original = format == 'xml' ? { 'root' => special } : special.reject { |_, v| v.is_a?(Array) }
        file = File.join(directory, "#{format}.epp")
        File.write(file, Convert.template(original, format))
        _, errors, valid = Open3.capture3(puppet, 'epp', 'validate', file)
        assert(valid.success?, errors)
        rendered, errors, valid = Open3.capture3(puppet, 'epp', 'render', file)
        assert(valid.success?, errors)
        expected = Convert.read(Convert.write(original, format), format)
        assert(Convert.read(rendered, format) == expected, "EPP round trip: #{format}")
      end
    else
      puts 'SKIP Puppet/OpenVox EPP validation and rendering: puppet is not installed'
    end
  end

  check('Basic errors and missing dependency') do
    [[], ['-i', 'missing.json'], ['-i', input, '-t', 'unknown'], ['template', '-i', input, '-t', 'json']].each do |args|
      stdout, stderr, status = cli(*args)
      assert(!status.success? && stdout.empty? && stderr.start_with?('Error:'))
    end
    { 'json' => '{bad', 'yaml' => 'x: !ruby/object:Object {}',
      'puppet-hash' => '{ "x" => system("touch bad") }', 'xml' => '<!DOCTYPE x><x/>' }.each do |format, source|
      begin
        Convert.read(source, format)
        raise "Accepted invalid #{format}"
      rescue ArgumentError
        # Expected: data must never be evaluated as code.
      end
    end
    xml = File.join(directory, 'input.xml')
    File.write(xml, '<settings/>')
    # Simulate a distribution omitting REXML, without changing installed gems.
    stub = File.join(directory, 'missing_rexml.rb')
    File.write(stub, <<~RUBY)
      module Kernel
        alias original_require require
        def require(path)
          if path == 'rexml/document'
            error = LoadError.new('missing rexml')
            def error.path = 'rexml/document'
            raise error
          end
          original_require(path)
        end
      end
    RUBY
    stdout, stderr, status = cli('-i', xml, env: { 'RUBYOPT' => "-r#{stub}" })
    assert(!status.success? && stdout.empty? && stderr.include?("Missing Ruby dependency: rexml\nInstall it using:\n  gem install rexml"), stderr)
  end
end
