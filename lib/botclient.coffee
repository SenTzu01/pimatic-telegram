module.exports = (env) ->
  
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require('telebot')
  Promise = env.require 'bluebird'
  
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
            Promise.resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.rejectWithErrorString Promise.reject, "Message was NOT sent to all recipients"
          )
        ).catch( (err) =>
          @base.error err
        )
      )
      
  return BotClient