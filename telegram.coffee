module.exports = (env) ->

  Promise = env.require 'bluebird'
  fs = require('fs')
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require('telebot');
  cassert = env.require 'cassert'
  events = require 'events'
  M = env.matcher
  _ = env.require 'lodash'
  assert = env.require 'cassert'
  
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
      @framework.ruleManager.addActionProvider(new TelegramReloadActionProvider(@framework, @config))
      
      deviceConfigDef = require("./telegram-device-config-schema")
      @framework.deviceManager.registerDeviceClass("TelegramReceiverDevice", {
        configDef: deviceConfigDef.TelegramReceiverDevice, 
        createCallback: (config, lastState) => new TelegramReceiverDevice(config, lastState)
      })
      
      @framework.on('deviceAdded', (device) =>
        @reparsePredicates(device) if device instanceof TelegramReceiverDevice
      )
      @framework.on('deviceChanged', (device) => # re-add predicate actions to listener on TelegramReceiverDevice config changes
        @reparsePredicates(device) if device instanceof TelegramReceiverDevice
      )
      
      @framework.ruleManager.on 'ruleAdded', @_ruleAddedEvent
      @framework.ruleManager.on 'ruleChanged', @_ruleAddedEvent
      
    _ruleAddedEvent: (rule) =>
      rule.predicates.map( (predicate) =>
        if predicate.handler instanceof TelegramPredicateHandler
          @emit('addedTelegramPredicate', rule)
      )
      
    reparsePredicates: (device) =>
      @emit 'changedTelegramReceiverDevice', device
      for rule in @framework.ruleManager.getRules()
        @_ruleAddedEvent(rule)
    
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
    
    updateRuleByString: (id, {name, ruleString, active, logging}) =>
      return new Promise((resolve, reject) =>
        @framework.ruleManager.updateRuleByString(id, {name, ruleString, active, logging})
        resolve(true)
      )

    executeAction: (actionString, simulate, logging) =>
      return @framework.ruleManager.executeAction(actionString, simulate, logging)
      
    getRuleById: (id) =>
      return @framework.ruleManager.getRuleById(id)

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
      recArgs = null
      withOptions = false
      
      setCommand = (m, tokens) => [recCommand, recArgs...] = tokens.split(' ')
      setOptions = (m, tokens) => withOptions = true

      m = M(input, context)
        .match('telegram received ')
        .matchString(setCommand)
        .match(' with arguments', optional: true, setOptions)
        

      if m.hadMatch()
        match = m.getFullMatch()
        nextInput = m.getRemainingInput()

      if match?
        cassert typeof recCommand is "string"
        env.logger.debug "Rule matched: '", match, "' and passed to Predicate handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          predicateHandler: new TelegramPredicateHandler(@framework, recCommand, recArgs, withOptions)
        }
      else return null

  class TelegramPredicateHandler extends env.predicates.PredicateHandler
    constructor: (framework, @command, @args, @options) ->
      @ruleId = null
      super()

    setup: ->
      #TelegramPlugin.registerCmd this
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> @command
    getArgs: -> @args
    getOptions: -> @options
    getRuleId: -> @ruleId
    
    setRuleId: (id) -> 
      @ruleId = id
      
    destroy: ->
      TelegramPlugin.deregisterCmd this
      super()
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
      
    parseAction: (input, context) =>
      type = null
      message = null
      match = null
      reply = false
      
      # Action arguments: send [<text(default) | video | audio | photo> telegram to <sender | recipient1 ... recipientN> <"message" | "path" | "url">]
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
          all.push 'sender ' # Add sender alias for the user having sent the predicate triggering the action
          while more and i < all.length
            more = false if @m1.getRemainingInput().charAt(0) is '"' or null
             
            @m1.match(all, (@m1, recipient) =>
              recipient = recipient.trim()
              message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.name is recipient and obj.enabled
              reply = true if recipient is 'sender'
            )
            i += 1
        )
      @m1.matchStringWithVars( (@m1, expr) =>
        message.addContent(new ContentFactory(type, expr))
        match = @m1.getFullMatch()
      )
      
      if match?
        if message.recipients.length < 1 and not reply
          message.addRecipient(new Recipient(obj)) for obj in @config.recipients when obj.enabled
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @config, @, message, reply)
        }
        
      else    
        return null
        
  class TelegramActionHandler extends env.actions.ActionHandler
  
    constructor: (@framework, @config, @actionProvider, @message, @reply) ->
      @listeners = []
      @trigger = null
      @ruleId = null
      
      if @reply
        for id, device of @framework.deviceManager.devices when device instanceof TelegramReceiverDevice
          @listeners.push device.listener
          @_addListener(device.listener)
        @framework.on 'changedTelegramReceiverDevice', @_changeListener
          
    _onReceivedRulePredicate: (cmd, sender, id) =>
      if cmd is @trigger
        env.logger.debug 'TelegramActionHandler::_onReceivedRulePredicate event => ruleId: ' + @ruleId + ', reply: ' + @reply + ', cmd: ' + cmd + ', trigger: ' + @trigger + ', sender: ' + sender.getName()
        @message.recipients = []
        @message.recipients.push sender
        env.logger.info @ruleId + ': Resolving [sender] to: ' + sender.getName()
      
    _addListener: (listener) -> listener.on 'receivedRulePredicate', @_onReceivedRulePredicate
    
    _changeListener: (listener) ->
      @_removeListener(listener)
      @_addListener(listener)
    
    _removeListener: (listener) -> listener.removeListener 'receivedRulePredicate', @_onReceivedRulePredicate
    
    mapCommand: (id, trigger) ->
      @setRuleId(id)
      @setTrigger(trigger)
      
    setTrigger: (trigger) -> @trigger = trigger
    setRuleId: (id) -> @ruleId = id
    
    executeAction: (simulate) =>
      if simulate
        return __("would send telegram \"%s\"", @message.content.get())
      else
        env.logger.debug 'TelegramActionHandler::executeAction: => ruleId: ' + @ruleId + ', reply: ' + @reply + ', trigger: ' + @trigger + ', recipients: ' + @message.recipients + ', sending message'
        return Promise.reject '"send telegram to sender ..." action syntax can only be used in combination with "when telegram ... received" as rule predicate!' if @reply and not @trigger?
        client = new BotClient({token: TelegramPlugin.getToken()})
        return client.sendMessage(@message, true)
        
    destroy: () ->
      @framework.removeListener 'changedTelegramReceiverDevice', @_changeListener
      @listeners.map( (listener) =>
        @_removeListener(listener)
      )
      
  class TelegramReloadActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
      
    parseAction: (input, context) =>
      selectorDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class is 'TelegramReceiverDevice'
      ).value()
      
      device = null
      match = null

      
      # Try to match the input string with: reload ->
      m = M(input, context).match(['reload '])
      m.matchDevice( selectorDevices, (m, d) ->
        # Already had a match with another device?
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return
        device = d
        match = m.getFullMatch()
      )
      
      if match?
        assert device?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramReloadActionHandler(@framework, device)
        }
      else
        return null
        
  class TelegramReloadActionHandler extends env.actions.ActionHandler
  
    constructor: (@framework, @device) ->
      @_base = commons.base @
      super()

    setup: ->
      @dependOnDevice(@device)
      super()

    executeAction: (simulate) =>
      @reloadDevice(@device, simulate)

    reloadDevice: (device, simulate) =>
      if simulate
        return Promise.resolve(__("Would reload device: '%s'"), device.name)
      else
        device.reloadListener()
        return Promise.resolve(__("%s was reloaded", device.name))
      
  class TelegramReceiverDevice extends env.devices.SwitchActuator
        
    constructor: (@config, lastState) ->
      @id = @config.id
      @name = @config.name
      @_state = lastState?.state?.value or @config.stateStartup
      
      super()

      @listener = new Listener(@id)

      TelegramPlugin.on('addedTelegramPredicate', (rule) =>
        rule.predicates.map( (predicate) =>
          if predicate.handler instanceof TelegramPredicateHandler
            predicate.handler.setRuleId(rule.id)
            @listener.requestAdd(predicate.handler) if rule.active
            rule.actions.map( (action) =>
              if action.handler instanceof TelegramActionHandler
                action.handler.mapCommand(rule.id, predicate.handler.command)
                env.logger.debug 'TelegramReceiverDevice::constructor => Mapping Telegram predicate command: ' + predicate.handler.command + ' to TelegramActionHandler for rule.id: ' + rule.id
                return
            )
        )
        
      )
      
      TelegramPlugin.on('cmdDeregistered', (cmd) =>
        @listener.requestDelete(cmd)
      )
      
      @startListener() if @_state
    
    reloadListener: () =>
      @stopListener()
      @startListener()
      
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
  
  class Listener extends events.EventEmitter
  
    constructor: (id) ->
      @id  = id
      @client = null
      @authenticated = []
      @requests = [{
          command: "help"
          type: "base"
          action: -> return null
          protected: false
          response: (msg) =>
            text = "Default commands:\n"
            for req in @requests
              if req.type is "base"
                text += "\t" + req.command
                if req.command is "get device"
                  text += " device_name | device_id"
                text += "\n"
            text += "\nRule commands: \n"
            for req in @requests
              if req.type is "rule"
                text += "\t" + req.command + "\n"
            text += "\nAny command following rule action syntax\nExamples:\n\t'turn on device'\n\t'set temp of device to 21'\n"
            return text
        },
        {
          command: "execute",
          type: "restricted"
          action: => 
            env.logger.warn "command 'execute' received; This is not allowed for security reasons" # It's a trap !!
            return null
          protected: false
          response: (msg) ->
            text = "command 'execute' received; This is not allowed for security reasons"
            return text
        },
        {
          command: "list devices"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) ->
            devices = TelegramPlugin.getDevices()
            text = 'Devices :\n'
            for dev in devices
              text += '\tName: ' + dev.name + "\nID: " + dev.id + "\n\n"
            return text
        },
        {
          command: "get device"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) => 
            obj = msg.split("device", 4)
            devices = TelegramPlugin.getDevices()
            for dev in devices
              if ( obj[1].substring(1) == dev.id.toLowerCase() ) or ( obj[1].substring(1) == dev.name.toLowerCase() )
                text = 'Name: ' + dev.name + "\nID: " + dev.id + "\nType: " +  dev.constructor.name + "\n"
                for name of dev.attributes
                  text += '\t\t' + name.charAt(0).toUpperCase() + name.slice(1) + ": " + dev.getLastAttributeValue(name) + "\n"
                return text
            return "device not found"
        }]
      #@queue = []
      
      
    start: (@client) =>
      env.logger.info "Starting Telegram listener"
      @client.connect()
      @enablecommands()
    
    stop: (@client) =>
      env.logger.info "Stopping Telegram listener"
      @authenticated = []
      @client.stop()
      
    enablecommands: () =>
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
        env.logger.debug "command '", msg.text, "' received, processing..."
        instance = TelegramPlugin.getDeviceById(@id)
        sender = TelegramPlugin.getSender(msg.from.id.toString())
        
        # auth logic
        if !sender.isAdmin() # Lord Vader force-chokes you !!
          env.logger.warn "auth_denied", sender.getName() + " is not authorized. Terminating session."
          return
        
        date = new Date()
        client = new BotClient({token: TelegramPlugin.getToken()})
        response = new MessageFactory("text")
        response.addRecipient(sender)
        
        if instance.config.secret is msg.text or instance.config.disable2FA # Face Vader you must!
          @authenticated.push {id: sender.getId(), time: date.getTime()}
          response.addContent(new ContentFactory("text", "Passcode correct, timeout set to " + instance.config.auth_timeout + " minutes. You can now issue commands"))
          client.sendMessage(response) unless instance.config.disable2FA
          env.logger.info sender.getName() + " successfully authenticated"
          return unless instance.config.disable2FA
        
        for auth in @authenticated
          if auth.id is sender.getId()
            if auth.time < (date.getTime()-(instance.config.auth_timeout*60000)) # You were carbon frozen for too long, Solo! Solo! Too Nakma Noya Solo!
              sender.setAuthenticated(false)
            else
              sender.setAuthenticated(true)
        
        
        message = msg.text.toLowerCase()
        match = false
        # message logic
        if sender.isAuthenticated()  # May the force be with you
          env.logger.info "command '" + message + "' received from " + sender.getName()
          
          for req in @requests
            if (req.type is "rule" or req.type is "base") and req.command.toLowerCase() is message.slice(0, req.command.length)
              if req.type is "rule"
                if req.options
                  [command, args...] = message.split(' ')
                  rule = req.getRule()
                  ruleString = rule.string
                  vars = ruleString.match(/\\\$\w+/g) or []
                  
                  if vars.length <= args.length
                    for i in [0..vars.length]
                      ruleString = ruleString.replace(vars[i], args[i])
                    
                    TelegramPlugin.updateRuleByString(rule.id, {ruleString}).then( () =>
                      @emit('receivedRulePredicate', req.command, sender, req.id)
                    )
                    req.action()
                    TelegramPlugin.updateRuleByString(rule.id, {ruleString: rule.string})
                  else
                    response.addContent(new ContentFactory("text", "'" + rule.id + "' action takes a minimum of " + vars.length + " arguments."))
                    client.sendMessage(response)
                else
                  @emit('receivedRulePredicate', req.command, sender, req.id)
                  req.action()

              if req.type is "base" or instance.config.confirmRuleTrigger
                response.addContent(new ContentFactory("text", req.response(message)))
                client.sendMessage(response)
              match = true
              break
          
          if !match
            for act in TelegramPlugin.getActionProviders()
              context = createDummyParseContext()
              han = act.parseAction(message, context) # test if message is a valid action, e.g. "turn on switch-room1"
              if han?
                han.actionHandler.executeAction()
                if instance.config.confirmDeviceAction
                  response.addContent(new ContentFactory("text", "command '" + message + "' executed"))
                  client.sendMessage(response)
                match = true
                break

          if !match
            response.addContent(new ContentFactory("text", "'" + message + "' is not a valid message"))
            client.sendMessage(response)
            return
          return
        
        else # Vader face you must
          response.addContent(new ContentFactory("text", "Please provide the passcode first and reissue your command after"))
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
          ruleId: req.getRuleId()
          getRule: () => return TelegramPlugin.getRuleById(obj.ruleId)
          command: req.getCommand()
          args: req.getArgs()
          options: req.getOptions()
          action: () => req.emit('change', 'event')
          protected: true
          type: "rule"
          sender: null
          response: () => return "Rule condition '" + obj.request + "' triggered by " + obj.sender.getName()
        }
        @requests.push obj
        env.logger.debug "Listener enabled ruleset command: '", obj.command, "'"
          
    requestChange: (req) =>
      @requestDelete(req)
      @requestAdd(req)
      
    requestDelete: (req) =>
      i = -1 # additional iterator needed as array.indexOf(elem) does not work on array of objects
      for obj in @requests
        i++
        if obj.command is req.getCommand()
          @requests.splice(i,1)
          env.logger.debug "Listener disabled ruleset command: '", req.getCommand(), "' "
          break

      
    requestIsRegistered: (req) =>
      registered = false
      for obj in @requests
        if obj.command is req.getCommand()
          registered = true
          break
      return registered
    
  class BotClient
    
    constructor: (options) ->
      options.buildInPlugins = []
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
      parts = message.match(/[\s\S]{1,4096}/g)
      return parts.map( (part) => @processResult(@client.sendMessage(recipient.getId(), part, {parseMode: 'HTML'}), part, recipient.getName(), log) )
      
  class VideoMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "VideoMessage"
      
    send: (@client, log) =>
      @content.get().then( (file) =>
        return @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), file, r.getName(), log))
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, "Unable to send Video file"
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
          @base.rejectWithErrorString Promise.reject, "Unable to send Audio file"
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
            @base.rejectWithErrorString Promise.reject, "Unable to send Image file"
        )
  
  class DocumentMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "DocumentMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
            return @recipients.map( (r) => @processResult(@client.sendDocument(r.getId(), file), r.getName(), log))
        ).catch( (err) =>
            @base.rejectWithErrorString Promise.reject, "Unable to send file"
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
      super().then( (message) =>
        if message.length > 4096
          @base.rejectWithErrorString Promise.reject, __("Message exceeds 4096 characters.")
        else
          Promise.resolve message
      )
      
  class MediaContent extends Content
    constructor: (input) ->
      super(input)
      
      @base = commons.base @, "MediaContent"
      
    get: () ->
      super()
        .then( (file) =>
          max_size = 50
          MB = Math.pow(1024,2)
          
          stats = fs.statSync(file)
          if stats.isFile()
            if stats.size < max_size*MB
              Promise.resolve file
            else
              @base.rejectWithErrorString Promise.reject, __("filesize of \"%s\" is too large (%s MB). Max. allowed size is %s MB", file, stats.size/MB, max_size)
          else
            if stats.isDirectory()
              error = __("\"%s\" is a directory", file)
            else
              err = __("\"%s\" does not exist or is a *nix device", file)
            @base.rejectWithErrorString Promise.reject, error
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
      doc: DocumentMessage
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
      doc: MediaContent
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
      
  module.exports.TelegramActionHandler = TelegramActionHandler
  module.exports.TelegramReloadActionHandler = TelegramReloadActionHandler
  TelegramPlugin = new Telegram()
  return TelegramPlugin