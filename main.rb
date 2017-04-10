require_relative 'ZappBuilder'
require_relative 'ConfigDB'
require_relative 'Builder'
require_relative 'Utilities'
require_relative 'Options'
require_relative 'Analyzer'
require 'highline/import'

# Begin by parsing comamand line arguments
# If no arguments were passed, show the help banner

ARGV << '-h' if ARGV.empty?


#Make sure we don't have any conflicting options
options = Options.new
swconfig = nil

unless options.valid?
  ZappBuilder::Utilities.exit_with_reason(options.error)
end

unless options.skip_schema || !(options.backup || options.manifest)
  swconfig = ZappBuilder::ConfigDB.new
  until (swconfig.connected?) || (swconfig.connection_attempts > 3)
    if swconfig.connection_attempts == 1
      again = ask 'We were unable to connect to the Supportworks database using the default username and password. Would you like to try again?(y/n) '
    else
      again = ask 'We were unable to connect to the Supportworks database using the credentials supplied. Would you like to try again?(y/n) '
    end
    if again.downcase == 'yes' || again.downcase == 'y'
      username = ask 'Please supply your username: '
      password = ZappBuilder::Utilities::password
      swconfig.connect(username, password)
    else
      break
    end
  end

  unless swconfig.connected?
    skip_schema = ask 'We were unable to determine your username and password. Would you like to continue without exporting the swdata schema?(y/n) '
    if skip_schema.downcase == 'yes' || skip_schema.downcase == 'y'
      options.skip_schema true
    else
      ZappBuilder::Utilities::exit_with_reason 'We were unable to connect to the Supportworks Database.'
    end
  end
end


if options.manifest or (options.backup === true)
  builder = ZappBuilder::Builder.new(options, swconfig.db)
  builder.build
end


if options.analyze
  analyzer = ZappBuilder::Analyzer.new(options.analyze, options.filename || './')
  analyzer.diff
end

if options.backup.respond_to? :sub
  analyzer = ZappBuilder::Analyzer.new(options.backup, options.filename || './')
  analyzer.backup(swconfig.db)
end

if options.license && !options.backup && options.manifest.nil?
  include ZappBuilder
  relicense(options.license, ARGV[0])
end

if options.decode_
  include ZappBuilder
  decode(options.decode_, (options.filename || './'))
end




