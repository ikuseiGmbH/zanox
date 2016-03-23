require "rubygems"

module Zanox
  module API
    require "savon"
    require "base64"
    require "hmac-sha1"
    require "digest/md5"

    class AuthError < ArgumentError; end

    attr_accessor :public_key
    attr_accessor :secret_key
    attr_accessor :wsdl
    attr_accessor :driver

    def self.request(method, options)
      puts method + " " + options.inspect if $DEBUG

      options[:connectId] = Zanox::API::Session.connect_id

      unless Zanox::API::Session.secret_key.nil?
        timestamp = Zanox::API.get_timestamp
        nonce = Zanox::API.generate_nonce
        signature = Zanox::API.create_signature(Zanox::API::Session.secret_key, "publisherservice" + method.delete("_").downcase + timestamp + nonce)
        options.merge!(timestamp: timestamp, nonce: nonce, signature: signature)
      end

      @wsdl = "http://api.zanox.com/wsdl/2011-03-01/" unless @wsdl
      @driver = Savon.client(wsdl: @wsdl)
      @driver.ssl_verify_mode = OpenSSL::SSL::VERIFY_NONE if $DEBUG
      @driver.call(method.to_sym, message: options).hash
    rescue Exception => e
      puts
      puts "ERROR"
      puts e.message
      nil
    end

    def self.generate_nonce
      Digest::MD5.hexdigest((Time.new.usec + rand).to_s)
    end

    def self.get_timestamp
      Time.new.gmtime.strftime("%Y-%m-%dT%H:%M:%S.000Z").to_s
    end

    def self.create_signature(secret_key, string2sign)
      Base64.encode64(HMAC::SHA1.new(secret_key).update(string2sign).digest)[0..-2]
    end

    module Session
      attr_accessor :connect_id
      attr_accessor :secret_key
      attr_accessor :session_key
      attr_accessor :offline_token

      def self.new(auth_token)
        response = Zanox::Connect.request("getSession", authToken: auth_token, publicKey: Zanox::API.public_key)
        map(response)
      end

      def self.offline(offline_token)
        response = Zanox::Connect.request("getOfflineSession", offlineToken: offline_token, publicKey: Zanox::API.public_key)
        map(response) ? response.session : { error: "error!!! offline session" }
      end

      def map(response)
        if response.respond_to?(:session)
          @connect_id = response.session.connectId
          @secret_key = response.session.secretKey
          @session_key = response.session.sessionKey
          @offline_token = response.session.respond_to?(:offlineToken) ? response.session.offlineToken : nil
          true
        else
          false
        end
      end

      instance_methods.each do |method|
        module_function method.to_sym
      end
    end

    instance_methods.each do |method|
      module_function method.to_sym
    end
  end

  module Connect
    attr_accessor :wsdl
    attr_accessor :driver

    def self.request(method, options = {})
      unless Zanox::API.secret_key.nil?
        timestamp = Zanox::API.get_timestamp
        nonce = Zanox::API.generate_nonce
        signature = Zanox::API.create_signature(Zanox::API.secret_key, "connectservice" + method.delete("_").downcase + timestamp + nonce)
        options.merge!(timestamp: timestamp, nonce: nonce, signature: signature)
      end
      @wsdl = "https://auth.zanox-affiliate.de/wsdl/2010-02-01" unless @wsdl
      @driver = Savon.client(wsdl: @wsdl)
      @driver.ssl_verify_mode = OpenSSL::SSL::VERIFY_NONE if $DEBUG
      @driver.call(method.to_sym, message: options).hash
    rescue Exception => e
      puts
      puts "ERROR"
      puts e.message
      nil
    end

    def self.ui_url
      Zanox::Connect.request("getUiUrl", connectId: Zanox::API::Session.connect_id, sessionKey: Zanox::API::Session.session_key)
    end

    instance_methods.each do |method|
      module_function method.to_sym
    end
  end

  module Item
    attr_accessor :id

    def new(item = nil)
      item.extend(self)
      item.id = item.xmlattr_id
      return item
    end

    def find_every(options)
      items = []
      class_name = name.split("::").last

      api_method = "get" + pluralize if respond_to?(:pluralize)

      if class_name == "Program" && options.key?(:adspaceId)
        raise "Zanox::Program.find(:adspaceId) is no longer supported. Please use the new Zanox::ProgramApplication.find(:adspaceId) instead."
      end

      response = Zanox::API.request(api_method, options)

      # class_name.sub!(/\b\w/) { $&.downcase }

      # m1_name = (class_name+'Items').to_sym
      # m2_name = (class_name+'Item').to_sym

      # if(response.respond_to?(m1_name) && response.items!=0)
      #   items_object = response.method(m1_name).call
      #   if(items_object.respond_to?(m2_name))
      #     item_object = items_object.method(m2_name).call
      #     if(item_object.is_a?(Array))
      #       item_list = item_object
      #     else
      #       item_list = [item_object]
      #     end
      #     [*item_object].each do |item|
      #       items.push self.new(item)
      #     end
      #   end
      # else
      #   # found nothing handling
      #   #return items
      # end

      # return items

      response
    end

    def find_other(args, options)
      #      binding.pry
      # TODO refactor
      ids = []
      queries = []
      items = []
      args.each do |arg|
        is_key?(arg) ? ids.push(arg) : queries.push(arg)
      end

      puts "found ids: " + ids.to_s if $DEBUG
      puts "found query strings: " + queries.to_s if $DEBUG

      class_name = name.split("::").last
      class_name = "_#{class_name.downcase}"

      if ids.size == 0 && queries.size == 0
        api_method = "get" + class_name
        response = Zanox::API.request(api_method, options)
        item_method = (class_name + "Item").to_sym
        if response.respond_to?(item_method)
          item = new(response.method(item_method).call)
          items.push item
        end
      end

      if ids.size > 0
        api_method = "get" + class_name

        ids.each do |id|
          options[key_symbol] = id
          response = Zanox::API.request(api_method, options)

          item_method = (class_name + "Item").to_sym

          if response.respond_to?(item_method)
            item = new(response.method(item_method).call)
            items.push item
          end
        end
      end

      if queries.size > 0
        api_method = "search" + pluralize
        queries.each do |query|
          options[:query] = query
          response = Zanox::API.request(api_method, options)
          m1_name = (class_name + "Items").to_sym
          m2_name = (class_name + "Item").to_sym

          next unless response.respond_to?(m1_name)
          items_object = response.method(m1_name).call
          next unless items_object.respond_to?(m2_name)
          item_object = items_object.method(m2_name).call
          item_list = if item_object.is_a?(Array)
                        item_object
                      else
                        [item_object]
                      end
          [*item_object].each do |item|
            items.push new(item)
          end
        end
      end

      return items
    end

    def find(*args)
      item_name = name.split("::").last
      options = args.last.is_a?(Hash) ? args.pop : {}

      puts "Arguments: " + args.inspect if $DEBUG
      puts "Options: " + options.inspect if $DEBUG

      if item_name == "Profile"
        find_other(args, options)
      else
        case args.first
        when :all then find_every(options)
        when nil  then find_every(options)
        else find_other(args, options)
        end
      end
    end
  end

  module Profile
    include Item
    extend  Item
  end

  module Program
    include Item
    extend  Item

    def self.key_symbol
      :programId
    end

    def self.pluralize
      "_programs"
    end

    def self.is_key?(id)
      id.to_s[/^[0-9]{1,8}$/] ? true : false
    end
  end

  module Admedium
    include Item
    extend  Item

    def self.key_symbol
      :admediumId
    end

    def self.pluralize
      "_admedia"
    end

    def self.is_key?(id)
      id.to_s[/^[0-9]{2,10}$/] ? true : false
    end
  end

  module Product
    include Item
    extend  Item

    def self.key_symbol
      :zupId
    end

    def self.pluralize
      "_products"
    end

    def self.is_key?(id)
      id.to_s[/[0-9A-Fa-f]{32}/] ? true : false
    end
  end

  module Adspace
    include Item
    extend Item

    def self.key_symbol
      :adspaceId
    end

    def self.pluralize
      "_adspaces"
    end

    def self.is_key?(id)
      id.to_s[/^[0-9]{2,10}$/] ? true : false
    end
  end

  module Sale
    include Item
    extend  Item

    def self.key_symbol
      :saleId
    end

    def self.pluralize
      "_sales"
    end

    def self.is_key?(id)
      id.to_s[/[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+/] ? true : false
    end
  end

  module Lead
    include Item
    extend  Item

    def self.key_symbol
      :leadId
    end

    def self.pluralize
      "_leads"
    end

    def self.is_key?(id)
      id.to_s[/[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+[-]{1}[0-9a-f]+/] ? true : false
    end
  end

  module MediaSlot
    include Item
    extend  Item

    def self.key_symbol
      :mediaSlotId
    end

    def self.pluralize
      "_media_slots"
    end

    def self.is_key?(id)
      id.to_s[/[0-9A-Fa-f]{20}/] ? true : false
    end
  end

  module Application
    include Item
    extend  Item

    def self.key_symbol
      :applicationId
    end

    def self.pluralize
      "_applications"
    end

    def self.is_key?(id)
      id.to_s[/[0-9A-Fa-f]{20}/] ? true : false
    end
  end

  module ProgramApplication
    include Item
    extend Item

    def self.key_symbol
      :programApplicationId
    end

    def self.pluralize
      "_program_applications"
    end

    def self.is_key?(id)
      id.to_s[/^[0-9]{2,10}$/] ? true : false
    end
  end

  module ReportBasic
    include Item
    extend Item

    def self.key_symbol
      :reportBasicId
    end

    def self.pluralize
      "_report_basic"
    end
  end
end
