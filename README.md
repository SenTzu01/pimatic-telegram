pimatic-Telegram
=======================

Plugin to provide a new rule action: send telegram
This plugin will allow you to define Telegram recipients in the Plugin config, and send rule based messages to the Telegram messaging client, which is freely available for a variety of platforms, such as mobiles, tablets and browsers. This service is free of charge!

After installation the following action will be made available in Pimatic:

*send telegram [recipient1 recipient 2 recipient3 ...] "message with $variables"

Naming recipients is optional, if you do not provide recipients, a message will be sent to all defined recipients

Real life Example:
*'send telegram KingOfMyCastle "Telegram detected movement in room: $room while nobody is home! You may want to check if someone is unexpectely making you a cup of tea"'

Requirements
========================
You will need the following:
- A Telegram client (Available for various mobile platforms, as well as webbased (www.telegram.org)
- A Telegram bot
- Obtain chatID's for all Telegram recipiets you would like to receive messages

Installation and Configuration:
========================


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
- With your Telegram client start a conversation with your bot (@MyAwesomePimaticBot)
- send a message, doesn't matter what the content is
- in your browser, type: https://api.telegram.org/bot784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL/getUpdates (replace the string after bot with your own token)
- in your browser you will see a JSON response similar to the below:
{"ok":true,"result":[{"update_id":123456789,
"message":{"message_id":1,"from":{"id":<this is the number you need!>,"first_name":"fname","username":"uname"},"chat":{"id":123456789,"first_name":"fname","username":"uname","type":"private"},"date":1481753058,"text":"Hello World!"}}]}
- Look for the number after "id", and save it.

Install the plugin
=======================
- Add pimatic-telegram to your pimatic config.json
- Check if the plugin has been activated. If not activate it
- Restart Pimatic

Configuration
=======================
In the plugin config page of Pimatic-Telegram enter the following information:
  - Enter the apiToken
  - Under recipients, click "Add" and add new recipients
   - For each recpient:
      - Enter a name friendly name (Alphanumeric)
      - Enter the corresponding ChatID in the appropriate fields
      - Check the "enabled" box, if the recipient is supposed to actually recieve messages
- Restart Pimatic
- Now you can use the action in rules to send messages to selected recipients in the Telegram app !

FAQ
======================
*I have installed Pimatic-Telegram, but no messages are sent, and no errors are logged. Whats wrong?

Please check the following first, as all similar issues have been solved so far by taking the below steps:
- Has the plugin been activated? Check in the section "Install the Plugin"
- Have you activated the intended recipient? Or has the enabled check box accidentally not been checked
- Restart Pimatic, this is often forgotten after the installation and or configuration. If you did everything right, you have rebooted Pimatic twice, once after installation, and once after configuration

*I upgraded from version 1.0.1 and now messages are no longer sent?

- A change in recipient configuration was made since 1.0.2. You will need to create recipients as outlined in the section "Configuration". The userChatId in the "main" config options is no longer used, and will be removed in a future version.
Just create a new recipient, and copy the userChatId over, restart Pimatic and Presto !
