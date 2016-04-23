require 'typescript/rails'
require 'typescript-node'
require 'json'

module Typescript::Rails::Compiler
  class << self
    # @!scope class
    cattr_accessor :default_options
    cattr_accessor :tsconfig_path

    # Replace relative paths specified in /// <reference path="..." /> with absolute paths.
    #
    # @param [String] ts_path Source .ts path
    # @param [String] source. It might be pre-processed by erb.
    # @return [String] replaces source
    def replace_relative_references(ts_path, source)
      ts_dir = File.dirname(File.expand_path(ts_path))
      escaped_dir = ts_dir.gsub(/["\\]/, '\\\\\&') # "\"" => "\\\"", '\\' => '\\\\'

      # Why don't we just use gsub? Because it display odd behavior with File.join on Ruby 2.0
      # So we go the long way around.
      (source.each_line.map do |l|
        if l.starts_with?('///') && !(m = %r!^///\s*<reference\s+path=(?:"([^"]+)"|'([^']+)')\s*/>\s*!.match(l)).nil?
          matched_path = m.captures.compact[0]
          l = l.sub(matched_path, File.join(escaped_dir, matched_path))
        end
        next l
      end).join
    end

    # Get all references
    #
    # @param [String] path Source .ts path
    # @param [String] source. It might be pre-processed by erb.
    # @yieldreturn [String] matched ref abs_path
    def get_all_reference_paths(path, source, visited_paths=Set.new, &block)
      visited_paths << path
      source ||= File.read(path)
      source.each_line do |l|
        if l.starts_with?('///') && !(m = %r!^///\s*<reference\s+path=(?:"([^"]+)"|'([^']+)')\s*/>\s*!.match(l)).nil?
          matched_path = m.captures.compact[0]
          abs_matched_path = File.expand_path(matched_path, File.dirname(path))
          unless visited_paths.include? abs_matched_path
            block.call abs_matched_path
            get_all_reference_paths(abs_matched_path, nil, visited_paths, &block)
          end
        end
      end
    end

    # @param [String] ts_path
    # @param [String] source TypeScript source code
    # @param [Sprockets::Context] sprockets context object
    # @return [String] compiled JavaScript source code
    def compile(ts_path, source, context=nil, *options)
      if context
        get_all_reference_paths(File.expand_path(ts_path), source) do |abs_path|
          context.depend_on abs_path
        end
      end
      s = replace_relative_references(ts_path, source)
      begin
        ::TypeScript::Node.compile(s, *default_options, *options)
      rescue Exception => e
        raise "Typescript error in file '#{ts_path}':\n#{e.message}"
      end
    end

    def compile_tsconfig(tsconfig_path, context)
      STDOUT.write "Compiling #{tsconfig_path}\n"
      result = compile_tsconfig_file(tsconfig_path, context)
      if result.success?
        result.js
      else
        raise result.stderr + result.stdout
      end
    end

    def compile_tsconfig_file(tsconfig_path, context)
      output_file, dependent_files = find_output_file(tsconfig_path)

      dependent_files.each do |file|
        context.depend_on file
      end

      stdout, stderr, exit_status = ::TypeScript::Node.tsc(*['--project', tsconfig_path])

      output_js = File.exist?(output_file) ? File.read(output_file) : nil
      ::TypeScript::Node::CompileResult.new(
          output_js,
          exit_status,
          stdout,
          stderr,
      )
    end

    def find_output_file(tsconfig_path)
      tsconfig = File.read(tsconfig_path)
      json = JSON.parse(tsconfig)
      compiler_options = json['compilerOptions']
      output_file = File.join(File.dirname(File.expand_path(tsconfig_path)), compiler_options['outFile'])

      dependent_files = []
      files = json['files']
      files.each do |file|
        dependent_files.push(File.join(File.dirname(File.expand_path(tsconfig_path)), file))
      end

      return output_file, dependent_files
    end

  end

  self.default_options = %w(--target ES5 --noImplicitAny)
end
