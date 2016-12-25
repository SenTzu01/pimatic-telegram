module.exports = (env) ->

  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require 'telegram-bot-client'
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
    
    getConfig: =>
      return @config
      
  plugin = new Telegram()
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
    
    parseAction: (input, context) =>
      messageTokens = null
      match = null
      @allRecipients = []
      @more = true
      
      @message = {
        type: "text"    # content type, e.g. video, photo, audio, text
        recipients: []  # array of intented recipients coming from rules
        content: null
      }
      
      @m = M(input, context).match('send ')
      @m.match(TelegramMessage:getTypeKeys(), optional: yes, (m, content) => # add content type, eg video, photo, text, if none provided default to text
        @message.type = content if content isnt null
      )
      @m.match(['telegram', ' telegram '])
      
      @allRecipients.push (recipient.name + " ") for recipient in @config.recipients
      i = 0
      # i = 0 to @allRecipients.lenght # Better performance with inner caching of i
      while @more and i < @allRecipients.length # var i needed to avoid lockup while editing existing rules, Pimatic bug?
        next = if @m.getRemainingInput() isnt null then @m.getRemainingInput().charAt(0) else null
        @more = false if next is '"' or null
        
        @m.match(@allRecipients, (@m, r) => #get the recipients names
          recipient = r.trim()
          @payload.recipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient objects 
        )
        i += 1
      
      @m.matchStringWithVars( (@m, message) => #get the message content
        @message.content = message
        match = @m.getFullMatch()
      )
      
      if match?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @config, @message)
        }
      else    
        return null
  
  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @message, @config) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @recipients = @config.recipients if @message.recipients.length < 1
    
    # #######################
    #
    # ---- BEGIN OLD CODE ---
    
    sendMessage: (message, recipient) =>
      client = new TelegramBotClient(@apiToken)
      if recipient.enabled
        client.sendMessage(recipient.userChatId, message).promise().then ((response) =>
          env.logger.info __("Telegram \"%s\" to \"%s\" successfully sent", response.result.text, recipient.name)
          return Promise.resolve
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to \"%s\" failed, reason: %s", message, recipient.name, err)
          error = new Error(message)
          return Promise.reject error
    
    executeAction: (simulate) =>
      @framework.variableManager.evaluateStringExpression(@message.content).then( (message) =>
        if simulate
          return __("would send telegram \"%s\"", message)
        else      
          
          return new Promise((resolve, reject) =>
            results = (@sendMessage(message, recipient) for recipient in @recipients)
            Promise.some(results, results.length).then( (result) =>
              resolve "Message sent to all recipients"
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          )
          
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
      #
      # ----- END OLD CODE -----
      #
      # ########################
      
      ###
      #
      # New ExecutionHandler below
      #
      ###
    executeAction2: (simulate) =>
      if simulate
        content = new Content(@framework)
        content.parse(@message.content)
        return __("would send telegram \"%s\"", content.get())
      else
        p = new Promise(resolve, reject)
        results = () =>
          for recipient in @recipients
            do (recipient) ->
              c = new Content(content)
              r = new Recipient(recipient)
              telegram = TelegramMessage::getinstanceOf(type)
              return telegram.send(r, c)
        
        p.some(results, results.length).then( (result) =>
          resolve "Message sent to all recipients"
        ).catch(Promise.AggregateError, (err) =>
          @base.error "Message was NOT sent to all recipients"
        )
        return p
    
  
  ###
  # TelegramMessage SuperClass
  #
  # .send(method: Telegram-bot-client.send) => (Promise.reject, Promise.resolve)
  #
  ###
  class TelegramMessage
    
    constructor: () ->
      @content = null
      @recipient = null
      @client = new TelegramBotClient(@apiToken)
      @classes = {
        text: TextMessage
        video: VideoMessage
      }
      
    getInstanceOf(type) =>
        return new @classes.type
        
    getTypeKeys() =>
      return @classes.keys()
    
    send: (method, recipient, message) =>
      if recipient.isEnabled()
        method(@recipient, @message).promise().then ((response) =>
          env.logger.info __("Telegram \"%s\" to \"%s\" successfully sent", response.result.text, recipient.name)
          return Promise.resolve
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to \"%s\" failed, reason: %s", message, recipient.name, err)
          error = new Error(message)
          return Promise.reject error
  
  ###
  # TextMessage Class
  #
  # .send (object: recipient, object: message) => (Promise.reject, Promise.resolve)
  #
  ####
  class TextMessage extends TelegramMessage
    
    constructor: (@recipient = null, @message = null) ->
      
    send: (recipient, message) =>
      @content = message.
      @recipient = recipient.getId()
      method: @client.sendMessage
      
      return super(method)
      
  ###
  # VideoMessage Class
  #  
  # .send (object: recipient, object: path)  => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends TelegramMessage
    
    constructor: () ->
    
    send: (recipient, path) =>
      return super(@client.sendVideo(recipient.userChatId, path))
  
  ###
  #  Recipient Class
  #
  # .prototype(name: string, id: string, enabled: bool)
  # .getId() => (id:string)
  # .getName() => (name:string)
  # .isEnabled() => (enabled: bool)
  #
  ###
  class Recipient
    
    constructor: (name, id, enabled) ->
      @name = name
      @id = id
      @enabled = enabled
      
      getId: () =>
        return @id
      
      getName: () =>
        return @name
        
      isEnabled: () =>
        return @enabled
    
  class Content
    
    constructor: (@framework) ->
      @content = null
    
    get: () =>
      return @content
      
    parse: (content) ->
      @framework.variableManager.evaluateStringExpression(content).then( (message) =>
        @content = message
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
      
  return plugin