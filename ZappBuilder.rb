require 'base64'
module ZappBuilder
  def relicense(license, zapp)
    cwd = Dir.pwd
    Dir.chdir File.join(File.dirname($0), 'staging')
    system "#{File.join('..', 'bin', '7za.exe')} x \"#{File.absolute_path(zapp)}\" data/_dd_data/*.setup -aoa"
    system "#{File.join('..', 'bin', 'xmlc.exe')} -d -f *.setup -r"
    setup = Manifest.from_xml(Dir.glob('*/**/*.setup').first)
    setup.license license
    File.open(Dir.glob('*/**/*.setup').first, 'wb') { |file| file.puts setup.to_xml }
    system "#{File.join('..', 'bin', '7za.exe')} a \"#{File.absolute_path(zapp)}\" *.setup -r"
    File.delete(File.absolute_path(Dir.glob('*/**/*.setup').first))
    Dir.chdir(cwd)
  end

  def decode(file, output = './')
    File.open(File.join(output, File.basename(file).split('.').take(2).join('.')), 'wb') { |new_file| new_file.puts Base64.decode64(File.read(file)) }
  end
end