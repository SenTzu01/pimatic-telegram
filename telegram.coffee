module.exports = (env) ->

  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require 'telegram-bot-client'
  M = env.matcher
    
  class Telegram extends env.plugins.Plugin
 
    init: (app, @framework, @config) =>
      @framework.ruleManager.addActionProvider(new TelegramActionProvider(@framework, @config))

  plugin = new Telegram()
  
  class TelegramActionProvider extends env.actions.ActionProvider

    constructor: (@framework, @config) ->
    parseAction: (input, context) =>
    
      messageTokens = null
      match = null
      @allRecipients = []
      @msgRecipients = []
      @more = true
      
      @m = M(input, context).match('send telegram ')
      
      @allRecipients.push (recipient.name + " ") for recipient in @config.recipients
      i = 0
      while @more and i < @allRecipients.length # i needed to avoid lockup while editing existing rules, Pimatic bug?
        next = if @m.getRemainingInput() isnt null then @m.getRemainingInput().charAt(0) else null
        @more = false if next is '"' or null
        
        @m.match(@allRecipients, (@m, r) => #get the recipients names
          recipient = r.trim()
          @msgRecipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient objects 
        )
        i += 1
      
      @m.matchStringWithVars( (@m, message) => #get the message content
        messageTokens = message
        match = @m.getFullMatch()
      )
         
      #env.logger.info "msgRecipients", @msgRecipients
      
      
      if match?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @msgRecipients, messageTokens, @config)
        }
      else
      
        return null

  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @msgRecipients, @messageTokens, @config) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @msgRecipients = @config.recipients if @msgRecipients.length < 1
        
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