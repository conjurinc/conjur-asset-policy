module DSLWorld

  def load_policy try, text, options = nil, privilege = nil
    elevate = false
    command_options = if options
      inject_namespace(options)
    else
      "--namespace #{namespace}"
    end
    command_string = %Q(bundle exec conjur #{privilege ? privilege : ''} policy load #{command_options})
    step "I run `#{command_string}` interactively"
    
    last_command_started.write(inject_namespace(text))
    last_command_started.stdin.close if last_command_started.stdin
    last_command_started.wait
    expect(last_command_started).to have_exit_status(0) unless try
  end

  # Drops the indentation of the first line shared indentation from the start of each line
  def normalize_indentation text
    lines = text.split("\n")
    return text if lines.empty?

    indent = if lines[0] =~ /^(\s+)(.+?)$/
      $1.length
    else
      0
    end
    lines.map{|l| l[indent..-1]}.join "\n"
  end

  def last_json
    # Hack to get Aruba to populate stdout
    step "the output should contain \"\""
    YAML.load(last_command_started.stdout).to_json.tap do |json|
      $stderr.puts "last_json is #{json}" if ENV['DEBUG']
    end
  end

  def normalize_stdout
    all_commands.each do |cmd|
      if cmd.instance_variable_get("@context").nil?
        cmd.instance_variable_set("@context", self)
        class << cmd
          def stdout(options={})
            @context.strip_namespace super(options)
          end
        end
      end
    end
  end

  def namespace
    @namespace
  end
  
  def user_namespace
    namespace.gsub('/', '-')
  end

  def user_namespace
    namespace.gsub('/', '-')
  end
  
  def inject_namespace text
    text.gsub "@namespace@", namespace
  end

  def strip_namespace text
    return "" if text.nil?
    text.gsub "#{namespace}/", ""
  end
end

require 'rspec/mocks'
require 'cucumber/rspec/doubles'

World(RSpec::Expectations, RSpec::Mocks, DSLWorld)
