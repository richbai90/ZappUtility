require 'mysql2'
module ZappBuilder
  class ConfigDB
    class << self
      attr_accessor :connection_attempts
      attr_accessor :error
    end
    attr_reader :db

    def initialize(*args)
      if self.class.connection_attempts.nil?
        self.class.connection_attempts = 0
      end
      if args.size < 2
        @db = connect
      else
        @db = connect(*args[0], *args[1])
      end
    end

    def connect(*args)
      ca = self.class.connection_attempts
      self.class.connection_attempts += 1
      if args.size < 2
        begin
          connection = Mysql2::Client.new(:host => 'localhost', :username => 'root', :password => '', :port => 5002, :database => 'sw_config')
        rescue Mysql2::Error => e
          print "#{e.message} \n"
          connection = nil
        end
      else
        username = *args[0]
        password = *args[1]
        begin
          connection = Mysql2::Client.new(:host => 'localhost', :username => username, :password => password, :port => 5002, :database => 'sw_config')
        rescue Mysql2::Error => e
          @error = e.message
          connection = nil
        end
      end
      connection
    end

    def connected?
      !@db.nil?
    end

    def connection_attempts
      self.class.connection_attempts
    end

  end
end