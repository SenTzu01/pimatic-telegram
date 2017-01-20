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
      
      @framework.on('deviceChanged', (device) => # re-add predicate actions to listener on TelegramReceiverDevice config changes
        if device instanceof TelegramReceiverDevice
          for rule in @framework.ruleManager.getRules()
            for predicate in rule.predicates
              if predicate.handler instanceof TelegramPredicateHandler
                  @registerCmd(predicate.handler)
      )
      
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
        
    getFramework: () =>
      return @framework
      
    registerCmd: (@cmd) =>
      @emit "cmdRegistered", @cmd
    
    deregisterCmd: (@cmd) =>
      @emit "cmdDeregistered", @cmd
      
  class TelegramPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      match = null
      nextInput = null
      recCommand = null

      setCommand = (m, tokens) => recCommand = tokens

      m = M(input, context)
        .match('telegram received ')
        .matchString(setCommand)

      if m.hadMatch()
        match = m.getFullMatch()
        nextInput = m.getRemainingInput()

      if match?
        cassert typeof recCommand is "string"
        env.logger.debug "Rule matched: '", match, "' and passed to Predicate handler"
        return {
          token: match
          nextInput: input.substring(match.length)
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
      type = null
      message = null
      match = null
      
      # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
      @m1 = M(input, context)
      @m1.match('send ')
        .match(MessageFactory.getTypes().map( (t) => t + ' '), (@m1, t) =>
          type = t.trim()
          message = new MessageFactory(type)
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
        message.addContent(new ContentFactory(type, expr))
        match = @m1.getFullMatch()
      )
      
      if match?
        if message.recipients.length < 1
          message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.enabled
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
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
  
  class TelegramReceiverDevice extends env.devices.SwitchActuator
        
    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name
      @_state = lastState?.state?.value or on
      
      super()
      
      @listener = new Listener(@id)
      TelegramPlugin.on('cmdRegistered', (cmd) =>
        @listener.requestAdd(cmd)
      )
      TelegramPlugin.on('cmdDeregistered', (cmd) =>
        @listener.requestDelete(cmd)
      )
      
      @startListener() if @_state
          
    changeStateTo: (state) ->
      pending = []
      if @_state is state then return Promise.resolve true
      if state
        pending.push @startListener()
      else
        pending.push @stopListener()
        
      Promise.all(pending).then( =>
        @_setState(state)
      )
      
    startListener: () =>
      
      @client = new BotClient({
        token: TelegramPlugin.getToken()
        polling: {
          interval: @config.interval
          timeout: @config.timeout
          limit: @config.limit
          retryTimeout: @config.retryTimeout
        }
      })
      
      @client.startListener(@listener)
     
    stopListener: () =>
      @client.stopListener(@listener)
      
    destroy: ->
      @stopListener()
      super()
  
  class Listener
  
    constructor: (id) ->
      @id = id
      @client = null
      @authenticated = []
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
            env.logger.warn "'execute' request received; This is not allowed for security reasons" # It's a trap !!
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
                return text
            return "device not found"
        }]
      
      
      
    start: (@client) =>
      env.logger.info "Starting Telegram listener"
      @client.connect()
      @enableRequests()
    
    stop: (@client) =>
      env.logger.info "Stopping Telegram listener"
      @authenticated = []
      @client.disconnect()
      
    enableRequests: () =>
      @client.on('/*', (msg) =>
        env.logger.debug "Bot command received: ", msg
        client = new BotClient({token: TelegramPlugin.getToken()})
        response = new MessageFactory("text")
        response.addRecipient(TelegramPlugin.getSender(msg.from.id.toString()))
        response.addContent(new Content('Bot commands (/<cmd>) are not implemented'))
        client.sendMessage(response)
        return true
      )
      
      @client.on('text', (msg) =>
        return if msg.text.charAt(0) is '/'
        env.logger.debug "Request '", msg.text, "' received, processing..."
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
          response.addContent(new ContentFactory("text", "Passcode correct, timeout set to " + TelegramPlugin.getDeviceById(@id).config.auth_timeout + " minutes. You can now issue requests"))
          client.sendMessage(response)
          env.logger.info sender.getName() + " successfully authenticated"
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
          env.logger.info "Request '" + request + "' received from " + sender.getName()
          for req in @requests
            if req.request.toLowerCase() is request.slice(0, req.request.length) # test request against base commands and 'receive "command"' predicate in ruleset
              req.action()
              response.addContent(new ContentFactory("text", req.response(request)))
              client.sendMessage(response)
              match = true
              break
          
          if !match
            for act in TelegramPlugin.getActionProviders()
              context = createDummyParseContext()
              han = act.parseAction(request, context) # test if request is a valid action, e.g. "turn on switch-room1"
              if han?
                han.actionHandler.executeAction()
                response.addContent(new ContentFactory("text", "Request '" + request + "' executed"))
                client.sendMessage(response)
                match = true
                break
          
          if !match
            response.addContent(new ContentFactory("text", "'" + request + "' is not a valid request"))
            client.sendMessage(response)
            return
          return
        else # Vader face you must
          response.addContent(new ContentFactory("text", "Please provide the passcode first and reissue your request after"))
          client.sendMessage(response)
          return
      )
      
    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)
    
    requestAdd: (req) =>
      if !@requestIsRegistered(req)
        obj = {
          request: req.getCommand()
          action: (msg) => req.emit('change', 'event')
          protected: true
          type: "rule"
          response: (msg) => return "Rule condition '" + obj.request + "' triggered"
        }
        @requests.push obj
        env.logger.info "Listener enabled ruleset command: '", obj.request, "'"
          
    requestChange: (req) =>
      @requestDelete(req)
      @requestAdd(req)
      
    requestDelete: (req) =>
      i = -1 # additional iterator needed as array.indexOf(elem) does not work on array of objects
      for obj in @requests
        i++
        if obj.request is req.getCommand()
          @requests.splice(i,1)
          break
      env.logger.info "Listener disabled ruleset command: '", req.getCommand(), "' "
      
    requestIsRegistered: (req) =>
      reistered = false
      for obj in @requests
        if obj.request is req.getCommand()
          registered = true
          break
      return registered
    
  class BotClient
    
    constructor: (options) ->
      @base = commons.base @, "BotClient"
      @client = new TelegramBotClient(options)
    
    stopListener: (listener) =>
      listener.stop(@client)
    
    startListener: (listener) =>
      listener.start(@client)
    
    sendMessage: (message, log) =>
      return new Promise( (resolve, reject) =>
        message.send(@client, log).then( (results) =>
          Promise.some(results, results.length).then( (result) =>
            resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.rejectWithErrorString Promise.reject, "Message was NOT sent to all recipients"
          )
        ).catch( (err) =>
          @base.error err
        )
      )
        
  class Message
  
    constructor: (options) ->
      @recipients = []
      @content = null
      @client = null
      @base = commons.base @, "Message"
      
    
    processResult: (method, message, recipient, log  = false) =>
        method.then( (response) =>
          log_msg = __("[Message] Sending Telegram \"%s\" to %s: success", message, recipient)
          if !log
            env.logger.debug log_msg
          else
            env.logger.info log_msg
          return Promise.resolve
        ).catch( (err) =>
          env.logger.info err
          env.logger.error __("[Message] Sending Telegram \"%s\" to %s: failed; reason: %s", message, recipient, err.description)
          return Promise.reject err
          
        )
    
    addRecipient: (recipient) =>
      @recipients.push recipient
    
    addContent: (content) =>
      @content = content
      
  class TextMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "TextMessage"
      
    send: (@client, log) =>
      @content.get().then( (message) =>
        @recipients.map( (r) =>
          Promise.all(@sendMessageParts(message, r, log)).then( (result) =>
            return Promise.resolve
          ).catch( (err) =>
            return Promise.reject err
          )
        )   
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, "Unable to get content"
      )
    
    sendMessageParts: (message, recipient, log) =>
      parts = message.match(/[\s\S]{1,2048}/g)
      return parts.map( (part) => @processResult(@client.sendMessage(recipient.getId(), part), part, recipient.getName(), log) )
      
  class VideoMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "VideoMessage"
      
    send: (@client, log) =>
      @content.get().then( (file) =>
        return @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), file, r.getName(), log))
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, "Unable to send Video media"
      )
      
  class AudioMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "AudioMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
          return @recipients.map( (r) => @processResult(@client.sendAudio(r.getId(), file), file, r.getName(), log))
        ).catch((err) =>
          @base.rejectWithErrorString Promise.reject, "Unable to send Audio media"
        )
      
  class PhotoMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "PhotoMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
            return @recipients.map( (r) => @processResult(@client.sendPhoto(r.getId(), file), r.getName(), log))
        ).catch( (err) =>
            @base.rejectWithErrorString Promise.reject, "Unable to send Image media"
        )
  
  class LocationMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "LocationMessage"
      
    send: (@client) =>
      @content.get().then( (gps) =>
        return @recipients.map( (r) => @processResult(@client.sendLocation(r.getId(), [gps[0], gps[1]]), gps, r.getName()))
      ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, "Unable to send Location coordinates"
      )
            
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
        
  class Content
    
    constructor: (input) ->
      if typeof input is "string" or typeof input is "number"
        input = ['"' + input + '"']
      @input = input
      @base = commons.base @, "Content"
   
    set: (@input) ->
    
    get: () =>      
      TelegramPlugin.evaluateStringExpression(@input).then( (content) =>
        return Promise.resolve content
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, __("Could not parse \"%s\"", @input)
      )
      
  class TextContent extends Content
    constructor: (input) ->
      super(input)
      @base = commons.base @, "TextContent"
      
    get: () ->
      super()
      
  class MediaContent extends Content
    constructor: (input) ->
      super(input)
      @base = commons.base @, "MediaContent"
      
    get: () ->
      super()
        .then( (file) =>
          if !fs.existsSync(file)
            @base.rejectWithErrorString Promise.reject, __("File: \"%s\" does not exist", file)
          else
            Promise.resolve file
        ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, err
        )
  
  class LocationContent extends Content
    constructor: (input) ->
      super(input)
      @base = commons.base @, "LocationContent"
      
    get: () ->
      super()
        .then( (gps) =>
          coord = gps.split(';')
          if (!isNaN(coord[0]) && coord[0].toString().indexOf('.') isnt -1) and (!isNaN(coord[1]) && coord[1].toString().indexOf('.') isnt -1)
            Promise.resolve coord
          else
            @base.rejectWithErrorString Promise.reject, __("'%s' and '%s' are not valid GPS coordinates", coord[0], coord[1])
        ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, err
        )
   
  class MessageFactory
    types = {
      text: TextMessage
      video: VideoMessage
      audio: AudioMessage
      photo: PhotoMessage
      gps: LocationMessage
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
      
  class ContentFactory
    types = {
      text: TextContent
      video: MediaContent
      audio: MediaContent
      photo: MediaContent
      gps: LocationContent
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
      
  module.exports.TelegramActionHandler = TelegramActionHandler
  TelegramPlugin = new Telegram()
  return TelegramPlugin