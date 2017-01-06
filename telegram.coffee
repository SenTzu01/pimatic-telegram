module.exports = (env) ->

  Promise = env.require 'bluebird'
  fs = require('fs')
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require('telebot');
  cassert = env.require 'cassert'
  events = require 'events'
  M = env.matcher
  
  
  class Telegram extends env.plugins.Plugin
    
    #cmdMap = []
    
    migrateMainChatId: (@framework, @config) =>
      oldChatId = {
        name: "MainRecipient"
        enabled: true
        
        oldId: => 
          id = null
          if @config.hasOwnProperty('userChatId')
            id = @config.userChatId
          return id
        
        migrated: =>
          found = null
          found = recipient.userChatId for recipient in @config.recipients when recipient.userChatId is @config.userChatId
          return found
          
        migrate: =>
          if oldChatId.migrated() is null and oldChatId.oldId() isnt null
            env.logger.info "old userChatId: " + oldChatId.oldId() + " found, migrating..."
            oldChatId = {name: oldChatId.name, userChatId: oldChatId.oldId(), enabled: oldChatId.enabled}
            @config.recipients.push oldChatId
            delete @config.userChatId if @config.hasOwnProperty('userChatId')
            @framework.pluginManager.updatePluginConfig(@config.plugin, @config)
      }
      oldChatId.migrate()
      
    init: (app, @framework, @config) =>
      
      
      @migrateMainChatId(@framework, @config)
      
      @framework.ruleManager.addPredicateProvider(new TelegramPredicateProvider(@framework, @config))
      @framework.ruleManager.addActionProvider(new TelegramActionProvider(@framework, @config))
      
      
      deviceConfigDef = require("./telegram-device-config-schema")
      @framework.deviceManager.registerDeviceClass("TelegramReceiverDevice", {
        configDef: deviceConfigDef.TelegramReceiverDevice, 
        createCallback: (config, lastState) => new TelegramReceiverDevice(config, lastState, @framework, @config)
      })
      
    evaluateStringExpression: (value) ->
      return @framework.variableManager.evaluateStringExpression(value)
    
    getConfig: () =>
      return @config
    
    getDeviceClasses: () =>
      return @framework.deviceManager.getDeviceClasses()
    
    getDevices: () ->
      return @framework.deviceManager.getDevices()
    
    getActionProviders: () =>
      return @framework.ruleManager.actionProviders
      
    registerCmd: (@cmd) =>
      env.logger.debug "Register command: #{@cmd.getCommand()}"
      @emit "cmdRegistered", @cmd
    
    deregisterCmd: (@cmd) =>
      env.logger.debug "Deregister command: #{@cmd.getCommand()}"
      @emit "cmdDeregistered", @cmd
      
    
  
  class TelegramPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      fullMatch = null
      nextInput = null
      recCommand = null

      setCommand = (m, tokens) => recCommand = tokens

      m = M(input, context)
        .match('received ')
        .matchString(setCommand)

      if m.hadMatch()
        fullMatch = m.getFullMatch()
        nextInput = m.getRemainingInput()

      if fullMatch?
        cassert typeof recCommand is "string"
        return {
          token: fullMatch
          nextInput: input.substring(fullMatch.length)
          predicateHandler: new TelegramPredicateHandler(@framework, recCommand)
        }
      else return null

  class TelegramPredicateHandler extends env.predicates.PredicateHandler
    constructor: (framework, @Command) ->
      super()

    setup: ->
      TelegramPlugin.registerCmd this
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> "#{@Command}"

    destroy: ->
      TelegramPlugin.deregisterCmd this
      super()
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
      
    parseAction: (input, context) =>
      message = null
      match = null
      
      # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
      m = M(input, context)
      m.match('send ')
        .match(MessageFactory.getTypes().map( (t) => t + ' '), (@m1, type) => 
          message = new MessageFactory(type.trim(), {token: @config.apiToken})
        )
        .match('telegram ')
        .match('to ', optional: yes, (@m1) =>
          i = 0
          more = true
          all = @config.recipients.map( (r) => r.name + ' ')
          while more and i < all.length
            more = false if @m1.getRemainingInput().charAt(0) is '"' or null
             
            @m1.match(all, (@m1, r) =>
              message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.name is r.trim() and obj.enabled
            )
            i += 1
        )
      @m1.matchStringWithVars( (@m1, content) =>
        message.addContent(new Content(content))
        match = @m1.getFullMatch()
      )
      
      
      if match?
        if message.recipients.length < 1
          message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.enabled
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @config, message)
        }
      else    
        return null
        
  class TelegramActionHandler extends env.actions.ActionHandler
  
    constructor: (@framework, @config, @message) ->
      
    executeAction: (simulate) =>
      if simulate
        return __("would send telegram \"%s\"", @message.content.get())
      else
        client = new BotClient({token: @config.apiToken})
        return client.sendMessage(@message)
  
  class TelegramReceiverDevice extends env.devices.Device
    
    constructor: (@config, lastState, @framework, @pluginConfig) ->
      @id = @config.id
      @name = @config.name
      #@attributes = {}
      #@_exprChangeListeners = []
      #@_vars = @framework.variableManager
      
      ###
      for command in @config.commands 
        do (command) =>
          name = command.name
          
          if @attributes[name]?
            throw new Error(
              "Two commands with the same name in TelegramReceiverDevice config \"#{name}\""
            )

          @attributes[name] = {
            description: name
            label: (if command.label? then command.label else "$#{name}")
            type: "string"
          }
          
          if command.request? and command.request.length > 0
            @attributes[name].request = command.request
          if command.variable? and command.variable.length > 0
            @attributes[name].variable = command.variable
          if command.value? and command.value.length > 0
            @attributes[name].value = command.value
          if typeof command.enabled is "boolean"
            @attributes[name].enabled = command.enabled
          
          getValue = ( (varsInEvaluation) =>
            # wait till variableManager is ready
            return @_vars.waitForInit().then( (val) =>
              if val isnt @_attributesMeta[name].value
                @emit name, val
              return val
            )
          )
          @_createGetter(name, getValue)
       ###   
      super()
      
      @client = new BotClient({
        token: @pluginConfig.apiToken
        pooling: {
          interval: @config.interval
          timeout: @config.timeout
          limit: @config.limit
          retryTimeout: @config.retryTimeout
        }
      })
      @listener = new Listener(@config.commands)
      @client.startListener(@listener)
      
      TelegramPlugin.on('cmdRegistered', (cmd) =>
        @listener.addCommand(cmd)
      )
      TelegramPlugin.on('cmdDeregistered', (cmd) =>
        @listener.removeCommand(cmd)
      )
      
    destroy: ->
      @client.stopListener(@listener) 
      super()
  
  ###
  # Listener Class
  #
  # .prototype(token: string, deviceconfig: object, framework: object ) => (Listener object)
  #
  # .start() => 
  # .stop() =>
  # .restart() =>
  #
  ###
  class Listener
  
    constructor: (@commands) ->
      @client = null
      @commands = [{
          command: "help",
          action: -> return null
          protected: false
          type: "base"
          response: (msg) =>
            text = "Default commands: \n"
            for cmd in @commands
              if cmd.type is "base"
                text += "\t" + cmd.command + "\n"
            text += "\nRule commands: \n"
            for cmd in @commands
              if cmd.type is "rule"
                text += "\t" + cmd.command + "\n"
            return text
        },
        {
          command: "execute", 
          action: -> return null # defined as an empty action for security reasons
          protected: false
          type: "restricted",
          response: (msg) ->
            text = "Command 'execute' received; This is not allowed for security reasons"
            env.logger.error text
            return text
        },
        {
          command: "list devices"
          action: -> return null
          protected: true
          type: "base"
          response: (msg) -> 
            devices = TelegramPlugin.getDevices()
            text = 'Devices :\n'
            for dev in devices
              text += '\tName: ' + dev.name + "\t\tID: " + dev.id + "\t\tType: " +  dev.constructor.name + "\n"
            return text
        },
        {
          command: "get all devices"
          action: -> return null
          protected: true
          type: "base"
          response: (msg) -> 
            devices = TelegramPlugin.getDevices()
            text = 'Devices :\n'
            for dev in devices
              text += 'Name: ' + dev.name + " \t\tID: " + dev.id + " \t\tType: " +  dev.constructor.name + "\n"
              for name of dev.attributes
                text += '\t\t' + name + " " + dev.getLastAttributeValue(name) + "\n"
            return text
        },
        {
          command: "get device"
          action: -> return null
          protected: true
          type: "base"
          response: (msg) => 
            obj = msg.split("device", 4)
            devices = TelegramPlugin.getDevices()
            for dev in devices
              if ( obj[1].substring(1) == dev.id.toLowerCase() ) or ( obj[1].substring(1) == dev.name.toLowerCase() )
                text = 'Name: ' + dev.name + " \t\tID: " + dev.id + " \t\tType: " +  dev.constructor.name + "\n"
                for name of dev.attributes
                  text += '\t\t' + name + " " + dev.getLastAttributeValue(name) + "\n"
                return text
            return "device not found"
        }]
      
    start: (@client) =>
      @client.connect()
      @listenForCommands()
      
    listenForCommands: () =>
      @client.on('text', (msg) =>
        match = false
        message = msg.text.toLowerCase()
        type = "base"
        name = senderName(msg.from)
        logRequest(type, "Received message: '" + msg.text + "'")
        
        for cmd in @commands
          if cmd.command.toLowerCase() is message.slice(0, cmd.command.length) # test request against base commands and 'receive "command"' predicate in ruleset
            
            # Add authorization logic here
            cmd.action()
            @client.sendMessage(msg.from.id, cmd.response(message), msg.message_id)
            type = cmd.type
            match = true
            break
        
        if !match
          for act in TelegramPlugin.getActionProviders()
            context = createDummyParseContext()
            han = act.parseAction(msg.text, context) # test if message is a valid action, e.g. "turn on switch-room1"
            if han?
              
              # Add authorization logic here
              han.actionHandler.executeAction()
              @client.sendMessage(msg.from.id, "Action '" + message + "' executed", msg.message_id)
              type = "action"
              match = true
              break
        
        if !match
          @client.sendMessage(msg.from.id, "'" + message + "' is not a valid command", msg.message_id)
          type = "base"
        
        logRequest(type, "Request '" + message + "' received from " + name)
        return
      )
    
    logRequest = (type, msg)->
      switch type
        when "base" then env.logger.debug msg
        when "restricted" then env.logger.error msg
        else env.logger.info msg
        
    senderName = (from) =>
      sender = null
      if from.first_name?
        sender = from.first_name
      else
        sender = from.username
        return sender
      if from.last_name?
        sender += " " + from.last_name
      return sender
    
    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)
      
    addCommand: (cmd) =>
      obj = {
        command: cmd.getCommand()
        action: (msg) => cmd.emit('change', 'event')
        protected: true
        type: "rule"
        response: (msg) => return "Rule condition '" + obj.command + "' triggered"
      }
      @commands.push obj
      env.logger.debug "added command ", obj.command
          
    changeCommand: (id, command) =>
      
    removeCommand: (cmd) =>
      @commands.splice(@commands.indexOf(cmd),1)
      
    stop: (@client) =>
      @client.disconnect()
  
  ###
  # BotClient Class
  #
  # .prototype(token: string) => (botclient object)
  #
  ###
  class BotClient
    
    constructor: (options) ->
      @base = commons.base @, "TelegramActionHandler"
      @client = new TelegramBotClient(options)
    
    stopListener: (listener) =>
      listener.stop(@client)
    
    startListener: (listener) =>
      listener.start(@client)
    
    sendMessage: (message) =>
      return new Promise( (resolve, reject) =>
        message.send(@client).then( (results) =>
          Promise.some(results, results.length).then( (result) =>
            resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.error "Message was NOT sent to all recipients"
          )
        )
      )
        
  ###
  # Message SuperClass
  #
  # .processResult(method: Message Subclass send method) => Promise
  #
  ####
  class Message
  
    constructor: (options) ->
      @recipients = []
      @content = null
    
    processResult: (method, message, recipient) =>
        method.then ((response) =>
          env.logger.info __("Telegram \"%s\" to %s successfully sent", message, recipient)
          return Promise.resolve "success"
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to %s failed, reason: %s", message, recipient, err.description)
          return Promise.reject err
    
    addRecipient: (recipient) =>
      @recipients.push recipient
    
    addContent: (content) =>
      @content = content
      
  ###
  # TextMessage Class
  #
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ####
  class TextMessage extends Message
   
    send: (@client) =>
      @content.get().then( (message) =>
        return @recipients.map( (r) => @processResult(@client.sendMessage(r.getId(), message), message, r.getName()))
      )
      
  ###
  # VideoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends Message
  
    send: (@client) =>
      @content.get().then( (file) =>
        if fs.existsSync(file)
          return @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), file, r.getName()))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
      )
      
  ###
  # AudioMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class AudioMessage extends Message
    
    send: (@client) =>
      @content.get().then( (file) =>
        if fs.existsSync(file)
          return @recipients.map( (r) => @processResult(@client.sendAudio(r.getId(), file), file, r.getName()))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
      )
      
  ###
  # PhotoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class PhotoMessage extends Message
    
    send: (@client) =>
      @content.get().then( (file) =>
        if fs.existsSync(file)
          return @recipients.map( (r) => @processResult(@client.sendPhoto(r.getId(), file), r.getName()))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
      )
      
  ###
  #
  # MessageFactory FactoryClass
  #
  # .getTypes() => (contentTypes: array)
  # .getInstance(type: string, opts: )
  #
  ###
  class MessageFactory
    types = {
      text: TextMessage
      video: VideoMessage
      audio: AudioMessage
      photo: PhotoMessage
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
  
  ###
  #  Recipient Class
  #
  # .prototype(name: string, id: string, enabled: bool) => (recipient object)
  # .getId() => (id:string)
  # .getName() => (name:string)
  # .isEnabled() => (enabled: bool)
  #
  ###
  class Recipient
    
    constructor: (recipient) ->
      @id = recipient.userChatId
      @name = recipient.name
      @enabled = recipient.enabled or false
      @admin = recipient.admin or false
      
    getId: () =>
      return @id
      
    getName: () =>
      return @name
      
    isSender: () =>
      return @admin
        
    isEnabled: () =>
      return @enabled
    
    isAuthorized: () =>
      if @isEnabled()
        return @isSender()
      return false
  
  class RecipientCollection
    constructor: (load = false) ->
      @collection = []
      if load
        @getAll()
    
    add: (recipient) =>
        @collection.push recipient
    
    getAll: () ->
      config = TelegramPlugin.getConfig()
      env.logger.info config
      @add(new Recipient(r)) for r in config.recipients
    
    getByName: (name) =>
      for r in @collection
        do (r) =>
          return r if r.name is name
      return false
    
    getById: (id) =>
      for r in @collection
        do (r) =>
          return r if r.userChatId is id
      return false
    
  ###
  #  Content Class
  #
  # .get() => (content:string)
  # .parse(content: string) => (Promise(resolve, reject)
  #
  ###
  class Content
    
    constructor: (@input) ->
      @base = commons.base @, "TelegramActionHandler"
        
    get: () =>
      return new Promise((resolve, reject) =>
        TelegramPlugin.evaluateStringExpression(@input).then( (content) =>
          resolve content
        ).catch( (error) =>
          reject error
        )
      ).catch((error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
    
    set: (@input) ->
      
  module.exports.TelegramActionHandler = TelegramActionHandler
  TelegramPlugin = new Telegram()
  return TelegramPlugin