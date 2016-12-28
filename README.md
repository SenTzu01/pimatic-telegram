pimatic-Telegram
=======================

Plugin to provide a new rule action: send telegram
This plugin will allow you to define Telegram recipients in the Plugin config, and send rule based messages to the Telegram messaging client, which is freely available for a variety of platforms, such as mobiles, tablets and browsers. This service is free of charge!

After installation the following action will be made available in Pimatic:

*send telegram [text | video | audio | photo] [1stRecipient ... nthRecipient] <"text with $variables"  | "/local/path/with/$variables/to/file">

Specifying recipients is optional, if you do not provide recipients, a message will be sent to all defined recipients
Specifiying a message type is optional, when not specifying a type a text message is assumed


Practical examples:
*'send telegram KingOfMyCastle "ALERT! Pimatic detected movement in room: $room while nobody is home! You may want to check if someone is unexpectely making you a cup of tea"'

*'send video telegram to KingOfMyCastle QueenofMyCastle "/home/pi/front_door_camera.mp4"'

Features:
========================
- Send text, audio, video or photo messages to your (mobile) device equipped with the Telegram messaging client
- Messages may be of types: text, video, audio, or photo 
- Define multiple recipients in your Pimatic configuration via the user interface or config.json
- Enable / disable existing recipients
- Messages can be sent to one, more, or all defined recipients
- Messages and file paths may contain Pimatic variables

Known issues:
========================
- Rules according to the previous format (send telegram [recipient1 ...] "message") are currently supported. However it is strongly encouraged to upgrade your rules to the new format indicating the message type (e.g. send text telegram "message"), as support for old syntax may be removed in future versions.

Requirements
========================
- A Telegram client (Available for various mobile platforms, as well as webbased (www.telegram.org)
- A Telegram bot
- Obtain chatID's for all Telegram recipiets you would like to receive messages
- Allowed file formats depend on Telegram supported formats, .mp3 (audio), .mp4, .avi (video), .jpg and .png (photo) have been validated

Installation and Configuration:
========================
Please follow these steps to install and configure a working environment:

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
Please check the following first, as all similar issues have been solved so far by taking the below steps:

*I have installed Pimatic-Telegram, but no messages are sent, and no errors are logged. Whats wrong?

- Has the plugin been activated? Check in the section "Install the Plugin"
- Have you activated the intended recipient? Or has the enabled check box accidentally not been checked?
- Restart Pimatic, this is often forgotten after the installation and or configuration. 

If you took these troubleshooting steps, you have probably rebooted Pimatic twice, once after installation, and once after configuration changes