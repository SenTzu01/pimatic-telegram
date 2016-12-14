pimatic-Telegram
=======================


Plugin to provide a new rule action: send telegram "message"
You will need the following:
- A Telegram client (Available for various mobile platforms, as well as webbased (www.telegram.org)
- A Telegram bot
- Obtain your chat ID

Obtain a Telegram client
=========================
- Go to the Apple store or Android Play store to install the client on your mobile and follow instructions

Creating a Telegram Bot
=========================
- With your Telegram client start a conversation with @BotFather
- Send a message: /newbot
- Follow the on-screen instructions
- When choosing a name for your bot, ensure the name ends in "bot", e.g. MyAwesomePimaticBot
- After completing the required steps, BotFather will provide a token (similar to this: 784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL)
- Make sure you copy this token, and keep it secret !

Obtain your chatID
========================
- With your Telegram client start a conversation with your bot (@MyAswesomePimaticBot)
- send a message, doesn't matter what the content is
- in your browser, type: https://api.telegram.org/bot784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL/getUpdates (replace the string after bot with your own token)
- in your browser you will see a JSON response similar to the below:
{"ok":true,"result":[{"update_id":123456789,
"message":{"message_id":1,"from":{"id":<this is the number you need!>,"first_name":"fname","username":"uname"},"chat":{"id":123456789,"first_name":"fname","username":"uname","type":"private"},"date":1481753058,"text":"Hello World!"}}]}
- Look for the number after "id", and save it.

Install the plugin
=======================
- Add pimatic-telegram to your pimatic config.json
- restart Pimatic
- in the plugin config of Pimatic-Telegram, enter the apiToken and ChatID in the appropriate fields.
- now you can use the action: send telegram "message" in rules to send messages to your Telegram app !



