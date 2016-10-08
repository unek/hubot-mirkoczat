{Adapter, TextMessage, EnterMessage, LeaveMessage, TopicMessage, User} = require 'hubot'

# pheonix websockets
phoenix = require 'phoenix-js'
WebSocket = require('websocket').w3cwebsocket

# actual adapter
class MirkoczatBot extends Adapter
    constructor: (robot) ->
        @robot = robot
        super robot

    run: ->
        self = @

        # startup options
        options =
            channel: process.env.HUBOT_MIRKOCZAT_CHANNEL
            token: process.env.HUBOT_MIRKOCZAT_TOKEN
            unflood: process.env.HUBOT_MIRKOCZAT_UNFLOOD
            usessl: process.env.HUBOT_MIRKOCZAT_USESSL?

        if not options.channel
            throw new Error 'HUBOT_MIRKOCZAT_CHANNEL env variable is not set.'
        if not options.token
            throw new Error 'HUBOT_MIRKOCZAT_TOKEN env variable is not set.'

        # flood protection
        if options.unflood
            queue = []
            send = @send

            self.send = ->
                queue.push arguments

            dequeue = ->
                args = queue.shift()
                if args
                    send.apply self, args

            setInterval dequeue, options.unflood
            dequeue()

        # connect to websocket
        # only use websocket, polling uses xmlhttprequest, not available for us
        @socket = new phoenix.Socket (options.usessl ? 'wss' : 'ws') + '://mirkoczat.pl/socket', 
            transport: WebSocket
            params:
                tag: options.channel
                token: options.token

        reconnect = (err) ->
            self.socket.connect()

            # open the channel
            if not err
                self.chan = self.socket.channel 'rooms:' + options.channel, {}
            # and join it
            self.chan.join()

        # do actually connect
        reconnect()

        # handle disconnects
        @socket.onClose reconnect

        # and errors
        @socket.onError reconnect

        # user avatars, nicknames and shit
        @authed = false
        @chan.on 'info:user', (msg) ->
            # first info:user sent is us, so save the login and emit 'connected'
            if not self.authed
                self.robot.name = msg.login
                self.authed = true

                self.emit 'connected'

        # topic messages
        @topic = null
        @chan.on 'info:room', (msg) ->
            if msg.topic is not self.topic
                self.topic = msg.topic
                message = new TopicMessage null, msg.topic
                self.receive message

        # enter messages
        @chan.on 'info:enter', (msg) ->
            user = self.robot.brain.userForName(msg.user) or new User(msg.user)
            user.room = options.channel
            self.receive new EnterMessage user

        # leave messages
        @chan.on 'info:leave', (msg) ->
            user = self.robot.brain.userForName(msg.user) or new User(msg.user)
            user.room = options.channel
            self.receive new LeaveMessage user

        # text messages
        @chan.on 'msg:send', (msg) ->
            # ignore own messages
            if msg.user is self.robot.name
                return
    
            user = self.robot.brain.userForName(msg.user) or new User(msg.user)
            user.room = options.channel
            message = new TextMessage user, msg.body, msg.uid
            self.receive message


    send: (envelope, strings...) ->
        for str in strings
            @chan.push 'msg:send', 
                body: str

    reply: (envelope, strings...) ->
        for str in strings
            @send envelope, "@#{envelope.user.name}: #{str}"


    emote: (user, strings...) ->
        @send user, strings.map((str) -> "/me #{str}")...


exports.use = (robot) ->
    new MirkoczatBot robot
