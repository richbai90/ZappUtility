require 'json'
require 'nokogiri'
module ZappBuilder
  class Manifest
    attr_accessor :json

    def initialize(path = '')
      @json = {
          :name => '',
          :license => '',
          :version => '1.0.0',
          :install_actions => {
              :folders => [],
              :files => [],
              :dataImports => [],
              :sqlQueries => [],
              :excludes => [],
              :schema => '',
              :reports => [],
              :merge => []
          },

          :update_actions => {
              :folders => [],
              :files => [],
              :dataImports => [],
              :sqlQueries => [],
              :excludes => [],
              :schema => '',
              :reports => [],
              :merge => []
          },

          :copy_actions => {
              :folders => [],
              :files => [],
              :dataImports => [],
              :sqlQueries => [],
              :excludes => [],
              :schema => '',
              :reports => [],
              :merge => []
          }
      }
      unless path.empty?
        @json.merge!(JSON.parse(IO.read(path), :symbolize_names => true))
      end
    end

    #overwrite the method_missing so that it can pass the method to the @json object
    def method_missing(method, *args)
      # find the name of the method minus any trailing underscores

      m = method.to_s[/^(.*)(?<!_$)/].to_sym
      if @json[method].nil?
        json = @json[:install_actions]
      else
        json = @json
      end
      unless args.length == 0
        if args.first.respond_to?(:has_key?) && args.first.has_key?(:action)
          json = @json[(args.first[:action].to_s + '_actions').to_sym]
          args.shift
        end

        if json[m].respond_to? :push
          if args.first.respond_to? :push
            json[m] = args.first
          else
            json[m].push(args.first)
          end
        else
          json[m] = args.first
        end
      end
      json[m]
    end

    def to_s
      JSON.pretty_generate(json).to_s
    end

    def to_xml
      setup = Nokogiri::XML::Builder.new do |xml|
        xml.ApplicationSetup(:version => (@json[:version].empty?) ? Date.today.to_s : @json[:version], :licensedTo => @json[:license]) {
          xml.installActions {
            json = @json[:install_actions]
            xml.files {
              json[:files].each do |f|
                xml.file(:name => f.gsub('/', "\\"))
              end
              json[:folders].each do |f|
                folder_options = {}
                if f.respond_to? :each
                  folder_options[:name] = f[:path].gsub(/\//, "\\")
                  folder_options[:match] = f.key?(:match) ? f[:match] : '*'
                  folder_options[:recursive] = f.key?(:recursive) ? f[:recursive] : 'yes'
                else
                  folder_options[:name] = f.gsub(/\//, "\\")
                  folder_options[:match] = '*'
                  folder_options[:recursive] = 'yes'
                end
                xml.folder(folder_options)
              end
            }
            xml.dataImport {
              json[:dataImports].each do |i|
                xml.sqlImport(:db => i[:db], :file => i[:import])
              end
              json[:sqlQueries].each do |q|
                xml.sqlQuery(:db => q[:db], :query => q[:query])
              end
              json[:reports].each do |r|
                xml.reportImport(:file => r)
              end
            }

            unless json[:schema].nil? || json[:schema].empty?
              if File.exist?(json[:schema])
                xml.schema(:name => Pathname(json[:schema]).basename)
              else
                xml.schema(:name => json[:schema])
              end
            end
          }
          xml.updateActions {
            json = @json[:update_actions]
            xml.files {
              json[:files].each do |f|
                xml.file(:name => f.gsub('/', "\\"))
              end
              json[:folders].each do |f|
                folder_options = {}
                if f.respond_to? :each
                  folder_options[:name] = f[:path].gsub(/\//, "\\")
                  folder_options[:match] = f.key?(:match) ? f[:match] : '*'
                  folder_options[:recursive] = f.key?(:recursive) ? f[:recursive] : 'yes'
                else
                  folder_options[:name] = f.gsub(/\//, "\\")
                  folder_options[:match] = '*'
                  folder_options[:recursive] = 'yes'
                end
                xml.folder(folder_options)
              end
            }
            xml.dataImport {
              json[:dataImports].each do |i|
                xml.sqlImport(:db => i[:db], :file => i[:import])
              end
              json[:sqlQueries].each do |q|
                xml.sqlQuery(:db => q[:db], :query => q[:query])
              end
              json[:reports].each do |r|
                xml.reportImport(:file => r)
              end
            }

            unless json[:schema].nil? || json[:schema].empty?
              if File.exist?(json[:schema])
                xml.schema(:name => Pathname(json[:schema]).basename)
              else
                xml.schema(:name => json[:schema])
              end
            end
          }
          xml.copyActions {
            json = @json[:copy_actions]
            xml.files {
              json[:files].each do |f|
                xml.file(:name => f.gsub('/', "\\"))
              end
              json[:folders].each do |f|
                folder_options = {}
                if f.respond_to? :each
                  folder_options[:name] = f[:path].gsub(/\//, "\\")
                  folder_options[:match] = f.key?(:match) ? f[:match] : '*'
                  folder_options[:recursive] = f.key?(:recursive) ? f[:recursive] : 'yes'
                else
                  folder_options[:name] = f.gsub(/\//, "\\")
                  folder_options[:match] = '*'
                  folder_options[:recursive] = 'yes'
                end
                xml.folder(folder_options)
              end
            }
            xml.dataImport {
              json[:dataImports].each do |i|
                xml.sqlImport(:db => i[:db], :file => i[:import])
              end
              json[:sqlQueries].each do |q|
                xml.sqlQuery(:db => q[:db], :query => q[:query])
              end
              json[:reports].each do |r|
                xml.reportImport(:file => r)
              end
            }

            unless json[:schema].empty?
              xml.schema(:name => Pathname(@json[:schema]).basename)
            end
          }
        }
      end
      setup.to_xml
    end

  end

  class << Manifest
    def from_xml(xml, manifest = nil, action = nil)
      if manifest.nil?
        manifest = Manifest.new
        if File.exist?(xml)
          name = File.basename(xml).split('.')[0]
          doc = Nokogiri::XML(File.read(xml))
        else
          name = ''
          doc = Nokogiri::XML(xml)
        end
        manifest.name name
        manifest.license doc.css('ApplicationSetup').first['licensedTo']
      else
        doc = xml
      end

      doc.children.each do |child|
        # skip text nodes Nokogiri adds by default during processing
        if child.name == 'text'
          next
        end

        action = child.name =~ /[a-z]+(?=Actions)/ ? child.name.match(/[a-z]+(?=Actions)/)[0] : action

        if child.name == 'schema'
          manifest.schema child['name']
          next
        end

        if child.children.length > 0
          from_xml(child, manifest, action)
        end

        case child.name
          when 'file'
            manifest.files({:action => action}, child['name'])
          when 'folder'
            manifest.folders({:action => action}, {:path => child['name'], :match => child['match'], :recursive => child['recursive']})
          when 'sqlImport'
            manifest.dataImports({:action => action}, {:db => child['db'], :import => child['file']})
          when 'sqlQuery'
            manifest.sqlQueries({:action => action}, {:query => child['query']})
          when 'reportImport'
            manifest.reports({:action => action}, child['file'])
          when 'schema'
            manifest.schema child['name'] || ''
          else
            next
        end
      end
      manifest
    end
  end
end

