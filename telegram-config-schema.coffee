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
}