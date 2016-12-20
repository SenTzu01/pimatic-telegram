module.exports = {
  title: "Telegram config"
  type: "object"
  properties:
    host:
      description: "API Server address"
      type: "string"
      default: "api.telegram.org"
    apiToken:
      description: "API token for your Bot (Obtained via BotFather)"
      type: "string"
      default: "123456789:ABC1AaBcd12AbBCD1BcCaB012CCCCClAbcA"
    userChatId:
      description: "ChatID/UserID of the recipient of messages"
      type: "string"
      default: "123456789"
    recipients:
     description: "Additional Telegram recipients"
     type: "array"
     default: []
     items:
       description: "ChatID/UserID - no longer used, copy to recipients below!"
       type: "object"
       properties:
         name:
           description: "Recipient Name"
           type: "string"
         userChatId:
           description: "ChatID/UserID of the telegram recipient"
           type: "string"
         enabled:
           description: "Enable / Disable recipient"
           type: "boolean"
           default: true
}