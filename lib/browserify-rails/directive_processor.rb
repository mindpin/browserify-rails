require "open3"
require "json"

module BrowserifyRails
  class DirectiveProcessor < Tilt::Template
    BROWSERIFY_CMD = "./node_modules/.bin/browserify".freeze

    class BrowserifyError < RuntimeError
    end

    def prepare
    end

    def evaluate(context, locals, &block)
      if commonjs_module?
        asset_dependencies(context.environment.paths).each do |path|
          context.depend_on_asset(path)
        end

        browserify
      else
        data
      end
    end

    private

    def commonjs_module?
      data.to_s.include?("module.exports") || data.to_s.include?("require")
    end

    # This primarily filters out required files from node modules
    #
    # @return [<String>] Paths of dependencies, that are in asset directories
    def asset_dependencies(asset_paths)
      dependencies.select do |path|
        path.start_with?(*asset_paths)
      end
    end

    # @return [<String>] Paths of files, that this file depends on
    def dependencies
      run_browserify("--list").lines.map(&:strip).select do |path|
        # Filter the temp file, where browserify caches the input stream
        File.exists?(path)
      end
    end

    def browserify
      options = "-d"

      run_browserify(options)
    end

    def browserify_cmd
      cmd = File.join(Rails.root, BROWSERIFY_CMD)

      if !File.exist?(cmd)
        raise ArgumentError, "#{cmd} could not be found. Please run npm install."
      end

      cmd
    end

    # Run browserify with `data` on standard input.
    #
    # We are passing the data via stdin, so that earlier preprocessing steps are
    # respected. If you had, say, an "application.js.coffee.erb", passing the
    # filename would fail, because browserify would read the original file with
    # ERB tags and fail. By passing the data via stdin, we get the expected
    # behavior of success, because everything has been compiled to plain
    # javascript at the time this processor is called.
    #
    # @raise [BrowserifyError] if browserify does not succeed
    # @param options [String] Options for browserify
    # @return [String] Output on standard out
    def run_browserify(options)
      command = "#{browserify_cmd} #{options}"
      directory = File.dirname(file)
      stdout, stderr, status = Open3.capture3(command, stdin_data: data, chdir: directory)

      if !status.success?
        raise BrowserifyError.new("Error while running `#{command}`:\n\n#{stderr}")
      end

      stdout
    end
  end
end
