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
      
  plugin = new Telegram()
  
  class TelegramActionProvider extends env.actions.ActionProvider

    constructor: (@framework, @config) ->
    parseAction: (input, context) =>
    
      messageTokens = null
      match = null
      @allRecipients = []
      #@msgRecipients = []
      @more = true
            
      @payload = {
        type: "text"    # content type, e.g. video, photo, audio, text
        recipients: []  # array of intented recipients coming from rules
      }
      
      @m = M(input, context).match('send ')
      @m.match((["text ", "video ", "photo "], optional: yes (m, content) => # add content type, eg video, photo, text, if none provided default to text
        @payload.type = content if content isnt null
      )
      @m.match('telegram ')
      @allRecipients.push (recipient.name + " ") for recipient in @config.recipients
      i = 0
      while @more and i < @allRecipients.length # var i needed to avoid lockup while editing existing rules, Pimatic bug?
        next = if @m.getRemainingInput() isnt null then @m.getRemainingInput().charAt(0) else null
        @more = false if next is '"' or null
        
        @m.match(@allRecipients, (@m, r) => #get the recipients names
          recipient = r.trim()
          @payload.recipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient objects 
        )
        i += 1
      
      @m.matchStringWithVars( (@m, message) => #get the message content
        messageTokens = message
        match = @m.getFullMatch()
      )
      
      if match?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @payload, messageTokens, @config)
        }
      else
      
        return null

  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @payload, @messageTokens, @config) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @msgRecipients = @config.recipients if @payload.recipients.length < 1
    
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
      @framework.variableManager.evaluateStringExpression(@messageTokens).then( (message) =>
        if simulate
          return __("would send telegram \"%s\"", message)
        else      
          
          return new Promise((resolve, reject) =>
            results = (@sendMessage(message, recipient) for recipient in @msgRecipients)
            Promise.some(results, results.length).then( (result) =>
              resolve "Message sent to all recipients"
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          )
          
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
    
   
  return plugin