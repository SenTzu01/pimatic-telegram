module.exports =

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