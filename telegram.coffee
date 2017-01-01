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
      @framework.ruleManager.addActionProvider(new TelegramActionProvider(@framework, @config))
      
      deviceConfigDef = require("./telegram-device-config-schema")
      @framework.deviceManager.registerDeviceClass("TelegramReceiverDevice", {
        configDef: deviceConfigDef.TelegramReceiverDevice, 
        createCallback: (config, lastState) => new TelegramReceiverDevice(config, lastState, @framework, @config)
      })
    
  
  
  class TelegramReceiverDevice extends env.devices.Device
    
    constructor: (@config, lastState, @framework, @pluginConfig) ->
      @id = @config.id
      @name = @config.name
      @attributes = {}
      @_exprChangeListeners = []
      @_vars = @framework.variableManager
      
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
          
      super()
      env.logger.info "device config: ", @config
      env.logger.info "plugin config: ", @pluginConfig
      #env.logger.info "attributes var: ", @attribute
      
      listener = new Listener(@pluginConfig.apiToken, @config, @framework)
      listener.start()
        
    destroy: ->
      @listener.disconnect() 
      super()
  
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
    
    parseAction: (input, context) =>
      message = null
      match = null
      @m1 = null
      @m2 = null
      
      m = M(input, context)
      m.or([
        ( (@m1) =>
          # Legacy Action matcher, remove in future version
          #
          @m1.match('send telegram ', (@m1) =>
            message = new MessageFactory('text', {token: @config.apiToken})
            
            i = 0
            more = true
            all = @config.recipients.map( (r) => r.name + ' ')
            while more and i < all.length
              more = false if @m1.getRemainingInput().charAt(0) is '"' or null
          
              @m1.match(all, (@m1, r) =>
                message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.name is r.trim
              )
              i += 1
          )
          @m1.matchStringWithVars( (@m1, content) =>
            message.addContent(new Content(@framework, content))
            match = @m1.getFullMatch()
          )
        ),
        ( (@m2) =>
          # New style Action matcher
          #
          # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
          @m2.match('send ')
            .match(MessageFactory.getTypes().map( (t) => t + ' '), (@m2, type) => 
              message = new MessageFactory(type.trim(), {token: @config.apiToken})
            )
            .match('telegram ')
            .match('to ', optional: yes, (@m2) =>
            
              i = 0
              more = true
              all = @config.recipients.map( (r) => r.name + ' ')
              while more and i < all.length
                more = false if @m2.getRemainingInput().charAt(0) is '"' or null
                 
                @m2.match(all, (@m2, r) =>
                  message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.name is r.trim()
                )
                i += 1
            )
          @m2.matchStringWithVars( (@m2, content) =>
            message.addContent(new Content(@framework, content))
            match = @m2.getFullMatch()
          )
        )
      ])
      
      
        
      env.logger.info "message:  ", message
      if match?
        if message.recipients.length < 1
          message.addRecipient(new Recipient(obj)) for obj in @config.recipients
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
        return @message.send()
    
  class Listener
  
    constructor: (token, config, @framework) ->
      @commands = config.commands
      options = {
        token: token
        pooling: {
          interval: config.interval
          timeout: config.timeout
          limit: config.limit
          retryTimeout: config.retryTimeout
        }
      }
      @client = new BotClient(options)
      
    start: () =>
      @client.botConnect()
    
      for command in @commands
        do (command) =>
          @client.addListener(command.request,{variable: command.variable, value: command.value})
    
    stop: () =>
      @client.botDisconnect()
    
    restart: () =>
      @stop()
      @start()
      
    destruct: () =>
      @stop()
      return
  
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
      #env.logger.info @client
      #return @client
    
    botConnect: () =>
      @client.connect()
    
    botDisconnect: () =>
      @client.disconnect()
    
    addListener: (@request, @action = {}) =>
      @client.on ('/' + @request), (msg) =>
        env.logger.info msg
        if @action.variable? && @action.value?
          # process request
          @client.sendMessage(msg.from.id, @action.variable + " set to " + @action.value)
  
  ###
  # Message SuperClass
  #
  # .processResult(method: Message Subclass send method) => Promise
  #
  ####
  class Message extends BotClient
  
    constructor: (options) ->
      super(options)
      @recipients = []
      @content = null
      
    processResult: (method, recipient) =>
        method.then ((response) =>
          env.logger.info __("Telegram to %s successfully sent", recipient)
          return Promise.resolve 
        ), (err) =>
          env.logger.error __("Sending Telegram to %s failed, reason: %s", recipient, err.description)
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
   
    send: () =>
      results = []
      return new Promise((resolve, reject) =>
        @content.get().then( (message) =>
          results = @recipients.map( (r) => @processResult(@client.sendMessage(r.getId(), message), r.getName()))
          Promise.some(results, results.length).then( (result) =>
            resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.error "Message was NOT sent to all recipients"
          )
        )
      )
     
  ###
  # VideoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends Message
  
    send: () =>
      results = []
      return new Promise((resolve, reject) =>
        @content.get().then( (file) =>
          if fs.existsSync(file)
            results = @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), r.getName()))
            Promise.some(results, results.length).then( (result) =>
              resolve
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          else
            @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
        )
      )
      
  ###
  # AudioMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class AudioMessage extends Message
    
    send: () =>
      results = []
      return new Promise((resolve, reject) =>
        @content.get().then( (file) =>
          if fs.existsSync(file)
            results = @recipients.map( (r) => @processResult(@client.sendAudio(r.getId(), file), r.getName()))
            Promise.some(results, results.length).then( (result) =>
              resolve
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          else
            @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
        )
      )
      
  ###
  # PhotoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class PhotoMessage extends Message
    
    send: () =>
      results = []
      return new Promise((resolve, reject) =>
        @content.get().then( (file) =>
          if fs.existsSync(file)
            results = @recipients.map( (r) => @processResult(@client.sendPhoto(r.getId(), file), r.getName()))
            Promise.some(results, results.length).then( (result) =>
              resolve
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          else
            @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
        )
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
  
  ###
  #  Content Class
  #
  # .get() => (content:string)
  # .parse(content: string) => (Promise(resolve, reject)
  #
  ###
  class Content
    
    constructor: (@framework, @input) ->
        @base = commons.base @, "TelegramActionHandler"
        
    get: () =>
      return new Promise((resolve, reject) =>
        @framework.variableManager.evaluateStringExpression(@input).then( (content) =>
          resolve content
        ).catch( (error) =>
          reject error
        )
      ).catch((error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
    
    set: (@input) ->
      
  plugin = new Telegram()
  return plugin