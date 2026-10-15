# frozen_string_literal: true
# SPDX-License-Identifier: AGPL-3.0-only

require 'json'
require 'yaml'
require_relative 'puppet_hash'

module Convert
  module_function

  def format(name)
    aliases = { 'yml' => 'yaml', 'pp' => 'puppet-hash' }
    name = name.downcase.delete_prefix('.')
    name = aliases.fetch(name, name)
    return name if %w[yaml json xml properties puppet-hash].include?(name)

    raise ArgumentError, "Unknown format #{name.inspect}; use yaml, json, xml, properties or puppet-hash"
  end

  def read(source, format)
    require 'rexml/document' if format == 'xml'
    if format == 'yaml' && Psych.parse_stream(source).children.size > 1
      raise ArgumentError, 'Expected one YAML document'
    end
    data = case format
           when 'yaml' then YAML.safe_load(source, aliases: false)
           when 'json' then JSON.parse(source)
           when 'xml' then read_xml(source)
           when 'properties' then read_properties(source)
           when 'puppet-hash' then PuppetHash.load(source)
           end
    validate(data)
    data
  rescue Psych::Exception, JSON::ParserError => e
    raise ArgumentError, "Invalid #{format}: #{e.message}"
  end

  def validate(data)
    case data
    when Hash
      raise ArgumentError, 'Mapping keys must be strings' unless data.keys.all?(String)

      data.each_value { |value| validate(value) }
    when Array then data.each { |value| validate(value) }
    when Float
      raise ArgumentError, 'Non-finite numbers are not supported' unless data.finite?
    when String, Integer, TrueClass, FalseClass, NilClass then nil
    else raise ArgumentError, "Unsupported value type: #{data.class}"
    end
  end

  def write(data, format)
    require 'rexml/document' if format == 'xml'
    case format
    when 'yaml' then YAML.dump(data)
    when 'json' then "#{JSON.pretty_generate(data)}\n"
    when 'xml' then write_xml(data)
    when 'properties'
      raise ArgumentError, 'Properties require a flat mapping of scalar values' unless data.is_a?(Hash)

      data.map do |key, value|
        raise ArgumentError, 'Properties cannot represent nested or null values' if value.nil? || value.is_a?(Hash) || value.is_a?(Array)

        "#{property_escape(key)}=#{property_escape(value.to_s)}\n"
      end.join
    when 'puppet-hash'
      raise ArgumentError, 'Puppet hash output requires a mapping' unless data.is_a?(Hash)

      "#{PuppetHash.dump(data)}\n"
    end
  end

  def read_properties(source)
    result = {}
    pending = ''
    source.each_line do |line|
      line = line.chomp.lstrip
      next if pending.empty? && (line.empty? || line.start_with?('#', '!'))

      pending += line
      if pending[/\\*\z/].length.odd?
        pending.chop!
        next
      end
      match = pending.match(/\A((?:\\.|[^\\=:\s])*)(?:\s*[=:]\s*|\s+)?(.*)\z/m)
      result[property_unescape(match[1])] = property_unescape(match[2])
      pending = ''
    end
    raise ArgumentError, 'Unfinished Properties continuation' unless pending.empty?

    result
  end

  def property_unescape(value)
    value.gsub(/\\(u[0-9a-fA-F]{4}|.)/m) do
      escape = Regexp.last_match(1)
      if escape.start_with?('u')
        raise ArgumentError, 'Properties require four hex digits after \\u (no surrogate escapes)' unless escape.length == 5 && !(0xd800..0xdfff).cover?(escape[1..].to_i(16))

        [escape[1..].to_i(16)].pack('U')
      else
        { 'n' => "\n", 'r' => "\r", 't' => "\t", 'f' => "\f" }.fetch(escape, escape)
      end
    end
  end

  def property_escape(value)
    value.gsub(/[\\\s=:#!]/) do |char|
      { "\n" => '\\n', "\r" => '\\r', "\t" => '\\t', "\f" => '\\f' }.fetch(char) { "\\#{char}" }
    end
  end

  def read_xml(source)
    raise ArgumentError, 'XML DTDs and entity declarations are not supported' if source.match?(/<!DOCTYPE|<!ENTITY/i)

    document = REXML::Document.new(source)
    raise ArgumentError, 'XML requires one root element' unless document.root

    { xml_decode_name(document.root.name) => xml_value(document.root) }
  rescue REXML::ParseException => e
    raise ArgumentError, "Invalid XML: #{e.message.lines.first.strip}"
  end

  def xml_value(element)
    raise ArgumentError, 'XML namespaces are not supported' unless element.prefix.empty? && element.namespaces.empty?

    result = element.attributes.to_h.transform_keys { |key| "@#{key}" }.transform_values(&:value)
    children = element.elements.to_a
    text = element.texts.map(&:value).join
    return text if children.empty? && result.empty?

    raise ArgumentError, 'XML mixed text and child elements are not supported' if !children.empty? && !text.strip.empty?

    result['#text'] = text if children.empty? && !text.empty?
    children.group_by(&:name).each do |name, entries|
      values = entries.map { |child| xml_value(child) }
      key = xml_decode_name(name)
      result[key] = values.length == 1 ? values.first : values
    end
    result
  end

  def write_xml(data)
    raise ArgumentError, 'XML output requires a mapping' unless data.is_a?(Hash)

    # Keep a valid existing XML root; wrap ordinary Hiera mappings automatically.
    root = data.size == 1 && !data.values.first.is_a?(Array) &&
           data.keys.first.match?(/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/) ? data : { 'hiera' => data }
    document = REXML::Document.new
    xml_element(document, *root.first)
    output = +''
    REXML::Formatters::Default.new.write(document, output)
    "#{output}\n"
  end

  def xml_decode_name(name)
    match = /\Aempeira_key_([0-9a-f]+)\z/.match(name)
    match ? [match[1]].pack('H*').force_encoding('UTF-8') : name
  end

  def xml_element(parent, name, value)
    unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/) && !name.start_with?('empeira_key_')
      name = "empeira_key_#{name.unpack1('H*')}"
    end
    element = parent.add_element(name)
    if value.is_a?(Hash)
      value.each do |key, child|
        if key.start_with?('@')
          attribute = key.delete_prefix('@')
          raise ArgumentError, 'Invalid XML attribute name' unless attribute.match?(/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/) && attribute != 'xmlns'

          element.add_attribute(attribute, xml_scalar(child))
        elsif key == '#text'
          raise ArgumentError, 'XML mixed content is not supported' if value.keys.any? { |k| !k.start_with?('@') && k != '#text' }

          element.text = xml_scalar(child)
        else
          raise ArgumentError, 'XML cannot represent empty arrays' if child == []

          (child.is_a?(Array) ? child : [child]).each { |item| xml_element(element, key, item) }
        end
      end
    else
      element.text = xml_scalar(value)
    end
  end

  def xml_scalar(value)
    if value.nil? || value.is_a?(Hash) || value.is_a?(Array)
      raise ArgumentError, 'XML text and attributes require scalar, non-null values'
    end
    raise ArgumentError, 'XML cannot represent control characters' if value.to_s.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f]/)

    value.to_s
  end

  def template(data, format)
    parameters = []
    # Unique markers let the existing serializers handle all structural syntax.
    prefix = 'EMPEIRAVALUE'
    prefix += 'X' while data.inspect.include?(prefix)
    marked = template_values(data, [], parameters, prefix)
    escape_name = 'empeira_string_escapes'
    escape_name += '_x' while parameters.any? { |name, _| name == escape_name }
    body = write(marked, format).gsub('<%', '<%%')
    parameters.each_with_index do |(name, value), index|
      marker = "#{prefix}#{index}END"
      token = %w[json puppet-hash].include?(format) ? "\"#{marker}\"" : marker
      interpolation = "<%= $#{name} %>"
      if value.is_a?(String)
        interpolation = "<%= $#{name}.split('').map |$character| { " \
                        "$#{escape_name}[$character] ? { undef => $character, " \
                        "default => $#{escape_name}[$character] } }.join('') %>"
        interpolation = "\"#{interpolation}\"" if %w[yaml json puppet-hash].include?(format)
      end
      body = body.gsub(token) { interpolation }
    end
    return body if parameters.empty?

    declarations = parameters.map do |name, value|
      type = [true, false].include?(value) ? 'Boolean' : value.class.name
      "  #{type} $#{name} = #{PuppetHash.dump(value)}"
    end
    escapes = if parameters.any? { |_, value| value.is_a?(String) }
                "<% $#{escape_name} = #{PuppetHash.dump(template_escapes(format))} -%>\n"
              else
                ''
              end
    "<%- |\n#{declarations.join(",\n")}\n| -%>\n#{escapes}#{body}"
  end

  def template_escapes(format)
    case format
    when 'xml'
      { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&apos;' }
    when 'properties'
      { '\\' => '\\\\', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t', "\f" => '\\f',
        ' ' => '\\ ', '=' => '\\=', ':' => '\\:', '#' => '\\#', '!' => '\\!' }
    else
      escapes = (0..31).to_h { |code| [code.chr, Kernel.format('\\u%04x', code)] }
      escapes.merge!('"' => '\\"', '\\' => '\\\\')
      escapes['$'] = '\\$' if format == 'puppet-hash'
      escapes
    end
  end

  def template_values(data, path, parameters, prefix)
    case data
    when Hash then data.to_h { |key, value| [key, template_values(value, path + [key], parameters, prefix)] }
    when Array then data.each_with_index.map { |value, i| template_values(value, path + [i], parameters, prefix) }
    when NilClass then nil
    else
      base = path.join('_').downcase.gsub(/[^a-z0-9_]/, '_')
      base = "value_#{base}" unless base.match?(/\A[a-z]/)
      name = base
      suffix = 2
      while parameters.any? { |entry| entry.first == name }
        name = "#{base}_#{suffix}"
        suffix += 1
      end
      marker = "#{prefix}#{parameters.size}END"
      parameters << [name, data]
      marker
    end
  end

end
