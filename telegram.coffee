module.exports = (env) ->

  Promise = env.require 'bluebird'
  fs = require('fs')
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require('telebot');
  cassert = env.require 'cassert'
  events = require 'events'
  M = env.matcher
  
  class Telegram extends env.plugins.Plugin
    
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
          if oldChatId.oldId() isnt null
            if oldChatId.migrated() is null
              env.logger.info "old userChatId: " + oldChatId.oldId() + " found, migrating..."
              oldChatId = {name: oldChatId.name, userChatId: oldChatId.oldId(), enabled: oldChatId.enabled}
              @config.recipients.push oldChatId
            else
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
        createCallback: (config, lastState) => new TelegramReceiverDevice(config, lastState, @framework)
      })
      
    evaluateStringExpression: (value) ->
      return @framework.variableManager.evaluateStringExpression(value)
    
    parseVariableExpression: (value) ->
      return @framework.variableManager.parseVariableExpression(value)
      
    getToken: () ->
      return @config.apiToken
    
    getRecipient: (id) =>
      for r in @config.recipients
        if r.userChatId is id
          return new Recipient(r)
      return false
    
    getSender: (id) =>
      return @getRecipient(id)
      
    getConfig: () =>
      return @config
    
    getDeviceById: (id) =>
      return @framework.deviceManager.getDeviceById(id)
      
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
        .match('telegram received ')
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
    constructor: (framework, @command) ->
      super()

    setup: ->
      TelegramPlugin.registerCmd this
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> "#{@command}"

    destroy: ->
      TelegramPlugin.deregisterCmd this
      super()
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
      
    parseAction: (input, context) =>
      message = null
      match = null
      
      # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
      @m1 = M(input, context)
      @m1.match('send ')
        .match(MessageFactory.getTypes().map( (t) => t + ' '), (@m1, type) => 
          message = new MessageFactory(type.trim())
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
      @m1.matchStringWithVars( (@m1, expr) =>
        @framework.variableManager.evaluateStringExpression(expr).then( (content) =>
          message.addContent(new Content(content))
        )
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
        client = new BotClient({token: TelegramPlugin.getToken()})
        client.sendMessage(@message, true)
  
  class TelegramReceiverDevice extends env.devices.Device
    
    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name
      super()
      
      @client = new BotClient({
        token: TelegramPlugin.getToken()
        polling: {
          interval: @config.interval
          timeout: @config.timeout
          limit: @config.limit
          retryTimeout: @config.retryTimeout
        }
      })
      
      @listener = new Listener(@id)
      @client.startListener(@listener)
      
      TelegramPlugin.on('cmdRegistered', (cmd) =>
        @listener.addRequest(cmd)
      )
      TelegramPlugin.on('cmdDeregistered', (cmd) =>
        @listener.removeRequest(cmd)
      )
      
    destroy: ->
      @client.stopListener(@listener) 
      super()
  
  
  class Listener
  
    constructor: (id) ->
      @id = id
      @client = null
      @authenticated = []
      @requests = []
      
      @requests = [{
          request: "help"
          type: "base"
          action: -> return null
          protected: false
          response: (msg) =>
            text = "Default commands: \n"
            for req in @requests
              if req.type is "base"
                text += "\t" + req.request
                if req.request is "get device"
                  text += " <device name | device id>"
                text += "\n"
            text += "\nRule commands: \n"
            for req in @requests
              if req.type is "rule"
                text += "\t" + req.request + "\n"
            return text
        },
        {
          request: "execute", 
          action: => 
            env.logger.warn "auth_error", "request 'execute' received; This is not allowed for security reasons" # It's a trap !!
            return null
          protected: false
          response: (msg) ->
            text = "request 'execute' received; This is not allowed for security reasons"
            return text
        },
        {
          request: "list devices"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) ->
            devices = TelegramPlugin.getDevices()
            text = 'Devices :\n'
            for dev in devices
              text += '\tName: ' + dev.name + "\tID: " + dev.id + "\n\n"
            return text
        },
        {
          request: "get device"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) => 
            obj = msg.split("device", 4)
            devices = TelegramPlugin.getDevices()
            for dev in devices
              if ( obj[1].substring(1) == dev.id.toLowerCase() ) or ( obj[1].substring(1) == dev.name.toLowerCase() )
                text = 'Name: ' + dev.name + " \tID: " + dev.id + " \tType: " +  dev.constructor.name + "\n"
                for name of dev.attributes
                  text += '\t\t' + name.charAt(0).toUpperCase() + name.slice(1) + ": " + dev.getLastAttributeValue(name) + "\n\n"
                message.addContent(new Content(text))
                return message
            return text
        }]
      
    start: (@client) =>
      @client.connect()
      @enableRequests()
      
    enableRequests: () =>
      @client.on('text', (msg) =>
        sender = TelegramPlugin.getSender(msg.from.id.toString())
        
        # auth logic
        if !sender.isAdmin() # Lord Vader force-chokes you !!
          env.logger.warn "auth_denied", sender.getName() + " is not authorized. Terminating request"
          return
        
        date = new Date()
        client = new BotClient({token: TelegramPlugin.getToken()})
        response = new MessageFactory("text")
        response.addRecipient(sender)
        
        if TelegramPlugin.getDeviceById(@id).config.secret is msg.text # Face Vader you must!
          @authenticated.push {id: sender.getId(), time: date.getTime()}
          response.addContent(new Content("Passcode correct, timeout set to " + TelegramPlugin.getDeviceById(@id).config.auth_timeout + " minutes. You can now issue requests"))
          client.sendMessage(response)
          env.logger.info "auth_success", sender.getName() + " successfully authenticated"
          return
        
        for auth in @authenticated
          if auth.id is sender.getId()
            if auth.time < (date.getTime()-(TelegramPlugin.getDeviceById(@id).config.auth_timeout*60000)) # You were carbon frozen for too long, Solo! Solo! Too Nakma Noya Solo!
              sender.setAuthenticated(false)
            else
              sender.setAuthenticated(true)
        
        
        request = msg.text.toLowerCase()
        match = false
        # command logic
        if sender.isAuthenticated()  # May the force be with you
          for req in @requests
            if req.request.toLowerCase() is request.slice(0, req.request.length) # test request against base commands and 'receive "command"' predicate in ruleset
              req.action()
              response.addContent(new Content(req.response(request)))
              client.sendMessage(response)
              match = true
              break
          
          if !match
            for act in TelegramPlugin.getActionProviders()
              context = createDummyParseContext()
              han = act.parseAction(request, context) # test if request is a valid action, e.g. "turn on switch-room1"
              if han?
                han.actionHandler.executeAction()
                response.addContent(new Content("Request '" + request + "' executed"))
                client.sendMessage(response)
                match = true
                break
          
          if !match
            response.addContent(new Content("'" + request + "' is not a valid request"))
            client.sendMessage(response)
          
          env.logger.info "Request '" + request + "' received from " + sender.getName()
          return
        else # Vader face you must
          response.addContent(new Content("Please provide the passcode first and reissue your request after"))
          client.sendMessage(response)
      )
    
    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)
      
    addRequest: (req) =>
      obj = {
        request: req.getCommand()
        action: (msg) => req.emit('change', 'event')
        protected: true
        type: "rule"
        response: (msg) => 
          return "Rule condition '" + obj.request + "' triggered"
      }
      @requests.push obj
      env.logger.debug "added command ", obj.request
          
    changeRequest: (id, request) =>
      
    removeRequest: (req) =>
      @commands.splice(@requests.indexOf(req),1)
      
    stop: (@client) =>
      @client.disconnect()
    
  class BotClient
    
    constructor: (options) ->
      @base = commons.base @, "TelegramActionHandler"
      @client = new TelegramBotClient(options)
    
    stopListener: (listener) =>
      listener.stop(@client)
    
    startListener: (listener) =>
      listener.start(@client)
    
    sendMessage: (message, log) =>
      return new Promise( (resolve, reject) =>
        message.send(@client).then( (results) =>
          Promise.some(results, results.length).then( (result) =>
            resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.error "Message was NOT sent to all recipients"
          )
        ).catch( (err) =>
          @base.error err
        )
      )
      
  class Logger
    types = {
      debug: env.logger.debug
      restricted: env.logger.warn
      auth_denied: env.logger.warn  
    }
    
    constructor = (type, msg) ->
      types[type] msg
    
  class Message
  
    constructor: (options) ->
      @recipients = []
      @content = null
    
    processResult: (method, message, recipient, log  = false) =>
        method.then ((response) =>
          log_msg = __("Sending Telegram \"%s\" to %s: success", message, recipient)
          if !log
            env.logger.debug log_msg
          else
            env.logger.info log_msg
          return Promise.resolve "success"
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to %s: failed; reason: %s", message, recipient, err.description)
          return Promise.reject err
    
    addRecipient: (recipient) =>
      @recipients.push recipient
    
    addContent: (content) =>
      @content = content
    
    messageParts: (msg) =>
      return msg.match(/[\s\S]{1,2048}/g)
      
  class TextMessage extends Message
   
    send: (@client, log) =>
      @content.getString()
        .then( (message) =>
          return @recipients.map( (r) =>
            @messageParts(message).map( (part) => 
              @processResult(@client.sendMessage(r.getId(), part), part, r.getName(), log)
            )
          )   
        ).catch( (err) =>
          Promise.reject "Cannot send text message via Telegram", err
        )
        
  class VideoMessage extends Message
  
    send: (@client, log) =>
      @content.getMedia()
        .then( (file) =>
          return @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), file, r.getName(), log))
        ).catch( (err) =>
          Promise.reject "Cannot send media via Telegram", err
        )
      
  class AudioMessage extends Message
    
    send: (@client, log) =>
      @content.getMedia()
        .then( (file) =>
          return @recipients.map( (r) => @processResult(@client.sendAudio(r.getId(), file), file, r.getName(), log))
        ).catch((err) =>
          Promise.reject "Cannot send media via Telegram", err
        )
      
  class PhotoMessage extends Message
    
    send: (@client, log) =>
      @content.getMedia()
        .then( (file) =>
            return @recipients.map( (r) => @processResult(@client.sendPhoto(r.getId(), file), r.getName(), log))
        ).catch( (err) =>
            Promise.reject "Cannot send media via Telegram", err
        )
      
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
       
  class Recipient
    
    constructor: (recipient) ->
      @id = recipient.userChatId
      @name = recipient.name
      @enabled = recipient.enabled or false
      @admin = recipient.admin or false
      @cleared = false
      @authenticated = false
      
    getId: () =>
      return @id
      
    getName: () =>
      return @name
      
    isAdmin: () =>
      return @admin
        
    isEnabled: () =>
      return @enabled
    
    isAuthorized: () =>
      if @isEnabled()
        return @isAdmin()
      return false
    
    isAuthenticated: () =>
      return @authenticated
      
    setAuthenticated: (val) =>
      @authenticated = val
    
  class RecipientCollection
    constructor: (load = false) ->
      @collection = []
      if load
        @getAll()
    
    add: (recipient) =>
        @collection.push recipient
    
    getAll: () ->
      config = TelegramPlugin.getConfig()
      env.logger.debug config
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
    
  class Content
    
    constructor: (input) ->
      @input = input
      @base = commons.base @, "TelegramContent"
   
    set: (@input) ->
    
    getString: () =>
      if typeof @input is "string"
        Promise.resolve @input
      else
        Promise.reject __("\"%s\" is not a string", @input)

    getMedia: () ->
      @getString()
        .then( (file) =>
          if !fs.existsSync(file)
            err = __("File: \"%s\" does not exist", file)
            @base.error err
            Promise.reject err
          else
            Promise.resolve file
        ).catch( (err) =>
          @base.error err
          Promise.reject err
        )
    
  module.exports.TelegramActionHandler = TelegramActionHandler
  TelegramPlugin = new Telegram()
  return TelegramPlugin