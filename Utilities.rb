require 'win32/registry'
module ZappBuilder
  module Utilities
    extend self

    def get_install_details
      dets = {}
      Win32::Registry::HKEY_LOCAL_MACHINE.open('Software\Wow6432Node\Hornbill\Supportworks Server') do |reg|
        dets[:sw] = reg['InstallPath'].gsub(/\\/, '/')
        dets[:version] = reg['Version']
      end
      Win32::Registry::HKEY_LOCAL_MACHINE.open('Software\Wow6432Node\Hornbill\Core Services') do |reg|
        dets[:cs] = reg['InstallPath'].gsub(/\\/,'/')
      end
      dets
    end

    def exit_with_reason(reason)
      print reason + " The program will now close. \n\n"
      sleep 2
      exit 0
    end

    def password(prompt='Please enter your password: ', confirm='Please confirm the password: ', echo='*')
      attempt_counter = 1
      pwd = ask (prompt) { |q| q.echo = echo }
      cpwd = ask (confirm) { |q| q.echo = echo }
      pwd = nil unless pwd == cpwd
      while pwd.nil? && attempt_counter < 4
        print 'The passwords do not match, please try again'
        pwd = ask (prompt) { |q| q.echo = echo }
        cpwd = ask (confirm) { |q| q.echo = echo }
        pwd = nil unless pwd == cpwd
        attempt_counter += 1
      end
      pwd
    end

  end
end