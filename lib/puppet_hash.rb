# frozen_string_literal: true
# SPDX-License-Identifier: AGPL-3.0-only

require 'strscan'

# A small data-literal reader, deliberately not a Puppet language interpreter.
module PuppetHash
  module_function

  def quote(value)
    escaped = value.each_char.with_index.map do |char, index|
      case char
      when '"', '\\', '$' then "\\#{char}"
      when '%' then value[index + 1] == '>' ? '\\u0025' : '%'
      when /[[:cntrl:]]/ then format('\\u%04x', char.ord)
      else char
      end
    end.join
    "\"#{escaped}\""
  end

  def dump(value)
    case value
    when Hash then "{#{value.map { |k, v| "#{quote(k)} => #{dump(v)}" }.join(', ')}}"
    when Array then "[#{value.map { |v| dump(v) }.join(', ')}]"
    when String then quote(value)
    when NilClass then 'undef'
    else value.to_s
    end
  end

  def load(source)
    scanner = StringScanner.new(source)
    result = value(scanner)
    space(scanner)
    raise ArgumentError, 'Expected only a Puppet hash literal' unless result.is_a?(Hash) && scanner.eos?

    result
  end

  def space(scanner)
    scanner.skip(/(?:\s+|\#[^\n]*)*/)
  end

  def take(scanner, token)
    space(scanner)
    scanner.scan(token)
  end

  def expect(scanner, token)
    return if take(scanner, token)

    raise ArgumentError, "Invalid Puppet data near byte #{scanner.pos}"
  end

  def value(scanner)
    space(scanner)
    if scanner.scan(/\{/)
      result = {}
      until take(scanner, /\}/)
        key = value(scanner)
        raise ArgumentError, 'Puppet hash keys must be strings' unless key.is_a?(String)

        expect(scanner, /=>/)
        result[key] = value(scanner)
        break if take(scanner, /\}/)

        expect(scanner, /,/)
      end
      result
    elsif scanner.scan(/\[/)
      result = []
      until take(scanner, /\]/)
        result << value(scanner)
        break if take(scanner, /\]/)

        expect(scanner, /,/)
      end
      result
    elsif (literal = scanner.scan(/'(?:[^'\\]|\\.)*'/m))
      literal[1...-1].gsub(/\\(['\\])/, '\1')
    elsif (literal = scanner.scan(/"(?:[^"\\]|\\.)*"/m))
      content = literal[1...-1]
      raise ArgumentError, 'Puppet interpolation is not supported' if content.match?(/(?<!\\)(?:\\\\)*\$/)

      content.gsub(/\\(u[0-9a-fA-F]{4}|[nrts"\\$])/) do
        escape = Regexp.last_match(1)
        escape.start_with?('u') ? [escape[1..].to_i(16)].pack('U') :
          { 'n' => "\n", 'r' => "\r", 't' => "\t", 's' => ' ' }.fetch(escape, escape)
      end
    elsif (number = scanner.scan(/-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/))
      number.match?(/[.eE]/) ? Float(number) : Integer(number)
    elsif (word = scanner.scan(/(?:true|false|undef)\b/))
      { 'true' => true, 'false' => false, 'undef' => nil }.fetch(word)
    else
      raise ArgumentError, "Expected a Puppet data literal near byte #{scanner.pos}; code is not supported"
    end
  end
end
