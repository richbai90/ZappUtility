require 'diffy'
require 'zip'
require_relative 'Utilities'
require_relative 'Options'
require_relative 'Builder'
require 'nokogiri'

module ZappBuilder
  class Analyzer
    def initialize(zapp, output = nil)
      $:.unshift File.dirname(__FILE__)
      @zapp = zapp
      @output = output.nil? ? Dir.pwd : output
      @cwd = Dir.pwd

      # we are running in the bin folder relative to the unpacked application.
      # This prevents the need to install gnutils into the path
      Dir.chdir(File.join(File.dirname($0), 'bin'))
    end


    def diff
      unless Dir.exists?('../Staging')
        Dir.mkdir('../Staging')
      end

      unless File.directory?(File.join(@output, 'diff'))
        Dir.mkdir(File.join(@output, 'diff'))
      end

      File.open('../Staging/blank', 'wb') do

      end

      output = File.join(@output, 'diff')
      Zip::File.open(@zapp) { |zip|
        zip.each do |e|
          e_path = File.join('../Staging', File.basename(e.name))
          server_path = ZappBuilder::Utilities::get_install_details[:sw]
          server_file_name = File.join(server_path, e.name)
          unless File::directory?(server_file_name)
            begin
              zip.extract(e, e_path) unless File.exist?(e_path)
            rescue NoMethodError
              next
            end
            unless File.exists?(server_file_name)
              server_file_name = '../Staging/blank'
            end

            if File.directory?(e_path)
              Dir.rmdir(e_path)
              next
            end

            unless FileUtils.compare_file(server_file_name, e_path)
              File.open(File.join(output, File.basename(e.name) + '.diff.html'), 'wb') do |f|
                if File.exists?(server_file_name)
                  diff = Diffy::SplitDiff.new(server_file_name, e_path, {:source => 'files', :format => :html})
                else
                  diff = Diffy::SplitDiff.new(File.read(server_file_name), File.read(e_path), {:format => :html})
                end
                f.puts(File.read('../html/template.html').sub('{{file_name}}', server_file_name).sub('{{diffy_css}}', Diffy::CSS).sub('{{left_diff}}', diff.left).sub('{{right_diff}}', diff.right))
              end
            end
            File.delete(e_path)
          end
        end
      }
      FileUtils.rm_r('../Staging')
    end

    def backup(conn)
      unless Dir.exists?('../Staging')
        Dir.mkdir('../Staging')
      end
      p 'This will make a backup of modified files only! We recommend creating a sql backup to undo any sql changes.'
      sleep(3)
      manifest = ZappBuilder::Manifest.new
      license = ''
      setup_name = ''
      Zip::File.open(@zapp) { |zip|
        zip.each do |e|
          server_path = ZappBuilder::Utilities::get_install_details[:sw]
          if e.name =~ /\.setup/i
            setup_name = File.basename(e.name, '.*')
            doc = Nokogiri::XML(e.get_input_stream.read)
            begin
              license = doc.css('ApplicationSetup').first['licensedTo']
              doc.css('file').each { |file|
                server_file_name = File.join(server_path, file['name'])
                if File.exists? server_file_name
                  unless File.directory?(server_file_name)
                    manifest.files file['name']
                  end
                end
              }
              doc.css('folder').each { |folder|
                server_file_name = File.join(server_path, folder['name'])
                if File.exists? server_file_name
                  manifest.folders ({:path => folder['name'], :match => folder['match'], :recursive => folder['recursive']})
                end
              }
            rescue NoMethodError
              #pass
            end
          end
        end
      }
      opts = Options.new
      opts.swserver ZappBuilder::Utilities::get_install_details[:sw]
      opts.cwd @cwd

      manifest.name setup_name
      manifest.version 'REMOVED'
      manifest.license license
      manifest_name = File.join('..', 'Staging', 'manifest.json')
      File.open(manifest_name, 'wb') do |m|
        m.write(manifest.to_s)
      end
      opts.manifest File.absolute_path(manifest_name)
      opts.filename File.join(@output, "#{manifest.name}.backup")
      builder = ZappBuilder::Builder.new(opts, conn)
      builder.build
    end
  end
end
