require 'optparse'
require 'ostruct'
class Options
  attr_reader :options

  def initialize
    @options = OpenStruct.new
    OptionParser.new do |opt|
      options[:dwl] = ''
      opt.on_tail('-h', '--help', 'Show this message') do
        puts opt
        exit
      end
      opt.on('-b', '--backup', 'Do a complete backup. The license flag is required.') { |o| options[:backup] = true }
      opt.on('-l', '--license license', 'To whom to license the zapp file. Required with backup flag.') { |o| options[:license] = o }
      opt.on('-m', '--manifest manifest.json', 'For a custom build, the path of the manifest file to use. Not to be used with --backup') { |o| options[:manifest] = o }
      opt.on('-d', '--data', "When doing a complete backup, whether or not to backup the database as well. \n\t\t\t\t     This option will not backup the swdata database when the environment is not mysql.\n") { options[:data] = true }
      opt.on('-w', '--workingdir filepath', 'Where to save the file. Defaults to Supportworks Server Folder') { |o| options[:filename] = o }
      opt.on('-a', '--analyze filename', 'Analyze a zapp file') { |o| options[:analyze] = o }
      opt.on('-z' '--zapp-backup zapp', 'Backup a zapp file') { |o| options[:backup] = o }
      opt.on('-e', '--encrypt', 'Encrypt the zapp file using a public/private key or password') { options[:encrypt] = true }
      opt.on('-p', '--password', 'Encrypt/Decrypt the file using a known password. Overwites the public/private key option') { |o| options[:password] = o }
      opt.on('-de', '--decode', 'Decodes a base64 zapp file after it has been decrypted') { |o| options[:decode] = o }
      opt.on('--skip-schema', 'Skip the Supportworks Data schema backup') { options[:skip_schema] = true }
      opt.on('--exclude file1,file2,etc', 'Files and folders to skip when doing a complete backup. The root of Supportworks Server is assumed') { |o| options[:excludes] = ZappBuilder::Utilities::string_to_array(o) }
      opt.on('--http', 'Make a backup of the apache configurations') { options[:merge] = true }
      opt.on('--merge', 'Merge the service xml files to backup auto responders and server configurations') { options[:merge] = true }
      opt.on('--merge-passwords', 'Overwrites the default behavior of skipping password configurations when --merge or --data are set') { options[:passwords] = true }
      opt.on('--merge-install-path', 'Overwrites the default behavior of skipping install path configurations when --merge is set.') { options[:filepath] = true }
      opt.on('--outsource', 'Restricts the files to a smaller range of files typically required by consultants when doing customizations') { options[:for_outsource] = true }
      opt.on('--dwl file', 'Provide a dirty word list to exclude files matching words on this list regardless of case. List may also contain expressions of the format /regexpattern/ in which case the i qualifier is assumed') { |file| options[:dwl] = file }
    end.parse!

    @valid = validate

  end

  def validate
    valid = true
    reason = ''
    @options.to_h.each do |opt, val|
      case opt
        when :backup
          if val === true && options[:license].nil?
            valid = false
            reason = 'Backup flag set without license'
          end
        when :license
          if (val && options[:backup].nil?) && (val && options[:manifest].nil?) && (val && ARGV[0].nil?)
            valid = false
            reason = 'License flag set without backup flag'
          end
        when :manifest
          if (val && !options[:backup].nil?) || (val && !options[:license].nil?)
            valid = false
            reason = 'Manifest flag provided with backup or license flag'
          end
        else
      end
    end
    {:valid => valid, :reason => reason}
  end

  def valid?
    @valid[:valid]
  end

  def error
    @valid[:reason]
  end

  def method_missing(m, *args, &block)
	m = m.to_s[/^(.*)(?<!_$)/].to_sym
    if args.length > 0
      @options[m] = args.first
    end
    @options[m]
  end

end


