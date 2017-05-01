require_relative './Manifest'
require 'tempfile'
require 'pathname'
require 'fileutils'
require 'win32/window'
require 'base64'


module ZappBuilder
  class Builder
    attr_reader :opts

    def initialize(opts, connection)
      @opts = opts
      @connection = connection
      install_details = ZappBuilder::Utilities.get_install_details
      @opts.swserver install_details[:sw]
      @opts.cs install_details[:cs]
      @opts.version install_details[:version]
      unless @opts.filename
        @opts.filename @opts.swserver
      end

      if @opts.cwd
        Dir.chdir @opts.cwd
      end

      @staging_directory = File.join(File.dirname($0), 'Staging')

    end

    def build
      if @opts.backup
        build_backup
      elsif @opts.manifest
        build_from_manifest
      else
        ZappBuilder::Utilities::exit_with_reason('Unknow build options provided')
      end
    end

    def build_backup
      unless @opts.skip_schema
        username = nil
        password = nil
        @connection.query("select * from sw_databases where dbname = 'swdata'").each do |db|
          username = db['uid']
          password = db['pwd']
        end
        swdbconf = Tempfile.new('swdbconfig')
        @swdbconf_path = swdbconf.path
        swdbconf.unlink
        if (/8\.\d.+/ =~ @opts.version).nil?
          system "start cmd /k cmd /C \"#{@opts.cs}tools\\swdbconf.exe\" -export #{@swdbconf_path.gsub('/', "\\")} -tdb swdata -cuid #{username} -cpwd #{password}"
        else
          system "start cmd /k cmd /C \"#{@opts.swserver}\\bin\\swdbconf.exe\" -export #{@swdbconf_path.gsub('/', "\\")} -tdb swdata -cuid #{username} -cpwd #{password}"
        end
        sleep 1
        while Window.find(:title => /Supportworks Database Configuration Analyzer/i).length > 0
          sleep 1
        end
      end
      #build_dir_structure
      build_from_manifest(create_backup_manifest)
    end

    def build_from_manifest(manifest = nil)
      begin
        if manifest.nil?
          manifest = ZappBuilder::Manifest.new(@opts.manifest)
        end
        # setup the staging directory
        FileUtils::mkdir_p File.join(@staging_directory, 'data', '_dd_data', 'backup')
        # move the schema definition
        unless manifest.schema.empty?
          begin
            File.open(File.join(@staging_directory, "#{Pathname(manifest.schema).basename}"), "wb") do |schema|
              File.foreach(manifest.schema) do |line|
                schema.puts line
              end
            end
          rescue Errno::ENOENT
            begin
              File.open(File.absolute_path(File.basename(manifest.schema))) do |schema|
                File.foreach(manifest.schema) do |line|
                  schema.puts line
                end
              end
            rescue Errno::ENOENT
              #pass
            end
          end
        end

        File.open(File.join(@staging_directory, 'data', '_dd_data', "#{manifest.name}.setup"), "wb") do |setup|
          setup.puts manifest.to_xml
        end

        File.open(File.join(@staging_directory, 'data', '_dd_data', 'backup', "#{manifest.name}.manifest"), "wb") do |json|
          json.puts manifest.to_s
        end

        # Create 7zip archive
        filename = File.join(@opts.filename, (manifest.name.empty? ? 'swbackup' : manifest.name))


        include_file = File.join(@staging_directory, 'include.txt')
        exclude_file = File.join(@staging_directory, 'exclude.txt')

        unless @opts.dwl.empty?
          print 'Searching files for excluded words...'
          File.open(File.join(@opts.filename, 'excludes.log'), 'wb') { |log|
            log.puts('The files listed below have been excluded due to their matching an item on the provided Dirty Word List.')
            log.puts('If these files are required to be in the archive, you will have to redact them first.')
            log.puts('Please note that each entry lists only the first match in the file and there may be others that will need to be redacted as well.')
            log.puts("#{'-' * 'Please note that each entry lists only the first match in the file and there may be others that will need to be redacted as well.'.length}\n\n")
          }
        end

        File.open(include_file, 'wb') { |include|
          manifest.folders.each do |f|
            folder = f.respond_to?(:each) ? File.join(f[:path], f[:match]) : File.join(f, '*.*')
            include.puts(folder.gsub(/\//, '\\'))
          end

          manifest.files.each do |f|
            unless !@opts.dwl.empty? && exclude?(f)
              include.puts(f.gsub(/\//, '\\'))
            end
          end

          manifest.dataImports.each do |i|
            unless !@opts.dwl.empty? && exclude?(i[:import])
              include.puts(i[:import].gsub(/\//, '\\'))
            end
          end

          manifest.reports.each do |r|
            unless !@opts.dwl.empty? && exclude?(r)
              include.puts(r.gsub(/\//, '\\'))
            end
          end
        }

        File.open(exclude_file, 'wb') { |exclude|
          manifest.excludes.each do |x|
            exclude.puts(x.gsub(/\//, '\\'))
          end
          unless @opts.dwl.empty?
            manifest.folders.each do |f|
              folder = f.respond_to?(:each) ? File.join(f[:path], f[:match]) : File.join(f, '*.*')
              x = exclude?(folder, true)
              x.each { |xf|
                exclude.puts(xf.gsub(/\//, '\\'))
              }
            end
          end
        }

        Dir.chdir(@opts.swserver)
        zapp = File.join(@staging_directory, '..', 'bin', '7za.exe')
        dbconf = File.join(@staging_directory, File.basename(manifest.schema))
        system(zapp + " a -tzip -ir@\"#{include_file}\" -xr@\"#{exclude_file}\" \"#{filename}.zapp\"")

        data_dir = File.join(@staging_directory, 'data')
        # if exclude?(@swdbconf_path)
        #   File.delete(@swdbconf_path)
        # end
        if @opts.skip_schema
          zapped = system("#{zapp} a \"#{filename}.zapp\" \"#{data_dir}\" -r")
        else
          zapped = system("#{zapp} a \"#{filename}.zapp\" \"#{dbconf}\"")
        end

        if @opts.encrypt
          gpg = File.join(@staging_directory, '..', 'bin', 'gpg', 'gpg2.exe')
          key = File.join(@staging_directory, '..', 'crypto', 'pub.asc')
          b64 = File.join(@staging_directory, "#{File.basename(filename)}.zapp.b64")
          begin
            if @opts.password.nil?
              `#{gpg} --import "#{key}" `
              File.open(b64, 'wb') { |f| f.puts Base64.strict_encode64(File.binread(filename + '.zapp')) }
              system("#{gpg} --always-trust --output \"#{filename}.zapp.b64.gpg\" -ear services@bittercreektech.com #{b64}")
            else
              system("#{zapp} a \"#{filename}.zapp.7z\" \"#{filename}.zapp\" -t7z -p\"#{@opts.password}\"" + (@opts.for_outsource ? ' -m0=LZMA2:d256m:fb64 -mx9' : ''))
              return true
            end
          ensure
            File.delete("#{filename}.zapp")
            if @opts.password.nil?
              filename = filename + '.zapp.b64.gpg'
            end
          end
        end
      ensure
        if @opts.for_outsource
          system("#{zapp} a \"#{filename}.7z\" \"#{filename}\" -t7z -m0=LZMA2 -mx9 ")
          if File.exist?(filename)
            File.delete(filename)
            filename = filename + '.7z'
          else
            begin
              File.delete(filename + '.zapp')
              filename = filename + '.zapp.7z'
            rescue Errno::ENOENT
              "The file #{filename}.zapp could not be found. This may indicate a problem during creation."
              return false
            end
          end
        end
      end
      p "The file has been saved to #{filename}."
      zapped
    end

    def create_backup_manifest
      manifest = ZappBuilder::Manifest.new
      schema = ''
      if @opts.for_outsource
        folders = [
            'forms',
            'html',
            'idata',
            'scripts',
            'vpme',
            'data/_dd_data/exported',
            'data/_dd_data/www',
            {:path => 'data/_dd_data', :match => '*.ddf', :recursive => 'yes'}
        ]
        excludes = ''
        unless @opts.skip_schema
          schema = @swdbconf_path
        end
      else
        folders = %w(bin cache clients conf data docs dump forms html idata knowledgebase log logarchive odbc postbox scripts vpme)
        excludes = 'data/_dd_data/*.setup'
        unless @opts.skip_schema
          schema = @swdbconf_path
        end
      end

      manifest.folders folders
      manifest.excludes excludes
      manifest.schema schema
      manifest.license_ @opts.license
      manifest.name_ 'SWBACKUP'
      manifest
    end


    def exclude?(file, glob=false)
      if File.exists?(@opts.dwl) && (glob || File.exists?(File.join(@opts.swserver, file)))
        dwl = []
        File.open(@opts.dwl).each_line do |line|
          line = line.strip
          unless line.match(/^(#)|^(\s*$)/) # skip comment lines and empty lines
            if line.match(/^(\/)(.*?)(\/[igmxsuXUAJ]*?)$/) # is a regex
              discard, expression, flags = line.match(/^(\/)(.*?)(\/[igmxsuXUAJ]*?)$/).captures
              regex = Regexp.new(expression, true)
            else
              regex = Regexp.new(line, true)
            end
            dwl.push(regex)
          end
        end

      else
        return false
      end
      File.open(File.join(@opts.filename, 'excludes.log'), 'ab') { |log|
        if glob
          parts = file.split('/')
          glob_pattern = parts.insert(parts.length - 1, '**').join('/')
          excludes = []
          Dir.glob(File.join(@opts.swserver, glob_pattern)).each do |f|
            exclude = dwl_compare(f, dwl, log)
            if exclude
              f.slice!(@opts.swserver + '/')
              excludes.push(f)
            end
          end
          return excludes
        else
          return dwl_compare(File.join(@opts.swserver, file), dwl, log)
        end
      }
      false
    end

    def dwl_compare(file, dwl, log)
      line_counter = 0
      does_match = false

      `"#{File.join(File.dirname($0), 'bin', 'xmlc.exe')}" -d -p "#{File.dirname(file)}" -i "#{File.basename(file)}" -o "_decrypted_#{File.basename(file)}"`

      begin
        begin
          _file = File.join(File.dirname(file), "_decrypted_#{File.basename(file)}")
        rescue Errno::ENOENT
          _file = file
        end

        file = _file
        File.open(file) { |f| f.each_line do |line|

          line_counter += 1
          dwl.each { |pattern|
            match = (line =~ pattern)
            unless match.nil?
              file_name = file.scan(/(.*(?=_decrypted_))|((?<=_decrypted_).*)/).flatten.select { |i| !(i.nil? || i.empty?) }.join('')
              log.puts("#{file_name}\t#{line_counter}:#{match}\tmatch: #{pattern.inspect}")
              does_match = true
              break
            end
          }
          if does_match
            break
          end
        end
        }
        File.delete(file)
      rescue Errno::ENOENT
        #pass
      end

      does_match
    end

  end

end


