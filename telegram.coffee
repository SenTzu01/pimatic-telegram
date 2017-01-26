module.exports = (env) ->

  Promise = env.require 'bluebird'
  
  commons = require('pimatic-plugin-commons')(env)
  cassert = env.require 'cassert'
  events = require 'events'
  M = env.matcher
  Listener = require('./lib/listener')(env)
  BotClient = require('./lib/botclient')(env)
  MessageFactory = require('./lib/messages')(env)
  ContentFactory = require('./lib/content')(env)
  Recipient = require('./lib/recipient')
  
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
      
      
      @framework.on('deviceAdded', (device) =>
        @reparsePredicates(device)
      )
      @framework.on('deviceChanged', (device) => # re-add predicate actions to listener on TelegramReceiverDevice config changes
        @reparsePredicates(device)
      )
    
    reparsePredicates: (device) =>
      if device instanceof TelegramReceiverDevice
          for rule in @framework.ruleManager.getRules()
            for predicate in rule.predicates
              if predicate.handler instanceof TelegramPredicateHandler
                  @registerCmd(predicate.handler)
    
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
        message.addContent(new ContentFactory(type, expr, TelegramPlugin))
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
      @_state = lastState?.state?.value or @config.stateStartup
      
      super()
      @listener = new Listener(@id, TelegramPlugin)
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
      TelegramPlugin.removeAllListeners('cmdRegistered')
      TelegramPlugin.removeAllListeners('cmdDeregistered')
      @stopListener()
      super()
    
  TelegramPlugin = new Telegram()
  return TelegramPlugin